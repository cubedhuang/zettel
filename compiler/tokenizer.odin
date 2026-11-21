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
	Eq_Eq,
	Bang,
	Bang_Eq,
	Lt,
	Lt_Eq,
	Gt,
	Gt_Eq,
	Plus,
	Minus,
	Star,
	Slash,
	Percent,
	Percent_Percent,
	Caret,
	Amp,
	Pipe,
	Tilde,
	Lt_Lt,
	Gt_Gt,
	Plus_Eq,
	Minus_Eq,
	Star_Eq,
	Slash_Eq,
	Percent_Eq,
	Percent_Percent_Eq,
	Caret_Eq,
	Amp_Eq,
	Pipe_Eq,
	Tilde_Eq,
	Lt_Lt_Eq,
	Gt_Gt_Eq,
	Semi,
	Newline,
	Colon,
	Comma,
	Dot,
	Dot_Dot,
	Paren_Open,
	Paren_Close,
	Brace_Open,
	Brace_Close,
	Bracket_Open,
	Bracket_Close,
	// Keywords
	Keyword_Nil,
	Keyword_True,
	Keyword_False,
	Keyword_Or,
	Keyword_And,
	Keyword_If,
	Keyword_Else,
	Keyword_While,
	Keyword_For,
	Keyword_Break,
	Keyword_Continue,
	Keyword_Fn,
	Keyword_Return,
	Keyword_Class,
	Keyword_Constructor,
	Keyword_Echo,
	// Dynamic content
	Number,
	String,
	Identifier,
}

token_lexemes := #partial [Token_Tag]string {
	// Symbols
	.Eq                  = "=",
	.Eq_Eq               = "==",
	.Bang                = "!",
	.Bang_Eq             = "!=",
	.Lt                  = "<",
	.Lt_Eq               = "<=",
	.Gt                  = ">",
	.Gt_Eq               = ">=",
	.Plus                = "+",
	.Minus               = "-",
	.Star                = "*",
	.Slash               = "/",
	.Percent             = "%",
	.Percent_Percent     = "%%",
	.Caret               = "^",
	.Amp                 = "&",
	.Pipe                = "|",
	.Tilde               = "~",
	.Lt_Lt               = "<<",
	.Gt_Gt               = ">>",
	.Plus_Eq             = "+=",
	.Minus_Eq            = "-=",
	.Star_Eq             = "*=",
	.Slash_Eq            = "/=",
	.Percent_Eq          = "%=",
	.Percent_Percent_Eq  = "%%=",
	.Caret_Eq            = "^=",
	.Amp_Eq              = "&=",
	.Pipe_Eq             = "|=",
	.Tilde_Eq            = "~=",
	.Lt_Lt_Eq            = "<<=",
	.Gt_Gt_Eq            = ">>=",
	.Semi                = ";",
	.Newline             = "\n",
	.Colon               = ":",
	.Comma               = ",",
	.Dot                 = ".",
	.Dot_Dot             = "..",
	.Paren_Open          = "(",
	.Paren_Close         = ")",
	.Brace_Open          = "{",
	.Brace_Close         = "}",
	.Bracket_Open        = "[",
	.Bracket_Close       = "]",
	// Keywords
	.Keyword_Nil         = "nil",
	.Keyword_True        = "true",
	.Keyword_False       = "false",
	.Keyword_Or          = "or",
	.Keyword_And         = "and",
	.Keyword_If          = "if",
	.Keyword_Else        = "else",
	.Keyword_While       = "while",
	.Keyword_For         = "for",
	.Keyword_Break       = "break",
	.Keyword_Continue    = "continue",
	.Keyword_Fn          = "fn",
	.Keyword_Return      = "return",
	.Keyword_Class       = "class",
	.Keyword_Constructor = "constructor",
	.Keyword_Echo        = "echo",
}

token_names := [Token_Tag]string {
	// Special states
	.Invalid             = "an invalid token",
	.EOF                 = "end of input",
	// Symbols
	.Eq                  = "'='",
	.Eq_Eq               = "'=='",
	.Bang                = "'!'",
	.Bang_Eq             = "'!='",
	.Lt                  = "'<'",
	.Lt_Eq               = "'<='",
	.Gt                  = "'>'",
	.Gt_Eq               = "'>='",
	.Plus                = "'+'",
	.Minus               = "'-'",
	.Star                = "'*'",
	.Slash               = "'/'",
	.Percent             = "'%'",
	.Percent_Percent     = "'%%'",
	.Caret               = "'^'",
	.Amp                 = "'&'",
	.Pipe                = "'|'",
	.Tilde               = "'~'",
	.Lt_Lt               = "'<<'",
	.Gt_Gt               = "'>>'",
	.Plus_Eq             = "'+='",
	.Minus_Eq            = "'-='",
	.Star_Eq             = "'*='",
	.Slash_Eq            = "'/='",
	.Percent_Eq          = "'%='",
	.Percent_Percent_Eq  = "'%%='",
	.Caret_Eq            = "'^='",
	.Amp_Eq              = "'&='",
	.Pipe_Eq             = "'|='",
	.Tilde_Eq            = "'~='",
	.Lt_Lt_Eq            = "'<<='",
	.Gt_Gt_Eq            = "'>>='",
	.Semi                = "';'",
	.Newline             = "a newline",
	.Colon               = "':'",
	.Comma               = "','",
	.Dot                 = "'.'",
	.Dot_Dot             = "'..'",
	.Paren_Open          = "'('",
	.Paren_Close         = "')'",
	.Brace_Open          = "'{'",
	.Brace_Close         = "'}'",
	.Bracket_Open        = "'['",
	.Bracket_Close       = "']'",
	// Keywords
	.Keyword_Nil         = "'nil'",
	.Keyword_True        = "'true'",
	.Keyword_False       = "'false'",
	.Keyword_Or          = "'or'",
	.Keyword_And         = "'and'",
	.Keyword_If          = "'if'",
	.Keyword_Else        = "'else'",
	.Keyword_While       = "'while'",
	.Keyword_For         = "'for'",
	.Keyword_Break       = "'break'",
	.Keyword_Continue    = "'continue'",
	.Keyword_Fn          = "'fn'",
	.Keyword_Return      = "'return'",
	.Keyword_Class       = "'class'",
	.Keyword_Constructor = "'constructor'",
	.Keyword_Echo        = "'echo'",
	// Dynamic content
	.Number              = "a number",
	.String              = "a string",
	.Identifier          = "an identifier",
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
		case '/':
			if t.offset + 1 >= len(t.source) || t.source[t.offset + 1] != '/' {
				break skip_whitespace
			}
			for t.offset < len(t.source) && t.source[t.offset] != '\n' do t.offset += 1
		case:
			break skip_whitespace
		}
	}

	token.tag = .Invalid
	token.start = u32(t.offset)

	if t.offset >= len(t.source) {
		token.tag = .EOF
		return
	}

	c := t.source[t.offset]
	t.offset += 1

	switch c {
	case '=':
		token.tag = .Eq_Eq if match(t, '=') else .Eq
	case '!':
		token.tag = .Bang_Eq if match(t, '=') else .Bang
	case '<':
		if match(t, '<') {
			token.tag = .Lt_Lt_Eq if match(t, '=') else .Lt_Lt
		} else {
			token.tag = .Lt_Eq if match(t, '=') else .Lt
		}
	case '>':
		if match(t, '>') {
			token.tag = .Gt_Gt_Eq if match(t, '=') else .Gt_Gt
		} else {
			token.tag = .Gt_Eq if match(t, '=') else .Gt
		}
	case '+':
		token.tag = .Plus_Eq if match(t, '=') else .Plus
	case '-':
		token.tag = .Minus_Eq if match(t, '=') else .Minus
	case '*':
		token.tag = .Star_Eq if match(t, '=') else .Star
	case '/':
		token.tag = .Slash_Eq if match(t, '=') else .Slash
	case '%':
		if match(t, '%') {
			token.tag = .Percent_Percent_Eq if match(t, '=') else .Percent_Percent
		} else {
			token.tag = .Percent_Eq if match(t, '=') else .Percent
		}
	case '^':
		token.tag = .Caret_Eq if match(t, '=') else .Caret
	case '&':
		token.tag = .Amp_Eq if match(t, '=') else .Amp
	case '|':
		token.tag = .Pipe_Eq if match(t, '=') else .Pipe
	case '~':
		token.tag = .Tilde_Eq if match(t, '=') else .Tilde
	case ';':
		token.tag = .Semi
	case ':':
		token.tag = .Colon
	case ',':
		token.tag = .Comma
	case '.':
		token.tag = .Dot_Dot if match(t, '.') else .Dot
	case '(':
		token.tag = .Paren_Open
	case ')':
		token.tag = .Paren_Close
	case '{':
		token.tag = .Brace_Open
	case '}':
		token.tag = .Brace_Close
	case '[':
		token.tag = .Bracket_Open
	case ']':
		token.tag = .Bracket_Close
	case '\n':
		token.tag = .Newline

	// The compiler checks the number's text, so this only finds where it ends.
	case '0' ..= '9':
		token.tag = .Number
		prefixed := c == '0' && is_alpha(peek(t)) && peek(t) != 'e' && peek(t) != 'E'
		skip_word(t)
		if !prefixed {
			// a fraction needs a digit after the '.', so `1..2` and `1.foo` aren't fractions
			if peek(t) == '.' && is_numeric(peek_next(t)) {
				t.offset += 1
				skip_word(t)
			}
			// the exponent's sign, as in `1e-5` (the 'e' was part of the word)
			last := t.source[t.offset - 1]
			if (last == 'e' || last == 'E') && (peek(t) == '+' || peek(t) == '-') {
				t.offset += 1
				skip_word(t)
			}
		}

	case '"':
		token.tag = .String
		for peek(t) != '"' {
			if peek(t) == 0 || peek(t) == '\n' {
				token.tag = .Invalid
				break
			}
			// skip the escaped character, which may be a '"'
			if peek(t) == '\\' && peek_next(t) != 0 && peek_next(t) != '\n' do t.offset += 1
			t.offset += 1
		}
		if token.tag == .String do t.offset += 1

	case 'a' ..= 'z', 'A' ..= 'Z', '_':
		token.tag = .Identifier

		for is_alphanumeric(peek(t)) || peek(t) == '_' {
			t.offset += 1
		}

		switch t.source[token.start:t.offset] {
		case "nil":
			token.tag = .Keyword_Nil
		case "true":
			token.tag = .Keyword_True
		case "false":
			token.tag = .Keyword_False
		case "or":
			token.tag = .Keyword_Or
		case "and":
			token.tag = .Keyword_And
		case "if":
			token.tag = .Keyword_If
		case "else":
			token.tag = .Keyword_Else
		case "while":
			token.tag = .Keyword_While
		case "for":
			token.tag = .Keyword_For
		case "break":
			token.tag = .Keyword_Break
		case "continue":
			token.tag = .Keyword_Continue
		case "fn":
			token.tag = .Keyword_Fn
		case "return":
			token.tag = .Keyword_Return
		case "class":
			token.tag = .Keyword_Class
		case "constructor":
			token.tag = .Keyword_Constructor
		case "echo":
			token.tag = .Keyword_Echo
		}

	// non-ASCII characters outside of strings are invalid
	case 0x80 ..= 0xFF:
		for peek(t) & 0xC0 == 0x80 {
			t.offset += 1
		}
	}

	#partial switch token.tag {
	case .Paren_Close,
	     .Brace_Close,
	     .Bracket_Close,
	     // ending the line lets the parser recover after an invalid token, like an unterminated string
	     .Invalid,
	     .Number,
	     .String,
	     .Identifier,
	     .Keyword_Nil,
	     .Keyword_True,
	     .Keyword_False,
	     .Keyword_Break,
	     .Keyword_Continue,
	     .Keyword_Return:
		t.insert_semicolon = true
	case:
		t.insert_semicolon = false
	}

	return
}

peek :: proc(t: ^Tokenizer) -> u8 {
	return t.source[t.offset] if t.offset < len(t.source) else 0
}

peek_next :: proc(t: ^Tokenizer) -> u8 {
	return t.source[t.offset + 1] if t.offset + 1 < len(t.source) else 0
}

// Skips letters, digits, and underscores.
skip_word :: proc(t: ^Tokenizer) {
	for is_alphanumeric(peek(t)) || peek(t) == '_' do t.offset += 1
}

// Consumes the next character if it's `c`.
match :: proc(t: ^Tokenizer, c: u8) -> bool {
	if peek(t) != c do return false
	t.offset += 1
	return true
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
