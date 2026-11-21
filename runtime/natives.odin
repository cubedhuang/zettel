package zettel_runtime

import "../common"
import "core:io"

VARIADIC :: -1

// A non-empty `error` is a runtime error and may use `context.temp_allocator`.
Native_Proc :: #type proc(vm: ^Vm, args: []Value) -> (result: Value, error: string)

Native :: struct {
	procedure: Native_Proc,
	arity:     int,
}

builtin_natives := [common.Builtin]Native {
	.Print = {native_print, VARIADIC},
	.Len   = {native_len, 1},
	.Push  = {native_push, 2},
	.Pop   = {native_pop, 1},
}

native_print :: proc(vm: ^Vm, args: []Value) -> (result: Value, error: string) {
	for arg, i in args {
		if i > 0 do io.write_byte(vm.out, ' ')
		write_value(vm.out, arg, quote_strings = false)
	}
	io.write_byte(vm.out, '\n')
	return NIL, ""
}

native_len :: proc(vm: ^Vm, args: []Value) -> (result: Value, error: string) {
	if array, ok := as_array(args[0]); ok do return to_value(f64(len(array.items))), ""
	if obj, ok := as_obj(args[0]); ok && obj.tag == .String {
		return to_value(f64(len((^Obj_String)(obj).text))), ""
	}
	return NIL, "len expects an array or a string"
}

native_push :: proc(vm: ^Vm, args: []Value) -> (result: Value, error: string) {
	array, ok := as_array(args[0])
	if !ok do return NIL, "push expects an array"
	append(&array.items, args[1])
	return NIL, ""
}

// Removes and returns the last element.
native_pop :: proc(vm: ^Vm, args: []Value) -> (result: Value, error: string) {
	array, ok := as_array(args[0])
	if !ok do return NIL, "pop expects an array"
	if len(array.items) == 0 do return NIL, "can't pop from an empty array"
	return pop(&array.items), ""
}
