#!/usr/bin/env bash
# TagosLabs screen adapter installer (SN65DSI86 bridge, NanoPi M6).
# Usage:  sudo bash tagos-bridge-installer.run [--dry-run] [--yes]
#         sudo bash tagos-bridge-installer.run --uninstall [--dry-run] [--yes]
# Self-contained: no internet needed. Needs only bash, coreutils, tar, gzip.
set -euo pipefail
PAYLOAD_SHA256="@PAYLOAD_SHA256@"
SELF="${BASH_SOURCE[0]:-$0}"
die() { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

MODE=install; ARGS=()
for a in "$@"; do
  case "$a" in
    --uninstall) MODE=uninstall ;;
    --dry-run|-n|--yes|-y) ARGS+=("$a") ;;
    -h|--help) sed -n '2,5p' "$SELF"; exit 0 ;;
    *) die "Unknown option: $a (use --help)" ;;
  esac
done
DRY=0; for a in "${ARGS[@]+"${ARGS[@]}"}"; do case "$a" in --dry-run|-n) DRY=1;; esac; done
if [ "$(id -u)" != 0 ] && [ "$DRY" = 0 ]; then
  die "Please run it with sudo:   sudo bash $SELF"
fi
[ -f "$SELF" ] || die "Cannot read the installer file. Run it as:  sudo bash /path/to/tagos-bridge-installer.run"
for t in tar gzip sha256sum tail mktemp; do command -v "$t" >/dev/null || die "Missing system tool: $t"; done

TMP="$(mktemp -d /tmp/tagos-bridge.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
LINE="$(grep -an '^__TAGOS_PAYLOAD_BELOW__$' "$SELF" | tail -n1 | cut -d: -f1)"
[ -n "$LINE" ] || die "The installer file is damaged. Please download it again."
tail -n +"$((LINE + 1))" "$SELF" > "$TMP/payload.tar.gz"
echo "Checking the installer file..."
echo "$PAYLOAD_SHA256  $TMP/payload.tar.gz" | sha256sum -c --quiet - >/dev/null 2>&1 \
  || die "The installer file is damaged or incomplete (checksum mismatch). Please download it again. Nothing was changed."
tar -xzf "$TMP/payload.tar.gz" -C "$TMP" || die "Could not unpack the installer. Please download it again."
bash "$TMP/pkg/$MODE.sh" "${ARGS[@]+"${ARGS[@]}"}"
exit $?
# shellcheck disable=SC2317
__TAGOS_PAYLOAD_BELOW__
