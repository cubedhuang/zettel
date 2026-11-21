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
	// Maps a path to its root class. The map owns the keys.
	modules:       map[string]^Obj_Class,
	builtins:      [common.Builtin]Value,
	open_upvalues: ^Obj_Upvalue,
	// How many values the last call that expected `common.ALL_RESULTS` returned.
	result_count:  int,
}

Frame :: struct {
	closure:  ^Obj_Closure,
	// Correct only during a call.
	ip:       int,
	// Stack index of the frame's first local. The callee is right below it.
	base:     int,
	// How many values the caller expects, or `common.ALL_RESULTS`.
	results:  int,
	// The instance that a constructor is making, which it returns. nil for other functions.
	instance: ^Obj_Instance,
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
	append(&vm.frames, Frame{closure = main, base = len(vm.stack), results = common.ALL_RESULTS})
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
		case .Bit_Not:
			operand, ok := as_u32(vm_pop(vm))
			if !ok do return runtime_error(vm, chunk, start, BITWISE_ERROR)
			vm_push(vm, to_value(f64(~operand)))
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
		case .Mod:
			lhs, rhs, ok := pop_numbers(vm)
			if !ok {
				return runtime_error(vm, chunk, start, "operands must be numbers")
			}
			// `math.mod` truncates, like C's `fmod`
			vm_push(vm, to_value(math.mod(lhs, rhs)))
		case .Mod_Floored:
			lhs, rhs, ok := pop_numbers(vm)
			if !ok {
				return runtime_error(vm, chunk, start, "operands must be numbers")
			}
			vm_push(vm, to_value(floored_mod(lhs, rhs)))
		case .Pow:
			lhs, rhs, ok := pop_numbers(vm)
			if !ok {
				return runtime_error(vm, chunk, start, "operands must be numbers")
			}
			vm_push(vm, to_value(math.pow(lhs, rhs)))
		case .Bit_And, .Bit_Or, .Bit_Xor:
			rhs_value, lhs_value := vm_pop(vm), vm_pop(vm)
			lhs, lhs_ok := as_u32(lhs_value)
			rhs, rhs_ok := as_u32(rhs_value)
			if !lhs_ok || !rhs_ok do return runtime_error(vm, chunk, start, BITWISE_ERROR)
			result: u32
			#partial switch op {
			case .Bit_And:
				result = lhs & rhs
			case .Bit_Or:
				result = lhs | rhs
			case .Bit_Xor:
				result = lhs ~ rhs
			}
			vm_push(vm, to_value(f64(result)))
		case .Shift_Left, .Shift_Right:
			rhs_value, lhs_value := vm_pop(vm), vm_pop(vm)
			lhs, lhs_ok := as_u32(lhs_value)
			if !lhs_ok do return runtime_error(vm, chunk, start, BITWISE_ERROR)
			amount, is_number := as_number(rhs_value)
			if !is_number || amount != math.trunc(amount) {
				return runtime_error(vm, chunk, start, "shift amount must be an integer")
			}
			// a negative amount shifts the other way
			if op == .Shift_Right do amount = -amount
			result: u32
			switch {
			case amount <= -32 || amount >= 32:
				result = 0
			case amount >= 0:
				result = lhs << uint(amount)
			case:
				result = lhs >> uint(-amount)
			}
			vm_push(vm, to_value(f64(result)))
		case .Equal:
			rhs, lhs := vm_pop(vm), vm_pop(vm)
			vm_push(vm, to_value(values_equal(lhs, rhs)))
		case .Not_Equal:
			rhs, lhs := vm_pop(vm), vm_pop(vm)
			vm_push(vm, to_value(!values_equal(lhs, rhs)))
		case .Less, .Less_Equal, .Greater, .Greater_Equal:
			rhs, lhs := vm_pop(vm), vm_pop(vm)
			order: int
			if a, b, ok := as_numbers(lhs, rhs); ok {
				// nan isn't ordered, so every comparison with it is false
				if a != a || b != b {
					vm_push(vm, FALSE)
					break
				}
				order = -1 if a < b else int(a > b)
			} else if a, b, ok := as_strings(lhs, rhs); ok {
				// byte by byte, like `strings.compare`
				order = strings.compare(a.text, b.text)
			} else {
				return runtime_error(
					vm,
					chunk,
					start,
					"operands must be two numbers or two strings",
				)
			}
			#partial switch op {
			case .Less:
				vm_push(vm, to_value(order < 0))
			case .Less_Equal:
				vm_push(vm, to_value(order <= 0))
			case .Greater:
				vm_push(vm, to_value(order > 0))
			case .Greater_Equal:
				vm_push(vm, to_value(order >= 0))
			}
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
			if value == UNDEFINED do return runtime_error(vm, chunk, start, UNDEFINED_ERROR)
			vm_push(vm, value)
		case .Set_Static:
			statics[common.read_u16(chunk.code, ip)] = vm_pop(vm)
			ip += 2
		case .Get_Outer_Static, .Set_Outer_Static:
			class := vm.frames[len(vm.frames) - 1].closure.function.class
			for _ in 0 ..< chunk.code[ip] do class = class.outer
			slot := common.read_u16(chunk.code, ip + 1)
			ip += 3
			if op == .Set_Outer_Static {
				class.statics[slot] = vm_pop(vm)
				break
			}
			value := class.statics[slot]
			if value == UNDEFINED do return runtime_error(vm, chunk, start, UNDEFINED_ERROR)
			vm_push(vm, value)
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
		case .Get_Index_Keep:
			index_value, indexed := vm.stack[len(vm.stack) - 1], vm.stack[len(vm.stack) - 2]
			array, index, message := array_index(indexed, index_value)
			if message != "" do return runtime_error(vm, chunk, start, message)
			vm_push(vm, array.items[index])
		case .Update_Index:
			item, index_value, indexed := vm_pop(vm), vm_pop(vm), vm_pop(vm)
			// check again, because the new element's expression may have shrunk the array
			array, index, message := array_index(indexed, index_value)
			if message != "" do return runtime_error(vm, chunk, start, message)
			array.items[index] = item
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
		case .Get_Property, .Get_Property_Keep:
			name := (^Obj_String)(to_obj(chunk.constants[common.read_u16(chunk.code, ip)]))
			ip += 2
			object := vm_peek(vm) if op == .Get_Property_Keep else vm_pop(vm)
			value, message := get_property(object, name)
			if message != "" do return runtime_error(vm, chunk, start, message)
			vm_push(vm, value)
		case .Set_Property, .Update_Property:
			name := (^Obj_String)(to_obj(chunk.constants[common.read_u16(chunk.code, ip)]))
			ip += 2
			object, value: Value
			if op == .Set_Property {
				object, value = vm_pop(vm), vm_pop(vm)
			} else {
				value, object = vm_pop(vm), vm_pop(vm)
			}
			if message := set_property(object, name, value); message != "" {
				return runtime_error(vm, chunk, start, message)
			}
		case .Get_Local:
			vm_push(vm, vm.stack[base + int(common.read_u16(chunk.code, ip))])
			ip += 2
		case .Set_Local:
			vm.stack[base + int(common.read_u16(chunk.code, ip))] = vm_pop(vm)
			ip += 2
		case .Call, .Call_Spread, .Invoke, .Invoke_Spread:
			name: ^Obj_String
			if op == .Invoke || op == .Invoke_Spread {
				name = (^Obj_String)(to_obj(chunk.constants[common.read_u16(chunk.code, ip)]))
				ip += 2
			}
			arg_count: int
			if op == .Call || op == .Invoke {
				arg_count = int(chunk.code[ip])
				ip += 1
				if arg_count == common.ALL_RESULTS do arg_count = vm.result_count
			} else {
				// the compiler made this array, so it can't be anything else
				args := (^Obj_Array)(to_obj(vm_pop(vm)))
				append(&vm.stack, ..args.items[:])
				arg_count = len(args.items)
			}
			results := int(chunk.code[ip])
			ip += 1
			if name != nil {
				message: string
				arg_count, message = prepare_invoke(vm, name, arg_count)
				if message != "" do return runtime_error(vm, chunk, start, message)
			}

			vm.frames[len(vm.frames) - 1].ip = ip
			if message := call_value(vm, arg_count, results); message != "" {
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
			count := int(chunk.code[ip])
			if count == common.ALL_RESULTS do count = vm.result_count
			finished := pop(&vm.frames)
			close_upvalues(vm, finished.base)
			if finished.instance != nil {
				// the compiler made sure the constructor returned only nil
				finished.instance.sealed = true
				vm.stack[len(vm.stack) - 1] = to_value(finished.instance)
			}
			if len(vm.frames) == 0 {
				resize(&vm.stack, finished.base)
				return {}, true
			}

			frame := vm.frames[len(vm.frames) - 1]
			if message := check_results(vm, finished.results, count); message != "" {
				// the call instruction's last byte is right before the caller's ip
				return runtime_error(vm, frame.closure.function.chunk, frame.ip - 1, message)
			}
			// move the values down over the callee
			callee_slot := finished.base - 1
			copy(vm.stack[callee_slot:], vm.stack[len(vm.stack) - count:])
			resize(&vm.stack, callee_slot + count)

			chunk = frame.closure.function.chunk
			statics = frame.closure.function.class.statics[:]
			upvalues = frame.closure.upvalues
			base = frame.base
			ip = frame.ip
		case .Pop:
			vm_pop(vm)
		case .Pop_Results:
			resize(&vm.stack, len(vm.stack) - vm.result_count)
		case .Echo_Results:
			values := vm.stack[len(vm.stack) - vm.result_count:]
			if len(values) == 1 && values[0] == NIL do break
			for value, i in values {
				if i > 0 do io.write_string(vm.out, ", ")
				write_value(vm.out, value)
			}
			io.write_byte(vm.out, '\n')
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
	// closures can stay alive after the error, for example in the REPL
	close_upvalues(vm, 0)
	clear(&vm.stack)
	clear(&vm.frames)
	return {message = message, span = chunk.spans[ip], source = chunk.source}, false
}

// Calls the value below the top `arg_count` values, which must return `results` values (or
// `common.ALL_RESULTS`). For a function, this pushes its frame.
// An error message may use `context.temp_allocator`.
call_value :: proc(vm: ^Vm, arg_count: int, results: int) -> (error: string) {
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
		if message := check_results(vm, results, 1); message != "" do return message
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
		instance: ^Obj_Instance
		if function.kind == .Constructor {
			// the new instance is the first parameter
			instance = new_instance(vm, function.class)
			inject_at(&vm.stack, callee_slot + 1, to_value(instance))
		}
		if function.variadic {
			vm_push(vm, to_value(pop_array(vm, arg_count - function.arity)))
		}
		append(
			&vm.frames,
			Frame {
				closure = closure,
				base = callee_slot + 1,
				results = results,
				instance = instance,
			},
		)
		return ""
	}
	return "can only call functions"
}

// For `Invoke`, replaces the receiver below the top `arg_count` values with the function to call.
// A method also gets the receiver as its first argument, which `new_count` includes.
prepare_invoke :: proc(
	vm: ^Vm,
	name: ^Obj_String,
	arg_count: int,
) -> (
	new_count: int,
	error: string,
) {
	receiver_slot := len(vm.stack) - arg_count - 1
	if obj, is_obj := as_obj(vm.stack[receiver_slot]); is_obj {
		#partial switch obj.tag {
		case .Instance:
			instance := (^Obj_Instance)(obj)
			if index := find_field(instance, name); index >= 0 {
				vm.stack[receiver_slot] = instance.fields[index]
				return arg_count, ""
			}
			slot, found := instance.class.slots[name]
			if !found {
				return 0, fmt.tprintf(
					"%v has no field or method '%v'",
					instance.class.name.text,
					name.text,
				)
			}
			method := instance.class.statics[slot]
			if method == UNDEFINED do return 0, UNDEFINED_ERROR
			inject_at(&vm.stack, receiver_slot, method)
			return arg_count + 1, ""
		case .Class:
			value, message := get_static((^Obj_Class)(obj), name)
			if message != "" do return 0, message
			vm.stack[receiver_slot] = value
			return arg_count, ""
		}
	}
	return 0, "only instances and classes have methods"
}

// Checks a call's return value count against what the caller expects, and remembers it when the
// caller takes any number.
check_results :: proc(vm: ^Vm, expected, count: int) -> (error: string) {
	if expected == common.ALL_RESULTS {
		vm.result_count = count
		return ""
	}
	if count == expected do return ""
	return fmt.tprintf(
		"expected %v return value%v, got %v",
		expected,
		"" if expected == 1 else "s",
		count,
	)
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

// Returns the open upvalue for the stack slot. Creates it if it does not exist.
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

UNDEFINED_ERROR :: "variable used before it was defined"

// An instance's properties are its fields, and a class's properties are its statics. A non-empty
// `error` uses `context.temp_allocator`.
get_property :: proc(object: Value, name: ^Obj_String) -> (value: Value, error: string) {
	if obj, is_obj := as_obj(object); is_obj {
		#partial switch obj.tag {
		case .Instance:
			instance := (^Obj_Instance)(obj)
			if index := find_field(instance, name); index >= 0 {
				return instance.fields[index], ""
			}
			if name in instance.class.slots {
				return NIL, fmt.tprintf(
					"can't get method '%v' of %v without calling it",
					name.text,
					instance.class.name.text,
				)
			}
			return NIL, fmt.tprintf("%v has no field '%v'", instance.class.name.text, name.text)
		case .Class:
			return get_static((^Obj_Class)(obj), name)
		}
	}
	return NIL, "only instances and classes have properties"
}

// Adds a field to an instance that's still being constructed. A non-empty `error` uses
// `context.temp_allocator`.
set_property :: proc(object: Value, name: ^Obj_String, value: Value) -> (error: string) {
	if obj, is_obj := as_obj(object); is_obj {
		#partial switch obj.tag {
		case .Instance:
			instance := (^Obj_Instance)(obj)
			if index := find_field(instance, name); index >= 0 {
				instance.fields[index] = value
				return ""
			}
			// a method call looks at fields first, so the field would hide the static
			if name in instance.class.slots {
				return fmt.tprintf(
					"a field named '%v' would hide the static '%v' of %v",
					name.text,
					name.text,
					instance.class.name.text,
				)
			}
			if instance.sealed {
				return fmt.tprintf(
					"%v has no field '%v', and fields can only be added by its constructor",
					instance.class.name.text,
					name.text,
				)
			}
			add_field(instance, name, value)
			return ""
		case .Class:
			class := (^Obj_Class)(obj)
			slot, found := class.slots[name]
			if !found do return static_message(class, name)
			class.statics[slot] = value
			return ""
		}
	}
	return "only instances and classes have properties"
}

// A non-empty `error` uses `context.temp_allocator`.
get_static :: proc(class: ^Obj_Class, name: ^Obj_String) -> (value: Value, error: string) {
	slot, found := class.slots[name]
	if !found do return NIL, static_message(class, name)
	value = class.statics[slot]
	if value == UNDEFINED do return NIL, UNDEFINED_ERROR
	return value, ""
}

// Uses `context.temp_allocator`.
static_message :: proc(class: ^Obj_Class, name: ^Obj_String) -> string {
	return fmt.tprintf("class %v has no static '%v'", class.name.text, name.text)
}

BITWISE_ERROR :: "bitwise operands must be 32-bit integers"

// Converts an integer from -2^31 to 2^32 - 1 to 32 bits. Negative numbers wrap, like in two's
// complement, so `-1` is `0xFFFF_FFFF`.
as_u32 :: proc(value: Value) -> (result: u32, ok: bool) {
	number := as_number(value) or_return
	if number != math.trunc(number) || number < -(1 << 31) || number >= 1 << 32 do return 0, false
	return u32(i64(number)), true
}

// The remainder of flooring division, which has the sign of `rhs`, like Odin's `%%`.
floored_mod :: proc(lhs, rhs: f64) -> f64 {
	remainder := math.mod(lhs, rhs)
	if remainder != 0 && (remainder < 0) != (rhs < 0) do remainder += rhs
	return remainder
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
