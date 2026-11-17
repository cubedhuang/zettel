// The report package renders diagnostics against the source they came from.
package report

import "../common"
import "core:fmt"
import "core:io"
import "core:math"
import "core:terminal/ansi"

Severity :: enum u8 {
	Error,
	Warning,
	Note,
}

severity_names := [Severity]string {
	.Error   = "error",
	.Warning = "warning",
	.Note    = "note",
}

severity_colors := [Severity]Color {
	.Error   = .Red,
	.Warning = .Bright_Yellow,
	.Note    = .Bright_Cyan,
}

Diagnostic :: struct {
	severity: Severity,
	span:     common.Span,
	message:  string,
}

Style :: enum u8 {
	/// Includes source and content around the span.
	Rich,
	// `path:line:col: severity: message`.
	Short,
}

Options :: struct {
	style:           Style,
	// Lines above and below span.
	context_lines:   int,
	/// Summary line displayed after.
	max_diagnostics: int,
}

DEFAULT_OPTIONS :: Options {
	style           = .Rich,
	context_lines   = 1,
	max_diagnostics = 10,
}

Terminal :: struct {
	writer: io.Writer,
	color:  bool,
}

render :: proc(t: Terminal, source: ^common.Source, diagnostics: []Diagnostic, options: Options) {
	shown := min(len(diagnostics), options.max_diagnostics)
	for diagnostic, i in diagnostics[:shown] {
		if i > 0 && options.style == .Rich do io.write_byte(t.writer, '\n')
		render_diagnostic(t, source, diagnostic, options)
	}

	if hidden := len(diagnostics) - shown; hidden > 0 {
		set_color(t, .Bold)
		fmt.wprintf(
			t.writer,
			"... and %v more error%v\n",
			hidden,
			"" if hidden == 1 else "s",
			flush = false,
		)
		set_color(t, .Reset)
	}
}

render_diagnostic :: proc(
	t: Terminal,
	source: ^common.Source,
	diagnostic: Diagnostic,
	options: Options,
) {
	source_end := u32(len(source.text))
	start := min(diagnostic.span.start, source_end)
	end := max(start, min(diagnostic.span.end, source_end))
	main := clamp(diagnostic.span.main, start, end)

	line := common.line_index(source, start)
	text := common.line_text(source, line)
	line_start := source.line_starts[line]

	span_start := min(int(start - line_start), len(text))
	span_end := max(span_start, min(int(end - line_start), len(text)))
	main_column := min(int(main - line_start), len(text))
	column := main_column + 1

	switch options.style {
	case .Short:
		set_color(t, .Bold)
		fmt.wprintf(t.writer, "%v:%v:%v: ", source.path, line + 1, column, flush = false)
		set_color(t, severity_colors[diagnostic.severity])
		fmt.wprintf(t.writer, "%v: ", severity_names[diagnostic.severity], flush = false)
		set_color(t, .Reset)
		fmt.wprintf(t.writer, "%v\n", diagnostic.message, flush = false)
	case .Rich:
		first := max(line - options.context_lines, 0)
		last := min(line + options.context_lines, common.line_count(source) - 1)

		write_headline(t, diagnostic)
		write_location(t, source, line + 1, column)

		gutter := max(4, math.count_digits_of_base(last + 1, 10))
		for n in first ..= last {
			write_source_line(t, source, gutter, n, n == line)
			if n == line {
				write_caret(
					t,
					diagnostic.severity,
					gutter,
					text,
					span_start,
					span_end,
					main_column,
				)
			}
		}
	}
}

// `level: message`
write_headline :: proc(t: Terminal, diagnostic: Diagnostic) {
	set_color(t, .Bold)
	set_color(t, severity_colors[diagnostic.severity])
	io.write_string(t.writer, severity_names[diagnostic.severity])
	set_color(t, .Reset)

	set_color(t, .Bold)
	fmt.wprintf(t.writer, ": %v", diagnostic.message, flush = false)
	set_color(t, .Reset)
	io.write_byte(t.writer, '\n')
}

// `  path/to/file.zettel:7:15`
write_location :: proc(t: Terminal, source: ^common.Source, line, column: int) {
	io.write_string(t.writer, "  ")

	set_color(t, .Bold)
	set_color(t, .Cyan)
	fmt.wprintf(t.writer, "%v:%v:%v", source.path, line, column, flush = false)
	set_color(t, .Reset)
	io.write_byte(t.writer, '\n')
}

// `   7 | 123 + +`
write_source_line :: proc(
	t: Terminal,
	source: ^common.Source,
	gutter, line: int,
	highlight: bool,
) {
	set_color(t, .Red if highlight else .Faint)
	splat(t.writer, ' ', gutter - math.count_digits_of_base(line + 1, 10))
	fmt.wprintf(t.writer, "%v |", line + 1, flush = false)
	if highlight do set_color(t, .Reset)

	if text := common.line_text(source, line); len(text) > 0 {
		io.write_byte(t.writer, ' ')
		io.write_string(t.writer, text)
	}
	if !highlight do set_color(t, .Reset)
	io.write_byte(t.writer, '\n')
}

// `     |     ~~^~~`
write_caret :: proc(
	t: Terminal,
	severity: Severity,
	gutter: int,
	text: string,
	span_start, span_end, main_column: int,
) {
	splat(t.writer, ' ', gutter + 1)
	set_color(t, .Red)
	io.write_byte(t.writer, '|')
	set_color(t, .Reset)

	io.write_byte(t.writer, ' ')
	for i in 0 ..< span_start {
		io.write_byte(t.writer, '\t' if text[i] == '\t' else ' ')
	}

	width := max(1, span_end - span_start)
	main := min(max(main_column - span_start, 0), width - 1)
	set_color(t, .Bold)
	set_color(t, severity_colors[severity])
	splat(t.writer, '~', main)
	io.write_byte(t.writer, '^')
	splat(t.writer, '~', width - main - 1)
	set_color(t, .Reset)

	io.write_byte(t.writer, '\n')
}

set_color :: proc(t: Terminal, color: Color) {
	if t.color {
		io.write_string(t.writer, ansi.CSI)
		io.write_string(t.writer, color_codes[color])
		io.write_string(t.writer, ansi.SGR)
	}
}

splat :: proc(w: io.Writer, c: u8, count: int) {
	for _ in 0 ..< count {
		io.write_byte(w, c)
	}
}
