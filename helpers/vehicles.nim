import
  sfml, sfml_vector, chipmunk, 
  sg_assets
type
  PVehicle* = ref TVehicle
  TVehicle* = object
    body*:      chipmunk.PBody
    shape*:     chipmunk.PShape
    record*:   PVehicleRecord
    sprite*:   PSprite
    spriteRect*: TIntRect
    when false:
      position*: TVector2f
      velocity*: TVector2f
      angle*:    float


proc update*(obj: PVehicle) =
  obj.sprite.setPosition(obj.body.getPos.floor)
  let 
    x = ((-activeVehicle.body.getAngVel + W_LIMIT) / (W_LIMIT*2.0) * (activeVehicle.record.anim.spriteSheet.cols - 1).float).floor.int * obj.record.anim.spriteSheet.framew
    y = ((obj.offsetAngle.wmod(TAU) / TAU) * obj.record.anim.spriteSheet.rows.float).floor.int * obj.record.anim.spriteSheet.frameh
  if obj.spriteRect.move(x.cint, y.cint):
    obj.sprite.setTextureRect(obj.spriteRect)

proc accel*(obj: PVehicle, dt: float) =
  #obj.velocity += vec2f(
  #  cos(obj.angle) * obj.record.handling.thrust.float * dt,
  #  sin(obj.angle) * obj.record.handling.thrust.float * dt)
  obj.body.applyImpulse(
    vectorForAngle(obj.body.getAngle()) * dt * obj.record.handling.thrust,
    vectorZero)
proc reverse*(obj: PVehicle, dt: float) =
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
