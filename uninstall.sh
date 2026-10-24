#!/usr/bin/env bash
# Revert the TagosLabs SN65DSI86 bridge installer: restore the resource
# partition from the backup and remove the 4 modules.
# Usage: sudo ./uninstall.sh [--dry-run] [--yes] [--backup DIR]
set -euo pipefail
MODULES=(tagos_auxbus drm_dp_aux_bus panel-edp ti-sn65dsi86)
BACKUP_ROOT="/var/backups/tagos-bridge"
STATE_FILE="/var/lib/tagos-bridge/installed"
MODLOAD_CONF="/etc/modules-load.d/tagos-sn65dsi86.conf"
DRY_RUN=0; ASSUME_YES=0; BK=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run|-n) DRY_RUN=1 ;; --yes|-y) ASSUME_YES=1 ;;
    --backup) BK="${2:?}"; BK_FROM_ARG=1; shift ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac; shift
done
say() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }
run() { if [ "$DRY_RUN" = 1 ]; then printf '[dry-run] %s\n' "$*"; else "$@"; fi; }
ask_yn() { [ "$ASSUME_YES" = 1 ] && return 0; local a=""; [ -r /dev/tty ] || return 1
  printf '%s [y/N] ' "$1" >/dev/tty; read -r a </dev/tty || a=""; [[ "$a" =~ ^[Yy] ]]; }
[ "$(id -u)" = 0 ] || [ "$DRY_RUN" = 1 ] || die "Run as root: sudo ./uninstall.sh"

if [ -z "$BK" ]; then
  if [ -f "$STATE_FILE" ]; then BK="$(cat "$STATE_FILE")"
  else BK="$(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort | head -n1 || true)"; fi
fi
# The FIRST backup is the original stock partition; prefer it over re-install backups.
FIRST="$(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort | head -n1 || true)"
[ -n "$FIRST" ] && [ -z "${BK_FROM_ARG:-}" ] && BK="$FIRST"
[ -n "$BK" ] && [ -f "$BK/resource-backup.img" ] || die "No backup found in $BACKUP_ROOT. It looks like the screen adapter was never installed on this computer, so there is nothing to undo."
DEV="$(sed -n 's/^device=//p' "$BK/info" 2>/dev/null)"; DEV="${DEV:-$(readlink -f /dev/disk/by-partlabel/resource)}"
[ -b "$DEV" ] || [ "$DRY_RUN" = 1 ] || die "Resource partition $DEV not found."
(cd "$BK" && sha256sum -c --quiet resource-backup.img.sha256) || [ "$DRY_RUN" = 1 ] || die "Backup $BK is corrupted."
echo "Restore $BK/resource-backup.img -> $DEV and remove modules ${MODULES[*]}"
[ "$DRY_RUN" = 1 ] || ask_yn "Continue?" || die "Aborted."

say "Restoring resource partition"
run dd if="$BK/resource-backup.img" of="$DEV" bs=1M conv=fsync status=none
run sync
if [ "$DRY_RUN" = 0 ]; then cmp -s "$BK/resource-backup.img" "$DEV" || die "Restore verification failed! Re-run uninstall or restore from a PC (see README)."; fi
say "Removing modules"
KREL="$(uname -r)"
for m in "${MODULES[@]}"; do run rm -f "/lib/modules/$KREL/extra/$m.ko"; done
run rm -f "$MODLOAD_CONF" "$STATE_FILE"
run depmod -a "$KREL"
echo "Done. Backups are kept in $BACKUP_ROOT."
[ "$DRY_RUN" = 1 ] && exit 0
if ask_yn "Reboot now?"; then sync; systemctl reboot || reboot; else echo "Reboot later: sudo reboot"; fi
