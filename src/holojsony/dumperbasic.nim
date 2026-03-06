import ./[common, dumperdef], hemodyne/syncartery, std/[json, typetraits, unicode]
import std/math # for classify

export JsonDumper, JsonDumperOptions, initJsonDumper, startDump

proc dump*(dumper: var JsonDumper, v: string)
type t[T] = tuple[a: string, b: T]
proc dump*[N, T](dumper: var JsonDumper, v: array[N, t[T]])
proc dump*[N, T](dumper: var JsonDumper, v: array[N, T])
proc dump*[T](dumper: var JsonDumper, v: seq[T])
proc dump*(dumper: var JsonDumper, v: object)
proc dump*[T: distinct](dumper: var JsonDumper, v: T) {.inline.}

# don't dogfood these yet if they add to compile times:
type
  ArrayDump* = object
    needsComma*: bool
  ObjectDump* = object
    needsComma*: bool

proc startArrayDump*(dumper: var JsonDumper): ArrayDump {.inline.} =
  result = ArrayDump(needsComma: false)
  dumper.write '['

proc finishArrayDump*(dumper: var JsonDumper, arr: var ArrayDump) {.inline.} =
  dumper.write ']'

proc startArrayItem*(dumper: var JsonDumper, arr: var ArrayDump) {.inline.} =
  if arr.needsComma:
    dumper.write ','
  else:
    arr.needsComma = true

proc finishArrayItem*(dumper: var JsonDumper, arr: var ArrayDump) {.inline.} =
  discard

template withArrayDump*(dumper: var JsonDumper, arr: var ArrayDump, body: typed) =
  arr = startArrayDump(dumper)
  body
  finishArrayDump(dumper, arr)

template withArrayItem*(dumper: var JsonDumper, arr: var ArrayDump, body: typed) =
  startArrayItem(dumper, arr)
  body
  finishArrayItem(dumper, arr)

proc startObjectDump*(dumper: var JsonDumper): ObjectDump {.inline.} =
  result = ObjectDump(needsComma: false)
  dumper.write '{'

proc finishObjectDump*(dumper: var JsonDumper, arr: var ObjectDump) {.inline.} =
  dumper.write '}'

proc startObjectField*(dumper: var JsonDumper, arr: var ObjectDump, name: string, raw = false) {.inline.} =
  if arr.needsComma:
    dumper.write ','
  else:
    arr.needsComma = true
  if raw:
    dumper.write name
  else:
    dumper.dump name
  dumper.write ':'

proc finishObjectField*(dumper: var JsonDumper, arr: var ObjectDump) {.inline.} =
  discard

template withObjectDump*(dumper: var JsonDumper, arr: var ObjectDump, body: typed) =
  arr = startObjectDump(dumper)
  body
  finishObjectDump(dumper, arr)

template withObjectField*(dumper: var JsonDumper, arr: var ObjectDump, name: string, body: typed) =
  startObjectField(dumper, arr, name)
  body
  finishObjectField(dumper, arr)

template withRawObjectField*(dumper: var JsonDumper, arr: var ObjectDump, name: string, body: typed) =
  startObjectField(dumper, arr, name, raw = true)
  body
  finishObjectField(dumper, arr)

proc dump*[T: distinct](dumper: var JsonDumper, v: T) {.inline.} =
  dumper.dump(distinctBase(T)(v))

proc dump*(dumper: var JsonDumper, v: bool) {.inline.} =
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

proc dumpNumberSlow(dumper: var JsonDumper, v: uint|uint8|uint16|uint32|uint64) {.inline.} =
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
  dumper.consumeBuffer()

proc dump*(dumper: var JsonDumper, v: uint|uint8|uint16|uint32|uint64) {.inline.} =
  when nimvm:
    dumper.dumpNumberSlow(v)
  else:
    when defined(js):
      dumper.dumpNumberSlow(v)
    else:
      dumper.dumpNumberFast(v)

proc dump*(dumper: var JsonDumper, v: int|int8|int16|int32|int64) {.inline.} =
  if v < 0:
    dumper.write '-'
    dump(dumper, 0.uint64 - v.uint64)
  else:
    dump(dumper, v.uint64)

proc dump*(dumper: var JsonDumper, v: SomeFloat) =
  #dumper.write $v # original jsony
  let cls = classify(v)
  case cls
  of fcNan:
    if dumper.options.rawJsNanInf:
      dumper.write "NaN"
    else:
      # copy nim json
      dumper.write "\"nan\""
  of fcInf:
    if dumper.options.rawJsNanInf:
      dumper.write "Infinity"
    else:
      # copy nim json
      dumper.write "\"inf\""
  of fcNegInf:
    if dumper.options.rawJsNanInf:
      dumper.write "-Infinity"
    else:
      # copy nim json
      dumper.write "\"-inf\""
  else:
    dumper.artery.buffer.addFloat(v)
    dumper.consumeBuffer()

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

const hex = [
  '0', '1', '2', '3', '4', '5', '6', '7',
  '8', '9', 'a', 'b', 'c', 'd', 'e', 'f']

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
      if i >= copyStart:
        let numBytes = i - copyStart
        when nimvm:
          for p in 0 ..< numBytes:
            dumper.artery.buffer.add v[copyStart + p]
        else:
          when defined(js) or defined(nimscript):
            for p in 0 ..< numBytes:
              dumper.artery.buffer.add v[copyStart + p]
          else:
            let sLen = dumper.artery.buffer.len
            dumper.artery.buffer.setLen(sLen + numBytes)
            copyMem(dumper.artery.buffer[sLen].addr, v[copyStart].unsafeAddr, numBytes)
        dumper.consumeBuffer()
      inCopy = false
  try:
    while i < v.len:
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
            s.add Rune(0xfffd) # ??? this is just bad
          if dumper.options.useXEscape:
            dumper.write r"\x"
          else:
            dumper.write r"\u00"
          dumper.write hex[c.int shr 4]
          dumper.write hex[c.int and 0xf]
          inc i
  finally:
    finishCopy()

  dumper.write '"'

proc dump*(dumper: var JsonDumper, v: char) =
  dumper.write '"'
  if v < 32.char or v > 127.char or v == '\\' or v == '"':
    case v
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
    else:
      if dumper.options.useXEscape:
        dumper.write r"\x"
      else:
        dumper.write r"\u00"
      dumper.write hex[v.int shr 4]
      dumper.write hex[v.int and 0xf]
  else:
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

proc dump*(dumper: var JsonDumper, v: enum) {.inline.} =
  case dumper.options.defaultEnumOutput
  of EnumName:
    dumper.dump($v)
  of EnumOrd:
    dumper.dump(ord(v))

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

template dumpKey(dumper: var JsonDumper, v: static string) =
  const v2 = holojsony.toJson(v) & ":"
  dumper.write v2

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
            dumper.write ','
          dumper.dumpKey(k)
          dumper.dump(e)
          inc i
      else:
        if i > 0:
          dumper.write ','
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

proc dump*(dumper: var JsonDumper, v: ref) {.inline.} =
  if v == nil:
    dumper.write "null"
  else:
    dumper.dump(v[])

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

proc dump*(dumper: var JsonDumper, v: RawJson) {.inline.} =
  dumper.write v.string

proc dump*[T](s: var string, v: T) {.inline.} =
  mixin dump
  var dumper = initJsonDumper()
  dumper.startDump()
  dumper.dump(v)
  s = dumper.finishDump()

proc toJson*[T](v: T): string {.inline.} =
  dump(result, v)

template toStaticJson*(v: untyped): static[string] =
  ## This will turn v into json at compile time and return the json string.
  const s = v.toJson()
  s
