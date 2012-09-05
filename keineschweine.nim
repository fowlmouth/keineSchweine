import 
  sfml, sfml_vector, sfml_colors, chipmunk, os, math, strutils, gl, tables,
  input_helpers, sg_lobby, sg_gui, sg_assets, animations, sfml_stuff
{.deadCodeElim: on.}
type
  PPlayer* = ref TPlayer
  TPlayer* = object
    id: uint16
    vehicle: PVehicle
    spectator: bool
    alias: string
    nameTag: PText
  PVehicle* = ref TVehicle
  TVehicle* = object
    body:      chipmunk.PBody
    shape:     chipmunk.PShape
    record*:   PVehicleRecord
    sprite*:   PSprite
    spriteRect*: TIntRect
  ## position*: TVector2f
  ## velocity*: TVector2f
  ## angle*:    float
  PGameObject = ref TGameObject
  TGameObject = object
    body: chipmunk.PBody
    shape: chipmunk.PShape
    record*: PObjectRecord
    anim*: PAnimation
    when false:
      sprite: PSprite
  
const
  TAU = PI * 2.0
  TenDegrees = 10.0 * PI / 180.0
  ##temporary constants
  W_LIMIT = 2.3
  V_LIMIT = 35
  MaxLocalBots = 3
var
  localPlayer: PPlayer
  localBots: seq[PPlayer] = @[]
  activeVehicle: PVehicle
  myVehicles: seq[PVehicle] = @[]
  objects: seq[PGameObject] = @[]
  gameRunning = true
  frameRate = newClock()
  showStars = off
  levelArea: TIntRect
  videoMode: TVideoMode
  window: PRenderWindow
  worldView: PView
  guiView: PView
  space = newSpace()
  ingameClient = newKeyClient("ingame")
  specInputClient = newKeyClient("spec")
  specGui = newGuiContainer()
  stars: seq[PSpriteSheet] = @[]
  playBtn: PButton
  shipSelect = newGuiContainer()
  delObjects: seq[int] = @[]
when defined(foo):
  var mouseSprite: sfml.PCircleShape
when defined(recordMode):
  var 
    snapshots: seq[PImage] = @[]
    isRecording = false
  proc startRecording() = 
    if snapshots.len > 100: return
    echo "Started recording"
    isRecording = true
  proc stopRecording() =
    if isRecording:
      echo "Stopped recording. ", snapshots.len, " images."
    isRecording = false
  proc zeroPad*(s: string; minLen: int): string =
    if s.len < minLen:
      result = repeatChar(minLen - s.len, '0')
      result.add s
    else:
      result = s
  var
    recordButton = newButton(
      nil, text = "Record", position = vec2f(680, 50),
      onClick = proc(b: PButton) = startRecording())

proc newNameTag*(text: string): PText =
  result = newText()
  result.setFont(guiFont)
  result.setCharacterSize(14)
  result.setColor(Red)
  result.setString(text)

var debugText = newNameTag("Loading...")
debugText.setPosition(vec2f(0.0, 600.0 - 50.0))

proc initLevel() =
  loadAllGraphics()
  let levelSettings = getLevelSettings()
  levelArea.width = levelSettings.size.x
  levelArea.height= levelSettings.size.y
  let borderSeq = @[
    vector(0, 0), vector(levelArea.width.float, 0.0),
    vector(levelArea.width.float, levelArea.height.float), vector(0.0, levelArea.height.float)]
  for i in 0..3:
    var seg = space.addShape(
      newSegmentShape(
        space.staticBody, 
        borderSeq[i], 
        borderSeq[(i + 1) mod 4],
        2.3))
    seg.setElasticity 0.96
  if levelSettings.starfield.len > 0:
    showStars = true
    for sprite in levelSettings.starfield:
      sprite.tex.setRepeated(true)
      sprite.sprite.setTextureRect(levelArea)
      sprite.sprite.setOrigin(vec2f(0, 0))
      stars.add(sprite)
  var pos = vec2f(0.0, 0.0)
  for veh in playableVehicles():
    shipSelect.newButton(veh.name, position = pos, onClick = proc(b: PButton) = echo "-__-")
    pos.y += 18.0
  

when defined(showFPS):
  var fpsText = newNameTag("0")
  #fpsText.setCharacterSize(16)
  fpsText.setPosition(vec2f(300.0, (800 - 50).float))

proc newPlayer*(alias: string = "poo"): PPlayer =
  new(result)
  result.spectator = true
  result.alias     = alias
  result.nameTag   = newNameTag(result.alias)

proc free*(veh: PVehicle) =
  ("Destroying vehicle "& veh.record.name).echo
  destroy(veh.sprite)
  if veh.shape.isNil: "Free'd vehicle's shape was NIL!".echo
  else: space.removeShape(veh.shape)
  if veh.body.isNil: "Free'd vehicle's BODY was NIL!".echo
  else: space.removeBody(veh.body)
  veh.body.free()
  veh.shape.free()
  veh.sprite = nil
  veh.body   = nil
  veh.shape  = nil


proc angularDampingSim(body: PBody, gravity: TVector, damping: CpFloat; dt: CpFloat){.cdecl.} =
  body.w -= (body.w * 0.98 * dt) 
  body.updateVelocity(gravity, damping, dt)

proc newVehicle*(veh: string): PVehicle =
  var v = fetchVeh(veh)
  if not v.playable:
    echo(veh &"is not playable")
    return nil
  echo("Creating "& veh)
  new(result, free)
  result.record = v
  result.sprite = result.record.anim.spriteSheet.sprite.copy()
  result.sprite.setOrigin(vec2f(v.anim.spriteSheet.framew / 2, v.anim.spriteSheet.frameh / 2))
  result.spriteRect = result.sprite.getTextureRect()
  result.body = space.addBody(
    newBody(
      result.record.physics.mass,
      momentForCircle(
        result.record.physics.mass.cdouble, 
        0.0, 
        result.record.physics.radius.cdouble, 
        vector(0.0,0.0)
      ) * 0.62
  ) )
  result.body.setAngVelLimit W_LIMIT
  result.body.setVelLimit result.record.handling.topSpeed
  result.body.velocityFunc = angularDampingSim
  result.shape = space.addShape(
    chipmunk.newCircleShape(result.body, 
                            result.record.physics.radius.cdouble, 
                            vectorZero))
  echo(veh &" created")

proc createBot() =
  if localBots.len < MaxLocalBots:
    var bot = newPlayer("Dodo Brown")
    bot.vehicle = newVehicle("Masta")
    localBots.add(bot)

var inputCursor = newVertexArray(sfml.Lines, 2)
inputCursor[0].position = vec2f(10.0, 10.0)
inputCursor[1].position = vec2f(50.0, 90.0)

proc accel(obj: PVehicle, dt: float) =
  #obj.velocity += vec2f(
  #  cos(obj.angle) * obj.record.handling.thrust.float * dt,
  #  sin(obj.angle) * obj.record.handling.thrust.float * dt)
  obj.body.applyImpulse(
    vectorForAngle(obj.body.getAngle()) * dt * obj.record.handling.thrust,
    vectorZero)
proc reverse(obj: PVehicle, dt: float) =
  #obj.velocity += vec2f(
  #  -cos(obj.angle) * obj.record.handling.reverse.float * dt,
  #  -sin(obj.angle) * obj.record.handling.reverse.float * dt)
  obj.body.applyImpulse(
    -vectorForAngle(obj.body.getAngle()) * dt * obj.record.handling.reverse.float,
    vectorZero)
proc strafe_left*(obj: PVehicle, dt: float) =
  obj.body.applyImpulse(
    vectorForAngle(obj.body.getAngle()).perp() * obj.record.handling.strafe.float * dt,
    vectorZero)
proc strafe_right*(obj: PVehicle, dt: float) =
  obj.body.applyImpulse(
    vectorForAngle(obj.body.getAngle()).rperp()* obj.record.handling.strafe.float * dt,
    vectorZero)
proc turn_right*(obj: PVehicle, dt: float) =
  #obj.angle = (obj.angle + (obj.record.handling.rotation.float / 10.0 * dt)) mod TAU
  obj.body.setTorque(obj.record.handling.rotation.float)
proc turn_left*(obj: PVehicle, dt: float) =
  #obj.angle = (obj.angle - (obj.record.handling.rotation.float / 10.0 * dt)) mod TAU
  obj.body.setTorque(-obj.record.handling.rotation.float)
proc offsetAngle*(obj: PVehicle): float {.inline.} =
  return (obj.record.anim.angle + obj.body.getAngle())

proc hasVehicle(p: PPlayer): bool {.inline.} = 
  result = not p.spectator and not p.vehicle.isNil

proc setMyVehicle(v: PVehicle) {.inline.} =
  activeVehicle = v
  localPlayer.vehicle = v
proc unspec() =
  var veh = newVehicle("Masta")
  if not veh.isNil:
    setMyVehicle veh
    localPlayer.spectator = false
    ingameClient.setActive
    veh.body.setPos vector(100, 100)
proc spec() =
  setMyVehicle nil
  localPlayer.spectator = true
  specInputClient.setActive

var 
  specLimiter = newClock()
  timeBetweenSpeccing = 1.0 #seconds
proc toggleSpec() {.inline.} =
  if specLimiter.getElapsedTime.asSeconds < timeBetweenSpeccing:
    return
  specLimiter.restart()
  if localPlayer.isNil: 
    echo("OMG WTF PLAYER IS NILL!!")
  elif localPlayer.spectator: unspec()
  else: spec()

proc `wmod`(x, y: float): float = return x - y * (x/y).floor
proc move*(a: var TIntRect, left, top: cint): bool =
  if a.left != left or a.top != top: result = true
  a.left = left
  a.top  = top
proc degrees(rad: float): float =
  return rad * 180.0 / PI
proc floor(a: TVector): TVector2f {.inline.} =
  result.x = a.x.floor
  result.y = a.y.floor
proc sfml2cp(a: TVector2f): TVector {.inline.} =
  result.x = a.x
  result.y = a.y
proc cp2sfml(a: TVector): TVector2f {.inline.} =
  result.x = a.x
  result.y = a.y

proc `$`(obj: PGameObject): string =
  result = "<Object "
  result.add obj.record.name
  result.add ' '
  result.add($obj.body.getpos())
  result.add '>'
proc free(obj: PGameObject) =
  when false:
    if not obj.sprite.isNil: destroy(obj.sprite)
  obj.record = nil
  free(obj.anim)
  obj.anim = nil
proc newObject*(name: string): PGameObject =
  let record = fetchObj(name)
  if record.isNil: return nil
  new(result, free)
  result.record = record
  result.anim = newAnimation(record.anim, AnimLoop)
  when false:
    result.sprite = record.anim.spriteSheet.sprite.copy()
  result.body = space.addBody(newBody(result.record.physics.mass, 10.0))
  result.shape = space.addShape(
    chipmunk.newCircleShape(result.body, result.record.physics.radius, vectorZero))
  result.body.setPos(vector(100, 100))
proc addObject*(name: string) =
  var o = newObject(name)
  if not o.isNil: 
    echo "Adding object ", o
    objects.add(o)
proc explode(obj: PGameObject) = 
  echo obj, " exploded"
  let ind = objects.find(obj)
  if ind != -1:
    delObjects.add ind
proc update(obj: PGameObject; dt: float) =
  if not(obj.anim.next(dt)):
    obj.explode()
  else:
    obj.anim.sprite.setPosition(obj.body.getPos.floor)
proc draw(window: PRenderWindow, obj: PGameObject) {.inline.} =
  window.draw(obj.anim.sprite)

proc update*(obj: PVehicle) =
  obj.sprite.setPosition(obj.body.getPos.floor)
  #obj.sprite.setPosition(obj.position)
  #let x = ((-obj.body.getAngVel + W_LIMIT) * obj.record.anim.spriteSheet.cols.float).floor * obj.record.anim.spriteSheet.framew.float ## 4 * obj.record.anim.spriteSheet.framew
  #let x = ((-obj.body.getAngVel + W_LIMIT) * (obj.record.anim.spriteSheet.cols - 1).float).floor.int * obj.record.anim.spriteSheet.framew ## 4 * obj.record.anim.spriteSheet.framew
  let x = ((-activeVehicle.body.getAngVel + W_LIMIT) / (W_LIMIT*2.0) * (activeVehicle.record.anim.spriteSheet.cols - 1).float).floor.int * obj.record.anim.spriteSheet.framew
  let y = ((obj.offsetAngle.wmod(TAU) / TAU) * obj.record.anim.spriteSheet.rows.float).floor.int * obj.record.anim.spriteSheet.frameh
  if obj.spriteRect.move(x.cint, y.cint):
    obj.sprite.setTextureRect(obj.spriteRect)

let nameTagOffset = vec2f(0.0, 1.0)
proc update*(obj: PPlayer) =
  if not obj.spectator:
    obj.vehicle.update()
    obj.nameTag.setPosition(obj.vehicle.body.getPos.floor + (nameTagOffset * (obj.vehicle.record.physics.radius + 5).cfloat))

proc ff(f: float, precision = 2): string {.inline.} = return formatFloat(f, ffDecimal, precision)
proc vec2i(a: TVector2f): TVector2i =
  result.x = a.x.cint
  result.y = a.y.cint

proc mouseToSpace*(): TVector =
  var pos = window.convertCoords(vec2i(getMousePos()), worldView)
  result = pos.sfml2cp()
  #result = getMousePos().sfml2cp

var showShipSelect = false
proc toggleShipSelect() = 
  showShipSelect = not showShipSelect

ingameClient.registerHandler(KeyF12, down, proc() = toggleSpec())
ingameClient.registerHandler(KeyF11, down, toggleShipSelect)
when defined(recordMode):
  if not existsDir("data/snapshots"):
    createDir("data/snapshots")
  ingameClient.registerHandler(keynum9, down, proc() =
    if not isRecording: startRecording()
    else: stopRecording())
  ingameClient.registerHandler(keynum0, down, proc() =
    if snapshots.len > 0 and not isRecording:
      echo "Saving images (LOL)"
      for i in 0..high(snapshots):
        if not(snapshots[i].save("data/snapshots/image"&(zeroPad($i, 3))&".jpg")):
          echo "Could not save"
        snapshots[i].destroy()
      snapshots.setLen 0)
when defined(DebugKeys):
  ingameClient.registerHandler(KeyRShift, down, proc() =
    if keyPressed(KeyR):
      echo("Friction: ", ff(activeVehicle.shape.getFriction()))
      echo("Damping: ", ff(space.getDamping()))
    elif keypressed(KeyM):
      echo("Mass: ", activeVehicle.body.getMass.ff())
      echo("Moment: ", activeVehicle.body.getMoment.ff())
    elif keypressed(KeyI):
      echo(repr(activeVehicle.record))
    elif keyPressed(KeyH):
      activeVehicle.body.setPos(vector(100.0, 100.0))
      activeVehicle.body.setVel(vectorZero)
    elif keyPressed(KeyComma):
      activeVehicle.body.setPos mouseToSpace())
  ingameClient.registerHandler(KeyY, down, proc() =
    const looloo = ["Asteroid1", "Asteroid2"]
    addObject(looloo[random(looloo.len)]))
  ingameClient.registerHandler(KeyO, down, proc() =
    if objects.len == 0:
      echo "Objects is empty"
      return
    for i, o in pairs(objects):
      echo(i, " ", o, " index: ", o.anim.index, " maxcol: ", o.anim.maxcol, " spriterect: ", o.anim.spriteRect))
  var 
    mouseJoint: PConstraint
    mouseBody = space.addBody(newBody(CpInfinity, CpInfinity))
  ingameClient.registerHandler(MouseMiddle, down, proc() =
    var point = mouseToSpace()
    var shape = space.pointQueryFirst(point, 0, 0)
    if shape.isNil: 
      echo("no shape there..\n", $point)
      return
    if mouseJoint.isNil:
      mouseJoint.destroy()
    let body = shape.getBody()
    mouseJoint = newPivotJoint(mouseBody, body, vectorZero, body.world2local(point))
    mouseJoint.maxForce = 50000.0
    mouseJoint.errorBias = pow(1.0 - 0.15, 60)
    discard space.addConstraint(mouseJoint))
  ingameclient.registerHandler(KeySpace, down, proc() = 
    echo("ang vel: ", ff(activeVehicle.body.getAngVel(), 3))
    echo("ang vel limit: ", ff(activevehicle.body.getAngVelLimit(), 3))
    echo("Sprite COL: ", ((-activeVehicle.body.getAngVel + W_LIMIT) / (W_LIMIT*2.0) * (activeVehicle.record.anim.spriteSheet.cols-1).float).floor.ff(2)))# * activeVehicle.record.anim.spriteSheet.framew.float))

var specCameraSpeed = 5.0
specInputClient.registerHandler(MouseLeft, down, proc() = specGui.click(getMousePos()))
specInputClient.registerHandler(KeyF11, down, toggleShipSelect)
specInputClient.registerHandler(KeyF11, down, proc() = toggleSpec())
specInputClient.registerHandler(KeyLShift, down, proc() = specCameraSpeed *= 2)
specInputClient.registerHandler(KeyLShift, up, proc() = specCameraSpeed /= 2)

specInputClient.registerHandler(KeyP, down, proc() =
  echo("addObject(solar mold)")
  addObject("Solar Mold"))

proc resetForcesCB(body: PBody; data: pointer) {.cdecl.} =
  body.resetForces()

when defined(showFPS):
  var i = 0
proc update(dt: float) =
  if localPlayer.spectator:
    if keyPressed(KeyLeft):
      worldView.move(vec2f(-1.0, 0.0) * specCameraSpeed)
    elif keyPressed(KeyRight):
      worldView.move(vec2f( 1.0, 0.0) * specCameraSpeed)
    if keyPressed(KeyUp):
      worldView.move(vec2f(0.0, -1.0) * specCameraSpeed)
    elif keyPressed(KeyDown):
      worldView.move(vec2f(0.0,  1.0) * specCameraSpeed)
  elif not activeVehicle.isNil:
    if keyPressed(KeyUp):
      activeVehicle.accel(dt)
    elif keyPressed(keyDown):
      activeVehicle.reverse(dt)
    if keyPressed(KeyRight):
      activeVehicle.turn_right(dt)
    elif keyPressed(KeyLeft):
      activeVehicle.turn_left(dt)
    if keyPressed(keyz):
      activeVehicle.strafe_left(dt)
    elif keyPressed(keyx):
      activeVehicle.strafe_right(dt)
    worldView.setCenter(activeVehicle.body.getPos.floor)#cp2sfml)
  
  if localPlayer != nil: localPlayer.update()
  for b in localBots:
    b.update()
  
  for o in items(objects):
    o.update(dt)
  for i in countdown(high(delObjects), 0):
    objects.del i
  delObjects.setLen 0
  
  space.step(dt)
  space.eachBody(resetForcesCB, nil)
  
  when defined(foo):
    var coords = window.convertCoords(vec2i(getMousePos()), worldView)
    mouseSprite.setPosition(coords)
  
  when defined(showFPS):
    inc(i)
    if i mod 60 == 0:
      fpsText.setString($(1.0/dt).round)
      i = 0


proc loadTexture(filename: string): PTexture =
  var image = newImage(filename)
  if image == nil:
    echo("Could not load image "& filename)
  result = newTexture(image)
  image.destroy()

proc draw(window: PRenderWindow, player: PPlayer) {.inline.} =
  if not player.spectator: 
    if player.vehicle != nil:
      window.draw(player.vehicle.sprite)
    window.draw(player.nameTag)

proc render(obj: PVehicle) =
  window.draw(obj.sprite)
proc render() =
  window.clear(Black)
  window.setView(worldView)
  
  if showStars:
    for star in stars:
      window.draw(star.sprite)
  window.draw(localPlayer)
  for b in localBots:
    window.draw(b)
  for o in objects:
    window.draw(o)
  when defined(Foo):
    window.draw(mouseSprite)
  
  window.setView(guiView)
  
  when defined(showFPS):
    window.draw(fpsText)
  when defined(recordMode):
    window.draw(recordButton)
  
  if localPlayer.spectator:
    window.draw(specGui)
  if showShipSelect: window.draw shipSelect
  window.display()
  
  when defined(recordMode):
    if isRecording:
      if snapshots.len < 100:
        if i mod 5 == 0:
          snapshots.add(window.capture())
      else: stopRecording()

proc `$`*(a: TKeyEvent): string =
  return "KeyEvent: code=$1 alt=$2 control=$3 shift=$4 system=$5" % [
    $a.code, $a.alt, $a.control, $a.shift, $a.system]

proc readyMainState() =
  specInputClient.setActive()

when isMainModule:
  localPlayer = newPlayer()
  LobbyInit()
  
  videoMode = getClientSettings().resolution
  window = newRenderWindow(videoMode, "sup", sfDefaultStyle)
  window.setFrameRateLimit 60
  
  worldView = window.getView.copy()
  guiView = worldView.copy()
  shipSelect.setPosition vec2f(665.0, 50.0)
  
  when defined(foo):
    mouseSprite = sfml.newCircleShape(14)
    mouseSprite.setFillColor Transparent
    mouseSprite.setOutlineColor RoyalBlue
    mouseSprite.setOutlineThickness 1.4
    mouseSprite.setOrigin vec2f(14, 14)
  
  LobbyReady()
  playBtn = specGui.newButton(
    "Unspec - F11", position = vec2f(680.0, 8.0), onClick = proc(b: PButton) =
      toggleSpec())
  
  gameRunning = true
  while gameRunning:
    for event in window.filterEvents:
      if event.kind == EvtClosed:
        gameRunning = false
        break
      elif event.kind == EvtMouseWheelMoved and getActiveState() == Field:
        if event.mouseWheel.delta == 1:
          worldView.zoom(0.9)
        else:
          worldView.zoom(1.1)
    let dt = frameRate.restart.asMilliSeconds().float / 1000.0
    case getActiveState()
    of Field:
      update(dt)
      render()
    of Lobby:
      lobbyUpdate(dt)
      lobbyDraw(window)
    else:
      initLevel()
      echo("Done? lol")
      doneWithSaidTransition()
      readyMainState()
