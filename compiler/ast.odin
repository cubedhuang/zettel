package compiler

// Design inspired by Zig's https://codeberg.org/ziglang/zig/src/branch/master/lib/std/zig/Ast.zig
Ast :: struct {
	source: string,
	tokens: #soa[dynamic]Token,
	nodes:  #soa[dynamic]Node,
	extra:  [dynamic]u32,
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

Node_Tag :: enum {
	// Guaranteed to be at index 0 of the node list. `data` is an `extra_range` of statements.
	//
	// The `main_token` field is 0.
	Root,
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
	extra_range:    struct {
		start, end: Extra_Index,
	},
}
