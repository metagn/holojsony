import ./[common, dumperdef, dumperbasic], std/[options, sets, tables]

proc dump*[T](dumper: var JsonDumper, v: Option[T]) {.inline.} =
  if v.isNone:
    dumper.write "null"
  else:
    dumper.dump(v.get())

proc dump*[T](dumper: var JsonDumper, v: SomeSet[T]) =
  var arr: ArrayDump
  dumper.withArrayDump(arr):
    for e in v:
      dumper.withArrayItem(arr):
        dumper.dump(e)

proc dump*[T](dumper: var JsonDumper, v: set[T]) =
  var arr: ArrayDump
  dumper.withArrayDump(arr):
    for e in v:
      dumper.withArrayItem(arr):
        dumper.dump(e)

proc dump*[K: string | enum, V](dumper: var JsonDumper, tab: SomeTable[K, V]) =
  ## Dump an object.
  # not in original jsony
  when tab is ref:
    if isNil(v):
      dumper.write "null"
      return
  var obj: ObjectDump
  dumper.withObjectDump(obj):
    for k, v in tab:
      dumper.withObjectField(obj, $k):
        dumper.dump v
