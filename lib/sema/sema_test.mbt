///|
test "sema simple" {
  let tu = @ast.parse_translation_unit(
    "int main(void) { int x; x = 7; return x; }", "t.c",
  )
  let a = @sema.analyze(tu)
  // Should find 'main' in the symbol table
  match a.lookup("main") {
    Some(s) => assert_eq(s.name, "main")
    None => assert_true(false, msg="main not found")
  }
}
