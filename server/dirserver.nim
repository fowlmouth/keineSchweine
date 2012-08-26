## directory server
## handles client authorization and assets
import 
  json, sockets,
  sg_packets
type
  TZone = object
    name: string
    host: string
    port: TPort
    key: string
    sock: TSocket
var
  zoneList = newScZonelist()
  handlers = initTable[char, proc()](16)


handlers[HZoneLogin] = proc(s: PStream) =
  var info = readSdZoneLogin(s)
  
  


when isMainModule:
  var s = json.parseFile("dirserver_settings.json")
  zoneList.network = s["network"].str
  let port = s["port"].num.TPort
  var slots: seq[tuple[