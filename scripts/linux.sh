#!/bin/sh
# Builds, tests, or opens a shell in Linux (Docker, swift:6.2) with this checkout mounted at
# /src and a named volume as the SwiftPM scratch path, so the macOS .build is never touched.
#
#   ./scripts/linux.sh build [swift build args...]
#   ./scripts/linux.sh test  [swift test args...]
#   ./scripts/linux.sh shell
#
# Environment:
#   MOCKINGBIRD_LINUX_IMAGE   container image          (default swift:6.2)
#   MOCKINGBIRD_LINUX_VOLUME  scratch-path volume name (default mockingbird-linux-build)
set -eu

usage() {
    echo "usage: $0 <build|test|shell> [args...]" >&2
    exit 2
}

[ $# -ge 1 ] || usage
command=$1
shift

image=${MOCKINGBIRD_LINUX_IMAGE:-swift:6.2}
volume=${MOCKINGBIRD_LINUX_VOLUME:-mockingbird-linux-build}
root=$(cd "$(dirname "$0")/.." && pwd)

run() {
    docker run --rm "$@"
}

case "$command" in
    build)
        run -v "$root":/src -v "$volume":/build -w /src "$image" \
            swift build --scratch-path /build "$@"
        ;;
    test)
        # BuiltProducts locates mockingbird next to the test bundle; point it at the
        # products directory explicitly as well, in case dladdr resolves elsewhere.
        if [ $# -gt 0 ]; then
            run -v "$root":/src -v "$volume":/build -w /src \
                -e MOCKINGBIRD_BIN_DIR=/build/debug "$image" \
                swift test --scratch-path /build "$@"
        else
            # Same two passes as CI: Core's CPU-bound suites run apart from the
            # wall-clock-sensitive process and audio tests.
            run -v "$root":/src -v "$volume":/build -w /src \
                -e MOCKINGBIRD_BIN_DIR=/build/debug "$image" \
                sh -c 'swift test --scratch-path /build --filter MockingBirdCoreTests &&
                       swift test --scratch-path /build --skip MockingBirdCoreTests'
        fi
        ;;
    shell)
        run -it -v "$root":/src -v "$volume":/build -w /src "$image" bash
        ;;
    *)
        usage
        ;;
esac
