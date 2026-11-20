package zettel_runtime

import "../common"
import "core:path/filepath"
import "core:slice"
import "core:strings"

Program :: struct {
	main:  Chunk,
	// Owned by the `Vm`.
	class: ^Obj_Class,
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
//
// Loading a path that was loaded (e.g., for the REPL) before reuses its class.
load :: proc(vm: ^Vm, path: string, module: common.Module) -> Program {
	class, found := vm.modules[path]
	if !found {
		class = new(Obj_Class)
		class.tag = .Class
		class.name = intern_clone(vm, filepath.short_stem(path))
		class.next = vm.objects
		vm.objects = class
		vm.modules[strings.clone(path)] = class
	}
	for len(class.statics) < common.static_count(module.statics) {
		append(&class.statics, UNDEFINED)
	}
	return {main = load_chunk(vm, module, module.main), class = class}
}

// `chunk` belongs to `module`.
load_chunk :: proc(vm: ^Vm, module: common.Module, chunk: common.Chunk) -> Chunk {
	constants := make([]Value, len(chunk.constants))
	for constant, index in chunk.constants {
		switch c in constant {
		case f64:
			constants[index] = to_value(c)
		case common.Constant_String:
			s := module.string_bytes[c.start:][:c.len]
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
