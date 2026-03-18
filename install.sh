#!/usr/bin/env bash
set -euo pipefail

PREFIX="${PREFIX:-/usr/local}"
DEST="${PREFIX}/bin/slack-thread-dump"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "${PREFIX}/bin"
cp "${SCRIPT_DIR}/slack-thread-dump.sh" "${DEST}"
chmod +x "${DEST}"

echo "Installed slack-thread-dump to ${DEST}"
echo "Make sure ${PREFIX}/bin is on your PATH."
