#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# build-server.sh
#
# Build the Linux dedicated server (openjkded.x86_64) and the MP server-side
# game module (jampgamex86_64.so) natively in WSL for the headless test loop.
#
# Usage:  ./scripts/build-server.sh
# ---------------------------------------------------------------------------

# ---- CONFIG (edit if paths change) ----------------------------------------
SRC="/home/kitesh/projects/jedy_academy/jedi_academy"   # WSL source of truth
BUILD="$SRC/build"
# ---------------------------------------------------------------------------

if [ ! -f "$SRC/CMakeLists.txt" ]; then
    echo "ERROR: source dir not found: $SRC" >&2
    exit 1
fi

cd "$SRC"

echo "==> Configuring (Linux, server-only, RelWithDebInfo)"
cmake -B "$BUILD" -S "$SRC" -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DBuildMPEngine=OFF -DBuildMPRdVanilla=OFF -DBuildMPRend2=OFF \
    -DBuildMPCGame=OFF -DBuildMPUI=OFF \
    -DBuildSPEngine=OFF -DBuildSPGame=OFF -DBuildSPRdVanilla=OFF \
    -DBuildJK2SPEngine=OFF -DBuildJK2SPGame=OFF -DBuildJK2SPRdVanilla=OFF

echo "==> Building"
cmake --build "$BUILD" -j"$(nproc)"

echo
echo "Done. Binaries:"
echo "  $BUILD/openjkded.x86_64"
echo "  $BUILD/jampgamex86_64.so"
