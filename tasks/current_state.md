Git cloned original Jedi Academy into ~/projects/jedy_academy/Jedi-Academy
Git cloned openjk into ~/projects/jedy_academy/jedi_academy (fork remote: github.com/sdelta/JediAcademy.git)
Installed Jedy Academy for assets into 'E:\Steam\steamapps\common\Jedi Academy' (GameData/base has assets0-3.pk3)
installed VC_redist.x64 and vs_BuildTools on windows

VS Build Tools 2026 (v18.11.3) verified installed at:
  C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools
  (MSVC 19.51 / cl.exe, MSBuild 18.11, bundled cmake.exe 4.3.1 + ninja)

Windows SP build DONE (SP-only, x64, Release):
  source staged (no .git) at E:\Games\JA_mod\src\openjk
  build dir at E:\Games\JA_mod\build
  playable layout assembled in E:\Games\JA_mod:
    openjk_sp.x86_64.exe, jagamex86_64.dll, rdsp-vanilla_x86_64.dll
    SDL2.dll (x64), OpenAL32.dll + EaxMan.dll (32-bit, unused by x64 build)
    base/assets0-3.pk3 + jaconfig.cfg + jampconfig.cfg
  Run single player with: E:\Games\JA_mod\openjk_sp.x86_64.exe

Linux (WSL) headless server built and smoke-tested:
  ~/projects/jedy_academy/jedi_academy/build/openjkded.x86_64
  ~/projects/jedy_academy/jedi_academy/build/jampgamex86_64.so

Stable helper scripts in ~/projects/jedy_academy/scripts/:
  sync-to-windows.sh   copy latest code (WSL -> E:\Games\JA_mod\src\openjk)
  build-windows.sh     configure+build SP (x64, Release) + assemble playable files
  build-server.sh      build Linux dedicated server + MP game module
  run-server.sh        launch headless server (stdin console) for testing

Notes:
  E:\ drive is ~99% full (~11 GB free) - worth cleaning up before more builds.
