import macros, streams, streams_enh, genpacket, sockets
type
  PacketID* = char
template idpacket(pktName, id, s2c, c2s: expr): stmt {.immediate.} =
  let `H pktName`* {.inject.} = id
  defPacket(`Sc pktName`, s2c)
  defPacket(`Cs pktName`, c2s)

idPacket(Login, 'a',
  tuple[id: int16],
  tuple[alias: string, passwd: string])

forwardPacket(TPort, int16)
defPacket(ScZoneRecord, tuple[
  name: string = "", desc: string = "", players: int16 = 0,
  ip: string = "", port: TPort = 0.Tport])
idPacket(ZoneList, 'z',
  tuple[time: string = "fu", zones: seq[ScZoneRecord]],
  tuple[time: string])

let HPoing* = 'p'
defPacket(Poing, tuple[id: int32, time: float32])

type
  ChatType* = enum
    CPub = 0'i8, CPriv, CSystem, CError
forwardPacket(ChatType, int8)

idPacket(Chat, 'C', 
  tuple[kind: ChatType = CPub; fromPlayer: string = ""; text: string = ""],
  tuple[target: string = ""; text: string = ""])

idPacket(Hello, 'h',
  tuple[resp: string],
  tuple[i: int8 = 14])

let HPlayerList* = 'P'
defPacket(ScPlayerRec, tuple[id: int16; alias: string = ""])
defPacket(ScPlayerList, tuple[players: seq[ScPlayerRec]])

let HTeamList* = 'T'
defPacket(ScTeam, tuple[id: int8; name: string = ""])
defPacket(ScTeamList, tuple[teams: seq[ScTeam]])
let HTeamChange* = 't'


