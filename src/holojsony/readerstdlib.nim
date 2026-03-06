import ./[readerdef, readerbasic], std/[options, tables, sets]

proc read*[T](reader: var JsonReader, v: var Option[T]) =
  ## Parse an Option.
  mixin read
  eatSpace(reader)
  if reader.nextMatch("null"):
    # v = none(T)?
    return
  var e: T
  read(reader, e)
  v = some(e)

template tableImpl(reader, v, K, V) =
  mixin read
  when v is ref:
    if reader.nextMatch("null"):
      # this is added this time
      return
    new(v)
  eatChar(reader, '{')
  while reader.hasNext():
    eatSpace(reader)
    if reader.peekMatch('}'):
      break
    var key: K
    read(reader, key)
    eatChar(reader, ':')
    var element: V
    read(reader, element)
    v[key] = element
    if reader.nextMatch(','):
      discard
    else:
      break
  eatChar(reader, '}')

proc read*[K: string | enum, V](reader: var JsonReader, v: var Table[K, V]) =
  ## Parse an object.
  tableImpl(reader, v, K, V)

proc read*[K: string | enum, V](reader: var JsonReader, v: var OrderedTable[K, V]) =
  ## Parse an object.
  tableImpl(reader, v, K, V)

proc read*[K: string | enum, V](reader: var JsonReader, v: var TableRef[K, V]) =
  ## Parse an object.
  tableImpl(reader, v, K, V)

proc read*[K: string | enum, V](reader: var JsonReader, v: var OrderedTableRef[K, V]) =
  ## Parse an object.
  tableImpl(reader, v, K, V)

proc read*[K: string | enum](reader: var JsonReader, v: var CountTable[K]) =
  ## Parse an object.
  tableImpl(reader, v, K, int)

proc read*[K: string | enum](reader: var JsonReader, v: var CountTableRef[K]) =
  ## Parse an object.
  tableImpl(reader, v, K, int)

proc read*[T](reader: var JsonReader, v: var HashSet[T]) =
  ## Parses `HashSet`.
  mixin read
  for i in readArray(reader):
    var e: T
    read(reader, e)
    v.incl(e)

proc read*[T](reader: var JsonReader, v: var OrderedSet[T]) =
  ## Parses `OrderedSet`.
  mixin read
  for i in readArray(reader):
    var e: T
    read(reader, e)
    v.incl(e)

proc read*[T](reader: var JsonReader, v: var set[T]) =
  ## Parses the built-in `set` type.
  # separate overload for bitflags or something
  mixin read
  for i in readArray(reader):
    var e: T
    read(reader, e)
    v.incl(e)
