package zettel

import "compiler"
import "core:fmt"
import "core:os"
import "core:strings"

main :: proc() {
	if len(os.args) != 2 {
		fmt.eprintfln("usage: %v <path>", os.args[0])
		os.exit(1)
	}
	path := os.args[1]

	source, read_err := os.read_entire_file(path, context.allocator)
	if read_err != nil {
		fmt.eprintfln("%v: %v", path, os.error_string(read_err))
		os.exit(1)
	}
	defer delete(source)

	ast := compiler.parse(string(source))
	defer compiler.ast_destroy(&ast)

	b := strings.builder_make()
	defer strings.builder_destroy(&b)
	compiler.render(&b, ast)
	fmt.print(strings.to_string(b))

	for error in ast.errors {
		line, column := compiler.source_location(ast.source, ast.tokens[error.token].start)
		fmt.eprintf("%v:%v:%v: ", path, line, column)
		switch error.tag {
		case .Expected_Expression:
			fmt.eprintln("expected expression")
		case .Expected_Token:
			fmt.eprintfln("expected %v", error.expected)
		}
	}
	if len(ast.errors) > 0 do os.exit(1)
}
