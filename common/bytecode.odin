package common

// The bytecode format: instructions, their operands, and how operands are encoded.

Op :: enum u8 {
	// Value
	//
	// Pushes one value onto the stack.
	Constant,
	Nil,
	True,
	False,
	// Pops the operand's number of values and pushes an array of them, in order.
	Array,
	// Pops a value and appends it to the array below it, which stays on the stack.
	Array_Push,
	// Pops an array and appends its elements to the array below it, which stays on the stack.
	Array_Extend,
	// Unary
	//
	// Pops one value from the stack.
	Negate,
	Not,
	Bit_Not,
	// Binary
	//
	// Pops two values from the stack.
	Add,
	Sub,
	Mul,
	Div,
	Mod,
	Mod_Floored,
	Pow,
	Bit_And,
	Bit_Or,
	Bit_Xor,
	Shift_Left,
	Shift_Right,
	Equal,
	Not_Equal,
	Less,
	Less_Equal,
	Greater,
	Greater_Equal,
	// Control flow
	//
	// Jump offsets start at the end of the instruction. For example, offset 1 means ip += 3.
	// Conditional jumps leave the condition on the stack.
	Jump,
	Jump_If_False,
	Jump_If_True,
	// Jumps backward. The offset also starts at the end of the instruction.
	Loop,
	// Variables
	//
	// `Get_*` pushes the value of the variable. `Set_*` pops a value into the variable.
	// The operand of `*_Static` indexes the statics of the class. The operand of `*_Local`
	// indexes the stack.
	Get_Static,
	Set_Static,
	Get_Local,
	Set_Local,
	// The operand is a `Builtin`.
	Get_Builtin,
	// The operand indexes the current closure's upvalues.
	Get_Upvalue,
	Set_Upvalue,
	// Pops the index, then the indexed value, and pushes the element.
	Get_Index,
	// Pops the index, then the indexed value, then the new element. The element is below the
	// others so that assignments can evaluate all their values first.
	Set_Index,
	// Like `Get_Index`, but leaves the indexed value and the index below the element. Compound
	// assignment uses it before `Update_Index`.
	Get_Index_Keep,
	// Pops the new element, then the index, then the indexed value.
	Update_Index,
	// Functions
	//
	// Pushes a new closure of a function that captures variables. The operand is the index of
	// the function's constant, followed by a `Capture` for each of its upvalues.
	Closure,
	// Moves the local on top of the stack into the upvalues that captured it, then pops it.
	Close_Upvalue,
	// Calls the value below its arguments, which are on top of the stack. The operands are the
	// argument count and the number of return values the caller expects, or `ALL_RESULTS`.
	// An argument count of `ALL_RESULTS` means the arguments are all the values of the call right
	// before it. Afterwards, the return values replace the callee and arguments.
	Call,
	// Like `Call`, but the arguments are an array on top of the stack, from spreading. The
	// operand is the expected number of return values.
	Call_Spread,
	// Pops the frame, including the callee, and pushes the return values in its place. The
	// operand is how many values are on top of the stack, or `ALL_RESULTS` to forward the values
	// of the call right before it.
	Return,
	//
	Pop,
	// Pops every value of the call right before it, which expected `ALL_RESULTS`.
	Pop_Results,
	// Writes the values of the call right before it, like `Echo_Result`, without popping them.
	Echo_Results,
	// Writes the top value to the output without popping it.
	Echo,
	// Like `Echo`, but writes nothing for `nil`. The REPL uses it.
	Echo_Result,
}

op_operand_size := #partial [Op]int {
	.Constant      = 2,
	.Array         = 2,
	.Jump          = 2,
	.Jump_If_False = 2,
	.Jump_If_True  = 2,
	.Loop          = 2,
	.Get_Static    = 2,
	.Set_Static    = 2,
	.Get_Local     = 2,
	.Set_Local     = 2,
	.Get_Builtin   = 1,
	.Get_Upvalue   = 1,
	.Set_Upvalue   = 1,
	// Does not include the captures.
	.Closure       = 2,
	.Call          = 2,
	.Call_Spread   = 1,
	.Return        = 1,
}

// As the expected result count of `Call` and `Call_Spread`, or as the count of `Return`, this means
// any number of values. The VM remembers the count until the next call returns. As the argument
// count of `Call`, it means that remembered count.
ALL_RESULTS :: 255

Capture :: struct {
	// Whether `index` is a local of the enclosing function, rather than one of its upvalues.
	is_local: bool,
	index:    u16,
}

CAPTURE_SIZE :: 3

Builtin :: enum u8 {
	Print,
	Len,
	Push,
	Pop,
}

builtin_names := [Builtin]string {
	.Print = "print",
	.Len   = "len",
	.Push  = "push",
	.Pop   = "pop",
}

MAX_CONSTANTS :: 1 << 16
MAX_STATICS :: 1 << 16
MAX_LOCALS :: 1 << 16
MAX_PARAMETERS :: ALL_RESULTS - 1
MAX_UPVALUES :: 256
MAX_ELEMENTS :: int(max(u16))
MAX_RESULTS :: ALL_RESULTS - 1

read_u16 :: proc(code: []u8, offset: int) -> u16 {
	return u16(code[offset]) | u16(code[offset + 1]) << 8
}

write_u16 :: proc(code: []u8, offset: int, value: u16) {
	code[offset] = u8(value)
	code[offset + 1] = u8(value >> 8)
}

read_capture :: proc(code: []u8, offset: int) -> Capture {
	return {is_local = code[offset] != 0, index = read_u16(code, offset + 1)}
}

write_capture :: proc(code: []u8, offset: int, capture: Capture) {
	code[offset] = u8(capture.is_local)
	write_u16(code, offset + 1, capture.index)
}
