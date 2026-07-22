///|
test "lexer_simple" {
  let tokens = @ast.tokenize("int main(void) { return 0; }", "test.c")
  assert_true(tokens.length() > 0)
  let last = tokens[tokens.length() - 1]
  match last.kind {
    @ast.Eof => ()
    _ => assert_true(false, msg="expected Eof")
  }
}

///|
test "parser_simple" {
  let tu = @ast.parse_translation_unit("int main(void) { return 0; }", "test.c")
  assert_true(tu.decls.length() > 0)
}
