// The compiler package is responsible for taking source code and converting it into a `common.Module` which may then be loaded into a `Vm`.
package compiler

import "../common"
import "core:strconv"

// `Compiler` contains intermediate compilation data about a single chunk. After compilation,
// it's converted into a `common.Module`.
Compiler :: struct {
	ast:                Ast,
	code:               [dynamic]u8,
	spans:              [dynamic]common.Span,
	constants:          [dynamic]common.Constant,
	constant_locations: map[common.Constant]int,
	string_bytes:       [dynamic]u8,
	string_locations:   map[string]common.Constant_String,
	error:              Compile_Error,
}

Compile_Error :: struct {
	tag:  Compile_Error_Tag,
	node: Node_Index,
}

Compile_Error_Tag :: enum u8 {
	None,
	Too_Many_Constants,
}

compile :: proc(ast: Ast) -> (module: common.Module, error: Compile_Error) {
	assert(len(ast.errors) == 0, "unable to compile an ast with errors")

	c := Compiler {
		ast = ast,
	}
	defer delete(c.constant_locations)
	defer delete(c.string_locations)

	compile_root(&c)

	if c.error.tag != .None {
		delete(c.code)
		delete(c.spans)
		delete(c.constants)
		delete(c.string_bytes)
		return {}, c.error
	}
	module.main = {
		code         = c.code[:],
		spans        = c.spans[:],
		constants    = c.constants[:],
		string_bytes = c.string_bytes[:],
	}
	return module, {}
}

compile_root :: proc(c: ^Compiler) {
	for statement in root_statements(c.ast) {
		compile_statement(c, statement)
	}
	emit(c, .Return, token_span(c.ast, Token_Index(len(c.ast.tokens) - 1)))
}

compile_statement :: proc(c: ^Compiler, index: Node_Index) {
	node := c.ast.nodes[index]
	#partial switch node.tag {
	case .Block:
		for statement in block_statements(c.ast, index) {
			compile_statement(c, statement)
		}
	case .Assign, .Assign_Multi: // TODO: implement this
	case .Decl, .Decl_Multi: // TODO: implement this
	case:
		compile_expression(c, index)
		emit(c, .Print, node_span(c.ast, index))
	}
}

compile_expression :: proc(c: ^Compiler, index: Node_Index) {
	node := c.ast.nodes[index]
	span := node_span(c.ast, index)
	#partial switch node.tag {
	case .Number_Literal:
		// TODO: better numbers
		value, _ := strconv.parse_f64(token_text(c.ast, node.main_token))
		emit_constant(c, value, index)
	case .String_Literal:
		// TODO: better strings
		value := add_string(c, token_text(c.ast, node.main_token))
		emit_constant(c, value, index)
	case .Nil_Literal:
		emit(c, .Nil, span)
	case .True_Literal:
		emit(c, .True, span)
	case .False_Literal:
		emit(c, .False, span)
	case .Identifier: // TODO: implement this

	case .Grouped:
		compile_expression(c, node.data.token_and_node.node)
	case .Negate:
		compile_expression(c, node.data.node)
		emit(c, .Negate, span)
	case .Not:
		compile_expression(c, node.data.node)
		emit(c, .Not, span)
	case .Add, .Sub, .Mul, .Div:
		compile_expression(c, node.data.node_and_node.lhs)
		compile_expression(c, node.data.node_and_node.rhs)
		#partial switch node.tag {
		case .Add:
			emit(c, .Add, span)
		case .Sub:
			emit(c, .Sub, span)
		case .Mul:
			emit(c, .Mul, span)
		case .Div:
			emit(c, .Div, span)
		}
	case:
		unreachable()
	}
}

emit :: proc(c: ^Compiler, op: common.Op, span: common.Span) {
	emit_byte(c, u8(op), span)
}

emit_byte :: proc(c: ^Compiler, byte: u8, span: common.Span) {
	append(&c.code, byte)
	append(&c.spans, span)
}

// `node` is the source of the constant.
emit_constant :: proc(c: ^Compiler, constant: common.Constant, node: Node_Index) {
	index, ok := c.constant_locations[constant]
	if !ok {
		index = len(c.constants)
		if index >= common.MAX_CONSTANTS {
			if c.error.tag == .None do c.error = {.Too_Many_Constants, node}
			return
		}
		append(&c.constants, constant)
		c.constant_locations[constant] = index
	}

	span := node_span(c.ast, node)
	emit(c, .Constant, span)
	emit_byte(c, u8(index), span)
	emit_byte(c, u8(index >> 8), span)
}

add_string :: proc(c: ^Compiler, source: string) -> common.Constant_String {
	str := source[1:len(source) - 1]
	if value, ok := c.string_locations[str]; ok {
		return value
	}

	bytes := transmute([]u8)str
	start := len(c.string_bytes)
	append(&c.string_bytes, ..bytes)

	value := common.Constant_String {
		start = u32(start),
		len   = u32(len(str)),
	}
	c.string_locations[str] = value

	return value
}
