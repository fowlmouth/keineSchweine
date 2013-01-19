import chipmunk
type
  PVolatile* = ref TVolatile
  TVolatile* = object of TObject
    shape*: chipmunk.PShape
    lifetime*: float

proc free*(obj: PVolatile) = 
  if not obj.shape.isNil:
    if not obj.shape.getBody.isNil:
      obj.shape.getBody.free()
    obj.shape.free()

method update*(obj: PVolatile; dt: float): bool =
  ## returns true if it should be removed
  obj.lifetime -= dt
  if obj.lifetime <= 0.0:
    if not obj.shape.isNil:
      let space = obj.shape.getSpace()
      space.removeShape obj.shape
      if not obj.shape.getBody.isRogue:
        space.removeBody obj.shape.getBody
    return true


