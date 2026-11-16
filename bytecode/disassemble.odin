package bytecode

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
			fmt.wprintf(w, " [%v] %v", index, chunk.constants[index], flush = false)
		}

		io.write_byte(w, '\n')
		offset += 1 + op_operand_size[op]
	}
}
