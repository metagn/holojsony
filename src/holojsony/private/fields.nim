import std/[macros, tables], ../common

proc realBasename(n: NimNode): string =
  var n = n
  if n.kind == nnkPragmaExpr: n = n[0]
  if n.kind == nnkPostfix: n = n[^1]
  result = $n

proc iterFieldNames(names: var seq[(string, NimNode)], list: NimNode) =
  case list.kind
  of nnkRecList, nnkTupleTy:
    for r in list:
      iterFieldNames(names, r)
  of nnkRecCase:
    iterFieldNames(names, list[0])
    for bi in 1 ..< list.len:
      expectKind list[bi], {nnkOfBranch, nnkElifBranch, nnkElse}
      iterFieldNames(names, list[bi][^1])
  of nnkRecWhen:
    for bi in 0 ..< list.len:
      expectKind list[bi], {nnkElifBranch, nnkElse}
      iterFieldNames(names, list[bi][^1])
  of nnkIdentDefs:
    for i in 0 ..< list.len - 2:
      let name = realBasename(list[i])
      var prag: NimNode = nil
      if list[i].kind == nnkPragmaExpr:
        prag = list[i][1]
      block doAdd:
        for existing in names.mitems:
          if existing[0] == name:
            break doAdd
        names.add (name, prag)
  of nnkSym:
    when defined(holojsonySymPragmaWarning):
      warning "got just sym for object field, maybe missing pragma information", list
    let name = $list
    names.add (name, nil)
  of nnkDiscardStmt, nnkNilLit, nnkEmpty: discard
  else:
    error "unknown object field AST kind " & $list.kind, list

const
  nnkPragmaCallKinds = {nnkExprColonExpr, nnkCall, nnkCallStrLit}

macro fieldOptionPairs*[T: object | ref object | tuple](obj: T): untyped =
  var names: seq[(string, NimNode)] = @[]
  var t = obj
  var isTuple = false
  while t != nil:
    # very horribly try to copy macros.customPragma:
    var impl = getTypeInst(t)
    while true:
      if impl.kind in {nnkRefTy, nnkPtrTy, nnkVarTy, nnkOutTy}:
        if impl[^1].kind == nnkObjectTy:
          impl = impl[^1]
        else:
          impl = getTypeInst(impl[^1])
      elif impl.kind == nnkBracketExpr and impl[0].eqIdent"typeDesc":
        impl = getTypeInst(impl[1])
      elif impl.kind == nnkBracketExpr and impl[0].kind == nnkSym:
        impl = getImpl(impl[0])[^1]
      elif impl.kind == nnkSym:
        impl = getImpl(impl)[^1]
      else:
        break
    case impl.kind
    of nnkTupleTy:
      iterFieldNames(names, impl)
      t = nil
      isTuple = true
    of nnkObjectTy:
      iterFieldNames(names, impl[^1])
      t = nil
      if impl[1].kind != nnkEmpty:
        expectKind impl[1], nnkOfInherit
        t = impl[1][0]
    else:
      error "got unknown object type kind " & $impl.kind, impl
  result = newNimNode(nnkBracket, obj)
  var pragmaSym = bindSym("json")
  var pragmaSyms: seq[NimNode] = @[]
  if pragmaSym.kind in {nnkOpenSymChoice, nnkClosedSymChoice}:
    for s in pragmaSym:
      let imp = getImpl(s)
      if imp != nil and imp.kind == nnkTemplateDef:
        pragmaSyms.add s
  for name, prag in names.items:
    var val: NimNode = nil
    if prag != nil and not isTuple:
      # again copied from macros.customPragma
      for p in prag:
        if p.kind in nnkPragmaCallKinds and p.len > 0 and p[0].kind == nnkSym and p[0] in pragmaSyms:
          if p.len == 2 or (p.len == 3 and p[1].kind == nnkSym and p[1].symKind == nskType):
            val = p[1]
          else:
            let def = p[0].getImpl[3]
            val = newTree(nnkPar)
            for i in 1 ..< def.len:
              let key = def[i][0]
              let val = p[i]
              val.add newTree(nnkExprColonExpr, key, val)
    if val == nil:
      val = quote do: FieldJsonOptions()
    else:
      val = quote do: toFieldOptions(`val`)
    result.add(newTree(nnkTupleConstr,
      newLit(name),
      val))
    when false:
      let ident = ident(name)
      if isTuple:
        quote do:
          FieldJsonOptions()
      else:
        quote do:
          when hasCustomPragma(`obj`.`ident`, `pragmaSym`):
            toFieldOptions(getCustomPragmaVal(`obj`.`ident`, `pragmaSym`))
          else:
            FieldJsonOptions()

macro fieldOptionTable*[T: object | ref object | tuple](obj: T): Table[string, FieldJsonOptions] =
  result = newCall(bindSym"toTable", getAst(fieldOptionPairs(obj)))

# XXX types could also define hooks for these too
