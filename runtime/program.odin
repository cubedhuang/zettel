package zettel_runtime

import "../bytecode"
import "core:slice"

Program :: struct {
	main: Chunk,
}

Chunk :: struct {
	code:      []u8,
	constants: []Value,
}

program_destroy :: proc(program: ^Program) {
	delete(program.main.code)
	delete(program.main.constants)
}

// `module` can be destroyed afterwards.
load :: proc(vm: ^Vm, module: bytecode.Module) -> Program {
	return {main = load_chunk(vm, module.main)}
}

load_chunk :: proc(vm: ^Vm, chunk: bytecode.Chunk) -> Chunk {
	constants := make([]Value, len(chunk.constants))
	for constant, index in chunk.constants {
		switch c in constant {
		case f64:
			constants[index] = c
		case bytecode.Constant_String:
			unreachable()
		}
	}
	return {code = slice.clone(chunk.code), constants = constants}
}
