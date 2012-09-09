import sfml_audio, sg_assets
when defined(NoSFML):
  {.error.}
var
  liveSounds: seq[PSound] = @[]
  deadSounds: seq[PSound] = @[]

proc playSound*(sound: PSoundRecord) =
  if sound.soundBuf.isNil: return
  var s: PSound
  if deadSounds.len == 0:
    s = sfml_audio.newSound()
    s.setLoop false
  else:
    s = deadSounds.pop()
  s.setBuffer(sound.soundBuf)
  s.play()
  liveSounds.add s

proc updateSoundBuffer*() =
  var i = 0
  while i < len(liveSounds):
    if liveSounds[i].getStatus == Stopped:
      deadSounds.add liveSounds[i]
      liveSounds.del i
    else:
      inc i

proc report*() =
  echo "live: ", liveSounds.len
  echo "dead: ", deadSounds.len
