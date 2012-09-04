import genpacket, sockets, md5
defPacketImports()

type
  PacketID* = char

template idpacket(pktName, id, s2c, c2s: expr): stmt {.immediate, dirty.} =
  let `H pktName`* {.inject.} = id
  defPacket(`Sc pktName`, s2c)
  defPacket(`Cs pktName`, c2s)

forwardPacket(Uint8, int8)
forwardPacket(Uint16, int16)
forwardPacket(TPort, int16)

idPacket(Login, 'a',
  tuple[id: uint16; alias: string; sessionKey: string],
  tuple[alias: string, passwd: string])

let HZoneJoinReq* = 'j'
defPacket(CsZoneJoinReq, tuple[session: ScLogin])

defPacket(ScZoneRecord, tuple[
  name: string = "", desc: string = "",
  ip: string = "", port: TPort = 0.Tport])
idPacket(ZoneList, 'z',
  tuple[network: string = "", zones: seq[ScZoneRecord]],
  tuple[time: string])

let HPoing* = 'p'
defPacket(Poing, tuple[id: int32, time: float32])

type ChatType* = enum
  CPub = 0'i8, CPriv, CSystem, CError
forwardPacket(ChatType, int8)
idPacket(Chat, 'C', 
  tuple[kind: ChatType = CPub; fromPlayer: string = ""; text: string = ""],
  tuple[target: string = ""; text: string = ""])

idPacket(Hello, 'h',
  tuple[resp: string],
  tuple[i: int8 = 14])

let HPlayerList* = 'P'
defPacket(ScPlayerRec, tuple[id: uint16; alias: string = ""])
defPacket(ScPlayerList, tuple[players: seq[ScPlayerRec]])

let HTeamList* = 'T'
defPacket(ScTeam, tuple[id: int8; name: string = ""])
defPacket(ScTeamList, tuple[teams: seq[ScTeam]])
let HTeamChange* = 't'

idPacket(ZoneQuery, 'Q',
  tuple[playerCount: Uint16], ##i should include a time here or something
  tuple[pad: char = '\0'])

type SpawnKind = enum
  SpawnItem = 1'i8, SpawnVehicle, SpawnObject
forwardPacket(SpawnKind, int8)
defPacket(ScSpawn, tuple[
  kind: SpawnKind; id: uint16; record: uint16; amount: uint16])

type TAssetType* = enum
  FZoneCfg = 1'i8, FGraphics, FSound 
forwardPacket(TAssetType, int8)
forwardPacket(MD5Digest, array[0..15, int8])
idPacket(FileChallenge, 'F', 
  tuple[file: string; assetType: TAssetType; fullLen: int32],
  tuple[needfile: bool, checksum: MD5Digest])

let HChallengeResult* = '('
defPacket(ScChallengeResult, tuple[status: bool])

let HFileTransfer* = 'f'
defPacket(ScFileTransfer, tuple[fileSize: int32; pos: int32; data: string])
defPacket(CsFilepartAck, tuple[lastpos: int32])

##dir server messages
let HZoneLogin* = 'u'
defPacket(SdZoneLogin, tuple[name: string; key: string; record: ScZoneRecord])
defPacket(DsZoneLogin, tuple[status: bool])
let HDsMsg* = 'c'
defPacket(DsMsg, tuple[msg: string])
let HVerifyClient* = 'v'
defPacket(SdVerifyClient, tuple[session: ScLogin])