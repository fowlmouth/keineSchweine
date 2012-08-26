
import
  sockets, streams, tables, times, math, strutils, json,
  sfml, sfml_vector, sfml_colors, 
  streams_enh, input, sg_packets, sg_assets, sg_gui
type
  TClientSettings = object
    offlineFile: string
    dirserver: tuple[host: string, port: TPort]
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
  client: TSocket
  bConnected = false
  outgoing = newStringStream("")
  incoming = newStringStream("")
  connectionButtons: seq[PButton] #buttons that depend on connection to function

template dispmessage(m: expr): stmt = 
  messageArea.add(m)

## TODO turn this into sockstream 
incoming.data.setLen 1024
incoming.data.setLen 0
outgoing.data.setLen 1024
outgoing.data.setLen 0
outgoing.flushImpl = proc(stream: PStream) =
  if stream.getPosition() == 0: return
  var s = PStringStream(stream)
  discard client.sendAsync(s.data)
  s.setPosition(0)
  s.data.setLen(0)
incoming.flushImpl = proc(stream: PStream) =
  #echo("Flushing incoming")
  stream.setPosition(0)
  PStringStream(stream).data.setLen(0)

proc writePkt[T](pid: PacketID, p: var T) =
  outgoing.write(pid)
  p.pack(outgoing)

proc sendChat*(text: string) =
  var pkt = newCsChat(text = text)
  writePkt HChat, pkt
proc zoneListReq() =
  var pkt = newCsZonelist("sup")
  writePkt HZonelist, pkt

##key handlers
keyClient.registerHandler(KeyM, down, proc() = 
  echo(repr(gui.renderState), "\n--------"))
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

proc connect(host: string, port: TPort) =
  if not client.isNil: 
    client.close()
  client = socket(typ = SOCK_DGRAM, protocol = IPPROTO_UDP, buffered = false)
  client.connect(host, port)
  var hello = newCsHello()
  writePkt HHello, hello

proc poll(timeout: int): bool =
  if client.isNil: return
  var
    ws = @[client]
    rs = @[client]
  if select(rs, timeout).bool:
    setLen(incoming.data, 512)
    #let res = client.recvAsync(incoming.data)
    let res = client.recv(addr incoming.data[0], 512)
    echo("Read ", res)
    if res > 0:
      incoming.data.setLen(res)
      handlePkts(incoming)
    incoming.flush()
  if selectWrite(ws, timeout).bool:
    outgoing.flush()
  result = true

proc lobbyReady*() = 
  keyClient.setActive()
  gui.setActive(u_alias)

proc tryConnect*(b: PButton) =
  echo("Connecting...")
  connect(clientSettings.dirserver.host, clientSettings.dirserver.port)
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

proc lobbyInit*() =
  var s = json.parseFile("./client_settings.json")
  clientSettings.offlineFile = "zones/"
  clientSettings.offlineFile.add s["default-file"].str
  let dirserv = s["directory-server"]
  clientSettings.dirserver.host = dirserv["host"].str
  clientSettings.dirserver.port = dirserv["port"].num.TPort
  
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
  if not poll(10) and bConnected:
    setConnected(false)
    echo("Lost connection")

proc lobbyDraw*(window: PRenderWindow) =
  window.clear(Black)
  window.draw messageArea
  window.draw mptext
  window.draw gui
  if showZonelist: window.draw zonelist
  window.display()
