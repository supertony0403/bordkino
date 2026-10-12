#!/usr/bin/env bash
# Verifies the newest Bordkino .deb: rootless paths, arm64-only binaries,
# embedded entitlements, valid Info.plists and bundled resources.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LDID="${THEOS:-$HOME/theos}/toolchain/linux/iphone/bin/ldid"
DEB="$(ls -t "$ROOT"/packages/*.deb 2>/dev/null | head -1 || true)"

fail() { echo "FEHLER: $*" >&2; exit 1; }
[ -n "$DEB" ] || fail "keine .deb in packages/ gefunden"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
(cd "$WORK" && ar x "$DEB")
mkdir -p "$WORK/data" "$WORK/control"
tar -xf "$WORK"/data.tar.* -C "$WORK/data"
tar -xf "$WORK"/control.tar.* -C "$WORK/control"

grep -q '^Architecture: iphoneos-arm64$' "$WORK/control/control" || fail "control: Architecture ist nicht iphoneos-arm64"
for s in postinst postrm; do
  [ -x "$WORK/control/$s" ] || fail "Paketskript $s fehlt oder ist nicht ausführbar"
done

check_app() {
  local name="$1" bundle_id="$2" entitlement="$3" role="$4"
  local app="$WORK/data/var/jb/Applications/$name.app"
  [ -d "$app" ] || fail "$name.app liegt nicht unter /var/jb/Applications"
  local bin="$app/$name"
  [ -f "$bin" ] || fail "$name: Binärdatei fehlt"
  local arch; arch="$(file -b "$bin")"
  [[ "$arch" == *arm64* ]] || fail "$name: keine arm64-Binärdatei ($arch)"
  [[ "$arch" != *arm64e* ]] || fail "$name: enthält arm64e (alte ABI von clang 11)"
  local ents; ents="$("$LDID" -e "$bin")"
  for key in "$entitlement" com.apple.private.security.no-container platform-application; do
    grep -q "<key>$key</key>" <<<"$ents" || fail "$name: Entitlement $key fehlt"
  done
  python3 -I - "$app/Info.plist" "$bundle_id" "$role" <<'PY' || fail "$name: Info.plist ungültig"
import plistlib, sys
p = plistlib.load(open(sys.argv[1], 'rb'))
assert p['CFBundleIdentifier'] == sys.argv[2], p['CFBundleIdentifier']
roles = p['UIApplicationSceneManifest']['UISceneConfigurations']
assert sys.argv[3] in roles, list(roles)
assert 'UIWindowSceneSessionRoleApplication' in roles
assert 'audio' in p['UIBackgroundModes']
assert p['NSLocationWhenInUseUsageDescription']
if sys.argv[2].endswith('.navi'):
    assert p.get('CPSupportsInstrumentClusterNavigationScene') is True
    assert roles['CPTemplateApplicationInstrumentClusterSceneSessionRoleApplication'][0]['UISceneDelegateClassName'] == 'BKClusterSceneDelegate'
PY
  for f in extractor.js AppIcon60x60@2x.png AppIcon60x60@3x.png; do
    [ -f "$app/$f" ] || fail "$name: $f fehlt im Bündel"
  done
  echo "  $name.app ok ($bundle_id)"
}

echo "Prüfe $(basename "$DEB")"
check_app Bordkino de.benzsw.bordkino SBStarkCapable UIWindowSceneSessionRoleCarPlay
check_app BordkinoNavi de.benzsw.bordkino.navi com.apple.developer.carplay-maps CPTemplateApplicationSceneSessionRoleApplication
echo OK
