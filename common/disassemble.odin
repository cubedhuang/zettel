package common

import "core:fmt"
import "core:io"

disassemble :: proc(w: io.Writer, module: Module) {
	disassemble_chunk(w, module, module.main)
	for function in module.functions {
		fmt.wprintf(
			w,
			"\nfn %s/%v:\n",
			function_name(module, function),
			function.arity,
			flush = false,
		)
		disassemble_chunk(w, module, function.chunk)
	}
}

disassemble_chunk :: proc(w: io.Writer, module: Module, chunk: Chunk) {
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
				fmt.wprintf(w, "\"%s\"", constant_string(module, c), flush = false)
			case Constant_Function:
				fmt.wprintf(
					w,
					"<fn %s>",
					function_name(module, module.functions[c.index]),
					flush = false,
				)
			}
		case .Jump, .Jump_If_False, .Jump_If_True:
			jump := read_u16(chunk.code, offset + 1)
			fmt.wprintf(w, " -> %v", offset + 3 + int(jump), flush = false)
		case .Loop:
			jump := read_u16(chunk.code, offset + 1)
			fmt.wprintf(w, " -> %v", offset + 3 - int(jump), flush = false)
		case .Get_Static, .Set_Static:
			slot := read_u16(chunk.code, offset + 1)
			fmt.wprintf(w, " [%v] %v", slot, static_name(module.statics, int(slot)), flush = false)
		case .Get_Local, .Set_Local:
			fmt.wprintf(w, " [%v]", read_u16(chunk.code, offset + 1), flush = false)
		case .Call:
			fmt.wprintf(w, " (%v)", chunk.code[offset + 1], flush = false)
		}

		io.write_byte(w, '\n')
		offset += 1 + op_operand_size[op]
	}
}
