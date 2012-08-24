import streams
from strutils import repeatChar

proc readPaddedStr*(s: PStream, length: int, padChar = '\0'): TaintedString = 
  var lastChr = length
  result = s.readStr(length)
  while lastChr >= 0 and result[lastChr - 1] == padChar: dec(lastChr)
  result.setLen(lastChr)

proc writePaddedStr*(s: PStream, str: string, length: int, padChar = '\0') =
  if str.len < length:
    s.write(str)
    s.write(repeatChar(length - str.len, padChar))
  elif str.len > length:
    s.write(str.substr(0, length - 1))
  else:
    s.write(str)

proc readLEStr*(s: PStream): TaintedString =
  var len = s.readInt16()
  result = s.readStr(len)

proc writeLEStr*(s: PStream, str: string) =
  s.write(str.len.int16)
  s.write(str)

when isMainModule:
  var testStream = newStringStream()
  
  testStream.writeLEStr("Hello")
  doAssert testStream.data == "\5\0Hello"
  
  testStream.setPosition 0
  var res = testStream.readLEStr()
  doAssert res == "Hello"
  
  testStream.setPosition 0
  testStream.writePaddedStr("Sup", 10)
  echo(repr(testStream), testStream.data.len)
  doAssert testStream.data == "Sup"&repeatChar(7, '\0')
  
  testStream.setPosition 0
  res = testStream.readPaddedStr(10)
  doAssert res == "Sup"
  
  testStream.close()

