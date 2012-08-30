import 
  streams, md5, sockets, unsigned,
  sg_packets, zlib_helpers
type
  TClientType* = enum
    CServer = 0'i8, CPlayer, CUnknown
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
    of CUnknown: nil
  TChecksumFile* = object
    unpackedSize*: int
    sum*: MD5Digest
    compressed*: string
  TupAddress* = tuple[host: string, port: int16]
  PIDGen*[T: Ordinal] = ref TIDGen[T]
  TIDGen[T: Ordinal] = object
    max: T
    freeIDs: seq[T]
var cliID: PIDGen[uint16]


#proc free[T](idg: PIDgen[T]) = 
#  result.freeIDs = nil
proc newIDGen*[T: Ordinal](): PIDGen[T] =
  new(result)#, free)
  result.max = 0.T
  result.freeIDs = @[]
proc next*[T](idg: PIDGen[T]): T =
  if idg.freeIDs.len > 0:
    result = idg.freeIDs.pop
  elif idg.max < high(T)-T(1):
    result = idg.max
    idg.max += 1
  else:
    nil #system meltdown
proc del*[T](idg: PIDGen[T]; id: T) =
  idg.freeIDs.add id


proc free*(c: PClient) =
  cliID.del c.id
  c.outputBuf.flush()
  c.outputBuf = nil
proc newClient*(addy: TupAddress): PClient =
  new(result, free)
  result.addy = addy
  result.id = cliID.next()
  result.outputBuf = newStringStream("")
  result.outputBuf.flushImpl = proc(stream: PStream) = 
    stream.setPosition 0
    PStringStream(stream).data.setLen 0

proc `$`*(client: PClient): string =
  if not client.auth: return $client.addy
  case client.kind
  of CPlayer: result = client.alias
  of CServer: result = client.record.name
  else: result = $client.addy
proc send*[T](client: PClient; pktType: char; pkt: var T) =
  client.outputBuf.write(pktType)
  pkt.pack(client.outputBuf)


proc checksumFile*(filename: string): TChecksumFile =
  let fullText = readFile(filename)
  result.unpackedSize = fullText.len
  result.sum = toMD5(fullText)
  result.compressed = compress(fullText)
proc checksumStr*(str: string): TChecksumFile =
  result.unpackedSize = str.len
  result.sum = toMD5(str)
  result.compressed = compress(str)

cliID = newIDGen[uint16]()#[uint16]()

discard """def validateAlias*(alias: string): bool =
  """