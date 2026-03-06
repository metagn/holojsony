import std/tables

type
  SomeTable*[K, V] = Table[K, V] | OrderedTable[K, V] |
    TableRef[K, V] | OrderedTableRef[K, V]
  RawJson* = distinct string
  JsonValueError* = object of ValueError
  JsonParseError* = object of CatchableError
