import sfml
from strutils import format
proc `$`*(a: var TIntRect): string =
  result = "[TIntRect $1,$2 $3x$4]".format($a.left, $a.top, $a.width, $a.height)