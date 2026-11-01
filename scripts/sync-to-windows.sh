#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# sync-to-windows.sh
#
# Copy the latest OpenJK source from WSL (ext4, source of truth) to the
# Windows (NTFS) tree so it can be built with MSVC.
#
# One-directional: the WSL repo is authoritative. Uncommitted changes ARE
# included (the working tree is copied, not just committed state).
#
# Usage:  ./scripts/sync-to-windows.sh
# ---------------------------------------------------------------------------

# ---- CONFIG (edit if paths change) ----------------------------------------
WSL_SRC="/home/kitesh/projects/jedy_academy/jedi_academy"   # WSL source of truth
WIN_SRC="/mnt/e/Games/JA_mod/src/openjk"                    # E:\Games\JA_mod\src\openjk
# ---------------------------------------------------------------------------

if [ ! -f "$WSL_SRC/CMakeLists.txt" ]; then
    echo "ERROR: source dir not found (or missing CMakeLists.txt): $WSL_SRC" >&2
    exit 1
fi

mkdir -p "$WIN_SRC"

echo "Syncing: $WSL_SRC -> $WIN_SRC"
rsync -rlt --delete \
    --exclude='.git/' \
    --exclude='build/' \
    --exclude='build-*/' \
    "$WSL_SRC/" "$WIN_SRC/"

echo "Done. Windows source tree: $WIN_SRC"
