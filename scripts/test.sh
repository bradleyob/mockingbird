#!/bin/sh
# Runs `swift test`, adding the framework/rpath flags Swift Testing needs when only the
# Command Line Tools are installed (no Xcode). All arguments are forwarded to `swift test`.
set -eu

if [ "$(uname)" = "Darwin" ] && ! xcodebuild -version >/dev/null 2>&1; then
    CLT=/Library/Developer/CommandLineTools/Library/Developer
    exec swift test \
        -Xswiftc -F"$CLT/Frameworks" \
        -Xlinker -F"$CLT/Frameworks" \
        -Xlinker -rpath -Xlinker "$CLT/Frameworks" \
        -Xlinker -rpath -Xlinker "$CLT/usr/lib" \
        "$@"
fi

exec swift test "$@"
