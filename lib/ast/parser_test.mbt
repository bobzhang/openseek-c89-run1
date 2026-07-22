///|
test "parse_div_expr" {
  let tu = @ast.parse_translation_unit("int f(void){return 10/3;}", "t.c")
  assert_eq(tu.decls.length(), 1)
  // If we get here the parser didn't crash; the codegen test shows if division works
}
