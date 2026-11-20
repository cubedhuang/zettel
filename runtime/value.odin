package zettel_runtime

import "core:io"
import "core:math"
import "core:strconv"

Value :: distinct u64

SIGN_BIT :: u64(0x8000_0000_0000_0000)
QNAN :: u64(0x7ffc_0000_0000_0000)

TAG_NIL :: u64(1)
// `TAG_TRUE == TAG_FALSE | 1`
TAG_FALSE :: u64(2)
TAG_TRUE :: u64(3)
TAG_UNDEFINED :: u64(4)

NIL :: Value(QNAN | TAG_NIL)
FALSE :: Value(QNAN | TAG_FALSE)
TRUE :: Value(QNAN | TAG_TRUE)
// Static variables whose declaration hasn't run yet.
UNDEFINED :: Value(QNAN | TAG_UNDEFINED)

write_value :: proc(w: io.Writer, value: Value) {
	switch {
	case is_number(value):
		write_number(w, to_number(value))
	case is_obj(value):
		write_obj(w, to_obj(value))
	case value == NIL:
		io.write_string(w, "nil")
	case value == TRUE:
		io.write_string(w, "true")
	case value == FALSE:
		io.write_string(w, "false")
	case:
		unreachable()
	}
}

write_number :: proc(w: io.Writer, number: f64) {
	switch {
	case math.is_nan(number):
		io.write_string(w, "nan")
		return
	case math.is_inf(number, 1):
		io.write_string(w, "inf")
		return
	case math.is_inf(number, -1):
		io.write_string(w, "-inf")
		return
	}

	magnitude := abs(number)
	format: u8 = 'f' if magnitude == 0 || (magnitude >= 1e-7 && magnitude < 1e21) else 'e'

	buffer: [64]u8
	text := strconv.write_float(buffer[:], number, format, -1, 64, nil)
	io.write_string(w, text)
}

write_obj :: proc(w: io.Writer, obj: ^Obj) {
	switch obj.tag {
	case .String:
		s := (^Obj_String)(obj)
		io.write_byte(w, '"')
		io.write_string(w, s.text)
		io.write_byte(w, '"')
	case .Class:
		io.write_string(w, "<class ")
		io.write_string(w, (^Obj_Class)(obj).name.text)
		io.write_byte(w, '>')
	}
}

Obj :: struct {
	tag:  Obj_Tag,
	next: ^Obj,
}

Obj_Tag :: enum u8 {
	String,
	Class,
}

Obj_String :: struct {
	using obj: Obj,
	text:      string,
}

Obj_Class :: struct {
	using obj: Obj,
	// For a file's root class, the file's stem.
	name:      ^Obj_String,
	statics:   [dynamic]Value,
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
		free(class)
	}
}

to_value :: proc {
	number_to_value,
	obj_to_value,
	bool_to_value,
}

// Prefer `to_value`.
number_to_value :: #force_inline proc "contextless" (number: f64) -> Value {
	return transmute(Value)number
}

// Prefer `to_value`.
obj_to_value :: #force_inline proc "contextless" (obj: ^Obj) -> Value {
	return Value(SIGN_BIT | QNAN | u64(uintptr(obj)))
}

// Prefer `to_value`.
bool_to_value :: #force_inline proc "contextless" (b: bool) -> Value {
	return TRUE if b else FALSE
}

is_number :: #force_inline proc "contextless" (v: Value) -> bool {
	return u64(v) & QNAN != QNAN
}

is_obj :: #force_inline proc "contextless" (v: Value) -> bool {
	return u64(v) & (SIGN_BIT | QNAN) == SIGN_BIT | QNAN
}

is_bool :: #force_inline proc "contextless" (v: Value) -> bool {
	return v | 1 == TRUE
}

as_number :: #force_inline proc "contextless" (v: Value) -> (number: f64, ok: bool) {
	if !is_number(v) {
		return 0, false
	}
	return to_number(v), true
}

as_obj :: #force_inline proc "contextless" (v: Value) -> (obj: ^Obj, ok: bool) {
	if !is_obj(v) {
		return nil, false
	}
	return to_obj(v), true
}

as_bool :: #force_inline proc "contextless" (v: Value) -> (b: bool, ok: bool) {
	if !is_bool(v) {
		return false, false
	}
	return to_bool(v), true
}

to_number :: #force_inline proc "contextless" (v: Value) -> f64 {
	when ODIN_DEBUG {
		assert_contextless(is_number(v), "to_number on a non-number value")
	}
	return transmute(f64)v
}

to_obj :: #force_inline proc "contextless" (v: Value) -> ^Obj {
	when ODIN_DEBUG {
		assert_contextless(is_obj(v), "to_obj on a non-object value")
	}
	return transmute(^Obj)uintptr(u64(v) & ~(SIGN_BIT | QNAN))
}

to_bool :: #force_inline proc "contextless" (v: Value) -> bool {
	when ODIN_DEBUG {
		assert_contextless(is_bool(v), "to_bool on a non-bool value")
	}
	return v == TRUE
}

// For numbers, `nan != nan` and `0 == -0`.
// Strings are interned! (/^▽^)/
values_equal :: #force_inline proc "contextless" (a, b: Value) -> bool {
	if is_number(a) && is_number(b) {
		return to_number(a) == to_number(b)
	}
	return a == b
}

is_falsy :: proc(value: Value) -> bool {
	return value == NIL || value == FALSE
}
