package compiler

import "core:strings"

// `Parser` holds intermediate parsing data. After parsing, it's converted into
// an `Ast`.
Parser :: struct {
	// Externally owned.
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
		if tag == .Semi || tag == .Newline {
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
//       / IfStmt
//       / WhileStmt
//       / KEYWORD_BREAK SEMI
//       / KEYWORD_CONTINUE SEMI
//       / SimpleStmt SEMI
//
// Block <- BRACE_OPEN Stmt* BRACE_CLOSE
parse_stmt :: proc(p: ^Parser) -> (node: Node_Index, ok: bool) {
	#partial switch peek_tag(p) {
	case .Brace_Open:
		return parse_block(p)
	case .Keyword_If:
		return parse_if(p)
	case .Keyword_While:
		return parse_while(p)
	case .Keyword_Break, .Keyword_Continue:
		tag: Node_Tag = .Break if peek_tag(p) == .Keyword_Break else .Continue
		node = add_node(p, {tag = tag, main_token = advance(p)})
		expect_stmt_end(p) or_return
		return node, true
	}

	node = parse_simple_stmt(p) or_return
	expect_stmt_end(p) or_return
	return node, true
}

// Block <- BRACE_OPEN Stmt* BRACE_CLOSE
parse_block :: proc(p: ^Parser) -> (node: Node_Index, ok: bool) {
	open := expect(p, .Brace_Open) or_return
	range := parse_stmts(p, .Brace_Close)
	expect(p, .Brace_Close) or_return
	return add_node(p, {tag = .Block, main_token = open, data = {extra_range = range}}), true
}

// IfStmt <- KEYWORD_IF Condition Block Else?
parse_if :: proc(p: ^Parser) -> (node: Node_Index, ok: bool) {
	if_token := expect(p, .Keyword_If) or_return
	init, condition := parse_condition(p) or_return
	then_branch := parse_block(p) or_return

	if init == 0 && peek_tag(p) != .Keyword_Else {
		return add_node(
				p,
				{
					tag = .If_Simple,
					main_token = if_token,
					data = {node_and_node = {condition, then_branch}},
				},
			),
			true
	}

	else_branch := parse_else(p) or_return
	extra := add_extra(p, If_While{init, then_branch, else_branch})
	return add_node(
			p,
			{tag = .If, main_token = if_token, data = {node_and_extra = {condition, extra}}},
		),
		true
}

// WhileStmt <- KEYWORD_WHILE Condition Block Else?
parse_while :: proc(p: ^Parser) -> (node: Node_Index, ok: bool) {
	while_token := expect(p, .Keyword_While) or_return
	init, condition := parse_condition(p) or_return
	body := parse_block(p) or_return
	else_branch := parse_else(p) or_return

	if init == 0 && else_branch == 0 {
		return add_node(
				p,
				{
					tag = .While_Simple,
					main_token = while_token,
					data = {node_and_node = {condition, body}},
				},
			),
			true
	}
	extra := add_extra(p, If_While{init, body, else_branch})
	return add_node(
			p,
			{tag = .While, main_token = while_token, data = {node_and_extra = {condition, extra}}},
		),
		true
}

// Else <- KEYWORD_ELSE (IfStmt / Block)
//
// Returns 0 if there's no `else`.
parse_else :: proc(p: ^Parser) -> (node: Node_Index, ok: bool) {
	if peek_tag(p) != .Keyword_Else do return 0, true
	advance(p)
	if peek_tag(p) == .Keyword_If do return parse_if(p)
	return parse_block(p)
}

// Condition <- (SimpleStmt SEMI)? Expr
//
// `init` is 0 when missing.
parse_condition :: proc(p: ^Parser) -> (init, condition: Node_Index, ok: bool) {
	first := parse_simple_stmt(p) or_return
	#partial switch p.nodes[first].tag {
	case .Assign, .Assign_Multi, .Decl, .Decl_Multi:
		init = first
		expect(p, .Semi) or_return
	case:
		if peek_tag(p) != .Semi do return 0, first, true
		init = first
		advance(p)
	}
	condition = parse_expression(p) or_return
	return init, condition, true
}

// SimpleStmt <- Expr
//             / AssignStmt
//             / DeclStmt
//
// AssignStmt <- Exprs EQ Exprs
//
// DeclStmt <- IDENTIFIER (COMMA IDENTIFIER)* COLON EQ Exprs
parse_simple_stmt :: proc(p: ^Parser) -> (node: Node_Index, ok: bool) {
	lhs := parse_exprs(p) or_return

	eq: Token_Index
	is_decl: bool
	#partial switch peek_tag(p) {
	case .Eq:
		eq = advance(p)
	case .Colon:
		is_decl = true
		advance(p)
		eq = expect(p, .Eq) or_return
	case:
		if expr, ok := lhs.(Node_Index); ok {
			return expr, ok
		}
		add_error(p, {tag = .Invalid_Expression_List})
		return
	}

	rhs := parse_exprs(p) or_return

	ls, rs := exprs_len(lhs), exprs_len(rhs)
	if ls == 1 && rs == 1 {
		l, r := lhs.(Node_Index), rhs.(Node_Index)

		if is_decl && p.nodes[l].tag != .Identifier {
			add_error(p, {tag = .Invalid_Declaration_Target, token = eq})
			return
		}

		node = add_node(
			p,
			{
				tag = .Decl if is_decl else .Assign,
				main_token = eq,
				data = {node_and_node = {l, r}},
			},
		)
	} else {
		if rs > ls {
			add_error(p, {tag = .Too_Many_Rhs, token = eq})
			return
		}

		l, r := exprs_to_range(p, lhs), exprs_to_range(p, rhs)
		if is_decl {
			for target in l.start ..< l.end {
				if p.nodes[p.extra[target]].tag != .Identifier {
					add_error(p, {tag = .Invalid_Declaration_Target, token = eq})
					return
				}
			}
		}
		ranges := Multi_Assign {
			lhs = l,
			rhs = r,
		}
		extra := add_extra(p, ranges)
		node = add_node(
			p,
			{
				tag = .Decl_Multi if is_decl else .Assign_Multi,
				main_token = eq,
				data = {extra = extra},
			},
		)
	}

	return node, true
}

// If there is only one expr, it shouldn't get a range.
Exprs :: union {
	Node_Index,
	Node_Range,
}

// Exprs <- Expr (COMMA Expr)*
parse_exprs :: proc(p: ^Parser) -> (exprs: Exprs, ok: bool) {
	scratch_top := len(p.scratch)
	defer non_zero_resize(&p.scratch, scratch_top)

	for {
		append(&p.scratch, parse_expression(p) or_return)
		if peek_tag(p) != .Comma do break
		advance(p)
	}

	items := p.scratch[scratch_top:]
	if len(items) == 1 {
		exprs = items[0]
	} else {
		exprs = make_range(p, items)
	}
	return exprs, true
}

exprs_len :: proc(exprs: Exprs) -> int {
	switch e in exprs {
	case Node_Index:
		return 1
	case Node_Range:
		return int(e.end - e.start)
	}
	unreachable()
}

exprs_to_range :: proc(p: ^Parser, exprs: Exprs) -> Node_Range {
	switch e in exprs {
	case Node_Index:
		return make_range(p, {e})
	case Node_Range:
		return e
	}
	unreachable()
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

// PRECEDENCE:
//
// Or              or
// And             and
// Equality        == !=
// Comparison      < <= > >=
// Addition        + -
// Multiplication  * /
binary_op :: proc(tag: Token_Tag) -> (Node_Tag, int) {
	#partial switch tag {
	case .Keyword_Or:
		return .Or, 1
	case .Keyword_And:
		return .And, 2
	case .Eq_Eq:
		return .Equal, 3
	case .Bang_Eq:
		return .Not_Equal, 3
	case .Lt:
		return .Less, 4
	case .Lt_Eq:
		return .Less_Equal, 4
	case .Gt:
		return .Greater, 4
	case .Gt_Eq:
		return .Greater_Equal, 4
	case .Plus:
		return .Add, 5
	case .Minus:
		return .Sub, 5
	case .Star:
		return .Mul, 6
	case .Slash:
		return .Div, 6
	}
	return .Root, 0
}

// Unary <- UnaryOp Unary
//        / KEYWORD_ECHO Expr
//        / Primary
parse_unary :: proc(p: ^Parser) -> (node: Node_Index, ok: bool) {
	tag: Node_Tag
	#partial switch peek_tag(p) {
	case .Minus:
		tag = .Negate
	case .Bang:
		tag = .Not
	case .Keyword_Echo:
		echo := advance(p)
		operand := parse_expression(p) or_return
		return add_node(p, {tag = .Echo, main_token = echo, data = {node = operand}}), true
	case:
		return parse_primary(p)
	}
	operator := advance(p)
	operand := parse_unary(p) or_return
	return add_node(p, {tag = tag, main_token = operator, data = {node = operand}}), true
}

// Primary <- NUMBER
//          / STRING
//          / KEYWORD_NIL
//          / KEYWORD_TRUE
//          / KEYWORD_FALSE
//          / IDENTIFIER
//          / PAREN_OPEN Expr PAREN_CLOSE
parse_primary :: proc(p: ^Parser) -> (node: Node_Index, ok: bool) {
	#partial switch peek_tag(p) {
	case .Number:
		return add_node(p, {tag = .Number_Literal, main_token = advance(p)}), true
	case .String:
		return add_node(p, {tag = .String_Literal, main_token = advance(p)}), true
	case .Keyword_Nil:
		return add_node(p, {tag = .Nil_Literal, main_token = advance(p)}), true
	case .Keyword_True:
		return add_node(p, {tag = .True_Literal, main_token = advance(p)}), true
	case .Keyword_False:
		return add_node(p, {tag = .False_Literal, main_token = advance(p)}), true
	case .Identifier:
		return add_node(p, {tag = .Identifier, main_token = advance(p)}), true
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

peek_tag :: proc(p: ^Parser) -> Token_Tag {
	return p.tokens[p.i].tag
}

advance :: proc(p: ^Parser) -> (i: Token_Index) {
	i = Token_Index(p.i)
	if peek_tag(p) != .EOF do p.i += 1
	if p.depth > 0 {
		for peek_tag(p) == .Newline do p.i += 1
	}
	return
}

expect :: proc(p: ^Parser, tag: Token_Tag) -> (token: Token_Index, ok: bool) {
	if peek_tag(p) != tag {
		add_error(p, {tag = .Expected_Token, expected = tag})
		return
	}
	return advance(p), true
}

expect_stmt_end :: proc(p: ^Parser) -> (ok: bool) {
	#partial switch peek_tag(p) {
	case .Semi, .Newline:
		advance(p)
		return true
	case .Paren_Close, .Brace_Close, .EOF:
		return true
	}
	add_error(p, {tag = .Expected_Stmt_End})
	return false
}

synchronize :: proc(p: ^Parser) {
	for peek_tag(p) != .EOF {
		if peek_tag(p) == .Brace_Close do return
		tag := p.tokens[advance(p)].tag
		if tag == .Semi || tag == .Newline do return
	}
}

add_node :: proc(p: ^Parser, node: Node) -> Node_Index {
	append(&p.nodes, node)
	return Node_Index(len(p.nodes) - 1)
}

add_extra :: proc(p: ^Parser, item: $T) -> Extra_Index where size_of(T) % size_of(u32) == 0,
	align_of(T) <= align_of(u32) {
	start := len(p.extra)
	data := transmute([size_of(T) / size_of(u32)]u32)item
	append(&p.extra, ..data[:])
	return Extra_Index(start)
}

make_range :: proc(p: ^Parser, items: []Node_Index) -> Node_Range {
	start := len(p.extra)
	append(&p.extra, ..transmute([]u32)items)
	return {Extra_Index(start), Extra_Index(len(p.extra))}
}

add_error :: proc(p: ^Parser, error: Error) {
	error := error
	if error.token == 0 {
		error.token = Token_Index(p.i)
		if previous := p.i - 1; previous >= 0 {
			tag := p.tokens[previous].tag
			start, end := p.tokens[previous].start, p.tokens[p.i].start
			if tag != .Semi &&
			   tag != .Newline &&
			   tag != .Brace_Open &&
			   strings.contains_rune(p.source[start:end], '\n') {
				error.after_previous = true
				error.previous = Token_Index(previous)
			}
		}
	}
	append(&p.errors, error)
}
