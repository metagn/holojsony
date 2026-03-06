import holonomy_jsony/objvar
import std/[json, options, parseutils, sets, strutils, tables, typetraits, unicode]
import hemodyne/[syncvein, syncartery]

type
  SomeTable*[K, V] = Table[K, V] | OrderedTable[K, V] |
    TableRef[K, V] | OrderedTableRef[K, V]
  RawJson* = distinct string
  JsonError* = object of ValueError

# reader:

type
  JsonReaderOptions* = object
    handleUtf16*: bool
      ## jsony converts utf 16 characters in strings by default apparently this is now opt in
    forceUtf8Strings*: bool
      ## jsony errors if binary data in strings is not utf8, this is now opt in
  JsonReader* = object
    options*: JsonReaderOptions
    vein*: Vein
    bufferLocks*: int
    bufferPos*: int
    line*, column*: int

# XXX go over inlines later do it manually

proc initJsonReader*(options = JsonReaderOptions()): JsonReader =
  result = JsonReader(options: options)

proc startRead*(reader: var JsonReader, vein: Vein) =
  reader.vein = vein
  reader.bufferPos = -1
  reader.bufferLocks = 0
  reader.line = 1
  reader.column = 1

proc startRead*(reader: var JsonReader, str: string) =
  reader.startRead(initVein(str))

# ----- reader internals ----

template error*(reader: var JsonReader, msg: string) =
  ## Shortcut to raise an exception.
  raise newException(JsonError, "(" & $reader.line & ", " & $reader.column & ") " & msg)

proc extendBufferOne*(reader: var JsonReader) =
  let remove = reader.vein.extendBufferOne()
  reader.bufferPos -= remove

proc extendBufferBy*(reader: var JsonReader, n: int) =
  let remove = reader.vein.extendBufferBy(n)
  reader.bufferPos -= remove

proc peek*(reader: var JsonReader, c: var char): bool =
  let nextPos = reader.bufferPos + 1
  if nextPos < reader.vein.buffer.len:
    c = reader.vein.buffer[nextPos]
    result = true
  else:
    reader.extendBufferOne()
    if nextPos < reader.vein.buffer.len:
      c = reader.vein.buffer[nextPos]
      result = true
    else:
      result = false

proc unsafePeek*(reader: var JsonReader): char =
  result = reader.vein.buffer[reader.bufferPos + 1]

proc peek*(reader: var JsonReader, c: var char, offset: int): bool =
  let nextPos = reader.bufferPos + 1 + offset
  if nextPos < reader.vein.buffer.len:
    c = reader.vein.buffer[nextPos]
    result = true
  else:
    reader.extendBufferBy(1 + offset)
    if nextPos < reader.vein.buffer.len:
      c = reader.vein.buffer[nextPos]
      result = true
    else:
      result = false

proc unsafePeek*(reader: var JsonReader, offset: int): char =
  result = reader.vein.buffer[reader.bufferPos + 1 + offset]

proc peek*(reader: var JsonReader, cs: var openArray[char]): bool =
  let n = cs.len
  if reader.bufferPos + n >= reader.vein.buffer.len:
    reader.extendBufferBy(n)
  if reader.bufferPos + n < reader.vein.buffer.len:
    for i in 0 ..< n:
      cs[i] = reader.vein.buffer[reader.bufferPos + 1 + i]

proc peekOrZero*(reader: var JsonReader): char =
  if not peek(reader, result):
    result = '\0'

proc hasNext*(reader: var JsonReader): bool =
  var dummy: char
  result = peek(reader, dummy)

proc hasNext*(reader: var JsonReader, offset: int): bool =
  var dummy: char
  result = peek(reader, dummy, offset)

proc lockBuffer*(reader: var JsonReader) =
  inc reader.bufferLocks

proc unlockBuffer*(reader: var JsonReader) =
  assert reader.bufferLocks > 0, "unpaired buffer unlock"
  dec reader.bufferLocks

proc unsafeNext*(reader: var JsonReader) =
  # keep separate from next for now
  let prevPos = reader.bufferPos
  inc reader.bufferPos
  let c = reader.vein.buffer[reader.bufferPos]
  if c == '\n' or (c == '\r' and reader.peekOrZero() != '\n'):
    inc reader.line
    reader.column = 1
  else:
    inc reader.column
  if reader.bufferLocks == 0: reader.vein.setFreeBefore(prevPos)

proc next*(reader: var JsonReader, c: var char): bool =
  # keep separate from unsafeNext for now
  if not peek(reader, c):
    return false
  let prevPos = reader.bufferPos
  inc reader.bufferPos
  if c == '\n' or (c == '\r' and reader.peekOrZero() != '\n'):
    inc reader.line
    reader.column = 1
  else:
    inc reader.column
  if reader.bufferLocks == 0: reader.vein.setFreeBefore(prevPos)
  result = true

proc next*(reader: var JsonReader): bool =
  var dummy: char
  result = next(reader, dummy)

iterator peekNext*(reader: var JsonReader): char =
  var c: char
  while reader.peek(c):
    yield c
    reader.unsafeNext()

proc peekMatch*(reader: var JsonReader, c: char): bool =
  var c2: char
  if reader.peek(c2) and c2 == c:
    result = true
  else:
    result = false

proc nextMatch*(reader: var JsonReader, c: char): bool =
  result = peekMatch(reader, c)
  if result:
    reader.unsafeNext()

proc peekMatch*(reader: var JsonReader, c: char, offset: int): bool =
  if reader.bufferPos + 1 + offset >= reader.vein.buffer.len:
    reader.extendBufferBy(1 + offset)
  if reader.bufferPos + 1 + offset < reader.vein.buffer.len:
    if c != reader.vein.buffer[reader.bufferPos + 1 + offset]:
      return false
    result = true
  else:
    result = false

proc peekMatch*(reader: var JsonReader, cs: set[char], c: var char): bool =
  if reader.peek(c) and c in cs:
    result = true
  else:
    result = false

proc nextMatch*(reader: var JsonReader, cs: set[char], c: var char): bool =
  result = peekMatch(reader, cs, c)
  if result:
    reader.unsafeNext()

proc peekMatch*(reader: var JsonReader, cs: set[char]): bool =
  var dummy: char
  result = reader.peekMatch(cs, dummy)

proc nextMatch*(reader: var JsonReader, cs: set[char]): bool =
  var dummy: char
  result = reader.nextMatch(cs, dummy)

proc peekMatch*(reader: var JsonReader, cs: set[char], offset: int, c: var char): bool =
  if reader.bufferPos + 1 + offset >= reader.vein.buffer.len:
    reader.extendBufferBy(1 + offset)
  if reader.bufferPos + 1 + offset < reader.vein.buffer.len:
    let c2 = reader.vein.buffer[reader.bufferPos + 1 + offset]
    if c2 in cs:
      c = c2
      return false
    result = true
  else:
    result = false

proc peekMatch*(reader: var JsonReader, cs: set[char], offset: int): bool =
  var dummy: char
  result = reader.peekMatch(cs, offset, dummy)

proc peekMatch*(reader: var JsonReader, str: string): bool =
  if reader.bufferPos + str.len >= reader.vein.buffer.len:
    reader.extendBufferBy(str.len)
  if reader.bufferPos + str.len < reader.vein.buffer.len:
    for i in 0 ..< str.len:
      if str[i] != reader.vein.buffer[reader.bufferPos + 1 + i]:
        return false
    result = true
  else:
    result = false

proc nextMatch*(reader: var JsonReader, str: string): bool =
  result = peekMatch(reader, str)
  if result:
    for i in 0 ..< str.len:
      reader.unsafeNext()

# ----- end reader internals ----

# XXX make sure "wrong parses" are properly dealt with, ie if it expects a integer and receives "123abc" it should not parse 123 and be done with it

proc read*[T](reader: var JsonReader, v: var seq[T])
proc read*[T: enum](reader: var JsonReader, v: var T)
proc read*[T: object|ref object](reader: var JsonReader, v: var T)
proc read*[K: string | enum, V](reader: var JsonReader, v: var SomeTable[K, V])
proc read*[T](reader: var JsonReader, v: var (SomeSet[T]|set[T]))
proc read*[T: tuple](reader: var JsonReader, v: var T)
proc read*[T: array](reader: var JsonReader, v: var T)
proc read*[T: not object](reader: var JsonReader, v: var ref T)
proc read*(reader: var JsonReader, v: var JsonNode)
proc read*(reader: var JsonReader, v: var char)
proc read*[T: distinct](reader: var JsonReader, v: var T)

template eatSpace*(reader: var JsonReader) =
  ## Will consume whitespace.
  for c in reader.peekNext():
    if c notin Whitespace:
      break

proc eatChar*(reader: var JsonReader, c: char) {.inline.} =
  ## Will consume space before and then the character `c`.
  ## Will raise an exception if `c` is not found.
  eatSpace(reader)
  var c2: char
  if not reader.next(c2):
    reader.error("Expected " & c & " but end reached.")
  elif c != c2:
    reader.error("Expected " & c & " but got " & c2 & " instead.")

proc parseSymbol*(reader: var JsonReader): string =
  ## Will read a symbol and return it.
  ## Used for numbers and booleans.
  # XXX numbers??
  eatSpace(reader)
  result = ""
  for c in reader.peekNext():
    case c
    of ',', '}', ']', Whitespace:
      break
    else:
      result.add c

proc read*(reader: var JsonReader, v: var bool) =
  ## Will parse boolean true or false.
  when nimvm:
    # XXX other should be fine for nimvm but test
    case parseSymbol(reader)
    of "true":
      v = true
    of "false":
      v = false
    else:
      reader.error("Boolean true or false expected.")
  else:
    # Its faster to do char by char scan:
    eatSpace(reader)
    if reader.nextMatch("true"):
      v = true
    elif reader.nextMatch("false"):
      v = false
    else:
      reader.error("Boolean true or false expected.")

proc read*(reader: var JsonReader, v: var SomeUnsignedInt) =
  ## Will parse unsigned integers.
  when nimvm:
    v = type(v)(parseBiggestUInt(parseSymbol(reader)))
  else:
    eatSpace(reader)
    if reader.nextMatch('+'):
      discard
    var
      v2: uint64 = 0
      gotChar = false
    while c in reader.peekNext():
      case c
      of '0'..'9':
        gotChar = true
        v2 = v2 * 10 + (c.ord - '0'.ord).uint64
      else:
        break
    if not gotChar:
      reader.error("Number expected.")
    v = type(v)(v2)

proc read*(reader: var JsonReader, v: var SomeSignedInt) =
  ## Will parse signed integers.
  when nimvm:
    v = type(v)(parseBiggestInt(parseSymbol(reader)))
  else:
    eatSpace(reader)
    if reader.nextMatch('+'):
      discard
    if reader.nextMatch('-'):
      var v2: uint64
      read(reader, v2)
      v = -type(v)(v2)
    else:
      var v2: uint64
      read(reader, v2)
      try:
        v = type(v)(v2)
      except:
        # XXX why here but not above?
        reader.error("Number type to small to contain the number.")

proc read*(reader: var JsonReader, v: var SomeFloat) =
  ## Will parse float32 and float64.
  eatSpace(reader)
  # build float string based on acceptable characters:
  var s = ""
  block sign:
    var sign: char
    if reader.nextMatch({'-', '+'}, sign):
      s.add sign
  block integerPart:
    for c in reader.peekNext():
      case c
      of '0'..'9': s.add c
      else: break
  block decimalPoint:
    if reader.peekMatch('.') and reader.peekMatch({'0'..'9'}, offset = 1):
      s.add '.'
      reader.unsafeNext()
      for c in reader.peekNext():
        case c
        of '0'..'9': s.add c
        else: break
  block exponent:
    var hasSign = false
    if reader.peekMatch({'e', 'E'}):
      var digitOffset = 1
      hasSign = reader.peekMatch({'+', '-'}, offset = 1)
      if hasSign:
        inc digitOffset
      if reader.peekMatch({'0'..'9'}, offset = digitOffset):
        s.add reader.next() # e/E
        if hasSign: s.add reader.next()
        for c in reader.peekNext():
          case c
          of '0'..'9': s.add c
          else: break
  var i = 0
  var f: float
  let chars = parseutils.parseFloat(s, f, i)
  if chars == 0:
    reader.error("Failed to parse a float.")
  for i in 0..<chars:
    reader.unsafeNext()
  v = f

proc validRune(reader: var JsonReader, rune: var Rune, start: char): int =
  # returns number of skipped bytes
  # Based on fastRuneAt from std/unicode
  result = 0

  template ones(n: untyped): untyped = ((1 shl n)-1)

  let startByte = start.byte
  if startByte <= 127:
    result = 1
    rune = Rune(startByte)
  elif startByte shr 5 == 0b110:
    var bytes: array[2, char]
    if reader.peek(bytes):
      let valid = (uint(bytes[1]) shr 6 == 0b10)
      if valid:
        result = 2
        rune = Rune(
          (uint(bytes[0]) and ones(5)) shl 6 or
          (uint(bytes[1]) and ones(6))
        )
  elif startByte shr 4 == 0b1110:
    var bytes: array[3, char]
    if reader.peek(bytes):
      let valid =
        (uint(bytes[1]) shr 6 == 0b10) and
        (uint(bytes[2]) shr 6 == 0b10)
      if valid:
        result = 3
        rune = Rune(
          (uint(bytes[0]) and ones(4)) shl 12 or
          (uint(bytes[1]) and ones(6)) shl 6 or
          (uint(bytes[2]) and ones(6))
        )
  elif startByte shr 3 == 0b11110:
    var bytes: array[4, char]
    if reader.peek(bytes):
      let valid =
        (uint(bytes[1]) shr 6 == 0b10) and
        (uint(bytes[2]) shr 6 == 0b10) and
        (uint(bytes[3]) shr 6 == 0b10)
      if valid:
        result = 4
        rune = Rune(
          (uint(bytes[0]) and ones(3)) shl 18 or
          (uint(bytes[1]) and ones(6)) shl 12 or
          (uint(bytes[2]) and ones(6)) shl 6 or
          (uint(bytes[3]) and ones(6))
        )

proc parseUnicodeEscape(reader: var JsonReader): int =
  # uXXXX
  #reader.unsafeNext() # u already skipped
  var hexStr = newString(4)
  if not reader.peek(hexStr):
    reader.error("Expected unicode escape hex but end reached.")
  for i in 1..hexStr.len: reader.unsafeNext()
  result = parseHexInt(hexStr)
  if reader.options.handleUtf16:
    # Deal with UTF-16 surrogates. Most of the time strings are encoded as utf8
    # but some APIs will reply with UTF-16 surrogate pairs which needs to be dealt
    # with.
    if (result and 0xfc00) == 0xd800:
      if not reader.nextMatch("\\u"):
        # maybe make the option an enum for whether or not to error here
        reader.error("Found an Orphan Surrogate.")
      var nextHexStr = newString(4)
      if not reader.peek(nextHexStr):
        reader.error("Expected unicode escape hex but end reached.")
      for i in 1..nextHexStr.len: reader.unsafeNext()
      let nextRune = parseHexInt(nextHexStr)
      if (nextRune and 0xfc00) == 0xdc00:
        result = 0x10000 + (((result - 0xd800) shl 10) or (nextRune - 0xdc00))

proc read*(reader: var JsonReader, v: var string) =
  ## Parse string.
  eatSpace(reader)
  if reader.nextMatch("null"):
    # XXX v = ""? allow null or not? configured by user?
    return

  eatChar(reader, '"')

  var
    copyStart = 0
    inCopy = false
  template enterCopy() =
    if not inCopy:
      reader.lockBuffer()
      copyStart = reader.bufferPos
      inCopy = true
  template finishCopy() =
    if inCopy:
      if reader.bufferPos > copyStart:
        let numBytes = reader.bufferPos - copyStart
        when nimvm:
          for p in 0 ..< numBytes:
            v.add reader.vein.buffer[copyStart + p]
        else:
          when defined(js):
            for p in 0 ..< numBytes:
              v.add reader.vein.buffer[copyStart + p]
          else:
            let vLen = v.len
            v.setLen(vLen + numBytes)
            copyMem(v[vLen].addr, reader.vein.buffer[copyStart].unsafeAddr, numBytes)
      reader.unlockBuffer()
      inCopy = false
  try:
    var c: char
    while reader.peek(c):
      if reader.options.forceUtf8Strings and (cast[uint8](c) and 0b10000000) != 0: # Multi-byte characters
        var r: Rune
        let byteCount = reader.validRune(r, c)
        if byteCount != 0:
          for _ in 1..byteCount: reader.unsafeNext()
        else: # Not a valid rune
          reader.error("Found invalid UTF-8 character.")
      else:
        # When the high bit is not set this is a single-byte character (ASCII)
        case c
        of '"':
          break
        of '\\':
          if not reader.hasNext(offset = 1):
            reader.error("Expected escaped character but end reached.")
          finishCopy()
          reader.unsafeNext() # first \
          let c = reader.unsafePeek()
          reader.unsafeNext() # escape character
          case c
          of '"', '\\', '/': v.add(c)
          of 'b': v.add '\b'
          of 'f': v.add '\f'
          of 'n': v.add '\n'
          of 'r': v.add '\r'
          of 't': v.add '\t'
          of 'u':
            v.add(Rune(parseUnicodeEscape(reader)))
          else:
            v.add(c)
        else:
          enterCopy()
  finally:
    finishCopy()

  eatChar(reader, '"')

proc read*(reader: var JsonReader, v: var char) =
  var str: string
  reader.read(str)
  if str.len != 1:
    reader.error("String can't fit into a char.")
  v = str[0]

proc read*[T](reader: var JsonReader, v: var seq[T]) =
  ## Parse seq.
  eatChar(reader, '[')
  while reader.hasNext():
    eatSpace(reader)
    if reader.peekMatch(']'):
      break
    var element: T
    read(reader, element)
    v.add(element)
    eatSpace(reader)
    if reader.nextMatch(','):
      discard
    else:
      break
  eatChar(reader, ']')

proc read*[T: array](reader: var JsonReader, v: var T) =
  eatSpace(reader)
  eatChar(reader, '[')
  var i = 0
  for value in v.mitems:
    inc i
    eatSpace(reader)
    if reader.peekMatch(']'):
      reader.error("expected " & $i & "th element in array of len " & $len(v))
    read(reader, value)
    eatSpace(reader)
    if reader.nextMatch(','):
      discard
    elif reader.peekMatch(']'):
      # if it has a next element it will fail above
      discard
    else:
      # maybe improve error message wasnt in original
      reader.error("expected comma")
  eatChar(reader, ']')

proc read*[T: not object](reader: var JsonReader, v: var ref T) =
  eatSpace(reader)
  if reader.nextMatch("null"):
    # v = nil here? would be pretty unambiguous unlike string case
    return
  new(v)
  read(reader, v[])

proc skipValue*(reader: var JsonReader) =
  ## Used to skip values of extra fields.
  eatSpace(reader)
  if reader.nextMatch('{'):
    while reader.hasNext():
      eatSpace(reader)
      if reader.peekMatch('}'):
        break
      skipValue(reader)
      eatChar(reader, ':')
      skipValue(reader)
      eatSpace(reader)
      if reader.nextMatch(','):
        discard
    eatChar(reader, '}')
  elif reader.nextMatch('['):
    while reader.hasNext():
      eatSpace(reader)
      if reader.peekMatch(']'):
        break
      skipValue(reader)
      eatSpace(reader)
      if reader.nextMatch(','):
        discard
    eatChar(reader, ']')
  elif reader.peekMatch('"'):
    var str: string
    read(reader, str)
  else:
    discard parseSymbol(reader)

proc snakeCaseDynamic(s: string): string =
  if s.len == 0:
    return
  var prevCap = false
  for i, c in s:
    if c in {'A'..'Z'}:
      if result.len > 0 and result[result.len-1] != '_' and not prevCap:
        result.add '_'
      prevCap = true
      result.add c.toLowerAscii()
    else:
      prevCap = false
      result.add c

template snakeCase(s: string): string =
  const k = snakeCaseDynamic(s)
  k

proc parseObjectInner[T](reader: var JsonReader, v: var T) =
  while reader.hasNext():
    eatSpace(reader)
    if reader.peekNext('}'):
      break
    var key: string
    read(reader, key)
    eatChar(reader, ':')
    # XXX most important change to go here: scan pragma for more general field options, which could also be hooked into
    when compiles(renameHook(v, key)):
      renameHook(v, key)
    block all:
      # XXX maybe optimize this to case with a macro, unlikely that name style changes in representation
      for k, v in v.fieldPairs:
        if k == key or snakeCase(k) == key:
          var v2: type(v)
          read(reader, v2)
          v = v2
          break all
      skipValue(reader)
    eatSpace(reader)
    if reader.nextMatch(','):
      discard
    else:
      break
  when compiles(postHook(v)):
    postHook(v)

proc read*[T: tuple](reader: var JsonReader, v: var T) =
  eatSpace(reader)
  when T.isNamedTuple():
    if reader.nextMatch('{'):
      parseObjectInner(reader, v)
      eatChar(reader, '}')
      return
  eatChar(reader, '[')
  for name, value in v.fieldPairs:
    eatSpace(reader)
    read(reader, value)
    eatSpace(reader)
    if reader.nextMatch(','):
      discard
  eatChar(reader, ']')

proc read*[T: enum](reader: var JsonReader, v: var T) =
  eatSpace(reader)
  var strV: string
  if reader.peekMatch('"'):
    read(reader, strV)
    when compiles(enumHook(strV, v)):
      enumHook(strV, v)
    else:
      try:
        v = parseEnum[T](strV)
      except:
        reader.error("Can't parse enum.")
  else:
    try:
      strV = parseSymbol(reader)
      v = T(parseInt(strV))
    except:
      reader.error("Can't parse enum.")

proc read*[T: object|ref object](reader: var JsonReader, v: var T) =
  ## Parse an object or ref object.
  eatSpace(reader)
  if reader.nextMatch("null"):
    # v = nil here? ambivalence makes it suspicious
    return
  eatChar(reader, '{')
  when not v.isObjectVariant:
    when compiles(newHook(v)):
      newHook(v)
    elif compiles(new(v)):
      new(v)
  else:
    # Try looking for the discriminatorFieldName, then parse as normal object.
    eatSpace(reader)
    reader.lockBuffer()
    var saveI = reader.bufferPos
    try:
      while reader.hasNext():
        var key: string
        read(reader, key)
        eatChar(reader, ':')
        when compiles(renameHook(v, key)):
          renameHook(v, key)
        if key == v.discriminatorFieldName:
          var discriminator: type(v.discriminatorField)
          read(reader, discriminator)
          new(v, discriminator)
          when compiles(newHook(v)):
            newHook(v)
          break
        skipValue(reader)
        if not reader.peekMatch('}'):
          # needs space skipped above?
          eatChar(reader, ',')
        else:
          when compiles(newHook(v)):
            newHook(v)
          elif compiles(new(v)):
            new(v)
          break
    finally:
      reader.bufferPos = saveI
      reader.unlockBuffer()
  parseObjectInner(reader, v)
  eatChar(reader, '}')

proc read*[T](reader: var JsonReader, v: var Option[T]) =
  ## Parse an Option.
  eatSpace(reader)
  if reader.nextMatch("null"):
    # v = none(T)?
    return
  var e: T
  read(reader, e)
  v = some(e)

proc read*[K: string | enum, V](reader: var JsonReader, v: var SomeTable[K, V]) =
  ## Parse an object.
  when compiles(new(v)):
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

proc read*[T](reader: var JsonReader, v: var (SomeSet[T]|set[T])) =
  ## Parses `HashSet`, `OrderedSet`, or a built-in `set` type.
  eatSpace(reader)
  eatChar(reader, '[')
  while reader.hasNext():
    eatSpace(reader)
    if reader.peekMatch(']'):
      break
    var e: T
    read(reader, e)
    v.incl(e)
    eatSpace(reader)
    if reader.nextMatch(','):
      discard
  eatChar(reader, ']')

proc read*(reader: var JsonReader, v: var JsonNode) =
  ## Parses a regular json node.
  eatSpace(reader)
  if reader.peekMatch('{'):
    v = newJObject()
    eatChar(reader, '{')
    while reader.hasNext():
      eatSpace(reader)
      if reader.peekMatch('}'):
        break
      var k: string
      read(reader, k)
      eatChar(reader, ':')
      var e: JsonNode
      read(reader, e)
      v[k] = e
      eatSpace(reader)
      if reader.nextMatch(','):
        discard
    eatChar(reader, '}')
  elif reader.peekMatch('['):
    v = newJArray()
    eatChar(reader, '[')
    while reader.hasNext():
      eatSpace(reader)
      if reader.peekMatch(']'):
        break
      var e: JsonNode
      read(reader, e)
      v.add(e)
      eatSpace(reader)
      if reader.nextMatch(','):
        discard
    eatChar(reader, ']')
  elif reader.peekMatch('"'):
    var str: string
    read(reader, str)
    v = newJString(str)
  else:
    var data = parseSymbol(reader)
    if data == "null":
      v = newJNull()
    elif data == "true":
      v = newJBool(true)
    elif data == "false":
      v = newJBool(false)
    elif data.len > 0 and data[0] in {'0'..'9', '-', '+'}:
      try:
        v = newJInt(parseInt(data))
      except ValueError:
        try:
          v = newJFloat(parseFloat(data))
        except ValueError:
          reader.error("Invalid number.")
    else:
      reader.error("Unexpected.")

proc read*[T: distinct](reader: var JsonReader, v: var T) =
  var x: T.distinctBase
  read(reader, x)
  v = cast[T](x)

proc fromJson*[T](s: string, x: typedesc[T]): T =
  ## Takes json and outputs the object it represents.
  ## * Extra json fields are ignored.
  ## * Missing json fields keep their default values.
  ## * `proc newHook(foo: var ...)` Can be used to populate default values.
  result = default(T)
  var reader = initJsonReader()
  reader.startRead(s)
  reader.read(result)
  eatSpace(reader)
  if reader.hasNext():
    reader.error("Found non-whitespace character after JSON data.")

proc fromJson*(s: string): JsonNode =
  ## Takes json parses it into `JsonNode`s.
  var reader = initJsonReader()
  reader.startRead(s)
  reader.read(result)
  eatSpace(reader)
  if reader.hasNext():
    reader.error("Found non-whitespace character after JSON data.")

# dumper:

type
  JsonDumperOptions* = object
    keepUtf8*: bool
      ## keeps valid utf 8 codepoints in strings as-is instead of encoding an escape sequence 
    useXEscape*: bool
      ## uses \x instead of \u for characters known to be small, not in json standard
  JsonDumper* = object
    options*: JsonDumperOptions
    artery*: Artery # for like buffering writing to a file
    flushLocks*: int
    flushPos*: int

proc initJsonDumper*(options = JsonDumperOptions()): JsonDumper =
  result = JsonDumper(options: options)

proc lockFlush*(dumper: var JsonDumper) =
  inc dumper.flushLocks

proc unlockFlush*(dumper: var JsonDumper) =
  assert dumper.flushLocks > 0, "unpaired flush unlock"
  dec dumper.flushLocks

proc startDump*(dumper: var JsonDumper, artery: Artery) =
  dumper.artery = artery
  dumper.flushLocks = 0
  dumper.flushPos = 0

proc startDump*(dumper: var JsonDumper) =
  dumper.startDump(Artery(buffer: "", bufferConsumer: nil))

proc finishDump*(dumper: var JsonDumper): string =
  ## returns leftover buffer
  assert dumper.flushLocks == 0, "unpaired flush lock"
  dumper.flushPos += dumper.artery.flushBufferFull(dumper.flushPos)
  if dumper.flushPos < dumper.artery.buffer.len:
    result = dumper.artery.buffer[dumper.flushPos ..< dumper.artery.buffer.len]
  else:
    result = ""

proc addToBuffer*(dumper: var JsonDumper, c: char) =
  dumper.flushPos -= dumper.artery.addToBuffer(c)

proc addToBuffer*(dumper: var JsonDumper, s: sink string) =
  dumper.flushPos -= dumper.artery.addToBuffer(s)

proc flushBuffer*(dumper: var JsonDumper) =
  # XXX maybe pick a better word, maybe "flow" or just "send" to be boring
  #dumper.artery.flushBufferOnce(bufferPos)
  dumper.flushPos += dumper.artery.flushBuffer(dumper.flushPos)
  if dumper.flushLocks == 0: dumper.artery.freeAfter = dumper.flushPos

proc write*(dumper: var JsonDumper, c: char) =
  dumper.addToBuffer(c)
  dumper.flushBuffer()

proc write*(dumper: var JsonDumper, s: sink string) =
  dumper.addToBuffer(s)
  dumper.flushBuffer()

proc dump*(dumper: var JsonDumper, v: bool)
proc dump*(dumper: var JsonDumper, v: uint|uint8|uint16|uint32|uint64)
proc dump*(dumper: var JsonDumper, v: int|int8|int16|int32|int64)
proc dump*(dumper: var JsonDumper, v: SomeFloat)
proc dump*(dumper: var JsonDumper, v: string)
proc dump*(dumper: var JsonDumper, v: char)
proc dump*(dumper: var JsonDumper, v: tuple)
proc dump*(dumper: var JsonDumper, v: enum)
type t[T] = tuple[a: string, b: T]
proc dump*[N, T](dumper: var JsonDumper, v: array[N, t[T]])
proc dump*[N, T](dumper: var JsonDumper, v: array[N, T])
proc dump*[T](dumper: var JsonDumper, v: seq[T])
proc dump*(dumper: var JsonDumper, v: object)
proc dump*(dumper: var JsonDumper, v: ref)
proc dump*[T: distinct](dumper: var JsonDumper, v: T)

proc dump*[T: distinct](dumper: var JsonDumper, v: T) =
  var x = cast[T.distinctBase](v)
  dumper.dump(x)

proc dump*(dumper: var JsonDumper, v: bool) =
  if v:
    dumper.write "true"
  else:
    dumper.write "false"

const lookup = block:
  ## Generate 00, 01, 02 ... 99 pairs.
  var s = ""
  for i in 0 ..< 100:
    if ($i).len == 1:
      s.add("0")
    s.add($i)
  s

proc dumpNumberSlow(dumper: var JsonDumper, v: uint|uint8|uint16|uint32|uint64) =
  dumper.write $v.uint64

proc dumpNumberFast(dumper: var JsonDumper, v: uint|uint8|uint16|uint32|uint64) =
  # Its faster to not allocate a string for a number,
  # but to write it out the digits directly.
  # XXX can we just use addInt
  if v == 0:
    dumper.write '0'
    return
  # Max size of a uin64 number is 20 digits.
  var digits: array[20, char]
  var v = v
  var p = 0
  while v != 0:
    # Its faster to look up 2 digits at a time, less int divisions.
    let idx = v mod 100
    digits[p] = lookup[idx*2+1]
    inc p
    digits[p] = lookup[idx*2]
    inc p
    v = v div 100
  var at = dumper.artery.buffer.len
  if digits[p-1] == '0':
    dec p
  dumper.artery.buffer.setLen(dumper.artery.buffer.len + p)
  dec p
  while p >= 0:
    dumper.artery.buffer[at] = digits[p]
    dec p
    inc at
  dumper.flushBuffer()

proc dump*(dumper: var JsonDumper, v: uint|uint8|uint16|uint32|uint64) =
  when nimvm:
    dumper.dumpNumberSlow(v)
  else:
    when defined(js):
      dumper.dumpNumberSlow(v)
    else:
      dumper.dumpNumberFast(v)

proc dump*(dumper: var JsonDumper, v: int|int8|int16|int32|int64) =
  if v < 0:
    dumper.write '-'
    dump(dumper, 0.uint64 - v.uint64)
  else:
    dump(dumper, v.uint64)

proc dump*(dumper: var JsonDumper, v: SomeFloat) =
  #dumper.write $v # original jsony
  dumper.artery.buffer.addFloat(v)
  dumper.flushBuffer()

proc validRuneAt(s: string, i: int, rune: var Rune): int =
  # returns number of skipped bytes
  # Based on fastRuneAt from std/unicode
  result = 0

  template ones(n: untyped): untyped = ((1 shl n)-1)

  if uint(s[i]) <= 127:
    result = 1
    rune = Rune(uint(s[i]))
  elif uint(s[i]) shr 5 == 0b110:
    if i <= s.len - 2:
      let valid = (uint(s[i+1]) shr 6 == 0b10)
      if valid:
        result = 2
        rune = Rune(
          (uint(s[i]) and (ones(5))) shl 6 or
          (uint(s[i+1]) and ones(6))
        )
  elif uint(s[i]) shr 4 == 0b1110:
    if i <= s.len - 3:
      let valid =
        (uint(s[i+1]) shr 6 == 0b10) and
        (uint(s[i+2]) shr 6 == 0b10)
      if valid:
        result = 3
        rune = Rune(
          (uint(s[i]) and ones(4)) shl 12 or
          (uint(s[i+1]) and ones(6)) shl 6 or
          (uint(s[i+2]) and ones(6))
        )
  elif uint(s[i]) shr 3 == 0b11110:
    if i <= s.len - 4:
      let valid =
        (uint(s[i+1]) shr 6 == 0b10) and
        (uint(s[i+2]) shr 6 == 0b10) and
        (uint(s[i+3]) shr 6 == 0b10)
      if valid:
        result = 4
        rune = Rune(
          (uint(s[i]) and ones(3)) shl 18 or
          (uint(s[i+1]) and ones(6)) shl 12 or
          (uint(s[i+2]) and ones(6)) shl 6 or
          (uint(s[i+3]) and ones(6))
        )

proc dump*(dumper: var JsonDumper, v: string) =
  dumper.write '"'

  var
    i = 0
    copyStart = 0
    inCopy = false
  template enterCopy() =
    if not inCopy:
      copyStart = i
      inCopy = true
  template finishCopy() =
    if inCopy:
      if copyStart > i:
        let numBytes = i - copyStart
        when nimvm:
          for p in 0 ..< numBytes:
            dumper.artery.buffer.add v[copyStart + p]
        else:
          when defined(js):
            for p in 0 ..< numBytes:
              dumper.artery.buffer.add v[copyStart + p]
          else:
            let sLen = dumper.artery.buffer.len
            dumper.artery.buffer.setLen(sLen + numBytes)
            copyMem(dumper.artery.buffer[sLen].addr, v[copyStart].unsafeAddr, numBytes)
        dumper.flushBuffer()
      inCopy = false
  try:
    while i < v.len:
      const hex = [
        '0', '1', '2', '3', '4', '5', '6', '7',
        '8', '9', 'a', 'b', 'c', 'd', 'e', 'f']
      let c = v[i]
      if (cast[uint8](c) and 0b10000000) == 0:
        # When the high bit is not set this is a single-byte character (ASCII)
        # Does this character need escaping?
        if c < 32.char or c == '\\' or c == '"':
          finishCopy()
          case c:
          of '\\': dumper.write r"\\"
          of '\b': dumper.write r"\b"
          of '\f': dumper.write r"\f"
          of '\n': dumper.write r"\n"
          of '\r': dumper.write r"\r"
          of '\t': dumper.write r"\t"
          of '\v':
            if dumper.options.useXEscape:
              dumper.write r"\x0b"
            else:
              dumper.write r"\u000b"
          of '"': dumper.write r"\"""
          of '\0'..'\7', '\14'..'\31':
            if dumper.options.useXEscape:
              dumper.write r"\x"
            else:
              dumper.write r"\u00"
            dumper.write hex[c.int shr 4]
            dumper.write hex[c.int and 0xf]
          else:
            discard # Not possible
          inc i
        else:
          enterCopy()
          inc i
      else: # Multi-byte characters
        var r = 0
        if dumper.options.keepUtf8:
          var rune: Rune # not used apparently
          r = v.validRuneAt(i, rune)
        if r != 0:
          enterCopy()
          i += r
        else: # Not a valid rune, use replacement character 
          finishCopy()
          when false:
            s.add Rune(0xfffd) # XXX ??? this is just bad
          if dumper.options.useXEscape:
            dumper.write r"\x"
          else:
            dumper.write r"\u00"
          dumper.write hex[c.int shr 4]
          dumper.write hex[c.int and 0xf]
          inc i
          copyStart = i
  finally:
    finishCopy()

  dumper.write '"'

template dumpKey(dumper: var JsonDumper, v: string) =
  const v2 = jsony.toJson(v) & ":"
  dumper.write v2

proc dump*(dumper: var JsonDumper, v: char) =
  dumper.write '"'
  dumper.write v
  dumper.write '"'

proc dump*(dumper: var JsonDumper, v: tuple) =
  dumper.write '['
  var i = 0
  for _, e in v.fieldPairs:
    if i > 0:
      dumper.write ','
    dumper.dump(e)
    inc i
  dumper.write ']'

proc dump*(dumper: var JsonDumper, v: enum) =
  dumper.dump($v)

proc dump*[N, T](dumper: var JsonDumper, v: array[N, T]) =
  dumper.write '['
  var i = 0
  for e in v:
    if i != 0:
      dumper.write ','
    dumper.dump(e)
    inc i
  dumper.write ']'

proc dump*[T](dumper: var JsonDumper, v: seq[T]) =
  dumper.write '['
  for i, e in v:
    if i != 0:
      dumper.write ','
    dumper.dump(e)
  dumper.write ']'

proc dump*[T](dumper: var JsonDumper, v: Option[T]) =
  if v.isNone:
    dumper.write "null"
  else:
    dumper.dump(v.get())

proc dump*(dumper: var JsonDumper, v: object) =
  dumper.write '{'
  var i = 0
  when compiles(for k, e in v.pairs: discard):
    # Tables and table like objects.
    for k, e in v.pairs:
      if i > 0:
        dumper.write ','
      dumper.dump(k)
      dumper.write ':'
      dumper.dump(e)
      inc i
  else:
    # Normal objects.
    for k, e in v.fieldPairs:
      # XXX rename hook here too also important
      when compiles(skipHook(type(v), k)):
        when skipHook(type(v), k):
          discard
        else:
          if i > 0:
            s.add ','
          dumper.dumpKey(k)
          dumper.dump(e)
          inc i
      else:
        if i > 0:
          s.add ','
        dumper.dumpKey(k)
        dumper.dump(e)
        inc i
  dumper.write '}'

proc dump*[N, T](dumper: var JsonDumper, v: array[N, t[T]]) =
  dumper.write '{'
  var i = 0
  # Normal objects.
  for (k, e) in v:
    if i > 0:
      dumper.write ','
    dumper.dump(k)
    dumper.write ':'
    dumper.dump(e)
    inc i
  dumper.write '}'

proc dump*(dumper: var JsonDumper, v: ref) =
  if v == nil:
    dumper.write "null"
  else:
    dumper.dump(v[])

proc dump*[T](dumper: var JsonDumper, v: SomeSet[T]|set[T]) =
  dumper.write '['
  var i = 0
  for e in v:
    if i != 0:
      dumper.write ','
    dumper.dump(e)
    inc i
  dumper.write ']'

proc dump*(dumper: var JsonDumper, v: JsonNode) =
  ## Dumps a regular json node.
  if v == nil:
    dumper.write "null"
  else:
    case v.kind:
    of JObject:
      dumper.write '{'
      var i = 0
      for k, e in v.pairs:
        if i != 0:
          dumper.write ","
        dumper.dump(k)
        dumper.write ':'
        dumper.dump(e)
        inc i
      dumper.write '}'
    of JArray:
      dumper.write '['
      var i = 0
      for e in v:
        if i != 0:
          dumper.write ","
        dumper.dump(e)
        inc i
      dumper.write ']'
    of JNull:
      dumper.write "null"
    of JInt:
      dumper.dump(v.getInt)
    of JFloat:
      dumper.dump(v.getFloat)
    of JString:
      dumper.dump(v.getStr)
    of JBool:
      dumper.dump(v.getBool)

proc read*(reader: var JsonReader, v: var RawJson) =
  reader.lockBuffer()
  let oldI = reader.bufferPos
  skipValue(reader)
  v = reader.vein.buffer[oldI .. reader.bufferPos].RawJson

proc dump*(dumper: var JsonDumper, v: RawJson) =
  dumper.write v.string

proc toJson*[T](v: T): string =
  var dumper = initJsonDumper()
  dumper.startDump()
  dumper.dump(v)
  result = dumper.finishDump()

template toStaticJson*(v: untyped): static[string] =
  ## This will turn v into json at compile time and return the json string.
  const s = v.toJson()
  s

# A compiler bug prevents this from working. Otherwise toStaticJson and toJson
# can be same thing.
# TODO: Figure out the compiler bug.
# proc toJsonDynamic*[T](v: T): string =
#   dump(result, v)
# template toJson*[T](v: static[T]): string =
#   ## This will turn v into json at compile time and return the json string.
#   const s = v.toJsonDynamic()
#   s

when defined(release):
  {.pop.}
