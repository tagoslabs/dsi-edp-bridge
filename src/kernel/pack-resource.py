#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Check or update a FriendlyElec Rockchip resource image (RSCE).

The layout matches U-Boot tools/rockchip/resource_tool.c: a 512-byte header,
then one 512-byte "ENTR" record per file. Each record stores a SHA-1 of the
file bytes (hash_size 20).

  pack-resource.py --check payload/resource-nologo-16M.img
  pack-resource.py --replace-dtb rebuilt.dtb -o /tmp/resource-rebuilt.img \\
      payload/resource-nologo-16M.img

--replace-dtb writes a new image. It does not modify the input. The
replacement must be the same size as the rk3588-nanopi6-rev0a.dtb slot,
because the other files are packed at fixed offsets.
"""

import argparse
import hashlib
import struct
import sys
from pathlib import Path

ENTRY = 512
TAG = b"ENTR"
NAME_LEN = 220
HASH_OFF = 0xE0
HASH_SIZE_OFF = 0x100
OFF_OFF = 0x104
SIZE_OFF = 0x108
TARGET = "rk3588-nanopi6-rev0a.dtb"


def load(path: Path) -> bytes:
    data = path.read_bytes()
    if data[:4] != b"RSCE":
        sys.exit(f"{path} is not an RSCE resource image")
    return data


def entry_count(data: bytes) -> int:
    return struct.unpack_from("<I", data, 0x0C)[0]


def read_entry(data: bytes, index: int):
    base = ENTRY * (1 + index)
    ent = data[base : base + ENTRY]
    if ent[:4] != TAG:
        sys.exit(f"entry {index} is not ENTR")
    name = ent[4 : 4 + NAME_LEN].split(b"\0", 1)[0].decode()
    hash_size, blocks, size = struct.unpack_from("<III", ent, HASH_SIZE_OFF)
    stored = ent[HASH_OFF : HASH_OFF + hash_size]
    blob = data[blocks * ENTRY : blocks * ENTRY + size]
    return {
        "index": index,
        "base": base,
        "name": name,
        "hash_size": hash_size,
        "blocks": blocks,
        "size": size,
        "stored": stored,
        "blob": blob,
    }


def check(data: bytes) -> int:
    bad = 0
    for i in range(entry_count(data)):
        ent = read_entry(data, i)
        digest = hashlib.sha1(ent["blob"]).digest()
        ok = ent["hash_size"] == 20 and ent["stored"] == digest
        mark = "ok" if ok else "MISMATCH"
        if not ok:
            bad += 1
        print(f"{mark:8} {ent['name']:32} {ent['size']:8}  {digest.hex()}")
    return bad


def replace_dtb(data: bytearray, dtb: bytes) -> None:
    found = None
    for i in range(entry_count(data)):
        ent = read_entry(data, i)
        if ent["name"] == TARGET:
            found = ent
            break
    if found is None:
        sys.exit(f"{TARGET} is not in this image")
    if len(dtb) != found["size"]:
        sys.exit(
            f"{TARGET} is {found['size']} bytes in the image; "
            f"the replacement is {len(dtb)}. Refusing to shift the other files."
        )
    start = found["blocks"] * ENTRY
    data[start : start + len(dtb)] = dtb
    digest = hashlib.sha1(dtb).digest()
    base = found["base"]
    data[base + HASH_OFF : base + HASH_OFF + 20] = digest
    data[base + HASH_OFF + 20 : base + HASH_OFF + 32] = b"\0" * 12
    struct.pack_into("<I", data, base + HASH_SIZE_OFF, 20)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("image", type=Path)
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--replace-dtb", type=Path, metavar="DTB")
    ap.add_argument("-o", "--output", type=Path)
    args = ap.parse_args()
    if args.check == bool(args.replace_dtb):
        ap.error("pass exactly one of --check or --replace-dtb")
    data = load(args.image)
    if args.check:
        bad = check(data)
        sys.exit(1 if bad else 0)
    if args.output is None:
        ap.error("--replace-dtb needs -o")
    if args.output.resolve() == args.image.resolve():
        sys.exit("refusing to overwrite the input image")
    buf = bytearray(data)
    replace_dtb(buf, args.replace_dtb.read_bytes())
    args.output.write_bytes(buf)
    print(f"wrote {args.output}")


if __name__ == "__main__":
    main()
