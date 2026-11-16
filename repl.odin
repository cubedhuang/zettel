package zettel

import "bytecode"
import "compiler"
import "core:bufio"
import "core:fmt"
import "core:os"
import "runtime"

REPL_PATH :: "<repl>"

repl :: proc() {
	vm := runtime.Vm {
		out = os.to_writer(os.stdout),
	}
	defer runtime.vm_destroy(&vm)

	scanner: bufio.Scanner
	bufio.scanner_init(&scanner, os.to_reader(os.stdin))
	defer bufio.scanner_destroy(&scanner)

	for {
		fmt.print("> ")

		if !bufio.scan(&scanner) {
			break
		}

		line := bufio.scanner_text(&scanner)
		repl_evaluate(&vm, line)
	}
}

repl_evaluate :: proc(vm: ^runtime.Vm, source: string) {
	ast := compiler.parse(source)
	defer compiler.ast_destroy(&ast)

	if len(ast.errors) > 0 {
		report_errors(REPL_PATH, ast)
		return
	}

	module, ok := compile(REPL_PATH, ast)
	if !ok do return
	defer bytecode.module_destroy(&module)

	execute(vm, module)
	return
}
