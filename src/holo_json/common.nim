import private/caseutils

const jsonyHookCompatibility* {.booldefine.} = true
  ## allows compatibility with `renameHook` and `skipHook` which have been replaced with pragmas,
  ## these may become compile time hooks instead. since all other hooks are simply renamed or
  ## had their signature changed, this flag does not affect other hooks

const jsonyFieldCompatibility* {.booldefine.} = true
  ## uses the jsony field name patterns by default, which is: to read the original name and a snake case
  ## version of the name, and to output the original name of the field.
  ## true by default, when disabled only the snake case version of the name is used for both reading and output.

type
  RawJson* = distinct string
  JsonValueError* = object of ValueError
  JsonParseError* = object of CatchableError
    ## error that signifies a violation of json grammar,
    ## currently not used in all such cases

type
  NamePatternKind* = enum
    NoName,
    NameOriginal, ## uses the field name
    NameString, ## uses custom string and ignores field name
    NameSnakeCase ## converts field name to snake case
    # maybe raw json unquoted name
    NameConcat
  NamePattern* = object
    ## string pattern to apply to a given field name to use in json
    case kind*: NamePatternKind
    of NoName: discard
    of NameOriginal: discard
    of NameString: str*: string
    of NameSnakeCase: discard
    of NameConcat: concat*: seq[NamePattern]
  FieldJsonOptions* = object
    ## json serialization/deserialization options for an object field
    readNames*: seq[NamePattern]
      ## names that are accepted for this field when encountered in json
      ## if none are given, this defaults to the original field name and a snake case version of it
    ignoreRead*, ignoreDump*: bool
      ## whether or not to ignore a field when encountered in json or when dumping to json
    dumpName*: NamePattern
      ## name to dump this field in json by
      ## if not given, this defaults to the original field name
    # maybe normalize case option

template json*(options: FieldJsonOptions) {.pragma.}
  ## sets the json serialization/deserialization options for a field
template json*(name: string) {.pragma.}
  ## sets a single name between json serialization/deserialization for a field,
  ## can be fine tuned by giving a custom options object
template json*(enabled: bool) {.pragma.}
  ## whether or not to enable this field for both json serialization and deserialization,
  ## can be fine tuned by giving a custom options object

proc toName*(str: string): NamePattern =
  ## creates a name pattern that uses a specific string instead of the field name
  NamePattern(kind: NameString, str: str)

proc snakeCase*(): NamePattern =
  ## creates a name pattern that just converts a field name to snake case
  NamePattern(kind: NameSnakeCase)

proc toFieldOptions*(options: FieldJsonOptions): FieldJsonOptions {.inline.} =
  ## hook called on the argument to the `json` pragma to convert it to a full field option object
  options

proc toFieldOptions*(name: NamePattern): FieldJsonOptions =
  ## hook called on the argument to the `json` pragma to convert it to a full field option object,
  ## for a name pattern this sets both the serialization and deserialization name of the field to it
  FieldJsonOptions(readNames: @[name], dumpName: name)

proc toFieldOptions*(name: string): FieldJsonOptions =
  ## hook called on the argument to the `json` pragma to convert it to a full field option object,
  ## for a string this sets both the serialization and deserialization name of the field to it
  toFieldOptions(toName(name))

proc toFieldOptions*(enabled: bool): FieldJsonOptions =
  ## hook called on the argument to the `json` pragma to convert it to a full field option object,
  ## for a bool this sets whether or not to enable serialization and deserialization for this field
  FieldJsonOptions(ignoreRead: not enabled, ignoreDump: not enabled)

proc ignore*(): FieldJsonOptions =
  ## creates a field option object that ignores this field in both serialization and deserialization
  FieldJsonOptions(ignoreRead: true, ignoreDump: true)

proc apply*(pattern: NamePattern, name: string): string =
  ## applies a name pattern to a given name
  case pattern.kind
  of NoName:
    result = ""
  of NameOriginal:
    result = name
  of NameString:
    result = pattern.str
  of NameSnakeCase:
    result = snakeCaseDynamic(name)
  of NameConcat:
    if pattern.concat.len == 0: return ""
    result = apply(pattern.concat[0], name)
    for i in 1 ..< pattern.concat.len: result.add apply(pattern.concat[i], name)

proc getReadNames*(fieldName: string, options: FieldJsonOptions): seq[string] =
  ## gives the names accepted for this field when encountered in json
  ## if none are given, this defaults to the original field name and a snake case version of it
  if options.readNames.len != 0:
    result = @[]
    for pat in options.readNames:
      let name = apply(pat, fieldName)
      if name notin result: result.add name
  else:
    if jsonyFieldCompatibility:
      result = @[fieldName]
      let snakeCase = snakeCaseDynamic(fieldName)
      if snakeCase != fieldName: result.add snakeCase
    else:
      result = @[snakeCaseDynamic(fieldName)]

proc getDumpName*(fieldName: string, options: FieldJsonOptions): string =
  ## gives the name to dump this field in json by
  ## if not given, this defaults to the original field name
  if options.dumpName.kind != NoName:
    result = apply(options.dumpName, fieldName)
  else:
    if jsonyFieldCompatibility:
      result = fieldName
    else:
      result = snakeCaseDynamic(fieldName)
