
import
  sockets, streams, tables, times, math, strutils, json, os, md5, 
  sfml, sfml_vector, sfml_colors, 
  streams_enh, input_helpers, zlib_helpers, sg_packets, sg_assets, sg_gui
type
  TClientSettings = object
    resolution*: TVideoMode
    offlineFile: string
    dirserver: tuple[host: string, port: TPort]
  PServer* = ref TServer
  TServer* = object
    sock: TSocket
    outgoing: PStringStream
var
  clientSettings: TClientSettings
  gui = newGuiContainer()
  zonelist = newGuiContainer()
  u_alias, u_passwd: PTextEntry
  activeInput = 0
  aliasText, passwdText: PText
  fpsTimer: PButton
  loginBtn: PButton
  playBtn: PButton
  keyClient = newKeyClient("lobby")
  showZonelist = false
  chatInput*: PTextEntry
  messageArea*: PMessageArea
var
  dirServer: PServer
  zone*: PServer
  activeServer: PServer
  bConnected = false
  outgoing = newStringStream("")
  incoming = newStringStream("")
  connectionButtons: seq[PButton] #buttons that depend on connection to function

template dispmessage(m: expr): stmt = 
  messageArea.add(m)

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

proc close*(s: PServer) =
  s.sock.close
  s.outgoing.flush

proc writePkt[T](serv: PServer; pid: PacketID, p: var T) =
  if serv.isNil: return
  serv.outgoing.write(pid)
  p.pack(serv.outgoing)
proc writePkt[T](pid: PacketID; p: var T) {.inline.} =
  if activeServer.isNil: return
  activeServer.writePkt pid, p

proc connectToDirserv() =
  if not dirServer.isNil:
    dirServer.close()
  dirServer = newServerConnection(clientSettings.dirserver.host, clientSettings.dirserver.port)
  var hello = newCsHello()
  dirServer.writePkt HHello, hello
  activeServer = dirServer


## TODO turn this into sockstream 
incoming.data.setLen 1024
incoming.data.setLen 0
incoming.flushImpl = proc(stream: PStream) =
  #echo("Flushing incoming")
  stream.setPosition(0)
  PStringStream(stream).data.setLen(0)

proc sendChat*(text: string) =
  var pkt = newCsChat(text = text)
  activeServer.writePkt HChat, pkt
proc zoneListReq() =
  var pkt = newCsZonelist("sup")
  writePkt HZonelist, pkt

##key handlers
keyClient.registerHandler(MouseMiddle, down, proc() = 
  gui.setPosition(getMousePos()))

keyClient.registerHandler(KeyO, down, proc() = 
  if keyPressed(KeyRShift): echo(repr(outgoing)))
keyClient.registerHandler(KeyTab, down, proc() =
  activeInput = (activeInput + 1) mod 2) #does this work?
keyClient.registerHandler(MouseLeft, down, proc() = 
  let p = getMousePos()
  gui.click(p)
  if showZonelist: zonelist.click(p))
var mptext = newText("", guiFont, 16)
keyClient.registerHandler(MouseRight, down, proc() = 
  let p = getMousePos()
  mptext.setPosition(p)
  mptext.setString("($1,$2)"%[$p.x.int,$p.y.int]))

proc dispChat(kind: ChatType, text: string, fromPlayer: string = "") = 
  var m = messageArea.add(
    if fromPlayer == "": text
    else: "<$1> $2" % [fromPlayer, text])
  case kind
  of CPub: m.setColor(RoyalBlue)
  of CSystem: m.setColor(Green)
  else: m.setColor(Red)
proc dispChat(msg: ScChat) {.inline.} =
  dispChat(msg.kind, msg.text, msg.fromPlayer)

proc setActiveZone(ind: int; zone: ScZoneRecord) =
  #hilight it or something
  dispmessage("Selected " & zone.name)
  
  
proc setConnected(state: bool) =
  if state:
    bConnected = true
    for b in connectionButtons: enable(b)
  else:
    bConnected = false
    for b in connectionButtons: disable(b)

var incomingHandlers = initTable[char, proc(s: PStream)](16)
incomingHandlers[HHello] = proc(s: PStream) = 
  let msg = readScHello(s)
  dispChat(CSystem, msg.resp)
  setConnected(true)
incomingHandlers[HLogin] = proc(s: PStream) =
  var info = readScLogin(s)
  dispmessage("We logged in :>")
incomingHandlers[HZonelist] = proc(s: PStream) =
  var 
    info = readScZonelist(s)
    zones = info.zones
  if zones.len > 0:
    zonelist.clearButtons()
    var pos = vec2f(0.0, 0.0)
    zonelist.newButton(
      text = "Zonelist - "& info.network,
      position = pos,
      onClick = proc(b: PButton) =
        dispmessage("Click on header"))
    pos.y += 20
    for i in 0..zones.len - 1:
      var z = zones[i]
      zonelist.newButton(
        text = z.name, position = pos,
        onClick = proc(b: PButton) = 
          setActiveZone(i, z))
      pos.y += 20
    showZonelist = true
incomingHandlers[HPoing] = proc(s: PStream) = 
  var ping = readPoing(s)
  dispmessage("Ping: "& $ping.time)
  ping.time = epochTime().float32
  writePkt HPoing, ping
incomingHandlers[HChat] = proc(s: PStream) =
  var msg = readScChat(s)
  dispChat(msg)

incomingHandlers[HFileChallenge] = proc(s: PStream) =
  var challenge = readScFileChallenge(s)
  var path = "data"
  case challenge.assetType
  of FGraphics:
    path.add "/gfx"
  of FSound:
    path.add "/sfx"
  else: nil
  
  var resp: CsFileChallenge
  if not existsFile(path / challenge.file):
    resp.needFile = true
  else:
    resp.checksum = toMD5(readFile(path / challenge.file))
  writePkt HFileChallenge, resp

proc copyWith(t: PText, text: string): PText =
  result = t.copy()

proc handlePkts(stream: PStream) =
  var iters = 0
  while not stream.atEnd:
    iters += 1
    var typ = readChar(stream)
    if not incominghandlers.hasKey(typ):
      echo("Unknown pkt ", repr(typ), '(', typ.ord,')')
      echo(repr(PStringStream(stream).data))
      break
    else:
      echo("Pkt ", typ)
      echo(repr(PStringStream(stream).data))
      incominghandlers[typ](stream)
  echo("handlePkts finished after ", iters, " iterations")

proc connectZone(host: string, port: TPort) =
  if zone.isNil:
    zone = newServerConnection(host, port)
  else:
    zone.sock.connect(host, port)
  var hello = newCsHello()
  zone.writePkt HHello, hello


proc pollDirserver(timeout: int): bool =
  if dirServer.isNil: return
  var ws = @[dirServer]

proc flush*(serv: PServer) =
  if serv.outgoing.getPosition > 0:
    let res = serv.sock.sendAsync(serv.outgoing.data)
    echo "send res: ", res
    serv.outgoing.flush()

const ChunkSize = 512
proc pollServer(s: PServer; timeout: int): bool =
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
    handlePkts(incoming)
    incoming.flush()
  if selectWrite(ws, timeout).bool:
    s.flush()
  result = true

proc lobbyReady*() = 
  keyClient.setActive()
  gui.setActive(u_alias)

proc tryConnect*(b: PButton) =
  connectToDirserv()
proc tryLogin*(b: PButton) =
  var login = newCsLogin(
    alias = u_alias.getText(),
    passwd = u_passwd.getText())
  writePkt HLogin, login
proc tryTransition*(b: PButton) =
  ##check if we're logged in
  #<implementation censored by the church>
  var errors: seq[string] = @[]
  if loadSettings("", errors):
    transition()
  else:
    for e in errors: dispmessage(e)
proc playOffline(b: PButton) =
  var errors: seq[string] = @[]
  if loadSettingsFromFile(clientSettings.offlineFile, errors):
    transition()
  else:
    dispmessage("Errors reading the file:")
    for e in errors: dispmessage(e)

proc getClientSettings*(): TClientSettings =
  result = clientSettings

proc lobbyInit*() =
  var s = json.parseFile("./client_settings.json")
  clientSettings.offlineFile = "zones/"
  clientSettings.offlineFile.add s["default-file"].str
  let dirserv = s["directory-server"]
  clientSettings.dirserver.host = dirserv["host"].str
  clientSettings.dirserver.port = dirserv["port"].num.TPort
  clientSettings.resolution.width = s["resolution"][0].num.cint
  clientSettings.resolution.height= s["resolution"][1].num.cint
  clientSettings.resolution.bitsPerPixel = s["resolution"][2].num.cint
  zonelist.setPosition(vec2f(200.0, 100.0))
  connectionButtons = @[]
  u_alias = gui.newTextEntry(
    if s.existsKey("alias"): s["alias"].str else: "alias", 
    vec2f(10.0, 10.0))
  u_passwd = gui.newTextEntry("buzz", vec2f(10.0, 30.0))
  connectionButtons.add(gui.newButton(
    text = "Login", 
    position = vec2f(10.0, 50.0),
    onClick = tryLogin,
    startEnabled = false))
  playBtn = gui.newButton(
    text = "Play",
    position = vec2f(680.0, 8.0),
    onClick = tryTransition,
    startEnabled = false)
  gui.newButton(
    text = "Play Offline",
    position = vec2f(680.0, 28.0),
    onClick = playOffline)
  fpsTimer = gui.newButton(
    text = "FPS: ",
    position = vec2f(10.0, 70.0),
    onClick = proc(b: PButton) = nil)
  gui.newButton(
    text = "Connect",
    position = vec2f(10.0, 90.0),
    onClick = tryConnect)
  connectionButtons.add(gui.newButton(
    text = "Test Chat",
    position = vec2f(10.0, 110.0),
    onClick = (proc(b: PButton) = 
      var pkt = newCsChat(text = "ohai")
      writePkt HChat, pkt),
    startEnabled = false))
  chatInput = gui.newTextEntry("...", vec2f(10.0, 575.0), proc() =
    sendChat(chatInput.getText())
    chatInput.clearText())
  messageArea = gui.newMessageArea(vec2f(10.0, 575.0 - 20.0))

var i = 0
proc lobbyUpdate*(dt: float) = 
  #let res = disp.poll()
  gui.update(dt)
  i = (i + 1) mod 60
  if i == 0:
    fpsTimer.setString("FPS: "& $round(1.0/dt))
  if not pollServer(dirServer, 10) and bConnected:
    setConnected(false)
    echo("Lost connection")
  discard pollServer(zone, 10)
    

proc lobbyDraw*(window: PRenderWindow) =
  window.clear(Black)
  window.draw messageArea
  window.draw mptext
  window.draw gui
  if showZonelist: window.draw zonelist
  window.display()
