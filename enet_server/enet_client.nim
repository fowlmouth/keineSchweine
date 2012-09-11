import enet, strutils,
  sfml, sfml_vector, sfml_colors, sg_gui, input_helpers,
  math_helpers
const
  port = 8024
if enetInit() != 0:
  quit "Could not initialize ENet"
var
  address: enet.TAddress
  event: enet.TEvent
  peer: PPeer
  client: PHost
  bConnected = false
  runServer = true
  gui = newGuiContainer()
  kc = newKeyClient(setActive = true)
  window = newRenderWindow(videoMode(800, 600, 32), "doot", sfDefaultStyle)
  clock = newClock()
  chatBox: PMessageArea
  chatInput: PTextEntry
  fpsText = newText("", guiFont, 18)

chatBox = gui.newMessageArea(vec2f(15, 550))
chatInput = gui.newTextEntry("...", vec2f(15, 550), proc() =
  echo "blah blah", chatInput.getText())

gui.setActive(chatInput)

proc dispMessage(args: varargs[string, `$`]) =
  var s = ""
  for it in items(args):
    s.add it
  chatbox.add(s)
proc dispMessage(text: string) {.inline.} =
  chatbox.add(text)

proc netUpdate() =
  if bConnected:
    while client.hostService(event, 1000) > 0:
      case event.kind
      of EvtReceive:
        dispMessage("Recvd ($1) $2 ".format(
          event.packet.dataLength,
          event.packet.data))
      of EvtDisconnect:
        echo "Disconnected"
        event.peer.data = nil
        runServer = false
      of EvtNone: discard
      else:
        echo repr(event)
  else:
    if client.hostService(event, 40) > 0 and event.kind == EvtConnect:
      echo "Connected"
      bConnected = true


client = createHost(nil, 1, 2, 0, 0)
if client == nil:
  quit "Could not create client!"

if setHost(addr address, "localhost") != 0:
  quit "Could not set host"
address.port = port

peer = client.connect(addr address, 2, 0)
if peer == nil:
  quit "No available peers"

while runServer:
  let dt = clock.restart.asMilliseconds.float / 1000.0
  for event in window.filterEvents():
    if event.kind == EvtClosed:
      runServer = false
      break
  netUpdate()
  ##update
  ##render
  fpsText.setString ff(1.0 / dt)
  window.clear Black
  window.draw gui
  window.draw chatBox
  window.display()
  


client.destroy()
