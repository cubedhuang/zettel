package zettel

import "common"
import "compiler"
import "core:bufio"
import "core:flags"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:terminal"
import "report"
import "runtime"

Options :: struct {
	path:         string `args:"pos=0" usage:"Script to run."`,
	ast:          bool `usage:"Print the syntax tree instead of running."`,
	bytecode:     bool `usage:"Print the bytecode instead of running."`,
	error_format: Error_Format `usage:"How verbose errors are. [rich|short]"`,
}

Error_Format :: distinct Maybe(report.Style)

Reporter :: struct {
	color:   bool,
	options: report.Options,
}

main :: proc() {
	opt: Options
	flags.register_type_setter(set_error_format)
	flags.parse_or_exit(&opt, os.args, .Unix)

	path := opt.path
	if path == "" && (opt.ast || opt.bytecode) {
		fmt.eprintln("--ast and --bytecode need a script")
		os.exit(1)
	}

	reporter := Reporter {
		color   = stderr_color(),
		options = report.DEFAULT_OPTIONS,
	}
	reporter.options.style = opt.error_format.? or_else (.Short if path == "" else .Rich)

	if path == "" {
		repl(reporter)
		return
	}

	text, read_err := os.read_entire_file(path, context.allocator)
	if read_err != nil {
		fmt.eprintfln("%v: %v", path, os.error_string(read_err))
		os.exit(1)
	}
	defer delete(text)

	source := common.source_make(path, string(text))
	defer common.source_destroy(&source)

	ast := compiler.parse(source.text)
	defer compiler.ast_destroy(&ast)

	report_errors(reporter, &source, ast)

	if opt.ast {
		out: bufio.Writer
		bufio.writer_init(&out, os.to_writer(os.stdout))
		defer bufio.writer_destroy(&out)
		compiler.render(bufio.writer_to_writer(&out), ast)
		bufio.writer_flush(&out)
	}
	if len(ast.errors) > 0 do os.exit(1)
	if opt.ast do return

	module, ok := compile(reporter, &source, ast)
	if !ok do os.exit(1)
	defer common.module_destroy(&module)

	if opt.bytecode {
		out: bufio.Writer
		bufio.writer_init(&out, os.to_writer(os.stdout))
		defer bufio.writer_destroy(&out)
		common.disassemble(bufio.writer_to_writer(&out), module.main)
		bufio.writer_flush(&out)
		return
	}

	vm := runtime.Vm {
		out = os.to_writer(os.stdout),
	}
	defer runtime.vm_destroy(&vm)
	if !execute(reporter, &source, &vm, module) do os.exit(1)
}

report_diagnostics :: proc(r: Reporter, source: ^common.Source, diagnostics: []report.Diagnostic) {
	out: bufio.Writer
	bufio.writer_init(&out, os.to_writer(os.stderr))
	defer bufio.writer_destroy(&out)
	report.render(
		{writer = bufio.writer_to_writer(&out), color = r.color},
		source,
		diagnostics,
		r.options,
	)
	bufio.writer_flush(&out)
}

report_errors :: proc(r: Reporter, source: ^common.Source, ast: compiler.Ast) {
	if len(ast.errors) == 0 do return
	defer free_all(context.temp_allocator)

	diagnostics := make([]report.Diagnostic, len(ast.errors), context.temp_allocator)
	for error, i in ast.errors {
		diagnostics[i] = {
			span    = compiler.error_span(ast, error),
			message = compiler.error_message(ast, error),
		}
	}
	report_diagnostics(r, source, diagnostics)
}

compile :: proc(
	r: Reporter,
	source: ^common.Source,
	ast: compiler.Ast,
) -> (
	module: common.Module,
	ok: bool,
) {
	defer free_all(context.temp_allocator)

	error: compiler.Compile_Error
	module, error = compiler.compile(ast)
	if error.tag == .None {
		return module, true
	}
	report_diagnostics(
		r,
		source,
		{
			{
				span = compiler.node_span(ast, error.node),
				message = compiler.error_message(error),
			},
		},
	)
	return
}

execute :: proc(
	r: Reporter,
	source: ^common.Source,
	vm: ^runtime.Vm,
	module: common.Module,
) -> bool {
	program := runtime.load(vm, module)
	defer runtime.program_destroy(&program)

	error, ok := runtime.run(vm, program)
	if !ok {
		report_diagnostics(r, source, {{span = error.span, message = error.message}})
	}
	return ok
}

set_error_format :: proc(
	data: rawptr,
	data_type: typeid,
	unparsed_value: string,
	args_tag: string,
) -> (
	error: string,
	handled: bool,
	alloc_error: mem.Allocator_Error,
) {
	if data_type != Error_Format do return

	handled = true
	format := (^Error_Format)(data)
	switch unparsed_value {
	case "rich":
		format^ = .Rich
	case "short":
		format^ = .Short
	case:
		error = "Expected 'rich' or 'short'."
	}
	return
}

stderr_color :: proc() -> bool {
	if env_set("NO_COLOR") do return false
	if env_set("CLICOLOR_FORCE") do return true
	return terminal.is_terminal(os.stderr)
}

env_set :: proc(name: string) -> bool {
	buffer: [128]u8
	value, err := os.lookup_env(buffer[:], name)
	return err == nil && value != ""
}
