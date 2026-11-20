// The compiler package is responsible for taking source code and converting it into a `common.Module` which may then be loaded into a `Vm`.
package compiler

import "../common"
import "core:fmt"
import "core:strconv"

// `Compiler` contains intermediate compilation data about a single chunk. After compilation,
// it's converted into a `common.Module`.
Compiler :: struct {
	ast:                 Ast,
	code:                [dynamic]u8,
	spans:               [dynamic]common.Span,
	constants:           [dynamic]common.Constant,
	constant_locations:  map[common.Constant]int,
	string_bytes:        [dynamic]u8,
	// Keys are from the source.
	string_locations:    map[string]common.Constant_String,

	// Format like `common.Static_Names`.
	static_bytes:        [dynamic]u8,
	static_ends:         [dynamic]u32,
	// Keys are from the source or preview Static_Names.
	static_slots:        map[string]int,
	// We want to be able to declare things multiple times in the REPL.
	allow_redeclaration: bool,
	// Whether top-level expression statements are echoed, like in the REPL.
	echo_statements:     bool,

	// Each local's index is its stack slot.
	locals:              [dynamic]Local,
	// Declarations make statics at depth 0 and locals afterwards.
	depth:               int,
	error:               Compile_Error,
}

Local :: struct {
	name:  string,
	depth: int,
}

Variable :: struct {
	kind: enum u8 {
		Static,
		Local,
	},
	slot: int,
}

Compile_Error :: struct {
	tag:  Compile_Error_Tag,
	node: Node_Index,
}

Compile_Error_Tag :: enum u8 {
	None,
	// TODO: get rid of these with dynamic constant widths
	Too_Many_Constants,
	Jump_Too_Large,
	Too_Many_Statics,
	Too_Many_Locals,
	// `node` is the identifier.
	Undeclared,
	// `node` is the identifier.
	Redeclared,
	// `node` is the target.
	Invalid_Assignment_Target,
	// `node` is the assignment or declaration.
	Too_Few_Values,
}

error_message :: proc {
	parse_error_message,
	compile_error_message,
}

// Uses `context.temp_allocator`.
compile_error_message :: proc(ast: Ast, error: Compile_Error) -> string {
	switch error.tag {
	case .None:
		return ""
	case .Too_Many_Constants:
		return fmt.tprintf("more than %v constants", common.MAX_CONSTANTS)
	case .Jump_Too_Large:
		return fmt.tprintf("jump over more than %v bytes of code", max(u16))
	case .Too_Many_Statics:
		return fmt.tprintf("more than %v static variables", common.MAX_STATICS)
	case .Too_Many_Locals:
		return fmt.tprintf("more than %v local variables", common.MAX_LOCALS)
	case .Undeclared:
		return fmt.tprintf(
			"'%v' is not declared",
			token_text(ast, ast.nodes[error.node].main_token),
		)
	case .Redeclared:
		return fmt.tprintf(
			"'%v' is already declared in this scope",
			token_text(ast, ast.nodes[error.node].main_token),
		)
	case .Invalid_Assignment_Target:
		return "can only assign to variables"
	case .Too_Few_Values:
		return "fewer values than targets"
	}
	unreachable()
}

// `statics` are the names of statics declared by earlier compilations of the same class, such as
// previous REPL lines. They're copied into `module.statics` along with any new ones.
compile :: proc(
	ast: Ast,
	statics: common.Static_Names = {},
	allow_redeclaration := false,
	echo_statements := false,
) -> (
	module: common.Module,
	error: Compile_Error,
) {
	assert(len(ast.errors) == 0, "unable to compile an ast with errors")

	c := Compiler {
		ast                 = ast,
		allow_redeclaration = allow_redeclaration,
		echo_statements     = echo_statements,
	}
	defer delete(c.constant_locations)
	defer delete(c.string_locations)
	defer delete(c.static_slots)
	defer delete(c.locals)

	append(&c.static_bytes, ..statics.bytes)
	append(&c.static_ends, ..statics.ends)
	for slot in 0 ..< common.static_count(statics) {
		c.static_slots[common.static_name(statics, slot)] = slot
	}

	compile_root(&c)

	if c.error.tag != .None {
		delete(c.code)
		delete(c.spans)
		delete(c.constants)
		delete(c.string_bytes)
		delete(c.static_bytes)
		delete(c.static_ends)
		return {}, c.error
	}
	module.main = {
		code      = c.code[:],
		spans     = c.spans[:],
		constants = c.constants[:],
	}
	module.string_bytes = c.string_bytes[:]
	module.statics = {
		bytes = c.static_bytes[:],
		ends  = c.static_ends[:],
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
		begin_scope(c)
		for statement in block_statements(c.ast, index) {
			compile_statement(c, statement)
		}
		end_scope(c, token_span(c.ast, last_token(c.ast, index)))
	case .Assign, .Assign_Multi:
		compile_assign(c, index)
	case .Decl, .Decl_Multi:
		compile_decl(c, index)
	case .If_Simple, .If:
		compile_if(c, index)
	case:
		compile_expression(c, index)
		span := node_span(c.ast, index)
		if c.echo_statements && c.depth == 0 && node.tag != .Echo {
			emit(c, .Echo, span)
		}
		emit(c, .Pop, span)
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
	case .Identifier:
		if variable, ok := resolve(c, index); ok {
			emit_variable(
				c,
				.Get_Static if variable.kind == .Static else .Get_Local,
				variable,
				span,
			)
		}
	case .Grouped:
		compile_expression(c, node.data.token_and_node.node)
	case .Negate:
		compile_expression(c, node.data.node)
		emit(c, .Negate, span)
	case .Not:
		compile_expression(c, node.data.node)
		emit(c, .Not, span)
	case .Echo:
		compile_expression(c, node.data.node)
		emit(c, .Echo, span)
	case .And, .Or:
		compile_expression(c, node.data.node_and_node.lhs)
		jump := emit_jump(c, .Jump_If_False if node.tag == .And else .Jump_If_True, span)
		emit(c, .Pop, span)
		compile_expression(c, node.data.node_and_node.rhs)
		patch_jump(c, jump, index)
	case .Add, .Sub, .Mul, .Div, .Equal, .Not_Equal, .Less, .Less_Equal, .Greater, .Greater_Equal:
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
		case .Equal:
			emit(c, .Equal, span)
		case .Not_Equal:
			emit(c, .Not_Equal, span)
		case .Less:
			emit(c, .Less, span)
		case .Less_Equal:
			emit(c, .Less_Equal, span)
		case .Greater:
			emit(c, .Greater, span)
		case .Greater_Equal:
			emit(c, .Greater_Equal, span)
		}
	case:
		unreachable()
	}
}

compile_if :: proc(c: ^Compiler, index: Node_Index) {
	init, condition, then_branch, else_branch := if_parts(c.ast, index)
	span := token_span(c.ast, c.ast.nodes[index].main_token)

	if init != 0 {
		begin_scope(c)
		compile_statement(c, init)
	}
	defer if init != 0 do end_scope(c, span)

	compile_expression(c, condition)
	to_else := emit_jump(c, .Jump_If_False, span)
	emit(c, .Pop, span)
	compile_statement(c, then_branch)
	to_end := emit_jump(c, .Jump, span)

	patch_jump(c, to_else, index)
	emit(c, .Pop, span)
	if else_branch != 0 do compile_statement(c, else_branch)
	patch_jump(c, to_end, index)
}

begin_scope :: proc(c: ^Compiler) {
	c.depth += 1
}

end_scope :: proc(c: ^Compiler, span: common.Span) {
	c.depth -= 1
	for len(c.locals) > 0 && c.locals[len(c.locals) - 1].depth > c.depth {
		pop(&c.locals)
		emit(c, .Pop, span)
	}
}

compile_assign :: proc(c: ^Compiler, index: Node_Index) {
	targets := assign_targets(c.ast, index)
	for target in targets {
		if c.ast.nodes[target].tag != .Identifier {
			fail(c, .Invalid_Assignment_Target, target)
			return
		}
		if _, ok := resolve(c, target); !ok do return
	}

	if !compile_values(c, index) do return

	// The last value is on top of the stack.
	#reverse for target in targets {
		variable, _ := resolve(c, target)
		op: common.Op = .Set_Static if variable.kind == .Static else .Set_Local
		emit_variable(c, op, variable, node_span(c.ast, target))
	}
}

compile_decl :: proc(c: ^Compiler, index: Node_Index) {
	// do values first so shadowing is okay
	if !compile_values(c, index) do return
	targets := assign_targets(c.ast, index)

	if c.depth > 0 {
		for target in targets do declare_local(c, target)
		return
	}

	for target in targets {
		if !declare_static(c, target) do return
	}
	#reverse for target in targets {
		slot := c.static_slots[token_text(c.ast, c.ast.nodes[target].main_token)]
		emit_variable(c, .Set_Static, {.Static, slot}, node_span(c.ast, target))
	}
}

// Pushes the values of an assignment or declaration in order.
compile_values :: proc(c: ^Compiler, index: Node_Index) -> (ok: bool) {
	values := assign_values(c.ast, index)
	// TODO: allow fewer values once there are multiple returns
	if len(values) < len(assign_targets(c.ast, index)) {
		fail(c, .Too_Few_Values, index)
		return false
	}
	for value in values do compile_expression(c, value)
	return true
}

declare_local :: proc(c: ^Compiler, identifier: Node_Index) {
	name := token_text(c.ast, c.ast.nodes[identifier].main_token)
	#reverse for local in c.locals {
		if local.depth < c.depth do break
		if local.name == name do fail(c, .Redeclared, identifier)
	}
	if len(c.locals) >= common.MAX_LOCALS do fail(c, .Too_Many_Locals, identifier)
	// append on failure to keep locals in sync with the stack
	append(&c.locals, Local{name, c.depth})
}

declare_static :: proc(c: ^Compiler, identifier: Node_Index) -> (ok: bool) {
	name := token_text(c.ast, c.ast.nodes[identifier].main_token)
	if name in c.static_slots {
		if !c.allow_redeclaration {
			fail(c, .Redeclared, identifier)
			return false
		}
		return true
	}
	if len(c.static_ends) >= common.MAX_STATICS {
		fail(c, .Too_Many_Statics, identifier)
		return false
	}
	c.static_slots[name] = len(c.static_ends)
	append(&c.static_bytes, name)
	append(&c.static_ends, u32(len(c.static_bytes)))
	return true
}

resolve :: proc(c: ^Compiler, identifier: Node_Index) -> (variable: Variable, ok: bool) {
	name := token_text(c.ast, c.ast.nodes[identifier].main_token)
	#reverse for local, slot in c.locals {
		if local.name == name do return {.Local, slot}, true
	}
	if slot, found := c.static_slots[name]; found {
		return {.Static, slot}, true
	}
	fail(c, .Undeclared, identifier)
	return
}

fail :: proc(c: ^Compiler, tag: Compile_Error_Tag, node: Node_Index) {
	if c.error.tag == .None do c.error = {tag, node}
}

emit :: proc(c: ^Compiler, op: common.Op, span: common.Span) {
	emit_byte(c, u8(op), span)
}

emit_byte :: proc(c: ^Compiler, byte: u8, span: common.Span) {
	append(&c.code, byte)
	append(&c.spans, span)
}

emit_u16 :: proc(c: ^Compiler, value: int, span: common.Span) {
	emit_byte(c, u8(value), span)
	emit_byte(c, u8(value >> 8), span)
}

emit_variable :: proc(c: ^Compiler, op: common.Op, variable: Variable, span: common.Span) {
	emit(c, op, span)
	emit_u16(c, variable.slot, span)
}

// Returns the offset's location for `patch_jump`.
emit_jump :: proc(c: ^Compiler, op: common.Op, span: common.Span) -> int {
	emit(c, op, span)
	emit_u16(c, 0xffff, span)
	return len(c.code) - 2
}

// Patches the jump at `location` point to the next instruction. `node` is the source of the jump.
patch_jump :: proc(c: ^Compiler, location: int, node: Node_Index) {
	jump := len(c.code) - (location + 2)
	if jump > int(max(u16)) {
		fail(c, .Jump_Too_Large, node)
		return
	}
	c.code[location] = u8(jump)
	c.code[location + 1] = u8(jump >> 8)
}

// `node` is the source of the constant.
emit_constant :: proc(c: ^Compiler, constant: common.Constant, node: Node_Index) {
	index, ok := c.constant_locations[constant]
	if !ok {
		index = len(c.constants)
		if index >= common.MAX_CONSTANTS {
			fail(c, .Too_Many_Constants, node)
			return
		}
		append(&c.constants, constant)
		c.constant_locations[constant] = index
	}

	span := node_span(c.ast, node)
	emit(c, .Constant, span)
	emit_u16(c, index, span)
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
