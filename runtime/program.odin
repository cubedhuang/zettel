package zettel_runtime

import "../common"
import "core:path/filepath"
import "core:slice"
import "core:strings"

Chunk :: struct {
	code:      []u8,
	// The source of each byte in `code`.
	spans:     []common.Span,
	constants: []Value,
	// Index into `Vm.sources`, where `spans` point.
	source:    int,
}

chunk_destroy :: proc(chunk: ^Chunk) {
	delete(chunk.code)
	delete(chunk.spans)
	delete(chunk.constants)
}

// Returns the class body as a function to `run`. `source` and `module` can be destroyed afterwards,
// because the `Vm` keeps a copy of `source` for runtime errors.
//
// Loading a path that was loaded (e.g., for the REPL) before reuses its class.
load :: proc(vm: ^Vm, source: ^common.Source, module: common.Module) -> ^Obj_Function {
	append(&vm.sources, common.source_clone(source^))
	source_index := len(vm.sources) - 1

	class, found := vm.modules[source.path]
	if !found {
		class = new(Obj_Class)
		class.tag = .Class
		class.name = intern_clone(vm, filepath.short_stem(source.path))
		track(vm, class)
		vm.modules[strings.clone(source.path)] = class
	}
	for len(class.statics) < common.static_count(module.statics) {
		append(&class.statics, UNDEFINED)
	}

	// Chunks can refer to any function, so they're all made before loading chunks.
	functions := make([]^Obj_Function, len(module.functions))
	defer delete(functions)
	for function, index in module.functions {
		name := intern_clone(vm, common.function_name(module, function))
		functions[index] = new_function(vm, class, name, function.arity)
	}
	for function, index in module.functions {
		functions[index].chunk = load_chunk(vm, source_index, module, functions, function.chunk)
	}

	main := new_function(vm, class, nil, 0)
	main.chunk = load_chunk(vm, source_index, module, functions, module.main)
	return main
}

new_function :: proc(
	vm: ^Vm,
	class: ^Obj_Class,
	name: ^Obj_String,
	arity: int,
) -> ^Obj_Function {
	function := new(Obj_Function)
	function.tag = .Function
	function.name = name
	function.arity = arity
	function.class = class
	track(vm, function)
	return function
}

// `chunk` belongs to `module`, and `functions` are the loaded `module.functions`. `source` indexes
// `vm.sources`.
load_chunk :: proc(
	vm: ^Vm,
	source: int,
	module: common.Module,
	functions: []^Obj_Function,
	chunk: common.Chunk,
) -> Chunk {
	constants := make([]Value, len(chunk.constants))
	for constant, index in chunk.constants {
		switch c in constant {
		case f64:
			constants[index] = to_value(c)
		case common.Constant_String:
			value := intern_clone(vm, common.constant_string(module, c))
			constants[index] = to_value(value)
		case common.Constant_Function:
			constants[index] = to_value(functions[c.index])
		}
	}
	return {
		code = slice.clone(chunk.code),
		spans = slice.clone(chunk.spans),
		constants = constants,
		source = source,
	}
}
