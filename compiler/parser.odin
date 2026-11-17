package compiler

// `Parser` holds intermediate parsing data. After parsing, it's converted into
// an `Ast`.
Parser :: struct {
	source:  string,
	tokens:  #soa[]Token,
	nodes:   #soa[dynamic]Node,
	extra:   [dynamic]u32,
	errors:  [dynamic]Error,
	scratch: [dynamic]Node_Index,
	// Index of next token in `tokens`.
	i:       int,
	// Used to skip newlines.
	depth:   int,
}

parse :: proc(source: string) -> Ast {
	p := Parser {
		source = source,
		tokens = tokenize(source),
	}
	defer delete(p.scratch)
	parse_root(&p)

	return {
		source = source,
		tokens = p.tokens,
		nodes = p.nodes[:],
		extra = p.extra[:],
		errors = p.errors[:],
	}
}

// Root <- ClassBody EOF
parse_root :: proc(p: ^Parser) {
	append(&p.nodes, Node{tag = .Root})

	range := parse_class_body(p)
	p.nodes[0].data.extra_range = range
}

// ClassBody <- Stmt*
parse_class_body :: proc(p: ^Parser) -> Node_Range {
	return parse_stmts(p, .EOF)
}

// Stmt*
parse_stmts :: proc(p: ^Parser, end: Token_Tag) -> Node_Range {
	scratch_top := len(p.scratch)
	defer non_zero_resize(&p.scratch, scratch_top)

	for {
		tag := peek_tag(p)
		if tag == end || tag == .EOF do break

		// empty statement
		if tag == .Semi {
			advance(p)
			continue
		}
		// not in a `{}` block
		if tag == .Brace_Close {
			add_error(p, {tag = .Expected_Expression})
			advance(p)
			continue
		}

		if statement, ok := parse_stmt(p); ok {
			append(&p.scratch, statement)
		} else {
			synchronize(p)
		}
	}

	return make_range(p, p.scratch[scratch_top:])
}

// Stmt <- Block
//       / SimpleStmt
//
// Block <- BRACE_OPEN Stmt* BRACE_CLOSE
//
// SimpleStmt <- Expr SEMI
parse_stmt :: proc(p: ^Parser) -> (node: Node_Index, ok: bool) {
	#partial switch peek_tag(p) {
	case .Brace_Open:
		return parse_block(p)
	}

	node = parse_expression(p) or_return
	expect(p, .Semi) or_return
	return node, true
}

// Block <- BRACE_OPEN Stmt* BRACE_CLOSE
parse_block :: proc(p: ^Parser) -> (node: Node_Index, ok: bool) {
	open := expect(p, .Brace_Open) or_return
	range := parse_stmts(p, .Brace_Close)
	expect(p, .Brace_Close) or_return
	return add_node(p, {tag = .Block, main_token = open, data = {extra_range = range}}), true
}

// Expr <- Expr (BinaryOp Expr)?
//       / Unary
parse_expression :: proc(p: ^Parser, min_precedence := 0) -> (node: Node_Index, ok: bool) {
	node = parse_unary(p) or_return

	for {
		tag, precedence := binary_op(peek_tag(p))
		if precedence <= min_precedence do break

		operator := advance(p)
		rhs := parse_expression(p, precedence) or_return
		node = add_node(
			p,
			{tag = tag, main_token = operator, data = {node_and_node = {node, rhs}}},
		)
	}

	return node, true
}

binary_op :: proc(tag: Token_Tag) -> (Node_Tag, int) {
	#partial switch tag {
	case .Plus:
		return .Add, 1
	case .Minus:
		return .Sub, 1
	case .Star:
		return .Mul, 2
	case .Slash:
		return .Div, 2
	}
	return .Root, 0
}

// Unary <- UnaryOp Unary
//        / Primary
parse_unary :: proc(p: ^Parser) -> (node: Node_Index, ok: bool) {
	if peek_tag(p) == .Minus {
		operator := advance(p)
		operand := parse_unary(p) or_return
		return add_node(p, {tag = .Negate, main_token = operator, data = {node = operand}}), true
	}
	return parse_primary(p)
}

// Primary <- NUMBER
//          / STRING
//          / PAREN_OPEN Expr PAREN_CLOSE
parse_primary :: proc(p: ^Parser) -> (node: Node_Index, ok: bool) {
	#partial switch peek_tag(p) {
	case .Number:
		return add_node(p, {tag = .Number_Literal, main_token = advance(p)}), true
	case .String:
		return add_node(p, {tag = .String_Literal, main_token = advance(p)}), true
	case .Paren_Open:
		open := advance(p)
		p.depth += 1
		inner, inner_ok := parse_expression(p)
		p.depth -= 1
		if !inner_ok do return
		close := expect(p, .Paren_Close) or_return
		return add_node(
				p,
				{tag = .Grouped, main_token = open, data = {token_and_node = {close, inner}}},
			),
			true
	}
	add_error(p, {tag = .Expected_Expression})
	return
}

make_range :: proc(p: ^Parser, items: []Node_Index) -> Node_Range {
	start := len(p.extra)
	append(&p.extra, ..transmute([]u32)items)
	return {Extra_Index(start), Extra_Index(len(p.extra))}
}

peek_tag :: proc(p: ^Parser) -> Token_Tag {
	return p.tokens[p.i].tag
}

advance :: proc(p: ^Parser) -> (i: Token_Index) {
	i = Token_Index(p.i)
	if peek_tag(p) != .EOF do p.i += 1
	if p.depth > 0 {
		for is_newline_semi(p, p.i) do p.i += 1
	}
	return
}

is_newline_semi :: proc(p: ^Parser, i: int) -> bool {
	if p.tokens[i].tag != .Semi do return false
	start := int(p.tokens[i].start)
	return start >= len(p.source) || p.source[start] == '\n'
}

expect :: proc(p: ^Parser, tag: Token_Tag) -> (token: Token_Index, ok: bool) {
	if peek_tag(p) != tag {
		add_error(p, {tag = .Expected_Token, expected = tag})
		return
	}
	return advance(p), true
}

synchronize :: proc(p: ^Parser) {
	for peek_tag(p) != .EOF {
		if peek_tag(p) == .Brace_Close do return
		if p.tokens[advance(p)].tag == .Semi do return
	}
}

add_node :: proc(p: ^Parser, node: Node) -> Node_Index {
	append(&p.nodes, node)
	return Node_Index(len(p.nodes) - 1)
}

add_error :: proc(p: ^Parser, error: Error) {
	error := error
	error.token = Token_Index(p.i)
	append(&p.errors, error)
}
