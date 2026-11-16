package compiler

import "core:io"

render :: proc(w: io.Writer, ast: Ast) {
	for statement in root_statements(ast) {
		render_node(w, ast, statement)
		io.write_byte(w, '\n')
	}
}

render_node :: proc(w: io.Writer, ast: Ast, index: Node_Index, indent := 0) {
	node := ast.nodes[index]
	switch node.tag {
	case .Root:
		unreachable()
	case .Block:
		io.write_string(w, "(block")
		for statement in block_statements(ast, index) {
			io.write_byte(w, '\n')
			for _ in 0 ..= indent {
				io.write_string(w, "  ")
			}
			render_node(w, ast, statement, indent + 1)
		}
		io.write_byte(w, ')')
	case .Number_Literal:
		io.write_string(w, token_text(ast, node.main_token))
	case .Grouped:
		io.write_string(w, "(group ")
		render_node(w, ast, node.data.token_and_node.node, indent)
		io.write_byte(w, ')')
	case .Negate:
		io.write_string(w, "(- ")
		render_node(w, ast, node.data.node, indent)
		io.write_byte(w, ')')
	case .Add, .Sub, .Mul, .Div:
		io.write_byte(w, '(')
		io.write_string(w, token_text(ast, node.main_token))
		io.write_byte(w, ' ')
		render_node(w, ast, node.data.node_and_node.lhs, indent)
		io.write_byte(w, ' ')
		render_node(w, ast, node.data.node_and_node.rhs, indent)
		io.write_byte(w, ')')
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
