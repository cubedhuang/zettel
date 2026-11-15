package compiler

Parser :: struct {
	tokenizer: Tokenizer,
	prev:      Token,
	current:   Token,
}

parse :: proc(source: string) -> (ast: Ast) {
	ast.source = source

	parser := Parser {
		tokenizer = Tokenizer{source = source},
	}

	return
}

advance :: proc(p: ^Parser) {}
