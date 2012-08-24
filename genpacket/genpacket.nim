import macros, macro_dsl, streams, streams_enh

template `&$`(a, b: expr): expr {.immediate.} =
  (a & $b)

template newLenName(): stmt {.immediate.} =
  let lenName = ^("len"&$lenNames)
  inc(lenNames)

macro defPacket*(body: expr): stmt = 
  result = newNimNode(nnkStmtList)
  let 
    typeName = quoted2ident(body[1])
    typeFields = body[2]
    packetID = ^"p"
    streamID = ^"s"
  var
    constructorParams = newNimNode(nnkFormalParams).und(typeName)
    constructor = newNimNode(nnkProcDef).und(
      postfix(^("new"&$typeName.ident), "*"),
      newNimNode(nnkEmpty),
      constructorParams,
      newNimNode(nnkEmpty))
    pack = newNimNode(nnkProcDef).und(
      postfix(^"pack", "*"),
      newNimNode(nnkEmpty))
    read = newNimNode(nnkProcDef).und(
      newIdentNode("read"& $typeName.ident).postfix("*"),
      newNimNode(nnkEmpty))
    constructorBody = newNimNode(nnkStmtList)
    packBody = newNimNode(nnkStmtList)
    readBody = newNimNode(nnkStmtList)
    lenNames = 0
  pack.add(
    newNimNode(nnkFormalParams).und(
      newNimNode(nnkEmpty),   ##result type
      newNimNode(nnkIdentDefs).und(
        packetID,     ## p: var T
        newNimNode(nnkVarTy).und(typeName),
        newNimNode(nnkEmpty)),
      newNimNode(nnkIdentDefs).und(
        streamID,     ## s: PStream = nil
        ^"PStream",
        newNimNode(nnkNilLit))),
    newNimNode(nnkEmpty))
  read.add(
    newNimNode(nnkFormalParams).und(
      typeName,  #result type
      newNimNode(nnkIdentDefs).und(
        streamID,  ## s: PStream = nil
        ^"PStream",
        newNimNode(nnkNilLit))),
    newNimNode(nnkEmpty))
  for i in 0.. typeFields.len - 1:
    let 
      name = typeFields[i][0]
      dotName = packetID.dot(name)
      resName = newIdentNode(!"result").dot(name)
    case typeFields[i][1].kind
    of nnkBracketExpr: #ex: paddedstring[32, '\0'], array[range, type]
      case $typeFields[i][1][0].ident
      of "paddedstring":
        let length = typeFields[i][1][1]
        let padChar = typeFields[i][1][2]
        packBody.add(newCall(
          "writePaddedStr", streamID, dotName, length, padChar))
        ## result.name = readPaddedStr(s, length, char)
        readBody.add(resName := newCall(
          "readPaddedStr", streamID, length, padChar))
        ## make the type a string
        typeFields[i] = newNimNode(nnkIdentDefs).und(
          name,
          ^"string",
          newNimNode(nnkEmpty))
      of "seq":
        ## let lenX = readInt16(s)
        newLenName()
        let 
          item = ^"item"  ## item name in our iterators
          seqType = typeFields[i][1][1] ## type of seq
          readName = newIdentNode("read"& $seqType.ident)
        readBody.add(newNimNode(nnkLetSection).und(
          newNimNode(nnkIdentDefs).und(
            lenName,
            newNimNode(nnkEmpty),
            newCall("readInt16", streamID))))
        readBody.add(      ## result.name = @[]
          resName := ("@".prefix(newNimNode(nnkBracket))),
          newNimNode(nnkForStmt).und(  ## for item in 1..len:
            item, 
            infix(1.lit, "..", lenName),
            newNimNode(nnkStmtList).und(
              newCall(  ## add(result.name, unpack[seqType](stream))
                "add", resName, newNimNode(nnkCall).und(readName, streamID)
        ) ) ) )
        packbody.add(
          newNimNode(nnkVarSection).und(newNimNode(nnkIdentDefs).und(
            lenName,  ## var lenName = int16(len(p.name))
            newIdentNode("int16"),
            newCall("int16", newCall("len", dotName)))), 
          newCall("writeData", streamID, newNimNode(nnkAddr).und(lenName), 2.lit),
          newNimNode(nnkForStmt).und(  ## for item in 0..length - 1: pack(p.name[item], stream)
            item,
            infix(0.lit, "..", infix(lenName, "-", 1.lit)),
            newNimNode(nnkStmtList).und(
              newCall("echo", item, ": ".lit),
              newCall("pack", dotName[item], streamID))))
        #set the default value to @[] (new sequence)
        typeFields[i][2] = "@".prefix(newNimNode(nnkBracket))
      else:
        error("Unknown type: "& treeRepr(typeFields[i]))
    of nnkIdent: ##normal type
      case $typeFields[i][1].ident
      of "string": # length encoded string
        packBody.add(newCall("writeLEStr", streamID, dotName))
        readBody.add(resName := newCall("readLEStr", streamID))
      of "int8", "int16", "int32", "float32", "float64", "char":
        packBody.add(newCall(
          "writeData", streamID, newNimNode(nnkAddr).und(dotName), newCall("sizeof", dotName)))
        readBody.add(resName := newCall("read"& $typeFields[i][1].ident, streamID))
      else:  ## hopefully the type you specified was another defpacket() type
        packBody.add(newCall("pack", dotName, streamID))
        readBody.add(resName := newCall("read"& $typeFields[i][1].ident, streamID))
    else:
      error("I dont know what to do with: "& treerepr(typeFields[i]))
  
  const emptyFields = {nnkEmpty, nnkNilLit}
  var objFields = newNimNode(nnkRecList)
  for i in 0..len(typeFields)-1:
    let fname = typeFields[i][0]
    constructorParams.add(newNimNode(nnkIdentDefs).und(
      fname,
      typeFields[i][1],
      typeFields[i][2]))
    constructorBody.add((^"result").dot(fname) := fname)
    #export the name
    typeFields[i][0] = fname.postfix("*")
    if not(typeFields[i][2].kind in emptyFields):
      ## empty the type default for the type def
      typeFields[i][2] = newNimNode(nnkEmpty)
    objFields.add(typeFields[i])
  
  result.add(
    newNimNode(nnkTypeSection).und(
      newNimNode(nnkTypeDef).und(
        typeName.postfix("*"),
        newNimNode(nnkEmpty),
        newNimNode(nnkObjectTy).und(
          newNimNode(nnkEmpty), #not sure what this is
          newNimNode(nnkEmpty), #parent: OfInherit(Ident(!"SomeObj"))
          objFields))))
  result.add(constructor.und(constructorBody))
  result.add(pack.und(packBody))
  result.add(read.und(readBody))
  echo(repr(result))

proc `->`(a: string, b: string): PNimrodNode {.compileTime.} =
  result = newNimNode(nnkIdentDefs).und(^a, ^b, newNimNode(nnkEmpty))
proc `->`(a: string, b: PNimrodNode): PNimrodNode {.compileTime.} =
  result = newNimNode(nnkIdentDefs).und(^a, b, newNimNode(nnkEmpty))
proc `->`(a, b: PNimrodNode): PNimrodNode {.compileTime.} =
  a[2] = b
  result = a

proc newProc*(name: string, params: varargs[PNimrodNode], resultType: PNimrodNode): PNimrodNode {.compileTime.} =
  result = newNimNode(nnkProcDef).und(
    ^name,
    newNimNode(nnkEmpty),
    newNimNode(nnkFormalParams).und(resultType),
    newNimNode(nnkEmpty),
    newNimNode(nnkStmtList))
  result[2].add(params)
macro forwardPacket*(e: expr): stmt =
  let
    typeName = e[1]
    underlyingType = e[2]
  result = newNimNode(nnkStmtList).und(
    newProc(
      "read"& $typeName.ident, 
      ["s" -> "PStream" -> newNimNode(nnkNilLit)],
      typeName),
    newProc(
      "pack",
      [ "p" -> newNimNode(nnkVarTy).und(typeName),
        "s" -> "PStream" -> newNimNode(nnkNilLit)],
      newNimNode(nnkEmpty)))
  result[0][4].add((^"result") := newCall("read"& $underlyingType.ident, ^"s").dot(typeName))
  result[1][4].add(
    newCall(
      "writeData", ^"s", newNimNode(nnkAddr).und(^"p"), newCall(
        "sizeof", ^"p")))
  echo(repr(result))

when isMainModule:
  var s = newStringStream()
  s.flushImpl = proc(s: PStream) =
    var z = PStringStream(s)
    z.setPosition(0)
    z.data.setLen(0)
  type
    SomeEnum = enum
      A = 0'i8,
      B, C
  forwardPacket(SomeEnum, int8)
  s.setPosition(0)
  s.data.setLen(0)
  var o = B
  o.pack(s)
  o = A
  o.pack(s)
  o = C
  o.pack(s)
  assert s.data == "\1\0\2"
  s.flush
  
  defPacket(Y, tuple[z: int8])
  proc `$`(z: Y): string = result = "Y("& $z.z &")"
  defPacket(TestPkt, tuple[x: seq[Y]])
  var test = newTestPkt()
  test.x.add([newY(5), newY(4), newY(3), newY(2), newY(1)])
  for itm in test.x:
    echo(itm)
  test.pack(s)
  echo(repr(s.data))