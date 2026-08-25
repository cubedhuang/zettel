//! Abstract syntax tree for Zettel source code.
//! The root note is at nodes[0] and contains an `.extra_range` to a list of sub-nodes.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;
const assert = std.debug.assert;

const debug = @import("debug.zig");

const tokenizer = @import("tokenizer.zig");
pub const ByteOffset = tokenizer.ByteOffset;
pub const Token = tokenizer.Token;
pub const Tokenizer = tokenizer.Tokenizer;
pub const TokenList = tokenizer.TokenList;

const Parse = @import("Parse.zig");

const Ast = @This();

/// Reference to externally-owned data.
source: [:0]const u8,

tokens: TokenList.Slice,
nodes: NodeList.Slice,
extra_data: []u32,

errors: []const Error,

pub const NodeList = std.MultiArrayList(Node);

/// Index into `tokens`.
pub const TokenIndex = u32;

/// Index into `tokens`, or null.
pub const OptionalTokenIndex = enum(u32) {
    none = std.math.maxInt(u32),
    _,

    pub fn unwrap(oti: OptionalTokenIndex) ?TokenIndex {
        return if (oti == .none) null else @intFromEnum(oti);
    }

    pub fn fromToken(ti: TokenIndex) OptionalTokenIndex {
        return @enumFromInt(ti);
    }

    pub fn fromOptional(oti: ?TokenIndex) OptionalTokenIndex {
        return if (oti) |ti| @enumFromInt(ti) else .none;
    }
};

/// A relative token index.
pub const TokenOffset = enum(i32) {
    zero = 0,
    _,

    pub fn init(base: TokenIndex, destination: TokenIndex) TokenOffset {
        const base_i64: i64 = base;
        const destination_i64: i64 = destination;
        return @enumFromInt(destination_i64 - base_i64);
    }

    pub fn toOptional(to: TokenOffset) OptionalTokenOffset {
        const result: OptionalTokenOffset = @enumFromInt(@intFromEnum(to));
        assert(result != .none);
        return result;
    }

    pub fn toAbsolute(offset: TokenOffset, base: TokenIndex) TokenIndex {
        return @intCast(@as(i64, base) + @intFromEnum(offset));
    }
};

/// A relative token index, or null.
pub const OptionalTokenOffset = enum(i32) {
    none = std.math.maxInt(i32),
    _,

    pub fn unwrap(oto: OptionalTokenOffset) ?TokenOffset {
        return if (oto == .none) null else @enumFromInt(@intFromEnum(oto));
    }
};

pub fn tokenTag(tree: *const Ast, token_index: TokenIndex) Token.Tag {
    return tree.tokens.items(.tag)[token_index];
}

pub fn tokenStart(tree: *const Ast, token_index: TokenIndex) ByteOffset {
    return tree.tokens.items(.start)[token_index];
}

pub fn nodeTag(tree: *const Ast, node: Node.Index) Node.Tag {
    return tree.nodes.items(.tag)[@intFromEnum(node)];
}

pub fn nodeMainToken(tree: *const Ast, node: Node.Index) TokenIndex {
    return tree.nodes.items(.main_token)[@intFromEnum(node)];
}

pub fn nodeData(tree: *const Ast, node: Node.Index) Node.Data {
    return tree.nodes.items(.data)[@intFromEnum(node)];
}

pub fn isTokenPrecededByTags(
    tree: *const Ast,
    ti: TokenIndex,
    expected_token_tags: []const Token.Tag,
) bool {
    return std.mem.endsWith(
        Token.Tag,
        tree.tokens.items(.tag)[0..ti],
        expected_token_tags,
    );
}

pub const Location = struct {
    line: usize,
    column: usize,
    line_start: usize,
    line_end: usize,
};

pub const Span = struct {
    start: u32,
    end: u32,
    main: u32,
};

pub fn deinit(tree: *Ast, gpa: Allocator) void {
    tree.tokens.deinit(gpa);
    tree.nodes.deinit(gpa);
    gpa.free(tree.extra_data);
    gpa.free(tree.errors);
    tree.* = undefined;
}

/// Result should be freed with tree.deinit() when there are
/// no more references to any of the tokens or nodes.
pub fn parse(gpa: Allocator, source: [:0]const u8) Allocator.Error!Ast {
    var tokens = try Tokenizer.tokenize(gpa, source);
    defer tokens.deinit(gpa);

    if (debug.DISPLAY_TOKENS) {
        for (tokens.items(.tag), tokens.items(.start)) |tag, start| {
            std.debug.print("{d:>4} {s}\n", .{ start, @tagName(tag) });
        }
    }

    var tokens_slice = tokens.toOwnedSlice();
    errdefer tokens_slice.deinit(gpa);
    return parseTokens(gpa, source, tokens_slice);
}

pub fn parseTokens(gpa: Allocator, source: [:0]const u8, tokens: Ast.TokenList.Slice) Allocator.Error!Ast {
    var parser: Parse = .{
        .source = source,
        .gpa = gpa,
        .tokens = tokens,
        .errors = .empty,
        .nodes = .empty,
        .extra_data = .empty,
        .scratch = .empty,
        .tok_i = 0,
        .block_context = .class,
    };
    defer parser.errors.deinit(gpa);
    defer parser.nodes.deinit(gpa);
    defer parser.extra_data.deinit(gpa);
    defer parser.scratch.deinit(gpa);

    // Empirically, Zig source code has a 2:1 ratio of tokens to AST nodes.
    // Make sure at least 1 so we can use appendAssumeCapacity on the root node below.
    const estimated_node_count = (tokens.len + 2) / 2;
    try parser.nodes.ensureTotalCapacity(gpa, estimated_node_count);

    try parser.parseRoot();

    try parser.extra_data.shrinkToLen(gpa);
    try parser.errors.shrinkToLen(gpa);

    // TODO experiment with compacting the MultiArrayList slices here
    return .{
        .source = source,
        .tokens = tokens,
        .nodes = parser.nodes.toOwnedSlice(),
        .extra_data = parser.extra_data.toOwnedSliceAssert(),
        .errors = parser.errors.toOwnedSliceAssert(),
    };
}

/// Returns an extra offset for column and byte offset of errors that
/// should point after the token in the error message.
pub fn errorOffset(tree: Ast, parse_error: Error) u32 {
    return if (parse_error.token_is_prev) @intCast(tree.tokenSlice(parse_error.token).len) else 0;
}

pub fn tokenLocation(self: Ast, start_offset: ByteOffset, token_index: TokenIndex) Location {
    var loc = Location{
        .line = 0,
        .column = 0,
        .line_start = start_offset,
        .line_end = self.source.len,
    };
    const token_start = self.tokenStart(token_index);

    // Scan to by line until we go past the token start
    while (std.mem.findScalarPos(u8, self.source, loc.line_start, '\n')) |i| {
        if (i >= token_start) {
            break; // Went past
        }
        loc.line += 1;
        loc.line_start = i + 1;
    }

    const offset = loc.line_start;
    for (self.source[offset..], 0..) |c, i| {
        if (i + offset == token_start) {
            loc.line_end = i + offset;
            while (loc.line_end < self.source.len and self.source[loc.line_end] != '\n') {
                loc.line_end += 1;
            }
            return loc;
        }
        if (c == '\n') {
            loc.line += 1;
            loc.column = 0;
            loc.line_start = i + 1;
        } else {
            loc.column += 1;
        }
    }
    return loc;
}

pub fn tokenSlice(tree: Ast, token_index: TokenIndex) []const u8 {
    const token_tag = tree.tokenTag(token_index);

    // Many tokens can be determined entirely by their tag.
    if (token_tag.lexeme()) |lexeme| {
        return lexeme;
    }

    // For some tokens, re-tokenization is needed to find the end.
    var tok: Tokenizer = .{
        .buffer = tree.source,
        .index = tree.tokenStart(token_index),
    };
    const token = tok.next();
    assert(token.tag == token_tag);
    return tree.source[token.loc.start..token.loc.end];
}

pub fn extraDataSlice(tree: Ast, range: Node.SubRange, comptime T: type) []const T {
    return @ptrCast(tree.extra_data[@intFromEnum(range.start)..@intFromEnum(range.end)]);
}

pub fn extraDataSliceWithLen(tree: Ast, start: ExtraIndex, len: u32, comptime T: type) []const T {
    return @ptrCast(tree.extra_data[@intFromEnum(start)..][0..len]);
}

pub fn extraData(tree: Ast, index: ExtraIndex, comptime T: type) T {
    const fields = std.meta.fields(T);
    var result: T = undefined;
    inline for (fields, 0..) |field, i| {
        @field(result, field.name) = switch (field.type) {
            Node.Index,
            Node.OptionalIndex,
            OptionalTokenIndex,
            ExtraIndex,
            => @enumFromInt(tree.extra_data[@intFromEnum(index) + i]),
            TokenIndex => tree.extra_data[@intFromEnum(index) + i],
            else => @compileError("unexpected field type: " ++ @typeName(field.type)),
        };
    }
    return result;
}

fn loadOptionalNodesIntoBuffer(comptime size: usize, buffer: *[size]Node.Index, items: [size]Node.OptionalIndex) []Node.Index {
    for (buffer, items, 0..) |*node, opt_node, i| {
        node.* = opt_node.unwrap() orelse return buffer[0..i];
    }
    return buffer[0..];
}

pub fn rootDecls(tree: Ast) []const Node.Index {
    return tree.extraDataSlice(tree.nodeData(.root).extra_range, Node.Index);
}

pub fn renderError(tree: Ast, parse_error: Error, w: *Writer) Writer.Error!void {
    switch (parse_error.tag) {
        .chained_comparison_operators => {
            return w.writeAll("comparison operators cannot be chained");
        },
        .expected_block => {
            return w.print("expected block, found '{s}'", .{
                tree.tokenTag(parse_error.token + @intFromBool(parse_error.token_is_prev)).symbol(),
            });
        },
        .expected_expr => {
            return w.print("expected expression, found '{s}'", .{
                tree.tokenTag(parse_error.token + @intFromBool(parse_error.token_is_prev)).symbol(),
            });
        },
        .expected_expr_or_assignment => {
            return w.print("expected expression or assignment, found '{s}'", .{
                tree.tokenTag(parse_error.token + @intFromBool(parse_error.token_is_prev)).symbol(),
            });
        },
        .expected_param_list => {
            return w.print("expected parameter list, found '{s}'", .{
                tree.tokenTag(parse_error.token + @intFromBool(parse_error.token_is_prev)).symbol(),
            });
        },
        .expected_prefix_expr => {
            return w.print("expected prefix expression, found '{s}'", .{
                tree.tokenTag(parse_error.token + @intFromBool(parse_error.token_is_prev)).symbol(),
            });
        },
        .expected_pub_item => {
            return w.writeAll("expected function or variable declaration after pub");
        },
        .expected_statement => {
            return w.print("expected statement, found '{s}'", .{
                tree.tokenTag(parse_error.token).symbol(),
            });
        },
        .same_line_doc_comment => {
            return w.writeAll("same line documentation comment");
        },
        .invalid_doc_comment => {
            return w.writeAll("documentation comment only allowed on function, class, or variable declaration");
        },
        .varargs_nonfinal => {
            return w.writeAll("function prototype has parameter after varargs");
        },

        .invalid_decl_target => {
            return w.writeAll("declaration target must be an identifier");
        },
        .expected_semi_after_decl => {
            return w.writeAll("expected ';' or newline after declaration");
        },
        .expected_semi_after_stmt => {
            return w.writeAll("expected ';' or newline after statement");
        },
        .expected_comma_after_arg => {
            return w.writeAll("expected ',' after argument");
        },
        .expected_comma_after_param => {
            return w.writeAll("expected ',' after parameter");
        },
        .expected_comma_after_initializer => {
            return w.writeAll("expected ',' after initializer");
        },
        .invalid_ampersand_ampersand => {
            return w.writeAll("ambiguous use of '&&'; use 'and' for logical AND, or change whitespace to ' & &' for bitwise AND");
        },

        .invalid_byte => {
            const tok_slice = tree.source[tree.tokens.items(.start)[parse_error.token]..];
            return w.print("{s} contains invalid byte: '{f}'", .{
                switch (tok_slice[0]) {
                    '\'' => "character literal",
                    '"', '\\' => "string literal",
                    '/' => "comment",
                    else => unreachable,
                },
                std.zig.fmtChar(tok_slice[parse_error.extra.offset]),
            });
        },

        .expected_token => {
            const found_tag = tree.tokenTag(parse_error.token + @intFromBool(parse_error.token_is_prev));
            const expected_symbol = parse_error.extra.expected_tag.symbol();
            switch (found_tag) {
                .invalid => return w.print("expected '{s}', found invalid bytes", .{
                    expected_symbol,
                }),
                else => return w.print("expected '{s}', found '{s}'", .{
                    expected_symbol, found_tag.symbol(),
                }),
            }
        },
    }
}

pub fn firstToken(tree: Ast, node: Node.Index) TokenIndex {
    var end_offset: u32 = 0;
    var n = node;
    while (true) switch (tree.nodeTag(n)) {
        .root => return 0,

        .bool_not,
        .negation,
        .bit_not,
        .negation_wrap,
        .array_init_two,
        .array_init_two_comma,
        .array_init,
        .array_init_comma,
        .record_init_two,
        .record_init_two_comma,
        .record_init,
        .record_init_comma,
        .if_simple,
        .@"if",
        .@"continue",
        .@"break",
        .@"return",
        .fn_proto_two,
        .fn_proto_two_comma,
        .fn_proto,
        .fn_proto_comma,
        .fn_decl,
        .class_decl,
        .identifier,
        .literal_number,
        .literal_string,
        .literal_multiline_string,
        .grouped_expression,
        => return tree.nodeMainToken(n) - end_offset,

        .var_decl,
        .literal_atom,
        => return tree.nodeMainToken(n) - 1 - end_offset,

        .@"catch",
        .equal_equal,
        .bang_equal,
        .less_than,
        .greater_than,
        .less_or_equal,
        .greater_or_equal,
        .assign_mul,
        .assign_div,
        .assign_mod,
        .assign_add,
        .assign_sub,
        .assign_shl,
        .assign_shl_sat,
        .assign_shr,
        .assign_bit_and,
        .assign_bit_xor,
        .assign_bit_or,
        .assign_mul_wrap,
        .assign_add_wrap,
        .assign_sub_wrap,
        .assign_mul_sat,
        .assign_add_sat,
        .assign_sub_sat,
        .assign,
        .mul,
        .div,
        .mod,
        .mul_wrap,
        .mul_sat,
        .add,
        .sub,
        .array_cat,
        .add_wrap,
        .sub_wrap,
        .add_sat,
        .sub_sat,
        .shl,
        .shl_sat,
        .shr,
        .bit_and,
        .bit_xor,
        .bit_or,
        .bool_and,
        .bool_or,
        .slice_open,
        .array_access,
        => n = tree.nodeData(n).node_and_node[0],

        .call_one,
        .call_one_comma,
        => n = tree.nodeData(n).node_and_opt_node[0],

        .field_access,
        => n = tree.nodeData(n).node_and_token[0],

        .slice,
        .call,
        .call_comma,
        => n = tree.nodeData(n).node_and_extra[0],

        .for_simple,
        .@"for",
        .block,
        .block_semicolon,
        .block_two,
        .block_two_semicolon,
        => {
            // Look for a label.
            const lbrace = tree.nodeMainToken(n);
            if (tree.isTokenPrecededByTags(lbrace, &.{ .identifier, .colon })) {
                end_offset += 2;
            }
            return lbrace - end_offset;
        },
    };
}

pub fn lastToken(tree: Ast, node: Node.Index) TokenIndex {
    var n = node;
    var end_offset: u32 = 0;
    while (true) switch (tree.nodeTag(n)) {
        .root => return @intCast(tree.tokens.len - 1),

        .bool_not,
        .negation,
        .bit_not,
        .negation_wrap,
        => n = tree.nodeData(n).node,

        .equal_equal,
        .bang_equal,
        .less_than,
        .greater_than,
        .less_or_equal,
        .greater_or_equal,
        .assign_mul,
        .assign_div,
        .assign_mod,
        .assign_add,
        .assign_sub,
        .assign_shl,
        .assign_shl_sat,
        .assign_shr,
        .assign_bit_and,
        .assign_bit_xor,
        .assign_bit_or,
        .assign_mul_wrap,
        .assign_add_wrap,
        .assign_sub_wrap,
        .assign_mul_sat,
        .assign_add_sat,
        .assign_sub_sat,
        .assign,
        .mul,
        .div,
        .mod,
        .mul_wrap,
        .mul_sat,
        .add,
        .sub,
        .array_cat,
        .add_wrap,
        .sub_wrap,
        .add_sat,
        .sub_sat,
        .shl,
        .shl_sat,
        .shr,
        .bit_and,
        .bit_xor,
        .bit_or,
        .bool_and,
        .bool_or,
        .if_simple,
        .fn_decl,
        .class_decl,
        => n = tree.nodeData(n).node_and_node[1],

        .var_decl => n = tree.nodeData(n).token_and_node[1],

        .for_simple,
        => n = tree.nodeData(n).opt_node_and_node[1],

        .fn_proto_two,
        .fn_proto_two_comma,
        => {
            const params = tree.nodeData(n).opt_token_and_opt_token;
            if (params[1].unwrap() orelse params[0].unwrap()) |last_param| {
                return last_param + 1 + end_offset;
            } else {
                return tree.nodeMainToken(n) + 2 + end_offset;
            }
        },
        .fn_proto,
        .fn_proto_comma,
        => {
            const extra_index = tree.nodeData(n).extra_range.end - 1;
            const last_param = tree.extraData(extra_index, TokenIndex);
            return last_param + 1 + end_offset;
        },

        .field_access,
        => return tree.nodeData(n).node_and_token[1] + end_offset,
        .grouped_expression => return tree.nodeData(n).node_and_token[1] + end_offset,
        .literal_multiline_string => return tree.nodeData(n).token_and_token[1] + end_offset,

        .literal_number,
        .identifier,
        .literal_atom,
        .literal_string,
        => return tree.nodeMainToken(n) + end_offset,

        .@"return" => {
            n = tree.nodeData(n).opt_node.unwrap() orelse {
                return tree.nodeMainToken(n) + end_offset;
            };
        },

        .call => {
            _, const extra_index = tree.nodeData(n).node_and_extra;
            const params = tree.extraData(extra_index, Node.SubRange);
            assert(params.start != params.end);
            end_offset += 1; // for the rparen
            n = @enumFromInt(tree.extra_data[@intFromEnum(params.end) - 1]); // last parameter
        },
        .call_comma,
        => {
            _, const extra_index = tree.nodeData(n).node_and_extra;
            const params = tree.extraData(extra_index, Node.SubRange);
            assert(params.start != params.end);
            end_offset += 2; // for the comma + rparen
            n = @enumFromInt(tree.extra_data[@intFromEnum(params.end) - 1]); // last parameter
        },
        .array_init,
        .record_init,
        .block,
        => {
            const range = tree.nodeData(n).extra_range;
            assert(range.start != range.end);
            end_offset += 1; // for the rbrace
            n = @enumFromInt(tree.extra_data[@intFromEnum(range.end) - 1]); // last statement
        },
        .array_init_comma,
        .record_init_comma,
        .block_semicolon,
        => {
            const range = tree.nodeData(n).extra_range;
            assert(range.start != range.end);
            end_offset += 2; // for the comma/semicolon + rbrace/rparen
            n = @enumFromInt(tree.extra_data[@intFromEnum(range.end) - 1]); // last member
        },
        .call_one,
        => {
            _, const first_param = tree.nodeData(n).node_and_opt_node;
            end_offset += 1; // for the rparen
            n = first_param.unwrap() orelse {
                return tree.nodeMainToken(n) + end_offset;
            };
        },

        .array_init_two,
        .block_two,
        .record_init_two,
        => {
            const opt_lhs, const opt_rhs = tree.nodeData(n).opt_node_and_opt_node;
            if (opt_rhs.unwrap()) |rhs| {
                end_offset += 1; // for the rparen/rbrace
                n = rhs;
            } else if (opt_lhs.unwrap()) |lhs| {
                end_offset += 1; // for the rparen/rbrace
                n = lhs;
            } else {
                return tree.nodeMainToken(n) + 1 + end_offset;
            }
        },
        .array_init_two_comma,
        .block_two_semicolon,
        .record_init_two_comma,
        => {
            const opt_lhs, const opt_rhs = tree.nodeData(n).opt_node_and_opt_node;
            end_offset += 2; // for the comma/semicolon + rbrace/rparen
            if (opt_rhs.unwrap()) |rhs| {
                n = rhs;
            } else if (opt_lhs.unwrap()) |lhs| {
                n = lhs;
            } else {
                unreachable;
            }
        },
        .var_decl => n = tree.nodeData(n).token_and_node[1],

        .array_access,
        => {
            _, const rhs = tree.nodeData(n).node_and_node;
            end_offset += 1; // for the rbracket/rbrace/rparen
            n = rhs;
        },

        .slice_open => {
            _, const start_node = tree.nodeData(n).node_and_node;
            end_offset += 2; // ellipsis2 + rbracket, or comma + rparen
            n = start_node;
        },
        .slice => {
            _, const extra_index = tree.nodeData(n).node_and_extra;
            const extra = tree.extraData(extra_index, Node.Slice);
            end_offset += 1; // rbracket
            n = extra.end;
        },

        .@"continue", .@"break" => {
            const opt_label = tree.nodeData(n).opt_token;
            if (opt_label.unwrap()) |label| {
                return label + end_offset;
            } else {
                return tree.nodeMainToken(n) + end_offset;
            }
        },
        .@"if" => {
            _, const extra_index = tree.nodeData(n).node_and_extra;
            const extra = tree.extraData(extra_index, Node.If);
            n = extra.else_block.unwrap() orelse extra.then_block;
        },
        .@"for" => {
            _, const extra_index = tree.nodeData(n).opt_node_and_extra;
            const extra = tree.extraData(extra_index, Node.For);
            n = extra.else_block.unwrap() orelse extra.then_block;
        },
    };
}

pub fn tokensOnSameLine(tree: Ast, token1: TokenIndex, token2: TokenIndex) bool {
    const source = tree.source[tree.tokenStart(token1)..tree.tokenStart(token2)];
    return std.mem.findScalar(u8, source, '\n') == null;
}

pub fn getNodeSource(tree: Ast, node: Node.Index) []const u8 {
    const first_token = tree.firstToken(node);
    const last_token = tree.lastToken(node);
    const start = tree.tokenStart(first_token);
    const end = tree.tokenStart(last_token) + tree.tokenSlice(last_token).len;
    return tree.source[start..end];
}

pub const Error = struct {
    tag: Tag,
    /// True if `token` points to the token before the token causing an issue.
    token_is_prev: bool = false,
    token: TokenIndex,
    extra: union {
        none: void,
        expected_tag: Token.Tag,
        offset: usize,
    } = .{ .none = {} },

    pub const Tag = enum {
        chained_comparison_operators,
        expected_block,
        expected_expr,
        expected_expr_or_assignment,
        expected_param_list,
        expected_prefix_expr,
        expected_pub_item,
        expected_statement,
        same_line_doc_comment,
        invalid_doc_comment,

        varargs_nonfinal,
        invalid_decl_target,
        expected_semi_after_decl,
        expected_semi_after_stmt,
        expected_comma_after_arg,
        expected_comma_after_param,
        expected_comma_after_initializer,
        invalid_ampersand_ampersand,

        /// `expected_tag` is populated.
        expected_token,

        /// `offset` is populated
        invalid_byte,
    };
};

/// Index into `extra_data`.
pub const ExtraIndex = enum(u32) {
    _,
};

pub const Node = struct {
    tag: Tag,
    main_token: TokenIndex,
    data: Data,

    /// Index into `nodes`.
    pub const Index = enum(u32) {
        root = 0,
        _,

        pub fn toOptional(i: Index) OptionalIndex {
            const result: OptionalIndex = @enumFromInt(@intFromEnum(i));
            assert(result != .none);
            return result;
        }

        pub fn toOffset(base: Index, destination: Index) Offset {
            const base_i64: i64 = @intFromEnum(base);
            const destination_i64: i64 = @intFromEnum(destination);
            return @enumFromInt(destination_i64 - base_i64);
        }
    };

    /// Index into `nodes`, or null.
    pub const OptionalIndex = enum(u32) {
        root = 0,
        none = std.math.maxInt(u32),
        _,

        pub fn unwrap(oi: OptionalIndex) ?Index {
            return if (oi == .none) null else @enumFromInt(@intFromEnum(oi));
        }

        pub fn fromOptional(oi: ?Index) OptionalIndex {
            return if (oi) |i| i.toOptional() else .none;
        }
    };

    /// A relative node index.
    pub const Offset = enum(i32) {
        zero = 0,
        _,

        pub fn toOptional(o: Offset) OptionalOffset {
            const result: OptionalOffset = @enumFromInt(@intFromEnum(o));
            assert(result != .none);
            return result;
        }

        pub fn toAbsolute(offset: Offset, base: Index) Index {
            return @enumFromInt(@as(i64, @intFromEnum(base)) + @intFromEnum(offset));
        }
    };

    /// A relative node index, or null.
    pub const OptionalOffset = enum(i32) {
        none = std.math.maxInt(i32),
        _,

        pub fn unwrap(oo: OptionalOffset) ?Offset {
            return if (oo == .none) null else @enumFromInt(@intFromEnum(oo));
        }
    };

    comptime {
        // Goal is to keep this under one byte for efficiency.
        assert(@sizeOf(Tag) == 1);

        if (!std.debug.runtime_safety) {
            assert(@sizeOf(Data) == 8);
        }
    }

    /// The FooComma/FooSemicolon variants exist to ease the implementation of
    /// `Ast.lastToken()`
    pub const Tag = enum {
        /// The root node which is guaranteed to be at `Node.Index.root`.
        ///
        /// The `main_token` field is the first token for the source file.
        root,
        /// `a := b`.
        /// Can be local or global.
        ///
        /// The `data` field is a `.token_and_node`:
        ///   1. a `TokenIndex` to the name.
        ///   2. a `Node.Index` to the initialization expression.
        ///
        /// The `main_token` field is the `:=` token.
        var_decl,
        /// `lhs.a`.
        ///
        /// The `data` field is a `.node_and_token`:
        ///   1. a `Node.Index` to the left side of the field access.
        ///   2. a `TokenIndex` to the field name identifier.
        ///
        /// The `main_token` field is the `.` token.
        field_access,
        /// `a if b else c`.
        ///
        /// The `data` field is a `.node_and_extra`:
        ///   1. a `Node.Index` to the condition.
        ///   2. a `ExtraIndex` to `Ternary`.
        ///
        /// The `main_token` field is the `if` token.
        ternary,
        /// `lhs == rhs`. The `main_token` field is the `==` token.
        equal_equal,
        /// `lhs != rhs`. The `main_token` field is the `!=` token.
        bang_equal,
        /// `lhs < rhs`. The `main_token` field is the `<` token.
        less_than,
        /// `lhs > rhs`. The `main_token` field is the `>` token.
        greater_than,
        /// `lhs <= rhs`. The `main_token` field is the `<=` token.
        less_or_equal,
        /// `lhs >= rhs`. The `main_token` field is the `>=` token.
        greater_or_equal,
        /// `lhs *= rhs`. The `main_token` field is the `*=` token.
        assign_mul,
        /// `lhs /= rhs`. The `main_token` field is the `/=` token.
        assign_div,
        /// `lhs %= rhs`. The `main_token` field is the `%=` token.
        assign_mod,
        /// `lhs += rhs`. The `main_token` field is the `+=` token.
        assign_add,
        /// `lhs -= rhs`. The `main_token` field is the `-=` token.
        assign_sub,
        /// `lhs <<= rhs`. The `main_token` field is the `<<=` token.
        assign_shl,
        /// `lhs <<|= rhs`. The `main_token` field is the `<<|=` token.
        assign_shl_sat,
        /// `lhs >>= rhs`. The `main_token` field is the `>>=` token.
        assign_shr,
        /// `lhs &= rhs`. The `main_token` field is the `&=` token.
        assign_bit_and,
        /// `lhs ^= rhs`. The `main_token` field is the `^=` token.
        assign_bit_xor,
        /// `lhs |= rhs`. The `main_token` field is the `|=` token.
        assign_bit_or,
        /// `lhs *%= rhs`. The `main_token` field is the `*%=` token.
        assign_mul_wrap,
        /// `lhs +%= rhs`. The `main_token` field is the `+%=` token.
        assign_add_wrap,
        /// `lhs -%= rhs`. The `main_token` field is the `-%=` token.
        assign_sub_wrap,
        /// `lhs *|= rhs`. The `main_token` field is the `*%=` token.
        assign_mul_sat,
        /// `lhs +|= rhs`. The `main_token` field is the `+|=` token.
        assign_add_sat,
        /// `lhs -|= rhs`. The `main_token` field is the `-|=` token.
        assign_sub_sat,
        /// `lhs = rhs`. The `main_token` field is the `=` token.
        assign,
        /// `lhs * rhs`. The `main_token` field is the `*` token.
        mul,
        /// `lhs / rhs`. The `main_token` field is the `/` token.
        div,
        /// `lhs % rhs`. The `main_token` field is the `%` token.
        mod,
        /// `lhs *% rhs`. The `main_token` field is the `*%` token.
        mul_wrap,
        /// `lhs *| rhs`. The `main_token` field is the `*|` token.
        mul_sat,
        /// `lhs + rhs`. The `main_token` field is the `+` token.
        add,
        /// `lhs - rhs`. The `main_token` field is the `-` token.
        sub,
        /// `lhs ++ rhs`. The `main_token` field is the `++` token.
        array_cat,
        /// `lhs +% rhs`. The `main_token` field is the `+%` token.
        add_wrap,
        /// `lhs -% rhs`. The `main_token` field is the `-%` token.
        sub_wrap,
        /// `lhs +| rhs`. The `main_token` field is the `+|` token.
        add_sat,
        /// `lhs -| rhs`. The `main_token` field is the `-|` token.
        sub_sat,
        /// `lhs << rhs`. The `main_token` field is the `<<` token.
        shl,
        /// `lhs <<| rhs`. The `main_token` field is the `<<|` token.
        shl_sat,
        /// `lhs >> rhs`. The `main_token` field is the `>>` token.
        shr,
        /// `lhs & rhs`. The `main_token` field is the `&` token.
        bit_and,
        /// `lhs ^ rhs`. The `main_token` field is the `^` token.
        bit_xor,
        /// `lhs | rhs`. The `main_token` field is the `|` token.
        bit_or,
        /// `lhs and rhs`. The `main_token` field is the `and` token.
        bool_and,
        /// `lhs or rhs`. The `main_token` field is the `or` token.
        bool_or,
        /// `!expr`. The `main_token` field is the `!` token.
        bool_not,
        /// `-expr`. The `main_token` field is the `-` token.
        negation,
        /// `~expr`. The `main_token` field is the `~` token.
        bit_not,
        /// `-%expr`. The `main_token` field is the `-%` token.
        negation_wrap,
        /// `lhs[rhs..]`
        ///
        /// The `main_token` field is the `[` token.
        slice_open,
        /// `sliced[start..end]`.
        ///
        /// The `data` field is a `.node_and_extra`:
        ///   1. a `Node.Index` to the sliced expression.
        ///   2. a `ExtraIndex` to `Slice`.
        ///
        /// The `main_token` field is the `[` token.
        slice,
        /// `lhs[rhs]`.
        ///
        /// The `main_token` field is the `[` token.
        array_access,
        /// `[a]`,
        /// `[a, b]`.
        ///
        /// The `data` field is a `.opt_node_and_opt_node`:
        ///   1. a `Node.OptionalIndex` to the first element, if any.
        ///   2. a `Node.OptionalIndex` to the second element, if any.
        ///
        /// The `main_token` field is the `[` token.
        array_init_two,
        /// Same as `array_init_two` except there is known to be a trailing
        /// comma before the final rbrace.
        array_init_two_comma,
        /// `[a, b, c]`.
        ///
        /// The `data` field is a `.extra_range` that stores a `Node.Index` for
        /// each element.
        ///
        /// The `main_token` field is the `[` token.
        array_init,
        /// Same as `array_init` except there is known to be a trailing
        /// comma before the final rbrace.
        array_init_comma,
        /// `[=]`.
        /// `[x = a, y = b]`.
        ///
        /// The `data` field is a `.opt_node_and_opt_node`:
        ///   1. a `Node.OptionalIndex` to the first field initialization, if any.
        ///   2. a `Node.OptionalIndex` to the second field initialization, if any.
        ///
        /// The `main_token` field is the '{' token.
        ///
        /// The field name is determined by looking at the tokens preceding the
        /// field initialization.
        record_init_two,
        /// Same as `record_init_two` except there is known to be a trailing
        /// comma before the final rbrace.
        record_init_two_comma,
        /// `[x = a, y = b, z = c]`.
        ///
        /// The `data` field is a `.extra_range` that stores a `Node.Index` for
        /// each field initialization.
        ///
        /// The `main_token` field is the `{` token.
        ///
        /// The field name is determined by looking at the tokens preceding the
        /// field initialization.
        record_init,
        /// Same as `record_init` except there is known to be a trailing
        /// comma before the final rbrace.
        record_init_comma,
        /// `a(b)`, `a()`.
        ///
        /// The `data` field is a `.node_and_opt_node`:
        ///   1. a `Node.Index` to the function expression.
        ///   2. a `Node.OptionalIndex` to the first argument, if any.
        ///
        /// The `main_token` field is the `(` token.
        call_one,
        /// Same as `call_one` except there is known to be a trailing comma
        /// before the final rparen.
        call_one_comma,
        /// `a(b, c, d)`.
        ///
        /// The `data` field is a `.node_and_extra`:
        ///   1. a `Node.Index` to the function expression.
        ///   2. a `ExtraIndex` to a `SubRange` that stores a `Node.Index` for
        ///      each argument.
        ///
        /// The `main_token` field is the `(` token.
        call,
        /// Same as `call` except there is known to be a trailing comma before
        /// the final rparen.
        call_comma,
        /// `for { b }`.
        /// `for a { b }`.
        ///
        /// The `data` field is a `.opt_node_and_node`:
        ///   1. a `Node.OptionalIndex` to a condition, if any.
        ///   2. a `Node.Index` to a body block.
        ///
        /// The `main_token` field is the `for` token.
        for_simple,
        /// `for i := 1; i < 10; i += 1 {} else {}`.
        /// `for init_decl; condition; cont_expr {} else {}`.
        ///
        /// The `data` field is a `.opt_node_and_extra`:
        ///   1. a `Node.OptionalIndex` to a condition, if any.
        ///   2. a `ExtraIndex` to `For`.
        ///
        /// The `main_token` field is the `for` token.
        @"for",
        /// `if lhs { rhs }`.
        if_simple,
        /// `if a { b } else { c }`.
        /// `if a; b { c } else { d }`.
        ///
        /// The `data` field is a `.node_and_extra`:
        ///   1. a `Node.Index` to a condition.
        ///   2. a `ExtraIndex` to `If`.
        ///
        /// The `main_token` field is the `if` token.
        @"if",
        /// `continue label`,
        /// `continue`.
        ///
        /// The `data` field is a `.opt_token` to the label identifier, if any.
        ///
        /// The `main_token` field is the `continue` token.
        @"continue",
        /// `break label`,
        /// `break`.
        ///
        /// The `data` field is a `.opt_token` to the label identifier, if any.
        ///
        /// The `main_token` field is the `break` token.
        @"break",
        /// `return expr`, `return`.
        ///
        /// The `data` field is a `.opt_node` to the return value, if any.
        ///
        /// The `main_token` field is the `return` token.
        @"return",
        /// `fn name(a, b)`.
        ///
        /// The `data` field is a `.opt_token_and_opt_token`:
        ///   1. a `OptionalTokenIndex` to the first parameter name, if any.
        ///   2. a `OptionalTokenIndex` to the second parameter name, if any.
        ///
        /// The `main_token` field is the `fn` token.
        fn_proto_two,
        /// Same as `fn_proto_two` except there is known to be a
        /// trailing comma before the final rparen.
        fn_proto_two_comma,
        /// `fn name(a, b, c)`.
        ///
        /// The `data` field is a `.extra_range` that stores a TokenIndex for
        /// each parameter.
        ///
        /// The `main_token` field is the `fn` token.
        fn_proto,
        /// Same as `fn_proto` except there is known to be a
        /// trailing comma before the final rparen.
        fn_proto_comma,
        /// Extern function declarations use the fn_proto tags rather than this one.
        ///
        /// The `data` field is a `.node_and_node`:
        ///   1. a `Node.Index` to `fn_proto_*`.
        ///   2. a `Node.Index` to function body block.
        ///
        /// The `main_token` field is the `fn` token.
        fn_decl,
        /// The `data` field is unused.
        ///
        /// Most identifiers will not have explicit AST nodes, however for
        /// expressions which could be one of many different kinds of AST nodes,
        /// there will be an identifier AST node for it.
        identifier,
        /// The `main_token` field is the keyword.
        literal_nil,
        /// The `main_token` field is the keyword.
        literal_true,
        /// The `main_token` field is the keyword.
        literal_false,
        /// The `data` field is unused.
        literal_number,
        /// `:ok`.
        /// `:err`.
        ///
        /// The `data` field is unused.
        ///
        /// The `main_token` field is the identifier.
        literal_atom,
        /// The `data` field is unused.
        ///
        /// The `main_token` field is the string literal token.
        literal_string,
        /// The `data` field is a `.token_and_token`:
        ///   1. a `TokenIndex` to the first `.multiline_string_literal_line` token.
        ///   2. a `TokenIndex` to the last `.multiline_string_literal_line` token.
        ///
        /// The `main_token` field is the first token index (redundant with `data`).
        literal_multiline_string,
        /// `(expr)`.
        ///
        /// The `data` field is a `.node_and_token`:
        ///   1. a `Node.Index` to the sub-expression
        ///   2. a `TokenIndex` to the `)` token.
        ///
        /// The `main_token` field is the `(` token.
        grouped_expression,
        /// `class {}`.
        ///
        /// The `data` field is a `.node` to the class body block.
        ///
        /// The `main_token` field is the `class` token.
        class_decl,
        /// `{lhs rhs}`.
        ///
        /// The `data` field is a `.opt_node_and_opt_node`:
        ///   1. a `Node.OptionalIndex` to the first statement, if any.
        ///   2. a `Node.OptionalIndex` to the second statement, if any.
        ///
        /// The `main_token` field is the `{` token.
        block_two,
        /// Same as `block_two` except there is known to be a trailing
        /// comma before the final rbrace.
        block_two_semicolon,
        /// `{a b}`.
        ///
        /// The `data` field is a `.extra_range` that stores a `Node.Index` for
        /// each statement.
        ///
        /// The `main_token` field is the `{` token.
        block,
        /// Same as `block` except there is known to be a trailing comma before
        /// the final rbrace.
        block_semicolon,
    };

    pub const Data = union {
        node: Index,
        opt_node: OptionalIndex,
        token: TokenIndex,
        opt_token: OptionalTokenIndex,
        node_and_node: struct { Index, Index },
        opt_node_and_opt_node: struct { OptionalIndex, OptionalIndex },
        node_and_opt_node: struct { Index, OptionalIndex },
        opt_node_and_node: struct { OptionalIndex, Index },
        node_and_extra: struct { Index, ExtraIndex },
        extra_and_node: struct { ExtraIndex, Index },
        extra_and_opt_node: struct { ExtraIndex, OptionalIndex },
        node_and_token: struct { Index, TokenIndex },
        token_and_node: struct { TokenIndex, Index },
        token_and_token: struct { TokenIndex, TokenIndex },
        opt_node_and_token: struct { OptionalIndex, TokenIndex },
        opt_token_and_node: struct { OptionalTokenIndex, Index },
        opt_token_and_opt_node: struct { OptionalTokenIndex, OptionalIndex },
        opt_token_and_opt_token: struct { OptionalTokenIndex, OptionalTokenIndex },
        extra_range: SubRange,
    };

    pub const SubRange = struct {
        /// Index into extra_data.
        start: ExtraIndex,
        /// Index into extra_data.
        end: ExtraIndex,
    };

    pub const Ternary = struct {
        then_expr: Node.Index,
        else_expr: Node.Index,
    };

    pub const If = struct {
        init: OptionalIndex,
        then_block: Index,
        else_block: OptionalIndex,
    };

    pub const For = struct {
        init: OptionalIndex,
        cont: OptionalIndex,
        then_block: Index,
        else_block: OptionalIndex,
    };
};

pub fn nodeToSpan(tree: *const Ast, node: Ast.Node.Index) Span {
    return tokensToSpan(
        tree,
        tree.firstToken(node),
        tree.lastToken(node),
        tree.nodeMainToken(node),
    );
}

pub fn tokenToSpan(tree: *const Ast, token: Ast.TokenIndex) Span {
    return tokensToSpan(tree, token, token, token);
}

pub fn tokensToSpan(tree: *const Ast, start: Ast.TokenIndex, end: Ast.TokenIndex, main: Ast.TokenIndex) Span {
    var start_tok = start;
    var end_tok = end;

    if (tree.tokensOnSameLine(start, end)) {
        // do nothing
    } else if (tree.tokensOnSameLine(start, main)) {
        end_tok = main;
    } else if (tree.tokensOnSameLine(main, end)) {
        start_tok = main;
    } else {
        start_tok = main;
        end_tok = main;
    }
    const start_off = tree.tokenStart(start_tok);
    const end_off = tree.tokenStart(end_tok) + @as(u32, @intCast(tree.tokenSlice(end_tok).len));
    return Span{ .start = start_off, .end = end_off, .main = tree.tokenStart(main) };
}
