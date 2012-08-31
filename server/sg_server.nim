import
  sockets, times, streams, streams_enh, tables, json, os,
  sg_packets, sg_assets, md5, server_utils, client_helpers
type
  THandler = proc(client: PCLient; stream: PStream)
var
  server: TSocket
  dirServer: PServer
  handlers = initTable[char, THandler](16)
  thisZone = newScZoneRecord("local", "sup")
  thisZoneSettings: PZoneSettings
  zoneSettings: TChecksumFile
  ## I was high.
  clients = initTable[TupAddress, PClient](16)
  alias2client = initTable[string, PClient](32)
  allClients: seq[PClient] = @[] 
  zonePlayers: seq[PClient] = @[] 
const
  PubChatDelay = 100/1000 #100 ms

proc findClient*(host: string; port: int16): PClient =
  let addy: TupAddress = (host, port)
  if clients.hasKey(addy):
    return clients[addy]
  result = newClient(addy)
  clients[addy] = result
  allClients.add(result)

proc loginPlayer(client: PClient; login: CsLogin): bool =
  if client.auth:
    client.sendError("You are already logged in.")
    return
  if alias2client.hasKey(login.alias):
    client.sendError("Alias in use.")
    return
  client.auth = true
  client.kind = CPlayer
  client.alias = login.alias
  alias2client[client.alias] = client
  result = true

proc sendZoneList(client: PClient) = 
  echo(">> zonelist ", client)
  #client.send(HZonelist, zonelist)

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
  if client.login(loginInfo):
    client.sendMessage("Welcome "& client.alias)
    client.sendZonelist()
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

handlers[HZoneJoinReq] = proc(client: PClient; stream: PStream) =
  #var joinreq = readCsZoneJoinReq(stream)
  echo "Join zone request from ", client
  
type TFileChallenge = object
  filename: string
var fileChallenges = initTable[int16, TFileChallenge](32)
handlers[HFileChallenge] = proc(client: PClient; stream: PStream) =
  var fcResp = readCsFileChallenge(stream)
  if fcResp.needFile:
    nil
  else:
    nil

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

#var 
#  reads = @[server]
#  writes = @[server]
#let ready = select(reads, writes, timeout)
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
      #echo("<< ", res, " ", client.alias, ": ", len(line.data), " ", repr(line.data))
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
  var zoneCfgFile = "./server_settings.json"
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
  var jsonSettings = parseFile(zoneCfgFile)
  let 
    host = jsonSettings["host"].str
    port = TPort(jsonSettings["port"].num)
    zoneFile = jsonSettings["settings"].str
    dirServerInfo = jsonSettings["dirserver"]
  
  var path = getAppDir()/../"data"/zoneFile
  if not existsFile(path):
    echo("Zone settings file does not exist: ../data/", zoneFile)
    echo(path)
    quit(1)
  
  
  setCurrentDir getAppDir().parentDir()
  let zonesettingss = readFile(path)
  block:
    var 
      errors: seq[string] = @[]
    if not loadSettings(zoneSettingss, errors):
      echo("You have errors in your zone settings:")
      for e in errors: echo("**", e)
      quit(1)
  zoneSettings = checksumStr(zoneSettingsS)
  
  thisZone.name = jsonSettings["name"].str
  thisZone.desc = jsonSettings["desc"].str
  thisZone.ip = "localhost"
  thisZone.port = port
  var login = newSdZoneLogin(
    dirServerInfo[2].str, dirServerInfo[3].str,
    thisZone)  
  
  dirServer = newServerConnection(dirServerInfo[0].str, dirServerInfo[1].num.TPort)
  dirServer.handlers[HDsMsg] = proc(serv: PServer; stream: PStream) =
    var m = readDsMsg(stream)
    echo("DirServer> ", m.msg)
  dirServer.writePkt HZoneLogin, login
  
  createServer(port)
  echo("Listening on port ", port, "...")
  var pubChatTimer = cpuTime()#newClock()
  while true:
    discard dirServer.pollServer(15)
    poll(15)
    ## TODO sort this type of thing VV into a queue api
    #let now = cpuTime() 
    if cpuTime() - pubChatTimer > PubChatDelay:       #.getElapsedTime.asMilliseconds > 100:
      pubChatTimer -= pubChatDelay #.restart()
      if pubChatQueue.getPosition > 0:
        var cn = 0
        let sizePubChat = pubChatQueue.data.len
        for c in allClients:
          c.outputBuf.writeData(addr pubChatQueue.data[0], sizePubChat)
        pubChatQueue.flush()

  
  