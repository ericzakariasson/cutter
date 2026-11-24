#!/bin/bash
# Runs the unit tests.
#
# The tests use Swift Testing. With full Xcode, plain `swift test` finds it. With only the
# Command Line Tools the framework is installed but not on the default search paths, so
# this script adds them.
set -euo pipefail

cd "$(dirname "$0")/.."

developer_dir="$(xcode-select -p)"
flags=()
if [ ! -d "$developer_dir/Platforms/MacOSX.platform" ]; then
    frameworks="$developer_dir/Library/Developer/Frameworks"
    flags=(
        -Xswiftc -F"$frameworks"
        -Xswiftc -plugin-path -Xswiftc "$developer_dir/usr/lib/swift/host/plugins/testing"
        -Xlinker -F"$frameworks"
        -Xlinker -rpath -Xlinker "$frameworks"
        -Xlinker -rpath -Xlinker "$developer_dir/Library/Developer/usr/lib"
    )
fi

swift test ${flags[@]+"${flags[@]}"} "$@"
