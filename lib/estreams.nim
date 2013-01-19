import endians

proc swapEndian16*(outp, inp: pointer) = 
  ## copies `inp` to `outp` swapping bytes. Both buffers are supposed to
  ## contain at least 2 bytes.
  var i = cast[cstring](inp)
  var o = cast[cstring](outp)
  o[0] = i[1]
  o[1] = i[0]
when cpuEndian == bigEndian:
  proc bigEndian16*(outp, inp: pointer) {.inline.} = copyMem(outp, inp, 2)
  proc littleEndian16*(outp, inp: pointer) {.inline.} = swapEndian16(outp, inp)
else:
  proc bigEndian16*(outp, inp: pointer) {.inline.} = swapEndian16(outp, inp)
  proc littleEndian16*(outp, inp: pointer){.inline.} = copyMem(outp, inp, 2)

import enet

type
  PBuffer* = ref object
    pkt: PPacket
    pos: int

proc newBuffer*(size = 100): PBuffer =
  new(result)
  result.pkt = createPacket(nil, size.csize, FlagUnsequenced)
proc newBuffer*(pkt: PPacket): PBuffer =
  new(result)
  result.pkt = pkt
proc setLen(buf: PBuffer; size: int) {.inline.} = 
  discard buf.pkt.resize(size.csize)
proc send*(peer: PPeer; buf: PBuffer; channel = 0.cuchar): cint {.discardable.} =
  result = send(peer, channel, buf.pkt)
proc broadcast*(host: PHost; buf: PBuffer; channel = 0.cuchar) {.inline.} =
  broadcast(host, channel, buf.pkt)
proc atEnd*(buf: PBuffer): bool = buf.pos == buf.pkt.dataLength.int
proc data*(buf: PBuffer): cstring = buf.pkt.data


proc read*[T: int16|uint16](buffer: PBuffer; outp: var T) =
  bigEndian16(addr outp, addr buffer.pkt.data[buffer.pos])
  inc buffer.pos, 2
proc read*[T: float32|int32|uint32](buffer: PBuffer; outp: var T) =
  bigEndian32(addr outp, addr buffer.pkt.data[buffer.pos])
  inc buffer.pos, 4
proc read*[T: float64|int64|uint64](buffer: PBuffer; outp: var T) =
  bigEndian64(addr outp, addr buffer.pkt.data[buffer.pos])
  inc buffer.pos, 8
proc read*[T: int8|uint8|byte|bool|char](buffer: PBuffer; outp: var T) =
  copyMem(addr outp, addr buffer.pkt.data[buffer.pos], 1)
  inc buffer.pos, 1

proc writeBE*[T: int16|uint16](buffer: PBuffer; val: var T) =
  setLen buffer, buffer.pos + 2
  bigEndian16(addr buffer.pkt.data[buffer.pos], addr val)
  inc buffer.pos, 2
proc writeBE*[T: int32|uint32|float32](buffer: PBuffer; val: var T) =
  setLen buffer, buffer.pos + 4
  bigEndian32(addr buffer.pkt.data[buffer.pos], addr val)
  inc buffer.pos, 4
proc writeBE*[T: int64|uint64|float64](buffer: PBuffer; val: var T) =
  setLen buffer, buffer.pos + 8
  bigEndian64(addr buffer.pkt.data[buffer.pos], addr val)
  inc buffer.pos, 8
proc writeBE*[T: char|int8|uint8|byte|bool](buffer: PBuffer; val: var T) =
  setLen buffer, buffer.pos + 1
  copyMem(addr buffer.pkt.data[buffer.pos], addr val, 1)
  inc buffer.pos, 1


proc write*(buffer: PBuffer; val: var string) =
  var length = len(val).uint16
  writeBE buffer, length
  setLen buffer, buffer.pos + length.int
  copyMem(addr buffer.pkt.data[buffer.pos], addr val[0], length.int)
  inc buffer.pos, length.int
proc write*[T: TNumber|bool|char|byte](buffer: PBuffer; val: T) =
  var v: T
  shallowCopy v, val
  writeBE buffer, v

proc readInt8*(buffer: PBuffer): int8 =
  read buffer, result
proc readInt16*(buffer: PBuffer): int16 =
  read buffer, result
proc readInt32*(buffer: PBuffer): int32 =
  read buffer, result
proc readInt64*(buffer: PBuffer): int64 =
  read buffer, result
proc readFloat32*(buffer: PBuffer): float32 =
  read buffer, result
proc readFloat64*(buffer: PBuffer): float64 =
  read buffer, result
proc readStr*(buffer: PBuffer): string =
  let len = readInt16(buffer).int
  result = ""
  if len > 0:
    result.setLen len
    copyMem(addr result[0], addr buffer.pkt.data[buffer.pos], len)
    inc buffer.pos, len
proc readChar*(buffer: PBuffer): char {.inline.} = return readInt8(buffer).char
proc readBool*(buffer: PBuffer): bool {.inline.} = return readInt8(buffer).bool


when isMainModule:
  var b = newBuffer(100)
  var str = "hello there"
  b.write str
  echo(repr(b))
  b.pos = 0
  echo(repr(b.readStr()))
  
  b.flush()
  echo "flushed"
  b.writeC([1,2,3])
  echo(repr(b))
  
  

discard """type
  PBuffer* = ref object
    data*: string
    pos: int"""

discard """proc free(b: PBuffer) =
  GCunref b.data
  if not 
proc newBuffer*(len: int): PBuffer =
  new result, free
  result.data = newString(len)
proc newBuffer*(pkt: PPacket): PBuffer =
  new result, free
  result.data = newString(pkt.dataLength)
  copyMem(addr result.data[0], pkt.data, pkt.dataLength)
proc toPacket*(buffer: PBuffer; flags: TPacketFlag): PPacket =
  buffer.data.setLen buffer.pos
  result = createPacket(cstring(buffer.data), buffer.pos, flags)
"""
discard """proc isDirty*(buffer: PBuffer): bool {.inline.} =
  result = (buffer.pos != 0)
proc atEnd*(buffer: PBuffer): bool {.inline.} =
  result = (buffer.pos == buffer.data.len)
proc reset*(buffer: PBuffer) {.inline.} =
  buffer.pos = 0

proc flush*(buf: PBuffer) =
  buf.pos = 0
  buf.data.setLen(0)"""
  