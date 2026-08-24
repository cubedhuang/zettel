const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Token = struct {
    tag: Tag,
    loc: Loc,

    pub const Loc = struct {
        start: usize,
        end: usize,
    };

    pub const keywords = std.StaticStringMap(Tag).initComptime(.{
        .{ "and", .keyword_and },
        .{ "break", .keyword_break },
        .{ "catch", .keyword_catch },
        .{ "class", .keyword_class },
        .{ "continue", .keyword_continue },
        .{ "else", .keyword_else },
        .{ "enum", .keyword_enum },
        .{ "false", .keyword_false },
        .{ "fn", .keyword_fn },
        .{ "for", .keyword_for },
        .{ "if", .keyword_if },
        .{ "import", .keyword_import },
        .{ "nil", .keyword_nil },
        .{ "or", .keyword_or },
        .{ "pub", .keyword_pub },
        .{ "return", .keyword_return },
        .{ "switch", .keyword_switch },
        .{ "true", .keyword_true },
        .{ "try", .keyword_try },
    });

    pub fn getKeyword(bytes: []const u8) ?Tag {
        return keywords.get(bytes);
    }

    pub const Tag = enum {
        invalid,
        identifier,
        literal_string,
        literal_multiline_string_line,
        literal_number,
        eof,
        builtin,
        bang,
        pipe,
        pipe_pipe,
        pipe_equal,
        equal,
        equal_equal,
        equal_angle_bracket_right,
        bang_equal,
        l_paren,
        r_paren,
        semicolon,
        newline,
        percent,
        percent_equal,
        l_brace,
        r_brace,
        l_bracket,
        r_bracket,
        period,
        period_asterisk,
        ellipsis2,
        ellipsis3,
        caret,
        caret_equal,
        plus,
        plus_plus,
        plus_equal,
        plus_percent,
        plus_percent_equal,
        plus_pipe,
        plus_pipe_equal,
        minus,
        minus_equal,
        minus_percent,
        minus_percent_equal,
        minus_pipe,
        minus_pipe_equal,
        asterisk,
        asterisk_equal,
        asterisk_percent,
        asterisk_percent_equal,
        asterisk_pipe,
        asterisk_pipe_equal,
        arrow,
        colon,
        colon_equal,
        slash,
        slash_equal,
        comma,
        ampersand,
        ampersand_equal,
        question_mark,
        angle_bracket_left,
        angle_bracket_left_equal,
        angle_bracket_angle_bracket_left,
        angle_bracket_angle_bracket_left_equal,
        angle_bracket_angle_bracket_left_pipe,
        angle_bracket_angle_bracket_left_pipe_equal,
        angle_bracket_right,
        angle_bracket_right_equal,
        angle_bracket_angle_bracket_right,
        angle_bracket_angle_bracket_right_equal,
        tilde,
        doc_comment,
        container_doc_comment,
        keyword_and,
        keyword_break,
        keyword_catch,
        keyword_class,
        keyword_continue,
        keyword_else,
        keyword_enum,
        keyword_false,
        keyword_fn,
        keyword_for,
        keyword_if,
        keyword_import,
        keyword_nil,
        keyword_or,
        keyword_pub,
        keyword_return,
        keyword_switch,
        keyword_true,
        keyword_try,

        pub fn lexeme(tag: Tag) ?[]const u8 {
            return switch (tag) {
                .invalid,
                .identifier,
                .literal_string,
                .literal_multiline_string_line,
                .literal_number,
                .eof,
                .builtin,
                .doc_comment,
                .container_doc_comment,
                => null,

                .bang => "!",
                .pipe => "|",
                .pipe_pipe => "||",
                .pipe_equal => "|=",
                .equal => "=",
                .equal_equal => "==",
                .equal_angle_bracket_right => "=>",
                .bang_equal => "!=",
                .l_paren => "(",
                .r_paren => ")",
                .semicolon => ";",
                .newline => "\n",
                .percent => "%",
                .percent_equal => "%=",
                .l_brace => "{",
                .r_brace => "}",
                .l_bracket => "[",
                .r_bracket => "]",
                .period => ".",
                .period_asterisk => ".*",
                .ellipsis2 => "..",
                .ellipsis3 => "...",
                .caret => "^",
                .caret_equal => "^=",
                .plus => "+",
                .plus_plus => "++",
                .plus_equal => "+=",
                .plus_percent => "+%",
                .plus_percent_equal => "+%=",
                .plus_pipe => "+|",
                .plus_pipe_equal => "+|=",
                .minus => "-",
                .minus_equal => "-=",
                .minus_percent => "-%",
                .minus_percent_equal => "-%=",
                .minus_pipe => "-|",
                .minus_pipe_equal => "-|=",
                .asterisk => "*",
                .asterisk_equal => "*=",
                .asterisk_percent => "*%",
                .asterisk_percent_equal => "*%=",
                .asterisk_pipe => "*|",
                .asterisk_pipe_equal => "*|=",
                .arrow => "->",
                .colon => ":",
                .colon_equal => ":=",
                .slash => "/",
                .slash_equal => "/=",
                .comma => ",",
                .ampersand => "&",
                .ampersand_equal => "&=",
                .question_mark => "?",
                .angle_bracket_left => "<",
                .angle_bracket_left_equal => "<=",
                .angle_bracket_angle_bracket_left => "<<",
                .angle_bracket_angle_bracket_left_equal => "<<=",
                .angle_bracket_angle_bracket_left_pipe => "<<|",
                .angle_bracket_angle_bracket_left_pipe_equal => "<<|=",
                .angle_bracket_right => ">",
                .angle_bracket_right_equal => ">=",
                .angle_bracket_angle_bracket_right => ">>",
                .angle_bracket_angle_bracket_right_equal => ">>=",
                .tilde => "~",
                .keyword_and => "and",
                .keyword_break => "break",
                .keyword_catch => "catch",
                .keyword_class => "class",
                .keyword_continue => "continue",
                .keyword_else => "else",
                .keyword_enum => "enum",
                .keyword_false => "false",
                .keyword_fn => "fn",
                .keyword_for => "for",
                .keyword_if => "if",
                .keyword_import => "import",
                .keyword_nil => "nil",
                .keyword_or => "or",
                .keyword_pub => "pub",
                .keyword_return => "return",
                .keyword_switch => "switch",
                .keyword_true => "true",
                .keyword_try => "try",
            };
        }

        pub fn symbol(tag: Tag) []const u8 {
            if (tag == .newline) return "a newline";
            return tag.lexeme() orelse switch (tag) {
                .invalid => "invalid token",
                .identifier => "an identifier",
                .literal_string => "a string literal",
                .literal_multiline_string_line => "a multiline string literal",
                .literal_number => "a number literal",
                .eof => "EOF",
                .builtin => "a builtin function",
                .doc_comment, .container_doc_comment => "a document comment",
                else => unreachable,
            };
        }
    };
};

pub const ByteOffset = u32;

pub const TokenList = std.MultiArrayList(struct {
    tag: Token.Tag,
    start: ByteOffset,
});

pub const Tokenizer = struct {
    buffer: [:0]const u8,
    index: usize,
    /// Whether the previous token allows a following newline to insert a newline token.
    allow_semicolon: bool = false,
    paren_depth: usize = 0,

    fn init(buffer: [:0]const u8) Tokenizer {
        // Skip the UTF-8 BOM if present.
        return .{
            .buffer = buffer,
            .index = if (std.mem.startsWith(u8, buffer, "\xEF\xBB\xBF")) 3 else 0,
        };
    }

    /// Passes ownership of tokens to caller. `tokens.deinit` must be called when done. The final token will
    /// have tag `.eof`.
    pub fn tokenize(gpa: Allocator, buffer: [:0]const u8) !TokenList {
        var self: Tokenizer = .init(buffer);

        var tokens: TokenList = .empty;
        while (true) {
            const token = self.next();
            // If the next token unambiguously cannot appear at the beginning of a line
            // unless it's the continuation of the previous line, remove preceding newline
            // tokens.
            switch (token.tag) {
                .period, .keyword_and, .keyword_or => {
                    var count = tokens.len;
                    while (count >= 0 and tokens.items(.tag)[count - 1] == .newline) {
                        count -= 1;
                    }
                    tokens.shrinkRetainingCapacity(count);
                },
                else => {},
            }
            try tokens.append(gpa, .{
                .tag = token.tag,
                .start = @intCast(token.loc.start),
            });
            if (token.tag == .eof) break;
        }
        return tokens;
    }

    const State = enum {
        start,
        expect_newline,
        identifier,
        builtin,
        literal_string,
        literal_string_backslash,
        literal_multiline_string_line,
        backslash,
        equal,
        bang,
        pipe,
        minus,
        minus_percent,
        minus_pipe,
        asterisk,
        asterisk_percent,
        asterisk_pipe,
        slash,
        line_comment_start,
        line_comment,
        doc_comment_start,
        doc_comment,
        int,
        int_exponent,
        int_period,
        float,
        float_exponent,
        colon,
        ampersand,
        caret,
        percent,
        plus,
        plus_percent,
        plus_pipe,
        angle_bracket_left,
        angle_bracket_angle_bracket_left,
        angle_bracket_angle_bracket_left_pipe,
        angle_bracket_right,
        angle_bracket_angle_bracket_right,
        period,
        period_2,
        saw_at_sign,
        invalid,
    };

    /// After this returns invalid, it will reset on the next newline, returning tokens starting from there.
    /// An eof token will always be returned at the end.
    pub fn next(self: *Tokenizer) Token {
        var result: Token = .{
            .tag = undefined,
            .loc = .{
                .start = self.index,
                .end = undefined,
            },
        };
        state: switch (State.start) {
            .start => switch (self.buffer[self.index]) {
                0 => {
                    if (self.index == self.buffer.len) {
                        return .{
                            .tag = .eof,
                            .loc = .{
                                .start = self.index,
                                .end = self.index,
                            },
                        };
                    } else {
                        continue :state .invalid;
                    }
                },
                ' ', '\t', '\r' => {
                    self.index += 1;
                    result.loc.start = self.index;
                    continue :state .start;
                },
                '\n' => {
                    self.index += 1;
                    if (self.allow_semicolon and self.paren_depth == 0) {
                        result.tag = .newline;
                    } else {
                        continue :state .start;
                    }
                },
                '"' => {
                    result.tag = .literal_string;
                    continue :state .literal_string;
                },
                'a'...'z', 'A'...'Z', '_' => {
                    result.tag = .identifier;
                    continue :state .identifier;
                },
                '@' => continue :state .saw_at_sign,
                '=' => continue :state .equal,
                '!' => continue :state .bang,
                '|' => continue :state .pipe,
                '(' => {
                    result.tag = .l_paren;
                    self.index += 1;
                    self.paren_depth += 1;
                },
                ')' => {
                    result.tag = .r_paren;
                    self.index += 1;
                    self.paren_depth -|= 1;
                },
                '[' => {
                    result.tag = .l_bracket;
                    self.index += 1;
                    self.paren_depth += 1;
                },
                ']' => {
                    result.tag = .r_bracket;
                    self.index += 1;
                    self.paren_depth -|= 1;
                },
                ';' => {
                    result.tag = .semicolon;
                    self.index += 1;
                },
                ',' => {
                    result.tag = .comma;
                    self.index += 1;
                },
                '?' => {
                    result.tag = .question_mark;
                    self.index += 1;
                },
                '%' => continue :state .percent,
                '*' => continue :state .asterisk,
                '+' => continue :state .plus,
                '<' => continue :state .angle_bracket_left,
                '>' => continue :state .angle_bracket_right,
                '^' => continue :state .caret,
                '\\' => {
                    result.tag = .literal_multiline_string_line;
                    continue :state .backslash;
                },
                '{' => {
                    result.tag = .l_brace;
                    self.index += 1;
                },
                '}' => {
                    result.tag = .r_brace;
                    self.index += 1;
                },
                '~' => {
                    result.tag = .tilde;
                    self.index += 1;
                },
                '.' => continue :state .period,
                '-' => continue :state .minus,
                ':' => continue :state .colon,
                '/' => continue :state .slash,
                '&' => continue :state .ampersand,
                '0'...'9' => {
                    result.tag = .literal_number;
                    self.index += 1;
                    continue :state .int;
                },
                else => continue :state .invalid,
            },

            .expect_newline => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    0 => {
                        if (self.index == self.buffer.len) {
                            result.tag = .invalid;
                        } else {
                            continue :state .invalid;
                        }
                    },
                    '\n' => {
                        self.index += 1;
                        result.loc.start = self.index;
                        continue :state .start;
                    },
                    else => continue :state .invalid,
                }
            },

            .invalid => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    0 => if (self.index == self.buffer.len) {
                        result.tag = .invalid;
                    } else {
                        continue :state .invalid;
                    },
                    '\n' => result.tag = .invalid,
                    else => continue :state .invalid,
                }
            },

            .saw_at_sign => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    0, '\n' => result.tag = .invalid,
                    '"' => {
                        result.tag = .identifier;
                        continue :state .literal_string;
                    },
                    'a'...'z', 'A'...'Z', '_' => {
                        result.tag = .builtin;
                        continue :state .builtin;
                    },
                    else => continue :state .invalid,
                }
            },

            .colon => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '=' => {
                        result.tag = .colon_equal;
                        self.index += 1;
                    },
                    else => result.tag = .colon,
                }
            },

            .ampersand => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '=' => {
                        result.tag = .ampersand_equal;
                        self.index += 1;
                    },
                    else => result.tag = .ampersand,
                }
            },

            .asterisk => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '=' => {
                        result.tag = .asterisk_equal;
                        self.index += 1;
                    },
                    '%' => continue :state .asterisk_percent,
                    '|' => continue :state .asterisk_pipe,
                    else => result.tag = .asterisk,
                }
            },

            .asterisk_percent => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '=' => {
                        result.tag = .asterisk_percent_equal;
                        self.index += 1;
                    },
                    else => result.tag = .asterisk_percent,
                }
            },

            .asterisk_pipe => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '=' => {
                        result.tag = .asterisk_pipe_equal;
                        self.index += 1;
                    },
                    else => result.tag = .asterisk_pipe,
                }
            },

            .percent => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '=' => {
                        result.tag = .percent_equal;
                        self.index += 1;
                    },
                    else => result.tag = .percent,
                }
            },

            .plus => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '=' => {
                        result.tag = .plus_equal;
                        self.index += 1;
                    },
                    '+' => {
                        result.tag = .plus_plus;
                        self.index += 1;
                    },
                    '%' => continue :state .plus_percent,
                    '|' => continue :state .plus_pipe,
                    else => result.tag = .plus,
                }
            },

            .plus_percent => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '=' => {
                        result.tag = .plus_percent_equal;
                        self.index += 1;
                    },
                    else => result.tag = .plus_percent,
                }
            },

            .plus_pipe => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '=' => {
                        result.tag = .plus_pipe_equal;
                        self.index += 1;
                    },
                    else => result.tag = .plus_pipe,
                }
            },

            .caret => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '=' => {
                        result.tag = .caret_equal;
                        self.index += 1;
                    },
                    else => result.tag = .caret,
                }
            },

            .identifier => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    'a'...'z', 'A'...'Z', '_', '0'...'9' => continue :state .identifier,
                    else => {
                        const ident = self.buffer[result.loc.start..self.index];
                        if (Token.getKeyword(ident)) |tag| {
                            result.tag = tag;
                        }
                    },
                }
            },
            .builtin => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    'a'...'z', 'A'...'Z', '_', '0'...'9' => continue :state .builtin,
                    else => {},
                }
            },
            .backslash => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    0 => result.tag = .invalid,
                    '\\' => continue :state .literal_multiline_string_line,
                    '\n' => result.tag = .invalid,
                    else => continue :state .invalid,
                }
            },
            .literal_string => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    0 => {
                        if (self.index != self.buffer.len) {
                            continue :state .invalid;
                        } else {
                            result.tag = .invalid;
                        }
                    },
                    '\n' => result.tag = .invalid,
                    '\\' => continue :state .literal_string_backslash,
                    '"' => self.index += 1,
                    0x01...0x09, 0x0b...0x1f, 0x7f => {
                        continue :state .invalid;
                    },
                    else => continue :state .literal_string,
                }
            },

            .literal_string_backslash => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    0, '\n' => result.tag = .invalid,
                    0x01...0x09, 0x0b...0x1f, 0x7f => {
                        continue :state .invalid;
                    },
                    else => continue :state .literal_string,
                }
            },

            .literal_multiline_string_line => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    0 => if (self.index != self.buffer.len) {
                        continue :state .invalid;
                    },
                    '\n' => {},
                    '\r' => if (self.buffer[self.index + 1] != '\n') {
                        continue :state .invalid;
                    },
                    0x01...0x09, 0x0b...0x0c, 0x0e...0x1f, 0x7f => continue :state .invalid,
                    else => continue :state .literal_multiline_string_line,
                }
            },

            .bang => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '=' => {
                        result.tag = .bang_equal;
                        self.index += 1;
                    },
                    else => result.tag = .bang,
                }
            },

            .pipe => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '=' => {
                        result.tag = .pipe_equal;
                        self.index += 1;
                    },
                    '|' => {
                        result.tag = .pipe_pipe;
                        self.index += 1;
                    },
                    else => result.tag = .pipe,
                }
            },

            .equal => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '=' => {
                        result.tag = .equal_equal;
                        self.index += 1;
                    },
                    '>' => {
                        result.tag = .equal_angle_bracket_right;
                        self.index += 1;
                    },
                    else => result.tag = .equal,
                }
            },

            .minus => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '>' => {
                        result.tag = .arrow;
                        self.index += 1;
                    },
                    '=' => {
                        result.tag = .minus_equal;
                        self.index += 1;
                    },
                    '%' => continue :state .minus_percent,
                    '|' => continue :state .minus_pipe,
                    else => result.tag = .minus,
                }
            },

            .minus_percent => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '=' => {
                        result.tag = .minus_percent_equal;
                        self.index += 1;
                    },
                    else => result.tag = .minus_percent,
                }
            },
            .minus_pipe => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '=' => {
                        result.tag = .minus_pipe_equal;
                        self.index += 1;
                    },
                    else => result.tag = .minus_pipe,
                }
            },

            .angle_bracket_left => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '<' => continue :state .angle_bracket_angle_bracket_left,
                    '=' => {
                        result.tag = .angle_bracket_left_equal;
                        self.index += 1;
                    },
                    else => result.tag = .angle_bracket_left,
                }
            },

            .angle_bracket_angle_bracket_left => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '=' => {
                        result.tag = .angle_bracket_angle_bracket_left_equal;
                        self.index += 1;
                    },
                    '|' => continue :state .angle_bracket_angle_bracket_left_pipe,
                    else => result.tag = .angle_bracket_angle_bracket_left,
                }
            },

            .angle_bracket_angle_bracket_left_pipe => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '=' => {
                        result.tag = .angle_bracket_angle_bracket_left_pipe_equal;
                        self.index += 1;
                    },
                    else => result.tag = .angle_bracket_angle_bracket_left_pipe,
                }
            },

            .angle_bracket_right => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '>' => continue :state .angle_bracket_angle_bracket_right,
                    '=' => {
                        result.tag = .angle_bracket_right_equal;
                        self.index += 1;
                    },
                    else => result.tag = .angle_bracket_right,
                }
            },

            .angle_bracket_angle_bracket_right => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '=' => {
                        result.tag = .angle_bracket_angle_bracket_right_equal;
                        self.index += 1;
                    },
                    else => result.tag = .angle_bracket_angle_bracket_right,
                }
            },

            .period => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '.' => continue :state .period_2,
                    '*' => {
                        result.tag = .period_asterisk;
                        self.index += 1;
                    },
                    else => result.tag = .period,
                }
            },

            .period_2 => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '.' => {
                        result.tag = .ellipsis3;
                        self.index += 1;
                    },
                    else => result.tag = .ellipsis2,
                }
            },

            .slash => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '/' => continue :state .line_comment_start,
                    '=' => {
                        result.tag = .slash_equal;
                        self.index += 1;
                    },
                    else => result.tag = .slash,
                }
            },
            .line_comment_start => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    0 => {
                        if (self.index != self.buffer.len) {
                            continue :state .invalid;
                        } else return .{
                            .tag = .eof,
                            .loc = .{
                                .start = self.index,
                                .end = self.index,
                            },
                        };
                    },
                    '!' => {
                        result.tag = .container_doc_comment;
                        continue :state .doc_comment;
                    },
                    '\n' => {
                        self.index += 1;
                        result.loc.start = self.index;
                        continue :state .start;
                    },
                    '/' => continue :state .doc_comment_start,
                    '\r' => continue :state .expect_newline,
                    0x01...0x09, 0x0b...0x0c, 0x0e...0x1f, 0x7f => {
                        continue :state .invalid;
                    },
                    else => continue :state .line_comment,
                }
            },
            .doc_comment_start => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    0, '\n' => result.tag = .doc_comment,
                    '\r' => {
                        if (self.buffer[self.index + 1] == '\n') {
                            result.tag = .doc_comment;
                        } else {
                            continue :state .invalid;
                        }
                    },
                    '/' => continue :state .line_comment,
                    0x01...0x09, 0x0b...0x0c, 0x0e...0x1f, 0x7f => {
                        continue :state .invalid;
                    },
                    else => {
                        result.tag = .doc_comment;
                        continue :state .doc_comment;
                    },
                }
            },
            .line_comment => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    0 => {
                        if (self.index != self.buffer.len) {
                            continue :state .invalid;
                        } else return .{
                            .tag = .eof,
                            .loc = .{
                                .start = self.index,
                                .end = self.index,
                            },
                        };
                    },
                    '\n' => {
                        self.index += 1;
                        result.loc.start = self.index;
                        continue :state .start;
                    },
                    '\r' => continue :state .expect_newline,
                    0x01...0x09, 0x0b...0x0c, 0x0e...0x1f, 0x7f => {
                        continue :state .invalid;
                    },
                    else => continue :state .line_comment,
                }
            },
            .doc_comment => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    0, '\n' => {},
                    '\r' => if (self.buffer[self.index + 1] != '\n') {
                        continue :state .invalid;
                    },
                    0x01...0x09, 0x0b...0x0c, 0x0e...0x1f, 0x7f => {
                        continue :state .invalid;
                    },
                    else => continue :state .doc_comment,
                }
            },
            .int => switch (self.buffer[self.index]) {
                '.' => continue :state .int_period,
                '_', 'a'...'d', 'f'...'o', 'q'...'z', 'A'...'D', 'F'...'O', 'Q'...'Z', '0'...'9' => {
                    self.index += 1;
                    continue :state .int;
                },
                'e', 'E', 'p', 'P' => {
                    continue :state .int_exponent;
                },
                else => {},
            },
            .int_exponent => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '-', '+' => {
                        self.index += 1;
                        continue :state .float;
                    },
                    else => continue :state .int,
                }
            },
            .int_period => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '_', 'a'...'d', 'f'...'o', 'q'...'z', 'A'...'D', 'F'...'O', 'Q'...'Z', '0'...'9' => {
                        self.index += 1;
                        continue :state .float;
                    },
                    'e', 'E', 'p', 'P' => {
                        continue :state .float_exponent;
                    },
                    else => self.index -= 1,
                }
            },
            .float => switch (self.buffer[self.index]) {
                '_', 'a'...'d', 'f'...'o', 'q'...'z', 'A'...'D', 'F'...'O', 'Q'...'Z', '0'...'9' => {
                    self.index += 1;
                    continue :state .float;
                },
                'e', 'E', 'p', 'P' => {
                    continue :state .float_exponent;
                },
                else => {},
            },
            .float_exponent => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '-', '+' => {
                        self.index += 1;
                        continue :state .float;
                    },
                    else => continue :state .float,
                }
            },
        }

        switch (result.tag) {
            .identifier,
            .literal_string,
            .literal_number,
            .builtin,
            .r_paren,
            .r_brace,
            .r_bracket,
            .keyword_break,
            .keyword_continue,
            .keyword_return,
            .keyword_false,
            .keyword_true,
            .keyword_nil,
            => self.allow_semicolon = true,
            else => self.allow_semicolon = false,
        }

        result.loc.end = self.index;
        return result;
    }
};

test "keywords" {
    try testTokenize("class fn else", &.{ .keyword_class, .keyword_fn, .keyword_else });
}

test "line comment followed by top-level class and newline" {
    try testTokenize(
        \\// line comment
        \\class Hi {}
        \\
    , &.{
        .keyword_class,
        .identifier,
        .l_brace,
        .r_brace,
        .newline,
    });
}

test "unknown length pointer and then c pointer with newline" {
    try testTokenize(
        \\[*]u8
        \\[*c]u8
    , &.{
        .l_bracket,
        .asterisk,
        .r_bracket,
        .identifier,
        .newline,
        .l_bracket,
        .asterisk,
        .identifier,
        .r_bracket,
        .identifier,
    });
}

test "code point literal with hex escape" {
    try testTokenize(
        \\"\x1b"
    , &.{.literal_string});
    try testTokenize(
        \\"\x1"
    , &.{.literal_string});
}

test "newline in char literal" {
    try testTokenize(
        \\'
        \\'
    , &.{ .invalid, .invalid });
}

test "newline in string literal" {
    try testTokenize(
        \\"
        \\"
    , &.{ .invalid, .invalid });
}

test "code point literal with unicode escapes" {
    // Valid unicode escapes
    try testTokenize(
        \\"\u{3}"
    , &.{.literal_string});
    try testTokenize(
        \\"\u{01}"
    , &.{.literal_string});
    try testTokenize(
        \\"\u{2a}"
    , &.{.literal_string});
    try testTokenize(
        \\"\u{3f9}"
    , &.{.literal_string});
    try testTokenize(
        \\"\u{6E09aBc1523}"
    , &.{.literal_string});
    try testTokenize(
        \\"\u{440}"
    , &.{.literal_string});

    // Invalid unicode escapes
    try testTokenize(
        \\"\u"
    , &.{.literal_string});
    try testTokenize(
        \\"\u{{"
    , &.{.literal_string});
    try testTokenize(
        \\"\u{}"
    , &.{.literal_string});
    try testTokenize(
        \\"\u{s}"
    , &.{.literal_string});
    try testTokenize(
        \\"\u{2z}"
    , &.{.literal_string});
    try testTokenize(
        \\"\u{4a"
    , &.{.literal_string});

    // Test old-style unicode literals
    try testTokenize(
        \\"\u0333"
    , &.{.literal_string});
    try testTokenize(
        \\"\U0333"
    , &.{.literal_string});
}

test "code point literal with unicode code point" {
    try testTokenize(
        \\"💩"
    , &.{.literal_string});
}

test "float literal e exponent" {
    try testTokenize("a = 4.94065645841246544177e-324;\n", &.{
        .identifier,
        .equal,
        .literal_number,
        .semicolon,
    });
}

test "float literal p exponent" {
    try testTokenize("a = 0x1.a827999fcef32p+1022;\n", &.{
        .identifier,
        .equal,
        .literal_number,
        .semicolon,
    });
}

test "invalid token characters" {
    try testTokenize("#", &.{.invalid});
    try testTokenize("`", &.{.invalid});
    try testTokenize("'c", &.{.invalid});
    try testTokenize("'", &.{.invalid});
    try testTokenize("'\n'", &.{ .invalid, .invalid });
}

test "invalid literal/comment characters" {
    try testTokenize("\"\x00\"", &.{.invalid});
    try testTokenize("`\x00`", &.{.invalid});
    try testTokenize("//\x00", &.{.invalid});
    try testTokenize("//\x1f", &.{.invalid});
    try testTokenize("//\x7f", &.{.invalid});
}

test "utf8" {
    try testTokenize("//\xc2\x80", &.{});
    try testTokenize("//\xf4\x8f\xbf\xbf", &.{});
}

test "invalid utf8" {
    try testTokenize("//\x80", &.{});
    try testTokenize("//\xbf", &.{});
    try testTokenize("//\xf8", &.{});
    try testTokenize("//\xff", &.{});
    try testTokenize("//\xc2\xc0", &.{});
    try testTokenize("//\xe0", &.{});
    try testTokenize("//\xf0", &.{});
    try testTokenize("//\xf0\x90\x80\xc0", &.{});
}

test "illegal unicode codepoints" {
    // unicode newline characters.U+0085, U+2028, U+2029
    try testTokenize("//\xc2\x84", &.{});
    try testTokenize("//\xc2\x85", &.{});
    try testTokenize("//\xc2\x86", &.{});
    try testTokenize("//\xe2\x80\xa7", &.{});
    try testTokenize("//\xe2\x80\xa8", &.{});
    try testTokenize("//\xe2\x80\xa9", &.{});
    try testTokenize("//\xe2\x80\xaa", &.{});
}

test "string identifier and builtin fns" {
    try testTokenize(
        \\class @"if" = @import("std");
    , &.{
        .keyword_class,
        .identifier,
        .equal,
        .builtin,
        .l_paren,
        .literal_string,
        .r_paren,
        .semicolon,
    });
}

test "pipe and then invalid" {
    try testTokenize("||=", &.{
        .pipe_pipe,
        .equal,
    });
}

test "line comment and doc comment" {
    try testTokenize("//", &.{});
    try testTokenize("// a / b", &.{});
    try testTokenize("// /", &.{});
    try testTokenize("/// a", &.{.doc_comment});
    try testTokenize("///", &.{.doc_comment});
    try testTokenize("////", &.{});
    try testTokenize("//!", &.{.container_doc_comment});
    try testTokenize("//!!", &.{.container_doc_comment});
}

test "line comment followed by identifier" {
    try testTokenize(
        \\    Unexpected,
        \\    // another
        \\    Another,
    , &.{
        .identifier,
        .comma,
        .identifier,
        .comma,
    });
}

test "UTF-8 BOM is recognized and skipped" {
    try testTokenize("\xEF\xBB\xBFa;\n", &.{
        .identifier,
        .semicolon,
    });
}

test "correctly parse pointer assignment" {
    try testTokenize("b.*=3;\n", &.{
        .identifier,
        .period_asterisk,
        .equal,
        .literal_number,
        .semicolon,
    });
}

test "range literals" {
    try testTokenize("0...9", &.{ .literal_number, .ellipsis3, .literal_number });
    try testTokenize("0x00...0x09", &.{ .literal_number, .ellipsis3, .literal_number });
    try testTokenize("0b00...0b11", &.{ .literal_number, .ellipsis3, .literal_number });
    try testTokenize("0o00...0o11", &.{ .literal_number, .ellipsis3, .literal_number });
}

test "number literals decimal" {
    try testTokenize("0", &.{.literal_number});
    try testTokenize("1", &.{.literal_number});
    try testTokenize("2", &.{.literal_number});
    try testTokenize("3", &.{.literal_number});
    try testTokenize("4", &.{.literal_number});
    try testTokenize("5", &.{.literal_number});
    try testTokenize("6", &.{.literal_number});
    try testTokenize("7", &.{.literal_number});
    try testTokenize("8", &.{.literal_number});
    try testTokenize("9", &.{.literal_number});
    try testTokenize("1..", &.{ .literal_number, .ellipsis2 });
    try testTokenize("0a", &.{.literal_number});
    try testTokenize("9b", &.{.literal_number});
    try testTokenize("1z", &.{.literal_number});
    try testTokenize("1z_1", &.{.literal_number});
    try testTokenize("9z3", &.{.literal_number});

    try testTokenize("0_0", &.{.literal_number});
    try testTokenize("0001", &.{.literal_number});
    try testTokenize("01234567890", &.{.literal_number});
    try testTokenize("012_345_6789_0", &.{.literal_number});
    try testTokenize("0_1_2_3_4_5_6_7_8_9_0", &.{.literal_number});

    try testTokenize("00_", &.{.literal_number});
    try testTokenize("0_0_", &.{.literal_number});
    try testTokenize("0__0", &.{.literal_number});
    try testTokenize("0_0f", &.{.literal_number});
    try testTokenize("0_0_f", &.{.literal_number});
    try testTokenize("0_0_f_00", &.{.literal_number});
    try testTokenize("1_,", &.{ .literal_number, .comma });

    try testTokenize("0.0", &.{.literal_number});
    try testTokenize("1.0", &.{.literal_number});
    try testTokenize("10.0", &.{.literal_number});
    try testTokenize("0e0", &.{.literal_number});
    try testTokenize("1e0", &.{.literal_number});
    try testTokenize("1e100", &.{.literal_number});
    try testTokenize("1.0e100", &.{.literal_number});
    try testTokenize("1.0e+100", &.{.literal_number});
    try testTokenize("1.0e-100", &.{.literal_number});
    try testTokenize("1_0_0_0.0_0_0_0_0_1e1_0_0_0", &.{.literal_number});

    try testTokenize("1.", &.{ .literal_number, .period });
    try testTokenize("1e", &.{.literal_number});
    try testTokenize("1.e100", &.{.literal_number});
    try testTokenize("1.0e1f0", &.{.literal_number});
    try testTokenize("1.0p100", &.{.literal_number});
    try testTokenize("1.0p-100", &.{.literal_number});
    try testTokenize("1.0p1f0", &.{.literal_number});
    try testTokenize("1.0_,", &.{ .literal_number, .comma });
    try testTokenize("1_.0", &.{.literal_number});
    try testTokenize("1._", &.{.literal_number});
    try testTokenize("1.a", &.{.literal_number});
    try testTokenize("1.z", &.{.literal_number});
    try testTokenize("1._0", &.{.literal_number});
    try testTokenize("1.+", &.{ .literal_number, .period, .plus });
    try testTokenize("1._+", &.{ .literal_number, .plus });
    try testTokenize("1._e", &.{.literal_number});
    try testTokenize("1.0e", &.{.literal_number});
    try testTokenize("1.0e,", &.{ .literal_number, .comma });
    try testTokenize("1.0e_", &.{.literal_number});
    try testTokenize("1.0e+_", &.{.literal_number});
    try testTokenize("1.0e-_", &.{.literal_number});
    try testTokenize("1.0e0_+", &.{ .literal_number, .plus });
}

test "number literals binary" {
    try testTokenize("0b0", &.{.literal_number});
    try testTokenize("0b1", &.{.literal_number});
    try testTokenize("0b2", &.{.literal_number});
    try testTokenize("0b3", &.{.literal_number});
    try testTokenize("0b4", &.{.literal_number});
    try testTokenize("0b5", &.{.literal_number});
    try testTokenize("0b6", &.{.literal_number});
    try testTokenize("0b7", &.{.literal_number});
    try testTokenize("0b8", &.{.literal_number});
    try testTokenize("0b9", &.{.literal_number});
    try testTokenize("0ba", &.{.literal_number});
    try testTokenize("0bb", &.{.literal_number});
    try testTokenize("0bc", &.{.literal_number});
    try testTokenize("0bd", &.{.literal_number});
    try testTokenize("0be", &.{.literal_number});
    try testTokenize("0bf", &.{.literal_number});
    try testTokenize("0bz", &.{.literal_number});

    try testTokenize("0b0000_0000", &.{.literal_number});
    try testTokenize("0b1111_1111", &.{.literal_number});
    try testTokenize("0b10_10_10_10", &.{.literal_number});
    try testTokenize("0b0_1_0_1_0_1_0_1", &.{.literal_number});
    try testTokenize("0b1.", &.{ .literal_number, .period });
    try testTokenize("0b1.0", &.{.literal_number});

    try testTokenize("0B0", &.{.literal_number});
    try testTokenize("0b_", &.{.literal_number});
    try testTokenize("0b_0", &.{.literal_number});
    try testTokenize("0b1_", &.{.literal_number});
    try testTokenize("0b0__1", &.{.literal_number});
    try testTokenize("0b0_1_", &.{.literal_number});
    try testTokenize("0b1e", &.{.literal_number});
    try testTokenize("0b1p", &.{.literal_number});
    try testTokenize("0b1e0", &.{.literal_number});
    try testTokenize("0b1p0", &.{.literal_number});
    try testTokenize("0b1_,", &.{ .literal_number, .comma });
}

test "number literals octal" {
    try testTokenize("0o0", &.{.literal_number});
    try testTokenize("0o1", &.{.literal_number});
    try testTokenize("0o2", &.{.literal_number});
    try testTokenize("0o3", &.{.literal_number});
    try testTokenize("0o4", &.{.literal_number});
    try testTokenize("0o5", &.{.literal_number});
    try testTokenize("0o6", &.{.literal_number});
    try testTokenize("0o7", &.{.literal_number});
    try testTokenize("0o8", &.{.literal_number});
    try testTokenize("0o9", &.{.literal_number});
    try testTokenize("0oa", &.{.literal_number});
    try testTokenize("0ob", &.{.literal_number});
    try testTokenize("0oc", &.{.literal_number});
    try testTokenize("0od", &.{.literal_number});
    try testTokenize("0oe", &.{.literal_number});
    try testTokenize("0of", &.{.literal_number});
    try testTokenize("0oz", &.{.literal_number});

    try testTokenize("0o01234567", &.{.literal_number});
    try testTokenize("0o0123_4567", &.{.literal_number});
    try testTokenize("0o01_23_45_67", &.{.literal_number});
    try testTokenize("0o0_1_2_3_4_5_6_7", &.{.literal_number});
    try testTokenize("0o7.", &.{ .literal_number, .period });
    try testTokenize("0o7.0", &.{.literal_number});

    try testTokenize("0O0", &.{.literal_number});
    try testTokenize("0o_", &.{.literal_number});
    try testTokenize("0o_0", &.{.literal_number});
    try testTokenize("0o1_", &.{.literal_number});
    try testTokenize("0o0__1", &.{.literal_number});
    try testTokenize("0o0_1_", &.{.literal_number});
    try testTokenize("0o1e", &.{.literal_number});
    try testTokenize("0o1p", &.{.literal_number});
    try testTokenize("0o1e0", &.{.literal_number});
    try testTokenize("0o1p0", &.{.literal_number});
    try testTokenize("0o_,", &.{ .literal_number, .comma });
}

test "number literals hexadecimal" {
    try testTokenize("0x0", &.{.literal_number});
    try testTokenize("0x1", &.{.literal_number});
    try testTokenize("0x2", &.{.literal_number});
    try testTokenize("0x3", &.{.literal_number});
    try testTokenize("0x4", &.{.literal_number});
    try testTokenize("0x5", &.{.literal_number});
    try testTokenize("0x6", &.{.literal_number});
    try testTokenize("0x7", &.{.literal_number});
    try testTokenize("0x8", &.{.literal_number});
    try testTokenize("0x9", &.{.literal_number});
    try testTokenize("0xa", &.{.literal_number});
    try testTokenize("0xb", &.{.literal_number});
    try testTokenize("0xc", &.{.literal_number});
    try testTokenize("0xd", &.{.literal_number});
    try testTokenize("0xe", &.{.literal_number});
    try testTokenize("0xf", &.{.literal_number});
    try testTokenize("0xA", &.{.literal_number});
    try testTokenize("0xB", &.{.literal_number});
    try testTokenize("0xC", &.{.literal_number});
    try testTokenize("0xD", &.{.literal_number});
    try testTokenize("0xE", &.{.literal_number});
    try testTokenize("0xF", &.{.literal_number});
    try testTokenize("0x0z", &.{.literal_number});
    try testTokenize("0xz", &.{.literal_number});

    try testTokenize("0x0123456789ABCDEF", &.{.literal_number});
    try testTokenize("0x0123_4567_89AB_CDEF", &.{.literal_number});
    try testTokenize("0x01_23_45_67_89AB_CDE_F", &.{.literal_number});
    try testTokenize("0x0_1_2_3_4_5_6_7_8_9_A_B_C_D_E_F", &.{.literal_number});

    try testTokenize("0X0", &.{.literal_number});
    try testTokenize("0x_", &.{.literal_number});
    try testTokenize("0x_1", &.{.literal_number});
    try testTokenize("0x1_", &.{.literal_number});
    try testTokenize("0x0__1", &.{.literal_number});
    try testTokenize("0x0_1_", &.{.literal_number});
    try testTokenize("0x_,", &.{ .literal_number, .comma });

    try testTokenize("0x1.0", &.{.literal_number});
    try testTokenize("0xF.0", &.{.literal_number});
    try testTokenize("0xF.F", &.{.literal_number});
    try testTokenize("0xF.Fp0", &.{.literal_number});
    try testTokenize("0xF.FP0", &.{.literal_number});
    try testTokenize("0x1p0", &.{.literal_number});
    try testTokenize("0xfp0", &.{.literal_number});
    try testTokenize("0x1.0+0xF.0", &.{ .literal_number, .plus, .literal_number });

    try testTokenize("0x1.", &.{ .literal_number, .period });
    try testTokenize("0xF.", &.{ .literal_number, .period });
    try testTokenize("0x1.+0xF.", &.{ .literal_number, .period, .plus, .literal_number, .period });
    try testTokenize("0xff.p10", &.{.literal_number});

    try testTokenize("0x0123456.789ABCDEF", &.{.literal_number});
    try testTokenize("0x0_123_456.789_ABC_DEF", &.{.literal_number});
    try testTokenize("0x0_1_2_3_4_5_6.7_8_9_A_B_C_D_E_F", &.{.literal_number});
    try testTokenize("0x0p0", &.{.literal_number});
    try testTokenize("0x0.0p0", &.{.literal_number});
    try testTokenize("0xff.ffp10", &.{.literal_number});
    try testTokenize("0xff.ffP10", &.{.literal_number});
    try testTokenize("0xffp10", &.{.literal_number});
    try testTokenize("0xff_ff.ff_ffp1_0_0_0", &.{.literal_number});
    try testTokenize("0xf_f_f_f.f_f_f_fp+1_000", &.{.literal_number});
    try testTokenize("0xf_f_f_f.f_f_f_fp-1_00_0", &.{.literal_number});

    try testTokenize("0x1e", &.{.literal_number});
    try testTokenize("0x1e0", &.{.literal_number});
    try testTokenize("0x1p", &.{.literal_number});
    try testTokenize("0xfp0z1", &.{.literal_number});
    try testTokenize("0xff.ffpff", &.{.literal_number});
    try testTokenize("0x0.p", &.{.literal_number});
    try testTokenize("0x0.z", &.{.literal_number});
    try testTokenize("0x0._", &.{.literal_number});
    try testTokenize("0x0_.0", &.{.literal_number});
    try testTokenize("0x0_.0.0", &.{ .literal_number, .period, .literal_number });
    try testTokenize("0x0._0", &.{.literal_number});
    try testTokenize("0x0.0_", &.{.literal_number});
    try testTokenize("0x0_p0", &.{.literal_number});
    try testTokenize("0x0_.p0", &.{.literal_number});
    try testTokenize("0x0._p0", &.{.literal_number});
    try testTokenize("0x0.0_p0", &.{.literal_number});
    try testTokenize("0x0._0p0", &.{.literal_number});
    try testTokenize("0x0.0p_0", &.{.literal_number});
    try testTokenize("0x0.0p+_0", &.{.literal_number});
    try testTokenize("0x0.0p-_0", &.{.literal_number});
    try testTokenize("0x0.0p0_", &.{.literal_number});
}

test "multi line string literal with only 1 backslash" {
    try testTokenize("x \\\n;", &.{ .identifier, .invalid, .semicolon });
}

test "invalid builtin identifiers" {
    try testTokenize("@()", &.{.invalid});
    try testTokenize("@0()", &.{.invalid});
}

test "invalid token with unfinished escape right before eof" {
    try testTokenize("\"\\", &.{.invalid});
    try testTokenize("'\\", &.{.invalid});
    try testTokenize("'\\u", &.{.invalid});
}

test "saturating operators" {
    try testTokenize("<<", &.{.angle_bracket_angle_bracket_left});
    try testTokenize("<<|", &.{.angle_bracket_angle_bracket_left_pipe});
    try testTokenize("<<|=", &.{.angle_bracket_angle_bracket_left_pipe_equal});

    try testTokenize("*", &.{.asterisk});
    try testTokenize("*|", &.{.asterisk_pipe});
    try testTokenize("*|=", &.{.asterisk_pipe_equal});

    try testTokenize("+", &.{.plus});
    try testTokenize("+|", &.{.plus_pipe});
    try testTokenize("+|=", &.{.plus_pipe_equal});

    try testTokenize("-", &.{.minus});
    try testTokenize("-|", &.{.minus_pipe});
    try testTokenize("-|=", &.{.minus_pipe_equal});
}

test "null byte before eof" {
    try testTokenize("123 \x00 456", &.{ .literal_number, .invalid });
    try testTokenize("//\x00", &.{.invalid});
    try testTokenize("\\\\\x00", &.{.invalid});
    try testTokenize("\x00", &.{.invalid});
    try testTokenize("// NUL\x00\n", &.{.invalid});
    try testTokenize("///\x00\n", &.{ .doc_comment, .invalid });
    try testTokenize("/// NUL\x00\n", &.{ .doc_comment, .invalid });
}

test "invalid tabs and carriage returns" {
    // "Inside Line Comments and Documentation Comments, Any TAB is rejected by
    // the grammar since it is ambiguous how it should be rendered."
    // https://github.com/ziglang/zig-spec/issues/38
    try testTokenize("//\t", &.{.invalid});
    try testTokenize("// \t", &.{.invalid});
    try testTokenize("///\t", &.{.invalid});
    try testTokenize("/// \t", &.{.invalid});
    try testTokenize("//!\t", &.{.invalid});
    try testTokenize("//! \t", &.{.invalid});

    // "Inside Line Comments and Documentation Comments, CR directly preceding
    // NL is unambiguously part of the newline sequence. It is accepted by the
    // grammar and removed by zig fmt, leaving only NL. CR anywhere else is
    // rejected by the grammar."
    // https://github.com/ziglang/zig-spec/issues/38
    try testTokenize("//\r", &.{.invalid});
    try testTokenize("// \r", &.{.invalid});
    try testTokenize("///\r", &.{.invalid});
    try testTokenize("/// \r", &.{.invalid});
    try testTokenize("//\r ", &.{.invalid});
    try testTokenize("// \r ", &.{.invalid});
    try testTokenize("///\r ", &.{.invalid});
    try testTokenize("/// \r ", &.{.invalid});
    try testTokenize("//\r\n", &.{});
    try testTokenize("// \r\n", &.{});
    try testTokenize("///\r\n", &.{.doc_comment});
    try testTokenize("/// \r\n", &.{.doc_comment});
    try testTokenize("//!\r", &.{.invalid});
    try testTokenize("//! \r", &.{.invalid});
    try testTokenize("//!\r ", &.{.invalid});
    try testTokenize("//! \r ", &.{.invalid});
    try testTokenize("//!\r\n", &.{.container_doc_comment});
    try testTokenize("//! \r\n", &.{.container_doc_comment});

    // The control characters TAB and CR are rejected by the grammar inside multi-line string literals,
    // except if CR is directly before NL.
    // https://github.com/ziglang/zig-spec/issues/38
    try testTokenize("\\\\\r", &.{.invalid});
    try testTokenize("\\\\\r ", &.{.invalid});
    try testTokenize("\\\\ \r", &.{.invalid});
    try testTokenize("\\\\\t", &.{.invalid});
    try testTokenize("\\\\\t ", &.{.invalid});
    try testTokenize("\\\\ \t", &.{.invalid});
    try testTokenize("\\\\\r\n", &.{.literal_multiline_string_line});

    // "TAB used as whitespace is...accepted by the grammar. CR used as
    // whitespace, whether directly preceding NL or stray, is...accepted by the
    // grammar."
    // https://github.com/ziglang/zig-spec/issues/38
    try testTokenize("\tpub\tswitch\t", &.{ .keyword_pub, .keyword_switch });
    try testTokenize("\rpub\rswitch\r", &.{ .keyword_pub, .keyword_switch });
}

test "walrus" {
    try testTokenize(
        \\a := :b
    , &.{
        .identifier,
        .colon_equal,
        .colon,
        .identifier,
    });
}

test "newline token insertion" {
    try testTokenizeFull(
        \\hello
        \\again
    , &.{
        .identifier,
        .newline,
        .identifier,
    });
    try testTokenizeFull(
        \\1 +
        \\2
    , &.{
        .literal_number,
        .plus,
        .literal_number,
    });
    try testTokenizeFull(
        \\1
        \\+ 2
    , &.{
        .literal_number,
        .newline,
        .plus,
        .literal_number,
    });
    try testTokenizeFull(
        \\(1
        \\+ 2)
    , &.{
        .l_paren,
        .literal_number,
        .plus,
        .literal_number,
        .r_paren,
    });
}

test "fuzzable properties upheld" {
    return std.testing.fuzz({}, testPropertiesUpheld, .{});
}

fn testTokenize(source: [:0]const u8, expected_token_tags: []const Token.Tag) !void {
    var tokenizer = Tokenizer.init(source);
    for (expected_token_tags) |expected_token_tag| {
        const token = tokenizer.next();
        try std.testing.expectEqual(expected_token_tag, token.tag);
    }
    // Last token should always be eof, even when the last token was invalid,
    // in which case the tokenizer is in an invalid state, which can only be
    // recovered by opinionated means outside the scope of this implementation.
    const last_token = tokenizer.next();
    try std.testing.expectEqual(Token.Tag.eof, last_token.tag);
    try std.testing.expectEqual(source.len, last_token.loc.start);
    try std.testing.expectEqual(source.len, last_token.loc.end);
}

fn testTokenizeFull(source: [:0]const u8, expected_token_tags: []const Token.Tag) !void {
    var tokens = try Tokenizer.tokenize(std.testing.allocator, source);
    defer tokens.deinit(std.testing.allocator);
    try std.testing.expectEqual(expected_token_tags.len, tokens.len - 1);
    for (tokens.items(.tag)[0 .. tokens.len - 1], expected_token_tags) |tag, expected_token_tag| {
        try std.testing.expectEqual(expected_token_tag, tag);
    }
    const last_token = tokens.get(tokens.len - 1);
    try std.testing.expectEqual(Token.Tag.eof, last_token.tag);
    try std.testing.expectEqual(source.len, last_token.start);
}

fn testPropertiesUpheld(_: void, smith: *std.testing.Smith) !void {
    @disableInstrumentation();
    var source_buf: [512]u8 = undefined;
    const len = smith.sliceWeightedBytes(source_buf[0 .. source_buf.len - 1], &.{
        .rangeAtMost(u8, 0x00, 0xff, 1),
        .rangeAtMost(u8, 0x20, 0x7e, 4),
        .rangeAtMost(u8, 0x00, 0x1f, 1),
        .value(u8, 0, 6),
        .value(u8, ' ', 6),
        .rangeAtMost(u8, '\t', '\n', 6), // \t, \n
        .value(u8, '\r', 3),
    });
    source_buf[len] = 0;
    const source = source_buf[0..len :0];

    var tokenizer = Tokenizer.init(source);
    var tokenization_failed = false;
    while (true) {
        const token = tokenizer.next();

        // Property: token end location after start location (or equal)
        try std.testing.expect(token.loc.end >= token.loc.start);

        switch (token.tag) {
            .invalid => {
                tokenization_failed = true;

                // Property: invalid token always ends at newline or eof
                try std.testing.expect(source[token.loc.end] == '\n' or source[token.loc.end] == 0);
            },
            .eof => {
                // Property: EOF token is always 0-length at end of source.
                try std.testing.expectEqual(source.len, token.loc.start);
                try std.testing.expectEqual(source.len, token.loc.end);
                break;
            },
            else => continue,
        }
    }

    if (tokenization_failed) return;
    for (source) |cur| {
        // Property: No null byte allowed except at end.
        if (cur == 0) {
            return error.TestUnexpectedResult;
        }
        // Property: No ASCII control characters other than \n, \t, and \r are allowed.
        if (std.ascii.isControl(cur) and cur != '\n' and cur != '\t' and cur != '\r') {
            return error.TestUnexpectedResult;
        }
    }
}
