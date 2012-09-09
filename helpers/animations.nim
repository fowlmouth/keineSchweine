import
  math,
  sfml, chipmunk,
  sg_assets, sfml_stuff, math_helpers
type
  PAnimation* = ref TAnimation
  TAnimation* = object
    sprite*: PSprite
    record*: PAnimationRecord
    delay*: float
    index*: int
    direction*: int
    spriteRect*: TIntRect
    style*: TAnimationStyle
  TAnimationStyle* = enum
    AnimLoop = 0'i8, AnimBounce, AnimOnce

proc free*(obj: PAnimation) =
  obj.sprite.destroy()
  obj.record = nil

proc newAnimation*(src: PAnimationRecord; style = AnimLoop): PAnimation =
  new(result, free)
  result.sprite = src.spriteSheet.sprite.copy()
  result.record = src
  result.delay = src.delay
  result.index = 0
  result.direction = 1
  result.spriteRect = result.sprite.getTextureRect()
  result.style = style
proc newAnimation*(src: PAnimationRecord; style: TAnimationStyle; pos: TVector2f): PAnimation {.inline.} =
  result = newAnimation(src, style)
  result.sprite.setPosition(pos)

proc next*(obj: PAnimation; dt: float): bool {.discardable.} =
  ## step the animation. Returns false if the object is out of frames
  result = true
  obj.delay -= dt
  if obj.delay <= 0.0:
    obj.delay += obj.record.delay
    obj.index += obj.direction
    #if obj.index > (obj.record.spriteSheet.cols - 1) or obj.index < 0:
    if not(obj.index in 0..(obj.record.spriteSheet.cols - 1)):
      case obj.style
      of AnimOnce:
        return false
      of AnimBounce:
        obj.direction *= -1
        obj.index += obj.direction * 2
      of AnimLoop:
        obj.index = 0
    obj.spriteRect.left = obj.index.cint * obj.record.spriteSheet.frameW.cint
    obj.sprite.setTextureRect obj.spriteRect

proc setPos*(obj: PAnimation; pos: TVector) {.inline.} =
  setPosition(obj.sprite, pos.floor())
proc setPos*(obj: PAnimation; pos: TVector2f) {.inline.} =
  setPosition(obj.sprite, pos)
proc setAngle*(obj: PAnimation; radians: float) {.inline.} =
  if obj.record.spriteSheet.rows > 1:
    ## (rotation percent * rows).floor * frameheight
    obj.spriteRect.top = ((radians + obj.record.angle).wmod(TAU) / TAU * obj.record.spriteSheet.rows.float).floor.cint * obj.record.spriteSheet.frameh.cint
    obj.sprite.setTextureRect obj.spriteRect
  else:
    setRotation(obj.sprite, degrees(radians)) #stupid sfml, who uses degrees these days? -__-

proc draw*(window: PRenderWindow; obj: PAnimation) {.inline.} =
  window.draw(obj.sprite)
