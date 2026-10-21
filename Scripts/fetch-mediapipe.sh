#!/usr/bin/env bash
# Downloads the MediaPipe Tasks Vision xcframeworks into Vendor/MediaPipe (git-ignored: they are ~370 MB).
# Same binaries and checksums as Google's Swift package manifest for MediaPipeTasks 1.1.1.
# Usage: Scripts/fetch-mediapipe.sh [dest-dir]      (set ONLY=<zip name> to fetch a single archive)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${1:-$ROOT/Vendor/MediaPipe}"
BASE="https://dl.google.com/cpdc/20261013-213039"
VERSION="1.1.1"

# name | xcframework folder inside the zip | sha256 of the zip
ARCHIVES=(
  "MediaPipeTasksVision|MediaPipeTasksVision.xcframework|755390ce853b062536899f0729321156d4cdceb263aa92c4bf3b2dd05fe640e0"
  "MediaPipeTasksCommon|MediaPipeTasksCommon.xcframework|25690f3005c0405a7f27b6d273b4db241811d00fbb01c54004057ee1d0e983d8"
  "MediaPipeTaskGraphs|MediaPipeTaskGraphs_library.xcframework|e4d88ed65c101764ef90281a411b9942f369e48673d448eff1f934e1f68d9633"
)

mkdir -p "$DEST"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

for entry in "${ARCHIVES[@]}"; do
  IFS='|' read -r name framework checksum <<<"$entry"
  if [[ -n "${ONLY:-}" && "$ONLY" != "$name" ]]; then continue; fi
  if [[ -d "$DEST/$framework" ]]; then echo "$framework already present"; continue; fi
  zip="$WORK/$name.zip"
  echo "Downloading $name-$VERSION ..."
  curl --fail --location --silent --show-error "$BASE/$name-$VERSION.xcframework.zip" --output "$zip"
  actual="$(shasum -a 256 "$zip" | cut -d' ' -f1)"
  if [[ "$actual" != "$checksum" ]]; then
    echo "Checksum mismatch for $name: expected $checksum, got $actual" >&2
    exit 1
  fi
  unzip -q "$zip" -d "$WORK/$name"
  mv "$WORK/$name/$framework" "$DEST/$framework"
  echo "Installed $framework"
done
