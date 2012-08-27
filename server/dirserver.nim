## directory server
## handles client authorization and assets

import
  sockets, times, streams, streams_enh, tables, json, os,
  sg_packets, sg_assets, sfml, md5
type
  TServer = object
  THandler = proc(client: PCLient; stream: PStream)
  PClient* = ref TClient
  TClient* = object
    addy: TAddress
    auth: bool
    alias: string
    outputBuf: PStringStream
  PZone = ref TZone
  TZone = object
    name: string
    host: string
    port: TPort
    key: string
    sockaddr: TAddress
  TAddress* = tuple[host: string, port: int16]
var
  server: TSocket
  handlers = initTable[char, THandler](16)
  thisZone = newScZoneRecord("local", "sup")
  zoneList = newScZoneList()
  thisZoneSettings: string
  zoneSlots: seq[tuple[name: string; key: string]] = @[]
  zones: seq[PZone] = @[]
  ## I was high.
  clients = initTable[TAddress, PClient](16)
  alias2client = initTable[string, PClient](32)
  allClients: seq[PClient] = @[] 

proc newClient*(addy: TAddress): PClient =
  new(result)
  result.addy = addy
  result.alias = addy.host & ":" & $addy.port.uint16
  result.outputBuf = newStringStream("")
  result.outputBuf.flushImpl = proc(stream: PStream) =
    var s = PStringStream(stream)
    s.setPosition 0
    s.data.setLen 0
  clients[addy] = result
  allClients.add(result)
proc findClient*(host: string; port: int16): PClient =
  let addy: TAddress = (host, port)
  if clients.hasKey(addy):
    return clients[addy]
  result = newClient(addy)
proc send*(client: PClient; msg: string): int {.discardable.} =
  result = server.sendTo(client.addy.host, client.addy.port.TPort, msg)
proc send*[T](client: PClient; pktType: char; pkt: var T) =
  #echo(">> ", client, " ", pktType)
  #echo(client.outputBuf.getPosition())
  client.outputBuf.write(pktType)
  pkt.pack(client.outputBuf)
  #echo("output buf is now ", repr(client.outputBuf))
proc setAlias(client: PClient; newName: string): bool =
  if alias2client.hasKey(newName):
    return
  if alias2client.hasKey(client.alias):
    alias2client.del(client.alias)
  client.alias = newName
  alias2client[newName] = client
  result = true
proc `$`*(client: PClient): string =
  result = client.alias

proc sendZoneList(client: PClient) = 
  echo(">> zonelist ", client)
  client.send(HZonelist, zonelist)
proc forwardPrivate(rcv: PClient; sender: PClient; txt: string) =
  var m = newScChat(CPriv, sender.alias, txt)
  rcv.send(HChat, m)
proc sendMessage(client: PClient; txt: string) =
  echo(">> sys msg ", client)
  var m = newScChat(CSystem, "", txt)
  client.send(HChat, m)
proc sendChat(client: PClient; kind: ChatType; txt: string) =
  echo(">> chat ", client)
  var m = newScChat(kind, "", txt)
  client.send(HChat, m)
proc sendError(client: PClient; txt: string) {.inline.} =
  sendChat(client, CError, txt)

var pubChatQueue = newStringStream("")
pubChatQueue.flushImpl = proc(stream: PStream) =
  stream.setPosition(0)
  PStringStream(stream).data.setLen(0)
proc queuePub(sender: string, msg: CsChat) =
  var chat = newScChat(kind = CPub, fromPlayer = sender, text = msg.text)
  pubChatQueue.write(HChat)
  chat.pack(pubChatQueue)

template dont(e: expr): stmt {.immediate.} = nil
handlers[HHello] = (proc(client: PClient; stream: PStream) =
  var h = readCsHello(stream)
  if h.i == 14:
    var greet = newScHello("Well hello there")
    client.send(HHello, greet))
handlers[HLogin] = proc(client: PClient; stream: PStream) =
  var loginInfo = readCsLogin(stream)
  echo("** login: alias = ", loginInfo.alias)
  if client.auth:
    client.sendError("You are already logged in.")
  else:
    if client.setAlias(loginInfo.alias):
      client.auth = true
      client.sendMessage("Welcome "& client.alias)
      client.sendZonelist()
    else:
      client.sendError("Invalid alias")
handlers[HZoneList] = proc(client: PClient; stream: PStream) =
  var pinfo = readCsZoneList(stream)
  echo("** zonelist req")
handlers[HChat] = proc(client: PClient; stream: PStream) =
  var chat = readCsChat(stream)
  if not client.auth:
    client.sendError("You are not logged in.")
    return
  if chat.target != "": ##private
    if alias2client.hasKey(chat.target):
      alias2client[chat.target].forwardPrivate(client, chat.text)
  else:
    queuePub(client.alias, chat)
handlers[HZoneQuery] = proc(client: PClient; stream: PStream) =
  echo("Got zone query")
  var q = readCsZoneQuery(stream)
  var resp = newScZoneQuery(zonePlayers.len.uint16)
  client.send(HZoneQuery, resp)


proc zoneLogin(client: PClient; login: SdZoneLogin) =
  for s in zoneSlots.items:
    if s.name == login.name and s.key == login.key:
      
    
handlers[HZoneLogin] = proc(client: PClient; stream: PStream) =
  var 
    login = readSdZoneLogin(stream)
  zoneLogin(client, login)


proc handlePkt(s: PClient; stream: PStream) =
  while not stream.atEnd:  
    var typ = readChar(stream)
    if not handlers.hasKey(typ):
      break
    else:
      handlers[typ](s, stream)

proc createServer(port: TPort) =
  if not server.isNil:
    server.close()
  server = socket(typ = SOCK_DGRAM, protocol = IPPROTO_UDP, buffered = false)
  server.bindAddr(port)


var clientIndex = 0
proc poll*(timeout: int = 250) =
  if server.isNil: return
  var 
    reads = @[server]
    writes = @[server]
  if select(reads, timeout) > 0:
    var
      addy = ""
      port: TPort
      line = newStringStream("")
    let res = server.recvFromAsync(line.data, 512, addy, port, 0)
    if not res:
      echo("No recv")
      return
    else:
      var client = findClient(addy, port.int16)
      echo("<< ", res, " ", client.alias, ": ", len(line.data), " ", repr(line.data))
      handlePkt(client, line)
  if selectWrite(writes, timeout) > 0:
    let nclients = allClients.len
    if nclients == 0: 
      stdout.write(".")
      return
    clientIndex = (clientIndex + 1) mod nclients
    var c = allClients[clientIndex]
    if c.outputBuf.getPosition > 0:
      let res = server.sendTo(c.addy.host, c.addy.port.TPort, c.outputBuf.data)
      echo("Write ", c, " result: ", res, " data: ", c.outputBuf.data)
      c.outputBuf.flush()

when isMainModule:
  import parseopt, matchers, strutils
  var cfgFile = "dirserver_settings.json"
  for kind, key, val in getOpt():
    case kind
    of cmdShortOption, cmdLongOption:
      case key
      of "f", "file": 
        if existsFile(val):
          zoneCfgFile = val
        else:
          echo("File does not exist: ", val)
      else:
        echo("Unknown option: ", key," ", val)
    else:
      echo("Unknown option: ", key, " ", val)
  var jsonSettings = parseFile(cfgFile)
  let port = TPort(jsonSettings["port"].num)
  zonelist.network = jsonSettings["network"].str
  for slot in jsonSettings["zones"].items:
    zoneSlots.add((slot["name"].str, slot["key"].str))
  
  createServer(port)
  echo("Listening on port ", port, "...")
  var pubChatTimer = newClock()
  while true:
    poll(15)
    ## TODO sort this type of thing VV into a queue api 
    if pubChatTimer.getElapsedTime.asMilliseconds > 100:
      pubChatTimer.restart()
      if pubChatQueue.getPosition > 0:
        var cn = 0
        let sizePubChat = pubChatQueue.data.len
        for c in allClients:
          c.outputBuf.writeData(addr pubChatQueue.data[0], sizePubChat)
        pubChatQueue.flush()

