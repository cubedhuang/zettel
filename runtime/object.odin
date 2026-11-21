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
	Array,
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
	// Doesn't count a rest parameter.
	arity:         int,
	// Whether extra arguments are collected into an array for the last parameter.
	variadic:      bool,
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

Obj_Array :: struct {
	using obj: Obj,
	items:     [dynamic]Value,
}

Obj_Native :: struct {
	using obj: Obj,
	name:      ^Obj_String,
	// The minimum argument count when variadic.
	arity:     int,
	// Whether it takes any number of arguments after `arity`. They aren't collected into an array.
	variadic:  bool,
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
	} else when T == Obj_Array {
		obj.tag = .Array
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
	obj.variadic = native.variadic
	obj.procedure = native.procedure
	return obj
}

// Takes ownership of `items`.
new_array :: proc(vm: ^Vm, items: [dynamic]Value) -> ^Obj_Array {
	array := new_obj(vm, Obj_Array)
	array.items = items
	return array
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
	case .Array:
		array := (^Obj_Array)(obj)
		delete(array.items)
		free(array)
	}
}

// The arrays being written, innermost first, so an array that contains itself is written as `[...]`.
Writing_Array :: struct {
	array: ^Obj_Array,
	outer: ^Writing_Array,
}

write_obj :: proc(w: io.Writer, obj: ^Obj, quote_strings := true, writing: ^Writing_Array = nil) {
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
	case .Array:
		array := (^Obj_Array)(obj)
		for outer := writing; outer != nil; outer = outer.outer {
			if outer.array == array {
				io.write_string(w, "[...]")
				return
			}
		}
		inner := Writing_Array{array, writing}
		io.write_byte(w, '[')
		for item, i in array.items {
			if i > 0 do io.write_string(w, ", ")
			// elements are always quoted so `["a, b"]` and `["a", "b"]` look different
			write_value(w, item, true, &inner)
		}
		io.write_byte(w, ']')
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
