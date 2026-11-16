package zettel_runtime

import "core:io"
import "core:math"
import "core:strconv"

// TODO: probably this is nan-boxable
Value :: union {
	f64,
}

write_value :: proc(w: io.Writer, value: Value) {
	switch v in value {
	case nil:
		io.write_string(w, "nil")
	case f64:
		write_number(w, v)
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
