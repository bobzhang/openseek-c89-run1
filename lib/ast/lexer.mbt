///| C89 Lexer

///|
/// Lexer state
struct Lexer {
  source : String
  mut pos : Int
  mut line : Int
  mut col : Int
  file : String
  mut token_start_line : Int
  mut token_start_col : Int
}

///|
/// Create a new lexer
pub fn new_lexer(source : String, file : String) -> Lexer {
  {
    source,
    pos: 0,
    line: 1,
    col: 1,
    file,
    token_start_line: 1,
    token_start_col: 1,
  }
}

///|
/// Current character (nul if EOF)
fn Lexer::current(self : Lexer) -> Char {
  match self.source.get_char(self.pos) {
    Some(c) => c
    None => '\u0000'
  }
}

///|
/// Peek ahead n characters
fn Lexer::peek(self : Lexer, n : Int) -> Char {
  let idx = self.pos + n
  match self.source.get_char(idx) {
    Some(c) => c
    None => '\u0000'
  }
}

///|
/// Advance one character
fn Lexer::advance(self : Lexer) -> Char {
  let ch = self.current()
  if ch == '\u0000' {
    return ch
  }
  self.pos = self.pos + 1
  if ch == '\n' {
    self.line = self.line + 1
    self.col = 1
  } else {
    self.col = self.col + 1
  }
  ch
}

///|
/// Skip whitespace and comments
fn Lexer::skip_whitespace(self : Lexer) -> Unit {
  while true {
    let ch = self.current()
    match ch {
      ' ' | '\t' | '\r' | '\n' => self.advance() |> ignore
      '/' =>
        if self.peek(1) == '/' {
          // Single-line comment
          self.advance() |> ignore // skip first '/'
          self.advance() |> ignore // skip second '/'
          while self.current() != '\n' && self.current() != '\u0000' {
            self.advance() |> ignore
          }
        } else if self.peek(1) == '*' {
          // Multi-line comment
          self.advance() |> ignore // skip '/'
          self.advance() |> ignore // skip '*'
          while true {
            if self.current() == '\u0000' {
              break
            }
            if self.current() == '*' && self.peek(1) == '/' {
              self.advance() |> ignore // skip '*'
              self.advance() |> ignore // skip '/'
              break
            }
            self.advance() |> ignore
          }
        } else {
          break
        }
      _ => break
    }
  }
}

///|
/// Mark start of current token
fn Lexer::mark_token_start(self : Lexer) -> Unit {
  self.token_start_line = self.line
  self.token_start_col = self.col
}

///|
/// Create a token at the marked position
fn Lexer::make_token(self : Lexer, kind : TokenKind) -> Token {
  make_token(kind, loc(self.file, self.token_start_line, self.token_start_col))
}

///|
/// Read an identifier or keyword
fn Lexer::read_identifier(self : Lexer) -> Token {
  let start = self.pos - 1 // we already advanced past first char
  while true {
    let ch = self.current()
    match ch {
      'a'..='z' | 'A'..='Z' | '0'..='9' | '_' => self.advance() |> ignore
      _ => break
    }
  }
  let text = self.source[start:self.pos].to_owned()
  // Check keywords
  match text {
    "auto" => self.make_token(Auto)
    "break" => self.make_token(Break)
    "case" => self.make_token(Case)
    "char" => self.make_token(Char)
    "const" => self.make_token(Const)
    "continue" => self.make_token(Continue)
    "default" => self.make_token(Default)
    "do" => self.make_token(Do)
    "double" => self.make_token(Double)
    "else" => self.make_token(Else)
    "enum" => self.make_token(Enum)
    "extern" => self.make_token(Extern)
    "float" => self.make_token(Float)
    "for" => self.make_token(For)
    "goto" => self.make_token(Goto)
    "if" => self.make_token(If)
    "int" => self.make_token(Int)
    "long" => self.make_token(Long)
    "register" => self.make_token(Register)
    "return" => self.make_token(Return)
    "short" => self.make_token(Short)
    "signed" => self.make_token(Signed)
    "sizeof" => self.make_token(Sizeof)
    "static" => self.make_token(Static)
    "struct" => self.make_token(Struct)
    "switch" => self.make_token(Switch)
    "typedef" => self.make_token(Typedef)
    "union" => self.make_token(Union)
    "unsigned" => self.make_token(Unsigned)
    "void" => self.make_token(Void)
    "volatile" => self.make_token(Volatile)
    "while" => self.make_token(While)
    _ => self.make_token(Identifier(text))
  }
}

///|
/// Read a number literal (integer or float)
fn Lexer::read_number(self : Lexer) -> Token {
  let start = self.pos - 1 // already advanced past first digit
  let mut is_float = false

  // Check for hex prefix
  if self.source[start] == '0' &&
    (self.current() == 'x' || self.current() == 'X') {
    self.advance() |> ignore // skip 'x'
    // Read hex digits
    while true {
      let ch = self.current()
      match ch {
        '0'..='9' | 'a'..='f' | 'A'..='F' => self.advance() |> ignore
        _ => break
      }
    }
    // Read suffix
    while true {
      let ch = self.current()
      match ch {
        'l' | 'L' | 'u' | 'U' => self.advance() |> ignore
        _ => break
      }
    }
    return self.make_token(IntegerConst(self.source[start:self.pos].to_owned()))
  }

  // Read integer part
  while true {
    let ch = self.current()
    match ch {
      '0'..='9' => self.advance() |> ignore
      _ => break
    }
  }

  // Check for float
  if self.current() == '.' {
    is_float = true
    self.advance() |> ignore // skip '.'
    // Read fractional part
    while true {
      let ch = self.current()
      match ch {
        '0'..='9' => self.advance() |> ignore
        _ => break
      }
    }
  }

  // Check for exponent
  if self.current() == 'e' || self.current() == 'E' {
    is_float = true
    self.advance() |> ignore // skip 'e'
    if self.current() == '+' || self.current() == '-' {
      self.advance() |> ignore
    }
    while true {
      let ch = self.current()
      match ch {
        '0'..='9' => self.advance() |> ignore
        _ => break
      }
    }
  }

  // Read float suffix
  if is_float {
    let ch = self.current()
    if ch == 'f' || ch == 'F' || ch == 'l' || ch == 'L' {
      self.advance() |> ignore
    }
    return self.make_token(FloatConst(self.source[start:self.pos].to_owned()))
  }

  // Read integer suffix
  while true {
    let ch = self.current()
    match ch {
      'l' | 'L' | 'u' | 'U' => self.advance() |> ignore
      _ => break
    }
  }
  self.make_token(IntegerConst(self.source[start:self.pos].to_owned()))
}

///|
/// Read a character literal
fn Lexer::read_char_literal(self : Lexer) -> Token {
  // We've already consumed the opening '
  let start = self.pos - 1

  // Handle escape sequences
  if self.current() == '\\' {
    self.advance() |> ignore // skip backslash
    self.advance() |> ignore // skip escaped char
  } else if self.current() != '\'' && self.current() != '\u0000' {
    self.advance() |> ignore
  }

  // Consume closing quote if present
  if self.current() == '\'' {
    self.advance() |> ignore
  }

  self.make_token(CharConst(self.source[start:self.pos].to_owned()))
}

///|
/// Read a string literal
fn Lexer::read_string_literal(self : Lexer) -> Token {
  // We've already consumed the opening "
  let start = self.pos - 1

  while true {
    let ch = self.current()
    match ch {
      '\u0000' => break // unterminated string
      '"' => {
        self.advance() |> ignore
        break
      }
      '\\' => {
        self.advance() |> ignore // skip backslash
        if self.current() != '\u0000' {
          self.advance() |> ignore // skip escaped char
        }
      }
      '\n' =>
        // Newline in string - just advance
        self.advance() |> ignore
      _ => self.advance() |> ignore
    }
  }

  self.make_token(StringLiteral(self.source[start:self.pos].to_owned()))
}

///|
/// Read an operator or punctuator
fn Lexer::read_operator(self : Lexer) -> Token {
  let ch = self.current()
  self.advance() |> ignore

  match ch {
    '+' =>
      if self.current() == '+' {
        self.advance() |> ignore
        self.make_token(PlusPlus)
      } else if self.current() == '=' {
        self.advance() |> ignore
        self.make_token(PlusAssign)
      } else {
        self.make_token(Plus)
      }
    '-' =>
      if self.current() == '-' {
        self.advance() |> ignore
        self.make_token(MinusMinus)
      } else if self.current() == '=' {
        self.advance() |> ignore
        self.make_token(MinusAssign)
      } else if self.current() == '>' {
        self.advance() |> ignore
        self.make_token(Arrow)
      } else {
        self.make_token(Minus)
      }
    '*' =>
      if self.current() == '=' {
        self.advance() |> ignore
        self.make_token(StarAssign)
      } else {
        self.make_token(Star)
      }
    '/' =>
      if self.current() == '=' {
        self.advance() |> ignore
        self.make_token(SlashAssign)
      } else {
        self.make_token(Slash)
      }
    '%' =>
      if self.current() == '=' {
        self.advance() |> ignore
        self.make_token(PercentAssign)
      } else {
        self.make_token(Percent)
      }
    '&' =>
      if self.current() == '&' {
        self.advance() |> ignore
        self.make_token(AndAnd)
      } else if self.current() == '=' {
        self.advance() |> ignore
        self.make_token(AmpAssign)
      } else {
        self.make_token(Amp)
      }
    '|' =>
      if self.current() == '|' {
        self.advance() |> ignore
        self.make_token(OrOr)
      } else if self.current() == '=' {
        self.advance() |> ignore
        self.make_token(PipeAssign)
      } else {
        self.make_token(Pipe)
      }
    '^' =>
      if self.current() == '=' {
        self.advance() |> ignore
        self.make_token(CaretAssign)
      } else {
        self.make_token(Caret)
      }
    '~' => self.make_token(Tilde)
    '!' =>
      if self.current() == '=' {
        self.advance() |> ignore
        self.make_token(Ne)
      } else {
        self.make_token(Bang)
      }
    '=' =>
      if self.current() == '=' {
        self.advance() |> ignore
        self.make_token(Eq)
      } else {
        self.make_token(Assign)
      }
    '<' =>
      if self.current() == '<' {
        self.advance() |> ignore
        if self.current() == '=' {
          self.advance() |> ignore
          self.make_token(LtLtAssign)
        } else {
          self.make_token(LtLt)
        }
      } else if self.current() == '=' {
        self.advance() |> ignore
        self.make_token(Le)
      } else {
        self.make_token(Lt)
      }
    '>' =>
      if self.current() == '>' {
        self.advance() |> ignore
        if self.current() == '=' {
          self.advance() |> ignore
          self.make_token(GtGtAssign)
        } else {
          self.make_token(GtGt)
        }
      } else if self.current() == '=' {
        self.advance() |> ignore
        self.make_token(Ge)
      } else {
        self.make_token(Gt)
      }
    '.' =>
      if self.current() == '.' && self.peek(0) == '.' {
        self.advance() |> ignore
        self.advance() |> ignore
        self.make_token(Ellipsis)
      } else {
        self.make_token(Dot)
      }
    '?' => self.make_token(Question)
    ':' => self.make_token(Colon)
    ';' => self.make_token(Semicolon)
    ',' => self.make_token(Comma)
    '(' => self.make_token(LParen)
    ')' => self.make_token(RParen)
    '[' => self.make_token(LBracket)
    ']' => self.make_token(RBracket)
    '{' => self.make_token(LBrace)
    '}' => self.make_token(RBrace)
    _ => self.make_token(Invalid("unexpected character"))
  }
}

///|
/// Get the next token
pub fn Lexer::next_token(self : Lexer) -> Token {
  self.skip_whitespace()
  self.mark_token_start()

  if self.pos >= self.source.length() {
    return self.make_token(Eof)
  }

  let ch = self.current()

  if ch == '\u0000' {
    return self.make_token(Eof)
  }

  // Identifier or keyword
  if (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || ch == '_' {
    self.advance() |> ignore
    return self.read_identifier()
  }

  // Number
  if ch >= '0' && ch <= '9' {
    self.advance() |> ignore
    return self.read_number()
  }

  // Character literal
  if ch == '\'' {
    self.advance() |> ignore
    return self.read_char_literal()
  }

  // String literal
  if ch == '"' {
    self.advance() |> ignore
    return self.read_string_literal()
  }

  // Operators and punctuators
  self.read_operator()
}

///|
/// Collect all tokens (for debugging/testing)
pub fn tokenize(source : String, file : String) -> Array[Token] {
  let lex = new_lexer(source, file)
  let tokens : Array[Token] = []
  while true {
    let t = lex.next_token()
    match t.kind {
      Eof => {
        tokens.push(t)
        break
      }
      _ => tokens.push(t)
    }
  }
  tokens
}
