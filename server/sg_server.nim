import
  sockets, times, streams, streams_enh, tables, json, os, unsigned,
  sg_packets, sg_assets, md5, server_utils, client_helpers
type
  THandler = proc(client: PCLient; stream: PStream)
  FileChallengePair = tuple[challenge: ScFileChallenge; file: TChecksumFile]
var
  server: TSocket
  dirServer: PServer
  handlers = initTable[char, THandler](16)
  thisZone = newScZoneRecord("local", "sup")
  thisZoneSettings: PZoneSettings
  dirServerConnected = false
  myAssets: seq[FileChallengePair] = @[]
  ## I was high.
  clients = initTable[TupAddress, PClient](16)
  alias2client = initTable[string, PClient](32)
  allClients: seq[PClient] = @[] 
  zonePlayers: seq[PClient] = @[] 
const
  PubChatDelay = 100/1000 #100 ms

import hashes
proc hash*(x: uint16): THash {.inline.} = 
  result = int32(x)

proc findClient*(host: string; port: int16): PClient =
  let addy: TupAddress = (host, port)
  if clients.hasKey(addy):
    return clients[addy]
  result = newClient(addy)
  clients[addy] = result
  allClients.add(result)


proc sendZoneList(client: PClient) = 
  echo(">> zonelist ", client)
  #client.send(HZonelist, zonelist)

proc forwardPrivate(rcv: PClient; sender: PClient; txt: string) =
  var m = newScChat(CPriv, sender.alias, txt)
  rcv.send(HChat, m)
proc sendChat(client: PClient; kind: ChatType; txt: string) =
  echo(">> chat ", client)
  var m = newScChat(kind, "", txt)
  client.send(HChat, m)

var pubChatQueue = newStringStream("")
pubChatQueue.flushImpl = proc(stream: PStream) =
  stream.setPosition(0)
  PStringStream(stream).data.setLen(0)
proc queuePub(sender: string, msg: CsChat) =
  var chat = newScChat(kind = CPub, fromPlayer = sender, text = msg.text)
  pubChatQueue.write(HChat)
  chat.pack(pubChatQueue)

handlers[HHello] = (proc(client: PClient; stream: PStream) =
  var h = readCsHello(stream)
  if h.i == 14:
    var greet = newScHello("Well hello there")
    client.send(HHello, greet))
handlers[HLogin] = proc(client: PClient; stream: PStream) =
  var loginInfo = readCsLogin(stream)
  echo("** login: alias = ", loginInfo.alias)
  if not dirServerConnected and client.loginPlayer(loginInfo):
    client.sendMessage("Welcome "& client.alias)
    alias2client[client.alias] = client
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

type
  PFileChallengeSequence* = ref TFileChallengeSequence 
  TFileChallengeSequence = object
    index: int  #which file is active
    transfer: ScFileTransfer
    file: ptr FileChallengePair
const FileChunkSize = 256
var fileChallenges = initTable[uint16, PFileChallengeSequence](32)

proc next*(challenge: PFileChallengeSequence, client: PClient)
proc sendChunk*(challenge: PFileChallengeSequence, client: PClient)

proc startVerifyingFiles*(client: PClient) =
  var fcs: PFileChallengeSequence
  new(fcs)
  fcs.index = -1
  fileChallenges[client.id] = fcs
  next(fcs, client)

proc next*(challenge: PFileChallengeSequence, client: PClient) =
  inc(challenge.index)
  if challenge.index >= myAssets.len:
    client.sendMessage "You are cleared to enter"
    fileChallenges.del client.id
    return
  challenge.file = addr myAssets[challenge.index]
  client.send HFileChallenge, challenge.file.challenge # :rolleyes:

proc sendChunk*(challenge: PFileChallengeSequence, client: PClient) =
  let size = min(FileChunkSize, challenge.transfer.fileSize - challenge.transfer.pos)
  challenge.transfer.data.setLen size
  copyMem(
    addr challenge.transfer.data[0], 
    addr challenge.file.file.compressed[challenge.transfer.pos],
    size)
  client.send HFileTransfer, challenge.transfer

proc startSend*(challenge: PFileChallengeSequence, client: PClient) =
  challenge.transfer.fileSize = challenge.file.file.compressed.len().int32
  challenge.transfer.pos = 0
  challenge.transfer.data = ""
  challenge.transfer.data.setLen FileChunkSize
  challenge.sendChunk(client)

handlers[HZoneJoinReq] = proc(client: PClient; stream: PStream) =
  var req = readCsZoneJoinReq(stream)
  echo "Join zone request from (",req.session.id,") ", req.session.alias 
  if client.auth and client.kind == CPlayer:
    echo "Client is authenticated, verifying filez"
    client.startVerifyingFiles()
  elif dirServerConnected:
    echo "Dirserver is connected, verifying client"
    dirServer.send HVerifyClient, req.session
  else:
    echo "Dirserver is disconnected =("
    client.startVerifyingFiles()

handlers[HFileTransfer] = proc(client: PClient; stream: PStream) = 
  var 
    ftrans = readCsFilepartAck(stream)
    fcSeq = fileChallenges[client.id]
  fcSeq.transfer.pos = ftrans.lastPos
  fcSeq.sendChunk client

handlers[HFileChallenge] = proc(client: PClient; stream: PStream) =
  var 
    fcResp = readCsFileChallenge(stream)
    fcSeq = fileChallenges[client.id]
    resp = newScChallengeResult(false)
  if fcResp.needFile:
    client.sendMessage "Sending file..."
    fcSeq.startSend(client)
  else:
    var res = newScChallengeResult(false)
    if fcResp.checksum == fcSeq.file.file.sum: ##client is good
      #client.sendMessage "Checksum is good. ("& $(fcSeq.index+1) &'/'& $(myAssets.len) &')'
      res.status = true
      client.send HChallengeResult, res
      fcSeq.next(client)
    else:
      #client.sendMessage "Checksum is bad, sending file..."
      client.send HChallengeResult, res
      fcSeq.startSend(client)

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
var incoming = newIncomingBuffer()
proc poll*(timeout: int = 250) =
  if server.isNil: return
  var 
    reads = @[server]
    writes = @[server]
  if select(reads, timeout) > 0:
    var
      addy = ""
      port: TPort
    let res = server.recvFromAsync(incoming.data, 512, addy, port, 0)
    if not res:
      echo("No recv")
      return
    else:
      var client = findClient(addy, port.int16)
      #echo("<< ", res, " ", client.alias, ": ", len(line.data), " ", repr(line.data))
      handlePkt(client, incoming)
    incoming.flush()
  if selectWrite(writes, timeout) > 0:
    let nclients = allClients.len
    if nclients == 0:
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
  
  ## Test file
  block:
    var 
      TestFile: FileChallengePair
      contents = repeatStr(2, "abcdefghijklmnopqrstuvwxyz")
    testFile.challenge = newScFileChallenge("foobar.test", FZoneCfg, contents.len.int32) 
    testFile.file = checksumStr(contents)
    myAssets.add testFile
  
  setCurrentDir getAppDir().parentDir()
  block:
    let zonesettings = readFile(path)
    var 
      errors: seq[string] = @[]
    if not loadSettings(zoneSettings, errors):
      echo("You have errors in your zone settings:")
      for e in errors: echo("**", e)
      quit(1)
    errors.setLen 0
    
    var pair: FileChallengePair
    pair.challenge.file = zoneFile
    pair.challenge.assetType = FZoneCfg
    pair.challenge.fullLen = zoneSettings.len.int32
    pair.file = checksumStr(zoneSettings)
    myAssets.add pair
    
    allAssets:
      if not load(asset):
        echo "Invalid or missing file ", file
      else:
        var pair: FileChallengePair
        pair.challenge.file = file
        pair.challenge.assetType = assetType
        pair.challenge.fullLen = getFileSize(
          expandPath(assetType, file)).int32
        pair.file = asset.contents
        myAssets.add pair
  
  
      echo "Zone has ", myAssets.len, " associated assets"
  
  thisZone.name = jsonSettings["name"].str
  thisZone.desc = jsonSettings["desc"].str
  thisZone.ip = "localhost"
  thisZone.port = port
  var login = newSdZoneLogin(
    dirServerInfo[2].str, dirServerInfo[3].str,
    thisZone)  
  #echo "MY LOGIN: ", $login
  
  dirServer = newServerConnection(dirServerInfo[0].str, dirServerInfo[1].num.TPort)
  dirServer.handlers[HDsMsg] = proc(serv: PServer; stream: PStream) =
    var m = readDsMsg(stream)
    echo("DirServer> ", m.msg)
  dirServer.handlers[HZoneLogin] = proc(serv: PServer; stream: PStream) =
    let loggedIn = readDsZoneLogin(stream).status
    if loggedIn:
      dirServerConnected = true
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

  
  