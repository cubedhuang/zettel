// The compiler package is responsible for taking source code and converting it into a `common.Module` which may then be loaded into a `Vm`.
package compiler

import "../common"
import "core:fmt"
import "core:slice"
import "core:strconv"

// `Compiler` contains intermediate compilation data about a module. After compilation,
// it's converted into a `common.Module`.
Compiler :: struct {
	ast:                 Ast,
	chunk:               ^Chunk_Compiler,
	functions:           [dynamic]common.Function,
	string_bytes:        [dynamic]u8,
	// Keys are from the source.
	string_locations:    map[string]common.Constant_String,

	// Format like `common.Static_Names`.
	static_bytes:        [dynamic]u8,
	static_ends:         [dynamic]u32,
	// Keys are from the source or the previous `Static_Names`.
	static_slots:        map[string]int,
	// Whether class-body code can use each static yet.
	static_visible:      [dynamic]bool,
	// We want to be able to declare things multiple times in the REPL.
	allow_redeclaration: bool,
	// Whether top-level expression statements are echoed, like in the REPL.
	echo_statements:     bool,

	// Errors
	errors:              [dynamic]Compile_Error,
	// Only report some errors once.
	reported_once:       bit_set[Compile_Error_Tag],
	// Only report errors for any name once.
	reported_names:      map[Name_Error]struct{},
}

// Intermediate data about the class body or a function.
Chunk_Compiler :: struct {
	enclosing:          ^Chunk_Compiler,
	code:               [dynamic]u8,
	spans:              [dynamic]common.Span,
	constants:          [dynamic]common.Constant,
	constant_locations: map[common.Constant]int,
	// Each local's index is its stack slot relative to the frame.
	locals:             [dynamic]Local,
	// Variables of enclosing chunks that this function captures.
	upvalues:           [dynamic]common.Capture,
	// Declarations in the class body make statics at depth 0 and locals afterwards.
	depth:              int,
	// Enclosing loops and labeled statements, innermost last.
	targets:            [dynamic]Target,
	// `break` jumps that haven't been patched yet.
	breaks:             [dynamic]Break,
}

Local :: struct {
	name:     string,
	depth:    int,
	// Whether a nested function captures it, so leaving its scope must close the upvalue.
	captured: bool,
}

Variable :: struct {
	kind: enum u8 {
		Static,
		Local,
		Upvalue,
		Builtin,
	},
	// static_slots, locals, upvalues, or builtin index
	slot: int,
}

// Target for `break` and sometimes `continue`.
Target :: struct {
	// Empty for an unlabeled loop.
	label:   string,
	is_loop: bool,
	// Set while compiling a loop's `else`, which unlabeled `break` and `continue` skip past.
	in_else: bool,
	// Where `continue` goes.
	start:   int,
	// Locals deeper than this belong to the target.
	depth:   int,
}

Break :: struct {
	// The jump's location for `patch_jump`.
	location: int,
	// Index into `Chunk_Compiler.targets`.
	target:   int,
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
	Too_Many_Upvalues,
	// `node` is the identifier.
	Undeclared,
	// `node` is the identifier or `Fn_Decl`.
	Redeclared,
	// `node` is the target.
	Invalid_Assignment_Target,
	// `node` is the assignment or declaration.
	Too_Few_Values,
	// `node` is the assignment or declaration.
	Too_Many_Results,
	// `node` is the `break` or `continue`.
	Outside_Loop,
	// `node` is the `break` or `continue`.
	Unknown_Label,
	// `node` is the `continue`.
	Continue_Not_Loop,
	// `node` is the `continue`.
	Continue_From_Else,
	// `node` is the `Labeled`.
	Label_Shadowed,
	// `node` is the `return`.
	Return_Outside_Function,
	// `node` is the identifier.
	Used_Before_Declaration,
	// `node` is the identifier.
	Assign_To_Builtin,
}

Name_Error :: struct {
	tag:  Compile_Error_Tag,
	name: string,
}

// The instruction for each binary operator (except `And` and `Or`).
binary_ops := #partial [Node_Tag]common.Op {
	.Add           = .Add,
	.Sub           = .Sub,
	.Mul           = .Mul,
	.Div           = .Div,
	.Equal         = .Equal,
	.Not_Equal     = .Not_Equal,
	.Less          = .Less,
	.Less_Equal    = .Less_Equal,
	.Greater       = .Greater,
	.Greater_Equal = .Greater_Equal,
}

// `statics` are the names of statics declared by earlier compilations of the same class, such as
// previous REPL lines. They're copied into `module.statics` along with any new ones.
//
// `errors` are in source order and must be freed by the caller. Uses `context.temp_allocator`.
compile :: proc(
	ast: Ast,
	statics: common.Static_Names = {},
	allow_redeclaration := false,
	echo_statements := false,
) -> (
	module: common.Module,
	errors: []Compile_Error,
) {
	assert(len(ast.errors) == 0, "unable to compile an ast with errors")

	main: Chunk_Compiler
	c := Compiler {
		ast                 = ast,
		chunk               = &main,
		allow_redeclaration = allow_redeclaration,
		echo_statements     = echo_statements,
	}
	defer delete(c.string_locations)
	defer delete(c.static_slots)
	defer delete(c.static_visible)
	defer delete(c.reported_names)

	append(&c.static_bytes, ..statics.bytes)
	append(&c.static_ends, ..statics.ends)
	for slot in 0 ..< common.static_count(statics) {
		c.static_slots[common.static_name(statics, slot)] = slot
		append(&c.static_visible, true)
	}

	compile_root(&c)
	module.main = finish_chunk(&main)
	module.functions = c.functions[:]
	module.string_bytes = c.string_bytes[:]
	module.statics = {
		bytes = c.static_bytes[:],
		ends  = c.static_ends[:],
	}

	if len(c.errors) > 0 {
		common.module_destroy(&module)
		// sort errors by source order
		Positioned :: struct {
			position: u32,
			error:    Compile_Error,
		}
		positioned := make([]Positioned, len(c.errors), context.temp_allocator)
		for error, i in c.errors {
			positioned[i] = {compile_error_span(ast, error).main, error}
		}
		slice.stable_sort_by(positioned, proc(a, b: Positioned) -> bool {
			return a.position < b.position
		})
		for p, i in positioned do c.errors[i] = p.error
		return {}, c.errors[:]
	}
	delete(c.errors)
	return module, nil
}

// Frees the compiler's scratch data and returns the finished chunk.
finish_chunk :: proc(chunk: ^Chunk_Compiler) -> common.Chunk {
	delete(chunk.constant_locations)
	delete(chunk.locals)
	delete(chunk.upvalues)
	delete(chunk.targets)
	delete(chunk.breaks)
	return {code = chunk.code[:], spans = chunk.spans[:], constants = chunk.constants[:]}
}

compile_root :: proc(c: ^Compiler) {
	statements := root_statements(c.ast)
	for statement in statements {
		#partial switch c.ast.nodes[statement].tag {
		case .Fn_Decl:
			name := declared_name(c.ast, statement)
			if declare_static(c, name, statement) {
				c.static_visible[c.static_slots[name]] = true
			}
		case .Decl, .Decl_Multi:
			for target in assign_targets(c.ast, statement) {
				declare_static(c, token_text(c.ast, c.ast.nodes[target].main_token), target)
			}
		}
	}

	// hoist functions
	for statement in statements {
		if c.ast.nodes[statement].tag == .Fn_Decl do compile_fn_decl(c, statement)
	}
	for statement in statements {
		if c.ast.nodes[statement].tag != .Fn_Decl do compile_statement(c, statement)
	}
	span := token_span(c.ast, Token_Index(len(c.ast.tokens) - 1))
	emit(c, .Nil, span)
	emit(c, .Return, span)
	emit_byte(c, 1, span)
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
	case .While_Simple, .While:
		compile_while(c, index)
	case .Labeled:
		compile_labeled(c, index)
	case .Break, .Continue:
		compile_break(c, index)
	case .Fn_Decl:
		compile_fn_decl(c, index)
	case .Return, .Return_Multi:
		compile_return(c, index)
	case .Call_One, .Call:
		// a call statement discards however many values it returns
		compile_call(c, index, common.ALL_RESULTS)
		span := node_span(c.ast, index)
		if c.echo_statements && in_static_scope(c) do emit(c, .Echo_Results, span)
		emit(c, .Pop_Results, span)
	case:
		compile_expression(c, index)
		span := node_span(c.ast, index)
		if c.echo_statements && in_static_scope(c) && node.tag != .Echo {
			emit(c, .Echo_Result, span)
		}
		emit(c, .Pop, span)
	}
}

compile_assign :: proc(c: ^Compiler, index: Node_Index) {
	targets := assign_targets(c.ast, index)
	valid := true
	for target in targets {
		if c.ast.nodes[target].tag == .Index {
			continue
		} else if c.ast.nodes[target].tag != .Identifier {
			fail(c, .Invalid_Assignment_Target, target)
			valid = false
		} else if variable, ok := resolve(c, target); !ok {
			valid = false
		} else if variable.kind == .Builtin {
			fail(c, .Assign_To_Builtin, target)
			valid = false
		}
	}

	compile_values(c, index)
	if !valid do return

	// The last value is on top of the stack, so targets are assigned from right to left. An index
	// target's operands are evaluated just before it's assigned.
	#reverse for target in targets {
		span := node_span(c.ast, target)
		if c.ast.nodes[target].tag == .Index {
			compile_expression(c, c.ast.nodes[target].data.node_and_node.lhs)
			compile_expression(c, c.ast.nodes[target].data.node_and_node.rhs)
			emit(c, .Set_Index, span)
			continue
		}
		variable, _ := resolve(c, target)
		#partial switch variable.kind {
		case .Static:
			emit_variable(c, .Set_Static, variable, span)
		case .Local:
			emit_variable(c, .Set_Local, variable, span)
		case .Upvalue:
			emit(c, .Set_Upvalue, span)
			emit_byte(c, u8(variable.slot), span)
		}
	}
}

compile_decl :: proc(c: ^Compiler, index: Node_Index) {
	// do values first so shadowing is okay
	compile_values(c, index)
	targets := assign_targets(c.ast, index)

	if !in_static_scope(c) {
		for target in targets {
			declare_local(c, token_text(c.ast, c.ast.nodes[target].main_token), target)
		}
		return
	}

	for target in targets {
		c.static_visible[c.static_slots[token_text(c.ast, c.ast.nodes[target].main_token)]] = true
	}
	#reverse for target in targets {
		slot := c.static_slots[token_text(c.ast, c.ast.nodes[target].main_token)]
		emit_variable(c, .Set_Static, {.Static, slot}, node_span(c.ast, target))
	}
}

// Pushes the values of an assignment or declaration in order.
//
// A call that's the only value of several targets gives a value for each of them.
compile_values :: proc(c: ^Compiler, index: Node_Index) {
	values := assign_values(c.ast, index)
	target_count := len(assign_targets(c.ast, index))
	if len(values) == 1 && target_count > 1 && is_call(c.ast, values[0]) {
		if target_count > common.MAX_RESULTS do fail(c, .Too_Many_Results, index)
		compile_call(c, values[0], target_count)
		return
	}
	if len(values) < target_count do fail(c, .Too_Few_Values, index)
	for value in values do compile_expression(c, value)
}

is_call :: proc(ast: Ast, index: Node_Index) -> bool {
	return ast.nodes[index].tag == .Call_One || ast.nodes[index].tag == .Call
}

compile_if :: proc(c: ^Compiler, index: Node_Index) {
	init, condition, then_branch, else_branch := if_while_parts(c.ast, index)
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

compile_while :: proc(c: ^Compiler, index: Node_Index, label := "") {
	init, condition, body, else_branch := if_while_parts(c.ast, index)
	span := token_span(c.ast, c.ast.nodes[index].main_token)
	target := begin_target(
		c,
		{label = label, is_loop = true, start = len(c.chunk.code), depth = c.chunk.depth},
	)

	begin_scope(c)
	if init != 0 do compile_statement(c, init)
	compile_expression(c, condition)
	exit := emit_jump(c, .Jump_If_False, span)
	emit(c, .Pop, span)
	compile_statement(c, body)
	// Initializer locals are popped each iteration.
	emit_pops_above(c, c.chunk.targets[target].depth, span)
	emit_loop(c, c.chunk.targets[target].start, span, index)

	patch_jump(c, exit, index)
	emit(c, .Pop, span)
	// The `else` isn't part of the loop, but the initializer's locals are still in scope.
	c.chunk.targets[target].in_else = true
	if else_branch != 0 do compile_statement(c, else_branch)
	end_scope(c, span)

	end_target(c, target, index)
}

compile_labeled :: proc(c: ^Compiler, index: Node_Index) {
	label := token_text(c.ast, c.ast.nodes[index].main_token)
	for target in c.chunk.targets {
		if target.label == label {
			fail(c, .Label_Shadowed, index)
			break
		}
	}

	statement := c.ast.nodes[index].data.node
	#partial switch c.ast.nodes[statement].tag {
	case .While_Simple, .While:
		compile_while(c, statement, label)
	case:
		target := begin_target(c, {label = label, depth = c.chunk.depth})
		compile_statement(c, statement)
		end_target(c, target, index)
	}
}

compile_break :: proc(c: ^Compiler, index: Node_Index) {
	node := c.ast.nodes[index]
	is_break := node.tag == .Break

	found := -1
	if node.data.token == 0 {
		#reverse for target, i in c.chunk.targets {
			if target.is_loop && !target.in_else {
				found = i
				break
			}
		}
		if found < 0 {
			fail(c, .Outside_Loop, index)
			return
		}
	} else {
		label := token_text(c.ast, node.data.token)
		#reverse for target, i in c.chunk.targets {
			if target.label == label {
				found = i
				break
			}
		}
		switch {
		case found < 0:
			fail(c, .Unknown_Label, index)
			return
		case !is_break && !c.chunk.targets[found].is_loop:
			fail(c, .Continue_Not_Loop, index)
			return
		case !is_break && c.chunk.targets[found].in_else:
			fail(c, .Continue_From_Else, index)
			return
		}
	}

	target := c.chunk.targets[found]
	span := node_span(c.ast, index)
	emit_pops_above(c, target.depth, span)
	if is_break {
		append(&c.chunk.breaks, Break{emit_jump(c, .Jump, span), found})
	} else {
		emit_loop(c, target.start, span, index)
	}
}

compile_fn_decl :: proc(c: ^Compiler, index: Node_Index) {
	name := declared_name(c.ast, index)
	name_span := token_span(c.ast, c.ast.nodes[index].main_token + 1)
	params, body := fn_parts(c.ast, index)
	variadic := fn_is_variadic(c.ast, params)

	is_static := in_static_scope(c)
	if !is_static do declare_local(c, name, index)

	chunk := Chunk_Compiler {
		enclosing = c.chunk,
	}
	c.chunk = &chunk
	begin_scope(c)
	for param in params {
		declare_local(c, token_text(c.ast, c.ast.nodes[param].main_token), param)
	}
	for statement in block_statements(c.ast, body) {
		compile_statement(c, statement)
	}
	end_span := token_span(c.ast, last_token(c.ast, body))
	emit(c, .Nil, end_span)
	emit(c, .Return, end_span)
	emit_byte(c, 1, end_span)
	c.chunk = chunk.enclosing

	// Nested functions were added while compiling the body, so this one goes after them.
	constant := common.Constant_Function{u32(len(c.functions))}
	upvalue_count := len(chunk.upvalues)
	// A local function's value lands in its slot.
	if upvalue_count == 0 {
		emit_constant(c, constant, index)
	} else {
		span := node_span(c.ast, index)
		emit(c, .Closure, span)
		emit_u16(c, add_constant(c, constant, index), span)
		for capture in chunk.upvalues do emit_capture(c, capture, span)
	}
	if is_static {
		emit_variable(c, .Set_Static, {.Static, c.static_slots[name]}, name_span)
	}

	append(
		&c.functions,
		common.Function {
			name = add_string_bytes(c, name),
			arity = len(params) - int(variadic),
			variadic = variadic,
			upvalue_count = upvalue_count,
			chunk = finish_chunk(&chunk),
		},
	)
}

compile_return :: proc(c: ^Compiler, index: Node_Index) {
	if in_class_body(c) do fail(c, .Return_Outside_Function, index)
	values := return_values(c.ast, index)
	span := node_span(c.ast, index)
	count := len(values)
	switch {
	case count == 0:
		emit(c, .Nil, span)
		count = 1
	case count == 1 && is_call(c.ast, values[0]):
		// `return f()` forwards all of the call's values
		compile_call(c, values[0], common.ALL_RESULTS)
		count = common.ALL_RESULTS
	case:
		for value in values do compile_expression(c, value)
	}
	emit(c, .Return, span)
	emit_byte(c, u8(count), span)
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
		variable := resolve(c, index) or_break
		switch variable.kind {
		case .Static:
			emit_variable(c, .Get_Static, variable, span)
		case .Local:
			emit_variable(c, .Get_Local, variable, span)
		case .Upvalue:
			emit(c, .Get_Upvalue, span)
			emit_byte(c, u8(variable.slot), span)
		case .Builtin:
			emit(c, .Get_Builtin, span)
			emit_byte(c, u8(variable.slot), span)
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
	case .Array_Literal:
		elements := array_elements(c.ast, index)
		if !compile_list(c, elements, span) {
			emit(c, .Array, span)
			emit_u16(c, len(elements), span)
		}
	case .Index:
		compile_expression(c, node.data.node_and_node.lhs)
		compile_expression(c, node.data.node_and_node.rhs)
		emit(c, .Get_Index, span)
	case .Call_One, .Call:
		compile_call(c, index, 1)
	case .And, .Or:
		compile_expression(c, node.data.node_and_node.lhs)
		jump := emit_jump(c, .Jump_If_False if node.tag == .And else .Jump_If_True, span)
		emit(c, .Pop, span)
		compile_expression(c, node.data.node_and_node.rhs)
		patch_jump(c, jump, index)
	case .Add, .Sub, .Mul, .Div, .Equal, .Not_Equal, .Less, .Less_Equal, .Greater, .Greater_Equal:
		compile_expression(c, node.data.node_and_node.lhs)
		compile_expression(c, node.data.node_and_node.rhs)
		emit(c, binary_ops[node.tag], span)
	case:
		unreachable()
	}
}

// `results` is how many values the call must return, or `common.ALL_RESULTS`.
compile_call :: proc(c: ^Compiler, index: Node_Index, results: int) {
	span := node_span(c.ast, index)
	callee, args := call_parts(c.ast, index)
	compile_expression(c, callee)
	if compile_list(c, args, span) {
		emit(c, .Call_Spread, span)
	} else {
		emit(c, .Call, span)
		emit_byte(c, u8(len(args)), span)
	}
	emit_byte(c, u8(results), span)
}

// Pushes the arguments or elements in `items`. If any is a `Spread`, they're collected into one
// array instead, and `spread` is true. `span` is the list's source.
compile_list :: proc(c: ^Compiler, items: []Node_Index, span: common.Span) -> (spread: bool) {
	first_spread := -1
	for item, i in items {
		if c.ast.nodes[item].tag == .Spread {
			first_spread = i
			break
		}
	}
	if first_spread < 0 {
		for item in items do compile_expression(c, item)
		return false
	}

	for item in items[:first_spread] do compile_expression(c, item)
	emit(c, .Array, span)
	emit_u16(c, first_spread, span)
	for item in items[first_spread:] {
		if c.ast.nodes[item].tag == .Spread {
			compile_expression(c, c.ast.nodes[item].data.node)
			emit(c, .Array_Extend, node_span(c.ast, item))
		} else {
			compile_expression(c, item)
			emit(c, .Array_Push, span)
		}
	}
	return true
}

begin_scope :: proc(c: ^Compiler) {
	c.chunk.depth += 1
}

end_scope :: proc(c: ^Compiler, span: common.Span) {
	c.chunk.depth -= 1
	for len(c.chunk.locals) > 0 && c.chunk.locals[len(c.chunk.locals) - 1].depth > c.chunk.depth {
		emit_pop_local(c, pop(&c.chunk.locals), span)
	}
}

// Returns the target's index.
begin_target :: proc(c: ^Compiler, target: Target) -> int {
	append(&c.chunk.targets, target)
	return len(c.chunk.targets) - 1
}

// Patches the target's breaks to jump here. A `break` pops the target's locals itself, so it skips
// past any pops emitted when the target's scopes ended.
end_target :: proc(c: ^Compiler, target: int, node: Node_Index) {
	pop(&c.chunk.targets)
	kept := 0
	for b in c.chunk.breaks {
		if b.target == target {
			patch_jump(c, b.location, node)
		} else {
			c.chunk.breaks[kept] = b
			kept += 1
		}
	}
	resize(&c.chunk.breaks, kept)
}

// Whether the current chunk is the class body rather than a function.
in_class_body :: proc(c: ^Compiler) -> bool {
	return c.chunk.enclosing == nil
}

// Whether declarations make statics.
in_static_scope :: proc(c: ^Compiler) -> bool {
	return in_class_body(c) && c.chunk.depth == 0
}

// `node` is the declaration's source for errors.
declare_local :: proc(c: ^Compiler, name: string, node: Node_Index) {
	#reverse for local in c.chunk.locals {
		if local.depth < c.chunk.depth do break
		if local.name == name do fail(c, .Redeclared, node)
	}
	if len(c.chunk.locals) >= common.MAX_LOCALS do fail(c, .Too_Many_Locals, node)
	// append on failure to keep locals in sync with the stack
	append(&c.chunk.locals, Local{name = name, depth = c.chunk.depth})
}

// `node` is the declaration's source for errors.
declare_static :: proc(c: ^Compiler, name: string, node: Node_Index) -> (ok: bool) {
	if name in c.static_slots {
		if !c.allow_redeclaration {
			fail(c, .Redeclared, node)
			return false
		}
		return true
	}
	if len(c.static_ends) >= common.MAX_STATICS {
		fail(c, .Too_Many_Statics, node)
		return false
	}
	c.static_slots[name] = len(c.static_ends)
	append(&c.static_bytes, name)
	append(&c.static_ends, u32(len(c.static_bytes)))
	append(&c.static_visible, false)
	return true
}

resolve :: proc(c: ^Compiler, identifier: Node_Index) -> (variable: Variable, ok: bool) {
	name := token_text(c.ast, c.ast.nodes[identifier].main_token)
	#reverse for local, slot in c.chunk.locals {
		if local.name == name do return {.Local, slot}, true
	}
	if index, found := resolve_upvalue(c, c.chunk, name, identifier); found {
		return {.Upvalue, index}, true
	}
	if slot, found := c.static_slots[name]; found {
		if in_class_body(c) && !c.static_visible[slot] {
			fail(c, .Used_Before_Declaration, identifier)
			return
		}
		return {.Static, slot}, true
	}
	for builtin_name, builtin in common.builtin_names {
		if builtin_name == name do return {.Builtin, int(builtin)}, true
	}
	fail(c, .Undeclared, identifier)
	return
}

// Finds `name` in the chunks enclosing `chunk` and returns its index in `chunk.upvalues`, capturing
// it in every chunk in between.
resolve_upvalue :: proc(
	c: ^Compiler,
	chunk: ^Chunk_Compiler,
	name: string,
	identifier: Node_Index,
) -> (
	index: int,
	found: bool,
) {
	enclosing := chunk.enclosing
	if enclosing == nil do return
	#reverse for &local, slot in enclosing.locals {
		if local.name == name {
			local.captured = true
			return add_upvalue(c, chunk, {is_local = true, index = u16(slot)}, identifier), true
		}
	}
	outer := resolve_upvalue(c, enclosing, name, identifier) or_return
	return add_upvalue(c, chunk, {is_local = false, index = u16(outer)}, identifier), true
}

add_upvalue :: proc(
	c: ^Compiler,
	chunk: ^Chunk_Compiler,
	capture: common.Capture,
	identifier: Node_Index,
) -> int {
	for existing, index in chunk.upvalues {
		if existing == capture do return index
	}
	if len(chunk.upvalues) >= common.MAX_UPVALUES do fail(c, .Too_Many_Upvalues, identifier)
	append(&chunk.upvalues, capture)
	return len(chunk.upvalues) - 1
}

emit :: proc(c: ^Compiler, op: common.Op, span: common.Span) {
	emit_byte(c, u8(op), span)
}

emit_byte :: proc(c: ^Compiler, byte: u8, span: common.Span) {
	append(&c.chunk.code, byte)
	append(&c.chunk.spans, span)
}

emit_u16 :: proc(c: ^Compiler, value: int, span: common.Span) {
	offset := emit_space(c, 2, span)
	common.write_u16(c.chunk.code[:], offset, u16(value))
}

emit_capture :: proc(c: ^Compiler, capture: common.Capture, span: common.Span) {
	offset := emit_space(c, common.CAPTURE_SIZE, span)
	common.write_capture(c.chunk.code[:], offset, capture)
}

emit_space :: proc(c: ^Compiler, size: int, span: common.Span) -> int {
	offset := len(c.chunk.code)
	for _ in 0 ..< size do emit_byte(c, 0, span)
	return offset
}

emit_variable :: proc(c: ^Compiler, op: common.Op, variable: Variable, span: common.Span) {
	emit(c, op, span)
	emit_u16(c, variable.slot, span)
}

// `node` is the source of the constant.
emit_constant :: proc(c: ^Compiler, constant: common.Constant, node: Node_Index) {
	index := add_constant(c, constant, node)
	span := node_span(c.ast, node)
	emit(c, .Constant, span)
	emit_u16(c, index, span)
}

// Returns the offset's location for `patch_jump`.
emit_jump :: proc(c: ^Compiler, op: common.Op, span: common.Span) -> int {
	emit(c, op, span)
	emit_u16(c, 0xffff, span)
	return len(c.chunk.code) - 2
}

// Patches the jump at `location` point to the next instruction. `node` is the source of the jump.
patch_jump :: proc(c: ^Compiler, location: int, node: Node_Index) {
	jump := len(c.chunk.code) - (location + 2)
	if jump > int(max(u16)) {
		fail(c, .Jump_Too_Large, node)
		return
	}
	common.write_u16(c.chunk.code[:], location, u16(jump))
}

// Jumps back to `start`. `node` is the source of the jump.
emit_loop :: proc(c: ^Compiler, start: int, span: common.Span, node: Node_Index) {
	emit(c, .Loop, span)
	jump := len(c.chunk.code) + 2 - start
	if jump > int(max(u16)) do fail(c, .Jump_Too_Large, node)
	emit_u16(c, jump, span)
}

// Pops locals deeper than `depth` from the stack while keeping them declared.
emit_pops_above :: proc(c: ^Compiler, depth: int, span: common.Span) {
	#reverse for local in c.chunk.locals {
		if local.depth <= depth do break
		emit_pop_local(c, local, span)
	}
}

emit_pop_local :: proc(c: ^Compiler, local: Local, span: common.Span) {
	emit(c, .Close_Upvalue if local.captured else .Pop, span)
}

// Returns the constant's index in the chunk. `node` is the source of the constant.
add_constant :: proc(c: ^Compiler, constant: common.Constant, node: Node_Index) -> int {
	if index, ok := c.chunk.constant_locations[constant]; ok do return index
	index := len(c.chunk.constants)
	if index >= common.MAX_CONSTANTS {
		fail(c, .Too_Many_Constants, node)
		return 0
	}
	append(&c.chunk.constants, constant)
	c.chunk.constant_locations[constant] = index
	return index
}

// `source` includes the quotes.
add_string :: proc(c: ^Compiler, source: string) -> common.Constant_String {
	return add_string_bytes(c, source[1:len(source) - 1])
}

add_string_bytes :: proc(c: ^Compiler, str: string) -> common.Constant_String {
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

// Compilation continues after an error to find more
//
// Note: The module is discarded, so the code emitted afterwards doesn't need to make sense.
fail :: proc(c: ^Compiler, tag: Compile_Error_Tag, node: Node_Index) {
	#partial switch tag {
	case .Too_Many_Constants,
	     .Jump_Too_Large,
	     .Too_Many_Statics,
	     .Too_Many_Locals,
	     .Too_Many_Upvalues:
		if tag in c.reported_once do return
		c.reported_once += {tag}
	case .Undeclared, .Used_Before_Declaration:
		key := Name_Error{tag, token_text(c.ast, c.ast.nodes[node].main_token)}
		if key in c.reported_names do return
		c.reported_names[key] = {}
	}
	append(&c.errors, Compile_Error{tag, node})
}

error_message :: proc {
	parse_error_message,
	compile_error_message,
}

error_span :: proc {
	parse_error_span,
	compile_error_span,
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
	case .Too_Many_Upvalues:
		return fmt.tprintf("a function captures more than %v variables", common.MAX_UPVALUES)
	case .Undeclared:
		return fmt.tprintf(
			"'%v' is not declared",
			token_text(ast, ast.nodes[error.node].main_token),
		)
	case .Redeclared:
		return fmt.tprintf(
			"'%v' is already declared in this scope",
			declared_name(ast, error.node),
		)
	case .Invalid_Assignment_Target:
		return "can only assign to variables and elements"
	case .Too_Few_Values:
		return "fewer values than targets"
	case .Too_Many_Results:
		return fmt.tprintf("more than %v targets for a call's values", common.MAX_RESULTS)
	case .Outside_Loop:
		return fmt.tprintf(
			"'%v' outside of a loop",
			token_text(ast, ast.nodes[error.node].main_token),
		)
	case .Unknown_Label:
		return fmt.tprintf(
			"no enclosing statement is labeled '%v'",
			token_text(ast, ast.nodes[error.node].data.token),
		)
	case .Continue_Not_Loop:
		return fmt.tprintf(
			"can't continue '%v' because it isn't a loop",
			token_text(ast, ast.nodes[error.node].data.token),
		)
	case .Continue_From_Else:
		return fmt.tprintf(
			"can't continue '%v' from its else",
			token_text(ast, ast.nodes[error.node].data.token),
		)
	case .Label_Shadowed:
		return fmt.tprintf(
			"label '%v' is already used by an enclosing statement",
			token_text(ast, ast.nodes[error.node].main_token),
		)
	case .Return_Outside_Function:
		return "'return' outside of a function"
	case .Used_Before_Declaration:
		return fmt.tprintf(
			"'%v' is used before its declaration",
			token_text(ast, ast.nodes[error.node].main_token),
		)
	case .Assign_To_Builtin:
		return fmt.tprintf(
			"can't assign to builtin '%v'",
			token_text(ast, ast.nodes[error.node].main_token),
		)
	}
	unreachable()
}

compile_error_span :: proc(ast: Ast, error: Compile_Error) -> common.Span {
	return node_span(ast, error.node)
}
