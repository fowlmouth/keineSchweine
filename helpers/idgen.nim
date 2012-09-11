type
  PIDGen*[T: Ordinal] = ref TIDGen[T]
  TIDGen[T: Ordinal] = object
    max: T
    freeIDs: seq[T]

#proc free[T](idg: PIDgen[T]) = 
#  result.freeIDs = nil
proc newIDGen*[T: Ordinal](): PIDGen[T] =
  new(result)#, free)
  result.max = 0.T
  result.freeIDs = @[]
proc next*[T](idg: PIDGen[T]): T =
  if idg.freeIDs.len > 0:
    result = idg.freeIDs.pop
  elif idg.max < high(T)-T(1):
    idg.max += 1
    result = idg.max
  else:
    nil #system meltdown
proc del*[T](idg: PIDGen[T]; id: T) =
  idg.freeIDs.add id
