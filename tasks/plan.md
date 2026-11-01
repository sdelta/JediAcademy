# Plan — OpenJK, assets, WSL headless build/test loop, Windows playable build

## Goal

Closed loop for modding Jedi Academy from WSL2 Ubuntu:

1. Develop against **OpenJK** (community fork of this exact code; modern CMake build).
2. Use **retail JKA assets** (`GameData/base/`).
3. **Build + test** strictly headless in WSL using the **dedicated server** (no UI/GPU).
4. Produce a **playable Windows build** by invoking **Visual Studio tools from WSL**
   (interop), building on the Windows filesystem.

(Note: "OpenJK", not "OpenJDK" — that's the unrelated Java runtime.)

---

## Prerequisites

On **Linux (WSL)**:

```sh
sudo apt-get update
sudo apt-get install -y build-essential cmake git \
    libjpeg-dev libpng-dev zlib1g-dev libsdl2-dev   # SDL2 only needed for the client, harmless for server
# optional, for the debug/test loop
sudo apt-get install -y gdb
```

On **Windows** (the other side of WSL interop):

- Visual Studio (2019/2022) with the **C++ desktop workload** (this installs
  `MSBuild.exe`, the MSVC toolchain, and CMake — needed in §4).
- Optionally Windows CMake (`cmake.exe`) on PATH if not using VS's bundled one.

---

## Phase 0 — Fork & clone OpenJK

```sh
# Fork https://github.com/JACoders/OpenJK on GitHub first, then:
cd ~ && mkdir -p src && cd src
git clone https://github.com/<you>/OpenJK.git openjk
cd openjk
git remote add upstream https://github.com/JACoders/OpenJK.git
```

Keep **two working copies** (see §3 vs §4):

- `~/src/openjk` — on **ext4**, for the fast WSL server build/test loop.
- `/mnt/c/<you>/src/openjk` — on **NTFS**, for the Windows VS build.

They are the same git repo/branch; use `git push`/`git pull` (or `git worktree`)
to keep them in sync. The Windows copy lives on NTFS because MSVC struggles with
`\\wsl$\...` paths (case sensitivity, slow I/O).

Optionally rename the project (OpenJK README): change `JK_VERSION` in
`codemp/qcommon/game_version.h` to your mod name.

---

## Phase 1 — Get the game assets

The engine needs retail `GameData/` with its `base/` assets (no assets ship in
OpenJK; they're copyrighted).

**Option A — already own it on Windows:** just point the game at the existing
install, e.g. `/mnt/c/Program Files (x86)/Steam/steamapps/common/Jedi Academy/GameData`.

**Option B — pull it down in WSL via SteamCMD (no GUI):**

```sh
sudo apt-get install -y steamcmd
steamcmd +@sSteamCmdForcePlatformType windows +force_install_dir ~/jka +login <you> +app_update 6020 +quit
# -> ~/jka/GameData/base/...
```

(The `windows` platform flag is required: JKA on Steam is a Windows title.)

Record the asset path, e.g. `JKA_ASSETS=~/jka/GameData` (Linux side) and
`JKA_WIN_ASSETS="C:\...\Jedi Academy\GameData"` (Windows side).

---

## Phase 2 — Headless server build (WSL)

Build **only** the dedicated server and its game module. From the ext4 checkout:

```sh
cd ~/src/openjk
cmake -B build -S . -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DBuildMPEngine=OFF   -DBuildMPRdVanilla=OFF -DBuildMPRend2=OFF \
    -DBuildMPCGame=OFF    -DBuildMPUI=OFF \
    -DBuildSPEngine=OFF   -DBuildSPGame=OFF     -DBuildSPRdVanilla=OFF \
    -DBuildJK2SPGame=OFF
cmake --build build -j"$(nproc)"
```

What this produces (Linux, x86_64):

- `build/openjkded.x86_64` — MP dedicated server (headless).
- `build/jampgamex86_64.so` — MP **server-side game module** (this is where most
  gameplay modding happens: weapons, sabers, NPC/bot AI, game rules).

For the debug/test loop, also make an ASan/UBSan build (WSL's big advantage):

```sh
cmake -B build-asan -S . -DCMAKE_BUILD_TYPE=Debug \
    -DUseAddressSanitizer=ON -DUseUndefinedSanitizer=ON \
    <same -DBuild* options as above>
cmake --build build-asan -j"$(nproc)"
```

### Run the server (headless, no UI)

```sh
cd "$JKA_ASSETS"
~/src/openjk/build/openjkded.x86_64 \
    +set dedicated 2 \
    +set fs_basepath "$JKA_ASSETS" \
    +set fs_homepath ~/.openjk-test \
    +set sv_pure 0 \
    +set vm_game 0 \
    +set rconpassword test \
    +set net_port 29070 \
    +exec server.cfg
```

Key flags:

- `vm_game 0` — force the **native** `jampgamex86_64.so` (your modded module)
  instead of a bytecode `.qvm`. Non-negotiable for testing your code.
- `fs_basepath` — where the assets are; `fs_homepath` — writable dir for
  configs/saves/logs (use a throwaway dir per test run).
- `dedicated 2` — LAN/listen-less dedicated server; prints a console to stdin.

Because the dedicated server uses a TTY console (`con_tty`), you interact with it
directly on stdin/stdout:

```
map mp/ffa3        # load a map
addbot Kyle 5      # spawn a bot
sv_cheats 1
rcon test status
g_* <value>        # tweak your mod's cvars live
```

### Testing practices

- Rebuild only what changed: `cmake --build build --target jampgamex86_64 -j`.
- Re-run the server, type a map + `addbot`, watch behavior, check logs at
  `~/.openjk-test/base/games.log` / console output.
- Run under **gdb**: `gdb --args .../openjkded.x86_64 +set dedicated 2 ...`.
- Use the **ASan** build (`build-asan/openjkded.x86_64`) to catch memory errors in
  your gameplay code with a full backtrace — a huge part of why the WSL loop wins.
- Automate: script a boot → `map` → `addbot N` → `wait` → `rcon` sequence and grep
  the log for assertions/errors; this is CI-friendly.

---

## Phase 3 — Playable Windows build, driven from WSL

Use WSL→Windows **interop** to run the Windows CMake + MSBuild without leaving
the terminal. The source must be on NTFS.

From WSL (Windows-side checkout under `/mnt/c`):

```sh
cd /mnt/c/<you>/src/openjk

# 1. Generate a Visual Studio solution with Windows CMake (note C:\ paths)
cmake.exe -S "C:\\<you>\\src\\openjk" -B "C:\\<you>\\src\\openjk\\build-win" \
    -G "Visual Studio 17 2022" -A x64 \
    -DCMAKE_INSTALL_PREFIX="C:\\...\\Jedi Academy\\GameData"

# 2. Build (MSBuild from WSL — no IDE)
msbuild.exe "C:\\<you>\\src\\openjk\\build-win\\OpenJK.sln" \
    /p:Configuration=Release /m

# 3. Install into GameData (copies exe + DLLs)
cmake.exe --install "C:\\<you>\\src\\openjk\\build-win" --config Release
```

Windows deps are bundled by OpenJK (SDL2, OpenAL, jpeg, png, zlib), so nothing
else to install.

What you get (64-bit Windows build, `-A x64`):

- `openjk.x86_64.exe` (MP client) / `openjk_sp.x86_64.exe` (SP)
- `jampgamex86_64.dll`, `cgamex86_64.dll`, `uix86_64.dll`, renderer DLLs.

Play:

```
C:\...\Jedi Academy\GameData\openjk.x86_64.exe    # MP
C:\...\Jedi Academy\GameData\openjk_sp.x86_64.exe # SP
```

Note: OpenJK suffixes binaries with the arch (`x86_64`), so a 64-bit build loads
`jampgamex86_64.dll` etc. — matching modules are produced by the same build, so it
"just works". (If you ever wanted to drop modules into the *retail* 32-bit
`jamp.exe`, you'd need a 32-bit build via `-A Win32`.)

If `cmake.exe` isn't on PATH, call VS's bundled one, or wrap calls in `cmd.exe /c`:

```sh
cmd.exe /c '"C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe" "C:\...\build-win\OpenJK.sln" /p:Configuration=Release /m'
```

---

## Phase 4 — The closed loop

```
edit code  ──►  cmake --build (WSL, ~/src/openjk)  ──►  openjkded.x86_64 (headless)
   ▲                                                        │  map/addbot/rcon/gdb/asan
   │                                                        ▼
   └── fix bugs ◄──────────────────────────────  observe behavior + logs

   └── when ready to play (occasionally):
        git push  ──►  pull into /mnt/c/.../openjk  ──►  cmake.exe + msbuild.exe (from WSL)
                                                          ──►  run openjk*.exe on Windows
```

Fast path is entirely in WSL; the Windows build is an occasional, scriptable step
invoked through interop.

---

## Caveats / gotchas

- **Assets are required** for both loops; nothing runs without `GameData/base`.
- `vm_game 0` (native module) is essential when testing your C++ changes; otherwise
  the engine may load a stale `.qvm`.
- Two checkouts (ext4 for WSL, NTFS for MSVC) means you must **sync via git** —
  don't build MSVC from the ext4 tree over `\\wsl$`.
- The 2003 repo's `.vcproj` files are irrelevant here; OpenJK's CMake generates a
  modern `.sln`/`.vcxproj` that modern MSBuild can build.
- `sv_pure 0` when using modified assets; otherwise the pure-server check may
  reject them.
- First Windows `cmake.exe` run must be able to find VS; install VS *before*
  generating, or pass `-G` with the exact installed version.
