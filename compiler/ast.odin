package compiler

import "../common"
import "core:fmt"
import "core:slice"
import "core:strings"

// Design inspired by Zig's https://codeberg.org/ziglang/zig/src/branch/master/lib/std/zig/Ast.zig
Ast :: struct {
	// Externally owned.
	source: string,
	tokens: #soa[]Token,
	nodes:  #soa[]Node,
	extra:  []u32,
	errors: []Error,
}

ast_destroy :: proc(ast: ^Ast) {
	delete(ast.tokens)
	delete(ast.nodes)
	delete(ast.extra)
	delete(ast.errors)
}

extra_data :: proc(ast: Ast, index: Extra_Index, $T: typeid) -> T {
	return (^T)(&ast.extra[index])^
}

extra_data_slice :: proc(ast: Ast, range: Node_Range, $T: typeid) -> []T {
	return transmute([]T)ast.extra[range.start:range.end]
}

root_statements :: proc(ast: Ast) -> []Node_Index {
	return extra_data_slice(ast, ast.nodes[0].data.extra_range, Node_Index)
}

block_statements :: proc(ast: Ast, index: Node_Index) -> []Node_Index {
	return extra_data_slice(ast, ast.nodes[index].data.extra_range, Node_Index)
}

assign_targets :: proc(ast: Ast, index: Node_Index) -> []Node_Index {
	#partial switch ast.nodes[index].tag {
	case .Assign, .Decl:
		return slice.from_ptr(&ast.nodes[index].data.node_and_node.lhs, 1)
	case .Assign_Multi, .Decl_Multi:
		data := extra_data(ast, ast.nodes[index].data.extra, Multi_Assign)
		return extra_data_slice(ast, data.lhs, Node_Index)
	}
	panic("tag of assign_targets node must be assign or decl")
}

assign_values :: proc(ast: Ast, index: Node_Index) -> []Node_Index {
	#partial switch ast.nodes[index].tag {
	case .Assign, .Decl:
		return slice.from_ptr(&ast.nodes[index].data.node_and_node.rhs, 1)
	case .Assign_Multi, .Decl_Multi:
		data := extra_data(ast, ast.nodes[index].data.extra, Multi_Assign)
		return extra_data_slice(ast, data.rhs, Node_Index)
	}
	panic("tag of assign_values node must be assign or decl")
}

token_text :: proc(ast: Ast, index: Token_Index) -> string {
	tag := ast.tokens[index].tag
	if lexeme := token_lexemes[tag]; len(lexeme) > 0 {
		return lexeme
	}

	start := ast.tokens[index].start
	tokenizer := Tokenizer {
		source = ast.source,
		offset = int(start),
	}
	scan(&tokenizer)
	return ast.source[start:tokenizer.offset]
}

token_span :: proc(ast: Ast, index: Token_Index) -> common.Span {
	return tokens_span(ast, index, index, index)
}

node_span :: proc(ast: Ast, index: Node_Index) -> common.Span {
	return tokens_span(
		ast,
		first_token(ast, index),
		last_token(ast, index),
		ast.nodes[index].main_token,
	)
}

tokens_span :: proc(ast: Ast, first, last, main: Token_Index) -> common.Span {
	first, last := first, last
	switch {
	case tokens_on_same_line(ast, first, last):
	case tokens_on_same_line(ast, first, main):
		last = main
	case tokens_on_same_line(ast, main, last):
		first = main
	case:
		first, last = main, main
	}
	return {
		start = ast.tokens[first].start,
		end = token_end(ast, last),
		main = ast.tokens[main].start,
	}
}

error_span :: proc(ast: Ast, error: Error) -> common.Span {
	if error.after_previous {
		end := token_end(ast, error.previous)
		return {start = end, end = end, main = end}
	}
	return token_span(ast, error.token)
}

token_end :: proc(ast: Ast, index: Token_Index) -> u32 {
	return ast.tokens[index].start + u32(len(token_text(ast, index)))
}

tokens_on_same_line :: proc(ast: Ast, a, b: Token_Index) -> bool {
	return !strings.contains_rune(ast.source[ast.tokens[a].start:ast.tokens[b].start], '\n')
}

first_token :: proc(ast: Ast, index: Node_Index) -> Token_Index {
	index := index
	for {
		node := ast.nodes[index]
		switch node.tag {
		case .Root:
			return 0
		case .Block,
		     .Number_Literal,
		     .String_Literal,
		     .Nil_Literal,
		     .True_Literal,
		     .False_Literal,
		     .Identifier,
		     .Grouped,
		     .Negate,
		     .Not:
			return node.main_token
		case .Assign,
		     .Decl,
		     .Add,
		     .Sub,
		     .Mul,
		     .Div,
		     .Equal,
		     .Not_Equal,
		     .Less,
		     .Less_Equal,
		     .Greater,
		     .Greater_Equal:
			index = node.data.node_and_node.lhs
		case .Assign_Multi, .Decl_Multi:
			index = assign_targets(ast, index)[0]
		}
	}
}

last_token :: proc(ast: Ast, index: Node_Index) -> Token_Index {
	index := index
	for {
		node := ast.nodes[index]
		switch node.tag {
		case .Root:
			return Token_Index(len(ast.tokens) - 1)
		case .Block:
			// the '}' isn't stored, but only ';' can be between it and the last statement
			token := node.main_token
			if statements := block_statements(ast, index); len(statements) > 0 {
				token = last_token(ast, statements[len(statements) - 1])
			}
			token += 1
			for ast.tokens[token].tag == .Semi do token += 1
			return token
		case .Number_Literal,
		     .String_Literal,
		     .Nil_Literal,
		     .True_Literal,
		     .False_Literal,
		     .Identifier:
			return node.main_token
		case .Grouped:
			return node.data.token_and_node.token
		case .Negate, .Not:
			index = node.data.node
		case .Assign,
		     .Decl,
		     .Add,
		     .Sub,
		     .Mul,
		     .Div,
		     .Equal,
		     .Not_Equal,
		     .Less,
		     .Less_Equal,
		     .Greater,
		     .Greater_Equal:
			index = node.data.node_and_node.rhs
		case .Assign_Multi, .Decl_Multi:
			values := assign_values(ast, index)
			index = values[len(values) - 1]
		}
	}
}

// Index into Ast.tokens.
Token_Index :: distinct u32
// Index into Ast.nodes. Because the root is always at index 0, 0 is the empty value.
Node_Index :: distinct u32
// Index into Ast.extra.
Extra_Index :: distinct u32

Node :: struct {
	tag:        Node_Tag,
	main_token: Token_Index,
	data:       Node_Data,
}

Node_Tag :: enum u8 {
	// Guaranteed to be at index 0 of the node list.
	//
	// The `data` field is an `extra_range` of statements.
	//
	// The `main_token` field is 0.
	Root,

	// ---------- Statements ----------

	// `{ ... }`.
	//
	// The `data` field is `extra_range`.
	//
	// The `main_token` field is the `{`.
	Block,
	// `lhs = rhs`.
	//
	// The `data` field is `node_and_node`.
	//
	// The `main_token` field is the `=`.
	Assign,
	// `lhs0, lhs1, ... = rhs0, rhs1, ...`.
	//
	// The `data` field is `extra`, pointing at a `Multi_Assign`.
	//
	// The `main_token` field is the `=`.
	Assign_Multi,
	// `name := value`. Same layout as `Assign`. `lhs` must be an `Identifier` node.
	//
	// The `main_token` field is the `=`.
	Decl,
	// `a, b := ...`. Same layout as `Assign_Multi`.
	Decl_Multi,

	// ---------- Expressions ----------

	// The `data` field is unused.
	Number_Literal,
	// The `data` field is unused.
	String_Literal,
	// `nil`. The `data` field is unused.
	Nil_Literal,
	// `true`. The `data` field is unused.
	True_Literal,
	// `false`. The `data` field is unused.
	False_Literal,
	// The `data` field is unused.
	Identifier,
	// `(node)`.
	//
	// The `data` field is `token_and_node`. The token is the `)` and the node is the sub-expression.
	//
	// The `main_token` field is the `(`.
	Grouped,
	// `-node`.
	//
	// The `data` field is the operand.
	//
	// The `main_token` field is the `-`.
	Negate,
	// `!node`. Same layout as `Negate`.
	Not,
	// `lhs + rhs`.
	//
	// For all binary operations, the `data` field is `node_and_node` with both operands.
	//
	// The `main_token` field is the operator.
	Add,
	// `lhs - rhs`
	Sub,
	// `lhs * rhs`
	Mul,
	// `lhs / rhs`
	Div,
	// `lhs == rhs`
	Equal,
	// `lhs != rhs`
	Not_Equal,
	// `lhs < rhs`
	Less,
	// `lhs <= rhs`
	Less_Equal,
	// `lhs > rhs`
	Greater,
	// `lhs >= rhs`
	Greater_Equal,
}

Node_Data :: struct #raw_union {
	node:           Node_Index,
	token:          Token_Index,
	extra:          Extra_Index,
	node_and_node:  struct {
		lhs, rhs: Node_Index,
	},
	node_and_extra: struct {
		node:  Node_Index,
		extra: Extra_Index,
	},
	token_and_node: struct {
		token: Token_Index,
		node:  Node_Index,
	},
	extra_range:    Node_Range,
}

Node_Range :: struct {
	// `end` is exclusive.
	start, end: Extra_Index,
}

Multi_Assign :: struct {
	lhs: Node_Range,
	rhs: Node_Range,
}

Error :: struct {
	tag:            Error_Tag,
	token:          Token_Index,
	// Only used for `Expected_Token`.
	expected:       Token_Tag,
	// Set when `token` is on a later line than the unfinished code before it.
	// The error is then reported at the end of `previous`.
	after_previous: bool,
	previous:       Token_Index,
}

Error_Tag :: enum u8 {
	Expected_Expression,
	Expected_Token,
	Expected_Stmt_End,
	Invalid_Expression_List,
	Invalid_Declaration_Target,
	Too_Many_Rhs,
}

// Uses `context.temp_allocator`.
parse_error_message :: proc(ast: Ast, error: Error) -> string {
	found := token_names[ast.tokens[error.token].tag]
	switch error.tag {
	case .Expected_Expression:
		return fmt.tprintf("expected expression, got %v", found)
	case .Expected_Token:
		return fmt.tprintf("expected %v, got %v", token_names[error.expected], found)
	case .Expected_Stmt_End:
		return fmt.tprintf("expected end of statement, got %v", found)
	case .Invalid_Expression_List:
		return "expected '=' or ':=' after expression list"
	case .Invalid_Declaration_Target:
		return "can only declare identifiers"
	case .Too_Many_Rhs:
		return "more values than targets"
	}
	unreachable()
}
