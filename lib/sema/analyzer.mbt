///|
/// Semantic analyzer
struct Analyzer {
  symtab : Symtab
  structs : Array[(String, @ast.Type)] // struct/union registry: tag name -> Type
}

///|
pub fn Analyzer::new() -> Analyzer {
  { symtab: Symtab::new(), structs: [], }
}

///|
/// Analyze a translation unit end-to-end
pub fn analyze(tu : @ast.TranslationUnit) -> Analyzer {
  let a = Analyzer::new()
  a.collect_globals(tu)
  a.analyze_bodies(tu)
  a
}

///|
fn Analyzer::collect_globals(
  self : Analyzer,
  tu : @ast.TranslationUnit,
) -> Unit {
  for decl in tu.decls {
    self.collect_one_global(decl)
  }
}

///|
fn Analyzer::collect_one_global(self : Analyzer, tl : @ast.TopLevel) -> Unit {
  match tl {
    @ast.TopLevel::Function(decl) =>
      match decl {
        @ast.Decl::FuncDef(ret, name, _params, _body) =>
          self.add_func(name, ret)
        @ast.Decl::FuncDecl(ret, name, _params) => self.add_func(name, ret)
        _ => ()
      }
    @ast.TopLevel::Decl(decl) =>
      match decl {
        @ast.Decl::VarDecl(st, typ, name, _init) =>
          self.symtab.add({
            name,
            kind: SymbolKind::Var,
            typ,
            offset: -1,
            storage: st,
            value: 0,
          })
        @ast.Decl::EnumDef(_, enumerators) =>
          for en in enumerators {
            self.symtab.add({
              name: en.name,
              kind: SymbolKind::EnumConst,
              typ: @ast.int_type(@ast.signed_signed()),
              offset: -1,
              storage: @ast.sc_none(),
              value: en.value,
            })
          }
        @ast.Decl::StructDef(tag, fields) => {
          let styp = @ast.struct_type(tag, fields)
          self.structs.push((tag, styp))
        }
        _ => ()
      }
  }
}

///|
fn Analyzer::add_func(self : Analyzer, name : String, ret : @ast.Type) -> Unit {
  self.symtab.add({
    name,
    kind: SymbolKind::Func,
    typ: ret,
    offset: -1,
    storage: @ast.sc_none(),
    value: 0,
  })
}

///|
fn Analyzer::analyze_bodies(self : Analyzer, tu : @ast.TranslationUnit) -> Unit {
  for decl in tu.decls {
    match decl {
      @ast.TopLevel::Function(fn_decl) => self.analyze_function(fn_decl)
      _ => ()
    }
  }
}

///|
fn Analyzer::analyze_function(self : Analyzer, decl : @ast.Decl) -> Unit {
  match decl {
    @ast.Decl::FuncDef(_rt, _name, params, body) => {
      self.symtab.push_scope()

      let mut offset = 0
      let mut pi = 0
      while pi < params.length() {
        self.symtab.add({
          name: params[pi].name,
          kind: SymbolKind::Param,
          typ: params[pi].typ,
          offset,
          storage: @ast.sc_none(),
          value: 0,
        })
        pi = pi + 1
        offset = offset + 8
      }

      self.assign_local_offsets(body, offset) |> ignore

      // NOTE: we do NOT pop the scope so codegen can find symbols.
      // This means scopes accumulate; lookup searches innermost first.
      // For C89, each function's params are unique to that function,
      // and global symbols are function names, not variables.
    }
    _ => ()
  }
}

///|
fn Analyzer::assign_local_offsets(
  self : Analyzer,
  stmt : @ast.Stmt,
  offset : Int32,
) -> Int32 {
  match stmt {
    @ast.Compound(stmts) => {
      let mut cur_off = offset
      for s in stmts {
        cur_off = self.assign_local_offsets(s, cur_off)
      }
      cur_off
    }
    @ast.ExprStmt(_) => offset
    @ast.DeclStmt(decl) =>
      match decl {
        @ast.Decl::VarDecl(st, typ, name, _init) => {
          let size = self.type_size_of(typ)
          // Align to 8 bytes
          let aligned = (size + 7) / 8 * 8
          let new_off = offset + aligned
          self.symtab.add({
            name,
            kind: SymbolKind::Var,
            typ,
            offset,
            storage: st,
            value: 0,
          })
          new_off
        }
        _ => offset
      }
    @ast.If(_, then_s, else_s) => {
      let mut off = self.assign_local_offsets(then_s, offset)
      match else_s {
        Some(s) => off = self.assign_local_offsets(s, off)
        None => ()
      }
      off
    }
    @ast.While(_, body) => {
      self.assign_local_offsets(body, offset) |> ignore
      offset
    }
    @ast.DoWhile(body, _) => {
      self.assign_local_offsets(body, offset) |> ignore
      offset
    }
    @ast.For(_, _, _, body) => {
      self.assign_local_offsets(body, offset) |> ignore
      offset
    }
    @ast.Return(_) => offset
    @ast.Switch(_, body) => {
      self.assign_local_offsets(body, offset) |> ignore
      offset
    }
    @ast.Case(_, body) => {
      self.assign_local_offsets(body, offset) |> ignore
      offset
    }
    @ast.Default(body) => {
      self.assign_local_offsets(body, offset) |> ignore
      offset
    }
    @ast.Label(_, body) => self.assign_local_offsets(body, offset)
    @ast.Break => offset
    @ast.Continue => offset
    @ast.Goto(_) => offset
  }
}

///|
/// Compute byte size of a type
pub fn type_size(typ : @ast.Type) -> Int32 {
  match typ {
    @ast.Type::Void => 0
    @ast.Type::Char(_) => 1
    @ast.Type::Short(_) => 2
    @ast.Type::Int(_) => 4
    @ast.Type::Long(_) => 8
    @ast.Type::Float => 4
    @ast.Type::Double => 8
    @ast.Type::Pointer(_) => 8
    @ast.Type::Array(elem, count) => type_size(elem) * count
    @ast.Type::Struct(_, fields) => {
      let mut size = 0
      for f in fields {
        size = size + type_size(f.typ)
      }
      size
    }
    @ast.Type::Union(_, fields) => {
      let mut max = 0
      for f in fields {
        let s = type_size(f.typ)
        if s > max {
          max = s
        }
      }
      max
    }
    @ast.Type::Enum(_, _) => 4
    @ast.Type::Typedef(_) => 4
    @ast.Type::Function(_, _) => 8
  }
}

// Accessors

///|
pub fn Analyzer::lookup(self : Analyzer, name : String) -> Symbol? {
  self.symtab.lookup(name)
}

///|
pub fn Analyzer::lookup_struct(self : Analyzer, tag : String) -> @ast.Type? {
  let mut i = 0
  while i < self.structs.length() {
    let (t, sty) = self.structs[i]
    if t == tag {
      return Some(sty)
    }
    i = i + 1
  }
  None
}

///|
pub fn Analyzer::lookup_var_type(self : Analyzer, name : String) -> @ast.Type? {
  match self.symtab.lookup(name) {
    Some(s) => Some(s.typ)
    None => None
  }
}

///|
fn Analyzer::type_size_of(self : Analyzer, typ : @ast.Type) -> Int32 {
  match typ {
    @ast.Type::Struct(tag, fields) =>
      if fields.length() == 0 && tag != "" {
        match self.lookup_struct(tag) {
          Some(full_type) => type_size(full_type)
          None => 0
        }
      } else {
        type_size(typ)
      }
    @ast.Type::Union(tag, fields) =>
      if fields.length() == 0 && tag != "" {
        match self.lookup_struct(tag) {
          Some(full_type) => type_size(full_type)
          None => 0
        }
      } else {
        type_size(typ)
      }
    _ => type_size(typ)
  }
}
