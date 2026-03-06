import hemodyne/syncartery

type
  EnumOutput = enum
    EnumName, EnumOrd
  JsonDumperOptions* = object
    keepUtf8*: bool = true
      ## keeps valid utf 8 codepoints in strings as-is instead of encoding an escape sequence 
    useXEscape*: bool
      ## uses \x instead of \u for characters known to be small, not in json standard
    rawJsNanInf*: bool
      ## produces raw NaN/Infinity/-Infinity as in js and json5, as opposed to strings as in nim json
    defaultEnumOutput*: EnumOutput
    # XXX maybe pretty mode
  JsonDumper* = object
    options*: JsonDumperOptions
    artery*: Artery # for like buffering writing to a file
    flushLocks*: int
    flushPos*: int

{.push checks: off, stacktrace: off.}

proc initJsonDumper*(options = JsonDumperOptions()): JsonDumper {.inline.} =
  result = JsonDumper(options: options)

proc lockFlush*(dumper: var JsonDumper) {.inline.} =
  inc dumper.flushLocks

proc unlockFlush*(dumper: var JsonDumper) {.inline.} =
  doAssert dumper.flushLocks > 0, "unpaired flush unlock"
  dec dumper.flushLocks

proc startDump*(dumper: var JsonDumper, artery: Artery) {.inline.} =
  dumper.artery = artery
  dumper.flushLocks = 0
  dumper.flushPos = 0

proc startDump*(dumper: var JsonDumper) {.inline.} =
  dumper.startDump(Artery(buffer: "", bufferConsumer: nil))

proc finishDump*(dumper: var JsonDumper): string {.inline.} =
  ## returns leftover buffer
  doAssert dumper.flushLocks == 0, "unpaired flush lock"
  dumper.flushPos += dumper.artery.consumeBufferFull(dumper.flushPos)
  if dumper.flushPos < dumper.artery.buffer.len:
    result = dumper.artery.buffer[dumper.flushPos ..< dumper.artery.buffer.len]
  else:
    result = ""

proc addToBuffer*(dumper: var JsonDumper, c: char) {.inline.} =
  dumper.flushPos -= dumper.artery.addToBuffer(c)

proc addToBuffer*(dumper: var JsonDumper, s: sink string) {.inline.} =
  dumper.flushPos -= dumper.artery.addToBuffer(s)

proc consumeBuffer*(dumper: var JsonDumper) {.inline.} =
  #dumper.artery.consumeBufferOnce(bufferPos)
  dumper.flushPos += dumper.artery.consumeBuffer(dumper.flushPos)
  if dumper.flushLocks == 0: dumper.artery.freeBefore = dumper.flushPos

proc write*(dumper: var JsonDumper, c: char) {.inline.} =
  dumper.addToBuffer(c)
  dumper.consumeBuffer()

proc write*(dumper: var JsonDumper, s: sink string) {.inline.} =
  dumper.addToBuffer(s)
  dumper.consumeBuffer()

{.pop.}
