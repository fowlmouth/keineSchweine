import 
  sockets, streams, tables,
  sg_packets
type
  PServer* = ref TServer
  TServer* = object
    sock*: TSocket
    outgoing*: PStringStream
    handlers*: TTable[char, TScPktHandler]
  TScPktHandler* = proc(serv: PServer; stream: PStream)
var
  incoming = newStringStream("")

incoming.data.setLen 1024
incoming.data.setLen 0
incoming.flushImpl = proc(stream: PStream) =
  stream.setPosition 0
  PStringStream(stream).data.setLen 0

proc newServerConnection*(host: string; port: TPort): PServer =
  new(result)
  echo "Connecting to ", host, ":", port
  result.sock = socket(typ = SOCK_DGRAM, protocol = IPPROTO_UDP, buffered = false)
  result.sock.connect host, port
  result.outgoing = newStringStream("")
  result.outgoing.data.setLen 1024
  result.outgoing.data.setLen 0
  result.outgoing.flushImpl = proc(stream: PStream) =
    if stream.getPosition == 0: return
    stream.setPosition 0
    PStringStream(stream).data.setLen 0
  result.handlers = initTable[char, TScPktHandler](16)

proc flush*(serv: PServer) =
  if serv.outgoing.getPosition > 0:
    let res = serv.sock.sendAsync(serv.outgoing.data)
    echo "send res: ", res
    serv.outgoing.flush()
proc close*(s: PServer) =
  s.sock.close
  s.outgoing.flush

proc writePkt*[T](serv: PServer; pid: PacketID, p: var T) =
  if serv.isNil: return
  serv.outgoing.write(pid)
  p.pack(serv.outgoing)


proc sendChat*(serv: PServer; text: string) =
  var pkt = newCsChat(text = text)
  serv.writePkt HChat, pkt

proc handlePkts(serv: PServer; stream: PStream) =
  while not stream.atEnd:
    var typ = readChar(stream)
    if not serv.handlers.hasKey(typ):
      echo("Unknown pkt ", repr(typ), '(', typ.ord,')')
      echo(repr(PStringStream(stream).data))
      break
    else:
      serv.handlers[typ](serv, stream)


const ChunkSize = 512
proc pollServer*(s: PServer; timeout: int): bool =
  if s.isNil or s.sock.isNil: return true
  var
    ws = @[s.sock]
    rs = @[s.sock]
  if select(rs, timeout).bool:
    var recvd = 0
    while true:
      let pos = incoming.data.len
      setLen(incoming.data, pos + ChunkSize)
      #let res = client.recvAsync(incoming.data)
      let res = s.sock.recv(addr incoming.data[pos], ChunkSize)
      echo("Read ", res)
      if res > 0:
        if res < ChunkSize:
          incoming.data.setLen(incoming.data.len - (ChunkSize - res))
          break
      else: break
    handlePkts(s, incoming)
    incoming.flush()
  if selectWrite(ws, timeout).bool:
    s.flush()
  result = true
