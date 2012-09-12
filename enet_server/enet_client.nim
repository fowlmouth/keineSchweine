import enet, strutils,
  sfml, sfml_vector, sfml_colors, sg_gui, input_helpers,
  math_helpers, sg_packets, estreams, tables,
  json, sg_assets
if enetInit() != 0:
  quit "Could not initialize ENet"
type
  TClientSettings = object
    resolution*: TVideoMode
    offlineFile: string
    dirserver: tuple[host: string, port: int16]
    website*: string
  PServer = ptr TServer
  TServer = object
    connected: bool
    addy: enet.TAddress
    host: PHost
    peer: PPeer
    handlers: TTable[char, TCallback]
  
  TCallback = proc(serv: PServer; buffer: PBuffer) 
var
  clientSettings: TClientSettings
  event: enet.TEvent
  bConnected = false
  runServer = true
  gui = newGuiContainer()
  zonelist = newGuiContainer()
  kc = newKeyClient(setActive = true)
  clock = newClock()
  chatBox: PMessageArea
  chatInput: PTextEntry
  loginBtn, playBtn: PButton
  fpsText = newText("", guiFont, 18)
  connectionButtons: seq[PButton]
  downloadProgress: PButton
  u_alias, u_passwd: PTextEntry
  dirServer: PServer
  zone: PServer
  showZoneList = false
  myCreds: ScLogin ##my session token

proc handleChat(server: PServer; buf: PBuffer) =
  let msg = readScChat(buf)
  chatBox.add msg
proc handlePlayerLogin(server: PServer; buf: PBuffer) =
  let login = readScLogin(buf)
  myCreds = login
  echo("I am ", $myCreds)

proc handlePackets(server: PServer; buf: PBuffer) =
  while not buf.atEnd():
    let typ = readChar(buf)
    if server.handlers.hasKey(typ):
      server.handlers[typ](server, buf)
    else:
      break

proc connect(serv: PServer; host: string; port: int16) =
  if setHost(serv.addy, host) != 0:
    quit "Could not set host"
  serv.addy.port = port.cushort
  serv.peer = serv.host.connect(serv.addy, 2, 0)
  if serv.peer == nil:
    quit "No available peers"
proc newServer(host: string; port: int16): PServer =
  result = cast[ptr TServer](alloc0(sizeof(TServer)))
  result.connected = false
  result.host = createHost(nil, 1, 2, 0, 0)
  result.handlers = initTable[char, TCallback](32)
  result.connect(host, port)
proc sendPubChat(server: PServer; msg: string)

kc.registerHandler MouseLeft, down, proc() =
  gui.click(input_helpers.getMousePos())

block:
  var pos = vec2f(15, 550)
  chatBox = gui.newMessageArea(pos)
  pos.y += 20
  chatInput = gui.newTextEntry("...", pos, proc() =
    sendPubChat dirServer, chatInput.getText()
    chatInput.clearText())

gui.setActive(chatInput)

proc dispMessage(args: varargs[string, `$`]) =
  var s = ""
  for it in items(args):
    s.add it
  chatbox.add(s)
proc dispMessage(text: string) {.inline.} =
  chatbox.add(text)

proc send*[T](serv: PServer; packetType: char; pkt: var T) =
  if serv.connected:
    var b = newBuffer(100)
    b.write packetType
    b.pack pkt
    discard serv.peer.send(0.cuchar, b, FlagUnsequenced)
proc sendPubChat(server: PServer; msg: string) =
  var chat = newCsChat("", msg)
  server.send HChat, chat

proc updateButtons() =
  let conn = dirServer.connected
  for b in connectionButtons: setEnabled(b, conn)

proc poll(serv: PServer; timeout: cuint = 30) =
  if serv.isNil or serv.host.isNil: return
  if serv.connected:
    while serv.host.hostService(event, timeout) > 0:
      case event.kind
      of EvtReceive:
        var buf = newBuffer(event.packet)
        
        serv.handlePackets(buf)
        
        event.packet.destroy()
      of EvtDisconnect:
        dispMessage "Disconnected"
        serv.connected = false
        event.peer.data = nil
        updateButtons()
      of EvtNone: discard
      else:
        echo repr(event)
  else:
    if serv.host.hostService(event, 40) > 0 and event.kind == EvtConnect:
      dispMessage "Connected"
      serv.connected = true
      if serv.peer != event.peer:
        serv.peer = event.peer
      event.peer.data = serv
      updateButtons()

proc tryLogin*(b: PButton) =
  var login = newCsLogin(
    alias = u_alias.getText(),
    passwd = u_passwd.getText())
  dirServer.send HLogin, login
proc tryTransition*(b: PButton) =
  #zone.writePkt HZoneJoinReq, mySession

proc playOffline*(b: PButton) =
  var errors: seq[string] = @[]
  if loadSettingsFromFile(clientSettings.offlineFile, errors):
    transition()
  else:
    dispmessage("Errors reading the file ("& clientSettings.offlineFile &"):")
    for e in errors: dispmessage(e)

proc getClientSettings*(): TClientSettings =
  result = clientSettings


proc lobbyInit*() =
  var s = json.parseFile("./client_settings.json")
  clientSettings.offlineFile = "data/"
  clientSettings.offlineFile.add s["default-file"].str
  let dirserv = s["directory-server"]
  clientSettings.dirserver.host = dirserv["host"].str
  clientSettings.dirserver.port = dirserv["port"].num.int16
  clientSettings.resolution.width = s["resolution"][0].num.cint
  clientSettings.resolution.height= s["resolution"][1].num.cint
  clientSettings.resolution.bitsPerPixel = s["resolution"][2].num.cint
  clientSettings.website = s["website"].str
  zonelist.setPosition(vec2f(200.0, 100.0))
  connectionButtons = @[]
  
  downloadProgress = gui.newButton(
    text = "", position = vec2f(10, 130), onClick = nil) 
  downloadProgress.bg.setFillColor(color(34, 139, 34))
  downloadProgress.bg.setSize(vec2f(0, 0))
  
  var pos = vec2f(10, 10)
  u_alias = gui.newTextEntry(
    if s.existsKey("alias"): s["alias"].str else: "alias", 
    pos)
  pos.y += 20
  u_passwd = gui.newTextEntry("buzz", pos)
  pos.y += 20
  connectionButtons.add(gui.newButton(
    text = "Login", 
    position = pos,
    onClick = tryLogin,
    startEnabled = false))
  pos.y += 20
  fpsText.setPosition pos
  
  playBtn = gui.newButton(
    text = "Play",
    position = vec2f(680.0, 8.0),
    onClick = tryTransition,
    startEnabled = false)
  gui.newButton(
    text = "Play Offline",
    position = vec2f(680.0, 28.0),
    onClick = playOffline)
  discard """gui.newButton(
    text = "Connect",
    position = vec2f(10.0, 90.0),
    onClick = tryConnect)"""
  connectionButtons.add(gui.newButton(
    text = "Test Chat",
    position = vec2f(10.0, 110.0),
    onClick = (proc(b: PButton) = 
      var pkt = newCsChat(text = "ohai")
      dirServer.send HChat, pkt),
    startEnabled = false))
  discard """gui.newButton(text = "Scrollback + 1", position = vec2f(185, 10), onClick = proc(b: PButton) =
    messageArea.scrollBack += 1
    update(messageArea))
  gui.newButton(text = "Scrollback - 1", position = vec2f(185+160, 10), onClick = proc(b: PButton) = 
    messageArea.scrollBack -= 1
    update(messageArea))
  gui.newButton(text = "Flood msg area", position = vec2f(185, 30), onClick = proc(b: PButton) =
    for i in 0.. <30: 
      dispMessage($i))"""
  dirServer = newServer(clientSettings.dirserver.host, clientSettings.dirServer.port)
  dirServer.handlers[HChat] = handleChat
  dirServer.handlers[HLogin] = handlePlayerLogin

proc lobbyReady*() = 
  kc.setActive()
  gui.setActive(u_alias)

var i = 0
proc lobbyUpdate*(dt: float) =
  dirServer.poll()
  #let res = disp.poll()
  gui.update(dt)
  i = (i + 1) mod 60
  if i == 0:
    fpsText.setString("FPS: "& ff(1.0/dt))

proc lobbyDraw*(window: PRenderWindow) =
  window.clear(Black)
  window.draw chatBox
  window.draw gui
  window.draw fpsText
  if showZonelist: window.draw zonelist
  window.display()

