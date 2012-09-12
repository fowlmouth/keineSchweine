import enet, strutils, sfml, sfml_colors, sfml_vector, 
  input_helpers, sg_gui, sfml_stuff, idgen, tables, math_helpers, 
  estreams, sg_packets, server_utils
type
  TCallback = proc(client: PClient; buffer: PBuffer)
var
  server: PHost
  event: enet.TEvent
  clientID = newIDGen[int32]()
  clients = initTable[int32, PClient](64)
  handlers = initTable[char, TCallback](32) 

when true:
  var
    gui = newGuiContainer()
    chatBox = gui.newMessageArea(vec2f(15, 550))
    window = newRenderWindow(videoMode(800, 600, 32), "Sup yo", sfDefaultSTyle)
    mousepos = newText("", guiFont, 16)
    fpsText = mousePos.copy()
    inputClient = newKeyClient(setActive = true)
  chatBox.sizeVisible = 30
  mousePos.setColor(Green)
  fpsText.setposition(vec2f(0, 20))
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


var pubChatQueue = newBuffer(1024)
proc queuePub(sender: PClient, msg: CsChat) =
  var chat = newScChat(kind = CPub, fromPlayer = sender.alias, text = msg.text)
  pubChatQueue.write(HChat)
  pubChatQueue.pack(chat)

handlers[HChat] = proc(client: PClient; buffer: PBuffer) =
  var chat = readCsChat(buffer)
  
  if not client.auth:
    client.sendError("You are not logged in.")
    return
  #if chat.target != "": ##private
  #  if alias2client.hasKey(chat.target):
  #    alias2client[chat.target].forwardPrivate(client, chat.text)
  #else:
  
  dispmessage("<", client.alias, "> ", chat.text)
  queuePub(client, chat)

handlers[HLogin] = proc(client: PClient; buffer: PBuffer) =
  var info = readCsLogin(buffer)
  if client.auth:
    client.sendError "You are already logged in."
    return
  client.alias = info.alias
  client.auth = true
  client.sendMessage "welcome"
  

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
    var pubChatDelay = newClock()
  
  while serverRunning:
    let dt = frameRate.restart.asMilliseconds().float / 1000.0
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
        client.peer = event.peer
        
        dispMessage("New client connected ", client)
        
        var
          msg = "hello" 
          resp = createPacket(cstring(msg), msg.len + 1, FlagReliable)
          
        if event.peer.send(0.cuchar, resp) < 0:
          echo "FAILED"
        else:
          echo "Replied"
      of EvtReceive:
        let client = clients[cast[ptr int32](event.peer.data)[]] 
        chatBox.add("Recvd ($1) $2 ".format(
          event.packet.dataLength,
          $event.packet.data))
        
        echo("Packet: ", repr(event.packet))
        var buf = newBuffer(event.packet)
        echo("Buffer: ", repr(buf))
        let k = buf.readChar()
        if handlers.hasKey(k):
          dispMessage("has msg")
          handlers[k](client, buf)
        else:
          dispMessage("Unknown packet")
        
        destroy(event.packet)
      of EvtDisconnect:
        var
          id = cast[ptr int32](event.peer.data)[]
          client = clients[id]
          #id = cast[ptr int32](event.peer.data)[] 
        if client.isNil:
          dispmessage("CLIENT IS NIL!")
          dispmessage(event.peer.data.isNil)
        else:
          dispMessage(clients[id], " disconnected")
          GCUnref(clients[id])
          clientID.del id
          clients.del id
        
        event.peer.data = nil
      else:
        discard
    
    fpsText.setString(ff(1.0/dt))
    if pubChatDelay.getElapsedTime.asSeconds > 0.25:
      pubChatDelay.restart()
      if pubChatQueue.isDirty:
        let packet = pubChatQueue.toPacket(FlagReliable)
        for id, client in pairs(clients):
          discard client.peer.send(0.cuchar, packet)
        pubChatQueue.flush()
    
    window.clear(Black)
    window.draw(GUI)
    window.draw chatbox
    window.draw mousePos
    window.draw fpstext
    window.display()  

  server.destroy()
  enetDeinit()