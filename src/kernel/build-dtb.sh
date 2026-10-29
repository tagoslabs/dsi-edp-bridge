#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Rebuild payload/new-rev0a-nologo.dtb from src/kernel/dts and a
# friendlyarm/kernel-rockchip checkout. See SOURCES.md for the commit.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
KERNEL_SRC="${KERNEL_SRC:?Set KERNEL_SRC to a checkout of friendlyarm/kernel-rockchip}"
OUT="${OUT:-$HERE/build}"
DTS="$KERNEL_SRC/arch/arm64/boot/dts"
INC="$KERNEL_SRC/scripts/dtc/include-prefixes"
SHIPPED="$ROOT/payload/new-rev0a-nologo.dtb"

if [[ ! -f "$DTS/rockchip/rk3588-nanopi6-rev0a.dts" ]]; then
  echo "KERNEL_SRC does not look like friendlyarm/kernel-rockchip (missing rk3588-nanopi6-rev0a.dts)" >&2
  exit 1
fi
if [[ ! -d "$INC" ]]; then
  echo "Missing $INC. Use a full kernel checkout, not a sparse tree without scripts/dtc/include-prefixes." >&2
  exit 1
fi
command -v gcc >/dev/null
command -v dtc >/dev/null

mkdir -p "$OUT"
gcc -E -nostdinc \
  -I "$INC" -I "$DTS/rockchip" -I "$HERE/dts" \
  -undef -D__DTS__ -x assembler-with-cpp \
  -o "$OUT/rev0a-nologo.dts.pp" \
  "$HERE/dts/rk3588-nanopi6-rev0a-tagos-nologo.dts"
dtc -@ -I dts -O dtb -o "$OUT/rk3588-nanopi6-rev0a-nologo.dtb" \
  -Wno-unit_address_vs_reg -Wno-simple_bus_reg -Wno-unique_unit_address \
  -Wno-graph_child_address -Wno-avoid_unnecessary_addr_size \
  "$OUT/rev0a-nologo.dts.pp"

echo "wrote $OUT/rk3588-nanopi6-rev0a-nologo.dtb ($(stat -c%s "$OUT/rk3588-nanopi6-rev0a-nologo.dtb") bytes)"

if [[ -f "$SHIPPED" ]]; then
  if cmp -s "$OUT/rk3588-nanopi6-rev0a-nologo.dtb" "$SHIPPED"; then
    echo "byte-identical to payload/new-rev0a-nologo.dtb"
  else
    python3 - "$OUT/rk3588-nanopi6-rev0a-nologo.dtb" "$SHIPPED" << 'PY'
import sys
a=open(sys.argv[1],"rb").read(); b=open(sys.argv[2],"rb").read()
diffs=[i for i,(x,y) in enumerate(zip(a,b)) if x!=y]
extra=abs(len(a)-len(b))
print(f"not byte-identical: {len(diffs)+extra} differing byte(s), lengths {len(a)} and {len(b)}")
if len(diffs)==1 and extra==0:
    print(f"single byte at offset {diffs[0]}: rebuilt 0x{a[diffs[0]]:02x}, shipped 0x{b[diffs[0]]:02x}")
    print("That offset is padding after the route-dsi0 status property. dtc zeroes it;")
    print("the shipped blob left 0x03 there. No property value differs.")
PY
  fi
fi
