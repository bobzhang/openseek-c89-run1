///|
/// Arm64 macOS code generator
struct Codegen {
  output : StringBuilder
  mut label_counter : Int
  mut string_labels : Int
  string_literals : Array[(String, String)]
  float_constants : Array[(String, String, Bool)] // label, value_str, is_double
  global_vars : Array[(String, @ast.Type, @ast.Init?, @ast.StorageClass)]
  static_locals : Array[(String, @ast.Type, @ast.Init?)] // mangled_name, type, init
  static_var_labels : Array[(String, String)] // func.local_name → data_label
  analyzer : @sema.Analyzer?
  mut current_func : String
  break_stack : Array[String]
  continue_stack : Array[String]
}

///|
pub fn Codegen::new(analyzer : @sema.Analyzer?) -> Codegen {
  {
    output: StringBuilder::new(),
    label_counter: 0,
    string_labels: 0,
    string_literals: [],
    float_constants: [],
    global_vars: [],
    static_locals: [],
    static_var_labels: [],
    analyzer,
    current_func: "",
    break_stack: [],
    continue_stack: [],
  }
}

///|
pub fn generate(
  tu : @ast.TranslationUnit,
  analyzer : @sema.Analyzer?,
) -> String {
  let cg = Codegen::new(analyzer)

  // First pass: collect global variable declarations
  for decl in tu.decls {
    cg.collect_global(decl)
  }

  cg.emit_line(".section __TEXT,__text,regular,pure_instructions")
  cg.emit_line(".build_version macos, 14, 0")
  cg.emit_line("")

  // Second pass: translate function definitions
  for decl in tu.decls {
    cg.translate_top_level(decl)
  }

  // Emit string literals
  for item in cg.string_literals {
    let (label, content) = item
    cg.emit_line("")
    cg.emit_line(label + ":")
    cg.emit_line(".asciz \"" + content + "\"")
  }

  // Emit global variables in __DATA,__data section
  if cg.global_vars.length() > 0 || cg.float_constants.length() > 0 {
    cg.emit_line("")
    cg.emit_line(".section __DATA,__data")
    cg.emit_line(".p2align 2")
    let mut gi = 0
    while gi < cg.global_vars.length() {
      let (name, typ, init, sc) = cg.global_vars[gi]
      cg.emit_line("")
      // Only export if not static
      match sc {
        @ast.StorageClass::Static => ()
        _ => cg.emit_line(".globl _" + name)
      }
      cg.emit_line("_" + name + ":")
      match init {
        Some(@ast.Init::Single(@ast.IntLiteral(n))) =>
          cg.emit_line("  .long " + n.to_string())
        Some(@ast.Init::Single(@ast.CharLiteral(c))) =>
          cg.emit_line("  .long " + c.to_string())
        Some(@ast.Init::Single(@ast.AddressOf(@ast.Identifier(func_name)))) =>
          // Function pointer initializer: emit address of function
          cg.emit_line("  .quad _" + func_name)
        Some(@ast.Init::Single(@ast.Identifier(func_name))) =>
          // Function pointer initializer (implicit &func)
          cg.emit_line("  .quad _" + func_name)
        Some(_) => cg.emit_line("  .long 0")
        None => cg.emit_line("  .space " + @sema.type_size(typ).to_string())
      }
      gi = gi + 1
    }
    // Emit float constants
    let mut fi = 0
    while fi < cg.float_constants.length() {
      let (label, value_str, is_double) = cg.float_constants[fi]
      cg.emit_line("")
      cg.emit_line(label + ":")
      if is_double {
        cg.emit_line("  .double " + value_str)
      } else {
        cg.emit_line("  .float " + value_str)
      }
      fi = fi + 1
    }
  }

  // Emit static function-scope variables
  if cg.static_locals.length() > 0 {
    cg.emit_line("")
    cg.emit_line(".section __DATA,__data")
  }
  let mut sli = 0
  while sli < cg.static_locals.length() {
    let (label, typ, init) = cg.static_locals[sli]
    cg.emit_line("")
    cg.emit_line(label + ":")
    match init {
      Some(@ast.Init::Single(@ast.IntLiteral(n))) =>
        cg.emit_line("  .long " + n.to_string())
      Some(_) => cg.emit_line("  .long 0")
      None => cg.emit_line("  .space " + @sema.type_size(typ).to_string())
    }
    sli = sli + 1
  }

  // Add subsections_via_symbols
  cg.emit_line("")
  cg.emit_line(".subsections_via_symbols")

  StringBuilder::to_string(cg.output)
}

///|
fn Codegen::collect_global(self : Codegen, tl : @ast.TopLevel) -> Unit {
  match tl {
    @ast.Decl(decl) =>
      match decl {
        @ast.Decl::VarDecl(st, typ, name, init) =>
          self.global_vars.push((name, typ, init, st))
        _ => ()
      }
    _ => ()
  }
}

///|
fn Codegen::translate_top_level(self : Codegen, tl : @ast.TopLevel) -> Unit {
  match tl {
    @ast.Function(decl) => self.translate_func_def(decl)
    @ast.Decl(_) => ()
  }
}

///|
fn Codegen::translate_func_def(self : Codegen, decl : @ast.Decl) -> Unit {
  match decl {
    @ast.FuncDef(_rettype, name, params, body) => {
      self.current_func = name
      let frame_size = 144

      self.emit_line("")
      self.emit_line(".globl _" + name)
      self.emit_line(".p2align 2")
      self.emit_line("_" + name + ":")
      self.emit_line("  sub sp, sp, #" + frame_size.to_string())
      self.emit_line(
        "  stp x29, x30, [sp, #" + (frame_size - 16).to_string() + "]",
      )
      self.emit_line("  add x29, sp, #" + (frame_size - 16).to_string())

      // Save params at [x29, #-16], [x29, #-8], etc.
      let num_params = if params.length() > 8 { 8 } else { params.length() }
      let mut pi = 0
      while pi < num_params {
        let off = -(pi * 8 + 32)
        let reg = if is_float_type(params[pi].typ) {
          reg_prefix(params[pi].typ) + pi.to_string()
        } else {
          "x" + pi.to_string()
        }
        self.emit_line("  str " + reg + ", [x29, #" + off.to_string() + "]")
        pi = pi + 1
      }

      self.translate_stmt(body)

      // Epilogue
      self.emit_line("_epilogue_" + name + ":")
      self.emit_line(
        "  ldp x29, x30, [sp, #" + (frame_size - 16).to_string() + "]",
      )
      self.emit_line("  add sp, sp, #" + frame_size.to_string())
      self.emit_line("  ret")
      self.current_func = ""
    }
    _ => ()
  }
}

///|
fn Codegen::translate_stmt(self : Codegen, stmt : @ast.Stmt) -> Unit {
  match stmt {
    @ast.Compound(stmts) =>
      for s in stmts {
        self.translate_stmt(s)
      }
    @ast.Return(Some(expr)) => {
      self.translate_expr(expr)
      self.emit_line("  b _epilogue_" + self.current_func)
    }
    @ast.Return(None) => self.emit_line("  b _epilogue_" + self.current_func)
    @ast.DeclStmt(decl) =>
      match decl {
        @ast.Decl::VarDecl(st, _typ, name, init) =>
          match st {
            @ast.StorageClass::Static => {
              // Function-scope static: emit data section entry
              let label = "_" + self.current_func + "." + name
              let guard_label = label + "_guard"
              self.static_locals.push((label, _typ, init))
              self.static_var_labels.push(
                (self.current_func + "." + name, label),
              )
              // Emit run-once init with guard flag
              match init {
                Some(@ast.Init::Single(expr)) => {
                  let skip_label = self.next_label()
                  // Check guard flag
                  self.emit_line("  adrp x8, " + guard_label + "@PAGE")
                  self.emit_line("  add x8, x8, " + guard_label + "@PAGEOFF")
                  self.emit_line("  ldrb w9, [x8]")
                  self.emit_line("  cmp w9, #1")
                  self.emit_line("  b.eq " + skip_label)
                  // Run init
                  self.translate_expr(expr)
                  self.emit_line("  adrp x8, " + label + "@PAGE")
                  self.emit_line("  add x8, x8, " + label + "@PAGEOFF")
                  self.emit_line("  str x0, [x8]")
                  // Set guard flag
                  self.emit_line("  adrp x9, " + guard_label + "@PAGE")
                  self.emit_line("  add x9, x9, " + guard_label + "@PAGEOFF")
                  self.emit_line("  mov w10, #1")
                  self.emit_line("  strb w10, [x9]")
                  self.emit_line(skip_label + ":")
                }
                Some(_) => ()
                None => ()
              }
              // Track guard for data section
              self.static_locals.push((guard_label, @ast.char_type(@ast.signed_unsigned()), None))
            }
            _ =>
              match init {
                Some(@ast.Init::Single(expr)) => {
                  self.translate_expr(expr)
                  self.store_var(name)
                }
                Some(@ast.Init::Aggregate(items)) => {
                  let mut elem_idx = 0
                  for item in items {
                    match item {
                      @ast.InitItem::Designated(_, expr) => {
                        match self.analyzer {
                          Some(a) =>
                            match a.lookup(name) {
                              Some(sym) => {
                                let off = -(sym.offset + 32)
                                self.emit_line(
                                  "  add x0, x29, #" + off.to_string(),
                                )
                              }
                              None => ()
                            }
                          None => ()
                        }
                        self.emit_line("  mov x9, x0")
                        self.translate_expr(expr)
                        let off = elem_idx * 4
                        if off > 0 {
                          self.emit_line(
                            "  str x0, [x9, #" + off.to_string() + "]",
                          )
                        } else {
                          self.emit_line("  str x0, [x9]")
                        }
                        elem_idx = elem_idx + 1
                      }
                    }
                  }
                }
                _ => ()
              }
          }
        _ => ()
      }
    @ast.ExprStmt(Some(expr)) => self.translate_expr(expr)
    @ast.ExprStmt(None) => ()
    @ast.If(cond, then_stmt, else_opt) => {
      let else_label = self.next_label()
      let end_label = self.next_label()
      self.translate_expr(cond)
      self.emit_line("  cmp x0, #0")
      self.emit_line("  b.eq " + else_label)
      self.translate_stmt(then_stmt)
      self.emit_line("  b " + end_label)
      self.emit_line(else_label + ":")
      match else_opt {
        Some(s) => self.translate_stmt(s)
        None => ()
      }
      self.emit_line(end_label + ":")
    }
    @ast.While(cond, body) => {
      let start_label = self.next_label()
      let end_label = self.next_label()
      self.break_stack.push(end_label)
      self.continue_stack.push(start_label)
      self.emit_line(start_label + ":")
      self.translate_expr(cond)
      self.emit_line("  cmp x0, #0")
      self.emit_line("  b.eq " + end_label)
      self.translate_stmt(body)
      self.emit_line("  b " + start_label)
      self.emit_line(end_label + ":")
      self.break_stack.pop() |> ignore
      self.continue_stack.pop() |> ignore
    }
    @ast.DoWhile(body, cond) => {
      let start_label = self.next_label()
      let end_label = self.next_label()
      self.break_stack.push(end_label)
      self.continue_stack.push(start_label)
      self.emit_line(start_label + ":")
      self.translate_stmt(body)
      self.translate_expr(cond)
      self.emit_line("  cmp x0, #0")
      self.emit_line("  b.ne " + start_label)
      self.emit_line(end_label + ":")
      self.break_stack.pop() |> ignore
      self.continue_stack.pop() |> ignore
    }
    @ast.For(init, cond, post, body) => {
      match init {
        Some(e) => self.translate_expr(e) |> ignore
        None => ()
      }
      let start_label = self.next_label()
      let continue_label = self.next_label() // label before post-increment
      let end_label = self.next_label()
      self.break_stack.push(end_label)
      self.continue_stack.push(continue_label)
      self.emit_line(start_label + ":")
      match cond {
        Some(e) => {
          self.translate_expr(e)
          self.emit_line("  cmp x0, #0")
          self.emit_line("  b.eq " + end_label)
        }
        None => ()
      }
      self.translate_stmt(body)
      self.emit_line(continue_label + ":")
      match post {
        Some(e) => self.translate_expr(e) |> ignore
        None => ()
      }
      self.emit_line("  b " + start_label)
      self.emit_line(end_label + ":")
      self.break_stack.pop() |> ignore
      self.continue_stack.pop() |> ignore
    }
    @ast.Break =>
      match self.break_stack {
        [_, ..] => {
          let label = self.break_stack[self.break_stack.length() - 1]
          self.emit_line("  b " + label)
        }
        _ => self.emit_line("  // break outside loop")
      }
    @ast.Continue =>
      match self.continue_stack {
        [_, ..] => {
          let label = self.continue_stack[self.continue_stack.length() - 1]
          self.emit_line("  b " + label)
        }
        _ => self.emit_line("  // continue outside loop")
      }
    @ast.Label(label, body) => {
      self.emit_line(label + ":")
      self.translate_stmt(body)
    }
    @ast.Goto(label) => self.emit_line("  b " + label)
    @ast.Switch(expr, body) => self.translate_switch(expr, body)
    @ast.Case(_, _) => ()
    @ast.Default(_) => ()
  }
}

///|
fn Codegen::translate_expr(self : Codegen, expr : @ast.Expr) -> Unit {
  match expr {
    @ast.IntLiteral(n) => self.emit_line("  mov x0, #" + n.to_string())
    @ast.CharLiteral(c) => self.emit_line("  mov x0, #" + c.to_string())
    @ast.FloatLiteral(f) => {
      let label = self.add_float_constant(f, false)
      self.emit_line("  adrp x8, " + label + "@PAGE")
      self.emit_line("  add x8, x8, " + label + "@PAGEOFF")
      self.emit_line("  ldr s0, [x8]")
    }
    @ast.DoubleLiteral(d) => {
      let label = self.add_float_constant(d, true)
      self.emit_line("  adrp x8, " + label + "@PAGE")
      self.emit_line("  add x8, x8, " + label + "@PAGEOFF")
      self.emit_line("  ldr d0, [x8]")
    }
    @ast.StringLiteral(s) => {
      let label = self.add_string_literal(s)
      self.emit_line("  adrp x0, " + label + "@PAGE")
      self.emit_line("  add x0, x0, " + label + "@PAGEOFF")
    }
    @ast.Identifier(name) => self.load_var(name)
    @ast.Add(l, r) => {
      let typ = self.expr_type(l)
      if is_float_type(typ) {
        let prefix = reg_prefix(typ)
        self.translate_expr(l)
        self.emit_line("  str " + prefix + "0, [sp, #-16]!")
        self.translate_expr(r)
        self.emit_line("  ldr " + prefix + "1, [sp], #16")
        self.emit_line(
          "  fadd " + prefix + "0, " + prefix + "0, " + prefix + "1",
        )
      } else {
        self.binary(l, r, "add")
      }
    }
    @ast.Sub(l, r) => {
      let typ = self.expr_type(l)
      if is_float_type(typ) {
        let prefix = reg_prefix(typ)
        self.translate_expr(l)
        self.emit_line("  str " + prefix + "0, [sp, #-16]!")
        self.translate_expr(r)
        self.emit_line("  ldr " + prefix + "1, [sp], #16")
        self.emit_line(
          "  fsub " + prefix + "0, " + prefix + "0, " + prefix + "1",
        )
      } else {
        self.binary(l, r, "sub")
      }
    }
    @ast.Mul(l, r) => {
      let typ = self.expr_type(l)
      if is_float_type(typ) {
        let prefix = reg_prefix(typ)
        self.translate_expr(l)
        self.emit_line("  str " + prefix + "0, [sp, #-16]!")
        self.translate_expr(r)
        self.emit_line("  ldr " + prefix + "1, [sp], #16")
        self.emit_line(
          "  fmul " + prefix + "0, " + prefix + "0, " + prefix + "1",
        )
      } else {
        self.binary(l, r, "mul")
      }
    }
    @ast.Div(l, r) => {
      let typ = self.expr_type(l)
      if is_float_type(typ) {
        let prefix = reg_prefix(typ)
        self.translate_expr(l)
        self.emit_line("  str " + prefix + "0, [sp, #-16]!")
        self.translate_expr(r)
        self.emit_line("  ldr " + prefix + "1, [sp], #16")
        self.emit_line(
          "  fdiv " + prefix + "0, " + prefix + "0, " + prefix + "1",
        )
      } else {
        self.binary(l, r, "sdiv")
      }
    }
    @ast.Mod(l, r) => self.mod_div(l, r)
    @ast.BitAnd(l, r) => self.binary(l, r, "and")
    @ast.BitOr(l, r) => self.binary(l, r, "orr")
    @ast.BitXor(l, r) => self.binary(l, r, "eor")
    @ast.Shl(l, r) => self.binary(l, r, "lsl")
    @ast.Shr(l, r) => self.binary(l, r, "asr")
    @ast.Eq(l, r) => self.cmp_op_typed(l, r, "eq")
    @ast.Ne(l, r) => self.cmp_op_typed(l, r, "ne")
    @ast.Lt(l, r) => self.cmp_op_typed(l, r, "lt")
    @ast.Gt(l, r) => self.cmp_op_typed(l, r, "gt")
    @ast.Le(l, r) => self.cmp_op_typed(l, r, "le")
    @ast.Ge(l, r) => self.cmp_op_typed(l, r, "ge")
    @ast.LogicalAnd(l, r) => self.logical_bin(l, r, false)
    @ast.LogicalOr(l, r) => self.logical_bin(l, r, true)
    @ast.LogicalNot(e) => {
      self.translate_expr(e)
      self.emit_line("  cmp x0, #0")
      self.emit_line("  cset x0, eq")
    }
    @ast.UnaryMinus(e) => {
      self.translate_expr(e)
      self.emit_line("  neg x0, x0")
    }
    @ast.UnaryPlus(e) => self.translate_expr(e)
    @ast.BitwiseNot(e) => {
      self.translate_expr(e)
      self.emit_line("  mvn x0, x0")
    }
    @ast.Assign(l, r) => self.translate_assign(l, r, "mov")
    @ast.AddAssign(l, r) => self.translate_assign(l, r, "add")
    @ast.SubAssign(l, r) => self.translate_assign(l, r, "sub")
    @ast.MulAssign(l, r) => self.translate_assign(l, r, "mul")
    @ast.DivAssign(l, r) => self.translate_assign(l, r, "sdiv")
    @ast.ModAssign(l, r) => self.translate_assign_mod(l, r)
    @ast.AndAssign(l, r) => self.translate_assign(l, r, "and")
    @ast.OrAssign(l, r) => self.translate_assign(l, r, "orr")
    @ast.XorAssign(l, r) => self.translate_assign(l, r, "eor")
    @ast.ShlAssign(l, r) => self.translate_assign(l, r, "lsl")
    @ast.ShrAssign(l, r) => self.translate_assign(l, r, "asr")
    @ast.Call(func, args) => {
      let n = if args.length() > 8 { 8 } else { args.length() }
      // Determine if this is an indirect call
      let mut is_indirect = false
      match func {
        @ast.Identifier(name) =>
          match self.analyzer {
            Some(a) =>
              match a.lookup(name) {
                Some(sym) =>
                  // If the symbol is a variable, it's indirect
                  is_indirect = match sym.kind {
                    @sema.SymbolKind::Func => false
                    _ => true
                  }
                None => ()
              }
            None => ()
          }
        _ => is_indirect = true
      }

      if n > 0 {
        // For indirect calls: evaluate func pointer first, save in x16
        if is_indirect {
          self.translate_expr(func)
          self.emit_line("  mov x16, x0") // save function pointer in x16
        }
        if n > 0 {
        // Evaluate args right-to-left, pushing onto stack.
          // Each push decrements sp by 16. Nested calls within arg expressions
          // use their own push/pop, so they don't clobber our pushed values
          // (which are deeper in the stack).
          let mut i = n - 1
          while i >= 0 {
            self.translate_expr(args[i])
            let arg_type = self.expr_type(args[i])
            let prefix = reg_prefix(arg_type)
            self.emit_line("  str " + prefix + "0, [sp, #-16]!")
            i = i - 1
          }
          // Now pop args into registers: arg0 → x0, arg1 → x1, ...
          let mut j = 0
          while j < n {
            let arg_type = self.expr_type(args[j])
            let prefix = reg_prefix(arg_type)
            self.emit_line("  ldr " + prefix + j.to_string() + ", [sp], #16")
            j = j + 1
          }
          // For variadic support: leave args[1..] on the stack at [sp+0], [sp+8], ...
          // (skip arg0 for printf-like functions)
          let mut k = 1
          while k < n {
            let arg_type = self.expr_type(args[k])
            let prefix = reg_prefix(arg_type)
            self.emit_line(
              "  str " +
              prefix +
              k.to_string() +
              ", [sp, #" +
              ((k - 1) * 8).to_string() +
              "]",
            )
            k = k + 1
          }
        }
      }
      if is_indirect {
        // Function pointer stored in x16
        self.emit_line("  blr x16")
      } else {
        match func {
          @ast.Identifier(name) => self.emit_line("  bl _" + name)
          _ => self.emit_line("  // shouldn't happen")
        }
      }
    }
    @ast.Cast(to_type, e) => {
      let src_type = self.expr_type(e)
      // Determine which register the source value is in
      let src_is_float = is_float_type(src_type)
      let dst_is_float = is_float_type(to_type)
      // Evaluate source (puts value in x0 or s0 depending on type)
      self.translate_expr(e)
      if src_is_float && !dst_is_float {
        // float → int: fcvtzs
        let src_reg = reg_prefix(src_type)
        self.emit_line("  fcvtzs w0, " + src_reg + "0")
      } else if !src_is_float && dst_is_float {
        // int → float: scvtf
        let dst_reg = reg_prefix(to_type)
        self.emit_line("  scvtf " + dst_reg + "0, w0")
      } else if src_is_float && dst_is_float {
        // float → double or double → float: fcvt
        let src_reg = reg_prefix(src_type)
        let dst_reg = reg_prefix(to_type)
        if src_reg != dst_reg {
          self.emit_line("  fcvt " + dst_reg + "0, " + src_reg + "0")
        }
      }
      // int→int casts: truncation / extension
      // Already handled by emit_cast for int subtypes
    }
    @ast.Comma(l, r) => {
      self.translate_expr(l)
      self.translate_expr(r)
    }
    @ast.Conditional(cond, then_e, else_e) =>
      self.translate_ternary(cond, then_e, else_e)
    @ast.AddressOf(e) => self.translate_address_of(e)
    @ast.Deref(e) => self.translate_deref(e)
    @ast.Subscript(ptr, index) => self.translate_subscript(ptr, index)
    @ast.Dot(e, field_name) => self.translate_dot(e, field_name)
    @ast.Arrow(e, field_name) => self.translate_arrow(e, field_name)
    @ast.PostfixInc(e) => self.translate_postfix_incdec(e, "add")
    @ast.PostfixDec(e) => self.translate_postfix_incdec(e, "sub")
    @ast.PrefixInc(e) => self.translate_prefix_incdec(e, "add")
    @ast.PrefixDec(e) => self.translate_prefix_incdec(e, "sub")
    @ast.SizeofExpr(e) => {
      let typ = self.expr_type(e)
      let sz = @sema.type_size(typ)
      self.emit_line("  mov x0, #" + sz.to_string())
    }
    @ast.SizeofType(typ) => {
      let sz = @sema.type_size(typ)
      self.emit_line("  mov x0, #" + sz.to_string())
    }
  }
}

///|
fn Codegen::binary(
  self : Codegen,
  l : @ast.Expr,
  r : @ast.Expr,
  op : String,
) -> Unit {
  self.translate_expr(l)
  self.emit_line("  str x0, [sp, #-16]!")
  self.translate_expr(r)
  self.emit_line("  ldr x1, [sp], #16")
  self.emit_line("  " + op + " x0, x1, x0")
}


///|
fn Codegen::expr_type(self : Codegen, e : @ast.Expr) -> @ast.Type {
  match e {
    @ast.Identifier(name) =>
      match self.analyzer {
        Some(a) =>
          match a.lookup_var_type(name) {
            Some(t) => t
            None => @ast.int_type(@ast.signed_signed())
          }
        None => @ast.int_type(@ast.signed_signed())
      }
    @ast.FloatLiteral(_) => @ast.float_type()
    @ast.DoubleLiteral(_) => @ast.double_type()
    @ast.Call(func, _) => self.callee_return_type(func)
    @ast.Add(l, _) => self.expr_type(l)
    @ast.Sub(l, _) => self.expr_type(l)
    @ast.Mul(l, _) => self.expr_type(l)
    @ast.Div(l, _) => self.expr_type(l)
    @ast.Mod(l, _) => self.expr_type(l)
    _ => @ast.int_type(@ast.signed_signed())
  }
}

///|
fn Codegen::callee_return_type(self : Codegen, func : @ast.Expr) -> @ast.Type {
  match func {
    @ast.Identifier(name) =>
      match self.analyzer {
        Some(a) =>
          match a.lookup(name) {
            Some(sym) =>
              match sym.typ {
                @ast.Type::Void => @ast.int_type(@ast.signed_signed())
                other => other
              }
            None => @ast.int_type(@ast.signed_signed())
          }
        None => @ast.int_type(@ast.signed_signed())
      }
    _ => @ast.int_type(@ast.signed_signed())
  }
}

///|
fn Codegen::cmp_op(
  self : Codegen,
  l : @ast.Expr,
  r : @ast.Expr,
  cond : String,
) -> Unit {
  self.translate_expr(l)
  self.emit_line("  str x0, [sp, #-16]!")
  self.translate_expr(r)
  self.emit_line("  ldr x1, [sp], #16")
  self.emit_line("  cmp x1, x0")
  self.emit_line("  cset x0, " + cond)
}

///|
fn Codegen::cmp_op_typed(
  self : Codegen,
  l : @ast.Expr,
  r : @ast.Expr,
  cond : String,
) -> Unit {
  let typ = self.expr_type(l)
  if is_float_type(typ) {
    let prefix = reg_prefix(typ)
    self.translate_expr(l)
    self.emit_line("  str " + prefix + "0, [sp, #-16]!")
    self.translate_expr(r)
    self.emit_line("  ldr " + prefix + "1, [sp], #16")
    self.emit_line("  fcmp " + prefix + "1, " + prefix + "0")
    self.emit_line("  cset x0, " + cond)
  } else {
    self.cmp_op(l, r, cond)
  }
}

///|
fn Codegen::mod_div(self : Codegen, l : @ast.Expr, r : @ast.Expr) -> Unit {
  self.translate_expr(l)
  self.emit_line("  str x0, [sp, #-16]!")
  self.translate_expr(r)
  self.emit_line("  ldr x1, [sp], #16")
  self.emit_line("  sdiv x2, x1, x0")
  self.emit_line("  msub x0, x2, x0, x1")
}

///|
fn Codegen::logical_bin(
  self : Codegen,
  l : @ast.Expr,
  r : @ast.Expr,
  is_or : Bool,
) -> Unit {
  let short_label = self.next_label()
  let end_label = self.next_label()
  let branch = if is_or { "b.ne" } else { "b.eq" }
  let short_val = if is_or { "#1" } else { "#0" }
  let long_val = if is_or { "#0" } else { "#1" }

  self.translate_expr(l)
  self.emit_line("  cmp x0, #0")
  self.emit_line("  " + branch + " " + short_label)
  self.translate_expr(r)
  self.emit_line("  cmp x0, #0")
  self.emit_line("  " + branch + " " + short_label)
  self.emit_line("  mov x0, " + long_val)
  self.emit_line("  b " + end_label)
  self.emit_line(short_label + ":")
  self.emit_line("  mov x0, " + short_val)
  self.emit_line(end_label + ":")
}

///|
fn Codegen::emit_line(self : Codegen, s : String) -> Unit {
  self.output.write_string(s + "\n")
}

///|
fn Codegen::next_label(self : Codegen) -> String {
  let n = self.label_counter
  self.label_counter = n + 1
  "L" + n.to_string()
}

///|
fn Codegen::add_string_literal(self : Codegen, content : String) -> String {
  let n = self.string_labels
  self.string_labels = n + 1
  let label = "L_str" + n.to_string()
  self.string_literals.push((label, content))
  label
}

///|
fn Codegen::add_float_constant(
  self : Codegen,
  value : Double,
  is_double : Bool,
) -> String {
  let n = self.string_labels
  self.string_labels = n + 1
  let label = "L_float" + n.to_string()
  let value_str = value.to_string()
  self.float_constants.push((label, value_str, is_double))
  label
}
// =============================================================================
// Variable access via symbol table
// =============================================================================

///|
fn Codegen::load_var(self : Codegen, name : String) -> Unit {
  // Check static locals first
  let key = self.current_func + "." + name
  let mut found_label : String? = None
  let mut si = 0
  while si < self.static_var_labels.length() {
    let (f_name, label) = self.static_var_labels[si]
    if f_name == key {
      found_label = Some(label)
    }
    si = si + 1
  }
  match found_label {
    Some(label) => {
      self.emit_line("  adrp x8, " + label + "@PAGE")
      self.emit_line("  add x8, x8, " + label + "@PAGEOFF")
      self.emit_line("  ldr x0, [x8]")
      return ()
    }
    None => ()
  }

  match self.analyzer {
    Some(a) =>
      match a.lookup(name) {
        Some(sym) =>
          match sym.kind {
            @sema.SymbolKind::EnumConst => {
              self.emit_line("  mov x0, #" + sym.value.to_string())
              return ()
            }
            @sema.SymbolKind::Func => {
              // Function name used as value — compute its address
              self.emit_line("  adrp x0, _" + name + "@PAGE")
              self.emit_line("  add x0, x0, _" + name + "@PAGEOFF")
              return ()
            }
            _ => {
              if sym.offset == -1 {
                // Global variable — load via ADRP
                let instr = load_instr(sym.typ)
                self.emit_line("  adrp x8, _" + name + "@PAGE")
                self.emit_line("  add x8, x8, _" + name + "@PAGEOFF")
                self.emit_line("  " + instr + "0, [x8]")
                return ()
              }
              let off = -(sym.offset + 32)
              let instr = load_instr(sym.typ)
              self.emit_line(
                "  " + instr + "0, [x29, #" + off.to_string() + "]",
              )
              return ()
            }
          }
        None => ()
      }
    None => ()
  }
  self.emit_line("  ldr x0, [sp]")
}

///|
fn Codegen::store_var(self : Codegen, name : String) -> Unit {
  // Check static locals first
  let key = self.current_func + "." + name
  let mut found_label : String? = None
  let mut si = 0
  while si < self.static_var_labels.length() {
    let (f_name, label) = self.static_var_labels[si]
    if f_name == key {
      found_label = Some(label)
    }
    si = si + 1
  }
  match found_label {
    Some(label) => {
      self.emit_line("  adrp x8, " + label + "@PAGE")
      self.emit_line("  add x8, x8, " + label + "@PAGEOFF")
      self.emit_line("  str x0, [x8]")
      return ()
    }
    None => ()
  }

  match self.analyzer {
    Some(a) =>
      match a.lookup(name) {
        Some(sym) => {
          if sym.offset == -1 {
            // Global variable — store via ADRP
            let instr = store_instr(sym.typ)
            self.emit_line("  adrp x8, _" + name + "@PAGE")
            self.emit_line("  add x8, x8, _" + name + "@PAGEOFF")
            self.emit_line("  " + instr + "0, [x8]")
            return ()
          }
          let off = -(sym.offset + 32)
          let instr = store_instr(sym.typ)
          self.emit_line(
            "  " + instr + "0, [x29, #" + off.to_string() + "]",
          )
          return ()
        }
        None => ()
      }
    None => ()
  }
  self.emit_line("  str x0, [sp]")
}

// =============================================================================
// Type conversion helpers
// =============================================================================

///|
fn Codegen::translate_ternary(
  self : Codegen,
  cond : @ast.Expr,
  then_e : @ast.Expr,
  else_e : @ast.Expr,
) -> Unit {
  let else_label = self.next_label()
  let end_label = self.next_label()
  self.translate_expr(cond)
  self.emit_line("  cmp x0, #0")
  self.emit_line("  b.eq " + else_label)
  self.translate_expr(then_e)
  self.emit_line("  b " + end_label)
  self.emit_line(else_label + ":")
  self.translate_expr(else_e)
  self.emit_line(end_label + ":")
}

// =============================================================================
// Switch/case translation
// =============================================================================

///|
fn Codegen::translate_switch(
  self : Codegen,
  expr : @ast.Expr,
  body : @ast.Stmt,
) -> Unit {
  let end_label = self.next_label()
  self.break_stack.push(end_label)
  // Evaluate switch expression into x0, save to x9
  self.translate_expr(expr)
  self.emit_line("  mov x9, x0")
  self.translate_switch_body(body, end_label)
  self.emit_line(end_label + ":")
  self.break_stack.pop() |> ignore
}

///|
fn Codegen::translate_switch_body(
  self : Codegen,
  stmt : @ast.Stmt,
  end_label : String,
) -> Unit {
  match stmt {
    @ast.Compound(stmts) => {
      // Collect: (is_case, label_opt, body_stmt)
      // is_case=true means emit a case label before the body
      // For standalone statements, is_case=false
      let entries : Array[(Bool, String?, @ast.Stmt)] = []
      let mut has_default = false
      let mut default_label = ""
      for s in stmts {
        match s {
          @ast.Case(_, _) => {
            let label = self.next_label()
            entries.push((true, Some(label), s))
          }
          @ast.Default(_) => {
            has_default = true
            default_label = self.next_label()
            entries.push((true, Some(default_label), s))
          }
          _ => entries.push((false, None, s))
        }
      }
      // Pass 1: emit dispatch chain for Case entries
      let mut i = 0
      while i < entries.length() {
        let (is_case, _label_opt, s) = entries[i]
        if is_case {
          match s {
            @ast.Case(val, _) => {
              let label = entries[i].1.unwrap()
              self.translate_expr(val)
              self.emit_line("  cmp x9, x0")
              self.emit_line("  b.eq " + label)
            }
            _ => ()
          }
        }
        i = i + 1
      }
      // Branch to default or end
      if has_default {
        self.emit_line("  b " + default_label)
      } else {
        self.emit_line("  b " + end_label)
      }
      // Pass 2: emit body labels and bodies
      let mut j = 0
      while j < entries.length() {
        let (_is_case, label_opt, s) = entries[j]
        match label_opt {
          Some(lbl) => self.emit_line(lbl + ":")
          None => ()
        }
        match s {
          @ast.Case(_, case_body) => {
            let body = unwrap_case_chain(case_body)
            self.translate_stmt(body)
          }
          @ast.Default(body) => {
            let body = unwrap_case_chain(body)
            self.translate_stmt(body)
          }
          _ => self.translate_stmt(s)
        }
        j = j + 1
      }
    }
    _ => self.translate_stmt(stmt)
  }
}

///|
/// Unwrap nested Case/Default chains for multiple labels sharing one body
/// e.g. Case(1, Case(2, body)) → body
fn unwrap_case_chain(stmt3 : @ast.Stmt) -> @ast.Stmt {
  match stmt3 {
    @ast.Case(_, inner) => unwrap_case_chain(inner)
    @ast.Default(inner) => unwrap_case_chain(inner)
    _ => stmt3
  }
}
// =============================================================================
// Pointer / array support
// =============================================================================

///|
fn Codegen::translate_address_of(self : Codegen, e : @ast.Expr) -> Unit {
  // Compute the address of an lvalue expression
  match e {
    @ast.Identifier(name) => {
      // Check if this is a function (global, not on stack)
      match self.analyzer {
        Some(a) =>
          match a.lookup(name) {
            Some(sym) => {
              if sym.offset == -1 {
                // Global variable or function — load via ADRP
                self.emit_line("  adrp x0, _" + name + "@PAGE")
                self.emit_line("  add x0, x0, _" + name + "@PAGEOFF")
                return ()
              }
              let off = -(sym.offset + 32)
              self.emit_line("  add x0, x29, #" + off.to_string())
              return ()
            }
            None => ()
          }
        None => ()
      }
      self.emit_line("  mov x0, sp") // fallback
    }
    @ast.Deref(e2) =>
      // &*p = p
      self.translate_expr(e2)
    @ast.Subscript(ptr, index) => {
      // &arr[i] = ptr + index * elem_size
      self.translate_address_of(ptr)
      self.emit_line("  mov x9, x0")
      self.translate_expr(index)
      let elem_size = self.array_element_size(ptr)
      if elem_size > 1 {
        if elem_size == 2 {
          self.emit_line("  lsl x0, x0, #1")
        } else if elem_size == 4 {
          self.emit_line("  lsl x0, x0, #2")
        } else if elem_size == 8 {
          self.emit_line("  lsl x0, x0, #3")
        } else {
          self.emit_line("  mov x10, #" + elem_size.to_string())
          self.emit_line("  mul x0, x0, x10")
        }
      }
      self.emit_line("  add x0, x9, x0")
    }
    @ast.Dot(e2, field_name) => {
      // &s.field = address of s + offset of field
      self.translate_address_of(e2)
      let off = self.struct_field_offset(e2, field_name)
      if off > 0 {
        self.emit_line("  add x0, x0, #" + off.to_string())
      }
    }
    @ast.Arrow(e2, field_name) => {
      // &ptr->field = ptr + offset of field
      self.translate_expr(e2) // load pointer value
      let off = self.struct_field_offset(e2, field_name)
      if off > 0 {
        self.emit_line("  add x0, x0, #" + off.to_string())
      }
    }
    _ =>
      // Fallback: evaluate expression (assume it's already an lvalue address)
      self.translate_expr(e)
  }
}

///|
fn Codegen::translate_deref(self : Codegen, e : @ast.Expr) -> Unit {
  // Load from address in x0
  self.translate_expr(e)
  self.emit_line("  ldr x0, [x0]")
}

///|
fn Codegen::translate_subscript(
  self : Codegen,
  ptr : @ast.Expr,
  index : @ast.Expr,
) -> Unit {
  self.translate_address_of(ptr)
  self.emit_line("  mov x9, x0") // save base address in x9
  self.translate_expr(index)
  // Compute element size from array type
  let elem_size = self.array_element_size(ptr)
  if elem_size > 1 {
    // Use shift for power-of-2 sizes, multiply for others
    if elem_size == 2 {
      self.emit_line("  lsl x0, x0, #1")
    } else if elem_size == 4 {
      self.emit_line("  lsl x0, x0, #2")
    } else if elem_size == 8 {
      self.emit_line("  lsl x0, x0, #3")
    } else {
      self.emit_line("  mov x10, #" + elem_size.to_string())
      self.emit_line("  mul x0, x0, x10")
    }
  }
  self.emit_line("  add x9, x9, x0") // base + index*size
  self.emit_line("  ldr x0, [x9]") // load from computed address
}

///|
fn Codegen::array_element_size(self : Codegen, e : @ast.Expr) -> Int {
  match e {
    @ast.Identifier(name) =>
      match self.analyzer {
        Some(a) =>
          match a.lookup_var_type(name) {
            Some(@ast.Type::Array(elem, _)) => @sema.type_size(elem)
            _ => 4
          }
        None => 4
      }
    _ => 4 // default to int
  }
}

///|
fn Codegen::translate_dot(
  self : Codegen,
  e : @ast.Expr,
  field_name : String,
) -> Unit {
  // struct.field: compute address of struct, add field offset, then load
  self.translate_address_of(e)
  // Now x0 has struct base address. Compute field offset.
  let offset = self.struct_field_offset(e, field_name)
  if offset > 0 {
    self.emit_line("  add x0, x0, #" + offset.to_string())
  }
  self.emit_line("  ldr x0, [x0]")
}

///|
fn Codegen::translate_arrow(
  self : Codegen,
  e : @ast.Expr,
  field_name : String,
) -> Unit {
  // ptr->field = (*ptr).field
  self.translate_expr(e) // load pointer value into x0
  let offset = self.struct_field_offset(e, field_name)
  if offset > 0 {
    self.emit_line("  add x0, x0, #" + offset.to_string())
  }
  self.emit_line("  ldr x0, [x0]")
}

///|
fn Codegen::struct_field_offset(
  self : Codegen,
  e : @ast.Expr,
  field_name : String,
) -> Int {
  match e {
    @ast.Identifier(name) =>
      match self.analyzer {
        Some(a) =>
          match a.lookup_var_type(name) {
            Some(typ) => self.field_offset_of_type(typ, field_name, a)
            None => 0
          }
        None => 0
      }
    @ast.Dot(obj, _) =>
      // Recursively find the type of the inner object
      self.struct_field_offset(obj, field_name)
    @ast.Deref(ptr) =>
      // ptr->field: type is the pointed-to type
      match self.analyzer {
        Some(a) =>
          match a.lookup_var_type(self.expr_name(ptr)) {
            Some(@ast.Type::Pointer(inner)) =>
              self.field_offset_of_type(inner, field_name, a)
            _ => 0
          }
        None => 0
      }
    _ => 0
  }
}

///|
fn Codegen::expr_name(_self : Codegen, e : @ast.Expr) -> String {
  match e {
    @ast.Identifier(name) => name
    _ => ""
  }
}

///|
fn Codegen::field_offset_of_type(
  _self : Codegen,
  typ : @ast.Type,
  field_name : String,
  a : @sema.Analyzer,
) -> Int {
  match typ {
    @ast.Type::Struct(tag, fields) => {
      if fields.length() == 0 {
        // Look up tag in analyzer's struct registry
        match a.lookup_struct(tag) {
          Some(@ast.Type::Struct(_, full_fields)) => {
            let mut off = 0
            for f in full_fields {
              if f.name == field_name {
                return off
              }
              off = off + @sema.type_size(f.typ)
            }
            return 0
          }
          _ => return 0
        }
      }
      let mut off = 0
      for f in fields {
        if f.name == field_name {
          return off
        }
        off = off + @sema.type_size(f.typ)
      }
      0
    }
    @ast.Type::Union(tag, fields) => {
      // For unions, all fields start at offset 0
      if fields.length() == 0 {
        match a.lookup_struct(tag) {
          Some(_) => return 0
          None => return 0
        }
      }
      0
    }
    _ => 0
  }
}

// =============================================================================
// Float/double support helpers
// =============================================================================

///|
fn is_float_type(typ : @ast.Type) -> Bool {
  match typ {
    @ast.Type::Float => true
    @ast.Type::Double => true
    _ => false
  }
}

///|
fn reg_prefix(typ : @ast.Type) -> String {
  match typ {
    @ast.Type::Float => "s"
    @ast.Type::Double => "d"
    _ => "x"
  }
}

///|
/// Return the full ldr instruction with proper sign/zero extension for the type
fn load_instr(typ : @ast.Type) -> String {
  match typ {
    @ast.Type::Char(@ast.Signed::Signed) => "ldrsb x"
    @ast.Type::Char(@ast.Signed::Unsigned) | @ast.Type::Char(@ast.Signed::Unspecified) => "ldrb w"
    @ast.Type::Short(@ast.Signed::Signed) => "ldrsh x"
    @ast.Type::Short(@ast.Signed::Unsigned) => "ldrh w"
    @ast.Type::Float => "ldr s"
    @ast.Type::Double => "ldr d"
    _ => "ldr x"
  }
}

///|
/// Return the str instruction with proper truncation for the type
fn store_instr(typ : @ast.Type) -> String {
  match typ {
    @ast.Type::Char(_) => "strb w"
    @ast.Type::Short(_) => "strh w"
    @ast.Type::Float => "str s"
    @ast.Type::Double => "str d"
    _ => "str x"
  }
}



// =============================================================================
// Compound assignment codegen
// =============================================================================

///|
fn Codegen::translate_assign(
  self : Codegen,
  l : @ast.Expr,
  r : @ast.Expr,
  op : String,
) -> Unit {
  if op == "mov" {
    self.translate_plain_assign(l, r)
  } else {
    // Compound assignment: l op= r → l = load(l) op r
    match l {
      @ast.Identifier(name) => {
        self.load_var(name)
        self.emit_line("  mov x10, x0")
        self.translate_expr(r)
        self.emit_line("  " + op + " x0, x10, x0")
        self.store_var(name)
      }
      @ast.Deref(ptr) => {
        self.translate_expr(ptr)
        self.emit_line("  mov x9, x0")
        self.emit_line("  ldr x10, [x9]")
        self.translate_expr(r)
        self.emit_line("  " + op + " x0, x10, x0")
        self.emit_line("  str x0, [x9]")
      }
      _ => {
        self.translate_expr(l)
        self.emit_line("  str x0, [sp]")
      }
    }
  }
}

///|
fn Codegen::translate_assign_mod(
  self : Codegen,
  l : @ast.Expr,
  r : @ast.Expr,
) -> Unit {
  match l {
    @ast.Identifier(name) => {
      self.load_var(name)
      self.emit_line("  mov x10, x0")
      self.translate_expr(r)
      self.emit_line("  mov x11, x0")
      self.emit_line("  sdiv x12, x10, x11")
      self.emit_line("  msub x0, x12, x11, x10")
      self.store_var(name)
    }
    _ => {
      self.translate_expr(l)
      self.emit_line("  str x0, [sp]")
    }
  }
}

///|
fn Codegen::translate_plain_assign(
  self : Codegen,
  l : @ast.Expr,
  r : @ast.Expr,
) -> Unit {
  match l {
    @ast.Identifier(name) => {
      self.translate_expr(r)
      self.store_var(name)
    }
    @ast.Deref(ptr) => {
      self.translate_expr(ptr)
      self.emit_line("  mov x9, x0")
      self.translate_expr(r)
      self.emit_line("  str x0, [x9]")
    }
    @ast.Subscript(arr, idx) => {
      self.translate_address_of(arr)
      self.emit_line("  mov x9, x0")
      self.translate_expr(idx)
      let elem_size = self.array_element_size(arr)
      if elem_size > 1 {
        if elem_size == 2 {
          self.emit_line("  lsl x0, x0, #1")
        } else if elem_size == 4 {
          self.emit_line("  lsl x0, x0, #2")
        } else if elem_size == 8 {
          self.emit_line("  lsl x0, x0, #3")
        }
      }
      self.emit_line("  add x9, x9, x0")
      self.translate_expr(r)
      self.emit_line("  str x0, [x9]")
    }
    @ast.Dot(obj, field_name) => {
      self.translate_address_of(obj)
      let off = self.struct_field_offset(obj, field_name)
      if off > 0 {
        self.emit_line("  add x0, x0, #" + off.to_string())
      }
      self.emit_line("  mov x9, x0")
      self.translate_expr(r)
      self.emit_line("  str x0, [x9]")
    }
    @ast.Arrow(obj, field_name) => {
      self.translate_expr(obj)
      let off = self.struct_field_offset(obj, field_name)
      if off > 0 {
        self.emit_line("  add x0, x0, #" + off.to_string())
      }
      self.emit_line("  mov x9, x0")
      self.translate_expr(r)
      self.emit_line("  str x0, [x9]")
    }
    _ => {
      self.translate_expr(r)
      self.emit_line("  str x0, [sp]")
    }
  }
}
///|
/// Postfix inc/dec: return old value, then write new value back to lvalue
fn Codegen::translate_postfix_incdec(
  self : Codegen,
  e : @ast.Expr,
  op : String,
) -> Unit {
  match e {
    @ast.Identifier(name) => {
      self.load_var(name)
      self.emit_line("  mov x10, x0")
      self.emit_line("  " + op + " x0, x0, #1")
      self.store_var(name)
      self.emit_line("  mov x0, x10")
    }
    @ast.Deref(ptr) => {
      self.translate_expr(ptr)
      self.emit_line("  mov x9, x0")
      self.emit_line("  ldr x10, [x9]")
      self.emit_line("  " + op + " x0, x10, #1")
      self.emit_line("  str x0, [x9]")
      self.emit_line("  mov x0, x10")
    }
    _ => {
      self.translate_expr(e)
      self.emit_line("  mov x10, x0")
      self.emit_line("  " + op + " x0, x0, #1")
    }
  }
}

///|
/// Prefix inc/dec: compute new value, write it back, return new value
fn Codegen::translate_prefix_incdec(
  self : Codegen,
  e : @ast.Expr,
  op : String,
) -> Unit {
  match e {
    @ast.Identifier(name) => {
      self.load_var(name)
      self.emit_line("  " + op + " x0, x0, #1")
      self.store_var(name)
    }
    @ast.Deref(ptr) => {
      self.translate_expr(ptr)
      self.emit_line("  mov x9, x0")
      self.emit_line("  ldr x10, [x9]")
      self.emit_line("  " + op + " x0, x10, #1")
      self.emit_line("  str x0, [x9]")
    }
    _ => {
      self.translate_expr(e)
      self.emit_line("  " + op + " x0, x0, #1")
    }
  }
}
