// The compiler package converts source code into a `common.Module`, which a `Vm` can then load.
package compiler

import "../common"
import "core:fmt"
import "core:slice"
import "core:strconv"

// `Compiler` holds the data used during the compilation of a module. After compilation, it
// becomes a `common.Module`.
Compiler :: struct {
	ast:                 Ast,
	chunk:               ^Chunk_Compiler,
	class:               ^Class_Compiler,
	functions:           [dynamic]common.Function,
	// The file's class is first. A class's `statics` are set after its body is compiled.
	classes:             [dynamic]common.Class,
	string_bytes:        [dynamic]u8,
	// The keys are slices of the source or of `decoded_strings`.
	string_locations:    map[string]common.Constant_String,
	// String literals with escapes, which `strconv.unquote_string` allocated.
	decoded_strings:     [dynamic]string,
	// Lets the REPL declare a static of the file's class more than once.
	allow_redeclaration: bool,
	// Whether top-level expression statements are echoed, like in the REPL.
	echo_statements:     bool,

	// Errors
	errors:              [dynamic]Compile_Error,
	// Error tags that are reported only once.
	reported_once:       bit_set[Compile_Error_Tag],
	// Names that already have an error. Each name gets one error.
	reported_names:      map[Name_Error]struct{},
}

// Intermediate data about the class being compiled.
Class_Compiler :: struct {
	// The class it's declared in.
	outer:          ^Class_Compiler,
	// Index into `Compiler.classes`.
	index:          int,
	// Same format as `common.Static_Names`.
	static_bytes:   [dynamic]u8,
	static_ends:    [dynamic]u32,
	// The keys are slices of the source or of the previous `Static_Names`.
	static_slots:   map[string]int,
	// Whether class-body code can use each static yet.
	static_visible: [dynamic]bool,
	// The declaration of each static, or 0 for one from a previous `Static_Names`.
	static_nodes:   [dynamic]Node_Index,
}

// Intermediate data about a class body or a function.
Chunk_Compiler :: struct {
	// nil for a class body.
	enclosing:          ^Chunk_Compiler,
	kind:               common.Function_Kind,
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
	// The declaration.
	node:     Node_Index,
	depth:    int,
	// Whether a nested function captures it, so leaving its scope must close the upvalue.
	captured: bool,
}

Variable :: struct {
	kind: enum u8 {
		Static,
		// A static of a class that the current class is declared in.
		Outer_Static,
		Local,
		Upvalue,
		Builtin,
	},
	// Index into `static_slots`, `locals`, `upvalues`, or the builtins
	slot: int,
	// For `Outer_Static`, how many classes out the static is.
	hops: int,
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
	// The `Labeled` node, or 0 for an unlabeled loop.
	node:    Node_Index,
}

Break :: struct {
	// The jump's location for `patch_jump`.
	location: int,
	// Index into `Chunk_Compiler.targets`.
	target:   int,
}

Compile_Error :: struct {
	tag:     Compile_Error_Tag,
	node:    Node_Index,
	// An earlier node that a note points at, or 0.
	related: Node_Index,
}

// Extra information about an error, at another place in the source.
Error_Note :: struct {
	span:    common.Span,
	message: string,
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
	// `node` is the identifier or declaration. `related` is the first declaration, if known.
	Redeclared,
	// `node` is the target.
	Invalid_Assignment_Target,
	// `node` is the literal.
	Invalid_Number,
	// `node` is the literal.
	Invalid_String,
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
	// `node` is the `Labeled`. `related` is the enclosing `Labeled`.
	Label_Shadowed,
	// `node` is the `return`.
	Return_Outside_Function,
	// `node` is the identifier. `related` is the declaration, if known.
	Used_Before_Declaration,
	// `node` is the identifier.
	Assign_To_Builtin,
	// `node` is the `Class_Decl` or `Constructor_Decl`.
	Not_In_Class_Body,
	// `node` is the `Class_Decl`.
	Classes_Too_Deep,
	// `node` is the `return`.
	Return_In_Constructor,
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
	.Mod           = .Mod,
	.Mod_Floored   = .Mod_Floored,
	.Pow           = .Pow,
	.Bit_And       = .Bit_And,
	.Bit_Or        = .Bit_Or,
	.Bit_Xor       = .Bit_Xor,
	.Shift_Left    = .Shift_Left,
	.Shift_Right   = .Shift_Right,
	.Equal         = .Equal,
	.Not_Equal     = .Not_Equal,
	.Less          = .Less,
	.Less_Equal    = .Less_Equal,
	.Greater       = .Greater,
	.Greater_Equal = .Greater_Equal,
}

// The instruction for each compound assignment operator.
compound_ops := #partial [Token_Tag]common.Op {
	.Plus_Eq            = .Add,
	.Minus_Eq           = .Sub,
	.Star_Eq            = .Mul,
	.Slash_Eq           = .Div,
	.Percent_Eq         = .Mod,
	.Percent_Percent_Eq = .Mod_Floored,
	.Caret_Eq           = .Pow,
	.Amp_Eq             = .Bit_And,
	.Pipe_Eq            = .Bit_Or,
	.Tilde_Eq           = .Bit_Xor,
	.Lt_Lt_Eq           = .Shift_Left,
	.Gt_Gt_Eq           = .Shift_Right,
}

// `statics` are the names of statics declared by earlier compilations of the same file, such as
// previous REPL lines. They're copied into the statics of the file's class along with any new ones.
//
// `errors` are in source order. The caller must free them. Uses `context.temp_allocator`.
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

	main := Chunk_Compiler {
		kind = .Class_Body,
	}
	root: Class_Compiler
	c := Compiler {
		ast                 = ast,
		chunk               = &main,
		class               = &root,
		allow_redeclaration = allow_redeclaration,
		echo_statements     = echo_statements,
	}
	defer delete(c.string_locations)
	defer {
		for s in c.decoded_strings do delete(s)
		delete(c.decoded_strings)
	}
	defer delete(c.reported_names)

	append(&root.static_bytes, ..statics.bytes)
	append(&root.static_ends, ..statics.ends)
	for slot in 0 ..< common.static_count(statics) {
		root.static_slots[common.static_name(statics, slot)] = slot
		append(&root.static_visible, true)
		append(&root.static_nodes, 0)
	}
	append(&c.classes, common.Class{})

	end := token_span(c.ast, Token_Index(len(c.ast.tokens) - 1))
	compile_class_body(&c, root_statements(c.ast), end)
	module.main = finish_chunk(&main)
	c.classes[0].statics = finish_class(&root)
	module.functions = c.functions[:]
	module.classes = c.classes[:]
	module.string_bytes = c.string_bytes[:]

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

// Frees the compiler's scratch data and returns the class's static names.
finish_class :: proc(class: ^Class_Compiler) -> common.Static_Names {
	delete(class.static_slots)
	delete(class.static_visible)
	delete(class.static_nodes)
	return {bytes = class.static_bytes[:], ends = class.static_ends[:]}
}

// Compiles the statements of `c.class`'s body into `c.chunk`. `end` is the source of the code at the
// end of the body.
compile_class_body :: proc(c: ^Compiler, statements: []Node_Index, end: common.Span) {
	for statement in statements {
		#partial switch c.ast.nodes[statement].tag {
		case .Fn_Decl, .Constructor_Decl:
			name := declared_name(c.ast, statement)
			if declare_static(c, name, statement) {
				c.class.static_visible[c.class.static_slots[name]] = true
			}
		case .Class_Decl:
			declare_static(c, declared_name(c.ast, statement), statement)
		case .Decl, .Decl_Multi:
			for target in assign_targets(c.ast, statement) {
				declare_static(c, token_text(c.ast, c.ast.nodes[target].main_token), target)
			}
		}
	}

	// hoist functions and constructors
	for statement in statements {
		if is_fn_decl(c.ast, statement) do compile_fn_decl(c, statement)
	}
	for statement in statements {
		if !is_fn_decl(c.ast, statement) do compile_statement(c, statement)
	}
	emit(c, .Nil, end)
	emit(c, .Return, end)
	emit_byte(c, 1, end)
}

is_fn_decl :: proc(ast: Ast, index: Node_Index) -> bool {
	return ast.nodes[index].tag == .Fn_Decl || ast.nodes[index].tag == .Constructor_Decl
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
	case .Compound_Assign:
		compile_compound_assign(c, index)
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
	case .Fn_Decl, .Constructor_Decl:
		compile_fn_decl(c, index)
	case .Class_Decl:
		compile_class_decl(c, index)
	case .Return, .Return_Multi:
		compile_return(c, index)
	case .Call_One, .Call:
		// a call statement discards however many values it returns
		compile_call(c, index, common.ALL_RESULTS)
		span := node_span(c.ast, index)
		if echoes_statements(c) do emit(c, .Echo_Results, span)
		emit(c, .Pop_Results, span)
	case:
		compile_expression(c, index)
		span := node_span(c.ast, index)
		if echoes_statements(c) && node.tag != .Echo {
			emit(c, .Echo_Result, span)
		}
		emit(c, .Pop, span)
	}
}

compile_assign :: proc(c: ^Compiler, index: Node_Index) {
	targets := assign_targets(c.ast, index)
	valid := true
	for target in targets {
		if c.ast.nodes[target].tag == .Index || c.ast.nodes[target].tag == .Property {
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

	// The last value is on top of the stack, so this assigns the targets from right to left. It
	// evaluates the operands of an index target just before it assigns to that target.
	#reverse for target in targets {
		span := node_span(c.ast, target)
		if c.ast.nodes[target].tag == .Index {
			compile_expression(c, c.ast.nodes[target].data.node_and_node.lhs)
			compile_expression(c, c.ast.nodes[target].data.node_and_node.rhs)
			emit(c, .Set_Index, span)
			continue
		}
		if c.ast.nodes[target].tag == .Property {
			compile_expression(c, c.ast.nodes[target].data.node)
			emit_property(c, .Set_Property, target, span)
			continue
		}
		variable, _ := resolve(c, target)
		emit_set(c, variable, span)
	}
}

compile_compound_assign :: proc(c: ^Compiler, index: Node_Index) {
	node := c.ast.nodes[index]
	target, value := node.data.node_and_node.lhs, node.data.node_and_node.rhs
	op := compound_ops[c.ast.tokens[node.main_token].tag]
	span := node_span(c.ast, index)

	#partial switch c.ast.nodes[target].tag {
	case .Index:
		// the indexed value and the index are evaluated once
		compile_expression(c, c.ast.nodes[target].data.node_and_node.lhs)
		compile_expression(c, c.ast.nodes[target].data.node_and_node.rhs)
		emit(c, .Get_Index_Keep, node_span(c.ast, target))
		compile_expression(c, value)
		emit(c, op, span)
		emit(c, .Update_Index, node_span(c.ast, target))
	case .Property:
		// the object is evaluated once
		target_span := node_span(c.ast, target)
		compile_expression(c, c.ast.nodes[target].data.node)
		emit_property(c, .Get_Property_Keep, target, target_span)
		compile_expression(c, value)
		emit(c, op, span)
		emit_property(c, .Update_Property, target, target_span)
	case .Identifier:
		variable, ok := resolve(c, target)
		if ok && variable.kind == .Builtin {
			fail(c, .Assign_To_Builtin, target)
			ok = false
		}
		if !ok {
			compile_expression(c, value)
			return
		}
		target_span := node_span(c.ast, target)
		emit_get(c, variable, target_span)
		compile_expression(c, value)
		emit(c, op, span)
		emit_set(c, variable, target_span)
	case:
		fail(c, .Invalid_Assignment_Target, target)
		compile_expression(c, value)
	}
}

compile_decl :: proc(c: ^Compiler, index: Node_Index) {
	// compile the values first so a declaration can shadow a name that its values use
	compile_values(c, index)
	targets := assign_targets(c.ast, index)

	if !in_static_scope(c) {
		for target in targets {
			declare_local(c, token_text(c.ast, c.ast.nodes[target].main_token), target)
		}
		return
	}

	for target in targets {
		c.class.static_visible[c.class.static_slots[token_text(c.ast, c.ast.nodes[target].main_token)]] =
			true
	}
	#reverse for target in targets {
		slot := c.class.static_slots[token_text(c.ast, c.ast.nodes[target].main_token)]
		emit_variable(c, .Set_Static, {kind = .Static, slot = slot}, node_span(c.ast, target))
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
	// Each iteration pops the initializer's locals.
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
			fail(c, .Label_Shadowed, index, target.node)
			break
		}
	}

	statement := c.ast.nodes[index].data.node
	#partial switch c.ast.nodes[statement].tag {
	case .While_Simple, .While:
		compile_while(c, statement, label)
	case:
		target := begin_target(c, {label = label, depth = c.chunk.depth, node = index})
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
	kind: common.Function_Kind =
		.Constructor if c.ast.nodes[index].tag == .Constructor_Decl else .Function

	is_static := in_static_scope(c)
	if !is_static {
		// a constructor needs a class to make instances of
		if kind == .Constructor do fail(c, .Not_In_Class_Body, index)
		declare_local(c, name, index)
	}

	chunk := Chunk_Compiler {
		enclosing = c.chunk,
		kind      = kind,
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
		emit_variable(
			c,
			.Set_Static,
			{kind = .Static, slot = c.class.static_slots[name]},
			name_span,
		)
	}

	append(
		&c.functions,
		common.Function {
			kind = kind,
			name = add_string_bytes(c, name),
			class = u32(c.class.index),
			arity = len(params) - int(variadic) - int(kind == .Constructor),
			variadic = variadic,
			upvalue_count = upvalue_count,
			chunk = finish_chunk(&chunk),
		},
	)
}

// Compiles the declaration of a class in the current class. The class's body runs when the
// declaration does.
compile_class_decl :: proc(c: ^Compiler, index: Node_Index) {
	name := declared_name(c.ast, index)
	name_span := token_span(c.ast, c.ast.nodes[index].main_token + 1)
	body := c.ast.nodes[index].data.node

	depth := 1
	for class := c.class; class.outer != nil; class = class.outer do depth += 1
	if depth > common.MAX_CLASS_DEPTH do fail(c, .Classes_Too_Deep, index)

	class_index := len(c.classes)
	append(&c.classes, common.Class{name = add_string_bytes(c, name), outer = u32(c.class.index)})

	// assign the class first so its body can use it
	emit_constant(c, common.Constant_Class{u32(class_index)}, index)
	if in_static_scope(c) {
		slot := c.class.static_slots[name]
		c.class.static_visible[slot] = true
		emit_variable(c, .Set_Static, {kind = .Static, slot = slot}, name_span)
	} else {
		// the class's value lands in its slot
		fail(c, .Not_In_Class_Body, index)
		declare_local(c, name, index)
	}

	class := Class_Compiler {
		outer = c.class,
		index = class_index,
	}
	chunk := Chunk_Compiler {
		kind = .Class_Body,
	}
	enclosing := c.chunk
	c.class, c.chunk = &class, &chunk
	compile_class_body(
		c,
		block_statements(c.ast, body),
		token_span(c.ast, last_token(c.ast, body)),
	)
	c.class, c.chunk = class.outer, enclosing
	c.classes[class_index].statics = finish_class(&class)

	// Functions in the body were added while compiling it, so the body goes after them.
	emit_constant(c, common.Constant_Function{u32(len(c.functions))}, index)
	emit(c, .Call, name_span)
	emit_byte(c, 0, name_span)
	emit_byte(c, 1, name_span)
	emit(c, .Pop, name_span)
	append(
		&c.functions,
		common.Function {
			kind = .Class_Body,
			name = add_string_bytes(c, name),
			class = u32(class_index),
			chunk = finish_chunk(&chunk),
		},
	)
}

compile_return :: proc(c: ^Compiler, index: Node_Index) {
	if in_class_body(c) do fail(c, .Return_Outside_Function, index)
	values := return_values(c.ast, index)
	// the VM returns the new instance instead of the value
	if c.chunk.kind == .Constructor && len(values) > 0 do fail(c, .Return_In_Constructor, index)
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
		value, ok := parse_number(token_text(c.ast, node.main_token))
		if !ok do fail(c, .Invalid_Number, index)
		emit_constant(c, value, index)
	case .String_Literal:
		text, allocated, ok := strconv.unquote_string(token_text(c.ast, node.main_token))
		if !ok do fail(c, .Invalid_String, index)
		if allocated do append(&c.decoded_strings, text)
		emit_constant(c, add_string_bytes(c, text), index)
	case .Nil_Literal:
		emit(c, .Nil, span)
	case .True_Literal:
		emit(c, .True, span)
	case .False_Literal:
		emit(c, .False, span)
	case .Identifier:
		variable := resolve(c, index) or_break
		emit_get(c, variable, span)
	case .Grouped:
		compile_expression(c, node.data.token_and_node.node)
	case .Negate:
		compile_expression(c, node.data.node)
		emit(c, .Negate, span)
	case .Not:
		compile_expression(c, node.data.node)
		emit(c, .Not, span)
	case .Bit_Not:
		compile_expression(c, node.data.node)
		emit(c, .Bit_Not, span)
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
	case .Property:
		compile_expression(c, node.data.node)
		emit_property(c, .Get_Property, index, span)
	case .Call_One, .Call:
		compile_call(c, index, 1)
	case .And, .Or:
		compile_expression(c, node.data.node_and_node.lhs)
		jump := emit_jump(c, .Jump_If_False if node.tag == .And else .Jump_If_True, span)
		emit(c, .Pop, span)
		compile_expression(c, node.data.node_and_node.rhs)
		patch_jump(c, jump, index)
	case .Add,
	     .Sub,
	     .Mul,
	     .Div,
	     .Mod,
	     .Mod_Floored,
	     .Pow,
	     .Bit_And,
	     .Bit_Or,
	     .Bit_Xor,
	     .Shift_Left,
	     .Shift_Right,
	     .Equal,
	     .Not_Equal,
	     .Less,
	     .Less_Equal,
	     .Greater,
	     .Greater_Equal:
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
	// `object.name(args)` is a method call, which doesn't get the property first
	is_invoke := c.ast.nodes[callee].tag == .Property
	compile_expression(c, c.ast.nodes[callee].data.node if is_invoke else callee)
	if len(args) == 1 && is_call(c.ast, args[0]) {
		// a call that's the only argument passes all of its values
		compile_call(c, args[0], common.ALL_RESULTS)
		emit_call(c, .Invoke if is_invoke else .Call, callee, span)
		emit_byte(c, common.ALL_RESULTS, span)
	} else if compile_list(c, args, span) {
		emit_call(c, .Invoke_Spread if is_invoke else .Call_Spread, callee, span)
	} else {
		emit_call(c, .Invoke if is_invoke else .Call, callee, span)
		emit_byte(c, u8(len(args)), span)
	}
	emit_byte(c, u8(results), span)
}

// Emits a call instruction, followed by the name operand for `Invoke` and `Invoke_Spread`.
emit_call :: proc(c: ^Compiler, op: common.Op, callee: Node_Index, span: common.Span) {
	if op == .Invoke || op == .Invoke_Spread {
		emit_property(c, op, callee, span)
	} else {
		emit(c, op, span)
	}
}

// Pushes the arguments or elements in `items`. If any item is a `Spread`, this collects them all
// into one array instead, and `spread` is true. `span` is the list's source.
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

// Whether expression statements are echoed here. Only the file's class body echoes them.
echoes_statements :: proc(c: ^Compiler) -> bool {
	return c.echo_statements && in_static_scope(c) && c.class.outer == nil
}

// `node` is the declaration's source for errors.
declare_local :: proc(c: ^Compiler, name: string, node: Node_Index) {
	#reverse for local in c.chunk.locals {
		if local.depth < c.chunk.depth do break
		if local.name == name do fail(c, .Redeclared, node, local.node)
	}
	if len(c.chunk.locals) >= common.MAX_LOCALS do fail(c, .Too_Many_Locals, node)
	// append on failure to keep locals in sync with the stack
	append(&c.chunk.locals, Local{name = name, node = node, depth = c.chunk.depth})
}

// `node` is the declaration's source for errors.
declare_static :: proc(c: ^Compiler, name: string, node: Node_Index) -> (ok: bool) {
	class := c.class
	if slot, found := class.static_slots[name]; found {
		if !c.allow_redeclaration || class.outer != nil {
			fail(c, .Redeclared, node, class.static_nodes[slot])
			return false
		}
		return true
	}
	if len(class.static_ends) >= common.MAX_STATICS {
		fail(c, .Too_Many_Statics, node)
		return false
	}
	class.static_slots[name] = len(class.static_ends)
	append(&class.static_bytes, name)
	append(&class.static_ends, u32(len(class.static_bytes)))
	append(&class.static_visible, false)
	append(&class.static_nodes, node)
	return true
}

resolve :: proc(c: ^Compiler, identifier: Node_Index) -> (variable: Variable, ok: bool) {
	name := token_text(c.ast, c.ast.nodes[identifier].main_token)
	#reverse for local, slot in c.chunk.locals {
		if local.name == name do return {kind = .Local, slot = slot}, true
	}
	if index, found := resolve_upvalue(c, c.chunk, name, identifier); found {
		return {kind = .Upvalue, slot = index}, true
	}
	hops := 0
	for class := c.class; class != nil; class = class.outer {
		if slot, found := class.static_slots[name]; found {
			if in_class_body(c) && !class.static_visible[slot] {
				fail(c, .Used_Before_Declaration, identifier, class.static_nodes[slot])
				return
			}
			if hops == 0 do return {kind = .Static, slot = slot}, true
			return {kind = .Outer_Static, slot = slot, hops = hops}, true
		}
		hops += 1
	}
	for builtin_name, builtin in common.builtin_names {
		if builtin_name == name do return {kind = .Builtin, slot = int(builtin)}, true
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

emit_outer_static :: proc(c: ^Compiler, op: common.Op, variable: Variable, span: common.Span) {
	emit(c, op, span)
	emit_byte(c, u8(variable.hops), span)
	emit_u16(c, variable.slot, span)
}

// Emits an instruction whose operand is the name of a `Property` node.
emit_property :: proc(c: ^Compiler, op: common.Op, property: Node_Index, span: common.Span) {
	name := token_text(c.ast, c.ast.nodes[property].main_token)
	emit(c, op, span)
	emit_u16(c, add_constant(c, add_string_bytes(c, name), property), span)
}

// Pushes the variable's value.
emit_get :: proc(c: ^Compiler, variable: Variable, span: common.Span) {
	switch variable.kind {
	case .Static:
		emit_variable(c, .Get_Static, variable, span)
	case .Outer_Static:
		emit_outer_static(c, .Get_Outer_Static, variable, span)
	case .Local:
		emit_variable(c, .Get_Local, variable, span)
	case .Upvalue:
		emit(c, .Get_Upvalue, span)
		emit_byte(c, u8(variable.slot), span)
	case .Builtin:
		emit(c, .Get_Builtin, span)
		emit_byte(c, u8(variable.slot), span)
	}
}

// Pops a value into the variable, which can't be a builtin.
emit_set :: proc(c: ^Compiler, variable: Variable, span: common.Span) {
	#partial switch variable.kind {
	case .Static:
		emit_variable(c, .Set_Static, variable, span)
	case .Outer_Static:
		emit_outer_static(c, .Set_Outer_Static, variable, span)
	case .Local:
		emit_variable(c, .Set_Local, variable, span)
	case .Upvalue:
		emit(c, .Set_Upvalue, span)
		emit_byte(c, u8(variable.slot), span)
	case:
		unreachable()
	}
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

// Patches the jump at `location` to point to the next instruction. `node` is the source of the
// jump.
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

// Parses a number literal: decimal with an optional fraction and exponent, or an integer with one
// of Odin's prefixes (`0b`, `0o`, `0d`, `0z`, or `0x`). Any of these can contain `_` separators.
parse_number :: proc(text: string) -> (value: f64, ok: bool) {
	if len(text) > 1 && text[0] == '0' && is_alpha(text[1]) && text[1] != 'e' && text[1] != 'E' {
		n: int
		integer := strconv.parse_u64_maybe_prefixed(text, &n) or_return
		return f64(integer), n == len(text)
	}
	n: int
	value = strconv.parse_f64(text, &n) or_return
	return value, n == len(text)
}

// Compilation continues after an error to find more errors.
//
// The caller discards the module, so the code emitted after an error does not need to make sense.
// `related` is an earlier node for a note to point at.
fail :: proc(c: ^Compiler, tag: Compile_Error_Tag, node: Node_Index, related: Node_Index = 0) {
	#partial switch tag {
	case .Too_Many_Constants,
	     .Jump_Too_Large,
	     .Too_Many_Statics,
	     .Too_Many_Locals,
	     .Too_Many_Upvalues,
	     .Classes_Too_Deep:
		if tag in c.reported_once do return
		c.reported_once += {tag}
	case .Undeclared, .Used_Before_Declaration:
		key := Name_Error{tag, token_text(c.ast, c.ast.nodes[node].main_token)}
		if key in c.reported_names do return
		c.reported_names[key] = {}
	}
	append(&c.errors, Compile_Error{tag, node, related})
}

error_message :: proc {
	parse_error_message,
	compile_error_message,
}

error_span :: proc {
	parse_error_span,
	compile_error_span,
}

error_notes :: proc {
	parse_error_notes,
	compile_error_notes,
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
		return "can only assign to variables, elements, and properties"
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
	case .Invalid_Number:
		return fmt.tprintf(
			"invalid number '%v'",
			token_text(ast, ast.nodes[error.node].main_token),
		)
	case .Invalid_String:
		return "invalid escape sequence in string"
	case .Not_In_Class_Body:
		return fmt.tprintf(
			"%v can only be declared directly in a class body",
			"a class" if ast.nodes[error.node].tag == .Class_Decl else "a constructor",
		)
	case .Classes_Too_Deep:
		return fmt.tprintf("classes nested more than %v deep", common.MAX_CLASS_DEPTH)
	case .Return_In_Constructor:
		return "a constructor can't return a value, because it returns the new instance"
	}
	unreachable()
}

compile_error_span :: proc(ast: Ast, error: Compile_Error) -> common.Span {
	if error.tag == .Redeclared do return declaration_span(ast, error.node)
	return node_span(ast, error.node)
}

// Uses `context.temp_allocator`.
compile_error_notes :: proc(ast: Ast, error: Compile_Error) -> []Error_Note {
	if error.related == 0 do return nil
	// a note on the same line, as in `x := x`, would only repeat the error
	a, b := ast.nodes[error.node].main_token, ast.nodes[error.related].main_token
	if tokens_on_same_line(ast, min(a, b), max(a, b)) do return nil
	message: string
	#partial switch error.tag {
	case .Redeclared:
		message = fmt.tprintf("'%v' was first declared here", declared_name(ast, error.related))
	case .Used_Before_Declaration:
		message = fmt.tprintf("'%v' is declared here", declared_name(ast, error.related))
	case .Label_Shadowed:
		message = fmt.tprintf(
			"the enclosing statement labeled '%v' is here",
			token_text(ast, ast.nodes[error.related].main_token),
		)
	case:
		return nil
	}
	notes := make([]Error_Note, 1, context.temp_allocator)
	notes[0] = {declaration_span(ast, error.related), message}
	return notes
}
