// The common package contains data structures shared between the compiler and runtime, including
// the bytecode format and debugging information like `Span`s.
package common

// A module is the compiled form of a file, which is the body of a class.
Module :: struct {
	main:         Chunk,
	statics:      Static_Names,
	// Bytes of every chunk's string constants.
	string_bytes: []u8,
}

// Names of a class's static variables.
Static_Names :: struct {
	bytes: []u8,
	// The end of each name in `bytes`.
	ends:  []u32,
}

Chunk :: struct {
	code:         []u8,
	// The source of each byte in `code`.
	//
	// TODO: make this more space-efficient
	spans:        []Span,
	constants:    []Constant,
}

Constant :: union {
	f64,
	Constant_String,
}

Constant_String :: struct {
	// Index into `Module.string_bytes`.
	start: u32,
	len:   u32,
}

Op :: enum u8 {
	// Value
	//
	// Pushes one value onto the stack.
	Constant,
	Nil,
	True,
	False,
	// Unary
	//
	// Pops one value from the stack.
	Negate,
	Not,
	// Binary
	//
	// Pops two values from the stack.
	Add,
	Sub,
	Mul,
	Div,
	Equal,
	Not_Equal,
	Less,
	Less_Equal,
	Greater,
	Greater_Equal,
	// Control flow
	//
	// Jumps offsets are from the end of the instruction (i.e. offset 1 means ip += 3).
	// Leaves the condition on the stack.
	Jump,
	Jump_If_False,
	Jump_If_True,
	// Variables
	//
	// Get pushes the variable's value and Set pops a value into the variable.
	// Static indexes the class's statics and local indexes the stack.
	Get_Static,
	Set_Static,
	Get_Local,
	Set_Local,
	//
	Pop,
	Return,
	// Writes the top value to the output without popping it.
	Echo,
}

op_operand_size := #partial [Op]int {
	.Constant      = 2,
	.Jump          = 2,
	.Jump_If_False = 2,
	.Jump_If_True  = 2,
	.Get_Static    = 2,
	.Set_Static    = 2,
	.Get_Local     = 2,
	.Set_Local     = 2,
}

MAX_CONSTANTS :: 1 << 16
MAX_STATICS :: 1 << 16
MAX_LOCALS :: 1 << 16

module_destroy :: proc(module: ^Module) {
	chunk_destroy(&module.main)
	static_names_destroy(&module.statics)
	delete(module.string_bytes)
}

static_names_destroy :: proc(names: ^Static_Names) {
	delete(names.bytes)
	delete(names.ends)
}

static_count :: proc(names: Static_Names) -> int {
	return len(names.ends)
}

static_name :: proc(names: Static_Names, slot: int) -> string {
	start := names.ends[slot - 1] if slot > 0 else 0
	return string(names.bytes[start:names.ends[slot]])
}

chunk_destroy :: proc(chunk: ^Chunk) {
	delete(chunk.code)
	delete(chunk.spans)
	delete(chunk.constants)
}

read_u16 :: proc(code: []u8, offset: int) -> u16 {
	return u16(code[offset]) | u16(code[offset + 1]) << 8
}
