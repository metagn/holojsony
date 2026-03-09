import holo_json, std/strutils

type Node = ref object
  kind: string

proc renameHook(v: var Node, fieldName: var string) =
  if fieldName == "type":
    fieldName = "kind"

var node = """{"type":"root"}""".fromJson(Node)
doAssert node.kind == "root"

type
  NodeNumKind = enum # the different node types
    nkInt,           # a leaf with an integer value
    nkFloat,         # a leaf with a float value
  RefNode = ref object
    active: bool
    case kind: NodeNumKind # the ``kind`` field is the discriminator
    of nkInt: intVal: int
    of nkFloat: floatVal: float
  ValueNode = object
    active: bool
    case kind: NodeNumKind # the ``kind`` field is the discriminator
    of nkInt: intVal: int
    of nkFloat: floatVal: float

proc renameHook*(v: var RefNode|ValueNode, fieldName: var string) =
  # rename``type`` field name to ``kind``
  if fieldName == "type":
    fieldName = "kind"

# Test renameHook and discriminator Field Name not being first/missing.
block:
  let
    a = """{"active":true,"type":"nkFloat","floatVal":3.14}""".fromJson(RefNode)
    b = """{"floatVal":3.14,"active":true,"type":"nkFloat"}""".fromJson(RefNode)
    c = """{"type":"nkFloat","floatVal":3.14,"active":true}""".fromJson(RefNode)
    d = """{"active":true,"intVal":42}""".fromJson(RefNode)
  doAssert a.kind == nkFloat
  doAssert b.kind == nkFloat
  doAssert c.kind == nkFloat
  doAssert d.kind == nkInt

block:
  let
    a = """{"active":true,"type":"nkFloat","floatVal":3.14}""".fromJson(ValueNode)
    b = """{"floatVal":3.14,"active":true,"type":"nkFloat"}""".fromJson(ValueNode)
    c = """{"type":"nkFloat","floatVal":3.14,"active":true}""".fromJson(ValueNode)
    d = """{"active":true,"intVal":42}""".fromJson(ValueNode)
  doAssert a.kind == nkFloat
  doAssert b.kind == nkFloat
  doAssert c.kind == nkFloat
  doAssert d.kind == nkInt

# test https://forum.nim-lang.org/t/7619

type
  FooBar = object
    `Foo Bar`: string

const jsonString = "{\"Foo Bar\": \"Hello World\"}"

proc renameHook*(v: var FooBar, fieldName: var string) =
  if fieldName == "Foo Bar":
    fieldName = "FooBar"

echo jsonString.fromJson(FooBar)
