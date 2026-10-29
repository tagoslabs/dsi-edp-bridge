# Corresponding source for the shipped binaries

The files under `payload/` are what the installer copies onto the board. This
page is the map from each of those binaries back to source. Nothing in
`payload/` was changed.

Kernel tree used below:

- Repository: https://github.com/friendlyarm/kernel-rockchip
- Branch: `nanopi6-v6.1.y`
- Commit: `30d3e1c2470a7282f37b96fdd4354314dda69aa3` (2026-09-11). `Makefile` says `VERSION = 6`, `PATCHLEVEL = 1`, `SUBLEVEL = 141`, empty `EXTRAVERSION`.
- The four driver `.c` files and `rk3588-nanopi6-rev0a.dts` (and the dtsi files it includes) are the same at `0e60f21e4449a6d32ec899b97c7145305bcad86f` (2025-11-07), which is the last commit before FriendlyElec published the headers package dated 2025-12-05.

Headers the modules were built against:

- Package: `linux-headers-6.1.141`, version `6.1.141-16`, architecture `arm64`
- URL: http://112.124.9.243/archives/rk3588/linux-headers-6.1.141_6.1.141-16_arm64.deb
- sha256: `df6d8dfb41ccb6ccb033592ce22d497f264b055c12de5f953cbd02de13d7f333`
- `include/generated/utsrelease.h` is `6.1.141`
- Built by `fa@jensen` with `aarch64-linux-gcc (ctng-1.27.0-109g-FA) 15.2.0`
- Config that shows up in vermagic: `CONFIG_SMP`, `CONFIG_MODULE_UNLOAD`, `CONFIG_MODVERSIONS`, `CONFIG_PREEMPT_VOLUNTARY` (voluntary preempt does not add a vermagic token). `CONFIG_AUXILIARY_BUS`, `CONFIG_DRM_PANEL_EDP`, and `CONFIG_DRM_TI_SN65DSI86` are not set, which is why those drivers are shipped as out-of-tree modules.
- Every CRC in the modules' `__versions` tables matches `Module.symvers` from this package. Symbols the base kernel does not export (`auxiliary_*`, `devm_of_dp_aux_populate_bus`, `__dp_aux_dp_driver_register`, `dp_aux_dp_driver_unregister`) are supplied by the other modules in this set.

The `.ko` files themselves were compiled with `GCC: (Debian 14.2.0-19) 14.2.0`. That string is in each module's `.comment` section. Vermagic, read from the modules, is:

```
6.1.141 SMP mod_unload modversions aarch64
```

The `#47` in the installer README is the kernel's `uname -v` build counter. It is not stored in the modules or in this headers package. The published package revision for this ABI is `6.1.141-16`.

## Modules

`srcversion` is the kernel's hash of the `.c` file (comments and whitespace are ignored). It was checked against each shipped `.ko`.

| Shipped file | Source in this repo | srcversion | What it is |
|---|---|---|---|
| `payload/mods/drm_dp_aux_bus.ko` | `src/kernel/drm_dp_aux_bus.c` | `CE9C8CD5D57FBA337679014` | Unmodified `drivers/gpu/drm/display/drm_dp_aux_bus.c`. SPDX `GPL-2.0`. `MODULE_LICENSE("GPL v2")`. |
| `payload/mods/panel-edp.ko` | `src/kernel/panel-edp.c` | `59820185903C506D867AA1B` | Unmodified `drivers/gpu/drm/panel/panel-edp.c`. The file starts with the NVIDIA permissive notice and the module license string is `GPL and additional rights`. |
| `payload/mods/ti-sn65dsi86.ko` | `src/kernel/ti-sn65dsi86.c` | `0CE64868B71C33A5A39A927` | Unmodified `drivers/gpu/drm/bridge/ti-sn65dsi86.c`. SPDX `GPL-2.0`. |
| `payload/mods/tagos_auxbus.ko` | `src/kernel/tagos_auxbus.c` | `3A7AC5F00A800319D4E1ECF` | `drivers/base/auxiliary.c` built as a module. See below. |

`ti-sn65dsi86.ko` depends on `tagos_auxbus` and `drm_dp_aux_bus`, and `panel-edp.ko` depends on `drm_dp_aux_bus`. That dependency is recorded by modpost because those modules export the symbols. The bridge and panel `.c` files were not edited to name `tagos_auxbus`.

`tagos_auxbus.ko` is the one file that is not an untouched kernel file. The binary's `__FILE__` string is `/workspace/bridge/dtsi/build/auxbus-mod/tagos_auxbus.c`, so the original build was out of tree. The original `.c` was not in this repository. `src/kernel/tagos_auxbus.c` is that source, reconstructed so its srcversion matches the `.ko`: upstream `auxiliary.c`, with `#include "base.h"` and `auxiliary_bus_init()` removed (that header is unused, and the init in the binary returns `bus_register()` directly), plus `module_init` / `module_exit`, `MODULE_LICENSE("GPL v2")`, and `MODULE_DESCRIPTION("Auxiliary bus (drivers/base/auxiliary.c) as module")`.

A cross-build of these four files against the headers package above reproduced the same vermagic, the same srcversion, the same `depends=` lines, and the same symbol CRCs. The `.ko` bytes are not identical: the shipped objects contain no DWARF and were built with Debian GCC 14.2.0-19; a rebuild with another GCC, or with `CONFIG_DEBUG_INFO=y` from that headers package, comes out a different size. To load on the board, the rebuild has to use these headers (or the headers on a board running this kernel) so the CRCs stay the same.

```
make -C src/kernel KERNEL_SRC=/usr/src/linux-headers-6.1.141 \
    ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
```

On the board, `KERNEL_SRC=/lib/modules/6.1.141/build` is enough.

## Device tree

| Shipped file | Source |
|---|---|
| `payload/new-rev0a-nologo.dtb` | `src/kernel/dts/rk3588-nanopi6-rev0a-tagos-nologo.dts`, which includes the kernel's `rk3588-nanopi6-rev0a.dts` and `src/kernel/dts/rk3588-nanopi6-m6-sn65dsi86-nologo.dtsi` |
| `payload/rk3588-nanopi6-m6-sn65dsi86.dtsi` | Review draft already in the repo. It is **not** the exact overlay in the DTB: it sets `route_dsi0` to `okay`. The DTB leaves that route `disabled`. Its own header says the draft was not applied. |

`build-dtb.sh` preprocesses and runs `dtc -@`. Against commit `30d3e1c2470a7282f37b96fdd4354314dda69aa3` the output is the same size as `payload/new-rev0a-nologo.dtb` (265277 bytes) and `dtdiff` reports no property differences. One padding byte differs: after the `status = "disabled"` property of `/display-subsystem/route/route-dsi0`, the shipped blob has `0x03` and a current `dtc` writes `0x00`. That byte is alignment padding. It does not change the tree.

The stock FriendlyElec `rev0a` route for DSI0 is disabled and connected to VP3. The applied overlay enables the SN65DSI86 on I2C4 address `0x2c`, moves the DSI0 link to VP2, turns DSI1 off, and leaves `route-dsi0` disabled so U-Boot does not drive the panel for a boot logo. That is the "nologo" name. The BMP logos in the resource image were not blanked; they are the stock files.

```
KERNEL_SRC=/path/to/kernel-rockchip src/kernel/build-dtb.sh
```

## Resource image

`payload/resource-nologo-16M.img` is a 16 MiB Rockchip `RSCE` image (39 entries). Each entry's hash is SHA-1 of the file bytes, 20 bytes, as in U-Boot `tools/rockchip/resource_tool.c`. `src/kernel/pack-resource.py --check` checks them.

Checked by rebuilding with `dtc -@` from the public tree:

- `rk3588-nanopi6-rev01.dtb` through `rev09.dtb`, `rev0b.dtb`, and `rev0c.dtb` are byte-identical to that tree. `rev0b` is NanoPC-T6 Plus (added in `524e3e035d50`). `rev0c` is NanoPi M6 V2 (added in `474962f3f7ff`, 2026-03-31).
- `rk3588-nanopi6-rev0a.dtb` inside the image is byte-identical to `payload/new-rev0a-nologo.dtb`, not to the stock board dts.
- `rk3588-nanopi6-rev0d.dtb` is a `FriendlyElec NanoPi FC1X` tree (`compatible = "friendlyelec,nanopi-fc1x"`). There is no `rk3588-nanopi6-rev0d.dts` in `friendlyarm/kernel-rockchip` at `30d3e1c2`, and GitHub code search does not find that filename. Its corresponding source is not in the public tree. The blob in the image is the only copy we have.
- The other board dtbs in the image (rk3399, rk3528, rk3566, rk3568, rk3576) rebuild byte-identical from the same public tree, except `rk3566-nanopi-r3-rev01.dtb`. That one matches the file as it was before commit `8204040dbbf2` (2026-07-28, "use virtual-connector for nanopi-r3s"), not the copy at the branch tip. `0e60f21e4449` still has the matching text.
- `logo.bmp` and `logo_kernel.bmp` are identical to each other and to the copies in the `6.1.141-16` headers package (1152056 bytes, sha256 `8a9ac3a02264a56d4f877457da5496f1ab40be181d94c0aa0b310985e65780ce`). They are FriendlyElec's boot logos, not TagosLabs artwork, and they are not generated from a source file in this repo.

`pack-resource.py --replace-dtb` can drop a same-sized rebuilt `rev0a` dtb into a copy of the image and recompute that entry's SHA-1. It refuses to overwrite the input, and it refuses a different size because the other files sit at fixed offsets.

## What is not claimed

- The shipped `.ko` files are not reproduced byte for byte here. vermagic, srcversion, and symbol CRCs are.
- `uname -v` `#47` was not recovered from the modules. The ABI matches headers package `6.1.141-16`.
- `rk3588-nanopi6-rev0d.dtb` (NanoPi FC1X) has no public source.
- The one-byte DTB padding difference is real and has no effect on the decoded tree.
