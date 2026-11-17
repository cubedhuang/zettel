package zettel_runtime

import "../common"
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

Runtime_Error :: struct {
	message: string,
	span:    common.Span,
}

run :: proc(vm: ^Vm, program: Program) -> (error: Runtime_Error, ok: bool) {
	chunk := program.main
	ip := 0

	for {
		start := ip
		op := common.Op(chunk.code[ip])
		ip += 1

		switch op {
		case .Constant:
			index := common.read_u16(chunk.code, ip)
			ip += 2
			vm_push(vm, chunk.constants[index])
		case .Negate:
			operand, is_number := as_number(vm_pop(vm))
			if !is_number {
				return runtime_error(vm, chunk, start, "operand must be a number")
			}
			vm_push(vm, -operand)
		case .Add:
			rhs, lhs := vm_pop(vm), vm_pop(vm)
			switch lhs in lhs {
			case ^Obj:
				rhs, is_obj := as_obj(rhs)
				if !is_obj {
					return runtime_error(
						vm,
						chunk,
						start,
						"operands must be two numbers or two strings",
					)
				}
				a, b := (^Obj_String)(lhs), (^Obj_String)(rhs)
				result := strings.concatenate({a.text, b.text})
				vm_push(vm, intern_take(vm, result))
			case f64:
				rhs, is_number := as_number(rhs)
				if !is_number {
					return runtime_error(
						vm,
						chunk,
						start,
						"operands must be two numbers or two strings",
					)
				}
				vm_push(vm, lhs + rhs)
			}
		case .Sub:
			lhs, rhs, ok := pop_numbers(vm)
			if !ok {
				return runtime_error(vm, chunk, start, "operands must be numbers")
			}
			vm_push(vm, lhs - rhs)
		case .Mul:
			lhs, rhs, ok := pop_numbers(vm)
			if !ok {
				return runtime_error(vm, chunk, start, "operands must be numbers")
			}
			vm_push(vm, lhs * rhs)
		case .Div:
			lhs, rhs, ok := pop_numbers(vm)
			if !ok {
				return runtime_error(vm, chunk, start, "operands must be numbers")
			}
			vm_push(vm, lhs / rhs)
		case .Pop:
			vm_pop(vm)
		case .Print:
			write_value(vm.out, vm_pop(vm))
			io.write_byte(vm.out, '\n')
		case .Return:
			return {}, true
		}
	}
}

runtime_error :: proc(vm: ^Vm, chunk: Chunk, ip: int, message: string) -> (Runtime_Error, bool) {
	clear(&vm.stack)
	return {message = message, span = chunk.spans[ip]}, false
}

pop_numbers :: proc(vm: ^Vm) -> (lhs, rhs: f64, ok: bool) {
	rhs_value, lhs_value := vm_pop(vm), vm_pop(vm)
	lhs = as_number(lhs_value) or_return
	rhs = as_number(rhs_value) or_return
	return lhs, rhs, true
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
