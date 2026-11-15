package compiler

import "core:strings"

render :: proc(b: ^strings.Builder, ast: Ast) {
	for statement in root_statements(ast) {
		render_node(b, ast, statement)
		strings.write_byte(b, '\n')
	}
}

render_node :: proc(b: ^strings.Builder, ast: Ast, index: Node_Index) {
	node := ast.nodes[index]
	switch node.tag {
	case .Root:
		unreachable()
	case .Number_Literal:
		strings.write_string(b, token_text(ast, node.main_token))
	case .Grouped:
		strings.write_string(b, "(group ")
		render_node(b, ast, node.data.token_and_node.node)
		strings.write_byte(b, ')')
	case .Negate:
		strings.write_string(b, "(- ")
		render_node(b, ast, node.data.node)
		strings.write_byte(b, ')')
	case .Add, .Sub, .Mul, .Div:
		strings.write_byte(b, '(')
		strings.write_string(b, token_text(ast, node.main_token))
		strings.write_byte(b, ' ')
		render_node(b, ast, node.data.node_and_node.lhs)
		strings.write_byte(b, ' ')
		render_node(b, ast, node.data.node_and_node.rhs)
		strings.write_byte(b, ')')
	}
}

source_location :: proc(source: string, offset: u32) -> (line, column: int) {
	line, column = 1, 1
	for c in transmute([]u8)source[:offset] {
		if c == '\n' {
			line += 1
			column = 1
		} else {
			column += 1
		}
	}
	return
}
