package zettel_runtime

import "../common"
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
	Instance,
}

Obj_String :: struct {
	using obj: Obj,
	text:      string,
}

Obj_Class :: struct {
	using obj:     Obj,
	// For a file's root class, the file's stem.
	name:          ^Obj_String,
	// The class it's declared in, or nil for a file's class.
	outer:         ^Obj_Class,
	statics:       [dynamic]Value,
	// The slot of each static by name, for property access.
	slots:         map[^Obj_String]int,
	// Every field name that instances of the class have added, in the order they were first
	// added. A name's index never changes, and every instance stores the field at that index.
	field_names:   [dynamic]^Obj_String,
	// The index of each name in `field_names`.
	field_indices: map[^Obj_String]int,
}

// A function's code. Programs only see `Obj_Closure`s.
Obj_Function :: struct {
	using obj:     Obj,
	kind:          common.Function_Kind,
	// nil for a class body.
	name:          ^Obj_String,
	// Doesn't count a rest parameter.
	arity:         int,
	// Whether the last parameter collects the remaining arguments into an array.
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

Obj_Instance :: struct {
	using obj: Obj,
	class:     ^Obj_Class,
	// Indexed like `class.field_names`. A field that the instance doesn't have is `UNDEFINED` or
	// past the end.
	fields:    [dynamic]Value,
	// Set when the constructor that made the instance returns. Afterwards, fields can't be added.
	sealed:    bool,
}

Obj_Native :: struct {
	using obj: Obj,
	name:      ^Obj_String,
	// The minimum argument count when variadic.
	arity:     int,
	// Whether it takes any number of arguments after `arity`. It gets them as separate arguments.
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
	} else when T == Obj_Instance {
		obj.tag = .Instance
	} else {
		#panic("not an object type")
	}
	obj.next = vm.objects
	vm.objects = obj
	return obj
}

new_class :: proc(vm: ^Vm, name: ^Obj_String, outer: ^Obj_Class) -> ^Obj_Class {
	class := new_obj(vm, Obj_Class)
	class.name = name
	class.outer = outer
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

new_instance :: proc(vm: ^Vm, class: ^Obj_Class) -> ^Obj_Instance {
	instance := new_obj(vm, Obj_Instance)
	instance.class = class
	return instance
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
		delete(class.slots)
		delete(class.field_names)
		delete(class.field_indices)
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
	case .Instance:
		instance := (^Obj_Instance)(obj)
		delete(instance.fields)
		free(instance)
	}
}

// Returns the index of the instance's field with the name, or -1.
find_field :: proc(instance: ^Obj_Instance, name: ^Obj_String) -> int {
	index, found := instance.class.field_indices[name]
	if !found || index >= len(instance.fields) || instance.fields[index] == UNDEFINED do return -1
	return index
}

// Adds a field that the instance doesn't have yet.
add_field :: proc(instance: ^Obj_Instance, name: ^Obj_String, value: Value) {
	class := instance.class
	index, found := class.field_indices[name]
	if !found {
		index = len(class.field_names)
		append(&class.field_names, name)
		class.field_indices[name] = index
	}
	for len(instance.fields) <= index do append(&instance.fields, UNDEFINED)
	instance.fields[index] = value
}

// The arrays and instances being written, innermost first, so one that contains itself is written as
// `[...]` or `Name[...]`.
Writing :: struct {
	obj:   ^Obj,
	outer: ^Writing,
}

write_obj :: proc(w: io.Writer, obj: ^Obj, quote_strings := true, writing: ^Writing = nil) {
	switch obj.tag {
	case .String:
		s := (^Obj_String)(obj)
		if quote_strings {
			// escaped the way string literals are, so the output reads back as the same string
			io.write_quoted_string(w, s.text)
		} else {
			io.write_string(w, s.text)
		}
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
		if is_writing(writing, obj) {
			io.write_string(w, "[...]")
			return
		}
		inner := Writing{obj, writing}
		io.write_byte(w, '[')
		for item, i in array.items {
			if i > 0 do io.write_string(w, ", ")
			// elements are always quoted so `["a, b"]` and `["a", "b"]` look different
			write_value(w, item, true, &inner)
		}
		io.write_byte(w, ']')
	case .Instance:
		instance := (^Obj_Instance)(obj)
		io.write_string(w, instance.class.name.text)
		if is_writing(writing, obj) {
			io.write_string(w, "[...]")
			return
		}
		inner := Writing{obj, writing}
		io.write_byte(w, '[')
		first := true
		for value, index in instance.fields {
			if value == UNDEFINED do continue
			if !first do io.write_string(w, ", ")
			first = false
			io.write_string(w, instance.class.field_names[index].text)
			io.write_string(w, " = ")
			write_value(w, value, true, &inner)
		}
		io.write_byte(w, ']')
	}
}

is_writing :: proc(writing: ^Writing, obj: ^Obj) -> bool {
	for outer := writing; outer != nil; outer = outer.outer {
		if outer.obj == obj do return true
	}
	return false
}

write_function :: proc(w: io.Writer, function: ^Obj_Function) {
	io.write_string(w, "<fn")
	if function.name != nil {
		io.write_byte(w, ' ')
		io.write_string(w, function.name.text)
	}
	io.write_byte(w, '>')
}
