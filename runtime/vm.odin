package zettel_runtime

import "../common"
import "core:fmt"
import "core:io"
import "core:math"
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

Runtime_Error :: struct {
	// May use `context.temp_allocator`.
	message: string,
	span:    common.Span,
	// Index into `Vm.sources`.
	source:  int,
}

vm_init :: proc(vm: ^Vm, out: io.Writer) {
	vm.out = out
	for native, builtin in builtin_natives {
		name := intern_clone(vm, common.builtin_names[builtin])
		vm.builtins[builtin] = to_value(new_native(vm, name, native))
	}
}

vm_destroy :: proc(vm: ^Vm) {
	delete(vm.stack)
	delete(vm.frames)
	delete(vm.strings)
	for path in vm.modules do delete(path)
	delete(vm.modules)
	for &source in vm.sources do common.source_destroy(&source)
	delete(vm.sources)

	current := vm.objects
	for current != nil {
		next := current.next
		obj_free(current)
		current = next
	}
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
		case .Array:
			count := int(common.read_u16(chunk.code, ip))
			ip += 2
			vm_push(vm, to_value(pop_array(vm, count)))
		case .Array_Push:
			item := vm_pop(vm)
			array := (^Obj_Array)(to_obj(vm_peek(vm)))
			append(&array.items, item)
		case .Array_Extend:
			spread, is_array := as_array(vm_pop(vm))
			if !is_array do return runtime_error(vm, chunk, start, "can only spread arrays")
			array := (^Obj_Array)(to_obj(vm_peek(vm)))
			append(&array.items, ..spread.items[:])
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
		case .Get_Index:
			index_value, indexed := vm_pop(vm), vm_pop(vm)
			array, index, message := array_index(indexed, index_value)
			if message != "" do return runtime_error(vm, chunk, start, message)
			vm_push(vm, array.items[index])
		case .Set_Index:
			index_value, indexed, item := vm_pop(vm), vm_pop(vm), vm_pop(vm)
			array, index, message := array_index(indexed, index_value)
			if message != "" do return runtime_error(vm, chunk, start, message)
			array.items[index] = item
		case .Get_Local:
			vm_push(vm, vm.stack[base + int(common.read_u16(chunk.code, ip))])
			ip += 2
		case .Set_Local:
			vm.stack[base + int(common.read_u16(chunk.code, ip))] = vm_pop(vm)
			ip += 2
		case .Call, .Call_Spread:
			arg_count: int
			if op == .Call {
				arg_count = int(chunk.code[ip])
				ip += 1
			} else {
				// the compiler made this array, so it can't be anything else
				args := (^Obj_Array)(to_obj(vm_pop(vm)))
				append(&vm.stack, ..args.items[:])
				arg_count = len(args.items)
			}

			vm.frames[len(vm.frames) - 1].ip = ip
			if message := call_value(vm, arg_count); message != "" {
				return runtime_error(vm, chunk, start, message)
			}
			// a function call pushed a frame, and a native call left the same one
			frame := vm.frames[len(vm.frames) - 1]
			chunk = frame.closure.function.chunk
			statics = frame.closure.function.class.statics[:]
			upvalues = frame.closure.upvalues
			base = frame.base
			ip = frame.ip
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

runtime_error :: proc(vm: ^Vm, chunk: Chunk, ip: int, message: string) -> (Runtime_Error, bool) {
	// closures might still survive like in the REPL
	close_upvalues(vm, 0)
	clear(&vm.stack)
	clear(&vm.frames)
	return {message = message, span = chunk.spans[ip], source = chunk.source}, false
}

// Calls the value below the top `arg_count` values. For a function, this pushes its frame.
// An error message may use `context.temp_allocator`.
call_value :: proc(vm: ^Vm, arg_count: int) -> (error: string) {
	callee_slot := len(vm.stack) - arg_count - 1
	callee, is_obj := as_obj(vm.stack[callee_slot])
	if !is_obj do return "can only call functions"

	#partial switch callee.tag {
	case .Native:
		native := (^Obj_Native)(callee)
		if !arity_matches(native.arity, native.variadic, arg_count) {
			return arity_message(native.arity, native.variadic, arg_count)
		}
		result, native_error := native.procedure(vm, vm.stack[callee_slot + 1:])
		if native_error != "" do return native_error
		resize(&vm.stack, callee_slot)
		vm_push(vm, result)
		return ""
	case .Closure:
		closure := (^Obj_Closure)(callee)
		function := closure.function
		if !arity_matches(function.arity, function.variadic, arg_count) {
			return arity_message(function.arity, function.variadic, arg_count)
		}
		if len(vm.frames) >= MAX_FRAMES do return "stack overflow"
		if function.variadic {
			vm_push(vm, to_value(pop_array(vm, arg_count - function.arity)))
		}
		append(&vm.frames, Frame{closure = closure, base = callee_slot + 1})
		return ""
	}
	return "can only call functions"
}

arity_matches :: proc(arity: int, variadic: bool, arg_count: int) -> bool {
	return arg_count >= arity if variadic else arg_count == arity
}

// Uses `context.temp_allocator`.
arity_message :: proc(arity: int, variadic: bool, got: int) -> string {
	return fmt.tprintf(
		"expected %v%v argument%v, got %v",
		"at least " if variadic else "",
		arity,
		"" if arity == 1 else "s",
		got,
	)
}

// Pops the top `count` values into a new array, in order.
pop_array :: proc(vm: ^Vm, count: int) -> ^Obj_Array {
	items := make([dynamic]Value, count)
	copy(items[:], vm.stack[len(vm.stack) - count:])
	resize(&vm.stack, len(vm.stack) - count)
	return new_array(vm, items)
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

	upvalue := new_upvalue(vm, slot)
	upvalue.next_open = current
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

// Checks that `indexed` is an array and `index_value` is one of its indices. A non-empty
// `message` is the error and uses `context.temp_allocator`.
array_index :: proc(
	indexed, index_value: Value,
) -> (
	array: ^Obj_Array,
	index: int,
	message: string,
) {
	array = as_array(indexed) or_else nil
	if array == nil do return nil, 0, "can only index arrays"
	number, is_number := as_number(index_value)
	if !is_number || number != math.trunc(number) do return nil, 0, "index must be an integer"
	// compare as floats because huge numbers and infinities don't convert to `int`
	if number < 0 || number >= f64(len(array.items)) {
		return nil, 0, fmt.tprintf(
			"index %v is out of bounds for length %v",
			number,
			len(array.items),
		)
	}
	return array, int(number), ""
}

as_array :: proc(value: Value) -> (array: ^Obj_Array, ok: bool) {
	obj := as_obj(value) or_return
	if obj.tag != .Array do return nil, false
	return (^Obj_Array)(obj), true
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
