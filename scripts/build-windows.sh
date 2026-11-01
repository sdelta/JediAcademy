#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# build-windows.sh
#
# Configure + build the Windows SP build (x64, Release) with MSVC via WSL
# interop, then assemble the playable files into E:\Games\JA_mod.
#
# Run ./scripts/sync-to-windows.sh first if you changed code.
#
# Usage:  ./scripts/build-windows.sh
# ---------------------------------------------------------------------------

# ---- CONFIG (edit if paths change) ----------------------------------------
CMAKE_EXE="/mnt/c/Program Files (x86)/Microsoft Visual Studio/18/BuildTools/Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe"
WIN_ROOT="/mnt/e/Games/JA_mod"           # E:\Games\JA_mod (WSL view)
WIN_SRC="E:/Games/JA_mod/src/openjk"      # Windows-style path for cmake.exe
WIN_BUILD="E:/Games/JA_mod/build"         # Windows-style path for cmake.exe
CONFIG="Release"
JOBS="$(nproc)"

# WSL-style paths used for file copies
SRC_DIR="$WIN_ROOT/src/openjk"
BUILD_DIR="$WIN_ROOT/build"
# ---------------------------------------------------------------------------

if [ ! -f "$CMAKE_EXE" ]; then
    echo "ERROR: cmake.exe not found at: $CMAKE_EXE" >&2
    echo "       Is Visual Studio Build Tools installed?" >&2
    exit 1
fi
if [ ! -f "$SRC_DIR/CMakeLists.txt" ]; then
    echo "ERROR: source not staged at: $SRC_DIR" >&2
    echo "       Run ./scripts/sync-to-windows.sh first." >&2
    exit 1
fi

# Run from a Windows-visible cwd so cmake.exe is happy.
cd "$WIN_ROOT"

echo "==> Configuring (Visual Studio 18 2026, x64, SP-only)"
"$CMAKE_EXE" -S "$WIN_SRC" -B "$WIN_BUILD" -G "Visual Studio 18 2026" -A x64 \
    -DCMAKE_INSTALL_PREFIX="E:/Games/JA_mod" \
    -DBuildMPEngine=OFF -DBuildMPRdVanilla=OFF -DBuildMPDed=OFF \
    -DBuildMPGame=OFF -DBuildMPCGame=OFF -DBuildMPUI=OFF -DBuildMPRend2=OFF \
    -DBuildJK2SPEngine=OFF -DBuildJK2SPGame=OFF -DBuildJK2SPRdVanilla=OFF

echo "==> Building ($CONFIG)"
"$CMAKE_EXE" --build "$WIN_BUILD" --config "$CONFIG" --parallel "$JOBS"

echo "==> Assembling playable files into $WIN_ROOT"
cp -f "$BUILD_DIR/$CONFIG/openjk_sp.x86_64.exe"    "$WIN_ROOT/"
cp -f "$BUILD_DIR/$CONFIG/jagamex86_64.dll"        "$WIN_ROOT/"
cp -f "$BUILD_DIR/$CONFIG/rdsp-vanilla_x86_64.dll" "$WIN_ROOT/"
cp -f "$SRC_DIR/lib/SDL2/bin/x64/SDL2.dll"         "$WIN_ROOT/"
cp -f "$SRC_DIR/code/OpenAL32.dll"                 "$WIN_ROOT/"
cp -f "$SRC_DIR/code/EaxMan.dll"                   "$WIN_ROOT/"

echo
echo "Done. Playable SP build: $WIN_ROOT"
echo "Run: E:\\Games\\JA_mod\\openjk_sp.x86_64.exe"
