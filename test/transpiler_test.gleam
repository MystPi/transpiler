import gleam/list
import gleeunit
import birdie
import transpiler as t
import transpiler/pattern as p

pub fn main() {
  gleeunit.main()
}

pub fn literals_test() {
  t.EList([
    t.EInt(42),
    t.EString("I said\n\t\"hello\""),
    t.EVariable("foobar"),
    t.EBool(True),
    t.EBool(False),
  ])
  |> t.expression_to_string
  |> birdie.snap("literal values are generated")
}

pub fn nested_lists_test() {
  t.EList([t.EString("foo"), t.EString("bar"), t.EString("baz")])
  |> list.repeat(4)
  |> t.EList
  |> list.repeat(2)
  |> t.EList
  |> t.expression_to_string
  |> birdie.snap("nested lists are indented")
}

pub fn binops_test() {
  t.EBinop("+", t.EBinop("*", t.EInt(3), t.EInt(7)), t.EInt(8))
  |> t.expression_to_string
  |> birdie.snap("binops are generated")
}

pub fn let_test() {
  t.ELet(
    name: "my_name",
    value: t.EString("MystPi"),
    body: t.EVariable("my_name"),
  )
  |> t.expression_to_string
  |> birdie.snap("let expressions are generated")
}

pub fn lambda_test() {
  t.ELambda(
    parameters: ["foo", "bar", "baz"],
    body: t.EBinop(
      "+",
      t.EBinop("+", t.EVariable("foo"), t.EVariable("bar")),
      t.EVariable("baz"),
    ),
  )
  |> t.expression_to_string
  |> birdie.snap("lambda expressions are generated")
}

pub fn apply_test() {
  t.EApply(
    function: t.EVariable("foo"),
    arguments: t.EList([t.EString("foo"), t.EString("bar"), t.EString("baz")])
      |> list.repeat(4),
  )
  |> t.expression_to_string
  |> birdie.snap("function applications are generated")
}

pub fn match_test() {
  t.EMatch(
    subject: t.EList([t.EString("hello there"), t.EBool(False), t.EInt(3)]),
    clauses: [
      #(
        p.PList([p.PString("hello there"), p.PBool(False), p.PInt(3)]),
        t.EString("first case"),
      ),
      #(
        p.PListTail([p.PVariable("head")], "tail"),
        t.EString("pattern variables are defined"),
      ),
      #(p.PVariable("anything"), t.EString("catch-all case")),
      #(p.PIgnore, t.EString("cases after catch-all aren't generated")),
    ],
  )
  |> t.expression_to_string
  |> birdie.snap("match expressions are generated")
}

pub fn everything_test() {
  t.ELet(
    name: "map",
    value: t.ELambda(
      parameters: ["list", "fn"],
      body: t.EMatch(subject: t.EVariable("list"), clauses: [
        #(p.PList([]), t.EList([])),
        #(
          p.PListTail([p.PVariable("x")], "xs"),
          t.EApply(t.EVariable("cons"), [
            t.EApply(t.EVariable("fn"), [t.EVariable("x")]),
            t.EApply(t.EVariable("map"), [t.EVariable("xs"), t.EVariable("fn")]),
          ]),
        ),
      ]),
    ),
    body: t.ELet(
      name: "doubles",
      value: t.EApply(t.EVariable("map"), [
        t.EList([t.EInt(1), t.EInt(2), t.EInt(3)]),
        t.ELambda(["x"], t.EBinop("*", t.EVariable("x"), t.EInt(2))),
      ]),
      body: t.EApply(t.EVariable("println"), [t.EVariable("doubles")]),
    ),
  )
  |> t.expression_to_string
  |> birdie.snap("complex expressions are generated")
}
