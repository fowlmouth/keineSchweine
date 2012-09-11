import enet, strutils, sfml, sfml_colors, sfml_vector, 
  input_helpers, sg_gui, sfml_stuff, idgen, tables, math_helpers
type
  PClient* = ref object
    id: int32
    auth: bool
    alias: string
var
  server: PHost
  event: enet.TEvent
  clientID = newIDGen[int32]()
  clients = initTable[int32, PClient](64)

when not defined(NoSFML):
  var
    gui = newGuiContainer()
    chatBox = gui.newMessageArea(vec2f(15, 550))
    window = newRenderWindow(videoMode(800, 600, 32), "Sup yo", sfDefaultSTyle)
    mousepos = newText("", guiFont, 16)
    inputClient = newKeyClient(setActive = true)
  mousePos.setColor(Green)
  inputClient.registerHandler MouseLeft, down, proc() =
    gui.click(input_helpers.getMousePos())
  inputClient.registerHandler MouseMiddle, down, proc() =
    let pos = input_helpers.getMousePos()
    mousePos.setString("($1,$2)".format(ff(pos.x), ff(pos.y)))
    mousePos.setPosition(pos)
  proc dispMessage(args: varargs[string, `$`]) =
    var s = ""
    for it in items(args):
      s.add it
    chatbox.add(s)
else:
  template dispMessage(args: varargs[expr]) =
    echo("<msg> ", args)

type TPacketHandler = proc()
var handlers = initTable[char, 

proc free(client: PClient) =
  echo "client freed! id == 0 ? ", (client.id == 0)
proc newClient(): PClient =
  new(result, free)
  result.id = clientID.next()
  result.alias = "billy"
  clients[result.id] = result
proc `$`(client: PClient): string =
  result = "(client #$1 $2)".format(client.id, client.alias)

when isMainModule:
  var address: enet.TAddress
  if enetInit() != 0:
    quit "Could not initialize ENet"

  address.host = EnetHostAny
  address.port = 8024

  server = enet.createHost(addr address, 32, 2,  0,  0)
  if server == nil:
    quit "Could not create the server!"
  
  dispMessage("Listening on port ", address.port)
  
  var 
    serverRunning = true
  when not defined(NoSFML):
    var frameRate = newClock()
  
  while serverRunning:
    when not defined(NoSFML):
      for event in window.filterEvents():
        case event.kind
        of sfml.EvtClosed:
          window.close()
          serverRunning = false
        else:
          discard
    
    while server.hostService(event, 10) > 0:
      case event.kind
      of EvtConnect:
        var client = newClient()
        event.peer.data = addr client.id
        
        dispMessage("New client connected ", client)
        
        var
          msg = "hello" 
          resp = createPacket(cstring(msg), msg.len + 1, FlagReliable)
          
        if event.peer.send(0.cuchar, resp) < 0:
          echo "FAILED"
        else:
          echo "Replied"
      of EvtReceive:
        chatBox.add("Recvd ($1) $2 ".format(
          event.packet.dataLength,
          event.packet.data))
        dispMessage(repr(event.packet))
        
        ## it looks similar to this
        var data = event.packet.data
        case data[0]
        of 'C':
          nil
        
        destroy(event.packet)
      of EvtDisconnect:
        let 
          id = cast[ptr int32](event.peer.data)[] 
        dispMessage(clients[id], " disconnected")
        GCUnref(clients[id])
        clientID.del id
        clients.del id
        
        event.peer.data = nil
      else:
        discard
    
    window.clear(Black)
    window.draw(GUI)
    window.draw chatbox
    window.draw(mousePos)
    window.display()  

  server.destroy()
  enetDeinit()