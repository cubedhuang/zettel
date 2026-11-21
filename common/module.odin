// The common package holds the data that the compiler and the runtime share: the bytecode format
// and debug data such as `Span`s.
package common

// A module is a compiled file. A file is the body of a class.
Module :: struct {
	// The file's class body.
	main:         Chunk,
	functions:    []Function,
	// The file's class is first, and the classes it declares follow.
	classes:      []Class,
	// Bytes of every chunk's string constants.
	string_bytes: []u8,
}

Function :: struct {
	kind:          Function_Kind,
	// Index into `Module.string_bytes`.
	name:          Constant_String,
	// Index into `Module.classes`. The class whose statics the function uses.
	class:         u32,
	// Doesn't count a rest parameter, or the `self` parameter of a constructor.
	arity:         int,
	// Whether the last parameter collects the remaining arguments into an array.
	variadic:      bool,
	upvalue_count: int,
	chunk:         Chunk,
}

Function_Kind :: enum u8 {
	Function,
	// Calling it makes a new instance of its class, which it gets as its first parameter and
	// returns.
	Constructor,
	// The body of a class declared in another class. It's called once, when the declaration runs.
	Class_Body,
}

// A class declared in a module.
Class :: struct {
	// Index into `Module.string_bytes`. Empty for the file's class, which is named after the file.
	name:    Constant_String,
	// Index into `Module.classes` of the class it's declared in. Unused for the file's class.
	outer:   u32,
	statics: Static_Names,
}

Chunk :: struct {
	code:      []u8,
	// The source of each byte in `code`.
	//
	// TODO: make this more space-efficient
	spans:     []Span,
	constants: []Constant,
}

Constant :: union {
	f64,
	Constant_String,
	Constant_Function,
	Constant_Class,
}

Constant_Function :: struct {
	// Index into `Module.functions`.
	index: u32,
}

Constant_Class :: struct {
	// Index into `Module.classes`.
	index: u32,
}

Constant_String :: struct {
	// Index into `Module.string_bytes`.
	start: u32,
	len:   u32,
}

// Names of a class's static variables.
Static_Names :: struct {
	bytes: []u8,
	// The end of each name in `bytes`.
	ends:  []u32,
}

module_destroy :: proc(module: ^Module) {
	chunk_destroy(&module.main)
	for &function in module.functions do chunk_destroy(&function.chunk)
	delete(module.functions)
	for &class in module.classes do static_names_destroy(&class.statics)
	delete(module.classes)
	delete(module.string_bytes)
}

chunk_destroy :: proc(chunk: ^Chunk) {
	delete(chunk.code)
	delete(chunk.spans)
	delete(chunk.constants)
}

static_names_destroy :: proc(names: ^Static_Names) {
	delete(names.bytes)
	delete(names.ends)
}

constant_string :: proc(module: Module, s: Constant_String) -> string {
	return string(module.string_bytes[s.start:][:s.len])
}

function_name :: proc(module: Module, function: Function) -> string {
	return constant_string(module, function.name)
}

class_name :: proc(module: Module, class: Class) -> string {
	return constant_string(module, class.name)
}

static_count :: proc(names: Static_Names) -> int {
	return len(names.ends)
}

static_name :: proc(names: Static_Names, slot: int) -> string {
	start := names.ends[slot - 1] if slot > 0 else 0
	return string(names.bytes[start:names.ends[slot]])
}
