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

// Returns the class body as a closure to `run`. `source` and `module` can be destroyed afterwards,
// because the `Vm` keeps a copy of `source` for runtime errors.
//
// Loading a path that was loaded (e.g., for the REPL) before reuses its class.
load :: proc(vm: ^Vm, source: ^common.Source, module: common.Module) -> ^Obj_Closure {
	append(&vm.sources, common.source_clone(source^))
	source_index := len(vm.sources) - 1

	class, found := vm.modules[source.path]
	if !found {
		class = new_class(vm, intern_clone(vm, filepath.short_stem(source.path)))
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
		functions[index].variadic = function.variadic
		functions[index].upvalue_count = function.upvalue_count
	}
	for function, index in module.functions {
		functions[index].chunk = load_chunk(vm, source_index, module, functions, function.chunk)
	}

	main := new_function(vm, class, nil, 0)
	main.chunk = load_chunk(vm, source_index, module, functions, module.main)
	return new_closure(vm, main)
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
			// See `common.Function.upvalue_count`.
			function := functions[c.index]
			if function.upvalue_count == 0 {
				constants[index] = to_value(new_closure(vm, function))
			} else {
				constants[index] = to_value(function)
			}
		}
	}
	return {
		code = slice.clone(chunk.code),
		spans = slice.clone(chunk.spans),
		constants = constants,
		source = source,
	}
}
