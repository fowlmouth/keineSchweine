import nake
nakeimports

const
  ServerDefines = "-d:NoSFML --forceBuild"
task "server", "build the server":
  if shell("nimrod", ServerDefines, "-r", "compile", "enet_server") != 0:
    quit "Failed to build"
