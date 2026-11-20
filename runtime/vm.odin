package zettel_runtime

import "../common"
import "core:io"
import "core:strings"

Vm :: struct {
	out:     io.Writer,
	stack:   [dynamic]Value,
	objects: ^Obj,
	strings: map[string]^Obj_String,
	// path --> root class. Keys are owned.
	modules: map[string]^Obj_Class,
}

vm_destroy :: proc(vm: ^Vm) {
	delete(vm.stack)
	delete(vm.strings)
	for path in vm.modules do delete(path)
	delete(vm.modules)

	current := vm.objects
	for current != nil {
		next := current.next
		obj_free(current)
		current = next
	}
}

Runtime_Error :: struct {
	message: string,
	span:    common.Span,
}

run :: proc(vm: ^Vm, program: Program) -> (error: Runtime_Error, ok: bool) {
	chunk := program.main
	statics := program.class.statics[:]
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
		case .Nil:
			vm_push(vm, NIL)
		case .True:
			vm_push(vm, TRUE)
		case .False:
			vm_push(vm, FALSE)
		case .Negate:
			operand, is_number := as_number(vm_pop(vm))
			if !is_number {
				return runtime_error(vm, chunk, start, "operand must be a number")
			}
			vm_push(vm, to_value(-operand))
		case .Not:
			operand := vm_pop(vm)
			vm_push(vm, to_value(is_falsy(operand)))
		case .Add:
			rhs, lhs := vm_pop(vm), vm_pop(vm)
			if a, b, ok := as_numbers(lhs, rhs); ok {
				vm_push(vm, to_value(a + b))
			} else if a, b, ok := as_strings(lhs, rhs); ok {
				result := strings.concatenate({a.text, b.text})
				vm_push(vm, to_value(intern_take(vm, result)))
			} else {
				return runtime_error(
					vm,
					chunk,
					start,
					"operands must be two numbers or two strings",
				)
			}
		case .Sub:
			lhs, rhs, ok := pop_numbers(vm)
			if !ok {
				return runtime_error(vm, chunk, start, "operands must be numbers")
			}
			vm_push(vm, to_value(lhs - rhs))
		case .Mul:
			lhs, rhs, ok := pop_numbers(vm)
			if !ok {
				return runtime_error(vm, chunk, start, "operands must be numbers")
			}
			vm_push(vm, to_value(lhs * rhs))
		case .Div:
			lhs, rhs, ok := pop_numbers(vm)
			if !ok {
				return runtime_error(vm, chunk, start, "operands must be numbers")
			}
			vm_push(vm, to_value(lhs / rhs))
		case .Equal:
			rhs, lhs := vm_pop(vm), vm_pop(vm)
			vm_push(vm, to_value(values_equal(lhs, rhs)))
		case .Not_Equal:
			rhs, lhs := vm_pop(vm), vm_pop(vm)
			vm_push(vm, to_value(!values_equal(lhs, rhs)))
		case .Less:
			lhs, rhs, ok := pop_numbers(vm)
			if !ok {
				return runtime_error(vm, chunk, start, "operands must be numbers")
			}
			vm_push(vm, to_value(lhs < rhs))
		case .Less_Equal:
			lhs, rhs, ok := pop_numbers(vm)
			if !ok {
				return runtime_error(vm, chunk, start, "operands must be numbers")
			}
			vm_push(vm, to_value(lhs <= rhs))
		case .Greater:
			lhs, rhs, ok := pop_numbers(vm)
			if !ok {
				return runtime_error(vm, chunk, start, "operands must be numbers")
			}
			vm_push(vm, to_value(lhs > rhs))
		case .Greater_Equal:
			lhs, rhs, ok := pop_numbers(vm)
			if !ok {
				return runtime_error(vm, chunk, start, "operands must be numbers")
			}
			vm_push(vm, to_value(lhs >= rhs))
		case .Jump:
			ip += 2 + int(common.read_u16(chunk.code, ip))
		case .Jump_If_False:
			jump := int(common.read_u16(chunk.code, ip))
			ip += 2
			if is_falsy(vm_peek(vm)) do ip += jump
		case .Jump_If_True:
			jump := int(common.read_u16(chunk.code, ip))
			ip += 2
			if !is_falsy(vm_peek(vm)) do ip += jump
		case .Get_Static:
			value := statics[common.read_u16(chunk.code, ip)]
			ip += 2
			if value == UNDEFINED {
				return runtime_error(vm, chunk, start, "variable used before it was defined")
			}
			vm_push(vm, value)
		case .Set_Static:
			statics[common.read_u16(chunk.code, ip)] = vm_pop(vm)
			ip += 2
		case .Get_Local:
			vm_push(vm, vm.stack[common.read_u16(chunk.code, ip)])
			ip += 2
		case .Set_Local:
			vm.stack[common.read_u16(chunk.code, ip)] = vm_pop(vm)
			ip += 2
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
	return as_numbers(lhs_value, rhs_value)
}

as_numbers :: proc(lhs_value, rhs_value: Value) -> (lhs, rhs: f64, ok: bool) {
	lhs = as_number(lhs_value) or_return
	rhs = as_number(rhs_value) or_return
	return lhs, rhs, true
}

as_strings :: proc(lhs_value, rhs_value: Value) -> (lhs, rhs: ^Obj_String, ok: bool) {
	a := as_obj(lhs_value) or_return
	b := as_obj(rhs_value) or_return
	if a.tag != .String || b.tag != .String {
		return nil, nil, false
	}
	return (^Obj_String)(a), (^Obj_String)(b), true
}

vm_push :: proc(vm: ^Vm, value: Value) {
	append(&vm.stack, value)
}

vm_pop :: proc(vm: ^Vm) -> Value {
	return pop(&vm.stack)
}

vm_peek :: proc(vm: ^Vm) -> Value {
	return vm.stack[len(vm.stack) - 1]
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
