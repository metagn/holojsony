import ./[dumperdef, dumperbasic], std/[options, sets, tables]

proc dump*[T](dumper: var JsonDumper, v: Option[T]) {.inline.} =
  mixin dump
  if v.isNone:
    dumper.write "null"
  else:
    dumper.dump(v.get())

proc dump*[T](dumper: var JsonDumper, v: HashSet[T]) =
  mixin dump
  var arr: ArrayDump
  dumper.withArrayDump(arr):
    for e in v:
      dumper.withArrayItem(arr):
        dumper.dump(e)

proc dump*[T](dumper: var JsonDumper, v: OrderedSet[T]) =
  mixin dump
  var arr: ArrayDump
  dumper.withArrayDump(arr):
    for e in v:
      dumper.withArrayItem(arr):
        dumper.dump(e)

proc dump*[T](dumper: var JsonDumper, v: set[T]) =
  mixin dump
  var arr: ArrayDump
  dumper.withArrayDump(arr):
    for e in v:
      dumper.withArrayItem(arr):
        dumper.dump(e)

template tableImpl(dumper, tab, K, V) =
  mixin dump
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

proc dump*[K: string | enum, V](dumper: var JsonDumper, tab: Table[K, V]) =
  ## Dump an object.
  tableImpl(dumper, tab, K, V)

proc dump*[K: string | enum, V](dumper: var JsonDumper, tab: TableRef[K, V]) =
  ## Dump an object.
  tableImpl(dumper, tab, K, V)

proc dump*[K: string | enum, V](dumper: var JsonDumper, tab: OrderedTable[K, V]) =
  ## Dump an object.
  tableImpl(dumper, tab, K, V)

proc dump*[K: string | enum, V](dumper: var JsonDumper, tab: OrderedTableRef[K, V]) =
  ## Dump an object.
  tableImpl(dumper, tab, K, V)

proc dump*[K: string | enum](dumper: var JsonDumper, tab: CountTable[K]) =
  ## Dump an object.
  tableImpl(dumper, tab, K, int)

proc dump*[K: string | enum](dumper: var JsonDumper, tab: CountTableRef[K]) =
  ## Dump an object.
  tableImpl(dumper, tab, K, int)
