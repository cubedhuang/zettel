//! Renders diagnostics given a `Source`.

const std = @import("std");
const Io = std.Io;
const Terminal = std.Io.Terminal;
const Writer = std.Io.Writer;

const Source = @import("Source.zig");

pub const Error = Terminal.SetColorError;

pub const Severity = enum {
    @"error",
    warning,
    note,

    fn text(severity: Severity) []const u8 {
        return @tagName(severity);
    }

    fn color(severity: Severity) Terminal.Color {
        return switch (severity) {
            .@"error" => .red,
            .warning => .bright_yellow,
            .note => .bright_cyan,
        };
    }
};

pub const Diagnostic = struct {
    severity: Severity = .@"error",
    span: Source.Span,
    message: []const u8,
};

pub const Style = enum {
    /// `path:line:col: severity: message`.
    short,
    /// Includes source and content around the span.
    rich,
};

pub const Options = struct {
    style: Style = .rich,
    /// Lines above and below span.
    context_lines: u32 = 1,
    /// Summary line displayed after.
    max_diagnostics: usize = 10,
};

pub fn render(
    term: Terminal,
    source: *const Source,
    diagnostics: []const Diagnostic,
    options: Options,
) Error!void {
    const shown = @min(diagnostics.len, options.max_diagnostics);
    for (diagnostics[0..shown], 0..) |diagnostic, i| {
        if (i > 0 and options.style == .rich) try term.writer.writeByte('\n');
        try renderDiagnostic(term, source, diagnostic, options);
    }

    const hidden = diagnostics.len - shown;
    if (hidden > 0) {
        try term.setColor(.bold);
        try term.writer.print("... and {d} more error{s}\n", .{
            hidden,
            if (hidden == 1) "" else "s",
        });
        try term.setColor(.reset);
    }

    try term.writer.flush();
}

pub fn renderDiagnostic(
    term: Terminal,
    source: *const Source,
    diagnostic: Diagnostic,
    options: Options,
) Error!void {
    const source_end: u32 = @intCast(source.bytes.len);
    const start = @min(diagnostic.span.start, source_end);
    const end = @max(start, @min(diagnostic.span.end, source_end));
    const main = std.math.clamp(diagnostic.span.main, start, end);

    const line = source.lineIndex(start);
    const line_text = source.lineSlice(line);
    const line_start = source.line_starts[line];

    const span_start = @min(start - line_start, line_text.len);
    const span_end = @max(span_start, @min(end - line_start, line_text.len));
    const main_column = @min(main - line_start, line_text.len);
    const column = main_column + 1;

    switch (options.style) {
        .short => {
            try term.setColor(.bold);
            try term.writer.print("{s}:{d}:{d}: ", .{ source.path, line + 1, column });
            try term.setColor(diagnostic.severity.color());
            try term.writer.print("{s}: ", .{diagnostic.severity.text()});
            try term.setColor(.reset);
            try term.writer.print("{s}\n", .{diagnostic.message});
        },
        .rich => {
            const first = line -| options.context_lines;
            const last = @min(line + options.context_lines, source.lineCount() - 1);

            try writeHeadline(term, diagnostic);
            try writeLocation(term, source, line + 1, column);

            const gutter = @max(4, digitCount(last + 1));
            for (first..last + 1) |n| {
                const number: u32 = @intCast(n);
                try writeSourceLine(term, source, gutter, number, number == line);
                if (number == line) {
                    try writeCaret(term, diagnostic.severity, gutter, line_text, span_start, span_end, main_column);
                }
            }
        },
    }
}

/// `level: message`
fn writeHeadline(term: Terminal, diagnostic: Diagnostic) Error!void {
    try term.setColor(.bold);
    try term.setColor(diagnostic.severity.color());
    try term.writer.writeAll(diagnostic.severity.text());
    try term.setColor(.reset);

    try term.setColor(.bold);
    try term.writer.print(": {s}", .{diagnostic.message});
    try term.setColor(.reset);
    try term.writer.writeByte('\n');
}

/// `  path/to/file.zettel:7:15`
fn writeLocation(
    term: Terminal,
    source: *const Source,
    line: u32,
    column: u32,
) Error!void {
    try term.writer.writeAll("  ");

    try term.setColor(.bold);
    try term.setColor(.cyan);
    try term.writer.print("{s}:{d}:{d}", .{ source.path, line, column });
    try term.setColor(.reset);
    try term.writer.writeByte('\n');
}

/// `   7 | 123 + +`
fn writeSourceLine(term: Terminal, source: *const Source, gutter: u32, line: u32, highlight: bool) Error!void {
    try term.setColor(if (highlight) .red else .dim);
    try term.writer.splatByteAll(' ', gutter - digitCount(line + 1));
    try term.writer.print("{d} |", .{line + 1});
    if (highlight) try term.setColor(.reset);

    const text = source.lineSlice(line);
    if (text.len > 0) try term.writer.print(" {s}", .{text});
    if (!highlight) try term.setColor(.reset);
    try term.writer.writeByte('\n');
}

/// `     |     ~~^~~`
fn writeCaret(
    term: Terminal,
    severity: Severity,
    gutter: u32,
    line_text: []const u8,
    span_start: usize,
    span_end: usize,
    main_column: usize,
) Error!void {
    try term.writer.splatByteAll(' ', gutter + 1);
    try term.setColor(.red);
    try term.writer.writeAll("|");
    try term.setColor(.reset);

    try term.writer.writeByte(' ');
    try writeIndent(term.writer, line_text[0..span_start]);

    const width = @max(1, span_end - span_start);
    const main = @min(main_column -| span_start, width - 1);
    try term.setColor(.bold);
    try term.setColor(severity.color());
    try term.writer.splatByteAll('~', main);
    try term.writer.writeByte('^');
    try term.writer.splatByteAll('~', width - main - 1);
    try term.setColor(.reset);

    try term.writer.writeByte('\n');
}

fn writeIndent(writer: *Writer, text: []const u8) Writer.Error!void {
    for (text) |byte| {
        try writer.writeByte(if (byte == '\t') '\t' else ' ');
    }
}

fn digitCount(n: u32) u32 {
    return if (n == 0) 1 else std.math.log10_int(n) + 1;
}

test digitCount {
    try std.testing.expectEqual(1, digitCount(0));
    try std.testing.expectEqual(1, digitCount(9));
    try std.testing.expectEqual(2, digitCount(10));
    try std.testing.expectEqual(3, digitCount(999));
    try std.testing.expectEqual(4, digitCount(1000));
}

test writeIndent {
    var buffer: [256]u8 = undefined;
    var writer: Writer = .fixed(&buffer);
    try writeIndent(&writer, "\tab");
    try std.testing.expectEqualStrings("\t  ", writer.buffered());
}

fn expectRendered(
    expected: []const u8,
    source_text: [:0]const u8,
    diagnostics: []const Diagnostic,
    options: Options,
) !void {
    const gpa = std.testing.allocator;

    var source: Source = try .init(gpa, "main.zettel", source_text);
    defer source.deinit(gpa);

    var out: Writer.Allocating = .init(gpa);
    defer out.deinit();

    try render(.{ .writer = &out.writer, .mode = .no_color }, &source, diagnostics, options);
    try std.testing.expectEqualStrings(expected, out.written());
}

test "frame" {
    try expectRendered(
        \\error: expected expression, found '*'
        \\  main.zettel:3:6
        \\   2 | b := 2
        \\   3 | c := *
        \\     |      ^
        \\   4 | d := 4
        \\
    ,
        "a := 1\nb := 2\nc := *\nd := 4\n",
        &.{.{ .span = .{ .start = 19, .end = 20, .main = 19 }, .message = "expected expression, found '*'" }},
        .{},
    );
}

test "empty span get caret" {
    try expectRendered(
        \\error: expected expression, found 'EOF'
        \\  main.zettel:2:9
        \\   1 | a := 1
        \\   2 | b := a +
        \\     |         ^
        \\
    ,
        "a := 1\nb := a +",
        &.{.{ .span = .{ .start = 15, .end = 15, .main = 15 }, .message = "expected expression, found 'EOF'" }},
        .{},
    );
}

test "summary after max" {
    const many: [3]Diagnostic = @splat(.{
        .span = .{ .start = 0, .end = 1, .main = 0 },
        .message = "bad",
    });

    try expectRendered(
        \\main.zettel:1:1: error: bad
        \\main.zettel:1:1: error: bad
        \\... and 1 more error
        \\
    ,
        "abc\n",
        &many,
        .{ .style = .short, .max_diagnostics = 2 },
    );
}
