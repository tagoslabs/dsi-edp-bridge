#!/usr/bin/env bash
# TagosLabs SN65DSI86 DSI->eDP bridge installer for FriendlyElec NanoPi M6
# (FriendlyElec Debian, kernel 6.1.141 #47). Replicates the verified working
# setup of 2026-10-22:
#   1) 4 kernel modules -> /lib/modules/6.1.141/extra + depmod
#   2) resource partition (PARTLABEL "resource", 16 MiB, on the boot microSD)
#      overwritten with resource-nologo-16M.img via dd conv=fsync, then
#      read back and sha256-verified.
# Usage:
#   sudo ./install.sh [--dry-run] [--yes]                     (from extracted tarball)
set -euo pipefail

VERSION="1.0.0"; export VERSION

KVER_REQUIRED="6.1.141"
VERMAGIC_REQUIRED="6.1.141 SMP mod_unload modversions aarch64"
MODULES=(tagos_auxbus drm_dp_aux_bus panel-edp ti-sn65dsi86)   # load order
RES_IMG="resource-nologo-16M.img"
RES_SHA256="865dc1ed663226ad9124d4760138197da948e4decd13620f87971fa0fa3d0ec0"
RES_SIZE=16777216
BACKUP_ROOT="/var/backups/tagos-bridge"
MODLOAD_CONF="/etc/modules-load.d/tagos-sn65dsi86.conf"
STATE_FILE="/var/lib/tagos-bridge/installed"

DRY_RUN=0; ASSUME_YES=0
for a in "$@"; do
  case "$a" in
    --dry-run|-n) DRY_RUN=1 ;;
    --yes|-y) ASSUME_YES=1 ;;
    -h|--help) sed -n '2,13p' "$0" 2>/dev/null || true; exit 0 ;;
    *) echo "Unknown option: $a" >&2; exit 2 ;;
  esac
done

say()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWARN:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }
run()  { if [ "$DRY_RUN" = 1 ]; then printf '[dry-run] %s\n' "$*"; else "$@"; fi; }

ask_yn() {  # ask_yn "question" -> 0 if yes; reads /dev/tty so it works when stdin is not a terminal
  [ "$ASSUME_YES" = 1 ] && return 0
  local ans=""
  if [ -r /dev/tty ] && { true </dev/tty; } 2>/dev/null; then
    printf '%s [y/N] ' "$1" >/dev/tty; read -r ans </dev/tty || ans=""
  else
    warn "No terminal available; answering 'no' to: $1"; return 1
  fi
  [[ "$ans" =~ ^[Yy]([Ee][Ss])?$ ]]
}

# ---------- 1. checks ----------
[ "$(id -u)" = 0 ] || [ "$DRY_RUN" = 1 ] || die "Run as root: sudo ./install.sh  "
[ "$(id -u)" = 0 ] || warn "Not root - continuing only because --dry-run."

MODEL="$( { tr -d '\0' </proc/device-tree/model; } 2>/dev/null || echo unknown)"
COMPAT="$( { tr '\0' ' ' </proc/device-tree/compatible; } 2>/dev/null || echo unknown)"
KREL="$(uname -r)"
say "Board: $MODEL"
say "Kernel: $KREL ($(uname -v))"

check_fail() { if [ "$DRY_RUN" = 1 ]; then warn "$* (ignored in --dry-run)"; else die "$*"; fi; }
case "$MODEL" in *"NanoPi M6"*) ;; *) check_fail "This package supports only 'FriendlyElec NanoPi M6'. Detected: '$MODEL'." ;; esac
case "$COMPAT" in *rk3588s*|*rk3588*) ;; *) check_fail "SoC is not RK3588/RK3588S (compatible: $COMPAT)." ;; esac
[ "$KREL" = "$KVER_REQUIRED" ] || check_fail "Kernel mismatch: running '$KREL', modules are built for '$KVER_REQUIRED' (vermagic '$VERMAGIC_REQUIRED'). Use the stock FriendlyElec Debian image with kernel $KVER_REQUIRED, or ask TagosLabs for a build for your kernel. Nothing was changed."
[ "$(uname -m)" = aarch64 ] || check_fail "Architecture is $(uname -m), need aarch64."
for t in dd sha256sum depmod tar cmp blockdev readlink; do command -v "$t" >/dev/null || check_fail "Missing tool: $t"; done

# ---------- 2. payload ----------
SELF_DIR=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; fi
if [ -n "$SELF_DIR" ] && [ -f "$SELF_DIR/payload/SHA256SUMS" ]; then
  PAYLOAD="$SELF_DIR/payload"; say "Using local payload: $PAYLOAD"
else
  die "Installer files are missing. Please download tagos-bridge-installer.run again."
fi
(cd "$PAYLOAD" && sha256sum -c --quiet SHA256SUMS) || die "Payload file checksums failed."
echo "$RES_SHA256  $PAYLOAD/$RES_IMG" | sha256sum -c --quiet - || die "Resource image is not the verified 2026-10-22 image."
for m in "${MODULES[@]}"; do
  vm="$(tr '\0' '\n' <"$PAYLOAD/mods/$m.ko" | sed -n 's/^vermagic=//p' | head -n1 | sed 's/ *$//')"
  [ "$vm" = "$VERMAGIC_REQUIRED" ] || die "$m.ko vermagic '$vm' != '$VERMAGIC_REQUIRED'."
done

# ---------- 3. find resource partition ----------
RES_DEV=""
if [ -e /dev/disk/by-partlabel/resource ]; then RES_DEV="$(readlink -f /dev/disk/by-partlabel/resource)"; fi
if [ -z "$RES_DEV" ]; then check_fail "No partition with PARTLABEL 'resource' found (expected /dev/mmcblk0p4 on the boot microSD)."; RES_DEV=/dev/mmcblk0p4; fi
N="$( (find /dev/disk/by-partlabel -name resource 2>/dev/null || true) | wc -l)"
[ "$N" -le 1 ] || check_fail "More than one 'resource' partition found (eMMC + SD?). Remove the extra media and retry."
case "$RES_DEV" in /dev/mmcblk*p*) ;; *) check_fail "'resource' partition is $RES_DEV, expected an MMC/SD partition (e.g. /dev/mmcblk0p4).";; esac
if [ -b "$RES_DEV" ]; then
  SZ="$(blockdev --getsize64 "$RES_DEV")"
  [ "$SZ" = "$RES_SIZE" ] || check_fail "$RES_DEV is $SZ bytes, expected $RES_SIZE (16 MiB)."
  grep -q "^$RES_DEV " /proc/mounts && check_fail "$RES_DEV is mounted; refusing."
fi
say "Resource partition: $RES_DEV"

# ---------- 4. plan ----------
TS="$(date +%Y%m%d-%H%M%S)"; BK="$BACKUP_ROOT/$TS"; EXTRA="/lib/modules/$KREL/extra"
cat <<PLAN

Setting up the TagosLabs screen adapter. This takes about a minute:
  1. Back up $RES_DEV and existing modules to $BK
  2. Install ${MODULES[*]} (.ko) into $EXTRA and run depmod
  3. Write $MODLOAD_CONF (module load order)
  4. Write the bridge device tree image to $RES_DEV (dd, verified by sha256)
PLAN
[ "$DRY_RUN" = 1 ] && echo "  (DRY RUN - nothing will be changed)"
echo

# ---------- 5. backup ----------
say "Backing up to $BK"
run mkdir -p "$BK"
run dd if="$RES_DEV" of="$BK/resource-backup.img" bs=1M status=none
if [ "$DRY_RUN" = 0 ]; then
  ( cd "$BK" && sha256sum resource-backup.img > resource-backup.img.sha256 )
  cmp -s "$BK/resource-backup.img" "$RES_DEV" || die "Backup verification failed. Nothing was changed."
  printf 'device=%s\nkernel=%s\nmodel=%s\ndate=%s\n' "$RES_DEV" "$KREL" "$MODEL" "$TS" > "$BK/info"
  if cmp -s "$BK/resource-backup.img" "$PAYLOAD/$RES_IMG"; then warn "Resource partition already contains the bridge DT (re-install)."; fi
  mkdir -p "$BK/old-extra"; for m in "${MODULES[@]}"; do [ -f "$EXTRA/$m.ko" ] && cp -a "$EXTRA/$m.ko" "$BK/old-extra/"; done; true
fi

# ---------- 6. modules ----------
say "Installing kernel modules into $EXTRA"
run mkdir -p "$EXTRA"
for m in "${MODULES[@]}"; do run install -m 0644 "$PAYLOAD/mods/$m.ko" "$EXTRA/$m.ko"; done
run depmod -a "$KREL"
if [ "$DRY_RUN" = 1 ]; then echo "[dry-run] write $MODLOAD_CONF: ${MODULES[*]}"
else printf '# TagosLabs SN65DSI86 bridge (installed %s)\n' "$TS" > "$MODLOAD_CONF"; printf '%s\n' "${MODULES[@]}" >> "$MODLOAD_CONF"; fi

# ---------- 7. DTB (resource partition), exactly as the working setup ----------
say "Writing device tree image to $RES_DEV"
run dd if="$PAYLOAD/$RES_IMG" of="$RES_DEV" bs=1M conv=fsync status=none
run sync
if [ "$DRY_RUN" = 0 ]; then
  blockdev --flushbufs "$RES_DEV" 2>/dev/null || true
  GOT="$(dd if="$RES_DEV" bs=1M iflag=direct status=none | sha256sum | cut -d' ' -f1)"
  if [ "$GOT" != "$RES_SHA256" ]; then
    warn "Verification FAILED ($GOT). Restoring backup..."
    dd if="$BK/resource-backup.img" of="$RES_DEV" bs=1M conv=fsync status=none; sync
    die "Could not write the resource partition. Original restored. Do NOT reboot until you check it."
  fi
  mkdir -p "$(dirname "$STATE_FILE")"; echo "$BK" > "$STATE_FILE"
else echo "[dry-run] verify sha256($RES_DEV) == $RES_SHA256"; fi

# ---------- 8. summary ----------
cat <<DONE

============================================================
 DONE! The screen adapter is installed.
------------------------------------------------------------
 Modules : $EXTRA/{$(IFS=,; echo "${MODULES[*]}")}.ko
 DT      : $RES_DEV  (sha256 $RES_SHA256)
 Backup  : $BK
 Revert  : sudo bash tagos-bridge-installer.run --uninstall  (or: dd if=$BK/resource-backup.img of=$RES_DEV bs=1M conv=fsync)
 Restart the computer and the laptop screen will turn on.
 NOTE: HDMI stays usable; the old DSI1 (YX35) panel output is disabled.
 NOTE: a kernel update (apt) will break the modules - do not upgrade the kernel.
============================================================
DONE
[ "$DRY_RUN" = 1 ] && { echo "Dry run finished - nothing was changed."; exit 0; }
if ask_yn "Restart now? Type y and press Enter"; then say "Rebooting..."; sync; systemctl reboot || reboot
else echo "Reboot later with: sudo reboot"; fi
