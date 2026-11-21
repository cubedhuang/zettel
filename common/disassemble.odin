package common

import "core:fmt"
import "core:io"

disassemble :: proc(w: io.Writer, module: Module) {
	disassemble_chunk(w, module, module.main)
	for function in module.functions {
		fmt.wprintf(
			w,
			"\nfn %s/%v%v:\n",
			function_name(module, function),
			function.arity,
			"+" if function.variadic else "",
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
		size := 1 + op_operand_size[op]

		#partial switch op {
		case .Constant:
			index := read_u16(chunk.code, offset + 1)
			fmt.wprintf(w, " [%v] ", index, flush = false)
			disassemble_constant(w, module, chunk.constants[index])
		case .Closure:
			index := read_u16(chunk.code, offset + 1)
			fmt.wprintf(w, " [%v] ", index, flush = false)
			disassemble_constant(w, module, chunk.constants[index])
			function := module.functions[chunk.constants[index].(Constant_Function).index]
			for _ in 0 ..< function.upvalue_count {
				capture := read_capture(chunk.code, offset + size)
				fmt.wprintf(
					w,
					" %v[%v]",
					"local" if capture.is_local else "upvalue",
					capture.index,
					flush = false,
				)
				size += CAPTURE_SIZE
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
		case .Array:
			fmt.wprintf(w, " (%v)", read_u16(chunk.code, offset + 1), flush = false)
		case .Get_Local, .Set_Local:
			fmt.wprintf(w, " [%v]", read_u16(chunk.code, offset + 1), flush = false)
		case .Get_Upvalue, .Set_Upvalue:
			fmt.wprintf(w, " [%v]", chunk.code[offset + 1], flush = false)
		case .Get_Builtin:
			fmt.wprintf(w, " %v", builtin_names[Builtin(chunk.code[offset + 1])], flush = false)
		case .Call:
			fmt.wprintf(w, " (%v)", chunk.code[offset + 1], flush = false)
			disassemble_results(w, chunk.code[offset + 2], " -> ")
		case .Call_Spread:
			disassemble_results(w, chunk.code[offset + 1], " -> ")
		case .Return:
			disassemble_results(w, chunk.code[offset + 1], " ")
		}

		io.write_byte(w, '\n')
		offset += size
	}
}

disassemble_results :: proc(w: io.Writer, count: u8, prefix: string) {
	if count == ALL_RESULTS {
		fmt.wprintf(w, "%vall", prefix, flush = false)
	} else {
		fmt.wprintf(w, "%v%v", prefix, count, flush = false)
	}
}

disassemble_constant :: proc(w: io.Writer, module: Module, constant: Constant) {
	switch c in constant {
	case f64:
		fmt.wprint(w, c, flush = false)
	case Constant_String:
		fmt.wprintf(w, "\"%s\"", constant_string(module, c), flush = false)
	case Constant_Function:
		fmt.wprintf(w, "<fn %s>", function_name(module, module.functions[c.index]), flush = false)
	}
}
