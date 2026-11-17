package zettel_runtime

import "core:io"
import "core:math"
import "core:strconv"

// TODO: probably this is nan-boxable
Value :: union {
	f64,
	^Obj,
}

write_value :: proc(w: io.Writer, value: Value) {
	switch v in value {
	case nil:
		io.write_string(w, "nil")
	case f64:
		write_number(w, v)
	case ^Obj:
		write_obj(w, v)
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
	}
}

Obj :: struct {
	tag:  Obj_Tag,
	next: ^Obj,
}

Obj_Tag :: enum u8 {
	String,
}

Obj_String :: struct {
	using obj: Obj,
	text:      string,
}

as_number :: #force_inline proc "contextless" (v: Value) -> (number: f64, ok: bool) {
	return v.(f64)
}

as_obj :: #force_inline proc "contextless" (v: Value) -> (obj: ^Obj, ok: bool) {
	return v.(^Obj)
}
