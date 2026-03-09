import holo_json

doAssertRaises CatchableError:
  var
    reader = initJsonReader()
    n: uint64
  read(reader, n)

for i in 0 .. 10000:
  var s = ""
  dump(s, i)
  doAssert $i == s

for i in 0 .. 10000:
  var s = $i
  var reader = initJsonReader()
  reader.startRead(s)
  var v: int
  read(reader, v)
  doAssert i == v
