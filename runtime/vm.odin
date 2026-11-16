package zettel_runtime

import "../bytecode"
import "core:io"

Vm :: struct {
	out:   io.Writer,
	stack: [dynamic]Value,
}

vm_destroy :: proc(vm: ^Vm) {
	delete(vm.stack)
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
			rhs, lhs := vm_pop(vm).(f64), vm_pop(vm).(f64)
			vm_push(vm, lhs + rhs)
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
