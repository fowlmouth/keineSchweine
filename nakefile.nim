import nake
nakeImports

const ExeName = "keineschweine"

task "test", "Build to test dir":
  let res = shell("nimrod", "--forceBuild",
    "-d:showFPS", "-d:moreNimrod", "-d:debugKeys",
    "compile", ExeName)
  if res == 0:
    runTask "skel"
    moveFile ExeName, "test"/ExeName
    cd "test"
    shell "./"&ExeName

task "release", "release build":
  let res = shell("nimrod", "-d:release", "compile", ExeName)
  if res != 0:
    echo "The build failed."
    quit 1
  else:
    runTask "clean"
    ## zip up all the files and such or something useful here 

task "skel", "create skeleton test dir for testing":
  if not existsDir("test"):
    createDir("test")
  if not existsDir("test/data/fnt"):
    createDir("test/data/fnt")
  if not existsFile("test/data/fnt/LiberationMono-Regular.ttf"):
    copyFile "data/fnt/LiberationMono-Regular", "test/data/fnt/LiberationMono-Regular.ttf"
  if not existsFile("test/client_settings.json"):
    copyFile "client_settings.json", "test/client_settings.json"

task "clean", "cleanup generated files":
  var dirs = @["nimcache", "server"/"nimcache"]
  dirs.each(proc(x: var string) =
    if existsDir(x): removeDir(x))
  


