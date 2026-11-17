package zettel

import "common"
import "compiler"
import "core:bufio"
import "core:fmt"
import "core:os"
import "runtime"

REPL_PATH :: "<repl>"

repl :: proc(r: Reporter) {
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
		repl_evaluate(r, &vm, line)
	}
}

repl_evaluate :: proc(r: Reporter, vm: ^runtime.Vm, text: string) {
	source := common.source_make(REPL_PATH, text)
	defer common.source_destroy(&source)

	ast := compiler.parse(source.text)
	defer compiler.ast_destroy(&ast)

	if len(ast.errors) > 0 {
		report_errors(r, &source, ast)
		return
	}

	module, ok := compile(r, &source, ast)
	if !ok do return
	defer common.module_destroy(&module)

	execute(r, &source, vm, module)
}
