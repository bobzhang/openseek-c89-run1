///|
/// C89 Parser
struct Parser {
  lex : Lexer
  mut current : Token
  mut peek : Token
}

///|
pub fn Parser::new(source : String, file : String) -> Parser {
  let lex = new_lexer(source, file)
  let cur = lex.next_token()
  let p = lex.next_token()
  { lex, current: cur, peek: p, }
}

///|
fn Parser::advance(self : Parser) -> Unit {
  self.current = self.peek
  self.peek = self.lex.next_token()
}

///|
fn Parser::check(self : Parser, kind : TokenKind) -> Bool {
  kind_id(self.current.kind) == kind_id(kind)
}

///|
fn Parser::expect(self : Parser, kind : TokenKind) -> Unit {
  if self.check(kind) {
    self.advance()
  } else {
    self.advance()
  }
}

///|
fn Parser::match_token(self : Parser, kind : TokenKind) -> Bool {
  if self.check(kind) {
    self.advance()
    true
  } else {
    false
  }
}

///|
fn Parser::is_type_specifier(self : Parser) -> Bool {
  let k = self.kind_id_cur()
  k == kind_id(Void) ||
  k == kind_id(Char) ||
  k == kind_id(Short) ||
  k == kind_id(Int) ||
  k == kind_id(Long) ||
  k == kind_id(Float) ||
  k == kind_id(Double) ||
  k == kind_id(Signed) ||
  k == kind_id(Unsigned) ||
  k == kind_id(Struct) ||
  k == kind_id(Union) ||
  k == kind_id(Enum)
}

///|
fn Parser::is_type_qualifier(self : Parser) -> Bool {
  let k = self.kind_id_cur()
  k == kind_id(Const) || k == kind_id(Volatile)
}

///|
fn Parser::is_storage_class(self : Parser) -> Bool {
  let k = self.kind_id_cur()
  k == kind_id(Auto) ||
  k == kind_id(Register) ||
  k == kind_id(Static) ||
  k == kind_id(Extern) ||
  k == kind_id(Typedef)
}

///|
fn Parser::token_text(self : Parser) -> String {
  match self.current.kind {
    TokenKind::Identifier(s) => s
    IntegerConst(s) => s
    FloatConst(s) => s
    CharConst(s) => s
    StringLiteral(s) => s
    _ => ""
  }
}

///|
fn Parser::kind_id_cur(self : Parser) -> Int32 {
  kind_id(self.current.kind)
}

// =============================================================================
// Entry point
// =============================================================================

///|
pub fn parse_translation_unit(
  source : String,
  file : String,
) -> TranslationUnit {
  let parser = Parser::new(source, file)
  let decls : Array[TopLevel] = []
  while !parser.check(Eof) {
    match parser.parse_external_declaration() {
      Some(d) => decls.push(d)
      None => parser.advance()
    }
  }
  { decls, }
}

// =============================================================================
// External declarations
// =============================================================================

///|
fn Parser::parse_external_declaration(self : Parser) -> TopLevel? {
  if self.match_token(Semicolon) {
    return None
  }

  let sc = self.parse_storage_class()

  // struct/union/enum definitions
  let k = self.kind_id_cur()
  if k == kind_id(Struct) {
    match self.parse_struct_or_union() {
      Some(decl) => return Some(TopLevel::Decl(decl))
      None => return None
    }
  }
  if k == kind_id(Enum) {
    match self.parse_enum_specifier() {
      Some(decl) => return Some(TopLevel::Decl(decl))
      None => return None
    }
  }
  if k == kind_id(Union) {
    match self.parse_struct_or_union() {
      Some(decl) => return Some(TopLevel::Decl(decl))
      None => return None
    }
  }

  // Typedef
  match sc {
    Typedef => {
      self.parse_typedef_declaration()
      self.expect(Semicolon)
      return None
    }
    _ => ()
  }

  let basetype = self.parse_type_specifiers()
  if self.check(Semicolon) {
    self.advance()
    return None
  }

  self.parse_declarator_or_func(basetype, sc)
}

///|
fn Parser::parse_storage_class(self : Parser) -> StorageClass {
  match self.current.kind {
    Typedef => {
      self.advance()
      Typedef
    }
    Extern => {
      self.advance()
      Extern
    }
    Static => {
      self.advance()
      Static
    }
    Auto => {
      self.advance()
      Auto
    }
    Register => {
      self.advance()
      Register
    }
    _ => None
  }
}

// =============================================================================
// Type parsing
// =============================================================================

///|
fn Parser::parse_type_specifiers(self : Parser) -> Type {
  let mut signed = Unspecified
  let mut kind = 0
  while self.is_storage_class() {
    self.advance()
  }
  while self.is_type_qualifier() {
    self.advance()
  }

  while self.is_type_specifier() || self.is_type_qualifier() {
    while self.is_type_qualifier() {
      self.advance()
    }
    if !self.is_type_specifier() {
      break
    }
    match self.current.kind {
      Void => {
        self.advance()
        kind = 1
      }
      Char => {
        self.advance()
        kind = kind | 2
      }
      Short => {
        self.advance()
        kind = kind | 4
      }
      Int => {
        self.advance()
        kind = kind | 8
      }
      Long => {
        self.advance()
        kind = kind | 16
      }
      Float => {
        self.advance()
        kind = kind | 32
      }
      Double => {
        self.advance()
        kind = kind | 64
      }
      Signed => {
        self.advance()
        signed = Signed
      }
      Unsigned => {
        self.advance()
        signed = Unsigned
      }
      Struct => return self.parse_struct_or_union_type()
      Union => return self.parse_struct_or_union_type()
      Enum => return self.parse_enum_type()
      TokenKind::Identifier(_) => {
        let name = self.token_text()
        self.advance()
        return Type::Typedef(name)
      }
      _ => self.advance()
    }
  }

  if (kind & 64) != 0 {
    return Type::Double
  }
  if (kind & 32) != 0 {
    return Type::Float
  }
  if (kind & 16) != 0 {
    match signed {
      Unspecified => signed = Signed
      _ => ()
    }
    return Type::Long(signed)
  }
  if (kind & 8) != 0 {
    match signed {
      Unspecified => signed = Signed
      _ => ()
    }
    return Type::Int(signed)
  }
  if (kind & 4) != 0 {
    match signed {
      Unspecified => signed = Signed
      _ => ()
    }
    return Type::Short(signed)
  }
  if (kind & 2) != 0 {
    return Type::Char(signed)
  }
  if (kind & 1) != 0 {
    return Type::Void
  }
  match signed {
    Unspecified => ()
    _ => return Type::Int(signed)
  }
  Type::Int(Signed)
}
// =============================================================================
// Struct/Union/Enum parsing
// =============================================================================

///|
fn Parser::parse_struct_or_union(self : Parser) -> Decl? {
  self.advance() // skip struct/union keyword
  let tag = if self.check(TokenKind::Identifier("")) {
    self.token_text()
  } else {
    ""
  }
  if tag != "" {
    self.advance()
  }
  if !self.check(LBrace) {
    return None
  }
  self.advance()

  let fields : Array[Field] = []
  while !self.check(RBrace) && !self.check(Eof) {
    let ftype = self.parse_type_specifiers()
    while !self.check(Semicolon) && !self.check(Eof) {
      let fname = self.token_text()
      self.advance()
      let mut bit_width = -1
      if self.match_token(Colon) {
        bit_width = self.parse_constant_int()
      }
      fields.push({ name: fname, typ: ftype, bit_width, })
      if !self.match_token(Comma) {
        break
      }
    }
    self.expect(Semicolon)
  }
  self.expect(RBrace)
  Some(Decl::StructDef(tag, fields))
}

///|
fn Parser::parse_enum_specifier(self : Parser) -> Decl? {
  self.expect(Enum)
  let tag = if self.check(TokenKind::Identifier("")) {
    self.token_text()
  } else {
    ""
  }
  if tag != "" {
    self.advance()
  }
  if !self.check(LBrace) {
    return None
  }
  self.advance()

  let enumerators : Array[Enumerator] = []
  let mut value = 0
  while !self.check(RBrace) && !self.check(Eof) {
    let ename = self.token_text()
    self.advance()
    if self.match_token(Assign) {
      value = self.parse_constant_int()
    }
    enumerators.push({ name: ename, value, })
    value = value + 1
    if !self.match_token(Comma) {
      break
    }
  }
  self.expect(RBrace)
  Some(Decl::EnumDef(tag, enumerators))
}

///|
fn Parser::parse_struct_or_union_type(self : Parser) -> Type {
  let is_union = self.match_token(Union)
  if !is_union {
    self.expect(Struct)
  }

  let tag = if self.check(TokenKind::Identifier("")) {
    self.token_text()
  } else {
    ""
  }
  if tag != "" {
    self.advance()
  }

  if self.check(LBrace) {
    self.advance()
    let fields : Array[Field] = []
    while !self.check(RBrace) && !self.check(Eof) {
      let ftype = self.parse_type_specifiers()
      while !self.check(Semicolon) && !self.check(Eof) {
        let fname = self.token_text()
        self.advance()
        let mut bit_width = -1
        if self.match_token(Colon) {
          bit_width = self.parse_constant_int()
        }
        fields.push({ name: fname, typ: ftype, bit_width, })
        if !self.match_token(Comma) {
          break
        }
      }
      self.expect(Semicolon)
    }
    self.expect(RBrace)
    return if is_union {
      Type::Union(tag, fields)
    } else {
      Type::Struct(tag, fields)
    }
  }
  if is_union {
    Type::Union(tag, [])
  } else {
    Type::Struct(tag, [])
  }
}

///|
fn Parser::parse_enum_type(self : Parser) -> Type {
  self.expect(Enum)
  let tag = if self.check(TokenKind::Identifier("")) {
    self.token_text()
  } else {
    ""
  }
  if tag != "" {
    self.advance()
  }

  if self.check(LBrace) {
    self.advance()
    let enumerators : Array[Enumerator] = []
    let mut value = 0
    while !self.check(RBrace) && !self.check(Eof) {
      let ename = self.token_text()
      self.advance()
      if self.match_token(Assign) {
        value = self.parse_constant_int()
      }
      enumerators.push({ name: ename, value, })
      value = value + 1
      if !self.match_token(Comma) {
        break
      }
    }
    self.expect(RBrace)
    return Type::Enum(tag, enumerators)
  }
  Type::Enum(tag, [])
}

///|
fn Parser::parse_typedef_declaration(self : Parser) -> Unit {
  self.parse_type_specifiers() |> ignore
  while !self.check(Semicolon) && !self.check(Eof) {
    self.advance()
  }
}

// =============================================================================
// Declarator
// =============================================================================

///|
fn Parser::parse_declarator_or_func(
  self : Parser,
  basetype : Type,
  sc : StorageClass,
) -> TopLevel? {
  let mut ptr_depth = 0
  while self.match_token(Star) {
    ptr_depth = ptr_depth + 1
    while self.is_type_qualifier() {
      self.advance()
    }
  }

  let name = self.parse_direct_declarator_name()

  let mut final_type = basetype
  let mut i = 0
  while i < ptr_depth {
    final_type = Type::Pointer(final_type)
    i = i + 1
  }

  if self.check(LParen) {
    let params = self.parse_parameter_list()
    if self.check(LBrace) {
      let body = self.parse_compound_statement()
      return Some(
        TopLevel::Function(Decl::FuncDef(basetype, name, params, body)),
      )
    }
    // Check if this is a function pointer variable with initializer
    if self.check(Assign) {
      let init = self.parse_initializer()
      // Wrap type: pointer → function(params) → rettype
      let num_p = params.length()
      let param_types : Array[Type] = if num_p == 0 {
        []
      } else {
        let arr : Array[Type] = []
        let mut pi = 0
        while pi < num_p {
          pi = pi + 1
        }
        arr
      }
      let mut func_type = Type::Function(basetype, param_types)
      for _pi2 = 0; _pi2 < ptr_depth; _pi2 = _pi2 + 1 {
        func_type = Type::Pointer(func_type)
      }
      self.expect(Semicolon)
      return Some(TopLevel::Decl(Decl::VarDecl(sc, func_type, name, init)))
    }
    self.expect(Semicolon)
    return Some(TopLevel::Decl(Decl::FuncDecl(basetype, name, params)))
  }

  let init = self.parse_initializer()
  self.expect(Semicolon)
  Some(TopLevel::Decl(Decl::VarDecl(sc, final_type, name, init)))
}

///|
fn Parser::parse_direct_declarator_name(self : Parser) -> String {
  if self.check(LParen) {
    self.advance()
    // Skip any pointer stars inside the parens: (*fp) has a star
    // Note: the caller already counted these stars for ptr_depth
    while self.match_token(Star) {

    }
    let name = self.parse_direct_declarator_name()
    self.expect(RParen)
    return name
  }
  let name = self.token_text()
  self.advance()
  // Skip array dimensions but NOT function parameters
  while self.check(LBracket) {
    if self.match_token(LBracket) {
      if !self.check(RBracket) {
        self.parse_expression() |> ignore
      }
      self.expect(RBracket)
    }
  }
  name
}

// =============================================================================
// Parameters
// =============================================================================

///|
fn Parser::parse_parameter_list(self : Parser) -> Array[Param] {
  self.expect(LParen)
  let params : Array[Param] = []

  if self.check(Void) {
    self.advance()
    if self.check(RParen) {
      self.advance()
      return params
    }
    params.push({ name: "void", typ: Type::Int(Unspecified), })
    if !self.match_token(Comma) {
      self.expect(RParen)
      return params
    }
  }

  while !self.check(RParen) && !self.check(Eof) {
    if self.match_token(Ellipsis) {
      break
    }
    let ptype = self.parse_type_specifiers()

    let mut ptr_depth = 0
    while self.match_token(Star) {
      ptr_depth = ptr_depth + 1
      while self.is_type_qualifier() {
        self.advance()
      }
    }

    let mut final_type = ptype
    let mut i = 0
    while i < ptr_depth {
      final_type = Type::Pointer(final_type)
      i = i + 1
    }

    let pname = if self.check(TokenKind::Identifier("")) {
      let n = self.token_text()
      self.advance()
      n
    } else {
      ""
    }

    if self.match_token(LBracket) {
      if !self.check(RBracket) {
        self.parse_expression() |> ignore
      }
      self.expect(RBracket)
    }

    params.push({ name: pname, typ: final_type, })
    if !self.match_token(Comma) {
      break
    }
  }

  self.expect(RParen)
  params
}

// =============================================================================
// Initializer
// =============================================================================

///|
fn Parser::parse_initializer(self : Parser) -> Init? {
  if !self.match_token(Assign) {
    return None
  }
  if self.check(LBrace) {
    self.advance()
    let items : Array[InitItem] = []
    while !self.check(RBrace) && !self.check(Eof) {
      let expr = self.parse_assignment_expression()
      items.push(InitItem::Designated(None, expr))
      if !self.match_token(Comma) {
        break
      }
    }
    self.expect(RBrace)
    return Some(Init::Aggregate(items))
  }
  let expr = self.parse_assignment_expression()
  Some(Init::Single(expr))
}

// =============================================================================
// Expressions - recursive descent
// =============================================================================

///|
fn Parser::parse_expression(self : Parser) -> Expr {
  self.parse_comma()
}

///|
fn Parser::parse_comma(self : Parser) -> Expr {
  let mut expr = self.parse_assignment()
  while self.match_token(Comma) {
    expr = Expr::Comma(expr, self.parse_assignment())
  }
  expr
}

///|
fn Parser::parse_assignment(self : Parser) -> Expr {
  let expr = self.parse_conditional()
  match self.current.kind {
    Assign => {
      self.advance()
      Expr::Assign(expr, self.parse_assignment())
    }
    PlusAssign => {
      self.advance()
      Expr::AddAssign(expr, self.parse_assignment())
    }
    MinusAssign => {
      self.advance()
      Expr::SubAssign(expr, self.parse_assignment())
    }
    StarAssign => {
      self.advance()
      Expr::MulAssign(expr, self.parse_assignment())
    }
    SlashAssign => {
      self.advance()
      Expr::DivAssign(expr, self.parse_assignment())
    }
    PercentAssign => {
      self.advance()
      Expr::ModAssign(expr, self.parse_assignment())
    }
    AmpAssign => {
      self.advance()
      Expr::AndAssign(expr, self.parse_assignment())
    }
    PipeAssign => {
      self.advance()
      Expr::OrAssign(expr, self.parse_assignment())
    }
    CaretAssign => {
      self.advance()
      Expr::XorAssign(expr, self.parse_assignment())
    }
    LtLtAssign => {
      self.advance()
      Expr::ShlAssign(expr, self.parse_assignment())
    }
    GtGtAssign => {
      self.advance()
      Expr::ShrAssign(expr, self.parse_assignment())
    }
    _ => expr
  }
}

///|
fn Parser::parse_conditional(self : Parser) -> Expr {
  let expr = self.parse_logical_or()
  if self.match_token(Question) {
    let then_expr = self.parse_expression()
    self.expect(Colon)
    let else_expr = self.parse_conditional()
    return Expr::Conditional(expr, then_expr, else_expr)
  }
  expr
}

///|
fn Parser::parse_logical_or(self : Parser) -> Expr {
  let mut expr = self.parse_logical_and()
  while self.match_token(OrOr) {
    expr = Expr::LogicalOr(expr, self.parse_logical_and())
  }
  expr
}

///|
fn Parser::parse_logical_and(self : Parser) -> Expr {
  let mut expr = self.parse_bitwise_or()
  while self.match_token(AndAnd) {
    expr = Expr::LogicalAnd(expr, self.parse_bitwise_or())
  }
  expr
}

///|
fn Parser::parse_bitwise_or(self : Parser) -> Expr {
  let mut expr = self.parse_bitwise_xor()
  while self.match_token(Pipe) {
    expr = Expr::BitOr(expr, self.parse_bitwise_xor())
  }
  expr
}

///|
fn Parser::parse_bitwise_xor(self : Parser) -> Expr {
  let mut expr = self.parse_bitwise_and()
  while self.match_token(Caret) {
    expr = Expr::BitXor(expr, self.parse_bitwise_and())
  }
  expr
}

///|
fn Parser::parse_bitwise_and(self : Parser) -> Expr {
  let mut expr = self.parse_equality()
  while self.match_token(Amp) {
    expr = Expr::BitAnd(expr, self.parse_equality())
  }
  expr
}

///|
fn Parser::parse_equality(self : Parser) -> Expr {
  let mut expr = self.parse_relational()
  while true {
    if self.match_token(Eq) {
      expr = Expr::Eq(expr, self.parse_relational())
    } else if self.match_token(Ne) {
      expr = Expr::Ne(expr, self.parse_relational())
    } else {
      break
    }
  }
  expr
}

///|
fn Parser::parse_relational(self : Parser) -> Expr {
  let mut expr = self.parse_shift()
  while true {
    if self.match_token(Lt) {
      expr = Expr::Lt(expr, self.parse_shift())
    } else if self.match_token(Gt) {
      expr = Expr::Gt(expr, self.parse_shift())
    } else if self.match_token(Le) {
      expr = Expr::Le(expr, self.parse_shift())
    } else if self.match_token(Ge) {
      expr = Expr::Ge(expr, self.parse_shift())
    } else {
      break
    }
  }
  expr
}

///|
fn Parser::parse_shift(self : Parser) -> Expr {
  let mut expr = self.parse_additive()
  while true {
    if self.match_token(LtLt) {
      expr = Expr::Shl(expr, self.parse_additive())
    } else if self.match_token(GtGt) {
      expr = Expr::Shr(expr, self.parse_additive())
    } else {
      break
    }
  }
  expr
}

///|
fn Parser::parse_additive(self : Parser) -> Expr {
  let mut expr = self.parse_multiplicative()
  while true {
    if self.match_token(Plus) {
      expr = Expr::Add(expr, self.parse_multiplicative())
    } else if self.match_token(Minus) {
      expr = Expr::Sub(expr, self.parse_multiplicative())
    } else {
      break
    }
  }
  expr
}

///|
fn Parser::parse_multiplicative(self : Parser) -> Expr {
  let mut expr = self.parse_unary()
  while true {
    if self.match_token(Star) {
      expr = Expr::Mul(expr, self.parse_unary())
    } else if self.match_token(Slash) {
      expr = Expr::Div(expr, self.parse_unary())
    } else if self.match_token(Percent) {
      expr = Expr::Mod(expr, self.parse_unary())
    } else {
      break
    }
  }
  expr
}

///|
fn Parser::parse_unary(self : Parser) -> Expr {
  if self.match_token(PlusPlus) {
    return Expr::PrefixInc(self.parse_unary())
  }
  if self.match_token(MinusMinus) {
    return Expr::PrefixDec(self.parse_unary())
  }
  if self.match_token(Amp) {
    return Expr::AddressOf(self.parse_unary())
  }
  if self.match_token(Star) {
    return Expr::Deref(self.parse_unary())
  }
  if self.match_token(Plus) {
    return Expr::UnaryPlus(self.parse_unary())
  }
  if self.match_token(Minus) {
    return Expr::UnaryMinus(self.parse_unary())
  }
  if self.match_token(Bang) {
    return Expr::LogicalNot(self.parse_unary())
  }
  if self.match_token(Tilde) {
    return Expr::BitwiseNot(self.parse_unary())
  }
  if self.check(Sizeof) {
    self.advance()
    if self.match_token(LParen) && self.is_type_specifier() {
      let typ = self.parse_type_specifiers()
      self.expect(RParen)
      return Expr::SizeofType(typ)
    }
    return Expr::SizeofExpr(self.parse_unary())
  }
  // Cast expression: (type-name) unary-expr
  // Check: current is '(', peek is a type-specifier keyword
  if self.check(LParen) {
    let peek_kind = kind_id(self.peek.kind)
    if peek_kind == kind_id(Void) ||
      peek_kind == kind_id(Char) ||
      peek_kind == kind_id(Short) ||
      peek_kind == kind_id(Int) ||
      peek_kind == kind_id(Long) ||
      peek_kind == kind_id(Float) ||
      peek_kind == kind_id(Double) ||
      peek_kind == kind_id(Signed) ||
      peek_kind == kind_id(Unsigned) ||
      peek_kind == kind_id(Struct) ||
      peek_kind == kind_id(Union) ||
      peek_kind == kind_id(Enum) {
      self.advance() // consume '('
      let mut typ = self.parse_type_specifiers()
      // Parse optional pointer(s) inside cast: (int*)x
      while self.match_token(Star) {
        typ = Type::Pointer(typ)
      }
      self.expect(RParen)
      return Expr::Cast(typ, self.parse_unary())
    }
  }
  self.parse_postfix()
}

///|
fn Parser::parse_postfix(self : Parser) -> Expr {
  let mut expr = self.parse_primary()
  while true {
    if self.match_token(LBracket) {
      let index = self.parse_expression()
      self.expect(RBracket)
      expr = Expr::Subscript(expr, index)
    } else if self.match_token(LParen) {
      let args : Array[Expr] = []
      if !self.check(RParen) {
        while true {
          args.push(self.parse_assignment_expression())
          if !self.match_token(Comma) {
            break
          }
        }
      }
      self.expect(RParen)
      expr = Expr::Call(expr, args)
    } else if self.match_token(Dot) {
      let field_name = self.token_text()
      self.advance()
      expr = Expr::Dot(expr, field_name)
    } else if self.match_token(Arrow) {
      let field_name = self.token_text()
      self.advance()
      expr = Expr::Arrow(expr, field_name)
    } else if self.match_token(PlusPlus) {
      expr = Expr::PostfixInc(expr)
    } else if self.match_token(MinusMinus) {
      expr = Expr::PostfixDec(expr)
    } else {
      break
    }
  }
  expr
}

///|
fn Parser::parse_primary(self : Parser) -> Expr {
  let text = self.token_text()
  match self.current.kind {
    TokenKind::Identifier(_) => {
      self.advance()
      Expr::Identifier(text)
    }
    IntegerConst(_) => {
      self.advance()
      Expr::IntLiteral(parse_int_literal(text))
    }
    FloatConst(_) => {
      let val = parse_float_literal(text)
      // Check if original text has 'f' or 'F' suffix → FloatLiteral
      let raw = text
      let has_f_suffix = raw[raw.length() - 1] == 'f' ||
        raw[raw.length() - 1] == 'F'
      self.advance()
      if has_f_suffix {
        Expr::FloatLiteral(val)
      } else {
        Expr::DoubleLiteral(val)
      }
    }
    CharConst(_) => {
      self.advance()
      Expr::CharLiteral(parse_char_literal(text))
    }
    StringLiteral(_) => {
      self.advance()
      Expr::StringLiteral(raw_string_content(text))
    }
    LParen => {
      self.advance()
      let expr = self.parse_expression()
      self.expect(RParen)
      expr
    }
    _ => {
      self.advance()
      Expr::IntLiteral(0)
    }
  }
}

///|
fn Parser::parse_assignment_expression(self : Parser) -> Expr {
  self.parse_assignment()
}

// =============================================================================
// Constant
// =============================================================================

///|
fn Parser::parse_constant_int(self : Parser) -> Int32 {
  match self.parse_conditional() {
    IntLiteral(n) => n
    _ => 0
  }
}

// =============================================================================
// Statements
// =============================================================================

///|
fn Parser::parse_compound_statement(self : Parser) -> Stmt {
  self.expect(LBrace)
  let stmts : Array[Stmt] = []
  while !self.check(RBrace) && !self.check(Eof) {
    if self.is_type_specifier() || self.is_storage_class() {
      // Capture storage class before parsing type specifiers
      let st = if self.check(TokenKind::Identifier("")) {
        None
      } else if self.match_token(Static) {
        StorageClass::Static
      } else {
        None
      }
      let basetype = self.parse_type_specifiers()
      if self.check(Semicolon) {
        self.advance()
        continue
      }
      // Parse declarator(s)
      while !self.check(Semicolon) && !self.check(Eof) {
        let mut ptr_depth = 0
        while self.match_token(Star) {
          ptr_depth = ptr_depth + 1
          while self.is_type_qualifier() {
            self.advance()
          }
        }
        let name = self.parse_direct_declarator_name()
        // Check for array brackets or function parameters
        if self.check(LBracket) {
          while self.check(LBracket) {
            self.advance()
            if !self.check(RBracket) {
              self.parse_expression() |> ignore
            }
            self.expect(RBracket)
          }
        }
        if self.check(LParen) {
          // Function pointer: consume parameter list
          self.advance()
          while !self.check(RParen) && !self.check(Eof) {
            self.parse_type_specifiers() |> ignore
            // skip param name
            if self.check(TokenKind::Identifier("")) {
              self.advance()
            }
            if !self.match_token(Comma) {
              break
            }
          }
          self.expect(RParen)
        }
        // Apply pointer wrapping
        let mut final_type = basetype
        let mut pi = 0
        while pi < ptr_depth {
          final_type = Type::Pointer(final_type)
          pi = pi + 1
        }
        let init = self.parse_initializer()
        // Emit as DeclStmt
        stmts.push(Stmt::DeclStmt(Decl::VarDecl(st, final_type, name, init)))
        if !self.match_token(Comma) {
          break
        }
      }
      self.expect(Semicolon)
    } else {
      stmts.push(self.parse_statement())
    }
  }
  self.expect(RBrace)
  Stmt::Compound(stmts)
}

///|
fn Parser::parse_statement(self : Parser) -> Stmt {
  let k = self.kind_id_cur()
  if k == kind_id(LBrace) {
    return self.parse_compound_statement()
  }
  if k == kind_id(If) {
    return self.parse_if_statement()
  }
  if k == kind_id(Switch) {
    return self.parse_switch_statement()
  }
  if k == kind_id(While) {
    return self.parse_while_statement()
  }
  if k == kind_id(Do) {
    return self.parse_do_while_statement()
  }
  if k == kind_id(For) {
    return self.parse_for_statement()
  }
  if k == kind_id(Goto) {
    return self.parse_goto_statement()
  }
  if k == kind_id(Continue) {
    return self.parse_continue_statement()
  }
  if k == kind_id(Break) {
    return self.parse_break_statement()
  }
  if k == kind_id(Return) {
    return self.parse_return_statement()
  }
  if k == kind_id(Case) {
    return self.parse_case_statement()
  }
  if k == kind_id(Default) {
    return self.parse_default_statement()
  }
  if k == kind_id(TokenKind::Identifier("")) {
    if kind_id(self.peek.kind) == kind_id(Colon) {
      let label_text = self.token_text()
      self.advance()
      self.advance()
      return Stmt::Label(label_text, self.parse_statement())
    }
    return self.parse_expression_statement()
  }
  self.parse_expression_statement()
}

///|
fn Parser::parse_if_statement(self : Parser) -> Stmt {
  self.expect(If)
  self.expect(LParen)
  let cond = self.parse_expression()
  self.expect(RParen)
  let then_stmt = self.parse_statement()
  let mut else_stmt : Stmt? = None
  if self.match_token(Else) {
    else_stmt = Some(self.parse_statement())
  }
  Stmt::If(cond, then_stmt, else_stmt)
}

///|
fn Parser::parse_switch_statement(self : Parser) -> Stmt {
  self.expect(Switch)
  self.expect(LParen)
  let expr = self.parse_expression()
  self.expect(RParen)
  Stmt::Switch(expr, self.parse_statement())
}

///|
fn Parser::parse_while_statement(self : Parser) -> Stmt {
  self.expect(While)
  self.expect(LParen)
  let cond = self.parse_expression()
  self.expect(RParen)
  Stmt::While(cond, self.parse_statement())
}

///|
fn Parser::parse_do_while_statement(self : Parser) -> Stmt {
  self.expect(Do)
  let body = self.parse_statement()
  self.expect(While)
  self.expect(LParen)
  let cond = self.parse_expression()
  self.expect(RParen)
  self.expect(Semicolon)
  Stmt::DoWhile(body, cond)
}

///|
fn Parser::parse_for_statement(self : Parser) -> Stmt {
  self.expect(For)
  self.expect(LParen)
  let init : Expr? = if !self.check(Semicolon) {
    Some(self.parse_expression())
  } else {
    None
  }
  self.expect(Semicolon)
  let cond : Expr? = if !self.check(Semicolon) {
    Some(self.parse_expression())
  } else {
    None
  }
  self.expect(Semicolon)
  let post : Expr? = if !self.check(RParen) {
    Some(self.parse_expression())
  } else {
    None
  }
  self.expect(RParen)
  Stmt::For(init, cond, post, self.parse_statement())
}

///|
fn Parser::parse_goto_statement(self : Parser) -> Stmt {
  self.expect(Goto)
  let label = self.token_text()
  self.advance()
  self.expect(Semicolon)
  Stmt::Goto(label)
}

///|
fn Parser::parse_continue_statement(self : Parser) -> Stmt {
  self.expect(Continue)
  self.expect(Semicolon)
  Stmt::Continue
}

///|
fn Parser::parse_break_statement(self : Parser) -> Stmt {
  self.expect(Break)
  self.expect(Semicolon)
  Stmt::Break
}

///|
fn Parser::parse_return_statement(self : Parser) -> Stmt {
  self.expect(Return)
  let expr : Expr? = if !self.check(Semicolon) {
    Some(self.parse_expression())
  } else {
    None
  }
  self.expect(Semicolon)
  Stmt::Return(expr)
}

///|
fn Parser::parse_case_statement(self : Parser) -> Stmt {
  self.expect(Case)
  let expr = self.parse_conditional()
  self.expect(Colon)
  Stmt::Case(expr, self.parse_statement())
}

///|
fn Parser::parse_default_statement(self : Parser) -> Stmt {
  self.expect(Default)
  self.expect(Colon)
  Stmt::Default(self.parse_statement())
}

///|
fn Parser::parse_expression_statement(self : Parser) -> Stmt {
  if self.match_token(Semicolon) {
    return Stmt::ExprStmt(None)
  }
  let expr = self.parse_expression()
  self.expect(Semicolon)
  Stmt::ExprStmt(Some(expr))
}
// =============================================================================
// Literal parsing utilities
// =============================================================================

///|
fn parse_int_literal(s : String) -> Int32 {
  let text = trim_suffixes(s)
  if text.has_prefix("0x") || text.has_prefix("0X") {
    let hex = text[2:].to_owned()
    let mut n : Int32 = 0
    for ch in hex {
      let d = match ch {
        '0'..<='9' => ch.to_int() - '0'.to_int()
        'a'..<='f' => ch.to_int() - 'a'.to_int() + 10
        'A'..<='F' => ch.to_int() - 'A'.to_int() + 10
        _ => 0
      }
      n = n * 16 + d
    }
    return n
  }
  if text.has_prefix("0") && text.length() > 1 {
    let oct = text[1:].to_owned()
    let mut n : Int32 = 0
    for ch in oct {
      n = n * 8 + (ch.to_int() - '0'.to_int())
    }
    return n
  }
  let n : Int32 = @string.from_str(text) catch { _ => 0 }
  n
}

///|
fn parse_float_literal(s : String) -> Double {
  let sv = s
    .trim_end(chars="f")
    .trim_end(chars="F")
    .trim_end(chars="l")
    .trim_end(chars="L")
  let f : Double = @string.from_str(sv) catch { _ => 0.0 }
  f
}

///|
fn parse_char_literal(s : String) -> Int32 {
  let inner = s[1:s.length() - 1]
  if inner.has_prefix("\\") {
    parse_escape_seq(inner.to_owned())
  } else {
    match s.get_char(1) {
      Some(c) => c.to_int()
      None => 0
    }
  }
}

///|
fn parse_escape_seq(s : String) -> Int32 {
  match s {
    "\\n" => '\n'.to_int()
    "\\t" => '\t'.to_int()
    "\\r" => '\r'.to_int()
    "\\0" => 0
    "\\\\" => '\\'.to_int()
    "\\'" => '\''.to_int()
    "\\\"" => '"'.to_int()
    _ =>
      if s.length() >= 2 && s[1] == 'x' {
        parse_int_literal("0x" + s[2:].to_owned())
      } else if s.length() >= 2 {
        match s.get_char(1) {
          Some(c) => c.to_int()
          None => 0
        }
      } else {
        0
      }
  }
}

///|
fn trim_suffixes(s : String) -> String {
  let mut text = s
  while text != "" &&
        (
          text[text.length() - 1] == 'u' ||
          text[text.length() - 1] == 'U' ||
          text[text.length() - 1] == 'l' ||
          text[text.length() - 1] == 'L'
        ) {
    text = text[:text.length() - 1].to_owned()
  }
  text
}

///|
/// Strip quotes from string literal, keep escape sequences
fn raw_string_content(s : String) -> String {
  // s has quotes, e.g. "hello\nworld"
  // Return hello\nworld (with literal backslash-n, not newline)
  if s.length() < 2 {
    return ""
  }
  s[1:s.length() - 1].to_owned()
}
