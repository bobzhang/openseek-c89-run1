///| C89 AST type definitions

///|
/// Source location
pub struct Loc {
  file : String
  line : Int
  col : Int
}

///|
/// Token kind (used by lexer, not part of parsed AST)
pub enum TokenKind {
  // Keywords
  Auto
  Break
  Case
  Char
  Const
  Continue
  Default
  Do
  Double
  Else
  Enum
  Extern
  Float
  For
  Goto
  If
  Int
  Long
  Register
  Return
  Short
  Signed
  Sizeof
  Static
  Struct
  Switch
  Typedef
  Union
  Unsigned
  Void
  Volatile
  While

  // Identifiers and literals
  Identifier(String)
  IntegerConst(String) // raw text, e.g. "42", "0xFF"
  FloatConst(String) // raw text
  CharConst(String) // raw text including quotes, e.g. "'a'"
  StringLiteral(String) // raw text including quotes

  // Operators
  Plus // +
  Minus // -
  Star // *
  Slash // /
  Percent // %
  Amp // &
  Pipe // |
  Caret // ^
  Tilde // ~
  Bang // !
  Lt // <
  Gt // >
  Le // <=
  Ge // >=
  Eq // ==
  Ne // !=
  AndAnd // &&
  OrOr // ||
  LtLt // <<
  GtGt // >>
  PlusPlus // ++
  MinusMinus // --
  Arrow // ->
  Dot // .
  Question // ?
  Colon // :
  Semicolon // ;
  Comma // ,
  LParen // (
  RParen // )
  LBracket // [
  RBracket // ]
  LBrace // {
  RBrace // }
  Assign // =
  PlusAssign // +=
  MinusAssign // -=
  StarAssign // *=
  SlashAssign // /=
  PercentAssign // %=
  AmpAssign // &=
  PipeAssign // |=
  CaretAssign // ^=
  LtLtAssign // <<=
  GtGtAssign // >>=
  Ellipsis // ...

  // Special
  Eof
  Invalid(String)
}

///|
/// Convert TokenKind to an integer ID for comparison
pub fn kind_id(kind : TokenKind) -> Int {
  match kind {
    Eof => 0
    Auto => 1
    Break => 2
    Case => 3
    Char => 4
    Const => 5
    Continue => 6
    Default => 7
    Do => 8
    Double => 9
    Else => 10
    Enum => 11
    Extern => 12
    Float => 13
    For => 14
    Goto => 15
    If => 16
    Int => 17
    Long => 18
    Register => 19
    Return => 20
    Short => 21
    Signed => 22
    Sizeof => 23
    Static => 24
    Struct => 25
    Switch => 26
    Typedef => 27
    Union => 28
    Unsigned => 29
    Void => 30
    Volatile => 31
    While => 32
    Identifier(_) => 33
    IntegerConst(_) => 34
    FloatConst(_) => 35
    CharConst(_) => 36
    StringLiteral(_) => 37
    Plus => 38
    Minus => 39
    Star => 40
    Slash => 41
    Percent => 42
    Amp => 43
    Pipe => 44
    Caret => 45
    Tilde => 46
    Bang => 47
    Lt => 48
    Gt => 49
    Le => 50
    Ge => 51
    Eq => 52
    Ne => 53
    AndAnd => 54
    OrOr => 55
    LtLt => 56
    GtGt => 57
    PlusPlus => 58
    MinusMinus => 59
    Arrow => 60
    Dot => 61
    Question => 62
    Colon => 63
    Semicolon => 64
    Comma => 65
    LParen => 66
    RParen => 67
    LBracket => 68
    RBracket => 69
    LBrace => 70
    RBrace => 71
    Assign => 72
    PlusAssign => 73
    MinusAssign => 74
    StarAssign => 75
    SlashAssign => 76
    PercentAssign => 77
    AmpAssign => 78
    PipeAssign => 79
    CaretAssign => 80
    LtLtAssign => 81
    GtGtAssign => 82
    Ellipsis => 83
    Invalid(_) => 84
  }
}

///|
/// Check if two TokenKind values are equal
pub fn same_kind(a : TokenKind, b : TokenKind) -> Bool {
  kind_id(a) == kind_id(b)
}

///|
/// A token with location
pub struct Token {
  kind : TokenKind
  loc : Loc
}

///|
/// Signedness for integer types
pub enum Signed {
  Signed
  Unsigned
  Unspecified // for plain "char"
}

///|
/// A struct/union field
pub struct Field {
  name : String
  typ : Type
  bit_width : Int // -1 if not a bitfield
}

///|
/// An enumerator
pub struct Enumerator {
  name : String
  value : Int
}

///|
/// C type representation
pub enum Type {
  // Basic types
  Void
  Char(Signed)
  Short(Signed)
  Int(Signed)
  Long(Signed)
  Float
  Double
  // Pointer
  Pointer(Type)
  // Array
  Array(Type, Int) // element type, size (-1 if unspecified)
  // Function type
  Function(Type, Array[Type]) // return type, parameter types
  // Struct/Union
  Struct(String, Array[Field]) // tag name (empty if anonymous), fields
  Union(String, Array[Field])
  // Enum
  Enum(String, Array[Enumerator]) // tag name, enumerators
  // Typedef alias
  Typedef(String) // name to resolve
}

///|
/// Type constructors (for cross-package use)
pub fn void_type() -> Type {
  Void
}

///|
pub fn char_type(s : Signed) -> Type {
  Char(s)
}

///|
pub fn short_type(s : Signed) -> Type {
  Short(s)
}

///|
pub fn int_type(s : Signed) -> Type {
  Int(s)
}

///|
pub fn long_type(s : Signed) -> Type {
  Long(s)
}

///|
pub fn float_type() -> Type {
  Float
}

///|
pub fn double_type() -> Type {
  Double
}

///|
pub fn pointer_type(t : Type) -> Type {
  Pointer(t)
}

///|
pub fn array_type(t : Type, size : Int) -> Type {
  Array(t, size)
}

///|
pub fn function_type(ret : Type, params : Array[Type]) -> Type {
  Function(ret, params)
}

///|
pub fn struct_type(tag : String, fields : Array[Field]) -> Type {
  Struct(tag, fields)
}

///|
pub fn union_type(tag : String, fields : Array[Field]) -> Type {
  Union(tag, fields)
}

///|
pub fn enum_type(tag : String, enums : Array[Enumerator]) -> Type {
  Enum(tag, enums)
}

///|
pub fn typedef_type(name : String) -> Type {
  Typedef(name)
}

///|
/// Storage class constructors
pub fn sc_none() -> StorageClass {
  None
}

///|
pub fn sc_auto() -> StorageClass {
  Auto
}

///|
pub fn sc_register() -> StorageClass {
  Register
}

///|
pub fn sc_static() -> StorageClass {
  Static
}

///|
pub fn sc_extern() -> StorageClass {
  Extern
}

///|
pub fn sc_typedef() -> StorageClass {
  Typedef
}

///|
/// Signed constructors
pub fn signed_signed() -> Signed {
  Signed
}

///|
pub fn signed_unsigned() -> Signed {
  Unsigned
}

///|
pub fn signed_unspecified() -> Signed {
  Unspecified
}

///|
/// Field constructor
pub fn make_field(name : String, typ : Type, bit_width : Int) -> Field {
  { name, typ, bit_width }
}

///|
/// Enumerator constructor
pub fn make_enumerator(name : String, value : Int) -> Enumerator {
  { name, value }
}

///|
/// Param constructor
pub fn make_param(name : String, typ : Type) -> Param {
  { name, typ }
}

///|
/// Storage class
pub enum StorageClass {
  None
  Auto
  Register
  Static
  Extern
  Typedef
}

///|
/// Expression
pub enum Expr {
  // Literals
  IntLiteral(Int)
  FloatLiteral(Double) // single-precision float constant (has 'f' suffix)
  DoubleLiteral(Double) // double-precision constant (no 'f' suffix)
  CharLiteral(Int) // character value as integer
  StringLiteral(String) // the string content (without quotes, with escapes resolved)

  // Identifier
  Identifier(String)

  // Unary operators
  PrefixInc(Expr) // ++e
  PrefixDec(Expr) // --e
  PostfixInc(Expr) // e++
  PostfixDec(Expr) // e--
  UnaryPlus(Expr)
  UnaryMinus(Expr)
  LogicalNot(Expr) // !e
  BitwiseNot(Expr) // ~e
  Deref(Expr) // *e
  AddressOf(Expr) // &e
  SizeofExpr(Expr)
  SizeofType(Type)

  // Binary operators
  Add(Expr, Expr)
  Sub(Expr, Expr)
  Mul(Expr, Expr)
  Div(Expr, Expr)
  Mod(Expr, Expr)
  BitAnd(Expr, Expr)
  BitOr(Expr, Expr)
  BitXor(Expr, Expr)
  Shl(Expr, Expr)
  Shr(Expr, Expr)
  LogicalAnd(Expr, Expr)
  LogicalOr(Expr, Expr)
  Eq(Expr, Expr)
  Ne(Expr, Expr)
  Lt(Expr, Expr)
  Gt(Expr, Expr)
  Le(Expr, Expr)
  Ge(Expr, Expr)

  // Assignment
  Assign(Expr, Expr)
  AddAssign(Expr, Expr)
  SubAssign(Expr, Expr)
  MulAssign(Expr, Expr)
  DivAssign(Expr, Expr)
  ModAssign(Expr, Expr)
  AndAssign(Expr, Expr)
  OrAssign(Expr, Expr)
  XorAssign(Expr, Expr)
  ShlAssign(Expr, Expr)
  ShrAssign(Expr, Expr)

  // Member access
  Dot(Expr, String) // e.name
  Arrow(Expr, String) // e->name
  Subscript(Expr, Expr) // e[i]

  // Function call
  Call(Expr, Array[Expr])

  // Ternary
  Conditional(Expr, Expr, Expr)

  // Comma
  Comma(Expr, Expr)

  // Cast
  Cast(Type, Expr)
}

///|
/// Statement
pub enum Stmt {
  // Expression statement
  ExprStmt(Expr?)
  // Compound statement (block)
  Compound(Array[Stmt])
  // If/else
  If(Expr, Stmt, Stmt?) // condition, then, else (optional)
  // Switch
  Switch(Expr, Stmt) // expression, body (compound containing cases)
  // Case
  Case(Expr, Stmt) // label value, statement
  // Default
  Default(Stmt)
  // While
  While(Expr, Stmt)
  // Do-while
  DoWhile(Stmt, Expr)
  // For
  For(Expr?, Expr?, Expr?, Stmt) // init, cond, post, body
  // Goto
  Goto(String)
  // Label
  Label(String, Stmt)
  // Break
  Break
  // Continue
  Continue
  // Return
  Return(Expr?)
  // Declaration statement (block-level var decl)
  DeclStmt(Decl)
}

///|
/// Function parameter
pub struct Param {
  name : String // empty if unnamed
  typ : Type
}

///|
/// Declaration
pub enum Decl {
  // Variable declaration
  VarDecl(StorageClass, Type, String, Init?) // storage, type, name, initializer
  // Function definition
  FuncDef(Type, String, Array[Param], Stmt) // return type, name, params, body
  // Function declaration (prototype)
  FuncDecl(Type, String, Array[Param]) // return type, name, params
  // Struct definition
  StructDef(String, Array[Field])
  // Enum definition
  EnumDef(String, Array[Enumerator])
}

///|
/// Initializer
pub enum Init {
  Single(Expr)
  Aggregate(Array[InitItem])
}

///|
/// Initializer item (for struct/array)
pub enum InitItem {
  Designated(String?, Expr) // optional designator, value
}

///|
/// Translation unit (top-level)
pub enum TopLevel {
  Decl(Decl)
  Function(Decl) // function definition
}

///|
/// Full translation unit
pub struct TranslationUnit {
  decls : Array[TopLevel]
}

///|
/// Create a Token
pub fn make_token(kind : TokenKind, loc : Loc) -> Token {
  { kind, loc }
}

///|
/// Create a new translation unit
pub fn new_translation_unit() -> TranslationUnit {
  { decls: [] }
}

///|
/// Create a location
pub fn loc(file : String, line : Int, col : Int) -> Loc {
  { file, line, col }
}

///|
/// Default (unknown) location
pub fn unknown_loc() -> Loc {
  { file: "<unknown>", line: 0, col: 0 }
}

///| C89 Compiler - Language Coverage Checklist

///|

///| Each area lists test files that exercise it (under tests/valid/ and tests/invalid/).

///|

///| OPERATORS

///|   Arithmetic:   004_add, 005_sub, 006_mul, 007_div, 008_mod, 088_auto, 108_auto, 109_auto

///|   Comparison:   009_eq, 010_ne, 011_lt..016_ge, 038_precedence_cmp

///|   Logical:      017_and..020_or_false, 024_not..030_bitnot, 084_auto..087_auto

///|   Bitwise:      021_bitand..023_bitxor, 028_shl, 029_shr, 094_auto..096_auto

///|   Assignment:   048_var, 052_var_if..057_square, 067_while2

///|   Precedence:   036_precedence_mult, 037_precedence_paren

///|   Ternary:      not yet tested (codegen limited)

///|

///| STATEMENTS

///|   if/else:      031_if_true..035_if_block, 052_var_if..055_ifelse2

///|   while:        043_while, 044_while_loop, 067_while2

///|   do-while:     046_dowhile

///|   for:          045_for

///|   goto/labels:  not yet tested

///|   return:       001_return42, 002_return0, 003_return99

///|

///| TYPES

///|   int:          all arithmetic tests

///|   char:         not yet tested

///|   short/long:   not yet tested

///|   unsigned:     not yet tested

///|   float/double: not yet tested

///|   pointers:     not yet tested

///|   arrays:       not yet tested

///|   struct/union: not yet tested

///|   enum:         not yet tested

///|   typedef:      not yet tested

///|   void:         all tests use void parameter

///|

///| DECLARATIONS

///|   variables:    048_var, 049_var_add, 052_var_if, 053_var_ifnot

///|   functions:    all valid tests use function definitions

///|   extern:       not yet tested

///|   static:       not yet tested

///|

///| CONSTANTS

///|   integer:      040_hex, 041_octal, 042_hex2, 110_auto..112_auto

///|   character:    not yet tested

///|   float:        not yet tested

///|   string:       not yet tested

///|

///| PREPROCESSOR

///|   #define:      tested via preprocessor unit

///|   #undef:       tested via preprocessor unit

///|   #ifdef/#endif: tested via preprocessor unit

///|   #include:     not yet integrated

///|

///| ERROR REJECTION (tests/invalid/)

///|   001: goto without label

///|   002: random symbols

///|   003: unknown type

///|   004: empty file

///|   005: stray operator

///|   006: random text

///|   007: only preprocessor dirs

///|   008: undefined function

///|   009: goto nonexistent

///|   010: float func (type mismatch)

///|   011: no function

///|   012: struct without semicolon

///|
/// NOTE: This is an honest partial implementation. Many C89 features are
/// parsed but not yet code-generated. The test suite focuses on what
/// actually works end-to-end (compile, assemble, link, execute).
