import std/json, holo_json, std/strutils, std/tables
const doTimes = not defined(nimscript)
when doTimes:
  import std/times

type Fraction = object
  numerator: int
  denominator: int

proc read(reader: var JsonReader, v: var Fraction) =
  ## Instead of looking for fraction object look for a string.
  var str: string
  read(reader, str)
  let arr = str.split("/")
  v = Fraction()
  v.numerator = parseInt(arr[0])
  v.denominator = parseInt(arr[1])

var frac = """ "1/3" """.fromJson(Fraction)
doAssert frac.numerator == 1
doAssert frac.denominator == 3

when doTimes:
  proc read(reader: var JsonReader, v: var DateTime) =
    var str: string
    read(reader, str)
    v = parse(str, "yyyy-MM-dd hh:mm:ss")

  var dt = """ "2020-01-01 00:00:00" """.fromJson(DateTime)
  doAssert dt.year == 2020

type Entry = object
  id: string
  count: int
  filled: int

let data = """{
  "1": {"count":12, "filled": 11},
  "2": {"count":66, "filled": 0},
  "3": {"count":99, "filled": 99}
}"""

proc read(reader: var JsonReader, v: var seq[Entry]) =
  var table: Table[string, Entry]
  read(reader, table)
  for k, entry in table.mpairs:
    entry.id = k
    v.add(entry)

let s = data.fromJson(seq[Entry])
doAssert type(s) is seq[Entry]
for entry in s:
  if entry.id == "1":
    doAssert entry.count == 12
    doAssert entry.filled == 11
  elif entry.id == "2":
    doAssert entry.count == 66
    doAssert entry.filled == 0
  elif entry.id == "3":
    doAssert entry.count == 99
    doAssert entry.filled == 99

type Entry2 = object
  id: int
  pre: int
  post: int
  kind: string

let data2 = """{
  "id": 3444,
  "changes": [1, 2, "hi"]
}"""

proc read(reader: var JsonReader, v: var Entry2) =
  var entry: JsonNode
  read(reader, entry)
  v = Entry2()
  v.id = entry["id"].getInt()
  v.pre = entry["changes"][0].getInt()
  v.post = entry["changes"][1].getInt()
  v.kind = entry["changes"][2].getStr()

let s2 = data2.fromJson(Entry2)
doAssert type(s2) is Entry2
doAssert $s2 == """(id: 3444, pre: 1, post: 2, kind: "hi")"""

# Non unique / double keys in json
# https://forum.nim-lang.org/t/8787
type Header = object
  key: string
  value: string

proc read(reader: var JsonReader, v: var seq[Header]) =
  if false:
    eatChar(reader, '{')
    while reader.hasNext():
      eatSpace(reader)
      if reader.peekMatch('}'):
        break
      var key, value: string
      read(reader, key)
      eatChar(reader, ':')
      read(reader, value)
      v.add(Header(key: key, value: value))
      eatSpace(reader)
      if reader.nextMatch(','):
        discard
      else:
        break
    eatChar(reader, '}')
  else:
    for key in readObject(reader):
      var value: string
      read(reader, value)
      v.add(Header(key: key, value: value))


let data3 = """{
  "Cache-Control": "private, max-age=0d",
  "Content-Encoding": "brd",
  "Set-Cookie": "name=valued",
  "Set-Cookie": "name=value; name2=value2; name3=value3d"
}"""

let headers = data3.fromJson(seq[Header])
doAssert headers[0].key == "Cache-Control"
doAssert headers[0].value == "private, max-age=0d"
doAssert headers[1].key == "Content-Encoding"
doAssert headers[1].value == "brd"
doAssert headers[2].key == "Set-Cookie"
doAssert headers[2].value == "name=valued"
doAssert headers[3].key == "Set-Cookie"
doAssert headers[3].value == "name=value; name2=value2; name3=value3d"
