import enet, sg_packets, estreams
type
  PClient* = ref object
    id*: int32
    auth*: bool
    alias*: string
    peer*: PPeer

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

