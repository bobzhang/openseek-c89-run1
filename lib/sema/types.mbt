///|
/// Symbol table and semantic analysis - core types
pub enum SymbolKind {
  Var
  Func
  Param
  EnumConst
}

///|
pub struct Symbol {
  name : String
  kind : SymbolKind
  typ : @ast.Type
  offset : Int32
  storage : @ast.StorageClass
  value : Int32 // constant value for enum constants
}

///|
/// Base scope type - one level of name resolution
struct Scope {
  symbols : Array[Symbol]
}

///|
pub fn Scope::new() -> Scope {
  { symbols: [], }
}

///|
fn Scope::add(self : Scope, sym : Symbol) -> Unit {
  self.symbols.push(sym)
}

///|
fn Scope::lookup(self : Scope, name : String) -> Symbol? {
  for s in self.symbols {
    if s.name == name {
      return Some(s)
    }
  }
  None
}

///|
/// Symbol table - stack of scopes
struct Symtab {
  scopes : Array[Scope]
}

///|
pub fn Symtab::new() -> Symtab {
  { scopes: [Scope::new()], }
}

///|
pub fn Symtab::push_scope(self : Symtab) -> Unit {
  self.scopes.push(Scope::new())
}

///|
pub fn Symtab::pop_scope(self : Symtab) -> Unit {
  match self.scopes {
    [_, ..] => self.scopes.pop() |> ignore
    _ => ()
  }
}

///|
pub fn Symtab::add(self : Symtab, sym : Symbol) -> Unit {
  let len = self.scopes.length()
  self.scopes[len - 1].add(sym)
}

///|
pub fn Symtab::lookup(self : Symtab, name : String) -> Symbol? {
  let mut i = self.scopes.length()
  while i > 0 {
    i = i - 1
    match self.scopes[i].lookup(name) {
      Some(s) => return Some(s)
      None => ()
    }
  }
  None
}

///|
pub fn Symtab::current_scope(self : Symtab) -> Scope? {
  let len = self.scopes.length()
  if len == 0 {
    return None
  }
  Some(self.scopes[len - 1])
}
