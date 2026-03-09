## defines the `JsonReader` object along with helpers to use it

import hemodyne/syncvein, ./common, std/streams

const holojsonLineColumn* {.booldefine.} = true
  ## enables/disables line column tracking by default, has very little impact on performance

type
  JsonReaderOptions* = object
    doLineColumn*: bool = holojsonLineColumn
    handleUtf16*: bool = true
      ## jsony converts utf 16 characters in strings by default apparently so does stdlib json
    forceUtf8Strings*: bool
      ## jsony errors if binary data in strings is not utf8, this is now opt in
    rawJsNanInf*: bool
      ## parses raw NaN/Infinity/-Infinity as in js and json5
    # XXX comments?
  JsonReader* = object
    options*: JsonReaderOptions
    vein*: Vein
    bufferLocks*: int
    bufferPos*: int
    line*, column*: int

{.push checks: off, stacktrace: off.}

proc initJsonReader*(options = JsonReaderOptions()): JsonReader {.inline.} =
  result = JsonReader(options: options)

proc startRead*(reader: var JsonReader, vein: Vein) {.inline.} =
  reader.vein = vein
  reader.bufferPos = -1
  reader.bufferLocks = 0
  reader.line = 1
  reader.column = 1

proc startRead*(reader: var JsonReader, str: string) {.inline.} =
  reader.startRead(initVein(str))

proc startRead*(reader: var JsonReader, stream: Stream, loadAmount = 4) {.inline.} =
  reader.startRead(initVein(stream, loadAmount))

proc error*(reader: var JsonReader, msg: string) {.inline.} =
  ## Shortcut to raise an exception.
  raise newException(JsonValueError, "(" & $reader.line & ", " & $reader.column & ") " & msg)

proc parseError*(reader: var JsonReader, msg: string) {.inline.} =
  ## Shortcut to raise an exception.
  raise newException(JsonParseError, "(" & $reader.line & ", " & $reader.column & ") " & msg)

proc loadBufferOne*(reader: var JsonReader) {.inline.} =
  let remove = reader.vein.loadBufferOne()
  reader.bufferPos -= remove

proc loadBufferBy*(reader: var JsonReader, n: int) {.inline.} =
  let remove = reader.vein.loadBufferBy(n)
  reader.bufferPos -= remove

proc peek*(reader: var JsonReader, c: var char): bool {.inline.} =
  let nextPos = reader.bufferPos + 1
  if nextPos < reader.vein.buffer.len:
    c = reader.vein.buffer[nextPos]
    result = true
  else:
    reader.loadBufferOne()
    if nextPos < reader.vein.buffer.len:
      c = reader.vein.buffer[nextPos]
      result = true
    else:
      result = false

proc unsafePeek*(reader: var JsonReader): char {.inline.} =
  result = reader.vein.buffer[reader.bufferPos + 1]

proc peek*(reader: var JsonReader, c: var char, offset: int): bool {.inline.} =
  let nextPos = reader.bufferPos + 1 + offset
  if nextPos < reader.vein.buffer.len:
    c = reader.vein.buffer[nextPos]
    result = true
  else:
    reader.loadBufferBy(1 + offset)
    if nextPos < reader.vein.buffer.len:
      c = reader.vein.buffer[nextPos]
      result = true
    else:
      result = false

proc unsafePeek*(reader: var JsonReader, offset: int): char {.inline.} =
  result = reader.vein.buffer[reader.bufferPos + 1 + offset]

template peekStrImpl(reader: var JsonReader, cs) =
  result = false
  let n = cs.len
  if reader.bufferPos + n >= reader.vein.buffer.len:
    reader.loadBufferBy(n)
  if reader.bufferPos + n < reader.vein.buffer.len:
    result = true
    for i in 0 ..< n:
      cs[i] = reader.vein.buffer[reader.bufferPos + 1 + i]

proc peek*(reader: var JsonReader, cs: var openArray[char]): bool {.inline.} =
  peekStrImpl(reader, cs)

proc peek*[I](reader: var JsonReader, cs: var array[I, char]): bool {.inline.} =
  peekStrImpl(reader, cs)

proc peekOrZero*(reader: var JsonReader): char {.inline.} =
  if not peek(reader, result):
    result = '\0'

proc hasNext*(reader: var JsonReader): bool {.inline.} =
  var dummy: char
  result = peek(reader, dummy)

proc hasNext*(reader: var JsonReader, offset: int): bool {.inline.} =
  var dummy: char
  result = peek(reader, dummy, offset)

proc lockBuffer*(reader: var JsonReader) {.inline.} =
  inc reader.bufferLocks

proc unlockBuffer*(reader: var JsonReader) {.inline.} =
  doAssert reader.bufferLocks > 0, "unpaired buffer unlock"
  dec reader.bufferLocks

proc unsafeNext*(reader: var JsonReader) {.inline.} =
  # keep separate from next for now
  let prevPos = reader.bufferPos
  inc reader.bufferPos
  if reader.options.doLineColumn:
    let c = reader.vein.buffer[reader.bufferPos]
    if c == '\n' or (c == '\r' and reader.peekOrZero() != '\n'):
      inc reader.line
      reader.column = 1
    else:
      inc reader.column
  if reader.bufferLocks == 0: reader.vein.setFreeBefore(prevPos)

proc unsafeNextBy*(reader: var JsonReader, n: int) {.inline.} =
  # keep separate from next for now
  let prevPos = reader.bufferPos
  inc reader.bufferPos, n
  if reader.options.doLineColumn:
    for i in prevPos ..< reader.bufferPos:
      let c = reader.vein.buffer[i]
      if c == '\n' or (c == '\r' and reader.vein.buffer[i + 1] != '\n'):
        inc reader.line
        reader.column = 1
      else:
        inc reader.column
    let cf = reader.vein.buffer[reader.bufferPos]
    if cf == '\n' or (cf == '\r' and reader.peekOrZero() != '\n'):
      inc reader.line
      reader.column = 1
    else:
      inc reader.column
  if reader.bufferLocks == 0: reader.vein.setFreeBefore(reader.bufferPos - 1)

proc next*(reader: var JsonReader, c: var char): bool {.inline.} =
  # keep separate from unsafeNext for now
  if not peek(reader, c):
    return false
  let prevPos = reader.bufferPos
  inc reader.bufferPos
  if reader.options.doLineColumn:
    if c == '\n' or (c == '\r' and reader.peekOrZero() != '\n'):
      inc reader.line
      reader.column = 1
    else:
      inc reader.column
  if reader.bufferLocks == 0: reader.vein.setFreeBefore(prevPos)
  result = true

proc next*(reader: var JsonReader): bool {.inline.} =
  var dummy: char
  result = next(reader, dummy)

iterator peekNext*(reader: var JsonReader): char =
  var c: char
  while reader.peek(c):
    yield c
    reader.unsafeNext()

proc peekMatch*(reader: var JsonReader, c: char): bool {.inline.} =
  var c2: char
  if reader.peek(c2) and c2 == c:
    result = true
  else:
    result = false

proc nextMatch*(reader: var JsonReader, c: char): bool {.inline.} =
  result = peekMatch(reader, c)
  if result:
    reader.unsafeNext()

proc peekMatch*(reader: var JsonReader, c: char, offset: int): bool {.inline.} =
  if reader.bufferPos + 1 + offset >= reader.vein.buffer.len:
    reader.loadBufferBy(1 + offset)
  if reader.bufferPos + 1 + offset < reader.vein.buffer.len:
    if c != reader.vein.buffer[reader.bufferPos + 1 + offset]:
      return false
    result = true
  else:
    result = false

proc peekMatch*(reader: var JsonReader, cs: set[char], c: var char): bool {.inline.} =
  if reader.peek(c) and c in cs:
    result = true
  else:
    result = false

proc nextMatch*(reader: var JsonReader, cs: set[char], c: var char): bool {.inline.} =
  result = peekMatch(reader, cs, c)
  if result:
    reader.unsafeNext()

proc peekMatch*(reader: var JsonReader, cs: set[char]): bool {.inline.} =
  var dummy: char
  result = reader.peekMatch(cs, dummy)

proc nextMatch*(reader: var JsonReader, cs: set[char]): bool {.inline.} =
  var dummy: char
  result = reader.nextMatch(cs, dummy)

proc peekMatch*(reader: var JsonReader, cs: set[char], offset: int, c: var char): bool {.inline.} =
  if reader.bufferPos + 1 + offset >= reader.vein.buffer.len:
    reader.loadBufferBy(1 + offset)
  if reader.bufferPos + 1 + offset < reader.vein.buffer.len:
    let c2 = reader.vein.buffer[reader.bufferPos + 1 + offset]
    if c2 in cs:
      c = c2
      return true
    result = false
  else:
    result = false

proc peekMatch*(reader: var JsonReader, cs: set[char], offset: int): bool {.inline.} =
  var dummy: char
  result = reader.peekMatch(cs, offset, dummy)

template peekMatchStrImpl(reader: var JsonReader, str) =
  if reader.bufferPos + str.len >= reader.vein.buffer.len:
    reader.loadBufferBy(str.len)
  if reader.bufferPos + str.len < reader.vein.buffer.len:
    for i in 0 ..< str.len:
      if str[i] != reader.vein.buffer[reader.bufferPos + 1 + i]:
        return false
    result = true
  else:
    result = false

proc peekMatch*(reader: var JsonReader, str: openArray[char]): bool {.inline.} =
  peekMatchStrImpl(reader, str)

proc peekMatch*[I](reader: var JsonReader, str: array[I, char]): bool {.inline.} =
  peekMatchStrImpl(reader, str)

proc peekMatch*(reader: var JsonReader, str: static string): bool {.inline.} =
  # maybe make a const array
  peekMatchStrImpl(reader, str)

proc nextMatch*(reader: var JsonReader, str: openArray[char]): bool {.inline.} =
  result = peekMatch(reader, str)
  if result:
    reader.unsafeNextBy(str.len)

proc nextMatch*[I](reader: var JsonReader, str: array[I, char]): bool {.inline.} =
  result = peekMatch(reader, str)
  if result:
    reader.unsafeNextBy(str.len)

proc nextMatch*(reader: var JsonReader, str: static string): bool {.inline.} =
  result = peekMatch(reader, str)
  if result:
    reader.unsafeNextBy(str.len)

{.pop.}
