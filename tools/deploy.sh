#!/usr/bin/env bash
# Installs the newest Bordkino .deb on a USB-connected iPhone (Dopamine, OpenSSH from Sileo).
# Usage: tools/deploy.sh [ssh-user]   (default user: mobile, uses sudo on the device)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEB="$(ls -t "$ROOT"/packages/*.deb 2>/dev/null | head -1 || true)"
USER_NAME="${1:-mobile}"
PORT=2222

[ -n "$DEB" ] || { echo "Keine .deb gefunden – erst 'make package FINALPACKAGE=1' ausführen."; exit 1; }
if ! idevice_id -l 2>/dev/null | grep -q .; then
  cat <<MSG
Kein iPhone per USB gefunden.
Alternative ohne Kabel: Die .deb aus dem GitHub-Release am iPhone in Safari laden
(https://github.com/supertony0403/bordkino/releases/latest) und mit Sileo oder Filza öffnen.
MSG
  exit 1
fi

iproxy "$PORT" 22 >/dev/null 2>&1 &
PROXY=$!
trap 'kill $PROXY 2>/dev/null || true' EXIT
sleep 1

NAME="$(basename "$DEB")"
echo "Kopiere $NAME aufs iPhone …"
scp -P "$PORT" -o StrictHostKeyChecking=accept-new "$DEB" "$USER_NAME@localhost:/var/mobile/Documents/$NAME"
echo "Installiere (Passwort des Benutzers $USER_NAME auf dem iPhone) …"
ssh -t -p "$PORT" -o StrictHostKeyChecking=accept-new "$USER_NAME@localhost" \
  "sudo dpkg -i /var/mobile/Documents/$NAME && rm /var/mobile/Documents/$NAME"
echo "Fertig. Bordkino und Bordkino Navi liegen jetzt auf dem Homescreen."
