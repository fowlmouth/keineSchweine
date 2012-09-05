import
  sfml,
  sg_assets
type
  PAnimation* = ref TAnimation
  TAnimation* = object
    sprite*: PSprite
    delay*: float
    delayy*: float
    index*: int
    direction*: int
    maxCol*: int
    frameW: int
    spriteRect*: TIntRect
    style*: TAnimationStyle
  TAnimationStyle* = enum
    AnimLoop = 0'i8, AnimBounce, AnimOnce

proc free*(obj: PAnimation) =
  if obj.sprite.isNil:
    echo "sprite is nil -__-"
  else:
    obj.sprite.destroy()

proc newAnimation*(src: PAnimationRecord; style = AnimLoop): PAnimation =
  new(result, free)
  result.sprite = src.spriteSheet.sprite.copy()
  result.delay = src.delay
  result.delayy = src.delay
  result.index = 0
  result.direction = 1
  result.maxCol = src.spriteSheet.cols - 1
  result.frameW = src.spriteSheet.frameW
  result.spriteRect = result.sprite.getTextureRect()
  result.style = style

proc next*(obj: PAnimation; dt: float): bool {.discardable.} =
  ## step the animation. Returns false if the object is out of frames
  result = true
  obj.delay -= dt
  if obj.delay <= 0.0:
    obj.delay += obj.delayy
    obj.index += obj.direction
    if obj.index > obj.maxCol or obj.index < 0:
      case obj.style
      of AnimOnce:
        return false
      of AnimBounce:
        obj.direction *= -1
        obj.index += obj.direction * 2
      of AnimLoop:
        obj.index = 0
    obj.spriteRect.left = obj.index.cint * obj.frameW.cint
    obj.sprite.setTextureRect obj.spriteRect

proc draw*(window: PRenderWindow; obj: PAnimation) {.inline.} =
  window.draw(obj.sprite)
    
    