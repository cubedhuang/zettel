package compiler

// Design inspired by Zig's https://codeberg.org/ziglang/zig/src/branch/master/lib/std/zig/Ast.zig
Ast :: struct {
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

extra_data_slice :: proc(ast: Ast, range: Node_Range, $T: typeid) -> []T {
	return transmute([]T)ast.extra[range.start:range.end]
}

root_statements :: proc(ast: Ast) -> []Node_Index {
	return extra_data_slice(ast, ast.nodes[0].data.extra_range, Node_Index)
}

block_statements :: proc(ast: Ast, index: Node_Index) -> []Node_Index {
	return extra_data_slice(ast, ast.nodes[index].data.extra_range, Node_Index)
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

	// ---------- Expressions ----------

	// The `data` field is unused.
	Number_Literal,
	// The `data` field is unused.
	String_Literal,
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
}

Node_Data :: struct #raw_union {
	node:           Node_Index,
	token:          Token_Index,
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
	start, end: Extra_Index,
}

Error :: struct {
	tag:      Error_Tag,
	token:    Token_Index,
	// Only used for `Expected_Token`.
	expected: Token_Tag,
}

Error_Tag :: enum u8 {
	Expected_Expression,
	Expected_Token,
}
