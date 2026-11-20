package common

import "core:fmt"
import "core:io"

disassemble :: proc(w: io.Writer, chunk: Chunk) {
	offset := 0
	for offset < len(chunk.code) {
		op := Op(chunk.code[offset])
		fmt.wprintf(w, "% 4d %v", offset, op, flush = false)

		#partial switch op {
		case .Constant:
			index := read_u16(chunk.code, offset + 1)
			fmt.wprintf(w, " [%v] ", index, flush = false)
			constant := chunk.constants[index]
			switch c in constant {
			case f64:
				fmt.wprint(w, c, flush = false)
			case Constant_String:
				fmt.wprintf(w, "\"%s\"", chunk.string_bytes[c.start:][:c.len], flush = false)
			}
		case .Jump, .Jump_If_False, .Jump_If_True:
			jump := read_u16(chunk.code, offset + 1)
			fmt.wprintf(w, " -> %v", offset + 3 + int(jump), flush = false)
		}

		io.write_byte(w, '\n')
		offset += 1 + op_operand_size[op]
	}
}
