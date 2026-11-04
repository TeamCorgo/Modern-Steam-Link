# Kernel config

The kernel config is the Linux kernel's own default config for 32-bit ARM, `arch/arm/configs/multi_v7_defconfig`, plus a small fragment, [`steamlink.config`](steamlink.config). Everything not in the fragment keeps its upstream default, so the config stays close to what any generic ARM kernel would have and follows upstream as defaults change.

`multi_v7_defconfig` already supports the Steam Link's Marvell Berlin BG2CD: the SoC, its serial port, USB host, Ethernet (`PXA168_ETH`, as a module) and Wi-Fi (`MWIFIEX_SDIO`, as a module).

## How the config is built

`kernel/build.sh` (run by the workflow's `build-kernel` job):

1. Runs `make multi_v7_defconfig steamlink.config`, the kernel's standard way of applying a fragment on top of a default config (`merge_config.sh`, then `olddefconfig`).
2. Checks the result, and fails the build if:
   - any fragment entry didn't apply (`merge_config` silently drops an entry whose dependencies are off)
   - any default the Steam Link needs to boot from USB has changed (`REQUIRED`: Berlin SoC support, serial, USB host and storage, ext4, initramfs, seccomp, the default namespaces, ...)
   - any ARM SoC family other than Berlin is enabled
   - the Ethernet, Wi-Fi or SD host driver is missing (`REQUIRED_OR_MODULE`)
   - any internal flash (MTD) option is enabled (`FORBIDDEN`)
3. Builds the kernel with Debian's ARM cross-compiler (`gcc-arm-linux-gnueabihf`, from the Debian 13 build container), and installs stripped modules.

The final config ships in the image as `/boot/config-<version>-steam` and in the `kernel-<version>-steam` build artifact. On a running Steam Link, read it with `less /boot/config-$(uname -r)`.

## Changing the kernel version

The fragment isn't tied to a version. Set the workflow's `kernel_version` default (and `KERNEL_VERSION` in `rootfs/Dockerfile`), start a build, and boot it before relying on it. The config check catches upstream default changes that break the Steam Link. The compiler is Debian 13's current cross-compiler, so it stays new enough for new kernels.

## What the fragment changes, and why

Each entry has one of these reasons. Nothing is turned off just to save space.

**The hardware can't do it**

| Entry | Reason |
| --- | --- |
| `CONFIG_ARCH_*` (and four TI `CONFIG_SOC_*`) off for the 57 other SoC families (Qualcomm, Tegra, Exynos, Rockchip, Allwinner, Broadcom, i.MX, OMAP, ...) | `multi_v7_defconfig` supports many ARM chips. The Steam Link is a Berlin BG2CD, so the others are off, and their SoC-specific drivers (clocks, pins, power, display, sound, media) drop out with them. This cuts most of the build. Generic drivers for things you can plug in (USB devices, filesystems, networking) keep their defaults. `kernel/build.sh` reads the platform list from the kernel source and fails if any non-Berlin family is on, including ones added upstream later. |
| `CONFIG_SMP` off | The BG2CD has a single Cortex-A9 core. The device tree lists only `cpu@0`. |
| `CONFIG_CPUSETS` off (not in the fragment) | Pinning containers to CPU cores (`--cpuset-cpus`). It requires SMP, and there's only one core. |
| `CONFIG_POWER_RESET_GPIO_RESTART` off | The device tree declares a `gpio-restart` node, but according to notes from another Steam Link kernel build, toggling that pin doesn't reset the SoC. With the driver enabled, reboot hangs instead of failing. Not yet tested on this image. |

**Safety**

| Entry | Reason |
| --- | --- |
| `CONFIG_MTD` off | The internal NAND flash holds Valve's firmware and bootloader. With MTD off, the kernel has no driver that can read or write it, so it can't damage the stock firmware. `multi_v7_defconfig` enables MTD and the Marvell NAND driver, so this entry is essential. `MTD`, `MTD_RAW_NAND`, `MTD_NAND_MARVELL` and `MTD_UBI` are also in `FORBIDDEN`. |

**Boot path**

| Entry | Reason |
| --- | --- |
| `CONFIG_RESET_BERLIN=y` | The root filesystem is on USB, and both USB PHYs need the Berlin reset controller (`resets = <&chip_rst ...>` in `berlin2cd.dtsi`). The default builds it as a module; built in, USB comes up without depending on the initramfs. |
| `CONFIG_CMDLINE`, `CONFIG_CMDLINE_FORCE` | The stock firmware starts the kernel with kexec. The kernel uses this built-in command line, so the `--command-line` passed by `rootfs/steamlink/factory_test/run.sh` is ignored. This is the combination that has been booted and tested. |

**Debian userspace needs it, and it's off by default**

| Entry | Reason |
| --- | --- |
| `CONFIG_BPF_SYSCALL`, `CONFIG_CGROUP_BPF` | systemd's BPF-based cgroup features (per-service IP filtering, device policy) |
| `CONFIG_ZRAM` (zstd) | compressed swap in RAM, set up by `systemd-zram-generator`; off by default (see `/etc/systemd/zram-generator.conf`) |
| `CONFIG_NETFILTER`, nftables core and rule types | Debian's `nft` (and `iptables`, which runs on nftables in Debian 13). The core is built in; rule types (conntrack, NAT, masquerade, reject, fib, compat, ...) are modules. |

**Container support (Docker, Podman), off by default**

Docker isn't installed in the image, but the kernel is ready for it. The list matches what Docker's own `check-config.sh` asks for, and what [flame7787/steamlink-debian](https://github.com/flame7787/steamlink-debian) uses for Docker on the Steam Link.

| Entry | Reason |
| --- | --- |
| `CONFIG_USER_NS` | user namespaces, for rootless containers |
| `CONFIG_MEMCG`, `CGROUP_PIDS`, `CGROUP_SCHED`, `FAIR_GROUP_SCHED`, `CFS_BANDWIDTH`, `BLK_CGROUP`, `BLK_DEV_THROTTLING` | cgroup v2 controllers behind `--memory`, `--pids-limit`, `--cpus` and block I/O limits |
| `CONFIG_POSIX_MQUEUE`, `CONFIG_KEYS` | IPC and per-container keyrings used by container runtimes |
| `CONFIG_OVERLAY_FS` | Docker's `overlay2` storage driver |
| `CONFIG_VETH`, `CONFIG_BRIDGE_NETFILTER` | container network interfaces on the `docker0` bridge, with bridge traffic going through the firewall |
| `CONFIG_NETFILTER_XT_*` (addrtype, conntrack, multiport, comment, MASQUERADE, NAT, MARK) | matches and targets in the iptables rules Docker writes (Debian's `iptables` runs them on nftables through `NFT_COMPAT`) |
| `CONFIG_MACVLAN`, `CONFIG_IPVLAN`, `CONFIG_VXLAN` | Docker's macvlan, ipvlan and overlay network drivers |

`rootfs/etc/modules-load.d/containers.conf` loads `br_netfilter` and `overlay` at boot. `br_netfilter` doesn't load by itself when a bridge is created.

Seccomp, swap, cgroups and the PID, network, IPC and UTS namespaces are already on by default, so the fragment doesn't list them. They're in `REQUIRED`, so the build fails if a future default changes.

## Hardware that can't be enabled

These are off or unused because nothing in mainline Linux can safely drive them on this board, not because of a config choice:

- **Internal NAND flash.** Deliberately blocked (see Safety above). Turning it on would risk Valve's firmware and is never done here.
- **HDMI video output.** Mainline has no display driver for the Berlin video pipeline, so the screen goes dark at handover. There's no local console or desktop.
- **Audio** over HDMI or the built-in hardware: no mainline driver.
- **Hardware video decoding:** no mainline driver.
- **Reboot and power-off.** There's no working reset path (see `POWER_RESET_GPIO_RESTART` above). Reboot needs a power cycle.
- **A second CPU core.** There isn't one.

## Image size

Turning off the other SoC families removes most of `multi_v7_defconfig`'s board-specific drivers. Generic drivers still make the kernel and modules larger than a board-only config would. Modules are stripped when installed. `rootfs/build.sh` fails the build if the disk image would no longer fit on a 2 GB stick.

## Valve's Steam Link SDK

The kernel build doesn't use Valve's [steamlink-sdk](https://github.com/ValveSoftware/steamlink-sdk). The SDK targets apps running on the stock firmware: a 2019 GCC 9.2 toolchain, the firmware's root filesystem (glibc 2.19, Qt, SDL), and Valve's 3.8 kernel source. It's only needed to rebuild `rootfs/boot/kexec_load.ko`, which runs on Valve's 3.8 kernel and must be built against that kernel's source. Its source isn't published, so the repository ships the prebuilt module (see "Prebuilt boot binaries" in the main README).
