#!/usr/bin/env bash
#
# Build a Steam Link kernel. Expects ./linux-$KERNEL_VERSION (unpacked kernel.org
# source) in the current directory and Debian's ARM cross-compiler
# (gcc-arm-linux-gnueabihf) on the PATH.
# Output: linux-$KERNEL_VERSION/arch/arm/boot/zImage, the dtb, and modules
# installed under /tmp/build-modules.
#
# The config is the kernel's default 32-bit ARM config (multi_v7_defconfig)
# plus kernel/steamlink.config. See kernel/README.md.

set -e

: "${KERNEL_VERSION:?set KERNEL_VERSION, e.g. 7.3.1}"

REPO_DIR=$(cd "$(dirname "$0")/.." && pwd)
FRAGMENT="$REPO_DIR/kernel/steamlink.config"

export ARCH=arm
export CROSS_COMPILE=arm-linux-gnueabihf-
export LOCALVERSION="-steam"

${CROSS_COMPILE}gcc --version | head -1

cd linux-$KERNEL_VERSION

# Default config + Steam Link fragment (merge_config.sh, then olddefconfig)
cp "$FRAGMENT" arch/arm/configs/steamlink.config
make multi_v7_defconfig steamlink.config

failed=0

# 1. Every entry in the fragment must survive. merge_config can't enforce
#    dependencies, so an entry whose dependencies are off is silently dropped.
while IFS= read -r line; do
    case "$line" in
        CONFIG_*=*)
            if ! grep -qxF "$line" .config; then
                echo "ERROR: fragment entry not applied: $line (got: $(grep "^${line%%=*}=" .config || echo unset))" >&2
                failed=1
            fi
            ;;
        "# CONFIG_"*" is not set")
            sym=${line#\# }; sym=${sym%% is not set}
            if grep -q "^$sym=[ym]$" .config; then
                echo "ERROR: fragment says $sym is off, but it is $(grep "^$sym=" .config)" >&2
                failed=1
            fi
            ;;
    esac
done < "$FRAGMENT"

# 2. Defaults the Steam Link depends on to boot from USB. These come from
#    multi_v7_defconfig; fail if a future default changes them.
REQUIRED="
ARCH_BERLIN MACH_BERLIN_BG2CD PINCTRL_BERLIN_BG2CD RESET_BERLIN
SERIAL_8250_DW
USB_EHCI_HCD USB_CHIPIDEA USB_CHIPIDEA_HOST PHY_BERLIN_USB USB_STORAGE
EXT4_FS DEVTMPFS BLK_DEV_INITRD RD_GZIP
UNIX INET CGROUPS SWAP SECCOMP SECCOMP_FILTER
NAMESPACES UTS_NS IPC_NS PID_NS NET_NS
"
for sym in $REQUIRED; do
    if ! grep -q "^CONFIG_$sym=y$" .config; then
        echo "ERROR: CONFIG_$sym must be =y" >&2
        failed=1
    fi
done

# 2b. No other ARM SoC family may be enabled: no ARCH_*, MACH_* or SOC_* option
#     from arch/arm/mach-*/Kconfig or Kconfig.platforms except Berlin's. The
#     list comes from the kernel source, so a family added upstream later is
#     caught too; add it to the fragment's "Other ARM chip families" block.
berlin_syms=$(grep -hoE '^\s*(menu)?config (ARCH|MACH|SOC)_[A-Z0-9_]+' arch/arm/mach-berlin/Kconfig | awk '{print $2}')
platform_syms=$(grep -hoE '^\s*(menu)?config (ARCH|MACH|SOC)_[A-Z0-9_]+' arch/arm/mach-*/Kconfig arch/arm/Kconfig.platforms \
    | awk '{print $2}' | grep -vE '^ARCH_MULTI' | sort -u)
for sym in $platform_syms; do
    echo "$berlin_syms" | grep -qx "$sym" && continue
    if grep -q "^CONFIG_$sym=y$" .config; then
        echo "ERROR: CONFIG_$sym is another SoC family; disable it in kernel/steamlink.config" >&2
        failed=1
    fi
done

# 3. Hardware drivers that may be modules (they load after the root filesystem)
# Ethernet, Wi-Fi, and the SD host controller the Wi-Fi chip sits on
REQUIRED_OR_MODULE="PXA168_ETH MWIFIEX_SDIO MMC_SDHCI_PXAV3"
for sym in $REQUIRED_OR_MODULE; do
    if ! grep -q "^CONFIG_$sym=[ym]$" .config; then
        echo "ERROR: CONFIG_$sym must be =y or =m" >&2
        failed=1
    fi
done

# 4. Never build anything that can touch the internal NAND flash, where Valve's
#    firmware lives (MTD is off in the fragment; this also catches sub-options)
FORBIDDEN="MTD MTD_RAW_NAND MTD_NAND_MARVELL MTD_UBI"
for sym in $FORBIDDEN; do
    if grep -q "^CONFIG_$sym=[ym]$" .config; then
        echo "ERROR: CONFIG_$sym must be disabled" >&2
        failed=1
    fi
done

[ "$failed" = 0 ] || exit 1
echo "Kernel config check passed"

make -j"$(nproc)"
# Strip debug symbols from modules to keep the image small
INSTALL_MOD_PATH=/tmp/build-modules INSTALL_MOD_STRIP=1 make modules_install
