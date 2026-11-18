///|
/// C89 Preprocessor
priv struct Preprocessor {
  mut macros : Array[Macro]
}

///|
pub struct Macro {
  name : String
  replacement : String
  params : Array[String] // empty if object-like
}

///|
pub fn preprocess(source : String) -> String {
  let pp : Preprocessor = { macros: [], }
  let result = StringBuilder::StringBuilder()
  let lines_iter = source.split("\n")
  let skipping : Array[Bool] = []
  let mut skip = false

  for line_view in lines_iter {
    let line_str = line_view.to_owned()
    let line = line_str.trim().to_owned()
    if line.has_prefix("#") {
      let dir = line[1:].trim().to_owned()
      if dir.has_prefix("include ") {
        let rest = dir[8:].trim().to_owned()
        let filename = extract_header_name(rest)
        match filename {
          Some(f) => result.write_string("/* included: " + f + " */\n")
          None => ()
        }
      } else if dir.has_prefix("define ") {
        let rest = dir[7:].trim().to_owned()
        // Check for function-like macro first: NAME(...
        let paren = rest.find("(")
        let space = rest.find(" ")
        match paren {
          Some(pidx) =>
            match space {
              Some(sidx) if sidx < pidx => {
                // Space before paren: object-like macro with value
                let name = rest[:sidx].to_owned()
                let replacement = rest[sidx + 1:].trim().to_owned()
                pp.macros.push({ name, replacement, params: [], })
              }
              _ => {
                // Paren first (or no space): function-like macro
                let name = rest[:pidx].trim().to_owned()
                let after = rest[pidx + 1:].to_owned()
                let close = after.find(")")
                match close {
                  Some(cidx) => {
                    let params_str = after[:cidx].trim().to_owned()
                    let params_arr = parse_macro_params(params_str)
                    let replacement = after[cidx + 1:].trim().to_owned()
                    pp.macros.push({ name, replacement, params: params_arr, })
                  }
                  None =>
                    pp.macros.push({ name: rest, replacement: "", params: [], })
                }
              }
            }
          None =>
            // No paren at all: object-like macro
            match space {
              Some(idx) => {
                let name = rest[:idx].to_owned()
                let replacement = rest[idx + 1:].trim().to_owned()
                pp.macros.push({ name, replacement, params: [], })
              }
              None =>
                pp.macros.push({ name: rest, replacement: "", params: [], })
            }
        }
      } else if dir.has_prefix("undef ") {
        let name = dir[6:].trim().to_owned()
        let new_macros : Array[Macro] = []
        for m in pp.macros {
          if m.name != name {
            new_macros.push(m)
          }
        }
        pp.macros = new_macros
      } else if dir.has_prefix("ifdef ") {
        let name = dir[6:].trim().to_owned()
        let defined = is_defined(pp, name)
        let should_skip = !defined // skip if NOT defined
        skipping.push(skip) // save current skip level
        skip = skip || should_skip
      } else if dir.has_prefix("ifndef ") {
        let name = dir[7:].trim().to_owned()
        let defined = is_defined(pp, name)
        let should_skip = defined // skip if defined
        skipping.push(skip)
        skip = skip || should_skip
      } else if dir.has_prefix("if ") {
        let cond = dir[3:].trim().to_owned()
        let val = eval_constant(cond, pp)
        let should_skip = val == 0 // skip if condition false
        skipping.push(skip)
        skip = skip || should_skip
      } else if dir.has_prefix("else") {
        match skipping {
          [] => ()
          _ => {
            let saved = skipping[skipping.length() - 1]
            // Formula: skip = saved || (skip == saved)
            // This correctly inverts the effect of the corresponding #if directive.
            skip = saved || skip == saved
          }
        }
      } else if dir.has_prefix("endif") {
        match skipping {
          [] => ()
          _ => {
            skipping.pop() |> ignore
            skip = false
            for s in skipping {
              if s {
                skip = true
              }
            }
          }
        }
      } else if !skip {
        result.write_string(line_str + "\n")
      }
    } else if !skip {
      let expanded = expand_line(pp, line_str)
      let func_expanded = expand_func_macros(expanded, pp)
      result.write_string(func_expanded + "\n")
    }
  }
  StringBuilder::to_string(result)
}

///|
fn extract_header_name(s : String) -> String? {
  if s.has_prefix("\"") {
    let end_idx = find_last_char(s, '"')
    match end_idx {
      Some(i) => Some(s[1:i].to_owned())
      None => None
    }
  } else if s.has_prefix("<") {
    let end_idx = find_last_char(s, '>')
    match end_idx {
      Some(i) => Some(s[1:i].to_owned())
      None => None
    }
  } else {
    None
  }
}

///|
fn find_last_char(s : String, ch : Char) -> Int32? {
  let mut i = s.length() - 1
  while i >= 0 {
    match s.get_char(i) {
      Some(c) => if c == ch { return Some(i) }
      None => ()
    }
    i = i - 1
  }
  None
}

///|
fn is_defined(pp : Preprocessor, name : String) -> Bool {
  for m in pp.macros {
    if m.name == name {
      return true
    }
  }
  false
}

///|
fn eval_constant(cond : String, pp : Preprocessor) -> Int32 {
  let text = cond.trim().to_owned()
  if text.has_prefix("defined(") && text[text.length() - 1] == ')' {
    let inner = text[8:text.length() - 1].trim().to_owned()
    return if is_defined(pp, inner) { 1 } else { 0 }
  }
  if text.has_prefix("defined ") {
    let inner = text[8:].trim().to_owned()
    return if is_defined(pp, inner) { 1 } else { 0 }
  }
  let n : Int32 = @string.from_str(text) catch { _ => 0 }
  n
}

///|
fn expand_line(pp : Preprocessor, line : String) -> String {
  let mut result = line
  for m in pp.macros {
    // Skip function-like macros — they are handled by expand_func_macros
    if m.params.length() > 0 {
      continue
    }
    if m.name != "" {
      let mut idx : Int32? = result.find(m.name)
      while true {
        match idx {
          Some(pos) => {
            let before = pos == 0 || !is_id_char(line_char(result, pos - 1))
            let after = pos + m.name.length() >= result.length() ||
              !is_id_char(line_char(result, pos + m.name.length()))
            if before && after {
              let prefix = result[:pos].to_owned()
              let suffix_view = result[pos + m.name.length():]
              result = prefix + m.replacement + suffix_view.to_owned()
            }
            idx = result.find(m.name)
          }
          None => break
        }
      }
    }
  }
  result
}

///|
fn line_char(s : String, pos : Int32) -> UInt16 {
  if pos < 0 || pos >= s.length() {
    ' '.to_int().to_uint16()
  } else {
    s[pos]
  }
}

///|
fn is_id_char(ch : UInt16) -> Bool {
  (ch >= 'a' && ch <= 'z') ||
  (ch >= 'A' && ch <= 'Z') ||
  (ch >= '0' && ch <= '9') ||
  ch == '_'
}

///|
/// Parse comma-separated macro parameters: "a,b,c" -> ["a","b","c"]
fn parse_macro_params(s : String) -> Array[String] {
  let trimmed = s.trim()
  if trimmed == "" {
    return []
  }
  let result : Array[String] = []
  let mut start = 0
  while start < trimmed.length() {
    // Find next comma or end
    let mut end = start
    while end < trimmed.length() && trimmed[end] != ',' {
      end = end + 1
    }
    result.push(trimmed[start:end].trim().to_owned())
    start = if end < trimmed.length() { end + 1 } else { trimmed.length() }
  }
  result
}

///|
/// Expand function-like macro invocation: NAME(args)
/// Scans the line for NAME( and replaces with expansion if found.
fn expand_func_macros(line : String, pp : Preprocessor) -> String {
  let mut result = line
  // Loop until no more expansions happen (handles nested expansions like QUAD→DOUBLE→args)
  while true {
    let mut changed = false
    for m in pp.macros {
      if m.params.length() == 0 {
        continue
      }
      let pattern = m.name + "("
      let mut idx : Int32? = result.find(pattern)
      while true {
        match idx {
          Some(pos) => {
            let before = pos == 0 || !is_id_char(result[pos - 1])
            if before {
              let open_paren = pos + m.name.length()
              let mut close_paren = open_paren + 1
              let mut depth = 1
              while close_paren < result.length() && depth > 0 {
                if result[close_paren] == '(' {
                  depth = depth + 1
                } else if result[close_paren] == ')' {
                  depth = depth - 1
                }
                close_paren = close_paren + 1
              }
              if depth == 0 {
                let args_str = result[open_paren + 1:close_paren - 1]
                  .trim()
                  .to_owned()
                let args = parse_macro_args(args_str)
                let expansion = substitute_macro_args(
                  m.replacement,
                  m.params,
                  args,
                )
                let prefix = result[:pos].to_owned()
                let suffix = result[close_paren:].to_owned()
                result = prefix + expansion + suffix
                changed = true
                idx = result.find(pattern)
                continue
              }
            }
            idx = result.find(pattern)
          }
          None => break
        }
      }
    }
    if !changed {
      break
    }
  }
  result
}

///|
/// Parse macro call arguments: "1, 2, 3" -> ["1", "2", "3"] with balanced parens
fn parse_macro_args(s : String) -> Array[String] {
  let trimmed = s.trim()
  if trimmed == "" {
    return []
  }
  let result : Array[String] = []
  let mut start = 0
  let mut depth = 0
  let mut i = 0
  while i < trimmed.length() {
    let ch = trimmed[i]
    if ch == '(' {
      depth = depth + 1
    } else if ch == ')' {
      depth = depth - 1
    } else if ch == ',' && depth == 0 {
      result.push(trimmed[start:i].trim().to_owned())
      start = i + 1
    }
    i = i + 1
  }
  // Last argument (or only argument)
  if start < trimmed.length() {
    result.push(trimmed[start:].trim().to_owned())
  }
  result
}

///|
/// Simple macro argument substitution in replacement text
fn substitute_macro_args(
  replacement : String,
  params : Array[String],
  args : Array[String],
) -> String {
  if params.length() == 0 || args.length() == 0 {
    return replacement
  }
  let result = StringBuilder::StringBuilder()
  let mut i = 0
  while i < replacement.length() {
    // Check for identifier start
    let ch = replacement[i]
    if (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || ch == '_' {
      let start = i
      while i < replacement.length() {
        let c = replacement[i]
        if (c >= 'a' && c <= 'z') ||
          (c >= 'A' && c <= 'Z') ||
          (c >= '0' && c <= '9') ||
          c == '_' {
          i = i + 1
        } else {
          break
        }
      }
      let ident = replacement[start:i].to_owned()
      // Check if this is a parameter
      let mut found = false
      let mut pi = 0
      while pi < params.length() && pi < args.length() {
        if params[pi] == ident {
          result.write_string(args[pi])
          found = true
          break
        }
        pi = pi + 1
      }
      if !found {
        match replacement.get_char(start) {
          Some(c) => result.write_char(c)
          None => ()
        }
        // write remaining chars
        let mut j = start + 1
        while j < i {
          match replacement.get_char(j) {
            Some(c) => result.write_char(c)
            None => ()
          }
          j = j + 1
        }
      }
    } else {
      match replacement.get_char(i) {
        Some(c) => result.write_char(c)
        None => ()
      }
      i = i + 1
    }
  }
  StringBuilder::to_string(result)
}
