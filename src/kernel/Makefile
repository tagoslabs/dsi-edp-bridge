# SPDX-License-Identifier: GPL-2.0-only
# Build the four modules shipped in payload/mods/.
#
# On the NanoPi M6, with the matching headers installed:
#   make -C src/kernel KERNEL_SRC=/lib/modules/$(uname -r)/build
#
# Cross build:
#   make -C src/kernel KERNEL_SRC=/usr/src/linux-headers-6.1.141 \
#        ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
#
# The headers must be FriendlyElec linux-headers-6.1.141 version 6.1.141-16
# (see SOURCES.md). A different kernel will not load these modules.

obj-m += tagos_auxbus.o
obj-m += drm_dp_aux_bus.o
obj-m += panel-edp.o
obj-m += ti-sn65dsi86.o

KERNEL_SRC ?= /lib/modules/$(shell uname -r)/build

.PHONY: all modules clean

all modules:
	$(MAKE) -C $(KERNEL_SRC) M=$(CURDIR) \
		$(if $(ARCH),ARCH=$(ARCH)) \
		$(if $(CROSS_COMPILE),CROSS_COMPILE=$(CROSS_COMPILE)) \
		modules

clean:
	$(MAKE) -C $(KERNEL_SRC) M=$(CURDIR) \
		$(if $(ARCH),ARCH=$(ARCH)) \
		$(if $(CROSS_COMPILE),CROSS_COMPILE=$(CROSS_COMPILE)) \
		clean
