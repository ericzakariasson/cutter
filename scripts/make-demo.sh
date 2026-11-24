#!/bin/bash
# Draws the README's demo clip, docs/demo.gif.
#
#   ./scripts/make-demo.sh [--mp4 <file>] [--stills <directory>]
#
# The clip is drawn off-screen from the app's own placement and display-order code and
# its default shortcuts (Sources/CutterDemo), so run this again when either changes.
# Nothing is shown on or captured from the screen. --mp4 also writes an H.264 movie at
# twice the size; --stills writes PNGs of each step for a closer look.
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p docs
swift run -c release CutterDemo --gif docs/demo.gif "$@"
