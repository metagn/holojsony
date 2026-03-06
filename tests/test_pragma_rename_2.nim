import holojsony

type
  Foo {.inheritable.} = object
    a {.json: "x".}: string
    case b {.json: "y".}: uint8 #range[0..5] # https://github.com/nim-lang/Nim/pull/25585
    of 0..2:
      c {.json: "z".}: int
      #when true: # nim limitation
      d {.json: "t".}: bool
    else:
      discard
    notRenamed: string

  Bar = ref object of Foo
    e {.json: "u".}: int

when false:
  let renames = {
    "a": "x",
    "b": "y",
    "c": "z",
    "d": "t",
    "e": "u",
    "notRenamed": "notRenamed"
  }
  var dummy = Bar()
  for a, b in renames.items:
    var name = b
    renameHook dummy, name
    doAssert name == a, $(name, a)

  proc renameHook*(x: var Bar, y: var string) =
    jsonwrap.renameHook(x, y)

let obj1 = Bar(a: "foo", b: 1, c: 123, d: true, notRenamed: "bar", e: 456)
let ser = toJson(obj1)
echo ser
let obj2 = fromJson(ser, Bar)
doAssert obj1.a == obj2.a
doAssert obj1.b == obj2.b
doAssert obj1.c == obj2.c
doAssert obj1.d == obj2.d
doAssert obj1.e == obj2.e
doAssert obj1.notRenamed == obj2.notRenamed
