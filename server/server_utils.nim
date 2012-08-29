import 
  streams, md5, sockets,
  sg_packets, zlib_helpers
type
  TClientType* = enum
    CServer = 0'i8, CPlayer
  PClient* = ref TClient
  TClient* = object of TObject
    id*: uint16
    addy*: TupAddress
    clientID*: uint16
    auth*: bool
    outputBuf*: PStringStream
    case kind*: TClientType
    of CPlayer:
      alias*: string
    of CServer:
      record*: ScZoneRecord
      cfg*: TChecksumFile
  TChecksumFile* = object
    sum*: MD5Digest
    contents*: string
  TupAddress* = tuple[host: string, port: int16]
  PIDGen*[T: Ordinal] = ref TIDGen[T]
  TIDGen[T: Ordinal] = object
    max: T
    freeIDs: seq[T]
var cliID: PIDGen[uint16]


proc free(idg: PIDgen) = 
  result.freeIDs = nil
proc newIDGen*[T: Ordinal](): PIDGen[T] =
  new(result, free)
  result.max = 0.T
  result.freeIDs = @[]
proc next*[T](idg: PIDGen[T]): T =
  if idg.freeIDs.len > 0:
    result = idg.freeIDs.pop
  elif idg.max < high(T)-1:
    result = idg.max
    idg.max += 1
  else:
    nil #system meltdown
proc free*[T](idg: PIDGen[T]; id: T) =
  idg.freeIDs.add id



proc free*(c: PClient) =
  cliID.free(c.id)
  c.outputBuf.flush()
  c.outputBuf = nil
  c.alias = nil
proc newClient*(addy: TupAddress): PClient =
  new(result, free)
  result.addy = addy
  result.id = cliID.next()
  result.kind = CPlayer
  result.alias = addy.host & ":" & $addy.port.uint16
  result.outputBuf = newStringStream("")
  result.outputBuf.flushImpl = proc(stream: PStream) = 
    stream.setPosition 0
    PStringStream(stream).data.setLen 0

proc `$`*(client: PClient): string =
  case client.kind
  of CPlayer: result = client.alias
  of CServer: result = client.record.zoneName
proc send*[T](client: PClient; pktType: char; pkt: var T) =
  client.outputBuf.write(pktType)
  pkt.pack(client.outputBuf)



proc checksumFile*(filename: string): TChecksumFile =
  result.contents = readFile(filename)
  result.sum = toMD5(result.contents)

cliID = newIDGen[uint16]()

discard """def validateAlias*(alias: string): bool =
  """