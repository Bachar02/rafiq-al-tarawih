#!/usr/bin/env bash
# Check or re-render the golden screenshots on Linux, the platform CI compares
# them on (see test/golden/README.md). Needs Docker. Run from anywhere:
#
#   mobile/tool/goldens.sh check    # compare; diffs land in test/golden/failures/
#   mobile/tool/goldens.sh update   # re-render test/golden/screens/*.png
#
# The working copy is mounted read-only and copied inside the container, so the
# host's .dart_tool and build folders are never touched.
set -euo pipefail

case "${1:-check}" in
  check) flags="" ;;
  update) flags="--update-goldens" ;;
  *) echo "usage: $0 check|update" >&2; exit 2 ;;
esac

# Keep in step with flutter-version in .github/workflows/ci.yml.
image="ghcr.io/cirruslabs/flutter:3.19.5"

mobile="$(cd "$(dirname "$0")/.." && pwd)"
if command -v cygpath >/dev/null 2>&1; then # Git Bash on Windows
  mobile="$(cygpath -m "$mobile")"
  export MSYS_NO_PATHCONV=1
fi

docker run --rm --platform linux/amd64 \
  -e FLAGS="$flags" -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" -e PUB_CACHE=/pub-cache \
  -v "$mobile:/src:ro" -v "$mobile/test/golden:/out" -v rafiq-pub-cache:/pub-cache \
  "$image" bash -euc '
    mkdir /work
    tar -C /src --exclude=./.dart_tool --exclude=./build --exclude=./android/.gradle \
      --exclude=./test/golden/failures -cf - . | tar -C /work -xf -
    cd /work
    flutter pub get >/dev/null
    status=0
    flutter test $FLAGS test/golden || status=$?
    rm -rf /out/failures
    if [ -d test/golden/failures ]; then cp -r test/golden/failures /out/; fi
    if [ -n "$FLAGS" ]; then rm -rf /out/screens && cp -r test/golden/screens /out/; fi
    chown -R "$HOST_UID:$HOST_GID" /out/screens /out/failures 2>/dev/null || true
    exit $status
  '
