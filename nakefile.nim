import nake
nakeImports

const 
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

