import private/caseutils

const jsonyHookCompatibility* {.booldefine.} = true

type
  RawJson* = distinct string
  JsonValueError* = object of ValueError
  JsonParseError* = object of CatchableError

type
  NamePatternKind* = enum
    NoName,
    NameString,
    # raw name maybe
    NameSnakeCase ## converts field name to snake case
  NamePattern* = object
    case kind*: NamePatternKind
    of NoName: discard
    of NameString: str*: string
    of NameSnakeCase: discard
  FieldJsonOptions* = object
    readNames*: seq[NamePattern]
    ignoreRead*, ignoreDump*: bool
    dumpName*: NamePattern
    # maybe normalize case option

# dependency on macros.customPragmaVal means we can only use one overload and converters over it
template json*(options: FieldJsonOptions) {.pragma.}
#template json*(name: string) {.pragma.}
#template json*(dump: bool) {.pragma.}

proc toFieldOptions*(options: FieldJsonOptions): FieldJsonOptions {.inline.} =
  options

proc toName*(str: string): NamePattern = NamePattern(kind: NameString, str: str)

proc snakeCase*(): NamePattern = NamePattern(kind: NameSnakeCase)

converter toFieldOptions*(name: NamePattern): FieldJsonOptions =
  FieldJsonOptions(readNames: @[name], dumpName: name)

converter toFieldOptions*(name: string): FieldJsonOptions =
  toFieldOptions(toName(name))

converter toFieldOptions*(enabled: bool): FieldJsonOptions =
  FieldJsonOptions(ignoreRead: not enabled, ignoreDump: not enabled)

proc ignore*(): FieldJsonOptions =
  FieldJsonOptions(ignoreRead: true, ignoreDump: true)

proc apply*(pattern: NamePattern, name: string): string =
  case pattern.kind
  of NoName: ""
  of NameString: pattern.str
  of NameSnakeCase: snakeCaseDynamic(name)

proc getReadNames*(fieldName: string, options: FieldJsonOptions): seq[string] =
  if options.readNames.len != 0:
    result = @[]
    for pat in options.readNames:
      let name = apply(pat, fieldName)
      if name notin result: result.add name
  else:
    result = @[fieldName]
    let snakeCase = snakeCaseDynamic(fieldName)
    if snakeCase != fieldName: result.add snakeCase

proc getDumpName*(fieldName: string, options: FieldJsonOptions): string =
  if options.dumpName.kind != NoName:
    result = apply(options.dumpName, fieldName)
  else:
    result = fieldName
