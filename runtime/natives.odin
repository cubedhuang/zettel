package zettel_runtime

import "../common"
import "core:io"

VARIADIC :: -1

Native_Proc :: #type proc(vm: ^Vm, args: []Value) -> (result: Value, error: string)

Native :: struct {
	procedure: Native_Proc,
	arity:     int,
}

builtin_natives := [common.Builtin]Native {
	.Print = {native_print, VARIADIC},
}

native_print :: proc(vm: ^Vm, args: []Value) -> (result: Value, error: string) {
	for arg, i in args {
		if i > 0 do io.write_byte(vm.out, ' ')
		write_value(vm.out, arg, quote_strings = false)
	}
	io.write_byte(vm.out, '\n')
	return NIL, ""
}
