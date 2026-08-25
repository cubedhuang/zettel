//! Parse contains the internal state and functionality necessary to generate an Ast.

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const Ast = @import("Ast.zig");
const Node = Ast.Node;
const AstError = Ast.Error;
const TokenIndex = Ast.TokenIndex;
const OptionalTokenIndex = Ast.OptionalTokenIndex;
const ExtraIndex = Ast.ExtraIndex;
const Token = @import("tokenizer.zig").Token;

pub const Error = error{ParseError} || Allocator.Error;

const BlockContext = enum { class, not_class };

const Parse = @This();

gpa: Allocator,
source: []const u8,
tokens: Ast.TokenList.Slice,
tok_i: TokenIndex,
errors: std.ArrayList(AstError),
nodes: Ast.NodeList,
extra_data: std.ArrayList(u32),
scratch: std.ArrayList(Node.Index),
block_context: BlockContext,

fn tokenTag(p: *const Parse, token_index: TokenIndex) Token.Tag {
    return p.tokens.items(.tag)[token_index];
}

fn tokenStart(p: *const Parse, token_index: TokenIndex) Ast.ByteOffset {
    return p.tokens.items(.start)[token_index];
}

fn nodeTag(p: *const Parse, node: Node.Index) Node.Tag {
    return p.nodes.items(.tag)[@intFromEnum(node)];
}

fn nodeMainToken(p: *const Parse, node: Node.Index) TokenIndex {
    return p.nodes.items(.main_token)[@intFromEnum(node)];
}

fn nodeData(p: *const Parse, node: Node.Index) Node.Data {
    return p.nodes.items(.data)[@intFromEnum(node)];
}

fn listToSpan(p: *Parse, list: []const Node.Index) Allocator.Error!Node.SubRange {
    try p.extra_data.appendSlice(p.gpa, @ptrCast(list));
    return .{
        .start = @enumFromInt(p.extra_data.items.len - list.len),
        .end = @enumFromInt(p.extra_data.items.len),
    };
}

fn addNode(p: *Parse, elem: Ast.Node) Allocator.Error!Node.Index {
    const result: Node.Index = @enumFromInt(p.nodes.len);
    try p.nodes.append(p.gpa, elem);
    return result;
}

fn setNode(p: *Parse, i: usize, elem: Ast.Node) Node.Index {
    p.nodes.set(i, elem);
    return @enumFromInt(i);
}

fn reserveNode(p: *Parse, tag: Ast.Node.Tag) !usize {
    try p.nodes.resize(p.gpa, p.nodes.len + 1);
    p.nodes.items(.tag)[p.nodes.len - 1] = tag;
    return p.nodes.len - 1;
}

fn unreserveNode(p: *Parse, node_index: usize) void {
    if (p.nodes.len == node_index) {
        p.nodes.resize(p.gpa, p.nodes.len - 1) catch unreachable;
    } else {
        // There is zombie node left in the tree, let's make it as inoffensive as possible
        // (sadly there's no no-op node)
        p.nodes.items(.tag)[node_index] = .unreachable_literal;
        p.nodes.items(.main_token)[node_index] = p.tok_i;
    }
}

fn addExtra(p: *Parse, extra: anytype) Allocator.Error!ExtraIndex {
    const fields = std.meta.fields(@TypeOf(extra));
    try p.extra_data.ensureUnusedCapacity(p.gpa, fields.len);
    const result: ExtraIndex = @enumFromInt(p.extra_data.items.len);
    inline for (fields) |field| {
        const data: u32 = switch (field.type) {
            Node.Index,
            Node.OptionalIndex,
            OptionalTokenIndex,
            ExtraIndex,
            => @intFromEnum(@field(extra, field.name)),
            TokenIndex,
            => @field(extra, field.name),
            else => @compileError("unexpected field type"),
        };
        p.extra_data.appendAssumeCapacity(data);
    }
    return result;
}

fn warnExpected(p: *Parse, expected_token: Token.Tag) error{OutOfMemory}!void {
    @branchHint(.cold);
    try p.warnMsg(.{
        .tag = .expected_token,
        .token = p.tok_i,
        .extra = .{ .expected_tag = expected_token },
    });
}

fn warn(p: *Parse, error_tag: AstError.Tag) error{OutOfMemory}!void {
    @branchHint(.cold);
    try p.warnMsg(.{ .tag = error_tag, .token = p.tok_i });
}

fn warnMsg(p: *Parse, msg: Ast.Error) error{OutOfMemory}!void {
    @branchHint(.cold);
    switch (msg.tag) {
        .expected_semi_after_decl,
        .expected_semi_after_stmt,
        .expected_comma_after_field,
        .expected_comma_after_arg,
        .expected_comma_after_param,
        .expected_comma_after_initializer,
        .expected_comma_after_switch_prong,
        .expected_comma_after_for_operand,
        .expected_comma_after_capture,
        .expected_semi_or_else,
        .expected_token,
        .expected_block,
        .expected_block_or_assignment,
        .expected_block_or_expr,
        .expected_block_or_field,
        .expected_expr,
        .expected_expr_or_assignment,
        .expected_fn,
        .expected_inlinable,
        .expected_labelable,
        .expected_param_list,
        .expected_prefix_expr,
        .expected_primary_type_expr,
        .expected_pub_item,
        .expected_return_type,
        .expected_suffix_op,
        .expected_type_expr,
        .expected_var_decl,
        .expected_var_decl_or_fn,
        .expected_loop_payload,
        .expected_container,
        => if (msg.token != 0 and !p.tokensOnSameLine(msg.token - 1, msg.token)) {
            var copy = msg;
            copy.token_is_prev = true;
            copy.token -= 1;
            return p.errors.append(p.gpa, copy);
        },
        else => {},
    }
    try p.errors.append(p.gpa, msg);
}

fn fail(p: *Parse, tag: Ast.Error.Tag) error{ ParseError, OutOfMemory } {
    @branchHint(.cold);
    return p.failMsg(.{ .tag = tag, .token = p.tok_i });
}

fn failExpected(p: *Parse, expected_token: Token.Tag) error{ ParseError, OutOfMemory } {
    @branchHint(.cold);
    return p.failMsg(.{
        .tag = .expected_token,
        .token = p.tok_i,
        .extra = .{ .expected_tag = expected_token },
    });
}

fn failMsg(p: *Parse, msg: Ast.Error) error{ ParseError, OutOfMemory } {
    @branchHint(.cold);
    try p.warnMsg(msg);
    return error.ParseError;
}

/// Root <- container_doc_comment? Stmt* EOF
pub fn parseRoot(p: *Parse) Allocator.Error!void {
    p.nodes.appendAssumeCapacity(.{
        .tag = .root,
        .main_token = 0,
        .data = undefined,
    });
    while (p.eatToken(.container_doc_comment)) |_| {}

    const scratch_top = p.scratch.items.len;
    defer p.scratch.shrinkRetainingCapacity(scratch_top);

    while (p.tokenTag(p.tok_i) != .eof) {
        const stmt = p.expectStmtRecoverable() catch break orelse break;
        try p.scratch.append(p.gpa, stmt);
    }
    if (p.tokenTag(p.tok_i) != .eof) {
        try p.warnExpected(.eof);
    }

    const items = p.scratch.items[scratch_top..];
    p.nodes.items(.data)[0] = .{ .extra_range = try p.listToSpan(items) };
}
/// If a parse error occurs, reports an error, but then finds the next statement
/// and returns that one instead. If a parse error occurs but there is no following
/// statement, returns 0.
fn expectStmtRecoverable(p: *Parse) Error!?Node.Index {
    while (true) {
        return p.expectStmt() catch |err| switch (err) {
            error.OutOfMemory => |e| return e,
            error.ParseError => {
                p.findNextStmt(); // Try to skip to the next statement.
                switch (p.tokenTag(p.tok_i)) {
                    .r_brace => return null,
                    .eof => return error.ParseError,
                    else => continue,
                }
            },
        };
    }
}

/// Attempts to find the next statement by searching for a semicolon
fn findNextStmt(p: *Parse) void {
    var level: u32 = 0;
    while (true) {
        const tok = p.nextToken();
        switch (p.tokenTag(tok)) {
            .l_brace => level += 1,
            .r_brace => {
                if (level == 0) {
                    p.tok_i -= 1;
                    return;
                }
                level -= 1;
            },
            .semicolon => {
                if (level == 0) {
                    return;
                }
            },
            .eof => {
                p.tok_i -= 1;
                return;
            },
            else => {},
        }
    }
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
///
/// ReturnStmt <- KEYWORD_return Expr? stmt_terminator
/// BreakStmt <- KEYWORD_break IDENTIFIER? stmt_terminator
/// ContinueStmt <- KEYWORD_continue IDENTIFIER? stmt_terminator
fn expectStmt(p: *Parse) !Node.Index {
    const doc_comments = try p.eatDocComments();

    const node = node: switch (p.tokenTag(p.tok_i)) {
        .l_brace => try p.expectBlock(.not_class),
        .keyword_import => @panic("TODO: ImportDecl"),
        .keyword_fn => @panic("TODO: FnDecl"),
        .keyword_class => @panic("TODO: ClassDecl"),
        .keyword_return => {
            const node = try p.addNode(.{
                .tag = .@"return",
                .main_token = p.nextToken(),
                .data = .{ .opt_node = .fromOptional(try p.parseExpr()) },
            });
            try p.expectStmtTerminator(.expected_semi_after_stmt, true);
            break :node node;
        },
        .keyword_break => {
            const node = try p.addNode(.{
                .tag = .@"break",
                .main_token = p.nextToken(),
                .data = .{ .opt_token = .fromOptional(p.eatToken(.identifier)) },
            });
            try p.expectStmtTerminator(.expected_semi_after_stmt, true);
            break :node node;
        },
        .keyword_continue => {
            const node = try p.addNode(.{
                .tag = .@"continue",
                .main_token = p.nextToken(),
                .data = .{ .opt_token = .fromOptional(p.eatToken(.identifier)) },
            });
            try p.expectStmtTerminator(.expected_semi_after_stmt, true);
            break :node node;
        },
        .keyword_if => @panic("TODO: IfStmt"),
        .keyword_for => @panic("TODO: ForStmt"),
        else => try p.expectSimpleStmt(),
    };

    if (doc_comments) |_| {
        switch (p.nodeTag(node)) {
            .fn_decl, .class_decl, .var_decl => {},
            else => try p.warn(.invalid_doc_comment),
        }
    }

    return node;
}

fn eatDocComments(p: *Parse) Allocator.Error!?TokenIndex {
    if (p.eatToken(.doc_comment)) |tok| {
        var first_line = tok;
        if (tok > 0 and tokensOnSameLine(p, tok - 1, tok)) {
            try p.warnMsg(.{
                .tag = .same_line_doc_comment,
                .token = tok,
            });
            first_line = p.eatToken(.doc_comment) orelse return null;
        }
        while (p.eatToken(.doc_comment)) |_| {}
        return first_line;
    }
    return null;
}

/// Block <- LBRACE Decl* RBRACE NEWLINE?
fn expectBlock(p: *Parse, block_context: BlockContext) !Node.Index {
    const previous_block_context = p.block_context;
    p.block_context = block_context;
    defer p.block_context = previous_block_context;

    const l_brace = try p.expectToken(.l_brace);

    const scratch_top = p.scratch.items.len;
    defer p.scratch.shrinkRetainingCapacity(scratch_top);

    while (p.tokenTag(p.tok_i) != .r_brace) {
        const stmt = try p.expectStmtRecoverable() orelse break;
        try p.scratch.append(p.gpa, stmt);
    }
    _ = try p.expectToken(.r_brace);

    const statements = p.scratch.items[scratch_top..];
    const previous = p.tokenTag(p.tok_i - 2);
    const semicolon = statements.len != 0 and (previous == .semicolon or previous == .newline);

    _ = p.eatToken(.newline);

    if (statements.len <= 2) {
        return try p.addNode(.{
            .tag = if (semicolon) .block_two_semicolon else .block_two,
            .main_token = l_brace,
            .data = .{ .opt_node_and_opt_node = .{
                if (statements.len >= 1) statements[0].toOptional() else .none,
                if (statements.len >= 2) statements[1].toOptional() else .none,
            } },
        });
    } else {
        return try p.addNode(.{
            .tag = if (semicolon) .block_semicolon else .block,
            .main_token = l_brace,
            .data = .{ .extra_range = try p.listToSpan(statements) },
        });
    }
}

/// TODO: allow expression lists; currently only one expression is allowed per side
///
/// SimpleStmt <- InlineSimpleStmt stmt_terminator
///
/// InlineSimpleStmt
///     <- VarDecl
///      / AssignStmt
///      / Expr
///
/// # later validated to be a list of identifiers
/// VarDecl <- ExprList COLON_EQUAL ExprList
///
/// # later validated to be a list of lvalues
/// AssignStmt <- ExprList AssignOp ExprList
fn expectSimpleStmt(p: *Parse) !Node.Index {
    const lhs = try p.parseExpr() orelse return p.fail(.expected_statement);

    if (p.eatToken(.colon_equal)) |colon_equal| {
        if (p.nodeTag(lhs) != .identifier) {
            try p.warn(.invalid_decl_target);
            return error.ParseError;
        }
        const rhs = try p.expectExpr();
        try p.expectStmtTerminator(.expected_semi_after_decl, true);

        return try p.addNode(.{
            .tag = .var_decl,
            .main_token = colon_equal,
            .data = .{ .token_and_node = .{ p.nodeMainToken(lhs), rhs } },
        });
    }

    const tag = assignOpNode(p.tokenTag(p.tok_i)) orelse {
        try p.expectStmtTerminator(.expected_semi_after_stmt, true);
        return lhs;
    };
    const token = p.nextToken();
    const rhs = try p.expectExpr();
    try p.expectStmtTerminator(.expected_semi_after_stmt, true);

    return try p.addNode(.{
        .tag = tag,
        .main_token = token,
        .data = .{ .node_and_node = .{ lhs, rhs } },
    });
}

fn assignOpNode(tok: Token.Tag) ?Node.Tag {
    return switch (tok) {
        .asterisk_equal => .assign_mul,
        .slash_equal => .assign_div,
        .percent_equal => .assign_mod,
        .plus_equal => .assign_add,
        .minus_equal => .assign_sub,
        .angle_bracket_angle_bracket_left_equal => .assign_shl,
        .angle_bracket_angle_bracket_left_pipe_equal => .assign_shl_sat,
        .angle_bracket_angle_bracket_right_equal => .assign_shr,
        .ampersand_equal => .assign_bit_and,
        .caret_equal => .assign_bit_xor,
        .pipe_equal => .assign_bit_or,
        .asterisk_percent_equal => .assign_mul_wrap,
        .plus_percent_equal => .assign_add_wrap,
        .minus_percent_equal => .assign_sub_wrap,
        .asterisk_pipe_equal => .assign_mul_sat,
        .plus_pipe_equal => .assign_add_sat,
        .minus_pipe_equal => .assign_sub_sat,
        .equal => .assign,
        else => null,
    };
}

/// Expr <- TernaryExpr
/// TernaryExpr <- BoolOrExpr (KEYWORD_if BoolOrExpr KEYWORD_else TernaryExpr)?
fn parseExpr(p: *Parse) Error!?Node.Index {
    const lhs = try p.parseExprPrecedence(0) orelse return null;

    const @"if" = p.eatToken(.keyword_if) orelse return lhs;

    const cond = try p.parseExprPrecedence(0) orelse return p.fail(.expected_expr);
    _ = try p.expectToken(.keyword_else);

    const rhs = try p.expectExpr();
    return try p.addNode(.{
        .tag = .ternary,
        .main_token = @"if",
        .data = .{ .node_and_extra = .{
            cond,
            try p.addExtra(Node.Ternary{
                .then_expr = lhs,
                .else_expr = rhs,
            }),
        } },
    });
}

fn expectExpr(p: *Parse) Error!Node.Index {
    return try p.parseExpr() orelse return p.fail(.expected_expr);
}

const Assoc = enum {
    left,
    right,
    none,
};

const OperInfo = struct {
    prec: i8,
    tag: Node.Tag,
    assoc: Assoc = Assoc.left,
};

/// A table of binary operator information. Higher precedence numbers are
/// stickier. All operators at the same precedence level should have the same
/// associativity.
const operTable = std.enums.directEnumArrayDefault(Token.Tag, OperInfo, .{ .prec = -1, .tag = Node.Tag.root }, 0, .{
    .keyword_or = .{ .prec = 10, .tag = .bool_or },

    .keyword_and = .{ .prec = 20, .tag = .bool_and },

    .equal_equal = .{ .prec = 30, .tag = .equal_equal, .assoc = Assoc.none },
    .bang_equal = .{ .prec = 30, .tag = .bang_equal, .assoc = Assoc.none },
    .angle_bracket_left = .{ .prec = 30, .tag = .less_than, .assoc = Assoc.none },
    .angle_bracket_right = .{ .prec = 30, .tag = .greater_than, .assoc = Assoc.none },
    .angle_bracket_left_equal = .{ .prec = 30, .tag = .less_or_equal, .assoc = Assoc.none },
    .angle_bracket_right_equal = .{ .prec = 30, .tag = .greater_or_equal, .assoc = Assoc.none },

    .ampersand = .{ .prec = 40, .tag = .bit_and },
    .caret = .{ .prec = 40, .tag = .bit_xor },
    .pipe = .{ .prec = 40, .tag = .bit_or },

    .angle_bracket_angle_bracket_left = .{ .prec = 50, .tag = .shl },
    .angle_bracket_angle_bracket_left_pipe = .{ .prec = 50, .tag = .shl_sat },
    .angle_bracket_angle_bracket_right = .{ .prec = 50, .tag = .shr },

    .plus = .{ .prec = 60, .tag = .add },
    .minus = .{ .prec = 60, .tag = .sub },
    .plus_plus = .{ .prec = 60, .tag = .array_cat },
    .plus_percent = .{ .prec = 60, .tag = .add_wrap },
    .minus_percent = .{ .prec = 60, .tag = .sub_wrap },
    .plus_pipe = .{ .prec = 60, .tag = .add_sat },
    .minus_pipe = .{ .prec = 60, .tag = .sub_sat },

    .asterisk = .{ .prec = 70, .tag = .mul },
    .slash = .{ .prec = 70, .tag = .div },
    .percent = .{ .prec = 70, .tag = .mod },
    .asterisk_percent = .{ .prec = 70, .tag = .mul_wrap },
    .asterisk_pipe = .{ .prec = 70, .tag = .mul_sat },
});

fn parseExprPrecedence(p: *Parse, min_prec: i32) Error!?Node.Index {
    assert(min_prec >= 0);
    var node = try p.parsePrefixExpr() orelse return null;

    var banned_prec: i8 = -1;

    while (true) {
        const tok_tag = p.tokenTag(p.tok_i);
        const info = operTable[@as(usize, @intCast(@intFromEnum(tok_tag)))];
        if (info.prec < min_prec) {
            break;
        }
        if (info.prec == banned_prec) {
            return p.fail(.chained_comparison_operators);
        }

        const oper_token = p.nextToken();
        const rhs = try p.parseExprPrecedence(info.prec + 1) orelse {
            try p.warn(.expected_expr);
            return node;
        };

        node = try p.addNode(.{
            .tag = info.tag,
            .main_token = oper_token,
            .data = .{ .node_and_node = .{ node, rhs } },
        });

        if (info.assoc == Assoc.none) {
            banned_prec = info.prec;
        }
    }

    return node;
}

/// PrefixExpr <- PrefixOp* PrimaryExpr
///
/// PrefixOp
///     <- EXCLAMATIONMARK
///      / MINUS
///      / TILDE
///      / MINUSPERCENT
///      / AMPERSAND
///      / KEYWORD_try
fn parsePrefixExpr(p: *Parse) Error!?Node.Index {
    const tag: Node.Tag = switch (p.tokenTag(p.tok_i)) {
        .bang => .bool_not,
        .minus => .negation,
        .tilde => .bit_not,
        .minus_percent => .negation_wrap,
        else => return p.parsePostfixExpr(),
    };
    return try p.addNode(.{
        .tag = tag,
        .main_token = p.nextToken(),
        .data = .{ .node = try p.expectPrefixExpr() },
    });
}

/// PostfixExpr <- PrimaryExpr (Call / Member / Index)*
///
/// Call <- LPAREN ExprList? COMMA? RPAREN
/// Member <- DOT IDENTIFIER
/// Index <- LBRACK Expr RBRACK
fn parsePostfixExpr(p: *Parse) Error!?Node.Index {
    const node = try p.parsePrimaryExpr();

    while (true) {
        switch (p.tokenTag(p.tok_i)) {
            .l_paren => @panic("TODO: Call"),
            .period => @panic("TODO: Member"),
            .l_bracket => @panic("TODO: Index"),
            else => break,
        }
    }

    return node;
}

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
///
/// FnExpr <- KEYWORD_fn FnParams NEWLINE? Block
/// ClassExpr <- KEYWORD_class NEWLINE? Block
/// InitList <- LBRACK ExprList COMMA? RBRACK
/// GroupedExpr <- LPAREN Expr RPAREN
fn parsePrimaryExpr(p: *Parse) Error!?Node.Index {
    const token_tag = p.tokenTag(p.tok_i);
    switch (token_tag) {
        .keyword_fn => @panic("TODO: FnExpr"),
        .keyword_class => @panic("TODO: ClassExpr"),
        .l_bracket => @panic("TODO: InitList"),
        .l_paren => return try p.addNode(.{
            .tag = .grouped_expression,
            .main_token = p.nextToken(),
            .data = .{ .node_and_token = .{
                try p.expectExpr(),
                try p.expectToken(.r_paren),
            } },
        }),
        .identifier => return try p.addNode(.{
            .tag = .identifier,
            .main_token = p.nextToken(),
            .data = undefined,
        }),
        .colon => {
            p.tok_i += 1;
            return try p.addNode(.{
                .tag = .literal_atom,
                .main_token = try p.expectToken(.identifier),
                .data = undefined,
            });
        },
        .literal_number => return try p.addNode(.{
            .tag = .literal_number,
            .main_token = p.nextToken(),
            .data = undefined,
        }),
        .literal_string => return try p.addNode(.{
            .tag = .literal_string,
            .main_token = p.nextToken(),
            .data = undefined,
        }),
        .literal_multiline_string_line => {
            const first_line = p.nextToken();
            while (p.tokenTag(p.tok_i) == .literal_multiline_string_line) {
                p.tok_i += 1;
            }
            return try p.addNode(.{
                .tag = .literal_multiline_string,
                .main_token = first_line,
                .data = .{ .token_and_token = .{
                    first_line,
                    p.tok_i - 1,
                } },
            });
        },
        else => if (literalNode(token_tag)) |tag|
            return try p.addNode(.{
                .tag = tag,
                .main_token = p.nextToken(),
                .data = undefined,
            })
        else
            return null,
    }
}

fn literalNode(tok: Token.Tag) ?Node.Tag {
    return switch (tok) {
        .literal_number => .literal_number,
        .literal_string => .literal_string,
        .keyword_nil => .literal_nil,
        .keyword_true => .literal_true,
        .keyword_false => .literal_false,
        else => null,
    };
}

fn expectPrefixExpr(p: *Parse) Error!Node.Index {
    return try p.parsePrefixExpr() orelse return p.fail(.expected_prefix_expr);
}

fn tokensOnSameLine(p: *Parse, token1: TokenIndex, token2: TokenIndex) bool {
    return std.mem.findScalar(u8, p.source[p.tokenStart(token1)..p.tokenStart(token2)], '\n') == null;
}

fn eatToken(p: *Parse, tag: Token.Tag) ?TokenIndex {
    return if (p.tokenTag(p.tok_i) == tag) p.nextToken() else null;
}

fn eatTokens(p: *Parse, tags: []const Token.Tag) ?TokenIndex {
    const available_tags = p.tokens.items(.tag)[p.tok_i..];
    if (!std.mem.startsWith(Token.Tag, available_tags, tags)) return null;
    const result = p.tok_i;
    p.tok_i += @intCast(tags.len);
    return result;
}

fn assertToken(p: *Parse, tag: Token.Tag) TokenIndex {
    const token = p.nextToken();
    assert(p.tokenTag(token) == tag);
    return token;
}

fn expectToken(p: *Parse, tag: Token.Tag) Error!TokenIndex {
    if (p.tokenTag(p.tok_i) != tag) {
        return p.failMsg(.{
            .tag = .expected_token,
            .token = p.tok_i,
            .extra = .{ .expected_tag = tag },
        });
    }
    return p.nextToken();
}

/// EOF is not consumed.
///
/// stmt_terminator
///     <- NEWLINE
///      / SEMICOLON
///      / &EOF
fn expectStmtTerminator(p: *Parse, error_tag: AstError.Tag, recoverable: bool) Error!void {
    const tag = p.tokenTag(p.tok_i);
    if (tag == .semicolon or tag == .newline) {
        _ = p.nextToken();
        return;
    } else if (tag == .eof) {
        return;
    }
    try p.warn(error_tag);
    if (!recoverable) return error.ParseError;
}

fn nextToken(p: *Parse) TokenIndex {
    const result = p.tok_i;
    p.tok_i += 1;
    return result;
}
