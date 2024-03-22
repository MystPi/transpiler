import gleam/int
import gleam/list
import gleam/bool
import gleam/dict.{type Dict}
import gleam/string
import glam/doc.{type Document}
import transpiler/pattern.{type Pattern}

// ---- TYPES ------------------------------------------------------------------

pub type Expression {
  ELambda(parameters: List(String), body: Expression)
  EApply(function: Expression, arguments: List(Expression))
  ELet(name: String, value: Expression, body: Expression)
  EVariable(name: String)
  EInt(value: Int)
  EString(value: String)
  EBool(value: Bool)
  EList(List(Expression))
  EBinop(op: String, left: Expression, right: Expression)
  EMatch(subject: Expression, clauses: List(#(Pattern, Expression)))
}

// ---- CODE GENERATION --------------------------------------------------------

const max_width = 80

/// Generate JavaScript code from an expression.
///
pub fn expression_to_string(expression: Expression) -> String {
  expression
  |> expression_to_doc
  |> doc.to_string(max_width)
}

fn expression_to_doc(expression: Expression) -> Document {
  case expression {
    EInt(i) -> doc.from_string(int.to_string(i))
    EString(s) -> doc.from_string(string.inspect(s))
    EBool(b) -> doc.from_string(string.lowercase(bool.to_string(b)))
    EVariable(v) -> doc.from_string(v)
    EList(items) -> list_to_doc(items)
    EBinop(op, left, right) -> binop_to_doc(op, left, right)
    ELet(name, value, body) -> let_to_doc(name, value, body)
    EApply(function, args) -> apply_to_doc(function, args)
    ELambda(parameters, body) -> lambda_to_doc(parameters, body)
    EMatch(subject, clauses) -> match_to_doc(subject, clauses)
  }
}

/// A list is generated as a JS array literal.
///
fn list_to_doc(items: List(Expression)) -> Document {
  items
  |> list.map(expression_to_doc)
  |> doc.concat_join([doc.from_string(","), doc.space])
  |> wrap("[", "]", trailing: ",")
}

/// Binops map 1:1 with their JS equivalents.
///
fn binop_to_doc(op: String, left: Expression, right: Expression) -> Document {
  doc.concat([
    expression_to_doc(left),
    doc.from_string(" " <> op <> " "),
    expression_to_doc(right),
  ])
}

/// A let expression is generated as a const definition wrapped in an IIFE.
/// ```
/// (() => {        // IIFE
///   const x = 5;  // const definition
///   return x * 2; // the body is returned
/// })()
/// ```
///
fn let_to_doc(name: String, value: Expression, body: Expression) -> Document {
  doc.concat([
    gen_const(name, expression_to_doc(value)),
    doc.line,
    gen_return(body),
  ])
  |> wrap_with_iife
}

/// A function application is generated as a JS function call.
/// ```
/// foo(bar, baz)
/// ```
///
fn apply_to_doc(function: Expression, args: List(Expression)) -> Document {
  args
  |> list.map(expression_to_doc)
  |> doc.concat_join([doc.from_string(","), doc.space])
  |> wrap("(", ")", trailing: ",")
  |> doc.prepend(expression_to_doc(function))
}

/// A lambda is generated as an anonymous function.
/// ```
/// (x, y, z) => x + y + z
/// ```
///
fn lambda_to_doc(parameters: List(String), body: Expression) -> Document {
  doc.concat([
    list.map(parameters, doc.from_string)
      |> doc.concat_join([doc.from_string(","), doc.space])
      |> wrap("(", ")", trailing: ","),
    [doc.from_string(" =>"), doc.space, expression_to_doc(body)]
      |> doc.nest_docs(by: 2)
      |> doc.group,
  ])
}

/// A match generates a series of if statements wrapped in an IIFE.
/// ```
/// (() => {                                   // IIFE
///   const $ = ["a", "b", "c"];               // subject
///   if (Array.isArray($) && $.length == 3) { // match case
///     return "Three elements!";              // match body
///   }
///   return "Not three elements";             // catch-all case
/// })()
/// ```
/// When a catch-all case is encountered, all cases after it are ignored and not
/// generated. If there is no catch-all case, a `throw` statement will be generated
/// after the clauses instead to prevent any undefined behaviour.
/// ```
/// (() => {
///   // clauses...
///   throw new Error(..);
/// })()
/// ```
///
fn match_to_doc(
  subject: Expression,
  clauses: List(#(Pattern, Expression)),
) -> Document {
  // The subject will be assigned to the constant `$` so it is not evaluated
  // multiple times when performing checks.
  let new_subject = doc.from_string("$")

  let #(clauses_reversed, has_catch_all) =
    clauses
    |> list.fold_until(#([], False), fn(acc, clause) {
      case match_clause_to_doc(new_subject, clause.0, clause.1) {
        #(doc, True) -> list.Stop(#([doc, ..acc.0], True))
        #(doc, False) -> list.Continue(#([doc, ..acc.0], False))
      }
    })

  let clauses =
    clauses_reversed
    |> list.reverse
    |> doc.join(doc.line)

  let throw_statement = case has_catch_all {
    True -> doc.empty
    False ->
      doc.concat([
        doc.line,
        doc.from_string("throw new Error('Non-exhastive match clauses');"),
      ])
  }

  doc.concat([
    // Here's the actual assignment to `$`
    gen_const("$", expression_to_doc(subject)),
    doc.line,
    clauses,
    throw_statement,
  ])
  |> wrap_with_iife
}

/// A match clause is a simple if statement.
/// ```
/// if (check1 && check2 && ...) {
///   const binding1 = ...;
///   const binding2 = ...;
///   return body;
/// }
/// ```
/// The return tuple's Boolean tells whether the case is a match-all, i.e. there
/// are no checks to perform.
///
fn match_clause_to_doc(
  subject: Document,
  pattern: Pattern,
  body: Expression,
) -> #(Document, Bool) {
  let #(checks, bindings) = pattern.traverse_pattern(pattern, subject)
  let bindings = gen_definitions(bindings)
  let return = gen_return(body)

  case checks {
    [] -> #(doc.concat([bindings, return]), True)
    _ -> {
      let checks =
        checks
        |> list.map(pattern.check_to_doc)
        |> doc.concat_join([doc.from_string(" &&"), doc.space])

      #(
        doc.concat([
          doc.from_string("if "),
          checks
            |> wrap("(", ")", trailing: ""),
          doc.from_string(" {"),
          [doc.line, bindings, return]
            |> doc.nest_docs(by: 2),
          doc.line,
          doc.from_string("}"),
        ]),
        False,
      )
    }
  }
}

/// Generate const definitions for bindings created when traversing a pattern.
/// ```
/// const x = $[0];
/// const y = $[1][0];
/// ```
///
fn gen_definitions(bindings: Dict(String, Document)) -> Document {
  case dict.to_list(bindings) {
    [] -> doc.empty
    bindings ->
      bindings
      |> list.map(fn(bindings) {
        let #(name, value) = bindings
        gen_const(name, value)
      })
      |> doc.join(doc.line)
      |> doc.append(doc.line)
  }
}

// ---- HELPERS ----------------------------------------------------------------

/// Create a return statement returning the given expression.
///
fn gen_return(expression: Expression) -> Document {
  doc.concat([
    doc.from_string("return "),
    expression_to_doc(expression),
    doc.from_string(";"),
  ])
}

/// Create a const definition set to the given value.
///
fn gen_const(name: String, value: Document) -> Document {
  doc.concat([
    doc.from_string("const " <> name <> " = "),
    value,
    doc.from_string(";"),
  ])
}

/// Wrap the given document with an IIFE (Immediately Invoked Function Expression)
///
fn wrap_with_iife(inner: Document) -> Document {
  inner
  |> doc.prepend_docs([doc.from_string("(() => {"), doc.line])
  |> doc.nest(by: 2)
  |> doc.append_docs([doc.line, doc.from_string("})()")])
}

/// Wrap a document with the given left and right strings (such as `[` and `]`)
/// and a trailing character (probably a comma) if the group is broken.
///
fn wrap(
  inner: Document,
  left: String,
  right: String,
  trailing trailing: String,
) -> Document {
  inner
  |> doc.prepend_docs([doc.from_string(left), doc.soft_break])
  |> doc.nest(by: 2)
  |> doc.append_docs([doc.break("", trailing), doc.from_string(right)])
  |> doc.group
}
