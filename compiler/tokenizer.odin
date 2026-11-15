package compiler

Token :: struct {
	tag:   Token_Tag,
	start: u32,
}

Token_Tag :: enum u8 {
	// Special states
	Invalid,
	EOF,
	// Symbols
	Eq,
	Plus,
	Minus,
	Star,
	Slash,
	Semi,
	Colon,
	Comma,
	Paren_Open,
	Paren_Close,
	Brace_Open,
	Brace_Close,
	// Keywords
	Keyword_If,
	Keyword_Else,
	Keyword_While,
	Keyword_For,
	Keyword_Fn,
	Keyword_Return,
	Keyword_Class,
	Keyword_Constructor,
	// Dynamic content
	Number,
	Identifier,
}

token_lexemes := #partial [Token_Tag]string {
	// Symbols
	.Eq                  = "=",
	.Plus                = "+",
	.Minus               = "-",
	.Star                = "*",
	.Slash               = "/",
	.Semi                = ";",
	.Colon               = ":",
	.Comma               = ",",
	.Paren_Open          = "(",
	.Paren_Close         = ")",
	.Brace_Open          = "{",
	.Brace_Close         = "}",
	// Keywords
	.Keyword_If          = "if",
	.Keyword_Else        = "else",
	.Keyword_While       = "while",
	.Keyword_For         = "for",
	.Keyword_Fn          = "fn",
	.Keyword_Return      = "return",
	.Keyword_Class       = "class",
	.Keyword_Constructor = "constructor",
}

Tokenizer :: struct {
	source:           string,
	offset:           int,
	insert_semicolon: bool,
}

tokenize :: proc(source: string) -> #soa[]Token {
	tokens: #soa[dynamic]Token

	t := Tokenizer {
		source = source,
	}
	for {
		token := scan(&t)
		append(&tokens, token)
		if token.tag == .EOF do break
	}

	return tokens[:]
}

scan :: proc(t: ^Tokenizer) -> (token: Token) {
	skip_whitespace: for {
		switch peek(t) {
		case ' ', '\t', '\r':
			t.offset += 1
		case '\n':
			if t.insert_semicolon do break skip_whitespace
			t.offset += 1
		case:
			break skip_whitespace
		}
	}

	token.tag = .Invalid
	token.start = u32(t.offset)

	if t.offset >= len(t.source) {
		token.tag = .Semi if t.insert_semicolon else .EOF
		t.insert_semicolon = false
		return
	}

	c := t.source[t.offset]
	t.offset += 1

	switch c {
	case '=':
		token.tag = .Eq
	case '+':
		token.tag = .Plus
	case '-':
		token.tag = .Minus
	case '*':
		token.tag = .Star
	case '/':
		token.tag = .Slash
	case ';':
		token.tag = .Semi
	case ':':
		token.tag = .Colon
	case ',':
		token.tag = .Comma
	case '(':
		token.tag = .Paren_Open
	case ')':
		token.tag = .Paren_Close
	case '{':
		token.tag = .Brace_Open
	case '}':
		token.tag = .Brace_Close
	case '\n':
		token.tag = .Semi

	// TODO: floating point and whatnot. for now we just have integers
	case '0' ..= '9':
		token.tag = .Number

		for is_alphanumeric(peek(t)) || peek(t) == '_' {
			if is_alpha(peek(t)) || peek(t) == '_' {
				token.tag = .Invalid
			}
			t.offset += 1
		}

	case 'a' ..= 'z', 'A' ..= 'Z', '_':
		token.tag = .Identifier

		for is_alphanumeric(peek(t)) || peek(t) == '_' {
			t.offset += 1
		}

		switch t.source[token.start:t.offset] {
		case "if":
			token.tag = .Keyword_If
		case "else":
			token.tag = .Keyword_Else
		case "while":
			token.tag = .Keyword_While
		case "for":
			token.tag = .Keyword_For
		case "fn":
			token.tag = .Keyword_Fn
		case "return":
			token.tag = .Keyword_Return
		case "class":
			token.tag = .Keyword_Class
		case "constructor":
			token.tag = .Keyword_Constructor
		}

	// non-ASCII characters outside of strings are invalid
	case 0x80 ..= 0xFF:
		for peek(t) & 0xC0 == 0x80 {
			t.offset += 1
		}
	}

	#partial switch token.tag {
	case .Invalid:
		break
	case .Paren_Close, .Brace_Close, .Number, .Identifier:
		t.insert_semicolon = true
	case:
		t.insert_semicolon = false
	}

	return
}

peek :: proc(t: ^Tokenizer) -> u8 {
	return t.source[t.offset] if t.offset < len(t.source) else 0
}

is_alphanumeric :: proc(c: u8) -> bool {
	switch c {
	case 'a' ..= 'z', 'A' ..= 'Z', '0' ..= '9':
		return true
	}
	return false
}

is_alpha :: proc(c: u8) -> bool {
	switch c {
	case 'a' ..= 'z', 'A' ..= 'Z':
		return true
	}
	return false
}

is_numeric :: proc(c: u8) -> bool {
	switch c {
	case '0' ..= '9':
		return true
	}
	return false
}
