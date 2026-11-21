// Runs every `.zettel` file in this directory. Comments state what a file should do:
//
//     echo 1 + 2  // expect: 3
//     echo z      // error: 'z' is not declared
//     x := 1      // note: 'x' was first declared here
//
// `expect` comments are the output lines in order. `error` and `note` comments are the diagnostics,
// each reported on the line of its comment. A note belongs to whichever error it follows when
// diagnostics are ordered by line.
package zettel_tests

import "../common"
import "../compiler"
import "../runtime"
import "core:io"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import "core:testing"

EXPECT :: "// expect: "
ERROR :: "// error: "
NOTE :: "// note: "

Diagnostic :: struct {
	line:    int,
	message: string,
	note:    bool,
}

@(test)
run_files :: proc(t: ^testing.T) {
	entries, err := os.read_all_directory_by_path(#directory, context.allocator)
	if !testing.expectf(t, err == nil, "reading %v: %v", #directory, err) do return
	defer os.file_info_slice_delete(entries, context.allocator)

	slice.sort_by(entries, proc(a, b: os.File_Info) -> bool {return a.name < b.name})
	ran := 0
	for entry in entries {
		if filepath.ext(entry.name) != ".zettel" do continue
		run_file(t, entry.fullpath, entry.name)
		ran += 1
	}
	testing.expect(t, ran > 0, "no test files found")
}

run_file :: proc(t: ^testing.T, path, name: string) {
	defer free_all(context.temp_allocator)

	text, err := os.read_entire_file(path, context.allocator)
	if !testing.expectf(t, err == nil, "reading %v: %v", path, err) do return
	defer delete(text)

	source := common.source_make(name, string(text))
	defer common.source_destroy(&source)

	expected_output: [dynamic]string
	expected_errors: [dynamic]Diagnostic
	defer delete(expected_output)
	defer delete(expected_errors)
	for line_number in 0 ..< common.line_count(&source) {
		line := common.line_text(&source, line_number)
		if i := strings.index(line, EXPECT); i >= 0 {
			append(&expected_output, line[i + len(EXPECT):])
		} else if i := strings.index(line, ERROR); i >= 0 {
			append(&expected_errors, Diagnostic{line_number + 1, line[i + len(ERROR):], false})
		} else if i := strings.index(line, NOTE); i >= 0 {
			append(&expected_errors, Diagnostic{line_number + 1, line[i + len(NOTE):], true})
		}
	}

	output := strings.builder_make()
	defer strings.builder_destroy(&output)
	actual_errors := run(&source, strings.to_writer(&output))
	defer delete(actual_errors)
	// notes come right after their errors, but can be on earlier lines
	slice.stable_sort_by(actual_errors[:], proc(a, b: Diagnostic) -> bool {
		return a.line < b.line
	})

	actual_output := strings.split_lines(strings.to_string(output))
	defer delete(actual_output)
	// the output ends with a newline, so the last "line" is empty
	actual_output = actual_output[:len(actual_output) - 1]

	testing.expectf(
		t,
		slice.equal(expected_output[:], actual_output),
		"%v: wrong output\n\texpected: %q\n\tactual:   %q",
		name,
		expected_output[:],
		actual_output,
	)
	testing.expectf(
		t,
		slice.equal(expected_errors[:], actual_errors[:]),
		"%v: wrong errors\n\texpected: %v\n\tactual:   %v",
		name,
		expected_errors[:],
		actual_errors[:],
	)
}

// Messages use `context.temp_allocator`.
run :: proc(source: ^common.Source, out: io.Writer) -> (errors: [dynamic]Diagnostic) {
	line_of :: proc(source: ^common.Source, span: common.Span) -> int {
		return common.line_index(source, span.main) + 1
	}

	ast := compiler.parse(source.text)
	defer compiler.ast_destroy(&ast)
	if len(ast.errors) > 0 {
		for error in ast.errors {
			append(
				&errors,
				Diagnostic {
					line_of(source, compiler.error_span(ast, error)),
					compiler.error_message(ast, error),
					false,
				},
			)
		}
		return
	}

	module, compile_errors := compiler.compile(ast)
	if len(compile_errors) > 0 {
		for error in compile_errors {
			append(
				&errors,
				Diagnostic {
					line_of(source, compiler.error_span(ast, error)),
					compiler.error_message(ast, error),
					false,
				},
			)
			for note in compiler.error_notes(ast, error) {
				append(&errors, Diagnostic{line_of(source, note.span), note.message, true})
			}
		}
		delete(compile_errors)
		return
	}
	defer common.module_destroy(&module)

	vm: runtime.Vm
	runtime.vm_init(&vm, out)
	defer runtime.vm_destroy(&vm)
	if runtime_error, ok := runtime.run(&vm, runtime.load(&vm, source, module)); !ok {
		error_source := &vm.sources[runtime_error.source]
		append(
			&errors,
			Diagnostic{line_of(error_source, runtime_error.span), runtime_error.message, false},
		)
	}
	return
}
