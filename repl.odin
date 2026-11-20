package zettel

import "common"
import "compiler"
import "core:bufio"
import "core:fmt"
import "core:os"
import "runtime"

REPL_PATH :: "<repl>"

Repl :: struct {
	vm:      runtime.Vm,
	statics: common.Static_Names,
}

repl :: proc(r: Reporter) {
	state := Repl {
		vm = {out = os.to_writer(os.stdout)},
	}
	defer runtime.vm_destroy(&state.vm)
	defer common.static_names_destroy(&state.statics)

	scanner: bufio.Scanner
	bufio.scanner_init(&scanner, os.to_reader(os.stdin))
	defer bufio.scanner_destroy(&scanner)

	for {
		fmt.print("> ")

		if !bufio.scan(&scanner) {
			break
		}

		line := bufio.scanner_text(&scanner)
		repl_evaluate(r, &state, line)
	}
}

repl_evaluate :: proc(r: Reporter, state: ^Repl, text: string) {
	source := common.source_make(REPL_PATH, text)
	defer common.source_destroy(&source)

	ast := compiler.parse(source.text)
	defer compiler.ast_destroy(&ast)

	if len(ast.errors) > 0 {
		report_errors(r, &source, ast)
		return
	}

	module, ok := compile(r, &source, ast, state.statics, allow_redeclaration = true)
	if !ok do return
	defer common.module_destroy(&module)

	execute(r, &source, &state.vm, module)

	// steal the statics for next time
	common.static_names_destroy(&state.statics)
	state.statics = module.statics
	module.statics = {}
}
