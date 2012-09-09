import
  re, json, strutils, tables, math, os, math_helpers

when defined(NoSFML):
  import server_utils
  type TVector2i = object
    x*, y*: int32
  proc vec2i(x, y: int32): TVector2i =
    result.x = x
    result.y = y
else:
  import sfml, sfml_vector, sfml_audio, sfml_stuff
when not defined(NoChipmunk):
  import chipmunk

type
  PZoneSettings* = ref TZoneSettings
  TZoneSettings* = object
    vehicles: seq[PVehicleRecord]
    items: seq[PItemRecord]
    objects: seq[PObjectRecord]
    bullets: seq[PBulletRecord]
    levelSettings: PLevelSettings
  PLevelSettings* = ref TLevelSettings
  TLevelSettings* = object
    size*: TVector2i
    starfield*: seq[PSpriteSheet]
  PVehicleRecord* = ref TVehicleRecord
  TVehicleRecord* = object
    id*: int16
    name*: string
    playable*: bool
    anim*: PAnimationRecord
    physics*: TPhysicsRecord
    handling*: THandlingRecord
  TItemKind* = enum
    Projectile, Utility, Ammo
  PObjectRecord* = ref TObjectRecord
  TObjectRecord* = object
    id*: int16
    name*: string
    anim*: PAnimationRecord
    physics*: TPhysicsRecord
  PItemRecord* = ref TItemRecord
  TItemRecord* = object
    id*: int16
    name*: string
    anim*: PAnimationRecord
    physics*: TPhysicsRecord ##apply when the item is dropped in the arena
    cooldown*: float
    useSound*: PSoundRecord
    case kind*: TItemKind
    of Projectile: 
      bullet*: PBulletRecord
    else: 
      nil
  PBulletRecord* = ref TBulletRecord
  TBulletRecord* = object
    id*: int16
    name*: string
    anim*: PAnimationRecord
    physics*: TPhysicsRecord
    lifetime*, inheritVelocity*, baseVelocity*: float
    explosion*: TExplosionRecord
  TPhysicsRecord* = object
    mass*: float
    radius*: float
  THandlingRecord = object
    thrust*, top_speed*: float
    reverse*, strafe*, rotation*: float
  TSoulRecord = object
    energy*: int
    health*: int
  TExplosionRecord* = object
    anim*: PAnimationRecord
    sound*: PSoundRecord 
  PAnimationRecord* = ref TAnimationRecord
  TAnimationRecord* = object
    spriteSheet*: PSpriteSheet
    angle*: float
    delay*: float  ##animation delay
  PSoundRecord* = ref TSoundRecord
  TSoundRecord* = object
    when defined(NoSFML):
      file*: string
      contents*: TChecksumFile
    else:
      soundBuf*: PSoundBuffer 
  PSpriteSheet* = ref TSpriteSheet
  TSpriteSheet* = object 
    file*: string
    framew*,frameh*: int
    rows*, cols*: int
    when defined(NoSFML):
      contents*: TChecksumFile
    when not defined(NoSFML):
      sprite*: PSprite
      tex*: PTexture
  TGameState* = enum
    Lobby, Transitioning, Field
const
  TAU* = PI * 2.0
var 
  cfg: PZoneSettings
  SpriteSheets* = initTable[string, PSpriteSheet](64)
  SoundCache* = initTable[string, PSoundRecord](64)
  nameToVehID*: TTable[string, int]
  nameToItemID*: TTable[string, int]
  nameToObjID*: TTable[string, int]
  nameToBulletID*: TTable[string, int]
  activeState = Lobby

proc newSprite(filename: string): PSpriteSheet
proc load*(ss: PSpriteSheet): bool {.discardable.}
proc newSound(filename: string): PSoundRecord
proc load*(s: PSoundRecord): bool {.discardable.}

proc validateSettings*(settings: PJsonNode; errors: var seq[string]): bool
proc loadSettings*(rawJson: string, errors: var seq[string]): bool
proc loadSettingsFromFile*(filename: string, errors: var seq[string]): bool

proc fetchVeh*(name: string): PVehicleRecord
proc fetchItm*(itm: string): PItemRecord
proc fetchObj*(name: string): PObjectRecord
proc fetchBullet(name: string): PBulletRecord

proc importLevel(data: PJsonNode): PLevelSettings
proc importVeh(data: PJsonNode): PVehicleRecord
proc importObject(data: PJsonNode): PObjectRecord
proc importItem(data: PJsonNode): PItemRecord
proc importPhys(data: PJsonNode): TPhysicsRecord
proc importAnim(data: PJsonNode): PAnimationRecord
proc importHandling(data: PJsonNode): THandlingRecord
proc importBullet(data: PJsonNode): PBulletRecord
proc importSoul(data: PJsonNode): TSoulRecord
proc importExplosion(data: PJsonNode): TExplosionRecord
proc importSound(data: PJsonNode; fieldName: string = nil): PSoundRecord

## this is the only pipe between lobby and main.nim
proc getActiveState*(): TGameState =
  result = activeState
proc transition*() = 
  assert activeState == Lobby, "Transition() called from a state other than lobby!"
  activeState = Transitioning
proc doneWithSaidTransition*() =
  assert activeState == Transitioning, "Finished() called from a state other than transitioning!"
  activeState = Field

proc free*(obj: PZoneSettings) =
  nil
proc free*(obj: PSpriteSheet) =
  echo("Free'd "&obj.file)

proc loadAllGraphics*() =
  var l = 0
  for name, ss in SpriteSheets.pairs():
    if load(ss):
      inc(l)
  echo("Loaded ",l," sprites")
proc getLevelSettings*(): PLevelSettings =
  result = cfg.levelSettings

iterator playableVehicles*(): PVehicleRecord =
  for v in cfg.vehicles.items():
    if v.playable:
      yield v

proc newSprite(filename: string): PSpriteSheet =
  if hasKey(SpriteSheets, filename):
    return SpriteSheets[filename]
  let path = "data/gfx"/filename
  if not existsFile(path):
    raise newException(EIO, "File does not exist: "&path)
  elif filename =~ re"\S+_(\d+)x(\d+)\.\S\S\S":
    new(result, free)
    result.file = path
    result.framew = strutils.parseInt(matches[0])
    result.frameh = strutils.parseInt(matches[1])
    SpriteSheets[filename] = result
  else:
    raise newException(EIO, "bad file: "&filename&" must be in format name_WxH.png")

proc newSound(filename: string): PSoundRecord =
  if hasKey(SoundCache, filename): 
    return SoundCache[filename]
  when defined(noSFML):
    new(result)
    result.file = filename
    SoundCache[filename] = result
  else:
    new(result)
    result.soundBuf = newSoundBuffer("data/sfx"/filename)
    SoundCache[filename] = result

when defined(NoSFML):
  proc load*(ss: PSpriteSheet): bool =
    if not ss.contents.unpackedSize == 0: return
    ss.contents = checksumFile(ss.file)
    result = true
  proc load*(s: PSoundRecord): bool =
    s.contents = checksumFile(s.file)
    result = true
else:
  proc load*(ss: PSpriteSheet): bool =
    if not ss.sprite.isNil: 
      return
    var image = sfml.newImage(ss.file)
    if image == nil:
      echo "Image could not be loaded"
      return
    let size = image.getSize()
    ss.rows = int(size.y / ss.frameh) #y is h
    ss.cols = int(size.x / ss.framew) #x is w
    ss.tex = newTexture(image)
    image.destroy()
    ss.sprite = newSprite()
    ss.sprite.setTexture(ss.tex, true)
    ss.sprite.setTextureRect(intrect(0, 0, ss.framew.cint, ss.frameh.cint))
    ss.sprite.setOrigin(vec2f(ss.framew / 2, ss.frameh / 2))
    result = true
  proc load*(s: PSoundRecord): bool =
    nil

template addError(e: expr): stmt {.immediate.} =
  errors.add(e)
  result = false
proc validateSettings*(settings: PJsonNode, errors: var seq[string]): bool =
  result = true
  if settings.kind != JObject:
    addError("Settings root must be an object")
    return
  if not settings.existsKey("vehicles"):
    addError("Vehicles section missing")
  if not settings.existsKey("objects"):
    errors.add("Objects section is missing")
    result = false
  if not settings.existsKey("level"):
    errors.add("Level settings section is missing")
    result = false
  else:
    let lvl = settings["level"]
    if lvl.kind != JObject or not lvl.existsKey("size"):
      errors.add("Invalid level settings")
      result = false
    elif not lvl.existsKey("size") or lvl["size"].kind != JArray or lvl["size"].len != 2:
      errors.add("Invalid/missing level size")
      result = false
  if not settings.existsKey("items"):
    errors.add("Items section missing")
    result = false
  else:
    let items = settings["items"]
    if items.kind != JArray or items.len == 0:
      errors.add "Invalid or empty item list"
    else:
      var id = 0
      for i in items.items:
        if i.kind != JArray or i.len != 3 or 
           i[0].kind != JString or i[1].kind != JString or i[2].kind != JObject:
          errors.add "Item #"& $id &" is invalid"
          result = false

proc loadSettingsFromFile*(filename: string, errors: var seq[string]): bool =
  if not existsFile(filename):
    errors.add("File does not exist: "&filename)
  else:
    result = loadSettings(readFile(filename), errors)

proc loadSettings*(rawJson: string, errors: var seq[string]): bool =
  var settings: PJsonNode
  try:
    settings = parseJson(rawJson)
  except EJsonParsingError:
    errors.add("JSON parsing error: "& getCurrentExceptionMsg())
    return
  except: 
    errors.add("Unknown exception: "& getCurrentExceptionMsg())
    return
  if not validateSettings(settings, errors):
    return
  if cfg != nil: #TODO try this
    echo("Overwriting zone settings")
    free(cfg)
    cfg = nil
  new(cfg, free)
  cfg.levelSettings = importLevel(settings)
  cfg.vehicles = @[]
  cfg.items = @[]
  cfg.objects = @[]
  cfg.bullets = @[]
  nameToVehID = initTable[string, int](32)
  nameToItemID = initTable[string, int](32)
  nameToObjID = initTable[string, int](32)
  nameToBulletID = initTable[string, int](32)
  var 
    vID = 0'i16
    bID = 0'i16
  for vehicle in settings["vehicles"].items:
    var veh = importVeh(vehicle)
    veh.id = vID
    cfg.vehicles.add veh
    nameToVehID[veh.name] = veh.id
    inc vID
  vID = 0
  if settings.existsKey("bullets"):
    for blt in settings["bullets"].items:
      var bullet = importBullet(blt)
      bullet.id = bID
      cfg.bullets.add bullet
      nameToBulletID[bullet.name] = bullet.id
      inc bID
  for item in settings["items"].items:
    var itm = importItem(item)
    itm.id = vID
    cfg.items.add itm
    nameToItemID[itm.name] = itm.id
    inc vID
    if itm.kind == Projectile and itm.bullet.id == -1:
      ## this item has an anonymous bullet, fix the ID and name
      itm.bullet.id = bID 
      itm.bullet.name = itm.name
      cfg.bullets.add itm.bullet
      nameToBulletID[itm.bullet.name] = itm.bullet.id
      inc bID
  vID = 0
  for obj in settings["objects"].items:
    var o = importObject(obj)
    o.id = vID
    cfg.objects.add o
    nameToObjID[o.name] = o.id
    inc vID
  result = true

proc `$`*(obj: PSpriteSheet): string =
  return "<Sprite $1 ($2x$3) $4 rows $5 cols>" % [obj.file, $obj.framew, $obj.frameh, $obj.rows, $obj.cols]

proc fetchVeh*(name: string): PVehicleRecord =
  return cfg.vehicles[nameToVehID[name]]
proc fetchItm*(itm: string): PItemRecord =
  return cfg.items[nameToItemID[itm]]
proc fetchObj*(name: string): PObjectRecord =
  return cfg.objects[nameToObjID[name]]
proc fetchBullet(name: string): PBulletRecord =
  return cfg.bullets[nameToBulletID[name]]

proc getField(node: PJsonNode, field: string, target: var float) =
  if not node.existsKey(field):
    return
  if node[field].kind == JFloat:
    target = node[field].fnum
  elif node[field].kind == JInt:
    target = node[field].num.float
proc getField(node: PJsonNode, field: string, target: var int) =
  if not node.existsKey(field):
    return
  if node[field].kind == JInt:
    target = node[field].num.int
  elif node[field].kind == JFloat:
    target = node[field].fnum.int
proc getField(node: PJsonNode; field: string; target: var bool) =
  if not node.existsKey(field):
    return
  case node[field].kind
  of JBool:
    target = node[field].bval
  of JInt:
    target = (node[field].num != 0)
  of JFloat:
    target = (node[field].fnum != 0.0)
  else: nil

template checkKey(node: expr; key: string): stmt =
  if not existsKey(node, key):
    return

proc importLevel(data: PJsonNode): PLevelSettings =
  new(result)
  result.size = vec2i(5000, 5000)
  result.starfield = @[]
  
  checkKey(data, "level")
  var level = data["level"]
  if level.existsKey("size") and level["size"].kind == JArray and level["size"].len == 2:
    result.size.x = level["size"][0].num.cint
    result.size.y = level["size"][1].num.cint
  if level.existsKey("starfield"):
    for star in level["starfield"].items:
      result.starfield.add(newSprite(star.str))
proc importPhys(data: PJsonNode): TPhysicsRecord =
  result.radius = 20.0
  result.mass = 10.0
  
  checkKey(data, "physics")
  if data["physics"].kind != JObject:
    return
  
  let phys = data["physics"]
  phys.getField("radius", result.radius)
  phys.getField("mass", result.mass)
proc importHandling(data: PJsonNode): THandlingRecord =
  result.thrust = 45.0
  result.topSpeed = 100.0 #unused
  result.reverse = 30.0
  result.strafe = 30.0
  result.rotation = 2200.0
  
  checkKey(data, "handling")
  if data["handling"].kind != JObject:
    return
  
  let hand = data["handling"]
  hand.getField("thrust", result.thrust)
  hand.getField("top_speed", result.topSpeed)
  hand.getField("reverse", result.reverse)
  hand.getField("strafe", result.strafe)
  hand.getField("rotation", result.rotation)
proc importAnim(data: PJsonNode): PAnimationRecord =
  new(result)
  result.angle = 0.0
  result.delay = 1000.0
  result.spriteSheet = nil
  
  checkKey(data, "anim")
  if data["anim"].kind == JString:
    result.spriteSheet = newSprite(data["anim"].str)
    return
  let anim = data["anim"]
  if anim.existsKey("file"): 
    result.spriteSheet = newSprite(anim["file"].str)
  anim.getField("angle", result.angle) 
  result.angle = radians(result.angle) ## comes in as degrees 
  anim.getField("delay", result.delay) 
  result.delay /= 1000 ## delay comes in as milliseconds
proc importSoul(data: PJsonNode): TSoulRecord =
  result.energy = 10000
  result.health = 1
  checkKey(data, "soul")
  let soul = data["soul"]
  soul.getField("energy", result.energy)
  soul.getField("health", result.health)
proc importExplosion(data: PJsonNode): TExplosionRecord =
  checkKey(data, "explode")
  let expl = data["explode"]
  result.anim = importAnim(expl)
  result.sound = importSound(expl, "sound")

when defined(NoSFML):
  proc importSound*(data: PJsonNode; fieldName: string = nil): PSoundRecord =
    new(result)
else:
  proc importSound*(data: PJsonNode; fieldName: string = nil): PSoundRecord =
    if data.kind == JObject:
      checkKey(data, fieldName)
      result = newSound(data[fieldName].str)
    elif data.kind == JString:
      result = newSound(data.str)

proc importVeh(data: PJsonNode): PVehicleRecord =
  new(result)
  result.playable = false
  if data.kind != JArray or data.len != 2 or 
    (data.kind == JArray and 
      (data[0].kind != JString or data[1].kind != JObject)):
    result.name = "(broken)"
    return
  var vehData = data[1]
  result.name = data[0].str
  result.anim = importAnim(vehdata)
  result.physics = importPhys(vehdata)
  result.handling = importHandling(vehdata)
  vehdata.getField("playable", result.playable)
  if result.anim.spriteSheet.isNil and result.playable:
    result.playable = false
proc importObject(data: PJsonNode): PObjectRecord =
  new(result)
  if data.kind != JArray or data.len != 2:
    result.name = "(broken)"
    return
  result.name = data[0].str
  result.anim = importAnim(data[1])
  result.physics = importPhys(data[1])
proc importItem(data: PJsonNode): PItemRecord =
  new(result)
  if data.kind != JArray or data.len != 3:
    result.name = "(broken)"
    return
  result.name = data[0].str
  result.anim = importAnim(data[2])
  result.physics = importPhys(data[2])
  
  result.cooldown = 100.0 
  data[2].getField("cooldown", result.cooldown)
  result.cooldown /= 1000.0  ##cooldown is stored in ms 
  
  result.useSound = importSound(data, "useSound")
  
  case data[1].str.toLower
  of "projectile":
    result.kind = Projectile
    if data[2]["bullet"].kind == JString:
      result.bullet = fetchBullet(data[2]["bullet"].str)
    elif data[2]["bullet"].kind == JInt:
      result.bullet = cfg.bullets[data[2]["bullet"].num.int]
    elif data[2]["bullet"].kind == JObject: 
      result.bullet = importBullet(data[2]["bullet"])
    else:
      echo "UNKNOWN BULLET TYPE for item ", result.name
      quit 1
  of "ammo":
    result.kind = Ammo
  of "utility":
    nil
  else:
    echo "Invalid item type \"", data[1].str, "\" for item ", result.name

proc importBullet(data: PJsonNode): PBulletRecord =
  new(result)
  result.id = -1
  
  var bdata: PJsonNode
  if data.kind == JArray:
    result.name = data[0].str
    bdata = data[1]
  elif data.kind == JObject:
    bdata = data
  else: 
    echo "I'm a broken bullet :("
    quit 1
  
  result.anim = importAnim(bdata)
  result.physics = importPhys(bdata)
  
  result.lifetime = 2000.0
  result.inheritVelocity = 1000.0
  result.baseVelocity = 30.0
  getField(bdata, "lifetime", result.lifetime)
  getField(bdata, "inheritVelocity", result.inheritVelocity)
  getField(bdata, "baseVelocity", result.baseVelocity)
  result.lifetime /= 1000.0 ## lifetime is stored as milliseconds
  result.inheritVelocity /= 1000.0 ## inherit velocity 1000 = 1.0 (100%)
  result.explosion = importExplosion(bdata)
