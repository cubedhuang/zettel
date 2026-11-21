package zettel_runtime

import "core:io"
import "core:strings"

Obj :: struct {
	tag:  Obj_Tag,
	next: ^Obj,
}

Obj_Tag :: enum u8 {
	String,
	Class,
	Function,
	Closure,
	Upvalue,
	Native,
}

Obj_String :: struct {
	using obj: Obj,
	text:      string,
}

Obj_Class :: struct {
	using obj: Obj,
	// For a file's root class, the file's stem.
	name:      ^Obj_String,
	statics:   [dynamic]Value,
}

// A function's code. Programs only see `Obj_Closure`s.
Obj_Function :: struct {
	using obj:     Obj,
	// nil for a class body.
	name:          ^Obj_String,
	arity:         int,
	upvalue_count: int,
	chunk:         Chunk,
	// The class whose statics the function uses.
	class:         ^Obj_Class,
}

Obj_Closure :: struct {
	using obj: Obj,
	function:  ^Obj_Function,
	upvalues:  []^Obj_Upvalue,
}

// While the variable's scope is running, the upvalue is open and refers to
// its stack slot. Afterwards, it's closed and holds the value itself.
Obj_Upvalue :: struct {
	using obj: Obj,
	// Stack index while open, or `CLOSED`.
	slot:      int,
	closed:    Value,
	// The next open upvalue, in `Vm.open_upvalues`.
	next_open: ^Obj_Upvalue,
}

CLOSED :: -1

Obj_Native :: struct {
	using obj: Obj,
	name:      ^Obj_String,
	// `VARIADIC` for any number of arguments.
	arity:     int,
	procedure: Native_Proc,
}

// Allocates an object that the `Vm` frees.
new_obj :: proc(vm: ^Vm, $T: typeid) -> ^T {
	obj := new(T)
	when T == Obj_String {
		obj.tag = .String
	} else when T == Obj_Class {
		obj.tag = .Class
	} else when T == Obj_Function {
		obj.tag = .Function
	} else when T == Obj_Closure {
		obj.tag = .Closure
	} else when T == Obj_Upvalue {
		obj.tag = .Upvalue
	} else when T == Obj_Native {
		obj.tag = .Native
	} else {
		#panic("not an object type")
	}
	obj.next = vm.objects
	vm.objects = obj
	return obj
}

new_class :: proc(vm: ^Vm, name: ^Obj_String) -> ^Obj_Class {
	class := new_obj(vm, Obj_Class)
	class.name = name
	return class
}

new_function :: proc(vm: ^Vm, class: ^Obj_Class, name: ^Obj_String, arity: int) -> ^Obj_Function {
	function := new_obj(vm, Obj_Function)
	function.name = name
	function.arity = arity
	function.class = class
	return function
}

new_closure :: proc(vm: ^Vm, function: ^Obj_Function) -> ^Obj_Closure {
	closure := new_obj(vm, Obj_Closure)
	closure.function = function
	closure.upvalues = make([]^Obj_Upvalue, function.upvalue_count)
	return closure
}

// The upvalue starts open.
new_upvalue :: proc(vm: ^Vm, slot: int) -> ^Obj_Upvalue {
	upvalue := new_obj(vm, Obj_Upvalue)
	upvalue.slot = slot
	return upvalue
}

new_native :: proc(vm: ^Vm, name: ^Obj_String, native: Native) -> ^Obj_Native {
	obj := new_obj(vm, Obj_Native)
	obj.name = name
	obj.arity = native.arity
	obj.procedure = native.procedure
	return obj
}

intern_clone :: proc(vm: ^Vm, text: string) -> ^Obj_String {
	if s, ok := vm.strings[text]; ok {
		return s
	}

	return intern_take(vm, strings.clone(text))
}

intern_take :: proc(vm: ^Vm, text: string) -> ^Obj_String {
	if s, ok := vm.strings[text]; ok {
		delete(text)
		return s
	}

	s := new_obj(vm, Obj_String)
	s.text = text
	vm.strings[s.text] = s
	return s
}

obj_free :: proc(obj: ^Obj) {
	switch obj.tag {
	case .String:
		s := (^Obj_String)(obj)
		delete(s.text)
		free(s)
	case .Class:
		class := (^Obj_Class)(obj)
		delete(class.statics)
		free(class)
	case .Function:
		function := (^Obj_Function)(obj)
		chunk_destroy(&function.chunk)
		free(function)
	case .Closure:
		closure := (^Obj_Closure)(obj)
		delete(closure.upvalues)
		free(closure)
	case .Upvalue:
		free((^Obj_Upvalue)(obj))
	case .Native:
		free((^Obj_Native)(obj))
	}
}

write_obj :: proc(w: io.Writer, obj: ^Obj, quote_strings := true) {
	switch obj.tag {
	case .String:
		s := (^Obj_String)(obj)
		if quote_strings do io.write_byte(w, '"')
		io.write_string(w, s.text)
		if quote_strings do io.write_byte(w, '"')
	case .Class:
		io.write_string(w, "<class ")
		io.write_string(w, (^Obj_Class)(obj).name.text)
		io.write_byte(w, '>')
	case .Function:
		write_function(w, (^Obj_Function)(obj))
	case .Closure:
		write_function(w, (^Obj_Closure)(obj).function)
	case .Upvalue:
		io.write_string(w, "<upvalue>")
	case .Native:
		io.write_string(w, "<fn ")
		io.write_string(w, (^Obj_Native)(obj).name.text)
		io.write_byte(w, '>')
	}
}

write_function :: proc(w: io.Writer, function: ^Obj_Function) {
	io.write_string(w, "<fn")
	if function.name != nil {
		io.write_byte(w, ' ')
		io.write_string(w, function.name.text)
	}
	io.write_byte(w, '>')
}
