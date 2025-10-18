#!/bin/bash
cd "$(dirname "$0")"
source ./script/setup.sh

./build-debug.sh -Xswiftc -warnings-as-errors
./run-swift-test.sh

./.debug/hyprspace -h > /dev/null
./.debug/hyprspace --help > /dev/null
./.debug/hyprspace -v | grep -q "0.0.0-SNAPSHOT SNAPSHOT"
./.debug/hyprspace --version | grep -q "0.0.0-SNAPSHOT SNAPSHOT"

./format.sh
./generate.sh --all
./script/check-uncommitted-files.sh

echo
echo "All tests have passed successfully"
