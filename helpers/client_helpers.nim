import 
  sockets, streams, tables,
  sg_packets, enet, estreams
type
  PServer* = ptr TServer
  TServer* = object
    connected*: bool
    addy: enet.TAddress
    host*: PHost
    peer*: PPeer
    handlers*: TTable[char, TScPktHandler]
  TScPktHandler* = proc(serv: PServer; buffer: PBuffer)


proc addHandler*(serv: PServer; packetType: char; handler: TScPktHandler) =
  serv.handlers[packetType] = handler

proc newServer*(): PServer =
  result = cast[PServer](alloc0(sizeof(TServer)))
  result.connected = false
  result.host = createHost(nil, 1, 2, 0, 0)
  result.handlers = initTable[char, TScPktHandler](32)

proc connect*(serv: PServer; host: string; port: int16; error: var string): bool =
  if setHost(serv.addy, host) != 0:
    error = "Could not resolve host "
    error.add host
    return false
  serv.addy.port = port.cushort
  serv.peer = serv.host.connect(serv.addy, 2, 0)
  if serv.peer.isNil:
    error = "Could not connect to host "
    error.add host
    return false
  return true

proc send*[T](serv: PServer; packetType: char; pkt: var T) =
  if serv.connected:
    var b = newBuffer(100)
    b.write packetType
    b.pack pkt
    serv.peer.send(0.cuchar, b, FlagUnsequenced)
proc sendPubChat*(server: PServer; msg: string) =
  var chat = newCsChat("", msg)
  server.send HChat, chat

proc handlePackets*(server: PServer; buf: PBuffer) =
  while not buf.atEnd():
    let typ = readChar(buf)
    if server.handlers.hasKey(typ):
      server.handlers[typ](server, buf)
    else:
      break
