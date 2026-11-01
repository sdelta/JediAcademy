#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# run-server.sh
#
# Launch the headless dedicated server for the test loop. Interact on stdin:
#   map mp/ffa3      # load a map
#   addbot Kyle 5    # spawn a bot
#   sv_cheats 1      # enable cheats
#   g_* <value>      # tweak gameplay cvars live
#   quit             # exit
#
# Requires a server build first: ./scripts/build-server.sh
#
# Usage:  ./scripts/run-server.sh
# ---------------------------------------------------------------------------

# ---- CONFIG (edit if paths change) ----------------------------------------
SRC="/home/kitesh/projects/jedy_academy/jedi_academy"
BUILD="$SRC/build"
JKA_ASSETS="/mnt/e/Steam/steamapps/common/Jedi Academy/GameData"   # retail base assets
HOMEPATH="$HOME/.openjk-test"                                      # writable configs/logs/saves
NET_PORT="29070"
# ---------------------------------------------------------------------------

if [ ! -x "$BUILD/openjkded.x86_64" ]; then
    echo "ERROR: server binary not found: $BUILD/openjkded.x86_64" >&2
    echo "       Run ./scripts/build-server.sh first." >&2
    exit 1
fi

mkdir -p "$HOMEPATH"

echo "Starting dedicated server (type 'quit' to exit)..."
"$BUILD/openjkded.x86_64" \
    +set dedicated 2 \
    +set fs_basepath "$JKA_ASSETS" \
    +set fs_homepath "$HOMEPATH" \
    +set sv_pure 0 \
    +set vm_game 0 \
    +set rconpassword test \
    +set net_port "$NET_PORT"
