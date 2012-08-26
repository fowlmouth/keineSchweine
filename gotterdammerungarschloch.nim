import 
  sfml, sfml_vector, sfml_colors, chipmunk, os, math, strutils, gl, tables,
  input, sg_lobby, sg_gui, sg_assets
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
    sprite: PSprite
const
  TAU = PI * 2.0
  TenDegrees = 10.0 * PI / 180.0
  ##temporary constants
  ACCELRATE  = 0.04
  DECELRATE  = 0.02
  STRAFERATE = 0.02
  TURNRATE   = 0.40
  FRICTION   = 0.99
  TOPSPEED   = 0.02
  MaxLocalBots = 3
var
  localPlayer: PPlayer
  localBots: seq[PPlayer] = @[]
  activeVehicle: PVehicle
  myVehicles: seq[PVehicle] = @[]
  objects: seq[PGameObject] = @[]
  #objects: seq[PGameObject] = @[]
  gameRunning = true
  frameRate = newClock()
  enterKeyTimer = newClock()
  showStars = off
  window: PRenderWindow
  worldView, guiView: PView
  space = newSpace()
  ingameClient, specInputClient: PKeyClient
  stars: seq[PSpriteSheet] = @[]

window = newRenderWindow(VideoMode(800, 600, 32), "sup", sfDefaultStyle)
lobbyInit()

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
  if levelSettings.starfield.len > 0:
    showStars = true
    var rect: TIntRect
    rect.width = levelSettings.size.x
    rect.height= levelSettings.size.y
    for sprite in levelSettings.starfield:
      sprite.tex.setRepeated(true)
      sprite.sprite.setTextureRect(rect)
      stars.add(sprite)

when defined(showFPS):
  var fpsText = newNameTag("0")
  #fpsText.setCharacterSize(16)
  fpsText.setPosition(vec2f(300.0, (800 - 50).float))

proc newPlayer*(alias: string = "poo"): PPlayer =
  new(result)
  result.spectator = true
  result.alias     = alias
  result.nameTag   = newNameTag(result.alias)

localPlayer = newPlayer()

var testrect = intRect(0, 0, 500, 500)
echo(repr(testrect))

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

proc newVehicle*(veh: string): PVehicle =
  var v = fetchVeh(veh)
  if not v.playable:
    echo(veh &"is not playable")
    return nil
  echo("Creating "& veh)
  new(result, free)
  result.record = fetchVeh(veh)
  #result.angle = 0.0
  #result.position = vec2f(50.0, 50.0)
  #result.velocity = vec2f(0.0,  0.0)
  result.sprite = result.record.anim.spriteSheet.sprite.copy()
  result.spriteRect = result.sprite.getTextureRect()
  result.body = space.addBody(
    newBody(result.record.physics.mass, 10.0))
  result.body.setMass(result.record.physics.mass)
  result.body.setMoment(momentForCircle(
      result.record.physics.mass.cdouble, 0.0, result.record.physics.radius.cdouble, newVector(0.0,0.0)))
  result.shape = space.addShape(
    chipmunk.newCircleShape(result.body, 
                            result.record.physics.radius.cdouble, 
                            vectorZero))
  echo(veh &" created")
  echo(repr(result.record.physics))
  echo($result.body.getMass.round, " | ", $result.body.getMoment())
  echo($result.shape.getCircleRadius(), " | ", $result.shape.getCircleOffset())



proc createBot() =
  if localBots.len < MaxLocalBots:
    var bot = newPlayer("Dodo Brown")
    bot.vehicle = newVehicle("Masta")
    localBots.add(bot)

window.setFramerateLimit(60)
guiView = window.getView.copy()
worldView = guiView.copy()

var 
  i = 0
  inputText = newText()
inputText.setPosition(vec2f(10.0, 10.0))
inputText.setFont(guiFont)
inputText.setCharacterSize(24)
inputText.setColor(White)

var inputCursor = newVertexArray(sfml.Lines, 2)
inputCursor[0].position = vec2f(10.0, 10.0)
inputCursor[1].position = vec2f(50.0, 90.0)

discard """proc finished(text: string) =
  echo("\""& text &"\"")
  resetInputText()
  stopCapturingText()
  enterKeyTimer.restart()
setEnterProc(finished)
"""
proc accel(obj: PVehicle, dt: float) =
  #obj.velocity += vec2f(
  #  cos(obj.angle) * obj.record.handling.thrust.float * dt,
  #  sin(obj.angle) * obj.record.handling.thrust.float * dt)
  obj.body.applyForce(
    vectorForAngle(obj.body.getAngle()) * dt * obj.record.handling.thrust,
    vectorZero)
proc reverse(obj: PVehicle, dt: float) =
  #obj.velocity += vec2f(
  #  -cos(obj.angle) * obj.record.handling.reverse.float * dt,
  #  -sin(obj.angle) * obj.record.handling.reverse.float * dt)
  obj.body.applyForce(
    -vectorForAngle(obj.body.getAngle()) * dt * obj.record.handling.reverse.float,
    vectorZero)
proc strafe_left*(obj: PVehicle, dt: float) =
  obj.body.applyForce(
    vectorForAngle(obj.body.getAngle()).perp() * obj.record.handling.strafe.float * dt,
    vectorZero)
proc strafe_right*(obj: PVehicle, dt: float) =
  obj.body.applyForce(
    vectorForAngle(obj.body.getAngle()).rperp()* obj.record.handling.strafe.float * dt,
    vectorZero)
proc turn_right*(obj: PVehicle, dt: float) =
  #obj.angle = (obj.angle + (obj.record.handling.rotation.float / 10.0 * dt)) mod TAU
  obj.body.setTorque(obj.record.handling.rotation.float)
  debugText.setString("Torque: "& $obj.body.getTorque())
proc turn_left*(obj: PVehicle, dt: float) =
  #obj.angle = (obj.angle - (obj.record.handling.rotation.float / 10.0 * dt)) mod TAU
  obj.body.setTorque(-obj.record.handling.rotation.float)
  debugText.setString("Torque: "& $obj.body.getTorque() &" angle: "& $obj.body.getAngle())
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
proc spec() =
  setMyVehicle nil
  localPlayer.spectator = true

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
proc cp2sfml(a: TVector): TVector2f {.inline.} =
  result.x = a.x
  result.y = a.y


proc free(obj: PGameObject) =
  if not obj.sprite.isNil: destroy(obj.sprite)
  obj.record = nil
proc newObject*(name: string): PGameObject =
  let record = fetchObj(name)
  if record.isNil: return nil
  new(result, free)
  result.record = record
  result.sprite = record.anim.spriteSheet.sprite.copy()
  result.body = space.addBody(newBody(result.record.physics.mass, 10.0))
  result.shape = space.addShape(
    chipmunk.newCircleShape(result.body, result.record.physics.radius, vectorZero))
proc addObject*(name: string) =
  var o = newObject(name)
  if not o.isNil: objects.add(o)
proc draw(window: PRenderWindow, obj: PGameObject) {.inline.} =
  window.draw(obj.sprite)


proc update*(obj: PVehicle) =
  obj.sprite.setPosition(obj.body.getPos.cp2sfml)
  #obj.sprite.setPosition(obj.position)
  let x = 4 * obj.record.anim.spriteSheet.framew
  let y = ((obj.offsetAngle.wmod(TAU) / TAU) * obj.record.anim.spriteSheet.rows.float).floor.int * obj.record.anim.spriteSheet.frameh
  if obj.spriteRect.move(x.cint, y.cint):
    obj.sprite.setTextureRect(obj.spriteRect)

var nameTagOffset = vec2f(1.0, 0.0)
proc update*(obj: PPlayer) =
  if not obj.spectator:
    obj.vehicle.update()
    obj.nameTag.setPosition(obj.vehicle.body.getPos.cp2sfml + (nameTagOffset * obj.vehicle.record.physics.radius.cfloat))

ingameClient = newKeyClient("ingame")
ingameClient.registerHandler(KeyF11, down, proc() = toggleSpec())
ingameClient.registerHandler(KeyRShift, down, proc() =
  if keyPressed(KeyR):
    echo("Friction", $activeVehicle.shape.getFriction())
    echo("Damping", $space.getDamping()))

specInputClient = newKeyClient("spec")
var specCameraSpeed = 5.0
specInputClient.registerHandler(KeyF11, down, proc() = toggleSpec())
specInputClient.registerHandler(KeyLShift, down, proc() = specCameraSpeed *= 2)
specInputClient.registerHandler(KeyLShift, up, proc() = specCameraSpeed /= 2)

specInputClient.registerHandler(KeyP, down, proc() =
  echo("addObject(solar mold)")
  var objr = fetchObj("Solar Mold")
  echo(repr(objr))
  addObject("Solar Mold"))

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
    worldView.setCenter(activeVehicle.body.getPos.cp2sfml)
  
  if localPlayer != nil: localPlayer.update()
  for b in localBots:
    b.update()
  #for o in objects:
  #  o.update()
  
  space.step(dt)
  
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
  window.setView(guiView)
  window.draw(inputText)
  window.draw(inputCursor)
  window.draw(debugText)
  when defined(showFPS):
    window.draw(fpsText)
  window.display()

proc `$`*(a: TKeyEvent): string =
  return "KeyEvent: code=$1 alt=$2 control=$3 shift=$4 system=$5" % [
    $a.code, $a.alt, $a.control, $a.shift, $a.system]

proc readyMainState() =
  specInputClient.setActive()

LobbyReady()

when defined(LogFTime): from times import cpuTime

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
