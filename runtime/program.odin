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

// The objects that `load` made for a module, which its chunks refer to.
Loaded :: struct {
	// Index into `Vm.sources`.
	source:    int,
	functions: []^Obj_Function,
	classes:   []^Obj_Class,
}

chunk_destroy :: proc(chunk: ^Chunk) {
	delete(chunk.code)
	delete(chunk.spans)
	delete(chunk.constants)
}

// Returns the class body as a closure to `run`. `source` and `module` can be destroyed afterwards,
// because the `Vm` keeps a copy of `source` for runtime errors.
//
// If the path was loaded before (for example, in the REPL), this reuses its class.
load :: proc(vm: ^Vm, source: ^common.Source, module: common.Module) -> ^Obj_Closure {
	append(&vm.sources, common.source_clone(source^))
	source_index := len(vm.sources) - 1

	classes := make([]^Obj_Class, len(module.classes))
	defer delete(classes)
	root, found := vm.modules[source.path]
	if !found {
		root = new_class(vm, intern_clone(vm, filepath.short_stem(source.path)), nil)
		vm.modules[strings.clone(source.path)] = root
	}
	classes[0] = root
	for class, index in module.classes {
		if index > 0 {
			name := intern_clone(vm, common.class_name(module, class))
			// a class comes after the class it's declared in
			classes[index] = new_class(vm, name, classes[class.outer])
		}
		loaded := classes[index]
		for slot in len(loaded.statics) ..< common.static_count(class.statics) {
			append(&loaded.statics, UNDEFINED)
			loaded.slots[intern_clone(vm, common.static_name(class.statics, slot))] = slot
		}
	}

	// Chunks can refer to any function, so this makes all functions before it loads the chunks.
	functions := make([]^Obj_Function, len(module.functions))
	defer delete(functions)
	for function, index in module.functions {
		name := intern_clone(vm, common.function_name(module, function))
		functions[index] = new_function(vm, classes[function.class], name, function.arity)
		functions[index].kind = function.kind
		functions[index].variadic = function.variadic
		functions[index].upvalue_count = function.upvalue_count
	}
	loaded := Loaded{source_index, functions, classes}
	for function, index in module.functions {
		functions[index].chunk = load_chunk(vm, module, loaded, function.chunk)
	}

	main := new_function(vm, root, nil, 0)
	main.kind = .Class_Body
	main.chunk = load_chunk(vm, module, loaded, module.main)
	return new_closure(vm, main)
}

// `chunk` belongs to `module`.
load_chunk :: proc(vm: ^Vm, module: common.Module, loaded: Loaded, chunk: common.Chunk) -> Chunk {
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
			function := loaded.functions[c.index]
			if function.upvalue_count == 0 {
				constants[index] = to_value(new_closure(vm, function))
			} else {
				constants[index] = to_value(function)
			}
		case common.Constant_Class:
			constants[index] = to_value(loaded.classes[c.index])
		}
	}
	return {
		code = slice.clone(chunk.code),
		spans = slice.clone(chunk.spans),
		constants = constants,
		source = loaded.source,
	}
}
