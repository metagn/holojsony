import holo_json, std/strutils

type Node = ref object
  kind {.json: "type".}: string

const nodeJson = """{"type":"root"}"""
var node = nodeJson.fromJson(Node)
doAssert node.kind == "root"
doAssert node.toJson() == nodeJson

type
  NodeNumKind = enum # the different node types
    nkInt,           # a leaf with an integer value
    nkFloat,         # a leaf with a float value
  RefNode = ref object
    active: bool
    case kind {.json: "type".}: NodeNumKind # the ``kind`` field is the discriminator
    of nkInt: intVal: int
    of nkFloat: floatVal: float
  ValueNode = object
    active: bool
    case kind {.json: "type".}: NodeNumKind # the ``kind`` field is the discriminator
    of nkInt: intVal: int
    of nkFloat: floatVal: float

# Test renameHook and discriminator Field Name not being first/missing.
block:
  let
    a = """{"active":true,"type":"nkFloat","float_val":3.14}""".fromJson(RefNode)
    b = """{"float_val":3.14,"active":true,"type":"nkFloat"}""".fromJson(RefNode)
    c = """{"type":"nkFloat","float_val":3.14,"active":true}""".fromJson(RefNode)
    d = """{"active":true,"intVal":42}""".fromJson(RefNode)
  doAssert a.kind == nkFloat
  doAssert b.kind == nkFloat
  doAssert c.kind == nkFloat
  doAssert d.kind == nkInt
  doAssert a.toJson().fromJson(RefNode).kind == a.kind
  doAssert b.toJson().fromJson(RefNode).kind == b.kind
  doAssert c.toJson().fromJson(RefNode).kind == c.kind
  doAssert d.toJson().fromJson(RefNode).kind == d.kind

block:
  let
    a = """{"active":true,"type":"nkFloat","float_val":3.14}""".fromJson(ValueNode)
    b = """{"float_al":3.14,"active":true,"type":"nkFloat"}""".fromJson(ValueNode)
    c = """{"type":"nkFloat","float_val":3.14,"active":true}""".fromJson(ValueNode)
    d = """{"active":true,"intVal":42}""".fromJson(ValueNode)
  doAssert a.kind == nkFloat
  doAssert b.kind == nkFloat
  doAssert c.kind == nkFloat
  doAssert d.kind == nkInt
  doAssert a.toJson().fromJson(ValueNode).kind == a.kind
  doAssert b.toJson().fromJson(ValueNode).kind == b.kind
  doAssert c.toJson().fromJson(ValueNode).kind == c.kind
  doAssert d.toJson().fromJson(ValueNode).kind == d.kind

# test https://forum.nim-lang.org/t/7619

type
  FooBar = object
    `Foo Bar` {.json: "Foo Bar".}: string

const jsonString = "{\"Foo Bar\": \"Hello World\"}"

echo jsonString.fromJson(FooBar)
echo jsonString.fromJson(FooBar).toJson()
