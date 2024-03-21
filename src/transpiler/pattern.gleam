import gleam/int
import gleam/list
import gleam/bool
import gleam/dict.{type Dict}
import gleam/string
import glam/doc.{type Document}

// ---- TYPES ------------------------------------------------------------------

pub type Pattern {
  PList(List(Pattern))
  PListTail(list: List(Pattern), tail: String)
  PVariable(String)
  PIgnore
  PInt(Int)
  PString(String)
  PBool(Bool)
}

pub type Check {
  ListCheck(subject: Document, length: Int, has_tail: Bool)
  LiteralCheck(subject: Document, should_be: Document)
}

type Ctx {
  Ctx(checks: List(Check), bindings: Dict(String, Document))
}

// ---- TRAVERSING PATTERNS ----------------------------------------------------

/// Recursively traverse a pattern, returning checks and pattern variable bindings
/// created along the way. Checks can be turned into documents with the
/// `check_to_doc` function. Variable bindings are represented as a dictionary of
/// names to documents.
///
pub fn traverse_pattern(
  pattern: Pattern,
  subject: Document,
) -> #(List(Check), Dict(String, Document)) {
  let initial_ctx = Ctx([], dict.new())
  let Ctx(checks, bindings) = do_traverse_pattern(pattern, subject, initial_ctx)
  #(list.reverse(checks), bindings)
}

fn do_traverse_pattern(pattern: Pattern, subject: Document, ctx: Ctx) -> Ctx {
  case pattern {
    PVariable(name) -> insert_binding(ctx, name, subject)
    PIgnore -> ctx
    PInt(i) ->
      push_check(ctx, LiteralCheck(subject, doc.from_string(int.to_string(i))))
    PString(s) ->
      push_check(ctx, LiteralCheck(subject, doc.from_string(string.inspect(s))))
    PBool(b) ->
      push_check(
        ctx,
        LiteralCheck(
          subject,
          doc.from_string(string.lowercase(bool.to_string(b))),
        ),
      )
    PList(patterns) ->
      ctx
      |> push_check(ListCheck(subject, list.length(patterns), False))
      |> traverse_list_patterns(patterns, subject, _)
    PListTail(patterns, tailname) ->
      ctx
      |> push_check(ListCheck(subject, list.length(patterns), True))
      |> traverse_list_patterns(patterns, subject, _)
      |> insert_binding(
        tailname,
        doc.concat([subject, doc.from_string(".slice(1)")]),
      )
  }
}

fn traverse_list_patterns(
  patterns: List(Pattern),
  subject: Document,
  ctx: Ctx,
) -> Ctx {
  use ctx, pattern, index <- list.index_fold(patterns, ctx)

  let new_subject =
    doc.concat([subject, doc.from_string("[" <> int.to_string(index) <> "]")])
  do_traverse_pattern(pattern, new_subject, ctx)
}

// ---- GENERATING CHECKS ------------------------------------------------------

/// Convert a check into its JS equivalent.
///
pub fn check_to_doc(check: Check) -> Document {
  case check {
    ListCheck(subject, length, tail) ->
      doc.concat([
        doc.from_string("Array.isArray("),
        subject,
        doc.from_string(") && "),
        subject,
        doc.from_string(
          ".length"
          <> case tail {
            True -> " >= "
            False -> " == "
          }
          <> int.to_string(length),
        ),
      ])

    LiteralCheck(subject, should_be) ->
      doc.concat([subject, doc.from_string(" === "), should_be])
  }
}

// ---- HELPERS ----------------------------------------------------------------

fn push_check(ctx: Ctx, check: Check) -> Ctx {
  Ctx(..ctx, checks: [check, ..ctx.checks])
}

fn insert_binding(ctx: Ctx, name: String, value: Document) -> Ctx {
  Ctx(..ctx, bindings: dict.insert(ctx.bindings, name, value))
}
