#!/usr/bin/env bash
# Builds tagos-bridge-installer.run from install.sh, uninstall.sh, payload/
set -euo pipefail
cd "$(dirname "$0")"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir "$T/pkg"; cp -a install.sh uninstall.sh payload "$T/pkg/"
tar -czf "$T/p.tgz" --owner=0 --group=0 -C "$T" pkg
S="$(sha256sum "$T/p.tgz" | cut -d' ' -f1)"
sed "s/@PAYLOAD_SHA256@/$S/" run-header.sh > tagos-bridge-installer.run
cat "$T/p.tgz" >> tagos-bridge-installer.run
chmod +x tagos-bridge-installer.run
sha256sum tagos-bridge-installer.run > tagos-bridge-installer.run.sha256
echo "built, payload sha256 $S"
