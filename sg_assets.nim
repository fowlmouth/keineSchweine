import
  re, json, strutils, tables, math, os,
  sfml, sfml_vector
type
  PZoneSettings* = ref TZoneSettings
  TZoneSettings* = object
    vehicles: seq[PVehicleRecord]
    items: seq[PItemRecord]
    objects: seq[PObjectRecord]
    levelSettings: PLevelSettings
  PLevelSettings* = ref TLevelSettings
  TLevelSettings* = object
    size: TVector2i
  PVehicleRecord* = ref TVehicleRecord
  TVehicleRecord* = object
    id*: int16
    name*: string
    playable*: bool
    anim*: TAnimationRecord
    physics*: TPhysicsRecord
    handling*: THandlingRecord
  TItemKind* = enum
    Projectile, Utility, Ammo
  PObjectRecord* = ref TObjectRecord
  TObjectRecord* = object
    id*: int16
    name*: string
    anim*: TAnimationRecord
    physics*: TPhysicsRecord
  PItemRecord* = ref TItemRecord
  TItemRecord* = object
    id*: int16
    name*: string
    kind*: TItemKind
    anim*: TAnimationRecord
  TPhysicsRecord* = object
    mass*: float
    radius*: float
  THandlingRecord = object
    thrust*, top_speed*: float
    reverse*, strafe*, rotation*: int
  TAnimationRecord* = object
    spriteSheet*: PSpriteSheet
    angle*: float
  PSpriteSheet* = ref TSpriteSheet
  TSpriteSheet* = object 
    file*: string
    framew*,frameh*: int
    rows*, cols*: int
    sprite*: PSprite
    tex: PTexture
  TGameState* = enum
    Lobby, Transitioning, Field
var 
  cfg: PZoneSettings
  SpriteSheets = initTable[string, PSpriteSheet](64)
  nameToVehID*: TTable[string, int]
  nameToItemID*: TTable[string, int]
  activeState = Lobby
proc newSprite*(filename: string): PSpriteSheet
proc load*(ss: PSpriteSheet): bool {.discardable.}
proc validateSettings*(settings: PJsonNode; errors: var seq[string]): bool
proc loadSettings*(rawJson: string, errors: var seq[string]): bool
proc loadSettingsFromFile*(filename: string, errors: var seq[string]): bool

proc importVeh(data: PJsonNode): PVehicleRecord
proc importObject(data: PJsonNode): PObjectRecord
proc importItem(data: PJsonNode): PItemRecord
proc importPhys(data: PJsonNode): TPhysicsRecord
proc importAnim(data: PJsonNode): TAnimationRecord
proc importHandling(data: PJsonNode): THandlingRecord

## this is the only pipe between lobby and main.nim
proc getActiveState*(): TGameState =
  result = activeState
proc transition*() = 
  assert activeState == Lobby
  activeState = Transitioning
proc doneWithSaidTransition*() =
  assert activeState == Transitioning
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

proc newSprite*(filename: string): PSpriteSheet =
  if hasKey(SpriteSheets, filename):
    return SpriteSheets[filename]
  var matches: array[0..1, string]
  if re.match(filename, re"\S+_(\d+)x(\d+)\.\S\S\S", matches):
    var framew = strutils.parseInt(matches[0])
    var frameh = strutils.parseInt(matches[1])
    new(result, free)
    result.file = "data/gfx/" & filename
    result.framew = framew
    result.frameh = frameh
    SpriteSheets[filename] = result
  else:
    raise newException(EIO, "bad file: "&filename&" must be in format name_WxH.png")

proc validateSettings*(settings: PJsonNode, errors: var seq[string]): bool =
  result = true
  if settings.kind != JObject:
    errors.add("Settings root must be an object")
    return false
  if not settings.existsKey("vehicles"):
    errors.add("Vehicles section missing")
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
  var settings = parseJson(rawJson)
  if not validateSettings(settings, errors):
    return
  if cfg != nil: #TODO try this
    echo("Overwriting zone settings")
    free(cfg)
    cfg = nil
  new(cfg, free)
  cfg.vehicles = @[]
  cfg.items = @[]
  cfg.objects = @[]
  nameToVehID = initTable[string, int](32)
  nameToItemID = initTable[string, int](32)
  var 
    vID = 0'i16
    itmID = 0'i16
  for vehicle in settings["vehicles"].items:
    var veh = importVeh(vehicle)
    inc(vID)
    veh.id = vID
    cfg.vehicles.add veh
    nameToVehID[veh.name] = veh.id
  for item in settings["items"].items:
    var itm = importItem(item)
    inc(itmID)
    itm.id = itmID
    cfg.items.add itm
    nameToItemID[itm.name] = itm.id
  for obj in settings["objects"].items:
    var o = importObject(obj)
    inc(vID)
    o.id = vID
    cfg.objects.add o
    
  result = true

    

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
  result = true

proc `$`*(obj: PSpriteSheet): string =
  return "<Sprite $1 ($2x$3) $4 rows $5 cols>" % [obj.file, $obj.framew, $obj.frameh, $obj.rows, $obj.cols]

proc fetchVeh*(name: string): PVehicleRecord =
  return cfg.vehicles[nameToVehID[name]]
proc fetchItm*(itm: string): PItemRecord =
  return cfg.items[nameToItemID[itm]]

proc getField(node: PJsonNode, field: string, target: var float) =
  if not node.existsKey(field):
    return
  target = node[field].fnum
proc getField(node: PJsonNode, field: string, target: var int) =
  if not node.existsKey(field):
    return
  target = node[field].num.int

proc importPhys(data: PJsonNode): TPhysicsRecord =
  result.radius = 20.0
  result.mass = 10.0
  if not data.existsKey("physics") or data["physics"].kind != JObject:
    return
  var phys = data["physics"]
  var i: int
  phys.getField("radius", i)
  if i > 0:
    result.radius = i.float
    i = 0
  phys.getField("mass", i)
  if i > 0:
    result.mass = i.float
proc importHandling(data: PJsonNode): THandlingRecord =
  result.thrust = 45.0
  result.topSpeed = 100.0 #unused
  result.reverse = 30
  result.strafe = 30
  result.rotation = 2200
  if not data.existsKey("handling") or data["handling"].kind != JObject:
    return
  var hand = data["handling"]
  var i = 0
  hand.getField("thrust", i)
  if i > 0: 
    result.thrust = i.float
    i = 0
  hand.getField("top_speed", i)
  if i > 0: 
    result.topSpeed = i.float
    i = 0
  hand.getField("reverse", result.reverse)
  hand.getField("strafe", result.strafe)
  hand.getField("rotation", result.rotation)
proc importAnim(data: PJsonNode): TAnimationRecord =
  result.angle = 0.0
  result.spriteSheet = nil
  if not data.existsKey("anim"):
    return
  elif data["anim"].kind == JString:
    result.spriteSheet = newSprite(data["anim"].str)
    return
  var anim = data["anim"]
  if anim.existsKey("file"): 
    result.spriteSheet = newSprite(anim["file"].str)
  var angle: int
  anim.getField("angle", angle)
  result.angle = angle.float * PI / 180.0
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
  if not result.anim.spriteSheet.isNil:
    result.playable = true
proc importObject(data: PJsonNode): PObjectRecord =
  new(result)
  if data.kind != JArray or data.len != 2:
    result.name = "(broken)"
    return
  result.name = data[0].str
  
proc importItem(data: PJsonNode): PItemRecord =
  new(result)
  if data.kind != JArray or data.len != 3:
    result.name = "(broken)"
    return
  result.name = data[0].str
  case data[1].str
  of "Projectile":
    result.kind = Projectile
  of "Ammo":
    result.kind = Ammo
  else: nil