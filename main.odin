package zettel

import "bytecode"
import "compiler"
import "core:bufio"
import "core:fmt"
import "core:os"
import "runtime"

Mode :: enum {
	Run,
	Ast,
	Bytecode,
}

main :: proc() {
	mode := Mode.Run
	path: string
	switch {
	case len(os.args) == 1:
		repl()
		return
	case len(os.args) == 2:
		path = os.args[1]
	case len(os.args) == 3 && os.args[1] == "--ast":
		mode, path = .Ast, os.args[2]
	case len(os.args) == 3 && os.args[1] == "--bytecode":
		mode, path = .Bytecode, os.args[2]
	case:
		fmt.eprintfln("usage: %v [[--ast | --bytecode] <path>]", os.args[0])
		os.exit(1)
	}

	source, read_err := os.read_entire_file(path, context.allocator)
	if read_err != nil {
		fmt.eprintfln("%v: %v", path, os.error_string(read_err))
		os.exit(1)
	}
	defer delete(source)

	ast := compiler.parse(string(source))
	defer compiler.ast_destroy(&ast)

	report_errors(path, ast)

	if mode == .Ast {
		out: bufio.Writer
		bufio.writer_init(&out, os.to_writer(os.stdout))
		defer bufio.writer_destroy(&out)
		compiler.render(bufio.writer_to_writer(&out), ast)
		bufio.writer_flush(&out)
	}
	if len(ast.errors) > 0 do os.exit(1)
	if mode == .Ast do return

	module, ok := compile(path, ast)
	if !ok do os.exit(1)
	defer bytecode.module_destroy(&module)

	if mode == .Bytecode {
		out: bufio.Writer
		bufio.writer_init(&out, os.to_writer(os.stdout))
		defer bufio.writer_destroy(&out)
		bytecode.disassemble(bufio.writer_to_writer(&out), module.main)
		bufio.writer_flush(&out)
		return
	}

	vm := runtime.Vm {
		out = os.to_writer(os.stdout),
	}
	defer runtime.vm_destroy(&vm)
	execute(&vm, module)
}

report_errors :: proc(path: string, ast: compiler.Ast) {
	for error in ast.errors {
		token := ast.tokens[error.token]
		line, column := compiler.source_location(ast.source, token.start)
		fmt.eprintf("%v:%v:%v: ", path, line, column)
		switch error.tag {
		case .Expected_Expression:
			fmt.eprintfln("expected expression, got %v", compiler.token_names[token.tag])
		case .Expected_Token:
			fmt.eprintfln(
				"expected %v, got %v",
				compiler.token_names[error.expected],
				compiler.token_names[error.expected],
			)
		}
	}
}

compile :: proc(path: string, ast: compiler.Ast) -> (module: bytecode.Module, ok: bool) {
	error: compiler.Compile_Error
	module, error = compiler.compile(ast)
	switch error {
	case .None:
		return module, true
	case .Too_Many_Constants:
		fmt.eprintfln("%v: more than %v constants", path, bytecode.MAX_CONSTANTS)
	}
	return
}

execute :: proc(vm: ^runtime.Vm, module: bytecode.Module) {
	program := runtime.load(vm, module)
	defer runtime.program_destroy(&program)
	runtime.run(vm, program)
}
