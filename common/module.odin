// The common package contains data structures shared between the compiler and runtime, including
// the bytecode format and debugging information like `Span`s.
package common

Module :: struct {
	main: Chunk,
}

Chunk :: struct {
	code:         []u8,
	// The source of each byte in `code`.
	//
	// TODO: make this more space-efficient
	spans:        []Span,
	constants:    []Constant,
	string_bytes: []u8,
}

Constant :: union {
	f64,
	Constant_String,
}

Constant_String :: struct {
	// Index into `string_bytes`
	start: u32,
	len:   u32,
}

Op :: enum u8 {
	Constant,
	Nil,
	True,
	False,
	// Unary
	Negate,
	Not,
	// Binary
	Add,
	Sub,
	Mul,
	Div,
	Pop,
	Return,
	// TODO: get rid of this at some point
	Print,
}

op_operand_size := #partial [Op]int {
	.Constant = 2,
}

MAX_CONSTANTS :: 1 << 16

module_destroy :: proc(module: ^Module) {
	chunk_destroy(&module.main)
}

chunk_destroy :: proc(chunk: ^Chunk) {
	delete(chunk.code)
	delete(chunk.spans)
	delete(chunk.constants)
	delete(chunk.string_bytes)
}

read_u16 :: proc(code: []u8, offset: int) -> u16 {
	return u16(code[offset]) | u16(code[offset + 1]) << 8
}
