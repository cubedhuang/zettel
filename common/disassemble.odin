package common

import "core:fmt"
import "core:io"

disassemble :: proc(w: io.Writer, module: Module) {
	disassemble_chunk(w, module, module.main, 0)
	for function in module.functions {
		switch function.kind {
		case .Function, .Constructor:
			name := function_name(module, function)
			fmt.wprintf(
				w,
				"\n%v%v%s/%v%v:\n",
				"fn" if function.kind == .Function else "constructor",
				" " if name != "" else "",
				name,
				function.arity,
				"+" if function.variadic else "",
				flush = false,
			)
		case .Class_Body:
			fmt.wprintf(w, "\nclass %s:\n", function_name(module, function), flush = false)
		}
		disassemble_chunk(w, module, function.chunk, function.class)
	}
}

// `class` indexes `module.classes` and is the class whose statics the chunk uses.
disassemble_chunk :: proc(w: io.Writer, module: Module, chunk: Chunk, class: u32) {
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
			slot := int(read_u16(chunk.code, offset + 1))
			fmt.wprintf(
				w,
				" [%v] %v",
				slot,
				static_name(module.classes[class].statics, slot),
				flush = false,
			)
		case .Get_Outer_Static, .Set_Outer_Static:
			hops := chunk.code[offset + 1]
			slot := int(read_u16(chunk.code, offset + 2))
			outer := class
			for _ in 0 ..< hops do outer = module.classes[outer].outer
			fmt.wprintf(
				w,
				" (%v) [%v] %v",
				hops,
				slot,
				static_name(module.classes[outer].statics, slot),
				flush = false,
			)
		case .Get_Property, .Set_Property, .Get_Property_Keep, .Update_Property:
			index := read_u16(chunk.code, offset + 1)
			fmt.wprintf(w, " [%v] ", index, flush = false)
			disassemble_constant(w, module, chunk.constants[index])
		case .Array:
			fmt.wprintf(w, " (%v)", read_u16(chunk.code, offset + 1), flush = false)
		case .Get_Local, .Set_Local:
			fmt.wprintf(w, " [%v]", read_u16(chunk.code, offset + 1), flush = false)
		case .Get_Upvalue, .Set_Upvalue:
			fmt.wprintf(w, " [%v]", chunk.code[offset + 1], flush = false)
		case .Get_Builtin:
			fmt.wprintf(w, " %v", builtin_names[Builtin(chunk.code[offset + 1])], flush = false)
		case .Call:
			io.write_string(w, " (")
			disassemble_results(w, chunk.code[offset + 1], "")
			io.write_byte(w, ')')
			disassemble_results(w, chunk.code[offset + 2], " -> ")
		case .Call_Spread:
			disassemble_results(w, chunk.code[offset + 1], " -> ")
		case .Invoke:
			index := read_u16(chunk.code, offset + 1)
			fmt.wprintf(w, " [%v] ", index, flush = false)
			disassemble_constant(w, module, chunk.constants[index])
			io.write_string(w, " (")
			disassemble_results(w, chunk.code[offset + 3], "")
			io.write_byte(w, ')')
			disassemble_results(w, chunk.code[offset + 4], " -> ")
		case .Invoke_Spread:
			index := read_u16(chunk.code, offset + 1)
			fmt.wprintf(w, " [%v] ", index, flush = false)
			disassemble_constant(w, module, chunk.constants[index])
			disassemble_results(w, chunk.code[offset + 3], " -> ")
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
		function := module.functions[c.index]
		kind := "class body " if function.kind == .Class_Body else "fn "
		name := function_name(module, function)
		// a lambda has no name
		if name == "" do kind = "fn"
		fmt.wprintf(w, "<%v%s>", kind, name, flush = false)
	case Constant_Class:
		fmt.wprintf(w, "<class %s>", class_name(module, module.classes[c.index]), flush = false)
	}
}
