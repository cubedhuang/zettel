// The compiler package is responsible for taking source code and converting it into a `bytecode.Module` which may then be loaded into a `Vm`.
package compiler

import "../bytecode"
import "core:strconv"

// `Compiler` contains intermediate compilation data about a single chunk. After compilation,
// it's converted into a `bytecode.Module`.
Compiler :: struct {
	ast:                Ast,
	code:               [dynamic]u8,
	constants:          [dynamic]bytecode.Constant,
	constant_locations: map[bytecode.Constant]int,
	error:              Compile_Error,
}

Compile_Error :: enum u8 {
	None,
	Too_Many_Constants,
}

compile :: proc(ast: Ast) -> (module: bytecode.Module, error: Compile_Error) {
	assert(len(ast.errors) == 0, "unable to compile an ast with errors")

	c := Compiler {
		ast = ast,
	}
	defer delete(c.constant_locations)

	for statement in root_statements(ast) {
		compile_expression(&c, statement)
		emit(&c, .Print)
	}
	emit(&c, .Return)

	if c.error != .None {
		delete(c.code)
		delete(c.constants)
		return {}, c.error
	}
	return {main = {code = c.code[:], constants = c.constants[:]}}, .None
}

compile_expression :: proc(c: ^Compiler, index: Node_Index) {
	node := c.ast.nodes[index]
	switch node.tag {
	case .Root:
		unreachable()
	case .Number_Literal:
		// TODO: better numbers
		value, _ := strconv.parse_f64(token_text(c.ast, node.main_token))
		emit_constant(c, value)
	case .Grouped:
		compile_expression(c, node.data.token_and_node.node)
	case .Negate:
		compile_expression(c, node.data.node)
		emit(c, .Negate)
	case .Add, .Sub, .Mul, .Div:
		compile_expression(c, node.data.node_and_node.lhs)
		compile_expression(c, node.data.node_and_node.rhs)
		#partial switch node.tag {
		case .Add:
			emit(c, .Add)
		case .Sub:
			emit(c, .Sub)
		case .Mul:
			emit(c, .Mul)
		case .Div:
			emit(c, .Div)
		}
	}
}

emit :: proc(c: ^Compiler, op: bytecode.Op) {
	append(&c.code, u8(op))
}

emit_constant :: proc(c: ^Compiler, constant: bytecode.Constant) {
	index, ok := c.constant_locations[constant]
	if !ok {
		index = len(c.constants)
		if index >= bytecode.MAX_CONSTANTS {
			c.error = .Too_Many_Constants
			return
		}
		append(&c.constants, constant)
		c.constant_locations[constant] = index
	}

	append(&c.code, u8(bytecode.Op.Constant), u8(index), u8(index >> 8))
}
