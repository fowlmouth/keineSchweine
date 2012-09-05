import 
  math, strutils,
  sfml, sfml_vector, chipmunk,
  input_helpers

proc degrees*(rad: float): float =
  return rad * 180.0 / PI
proc radians*(deg: float): float =
  return deg * PI / 180.0
proc vec2f*(a: TVector2i): TVector2f =
  result.x = a.x.cfloat
  result.y = a.y.cfloat
proc vec2i*(a: TVector2f): TVector2i =
  result.x = a.x.cint
  result.y = a.y.cint
proc floor*(a: TVector): TVector2f {.inline.} =
  result.x = a.x.floor
  result.y = a.y.floor
proc sfml2cp*(a: TVector2f): TVector {.inline.} =
  result.x = a.x
  result.y = a.y
proc cp2sfml*(a: TVector): TVector2f {.inline.} =
  result.x = a.x
  result.y = a.y

proc ff*(f: float, precision = 2): string {.inline.} = 
  return formatFloat(f, ffDecimal, precision)

proc `$`*(a: var TIntRect): string =
  result = "[TIntRect $1,$2 $3x$4]".format($a.left, $a.top, $a.width, $a.height)
proc `$`*(a: TKeyEvent): string =
  return "KeyEvent: code=$1 alt=$2 control=$3 shift=$4 system=$5".format(
    $a.code, $a.alt, $a.control, $a.shift, $a.system)

proc `wmod`*(x, y: float): float = return x - y * (x/y).floor
proc move*(a: var TIntRect, left, top: cint): bool =
  if a.left != left or a.top != top: result = true
  a.left = left
  a.top  = top
