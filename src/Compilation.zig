//! Compiles a single source.

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Writer = std.Io.Writer;

const Ast = @import("Ast.zig");
const TokenIndex = Ast.TokenIndex;
const Proto = @import("Proto.zig");
const report = @import("report.zig");
const Source = @import("Source.zig");
const Tokenizer = @import("tokenizer.zig").Tokenizer;
const Vm = @import("Vm.zig");
const debug = @import("debug.zig");

pub const Error = struct {
    tag: Tag,
    location: Location,

    pub const Location = union(enum) {
        node: Ast.Node.Index,
        token: TokenIndex,
    };

    pub const Tag = enum {
        invalid_assign_target,
        todo,
    };
};

const Compilation = @This();

vm: *Vm,
arena: Allocator,
tree: *const Ast,
proto_index: Proto.Index,
proto: *Proto,
errors: ArrayList(Error),

pub fn compile(vm: *Vm, source: *const Source) !?Proto.Index {
    var tree = try Ast.parse(vm.gpa, source.bytes);
    defer tree.deinit(vm.gpa);

    var arena = std.heap.ArenaAllocator.init(vm.gpa);
    defer arena.deinit();

    var comp = Compilation{
        .vm = vm,
        .arena = arena.allocator(),
        .tree = &tree,
        .proto_index = undefined,
        .proto = undefined,
        .errors = .empty,
    };

    const proto_index = if (tree.errors.len == 0) try comp.lower() else null;
    if (tree.errors.len > 0 or comp.errors.items.len > 0) {
        try comp.reportErrors(source);
        return null;
    }
    return proto_index;
}

fn addError(comp: *Compilation, tag: Error.Tag, location: Error.Location) Allocator.Error!void {
    try comp.errors.append(comp.arena, .{ .tag = tag, .location = location });
}

fn reportErrors(comp: *Compilation, source: *const Source) !void {
    const tree = comp.tree;

    var diagnostics: ArrayList(report.Diagnostic) = .empty;
    try diagnostics.ensureTotalCapacityPrecise(comp.arena, tree.errors.len + comp.errors.items.len);

    var message: Writer.Allocating = .init(comp.arena);
    for (tree.errors) |parse_error| {
        message.clearRetainingCapacity();
        tree.renderError(parse_error, &message.writer) catch return error.OutOfMemory;
        diagnostics.appendAssumeCapacity(try comp.diagnostic(tree.errorSpan(parse_error), message.written()));
    }
    for (comp.errors.items) |compile_error| {
        message.clearRetainingCapacity();
        comp.renderError(compile_error, &message.writer) catch return error.OutOfMemory;
        diagnostics.appendAssumeCapacity(try comp.diagnostic(comp.errorSpan(compile_error), message.written()));
    }
    try report.render(comp.vm.diags, source, diagnostics.items, comp.vm.report_options);
}

fn diagnostic(comp: *Compilation, span: Ast.Span, message: []const u8) Allocator.Error!report.Diagnostic {
    return .{
        .severity = .@"error",
        .span = .{ .start = span.start, .end = span.end },
        .message = try comp.arena.dupe(u8, message),
    };
}

fn errorSpan(comp: *Compilation, compile_error: Error) Ast.Span {
    return switch (compile_error.location) {
        .node => |node| comp.tree.nodeToSpan(node),
        .token => |token| comp.tree.tokenToSpan(token),
    };
}

fn renderError(comp: *Compilation, compile_error: Error, writer: *Writer) Writer.Error!void {
    _ = comp;
    switch (compile_error.tag) {
        .invalid_assign_target => try writer.writeAll("invalid assignment target"),
        .todo => try writer.writeAll("not implemented yet"),
    }
}

fn lower(comp: *Compilation) !Proto.Index {
    const proto_index = try comp.vm.addProto();
    comp.setCurrentProto(proto_index);

    const statements = comp.tree.nodeData(.root).extra_range;
    for (comp.tree.extraDataSlice(statements, Ast.Node.Index)) |stmt| {
        // std.debug.print("index: {d}, tag: {s}\n", .{ index, @tagName(comp.tree.nodeTag(index)) });
        try comp.lowerStmt(stmt);
    }
    try comp.proto.write(comp.vm.gpa, .push_nil, 0);
    try comp.proto.write(comp.vm.gpa, .ret, 0);

    return proto_index;
}

/// Stmt <- Block
///       / ImportDecl
///       / FnDecl
///       / ClassDecl
///       / ReturnStmt
///       / BreakStmt
///       / ContinueStmt
///       / IfStmt
///       / ForStmt
///       / SimpleStmt
fn lowerStmt(comp: *Compilation, node: Ast.Node.Index) !void {
    switch (comp.tree.nodeTag(node)) {
        .block, .block_semicolon => {
            const statements = comp.tree.nodeData(node).extra_range;
            for (comp.tree.extraDataSlice(statements, Ast.Node.Index)) |stmt| {
                try comp.lowerStmt(stmt);
            }
        },
        .block_two, .block_two_semicolon => {
            const stmt_a, const stmt_b = comp.tree.nodeData(node).opt_node_and_opt_node;
            if (stmt_a.unwrap()) |a| {
                try comp.lowerStmt(a);
                if (stmt_b.unwrap()) |b| try comp.lowerStmt(b);
            }
        },
        else => try comp.lowerSimpleStmt(node),
    }
}

/// SimpleStmt <- InlineSimpleStmt stmt_terminator
/// InlineSimpleStmt
///     <- VarDecl
///      / AssignStmt
///      / Expr
fn lowerSimpleStmt(comp: *Compilation, node: Ast.Node.Index) !void {
    switch (comp.tree.nodeTag(node)) {
        .var_decl => try comp.lowerDecl(node),
        .assign => try comp.lowerAssign(node),
        .assign_shl => try comp.lowerAssignOp(node, .shl),
        .assign_shr => try comp.lowerAssignOp(node, .shr),
        .assign_bit_and => try comp.lowerAssignOp(node, .bit_and),
        .assign_bit_or => try comp.lowerAssignOp(node, .bit_or),
        .assign_bit_xor => try comp.lowerAssignOp(node, .xor),
        .assign_div => try comp.lowerAssignOp(node, .div),
        .assign_sub => try comp.lowerAssignOp(node, .sub),
        .assign_sub_wrap => try comp.lowerAssignOp(node, .subwrap),
        .assign_mod => try comp.lowerAssignOp(node, .mod_rem),
        .assign_add => try comp.lowerAssignOp(node, .add),
        .assign_add_wrap => try comp.lowerAssignOp(node, .addwrap),
        .assign_mul => try comp.lowerAssignOp(node, .mul),
        .assign_mul_wrap => try comp.lowerAssignOp(node, .mulwrap),

        else => {
            try comp.lowerExpr(node);
            try comp.proto.write(comp.vm.gpa, .pop, comp.tree.nodeMainToken(node));
        },
    }
}

fn lowerDecl(comp: *Compilation, node: Ast.Node.Index) !void {
    const name, const value = comp.tree.nodeData(node).token_and_node;
    try comp.lowerExpr(value);
    const name_constant = try comp.identifierConstant(name);
    const main_token = comp.tree.nodeMainToken(node);
    const offset = comp.tree.tokenStart(main_token);
    try comp.defineVariable(name_constant, offset);
}

fn lowerAssign(comp: *Compilation, node: Ast.Node.Index) !void {
    const target, const value = comp.tree.nodeData(node).node_and_node;
    try comp.lowerExpr(value);
    switch (comp.tree.nodeTag(target)) {
        .identifier => {
            const name = comp.tree.nodeMainToken(target);
            try comp.namedVariable(name, .set);
        },
        else => try comp.addError(.invalid_assign_target, .{ .node = target }),
    }
}

fn lowerAssignOp(comp: *Compilation, node: Ast.Node.Index, op: anytype) !void {
    _ = op;
    try comp.addError(.todo, .{ .token = comp.tree.nodeMainToken(node) });
}

/// Expr <- TernaryExpr
/// TernaryExpr <- BoolOrExpr (KEYWORD_if BoolOrExpr KEYWORD_else TernaryExpr)?
/// BoolOrExpr <- BoolAndExpr (OrOp BoolAndExpr)*
/// BoolAndExpr <- CompareExpr (AndOp CompareExpr)*
/// CompareExpr <- BitwiseExpr (CompareOp BitwiseExpr)?
/// BitwiseExpr <- BitShiftExpr (BitwiseOp BitShiftExpr)*
/// BitShiftExpr <- AdditionExpr (BitShiftOp AdditionExpr)*
/// AdditionExpr <- MultiplyExpr (AdditionOp MultiplyExpr)*
/// MultiplyExpr <- PrefixExpr (MultiplyOp PrefixExpr)*
/// PrefixExpr <- PrefixOp* PostfixExpr
/// PostfixExpr <- PrimaryExpr (Call / Member / Index)*
///
/// Call <- LPAREN ExprList? COMMA? RPAREN
/// Member <- DOT IDENTIFIER
/// Index <- LBRACK Expr RBRACK
///
/// PrimaryExpr
///     <- FnExpr
///      / ClassExpr
///      / InitList
///      / GroupedExpr
///      / IDENTIFIER
///      / COLON IDENTIFIER
///      / NUMBERLITERAL
///      / STRINGLITERAL
///      / KEYWORD_true
///      / KEYWORD_false
///      / KEYWORD_nil
///      / KEYWORD_this
///      / KEYWORD_This
fn lowerExpr(comp: *Compilation, node: Ast.Node.Index) Allocator.Error!void {
    switch (comp.tree.nodeTag(node)) {
        // .shl => return comp.lowerBinaryOp(node, .shl),
        // .shr => return comp.lowerBinaryOp(node, .shr),

        .add => return comp.lowerBinaryOp(node, .add),
        // .add_wrap => return comp.lowerBinaryOp(node, .addwrap),
        // .add_sat => return comp.lowerBinaryOp(node, .add_sat),
        .sub => return comp.lowerBinaryOp(node, .sub),
        // .sub_wrap => return comp.lowerBinaryOp(node, .subwrap),
        // .sub_sat => return comp.lowerBinaryOp(node, .sub_sat),
        .mul => return comp.lowerBinaryOp(node, .mul),
        // .mul_wrap => return comp.lowerBinaryOp(node, .mulwrap),
        // .mul_sat => return comp.lowerBinaryOp(node, .mul_sat),
        .div => return comp.lowerBinaryOp(node, .div),
        // .mod => return comp.lowerBinaryOp(node, .mod_rem),
        // .shl_sat => return comp.lowerBinaryOp(node, .shl_sat),

        // .bit_and => return comp.lowerBinaryOp(node, .bit_and),
        // .bit_or => return comp.lowerBinaryOp(node, .bit_or),
        // .bit_xor => return comp.lowerBinaryOp(node, .xor),
        .bang_equal => return comp.lowerBinaryOp(node, .cmp_neq),
        .equal_equal => return comp.lowerBinaryOp(node, .cmp_eq),
        .greater_than => return comp.lowerBinaryOp(node, .cmp_gt),
        .greater_or_equal => return comp.lowerBinaryOp(node, .cmp_gte),
        .less_than => return comp.lowerBinaryOp(node, .cmp_lt),
        .less_or_equal => return comp.lowerBinaryOp(node, .cmp_lte),
        // .array_cat => return comp.lowerBinaryOp(node, .array_cat),

        // .bool_and => return comp.lowerBinaryOp(node, .bool_br_and),
        // .bool_or => return comp.lowerBinaryOp(node, .bool_br_or),

        .bool_not => return comp.lowerUnaryOp(node, .bool_not),
        // .bit_not => return comp.lowerUnaryOp(node, .bit_not),

        .negation => return comp.lowerUnaryOp(node, .negate),
        // .negation_wrap => return comp.lowerUnaryOp(node, .negate_wrap),

        .identifier => {
            const token = comp.tree.nodeMainToken(node);
            try comp.namedVariable(token, .get);
        },
        .literal_nil => {
            const token = comp.tree.nodeMainToken(node);
            try comp.proto.write(comp.vm.gpa, .push_nil, token);
        },
        .literal_true => {
            const token = comp.tree.nodeMainToken(node);
            try comp.proto.write(comp.vm.gpa, .push_true, token);
        },
        .literal_false => {
            const token = comp.tree.nodeMainToken(node);
            try comp.proto.write(comp.vm.gpa, .push_false, token);
        },
        .literal_number => {
            const token = comp.tree.nodeMainToken(node);
            const offset = comp.tree.tokenStart(token);
            const result = std.fmt.parseFloat(f64, comp.tree.tokenSlice(token)) catch |err| switch (err) {
                error.InvalidCharacter => unreachable, // validated by tokenizer
            };
            const constant_index = try comp.proto.addConstant(comp.vm.gpa, .fromNumber(result));
            try comp.proto.write(comp.vm.gpa, .push_constant, offset);
            try comp.proto.writeByte(comp.vm.gpa, constant_index, offset);
        },
        .literal_string => {
            const token = comp.tree.nodeMainToken(node);
            const offset = comp.tree.tokenStart(token);
            const data = std.zig.string_literal.parseAlloc(comp.vm.gpa, comp.tree.tokenSlice(token)) catch |err| switch (err) {
                error.InvalidLiteral => std.debug.panic("invalid string literal", .{}),
                error.OutOfMemory => return error.OutOfMemory,
            };
            const string = try comp.vm.takeString(data);
            const constant_index = try comp.proto.addConstant(comp.vm.gpa, .fromObject(string));
            try comp.proto.write(comp.vm.gpa, .push_constant, offset);
            try comp.proto.writeByte(comp.vm.gpa, constant_index, offset);
        },

        else => std.debug.panic("TODO: lower {s}", .{@tagName(comp.tree.nodeTag(node))}),
    }
}

fn lowerBinaryOp(comp: *Compilation, node: Ast.Node.Index, op: Proto.OpCode) !void {
    const lhs, const rhs = comp.tree.nodeData(node).node_and_node;
    try comp.lowerExpr(lhs);
    try comp.lowerExpr(rhs);
    const main_token = comp.tree.nodeMainToken(node);
    const offset = comp.tree.tokenStart(main_token);
    try comp.proto.write(comp.vm.gpa, op, offset);
}

fn lowerUnaryOp(comp: *Compilation, node: Ast.Node.Index, op: Proto.OpCode) !void {
    const operand = comp.tree.nodeData(node).node;
    try comp.lowerExpr(operand);
    const main_token = comp.tree.nodeMainToken(node);
    const offset = comp.tree.tokenStart(main_token);
    try comp.proto.write(comp.vm.gpa, op, offset);
}

fn identifierConstant(comp: *Compilation, token_index: TokenIndex) !u8 {
    const identifier = try comp.vm.copyString(comp.tree.tokenSlice(token_index));
    const constant_index = try comp.proto.addConstant(comp.vm.gpa, .fromObject(identifier));
    return constant_index;
}

fn namedVariable(comp: *Compilation, token_index: TokenIndex, access: enum { set, get }) !void {
    const constant_index = try comp.identifierConstant(token_index);
    const offset = comp.tree.tokenStart(token_index);
    try comp.proto.write(comp.vm.gpa, switch (access) {
        .get => .get_global,
        .set => .set_global,
    }, offset);
    try comp.proto.writeByte(comp.vm.gpa, constant_index, offset);
}

fn defineVariable(comp: *Compilation, global: u8, offset: usize) !void {
    try comp.proto.write(comp.vm.gpa, .define_global, offset);
    try comp.proto.writeByte(comp.vm.gpa, global, offset);
}

fn setCurrentProto(comp: *Compilation, index: Proto.Index) void {
    comp.proto_index = index;
    comp.proto = comp.vm.getProto(index);
}
