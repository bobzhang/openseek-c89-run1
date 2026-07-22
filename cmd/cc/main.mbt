///| C89 Compiler CLI

///|
/// Strip .c suffix from a file path
fn strip_c_suffix(path : String) -> String {
  if path.has_suffix(".c") {
    path[:path.length() - 2].to_owned()
  } else {
    path
  }
}

///|
/// Get directory part of a file path
fn dirname(path : String) -> String {
  let mut i = path.length() - 1
  while i >= 0 {
    if path[i] == '/' {
      return path[:i].to_owned()
    }
    i = i - 1
  }
  "."
}

///|
/// Resolve #include "file" directives by reading included files
async fn resolve_includes(source : String, base_dir : String) -> String {
  let result = StringBuilder::new()
  let lines = source.split("\n")
  for line_view in lines {
    let line = line_view.to_owned()
    let trimmed = line.trim()
    if trimmed.has_prefix("#include \"") {
      // Extract filename between quotes
      // trimmed is like: #include "file.h"
      // Index 10 is the first char after the opening quote
      let rest = trimmed[10:].to_owned()
      let end = rest.find("\"")
      match end {
        Some(e) => {
          let filename = rest[:e].to_owned()
          let full_path = base_dir + "/" + filename
          let included_data = @fs.read_file(full_path)
          let included_src = included_data.text()
          result.write_string(included_src + "\n")
        }
        None => result.write_string(line + "\n")
      }
    } else {
      result.write_string(line + "\n")
    }
  }
  StringBuilder::to_string(result)
}

///|
async fn main {
  let args = @argparse.parse(
    Command("cc", about="C89 to arm64 macOS compiler", positionals=[
      PositionArg("input", about="Input C file"),
    ]),
  )

  let input_opt = match args {
    { values: { "input"? : Some([file, ..]), .. }, .. } => Some(file)
    _ => None
  }
  if input_opt is None {
    @stdio.stderr.write("error: no input file\n")
    @sys.exit(1)
  }
  let input = input_opt.unwrap()

  let data = @fs.read_file(input)
  let raw_source = data.text()

  // Resolve #include directives
  let source = resolve_includes(raw_source, dirname(input))

  let preprocessed = @preprocessor.preprocess(source)
  let tu = @ast.parse_translation_unit(preprocessed, input)
  // Count functions
  let mut has_func = false
  for d in tu.decls {
    match d {
      @ast.TopLevel::Function(_) => has_func = true
      _ => ()
    }
  }
  if !has_func {
    @stdio.stderr.write("error: no functions found\n")
    @sys.exit(1)
  }
  // Run semantic analysis
  let analyzer = @sema.analyze(tu)
  let asm_code = @codegen.generate(tu, Some(analyzer))

  let s_file = strip_c_suffix(input) + ".s"
  @fs.write_file(s_file, asm_code, create_mode=@fs.CreateMode::CreateOrTruncate)

  let out_file = strip_c_suffix(input)
  let (exit_code, _stdout, stderr) = @process.collect_output("cc", [
    "-o", out_file, s_file,
  ])

  if exit_code != 0 {
    @stdio.stderr.write(stderr.text() + "\n")
    @sys.exit(1)
  }

  println("compiled: " + out_file)
}
