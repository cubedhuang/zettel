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
			render_indent(w, indent)
			render_node(w, ast, statement, indent + 1)
		}
		io.write_byte(w, ')')
	case .Assign, .Assign_Multi, .Decl, .Decl_Multi:
		is_decl := node.tag == .Decl || node.tag == .Decl_Multi
		is_multi := node.tag == .Assign_Multi || node.tag == .Decl_Multi
		io.write_string(w, "(:= " if is_decl else "(= ")
		render_node_list(w, ast, assign_targets(ast, index), is_multi, indent)
		io.write_byte(w, ' ')
		render_node_list(w, ast, assign_values(ast, index), is_multi, indent)
		io.write_byte(w, ')')
	case .If_Simple, .If:
		init, condition, then_branch, else_branch := if_parts(ast, index)
		io.write_string(w, "(if ")
		if init != 0 {
			render_node(w, ast, init, indent)
			io.write_string(w, " ")
		}
		render_node(w, ast, condition, indent)
		io.write_byte(w, '\n')
		render_indent(w, indent)
		render_node(w, ast, then_branch, indent + 1)
		if else_branch != 0 {
			io.write_byte(w, '\n')
			render_indent(w, indent)
			render_node(w, ast, else_branch, indent + 1)
		}
		io.write_byte(w, ')')
	case .Number_Literal:
		io.write_string(w, token_text(ast, node.main_token))
	case .String_Literal:
		io.write_string(w, token_text(ast, node.main_token))
	case .Nil_Literal, .True_Literal, .False_Literal:
		io.write_string(w, token_text(ast, node.main_token))
	case .Identifier:
		io.write_string(w, token_text(ast, node.main_token))
	case .Grouped:
		io.write_string(w, "(group ")
		render_node(w, ast, node.data.token_and_node.node, indent)
		io.write_byte(w, ')')
	case .Negate:
		io.write_string(w, "(- ")
		render_node(w, ast, node.data.node, indent)
		io.write_byte(w, ')')
	case .Not:
		io.write_string(w, "(! ")
		render_node(w, ast, node.data.node, indent)
		io.write_byte(w, ')')
	case .Echo:
		io.write_string(w, "(echo ")
		render_node(w, ast, node.data.node, indent)
		io.write_byte(w, ')')
	case .Add,
	     .Sub,
	     .Mul,
	     .Div,
	     .Equal,
	     .Not_Equal,
	     .Less,
	     .Less_Equal,
	     .Greater,
	     .Greater_Equal,
	     .And,
	     .Or:
		io.write_byte(w, '(')
		io.write_string(w, token_text(ast, node.main_token))
		io.write_byte(w, ' ')
		render_node(w, ast, node.data.node_and_node.lhs, indent)
		io.write_byte(w, ' ')
		render_node(w, ast, node.data.node_and_node.rhs, indent)
		io.write_byte(w, ')')
	}
}

render_indent :: proc(w: io.Writer, indent: int) {
	for _ in 0 ..= indent {
		io.write_string(w, "  ")
	}
}

render_node_list :: proc(
	w: io.Writer,
	ast: Ast,
	nodes: []Node_Index,
	brackets: bool,
	indent: int,
) {
	if brackets do io.write_byte(w, '[')
	for node, i in nodes {
		if i != 0 do io.write_byte(w, ' ')
		render_node(w, ast, node, indent)
	}
	if brackets do io.write_byte(w, ']')
}
