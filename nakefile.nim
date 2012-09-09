import nake
nakeImports

const 
  GameAssets = "http://dl.dropbox.com/u/37533467/data-08-01-2012.7z"
  ExeName = "keineschweine"
  ServerDefines = "-d:NoSFML -d:NoChipmunk"
  TestBuildDefines = "-d:debugWeps -d:showFPS -d:moreNimrod -d:debugKeys -d:foo -d:recordMode --forceBuild"
  ReleaseDefines = "-d:release --deadCodeElim:on"

task "test", "Build with test defines":
  if shell("nimrod", TestBuildDefines, "compile", ExeName) != 0:
    echo "The build failed."
    quit 1
  shell "."/ExeName, "offline"

task "dirserver", "build the directory server":
  withDir "server":
    if shell("nimrod", ServerDefines, "compile", "dirserver") != 0:
      echo "Failed to build the dirserver"
      quit 1
task "zoneserver", "build the zone server":
  withDir "server":
    if shell("nimrod", ServerDefines, "compile", "sg_server") != 0:
      echo "Failed to build the zoneserver"
      quit 1

task "servers", "build the server and directory server":
  runTask "dirserver"
  runTask "zoneserver"
  echo "Successfully built both servers :')"

task "all", "run SERVERS and TEST tasks":
  runTask "servers"
  runTask "test"

task "release", "release build":
  let res = shell("nimrod", ReleaseDefines, "compile", ExeName)
  if res != 0:
    echo "The build failed."
    quit 1
  else:
    runTask "clean"
    ## zip up all the files and such or something useful here 

task "testskel", "create skeleton test dir for testing":
  if not existsDir("test"):
    createDir("test")
  if not existsDir("test/data/fnt"):
    createDir("test/data/fnt")
  if not existsFile("test/data/fnt/LiberationMono-Regular.ttf"):
    copyFile "data/fnt/LiberationMono-Regular", "test/data/fnt/LiberationMono-Regular.ttf"
  if not existsFile("test/client_settings.json"):
    copyFile "client_settings.json", "test/client_settings.json"
  runTask "test"
  copyFile ExeName, "test"/ExeName
  withDir "test":
    shell "."/ExeName

task "clean", "cleanup generated files":
  var dirs = @["nimcache", "server"/"nimcache"]
  dirs.each(proc(x: var string) =
    if existsDir(x): removeDir(x))

import httpclient
task "download", "download game assets":
  var path = expandFilename("data")
  path.add DirSep
  path.add(extractFilename(gameAssets))
  if existsFile(path):
    echo "The file already exists\n",
      "[R]emove  [M]ove  [Q]uit"
    case stdin.readLine.toLower
    of "r":
      removeFile path
    of "m":
      moveFile path, path/../(extractFilename(gameAssets)&"-old")
    else:
      quit 0
  echo "Downloading to ", path
  downloadFile gameAssets, path
  echo "Download finished"
  
  let targetDir = parentDir(parentDir(path))
  when defined(linux):
    let z7 = findExe("7z")
    if z7 == "":
      quit "Could not find 7z"
    if shell(z7, "t", path) != 0: ##note to self: make sure this is right
      quit "Bad download"
    echo "Unpacking..."
    shell(z7, "x", "-w[$1]" % targetDir, path)
  else:
    echo "I do not know how to unpack the data on this system. Perhaps you could ",
      "fill this part in?"


