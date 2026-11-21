package common

import "core:slice"
import "core:strings"

// Byte offsets into `Source.text`.
Span :: struct {
	start: u32,
	end:   u32,
	main:  u32,
}

// Owns its path and text.
Source :: struct {
	path:        string,
	text:        string,
	// Zero-indexed line to byte offset of its first character.
	line_starts: []u32,
}

// Copies `path` and `text`.
source_make :: proc(path: string, text: string) -> Source {
	line_starts: [dynamic]u32
	append(&line_starts, 0)
	for i in 0 ..< len(text) {
		// a trailing newline doesn't start another line
		if text[i] == '\n' && i + 1 < len(text) {
			append(&line_starts, u32(i + 1))
		}
	}
	return {path = strings.clone(path), text = strings.clone(text), line_starts = line_starts[:]}
}

source_clone :: proc(source: Source) -> Source {
	return {
		path = strings.clone(source.path),
		text = strings.clone(source.text),
		line_starts = slice.clone(source.line_starts),
	}
}

source_destroy :: proc(source: ^Source) {
	delete(source.path)
	delete(source.text)
	delete(source.line_starts)
}

line_count :: proc(source: ^Source) -> int {
	return len(source.line_starts)
}

line_index :: proc(source: ^Source, offset: u32) -> int {
	target := min(offset, u32(len(source.text)))

	index, found := slice.binary_search(source.line_starts, target)
	return index if found else index - 1
}

// Excludes '\n'.
line_text :: proc(source: ^Source, line: int) -> string {
	start := int(source.line_starts[line])
	end := len(source.text)
	if line + 1 < line_count(source) {
		end = int(source.line_starts[line + 1])
	}

	text := source.text[start:end]
	if len(text) > 0 && text[len(text) - 1] == '\n' do text = text[:len(text) - 1]
	if len(text) > 0 && text[len(text) - 1] == '\r' do text = text[:len(text) - 1]
	return text
}
