package zettel_runtime

import "../bytecode"
import "core:io"
import "core:strings"

Vm :: struct {
	out:     io.Writer,
	stack:   [dynamic]Value,
	objects: ^Obj,
	strings: map[string]^Obj_String,
}

vm_destroy :: proc(vm: ^Vm) {
	delete(vm.stack)

	current := vm.objects
	for current != nil {
		next := current.next
		free(current)
		current = next
	}
}

run :: proc(vm: ^Vm, program: Program) {
	chunk := program.main
	ip := 0

	for {
		op := bytecode.Op(chunk.code[ip])
		ip += 1

		switch op {
		case .Constant:
			index := bytecode.read_u16(chunk.code, ip)
			ip += 2
			vm_push(vm, chunk.constants[index])
		case .Negate:
			vm_push(vm, -vm_pop(vm).(f64))
		case .Add:
			rhs, lhs := vm_pop(vm), vm_pop(vm)
			switch lhs in lhs {
			case ^Obj:
				rhs, ok := as_obj(rhs)
				if !ok {
					// TODO: improve errors
					panic("string can only be added with string")
				}
				a, b := (^Obj_String)(lhs), (^Obj_String)(rhs)
				result := strings.concatenate({a.text, b.text})
				vm_push(vm, intern_take(vm, result))
			case f64:
				rhs, ok := as_number(rhs)
				if !ok {
					panic("number can only be added with number")
				}
				vm_push(vm, lhs + rhs)
			}
		case .Sub:
			rhs, lhs := vm_pop(vm).(f64), vm_pop(vm).(f64)
			vm_push(vm, lhs - rhs)
		case .Mul:
			rhs, lhs := vm_pop(vm).(f64), vm_pop(vm).(f64)
			vm_push(vm, lhs * rhs)
		case .Div:
			rhs, lhs := vm_pop(vm).(f64), vm_pop(vm).(f64)
			vm_push(vm, lhs / rhs)
		case .Pop:
			vm_pop(vm)
		case .Print:
			write_value(vm.out, vm_pop(vm))
			io.write_byte(vm.out, '\n')
		case .Return:
			return
		}
	}
}

vm_push :: proc(vm: ^Vm, value: Value) {
	append(&vm.stack, value)
}

vm_pop :: proc(vm: ^Vm) -> Value {
	return pop(&vm.stack)
}

intern_take :: proc(vm: ^Vm, text: string) -> ^Obj_String {
	if s, ok := vm.strings[text]; ok {
		delete(text)
		return s
	}

	s := new(Obj_String)
	s.tag = .String
	s.text = text
	s.next = vm.objects
	vm.objects = s
	vm.strings[s.text] = s
	return s
}

intern_clone :: proc(vm: ^Vm, text: string) -> ^Obj_String {
	if s, ok := vm.strings[text]; ok {
		return s
	}

	return intern_take(vm, strings.clone(text))
}
