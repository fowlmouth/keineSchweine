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


proc send*[T](serv: PServer; packetType: char; pkt: var T) =
  if serv.connected:
    var b = newBuffer(100)
    b.write packetType
    b.pack pkt
    discard serv.peer.send(0.cuchar, b, FlagUnsequenced)
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

proc connect*(serv: PServer; host: string; port: int16) =
  if setHost(serv.addy, host) != 0:
    quit "Could not set host"
  serv.addy.port = port.cushort
  serv.peer = serv.host.connect(serv.addy, 2, 0)
  if serv.peer == nil:
    quit "No available peers"
proc newServer*(host: string; port: int16): PServer =
  result = cast[ptr TServer](alloc0(sizeof(TServer)))
  result.connected = false
  result.host = createHost(nil, 1, 2, 0, 0)
  result.handlers = initTable[char, TScPktHandler](32)
  result.connect(host, port)



