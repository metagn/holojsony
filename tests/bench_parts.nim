import benchy, eminim, jason, random, streams
import jsony
import holojsony except toJson
when defined(packedjson):
  import packedjson, packedjson/deserialiser
else:
  import json
const status = not defined(gcArc)
when status:
  import serialization
  import json_serialization except Json, toJson

block:
  echo "deserialize string:"
  var jsonStr = "\"hello there how are you?\""
  timeIt "treeform/jsony", 100:
    for i in 0 ..< 1000:
      keep jsony.fromJson(jsonStr, string)

  timeIt "holojsony", 100:
    for i in 0 ..< 1000:
      keep holojsony.fromJson(jsonStr, string)

  when status:
    timeIt "status-im/nim-json-serialization", 100:
      for i in 0 ..< 1000:
        keep json_serialization.Json.decode(jsonStr, string)

block:
  echo "deserialize obj:"
  type Node = ref object
    active: bool
    kind: string
    name: string
    id: int
    kids: seq[Node]
  var node = Node()
  var jsonStr = jsony.toJson(node)
  timeIt "treeform/jsony", 100:
    for i in 0 ..< 1000:
      keep jsony.fromJson(jsonStr, Node)
  timeIt "holojsony", 100:
    for i in 0 ..< 1000:
      keep holojsony.fromJson(jsonStr, Node)

  when status:
    timeIt "status-im/nim-json-serialization", 100:
      for i in 0 ..< 1000:
        keep json_serialization.Json.decode(jsonStr, Node)

block:
  echo "deserialize seq[obj]:"
  type Node = object
    active: bool
    kind: string
    name: string
    id: int
    kids: seq[Node]
  var seqObj: seq[Node]
  for i in 0 ..< 100000:
    seqObj.add(Node())
  var jsonStr = seqObj.toJson()
  timeIt "treeform/jsony", 100:
    keep jsony.fromJson(jsonStr, seq[Node])
  timeIt "holojsony", 100:
    keep holojsony.fromJson(jsonStr, seq[Node])

  when status:
    timeIt "status-im/nim-json-serialization", 100:
      keep json_serialization.Json.decode(jsonStr, seq[Node])

block:
  echo "serialize int:"
  var number42: uint64 = 42

  timeIt "$", 100:
    for i in 0 ..< 1000:
      keep $number42

  timeIt "treeform/jsony", 100:
    for i in 0 ..< 1000:
      keep jsony.toJson(number42)

  timeIt "holojsony", 100:
    for i in 0 ..< 1000:
      keep holojsony.toJson(number42)

  timeIt "holojsony dumper", 100:
    var dumper = initJsonDumper()
    for i in 0 ..< 1000:
      dumper.startDump()
      dumper.dump(number42)
      keep finishDump(dumper)

  timeIt "disruptek/jason", 100:
    for i in 0 ..< 1000:
      keep number42.jason.string

  when status:
    timeIt "status-im/nim-json-serialization", 100:
      for i in 0 ..< 1000:
        keep json_serialization.Json.encode(number42)

block:
  echo "serialize string:"
  var hello = "Hello"

  timeIt "'$'", 100:
    for i in 0 ..< 1000:
      keep '"' & hello & '"'

  timeIt "treeform/jsony", 100:
    for i in 0 ..< 1000:
      keep jsony.toJson(hello)

  timeIt "holojsony", 100:
    for i in 0 ..< 1000:
      keep holojsony.toJson(hello)

  timeIt "holojsony dumper", 100:
    var dumper = initJsonDumper()
    for i in 0 ..< 1000:
      dumper.startDump()
      dumper.dump(hello)
      keep finishDump(dumper)

  timeIt "disruptek/jason", 100:
    for i in 0 ..< 1000:
      keep hello.jason.string

  when status:
    timeIt "status-im/nim-json-serialization", 100:
      for i in 0 ..< 1000:
        keep json_serialization.Json.encode(hello)

block:
  echo "serialize seq:"
  var numArray = @[1, 2, 3, 4, 5, 6, 7, 8, 9]

  timeIt "treeform/jsony", 100:
    for i in 0 ..< 1000:
      keep jsony.toJson(numArray)

  timeIt "holojsony", 100:
    for i in 0 ..< 1000:
      keep holojsony.toJson(numArray)

  timeIt "disruptek/jason", 100:
    for i in 0 ..< 1000:
      keep numArray.jason.string

  when status:
    timeIt "status-im/nim-json-serialization", 100:
      for i in 0 ..< 1000:
        keep json_serialization.Json.encode(numArray)

block:
  echo "serialize obj:"
  type Node = ref object
    active: bool
    kind: string
    name: string
    id: int
    kids: seq[Node]
  var node = Node()

  timeIt "treeform/jsony", 100:
    for i in 0 ..< 1000:
      keep jsony.toJson(node)

  timeIt "holojsony", 100:
    for i in 0 ..< 1000:
      keep holojsony.toJson(node)

  timeIt "disruptek/jason", 100:
    for i in 0 ..< 1000:
      keep node.jason.string

  when status:
    timeIt "status-im/nim-json-serialization", 100:
      for i in 0 ..< 1000:
        keep json_serialization.Json.encode(node)
