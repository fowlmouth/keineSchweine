import 
  streams, md5, sockets,
  sg_packets
type
  TClientType* = enum
    Server = 0'i8, Player
  PClient* = ref TClient
  TClient* = object of TObject
    addy*: TupAddress
    clientID*: uint16
    auth*: bool
    outputBuf*: PStringStream
    case kind*: TClientType
    of Player:
      alias*: string
    of Server:
      record*: ScZoneRecord
      cfg*: TChecksumFile
  TChecksumFile* = object
    sum*: MD5Digest
    contents*: string
  TupAddress* = tuple[host: string, port: int16]
  PIDGen*[T: Ordinal] = ref TIDGen
  TIDGen[T: Ordinal] = object
    max: T
    freeIDs: seq[T]


proc newClient*(addy: TupAddress): PClient =
  new(result)
  result.addy = addy
  result.kind = Player
  result.alias = addy.host & ":" & $addy.port.uint16
  result.outputBuf = newStringStream("")
  result.outputBuf.flushImpl = proc(stream: PStream) = 
    stream.setPosition 0
    PStringStream(stream).data.setLen 0
  


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

proc MD5File*(filename: string): TChecksumFile =
  result.contents = readFile(filename)
  result.sum = toMD5(result.contents)

discard """def validateAlias*(alias: string): bool =
  """