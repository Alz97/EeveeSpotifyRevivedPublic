#!/usr/bin/env bash
# Build zxPluginsInject.dylib — LC-injection sideload-compat shim.
#
# Loaded before main() in the resigned Spotify binary (and any .appex still
# present) via ipapatch. Provides keychain redirection and app-group
# fallbacks for sideloaded builds at a layer the host app can't avoid.
#
# Output: packages/zxPluginsInject.dylib

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MOD_DIR="$REPO_DIR/modules/zxPluginsInject"

[ -n "${THEOS:-}" ] || { echo "THEOS env not set" >&2; exit 1; }
[ -d "$MOD_DIR" ] || { echo "modules/zxPluginsInject missing" >&2; exit 1; }

cd "$MOD_DIR"
[ "${1:-}" = "--clean" ] && make clean >/dev/null 2>&1 || true
make FINALPACKAGE=1 >/dev/null

DYLIB_OUT="$MOD_DIR/.theos/obj/zxPluginsInject.dylib"
[ -f "$DYLIB_OUT" ] || { echo "zxPluginsInject.dylib not produced" >&2; exit 1; }

mkdir -p "$REPO_DIR/packages"
cp "$DYLIB_OUT" "$REPO_DIR/packages/zxPluginsInject.dylib"
install_name_tool -id "@rpath/zxPluginsInject.dylib" \
    "$REPO_DIR/packages/zxPluginsInject.dylib" 2>/dev/null || true

echo "$REPO_DIR/packages/zxPluginsInject.dylib"
