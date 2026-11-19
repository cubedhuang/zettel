package zettel_runtime

import "../common"
import "core:slice"

Program :: struct {
	main: Chunk,
}

Chunk :: struct {
	code:      []u8,
	// The source of each byte in `code`.
	spans:     []common.Span,
	constants: []Value,
}

program_destroy :: proc(program: ^Program) {
	delete(program.main.code)
	delete(program.main.spans)
	delete(program.main.constants)
}

// `module` can be destroyed afterwards.
load :: proc(vm: ^Vm, module: common.Module) -> Program {
	return {main = load_chunk(vm, module.main)}
}

load_chunk :: proc(vm: ^Vm, chunk: common.Chunk) -> Chunk {
	constants := make([]Value, len(chunk.constants))
	for constant, index in chunk.constants {
		switch c in constant {
		case f64:
			constants[index] = to_value(c)
		case common.Constant_String:
			s := chunk.string_bytes[c.start:][:c.len]
			value := intern_clone(vm, string(s))
			constants[index] = to_value(value)
		}
	}
	return {
		code = slice.clone(chunk.code),
		spans = slice.clone(chunk.spans),
		constants = constants,
	}
}
