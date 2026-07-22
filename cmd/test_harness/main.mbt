///| Test harness for C89 compiler

async fn main {
  let args = @env.args()
  let command = if args.length() > 1 { args[1] } else { "all" }

  match command {
    "run-valid" => run_valid_tests()
    "run-invalid" => run_invalid_tests()
    _ => {
      run_valid_tests()
      run_invalid_tests()
    }
  }
}

async fn run_valid_tests() -> Unit {
  let valid_dir = "tests/valid"
  let entries = @fs.read_dir(valid_dir)
  let mut passed = 0
  let mut failed = 0

  for entry in entries {
    if !entry.is_file() { continue }
    let name = entry.name()
    if !name.trim_end(chars=".c").length() != 0 || !name.has_suffix(".c") { continue }
    let path = valid_dir + "/" + name

    println("  TEST: " + name)

    // Read expected values from source
    let data = @fs.read_file(path)
    let source = data.text()
    let expected_exit = parse_expected_exit(source)
    let expected_stdout = parse_expected_stdout(source)

    // Compile with our compiler
    let asm = compile_c(source, path)

    // Write assembly and assemble+link
    let s_file = path.trim_end(chars=".c") + ".s"
    let bin_file = path.trim_end(chars=".c").to_owned()

    @fs.write_file(s_file, asm, create_mode=@fs.CreateMode::CreateOrTruncate)

    let (cc_exit, cc_stdout, cc_stderr) = @process.collect_output("cc", [
      "-o", bin_file,
      s_file,
    ])

    if cc_exit != 0 {
      println("    FAIL: assembly failed")
      println("    " + cc_stderr.text())
      failed = failed + 1
      continue
    }

    // Run the binary
    let (run_exit, run_stdout, _run_stderr) = @process.collect_output("./" + bin_file, [])

    if run_exit != expected_exit {
      println("    FAIL: exit code mismatch. got " + run_exit.to_string() + " expected " + expected_exit.to_string())
      failed = failed + 1
      continue
    }

    if expected_stdout.is_some() && run_stdout.text() != expected_stdout.unwrap() {
      println("    FAIL: stdout mismatch")
      println("    got:      " + run_stdout.text())
      println("    expected: " + expected_stdout.unwrap())
      failed = failed + 1
      continue
    }

    println("    PASS")
    passed = passed + 1
  }

  println("")
  println("Valid tests: " + passed.to_string() + " passed, " + failed.to_string() + " failed")
  if failed > 0 { @sys.exit(1) }
}

async fn run_invalid_tests() -> Unit {
  let invalid_dir = "tests/invalid"
  let entries = @fs.read_dir(invalid_dir)
  let mut passed = 0
  let mut failed = 0

  for entry in entries {
    if !entry.is_file() { continue }
    let name = entry.name()
    if !name.has_suffix(".c") { continue }
    let path = invalid_dir + "/" + name

    println("  TEST: " + name)

    let data = @fs.read_file(path)
    let source = data.text()

    // Our compiler should reject this
    let preprocessed = @preprocessor.preprocess(source, [])
    let tu = @ast.parse_translation_unit(preprocessed, path)
    let asm = @codegen.generate(tu)

    // For now, we check if the parser produced no functions (rejection approximation)
    if tu.decls.length() == 0 {
      println("    PASS (rejected)")
      passed = passed + 1
    } else {
      println("    FAIL: not rejected")
      failed = failed + 1
    }
  }

  println("")
  println("Invalid tests: " + passed.to_string() + " passed, " + failed.to_string() + " failed")
  if failed > 0 { @sys.exit(1) }
}

fn compile_c(source : String, filename : String) -> String {
  let preprocessed = @preprocessor.preprocess(source, [])
  let tu = @ast.parse_translation_unit(preprocessed, filename)
  @codegen.generate(tu)
}

fn parse_expected_exit(source : String) -> Int {
  for line in source.split("\n") {
    let s = line.trim()
    if s.starts_with("// EXPECT:EXIT=") {
      let rest = s[14:].trim().to_owned()
      let n : Int = @string.from_str(rest) catch { _ => 0 }
      return n
    }
  }
  0
}

fn parse_expected_stdout(source : String) -> String? {
  for line in source.split("\n") {
    let s = line.trim()
    if s.starts_with("// EXPECT:STDOUT=") {
      let rest = s[16:].trim().to_owned()
      return Some(rest)
    }
  }
  None
}
