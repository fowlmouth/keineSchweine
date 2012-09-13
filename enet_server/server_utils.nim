import enet, sg_packets, estreams, md5, zlib_helpers, client_helpers
type
  PClient* = ref object
    id*: int32
    auth*: bool
    alias*: string
    peer*: PPeer
  
  TChecksumFile* = object
    unpackedSize*: int
    sum*: MD5Digest
    compressed*: string

proc send*[T](client: PClient; pktType: char; pkt: var T) =
  var buf = newBuffer(128)
  buf.write pktType
  buf.pack pkt
  discard client.peer.send(0.cuchar, buf, flagReliable)

proc sendMessage*(client: PClient; txt: string) =
  var m = newScChat(CSystem, text = txt)
  client.send HChat, m
proc sendError*(client: PClient; error: string) =
  var m = newScChat(CError, text = error)
  client.send HChat, m


proc checksumFile*(filename: string): TChecksumFile =
  let fullText = readFile(filename)
  result.unpackedSize = fullText.len
  result.sum = toMD5(fullText)
  result.compressed = compress(fullText)
proc checksumStr*(str: string): TChecksumFile =
  result.unpackedSize = str.len
  result.sum = toMD5(str)
  result.compressed = compress(str)
