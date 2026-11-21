package zettel_runtime

import "../common"
import "core:fmt"
import "core:io"
import "core:strings"

MAX_FRAMES :: 1024

Vm :: struct {
	sources:       [dynamic]common.Source,
	out:           io.Writer,
	stack:         [dynamic]Value,
	frames:        [dynamic]Frame,
	objects:       ^Obj,
	strings:       map[string]^Obj_String,
	// path --> root class. Keys are owned.
	modules:       map[string]^Obj_Class,
	builtins:      [common.Builtin]Value,
	open_upvalues: ^Obj_Upvalue,
}

Frame :: struct {
	closure: ^Obj_Closure,
	// Only up to date at calls.
	ip:      int,
	// Stack index of the frame's first local. The callee is right below it.
	base:    int,
}

vm_init :: proc(vm: ^Vm, out: io.Writer) {
	vm.out = out
	for native, builtin in builtin_natives {
		obj := new(Obj_Native)
		obj.tag = .Native
		obj.name = intern_clone(vm, common.builtin_names[builtin])
		obj.arity = native.arity
		obj.procedure = native.procedure
		track(vm, obj)
		vm.builtins[builtin] = to_value(obj)
	}
}

vm_destroy :: proc(vm: ^Vm) {
	delete(vm.stack)
	delete(vm.frames)
	delete(vm.strings)
	for path in vm.modules do delete(path)
	delete(vm.modules)
	for &source in vm.sources do common.source_clone_destroy(&source)
	delete(vm.sources)

	current := vm.objects
	for current != nil {
		next := current.next
		obj_free(current)
		current = next
	}
}

Runtime_Error :: struct {
	// May use `context.temp_allocator`.
	message: string,
	span:    common.Span,
	// Index into `Vm.sources`.
	source:  int,
}

// Runs a class body from `load`.
run :: proc(vm: ^Vm, main: ^Obj_Closure) -> (error: Runtime_Error, ok: bool) {
	append(&vm.frames, Frame{closure = main, base = len(vm.stack)})
	chunk := main.function.chunk
	statics := main.function.class.statics[:]
	upvalues := main.upvalues
	base := len(vm.stack)
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
		case .Loop:
			jump := int(common.read_u16(chunk.code, ip))
			ip += 2 - jump
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
		case .Get_Builtin:
			vm_push(vm, vm.builtins[common.Builtin(chunk.code[ip])])
			ip += 1
		case .Get_Upvalue:
			upvalue := upvalues[chunk.code[ip]]
			ip += 1
			vm_push(vm, upvalue.closed if upvalue.slot == CLOSED else vm.stack[upvalue.slot])
		case .Set_Upvalue:
			upvalue := upvalues[chunk.code[ip]]
			ip += 1
			if upvalue.slot == CLOSED {
				upvalue.closed = vm_pop(vm)
			} else {
				vm.stack[upvalue.slot] = vm_pop(vm)
			}
		case .Get_Local:
			vm_push(vm, vm.stack[base + int(common.read_u16(chunk.code, ip))])
			ip += 2
		case .Set_Local:
			vm.stack[base + int(common.read_u16(chunk.code, ip))] = vm_pop(vm)
			ip += 2
		case .Call:
			arg_count := int(chunk.code[ip])
			ip += 1
			callee, is_obj := as_obj(vm.stack[len(vm.stack) - arg_count - 1])
			if !is_obj || (callee.tag != .Closure && callee.tag != .Native) {
				return runtime_error(vm, chunk, start, "can only call functions")
			}
			if callee.tag == .Native {
				native := (^Obj_Native)(callee)
				if native.arity != VARIADIC && arg_count != native.arity {
					return runtime_error(vm, chunk, start, arity_message(native.arity, arg_count))
				}
				args_start := len(vm.stack) - arg_count
				result, error := native.procedure(vm, vm.stack[args_start:])
				if error != "" do return runtime_error(vm, chunk, start, error)
				resize(&vm.stack, args_start - 1)
				vm_push(vm, result)
				break
			}

			closure := (^Obj_Closure)(callee)
			function := closure.function
			if arg_count != function.arity {
				return runtime_error(vm, chunk, start, arity_message(function.arity, arg_count))
			}
			if len(vm.frames) >= MAX_FRAMES {
				return runtime_error(vm, chunk, start, "stack overflow")
			}

			vm.frames[len(vm.frames) - 1].ip = ip
			base = len(vm.stack) - arg_count
			append(&vm.frames, Frame{closure = closure, base = base})
			chunk = function.chunk
			statics = function.class.statics[:]
			upvalues = closure.upvalues
			ip = 0
		case .Closure:
			function := (^Obj_Function)(to_obj(chunk.constants[common.read_u16(chunk.code, ip)]))
			ip += 2
			closure := new_closure(vm, function)
			for &upvalue in closure.upvalues {
				capture := common.read_capture(chunk.code, ip)
				ip += common.CAPTURE_SIZE
				if capture.is_local {
					upvalue = capture_upvalue(vm, base + int(capture.index))
				} else {
					upvalue = upvalues[capture.index]
				}
			}
			vm_push(vm, to_value(closure))
		case .Close_Upvalue:
			close_upvalues(vm, len(vm.stack) - 1)
			vm_pop(vm)
		case .Return:
			result := vm_pop(vm)
			finished := pop(&vm.frames)
			close_upvalues(vm, finished.base)
			if len(vm.frames) == 0 {
				resize(&vm.stack, finished.base)
				return {}, true
			}
			resize(&vm.stack, finished.base - 1)
			vm_push(vm, result)

			frame := vm.frames[len(vm.frames) - 1]
			chunk = frame.closure.function.chunk
			statics = frame.closure.function.class.statics[:]
			upvalues = frame.closure.upvalues
			base = frame.base
			ip = frame.ip
		case .Pop:
			vm_pop(vm)
		case .Echo:
			write_value(vm.out, vm_peek(vm))
			io.write_byte(vm.out, '\n')
		case .Echo_Result:
			value := vm_peek(vm)
			if value == NIL do break
			write_value(vm.out, value)
			io.write_byte(vm.out, '\n')
		}
	}
}

// Uses `context.temp_allocator`.
arity_message :: proc(expected, got: int) -> string {
	return fmt.tprintf(
		"expected %v argument%v, got %v",
		expected,
		"" if expected == 1 else "s",
		got,
	)
}

// Returns the open upvalue for the stack slot or creates if needed.
capture_upvalue :: proc(vm: ^Vm, slot: int) -> ^Obj_Upvalue {
	previous: ^Obj_Upvalue
	current := vm.open_upvalues
	for current != nil && current.slot > slot {
		previous = current
		current = current.next_open
	}
	if current != nil && current.slot == slot do return current

	upvalue := new(Obj_Upvalue)
	upvalue.tag = .Upvalue
	upvalue.slot = slot
	upvalue.next_open = current
	track(vm, upvalue)
	if previous == nil {
		vm.open_upvalues = upvalue
	} else {
		previous.next_open = upvalue
	}
	return upvalue
}

// Closes the open upvalues for stack slots from `first` up.
close_upvalues :: proc(vm: ^Vm, first: int) {
	for vm.open_upvalues != nil && vm.open_upvalues.slot >= first {
		upvalue := vm.open_upvalues
		upvalue.closed = vm.stack[upvalue.slot]
		upvalue.slot = CLOSED
		vm.open_upvalues = upvalue.next_open
		upvalue.next_open = nil
	}
}

runtime_error :: proc(vm: ^Vm, chunk: Chunk, ip: int, message: string) -> (Runtime_Error, bool) {
	// closures might still survive like in the REPL
	close_upvalues(vm, 0)
	clear(&vm.stack)
	clear(&vm.frames)
	return {message = message, span = chunk.spans[ip], source = chunk.source}, false
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
	track(vm, s)
	vm.strings[s.text] = s
	return s
}

// Adds `obj` to the objects the `Vm` frees.
track :: proc(vm: ^Vm, obj: ^Obj) {
	obj.next = vm.objects
	vm.objects = obj
}

intern_clone :: proc(vm: ^Vm, text: string) -> ^Obj_String {
	if s, ok := vm.strings[text]; ok {
		return s
	}

	return intern_take(vm, strings.clone(text))
}
