# NanoPi M4B (RK3399) iStoreOS 适配补丁集（24.10 / 25.12）

把 FriendlyElec **NanoPi M4B**（RK3399 + Ampak AP6256 无线模组）适配进 **iStoreOS 24.10 与 25.12**
（均基于 OpenWrt）的补丁 + 脚本集合。让官方上游能编译出可启动的 M4B 镜像，并修好 HDMI 显示、
WiFi（AP6256 / BCM4345/9）与 U-Boot SPL 软重启等问题。

本仓库用**两个并列子目录**管理两个 iStoreOS 版本：

- `24.10/` —— 对应上游 `istoreos-24.10`（内核 6.6、U-Boot 2024.10）
- `25.12/` —— 对应上游 `istoreos-25.12`（内核 6.12、U-Boot 2025.10），是 24.10 的**重移植版**
  （25.12 相对 24.10 的关键变化见下方「版本差异概览」）

所有补丁与脚本由 AI 在对话中生成；GitHub Actions 通过 `version` 输入手动选择要编译的版本。

---

## ⚠️ 生成方式声明（AI-Generated）

> **本仓库内的全部内容均由 AI 在对话中自动生成，未经人工逐行审阅内核 / 构建系统源码。**
> 包括但不限于：各版本的补丁文件、`apply.sh`、`build.sh`、`files/` 覆盖层、
> `config.r4se` / `feeds.r4se`，以及这份 README 本身。
>
> 其中 `config.r4se` 与 `feeds.r4se` 是基于 **iStoreOS 官方 NanoPi R4SE 固件**
> （<https://fw.koolcenter.com/iStoreOS/r4se/>）发布包里的 `config.*.buildinfo` / `feeds.*.buildinfo`
> 生成，目的是**复刻官方原版固件的功能选型**（软件包集合、默认 feeds 源等），再在此之上
> **仅保留 NanoPi M4B 一个设备**、叠加 M4B 专属驱动配置。R4SE 与 M4B 同为 RK3399 平台，故可直接借用其构建配置基线。

AI 无法完成、必须由**使用者（人工）**负责的部分：

| 阶段 | 人工职责 | 说明 |
|------|----------|------|
| 编译验证 | 在本地 iStoreOS 源码树中实际执行 `apply.sh` + `make`，确认能产出 M4B 镜像、无编译错误 | AI 只能静态核对补丁 `git apply` 是否通过，无法真正编译 |
| 烧录后系统验证 | 将镜像写入 SD / eMMC，开机检查 HDMI 显示、WiFi AP/Client、网络连通性、长时间稳定性 | AI 没有实体设备，无法上电实测 |
| 问题反馈 | 把编译报错、运行日志（`dmesg`）、异常现象反馈回来 | AI 据此迭代修复补丁 |

**风险自负**：本适配未经过完整的人工端到端验证，不保证在你的硬件 / 环境下一定能工作。
使用前请自行备份设备数据，刷机有变砖风险。

---

## 目标设备与基础

- 设备：FriendlyElec **NanoPi M4B**（SoC Rockchip RK3399，无线模组 Ampak **AP6256** =
  Broadcom **BCM4345/9**，chiprev 9，SDIO FullMAC）
- 固件基础：iStoreOS（OpenWrt 衍生），两个版本各自基线如下：

| 项 | 24.10 | 25.12 |
|----|-------|-------|
| 内核 | 6.6.144 | 6.12 |
| U-Boot | 2024.10 | 2025.10 |
| mac80211 backports | 6.12.96 | 6.18.26 |
| brcmfmac 来源 | backports（已含 43456 CLM 支持） | backports 6.18.26 |
| 推荐构建环境 | WSL2（Debian/Ubuntu 系），干净 PATH | 同左 |

---

## 版本差异概览

| 项 | 24.10 | 25.12 | 影响 |
|----|-------|-------|------|
| 内核 | 6.6 | 6.12 | `config-6.6` → `config-6.12`；HDMI 控制台机制变化 |
| U-Boot | 2024.10 | 2025.10 | 24.10 的 SPL IO-domain 修复（300–303）已**合入上游** → 25.12 **丢弃 300–303** |
| backports | 6.12.96 | 6.18.26 | brcmfmac `feature.h` 枚举已核对，`feature_disable=0x28A000` 仍正确 |
| 帧缓冲控制台 | `FRAMEBUFFER_CONSOLE=y` | **已移除**（6.12 fbcon 改为 DRM fbdev client） | 25.12 依赖 `DRM_FBDEV_EMULATION=y` 提供 tty0 控制台 |
| 补丁集 | 001–005, 300–303, 880-01 | **001–005, 880-01** | 净减 300–303 四个补丁（仅 24.10 保留） |

> 注意：`880-01` 在两个版本**正文逐字相同**，仅文件名前缀不同（`-6.12-` vs `-6.18-`，对应 backports 版本），
> 已分别在各自 backports 的 `cfg80211.c` 上 `git apply --check` 验证通过。

---

## 目录结构

```
nanopi-m4b_istoreos/
├── .github/workflows/build.yml   # GitHub Actions：手动触发，version 选择 24.10 / 25.12
├── README.md                     # 本文件（合并 README）
├── 24.10/                        # iStoreOS 24.10 适配
│   ├── apply.sh                  # 一键套用全部补丁 + 覆盖层 + 配置（核心脚本）
│   ├── build.sh                  # 编译包装器（清理 PATH 后透传 make 参数）
│   ├── config.r4se               # 预设配置：基于官方 R4SE 24.10 buildinfo 派生，仅保留 M4B
│   ├── feeds.r4se                # feeds 配置：基于官方 R4SE 24.10 buildinfo
│   ├── 001-armv8.mk-add-nanopi-m4b.patch
│   ├── 002-uboot-rockchip-add-nanopi-m4b.patch
│   ├── 003-modules-drm-rockchip-rk3399-vop-hdmi.patch
│   ├── 004-bootscript-console-tty0.patch
│   ├── 005-brcmfmac-firmware-43456-sdio.patch
│   ├── 300-rk3399-nanopi4-spl-io-domain-dts.patch      # 仅 24.10：U-Boot SPL IO-domain（DTS）
│   ├── 301-rockchip-io-domain-spl-kconfig.patch        # 仅 24.10：U-Boot SPL IO-domain（Kconfig）
│   ├── 302-rk8xx-regulator-spl.patch                    # 仅 24.10：U-Boot SPL rk8xx 稳压器
│   ├── 303-nanopi-m4b-spl-io-domain-defconfig.patch     # 仅 24.10：U-Boot SPL defconfig 使能
│   ├── 880-01-istoreos-6.12-brcmfmac-fix-ap-mode-station-signal.patch
│   └── files/
│       ├── etc/uci-defaults/91-hdmi-console-tty1        # HDMI 屏 tty1 登录控制台
│       ├── etc/modprobe.d/brcmfmac.conf                 # brcmfmac 稳定性修复
│       └── etc/hotplug.d/ieee80211/99-brcmfmac-recover  # 固件崩溃后自动 `wifi up` 恢复 AP（看门狗）
└── 25.12/                        # iStoreOS 25.12 适配
    ├── apply.sh
    ├── build.sh
    ├── install-deps.sh           # 25.12 专属：构建主机依赖安装（含 zstd/dtc 自检）
    ├── config.r4se
    ├── feeds.r4se
    ├── 001-armv8.mk-add-nanopi-m4b.patch
    ├── 002-uboot-rockchip-add-nanopi-m4b.patch
    ├── 003-modules-drm-rockchip-rk3399-vop-hdmi.patch
    ├── 004-bootscript-console-tty0.patch
    ├── 005-brcmfmac-firmware-43456-sdio.patch
    ├── 880-01-istoreos-6.18-brcmfmac-fix-ap-mode-station-signal.patch
    └── files/                    # 同 24.10/files/（91-hdmi-console-tty1、brcmfmac.conf、99-brcmfmac-recover）
```

> **`config.r4se` / `feeds.r4se` 说明**：
> - **来源**：基于 iStoreOS 官方 NanoPi R4SE 固件（<https://fw.koolcenter.com/iStoreOS/r4se/>）发布包中的
>   `config.*.buildinfo` / `feeds.*.buildinfo` 派生。R4SE 与 M4B 同为 RK3399 平台，故直接借用其构建配置基线。
> - **作用**：`config.r4se` 复刻官方原版固件的功能选型（软件包集合等），再在其上**仅保留 NanoPi M4B 一个设备**、
>   叠加 M4B 专属驱动配置；`feeds.r4se` 复刻官方的默认 feeds 源。
> - **运行期映射**：iStoreOS 实际读取的是 `feeds.conf.default` 与 `.config` —— 由 `apply.sh` 在套用时
>   把 `feeds.r4se` 复制为 `feeds.conf.default`、把 `config.r4se` 复制为 `.config`。

---

## 补丁与脚本清单

### 构建系统 / 内核补丁（`git apply`，由 `apply.sh` [2/6] 套用）

| 文件 | 作用目标 | 内容 |
|------|----------|------|
| `001-armv8.mk-add-nanopi-m4b.patch` | `target/linux/rockchip/image/armv8.mk` | 新增 `DEVICE_friendlyarm_nanopi-m4b`（含 `nanopi-m4b-rk3399` U-Boot 选择、DTB 名）。**必需**，上游无 M4B |
| `002-uboot-rockchip-add-nanopi-m4b.patch` | `package/boot/uboot-rockchip/Makefile` | 新增 `nanopi-m4b-rk3399` U-Boot 变体。**必需** |
| `003-modules-drm-rockchip-rk3399-vop-hdmi.patch` | `target/linux/rockchip/modules.mk` | 新增 RK3399 VOP / DW-HDMI / INNO-HDMI-PHY 等显示内核模块包 |
| `004-bootscript-console-tty0.patch` | `target/linux/rockchip/image/default.bootscript` | 内核命令行 `console=tty0`，让显示输出到 HDMI 帧缓冲控制台 |
| `005-brcmfmac-firmware-43456-sdio.patch` | `package/firmware/brcmfmac-firmware-43456/Makefile`（新增） | AP6256 固件包：从 `armbian/firmware` 固定 commit 拉取 `brcmfmac43456-sdio.{bin,txt,clm_blob}`，装到 `/lib/firmware/brcm/`，并软链板级 `brcmfmac43456-sdio.friendlyarm,nanopi-m4b.{bin,txt}`。**WiFi 必需** |

> 注：HDMI 显示栈的内核 `config-*` 内建开关（DRM / ROCKCHIP_VOP / DW_HDMI / INNO_HDMI /
> `DRM_FBDEV_EMULATION` 等）由 `apply.sh` 的 **[3/6]** 步骤以 Python 内联改写
> `target/linux/rockchip/armv8/config-6.6`（24.10）或 `config-6.12`（25.12）注入
> （**没有独立 patch 文件**）。因此务必用 `apply.sh` 套用，勿仅手工 `git apply` 前 5 个补丁。

### U-Boot SPL 补丁（`cp` 到 `package/boot/uboot-rockchip/patches/`，**仅 24.10 有**，由 `apply.sh` [5/6] 套用）

修复 M4B 在 SPL 阶段 IO-domain 未上电导致软重启异常的问题（25.12 的 U-Boot 2025.10 已上游化，故丢弃）：

| 文件 | 作用目标 |
|------|----------|
| `300-rk3399-nanopi4-spl-io-domain-dts.patch` | `arch/arm/dts/rk3399-nanopi4-u-boot.dtsi` |
| `301-rockchip-io-domain-spl-kconfig.patch` | `drivers/misc/Kconfig`、`drivers/power/regulator/Kconfig` |
| `302-rk8xx-regulator-spl.patch` | `drivers/power/regulator/rk8xx.c` |
| `303-nanopi-m4b-spl-io-domain-defconfig.patch` | `configs/nanopi-m4b-rk3399_defconfig` |

### mac80211 backports brcmfmac 补丁（`cp` 到 `package/kernel/mac80211/patches/brcm/`，由 `apply.sh` [5/6] 套用）

修复 M4B 在 AP（hostapd）模式下 `LuCI 关联站点` 列表显示 `--- dBm` 的问题：

| 文件 | 作用目标 |
|------|----------|
| `880-01-istoreos-6.12-brcmfmac-fix-ap-mode-station-signal.patch`（24.10） | `drivers/net/wireless/broadcom/brcm80211/brcmfmac/cfg80211.c`（来自 backports 6.12.96） |
| `880-01-istoreos-6.18-brcmfmac-fix-ap-mode-station-signal.patch`（25.12） | 同上，来自 backports 6.18.26 |

**880-01 修复内容**：原函数 RSSI 兜底分支被 `BRCMF_VIF_STATUS_CONNECTED` 闸住（仅 STA 模式置位），
AP 模式 `sta_info.rssi[]` 全 0 时直接掉进兜底空跑，导致 `NL80211_STA_INFO_SIGNAL` 永远不报。
补丁放行 `brcmf_is_apmode()`、并在 AP 路径预填 `scb_val.ea` 给固件（`BRCMF_C_GET_RSSI` 在 AP 模式需 peer MAC）。
STA 模式行为完全不变。两版本补丁正文逐字相同，已分别在各自 backports 的 `cfg80211.c` 上 `git apply --check` 通过。

### `files/` 覆盖层（构建期并入 rootfs，由 `apply.sh` [6/6] 复制）

- `etc/uci-defaults/91-hdmi-console-tty1`：首启向 `/etc/inittab` 追加 `tty1::askfirst:/usr/libexec/login.sh`，
  让 HDMI 屏出现登录控制台（该板内核 console 默认指向 `ttyFIQ0` 调试串口）。使用 `askfirst + login.sh` 而非
  `getty`，避免 busybox 缺 getty 导致 procd 反复重启缺失二进制。
- `etc/modprobe.d/brcmfmac.conf`：
  `options brcmfmac roamoff=1 feature_disable=0x28A000` —— **兜底**层稳定性修复。
  关闭固件里易触发崩溃/Assert 的位：FWSUP(bit13, 固件内置 supplicant)、SAE(bit19, WPA3)、
  DUMP_OBSS(bit21, ACS 邻频 dump)、MONITOR_FLAG(bit15)；并禁用固件内部 roaming 引擎(roamoff=1)。
  位序严格对照内核 6.12 `brcmfmac/feature.h` 的 enum（0 基）。
  **注意**：`feature_disable` 只能"减少"崩溃、不能"根除"——真正根因是随 armbian 提供的
  2017 年固件 `7.45.96.2` 在 AP 模式下本就 "known to crash"。**彻底修复靠固件升级**（见下方 WiFi 段）：
  005 补丁已把 `.bin` 换成 RPi 维护的 `7.84.17.1`。若仍出现扫描相关崩溃，可把 mask 追加 bit22(SCAN_V2) → `0x68A000`。
- `etc/hotplug.d/ieee80211/99-brcmfmac-recover`：固件偶发崩溃、SDIO 复位后以**新 phy 索引**(phy0→phy1) 重枚举时，
  自动 `wifi up` 在 new phy 上重建 AP，作为兜底确保崩溃也能自愈，无需人工重开 WiFi。
  与上面的 feature_disable 配合：前者尽量从根上避免崩溃，后者作为兜底自愈。

### 脚本

- `apply.sh`：在 iStoreOS 源码根目录运行，**六步**完成适配——净化 PATH、重置源码、git apply 001–005、
  内联注入 HDMI config、SPL + mac80211 backports 补丁落盘、复制 `files/` + 配置，并做全套校验。
- `build.sh`：编译包装器，清理 PATH（去掉 WSL 挂载的 Windows 路径）后透传任意 `make` 参数；
  25.12 版额外在 `make` 前做 curl 后端 / libmbedtls / M4B 设备**自愈与断言**。
- `install-deps.sh`（仅 25.12）：首次构建前安装主机依赖并自检 gcc/git/python3/zstd/dtc 等。

---

## 使用步骤

> 下面以版本 `25.12` 为例；编译 `24.10` 时把子目录与分支替换为 `24.10` / `istoreos-24.10` 即可。
> 24.10 不含 `install-deps.sh`，主机依赖请参考 25.12 版本手动安装。

### 方式 A：本地编译（WSL2）

```bash
# 0. （仅 25.12）安装构建依赖，装完会自检关键工具
bash 25.12/install-deps.sh

# 1. 克隆 iStoreOS 对应版本源码
git clone https://github.com/istoreos/istoreos -b istoreos-25.12 istoreos
cd istoreos

# 2. 把对应版本子目录放入源码树，套用补丁（apply.sh 通过 $0 自定位，并把子目录从 git clean 中排除保护）
cp -r /path/to/nanopi-m4b_istoreos/25.12 ./
bash 25.12/apply.sh "$(pwd)"

# 3. 更新并安装 feeds（勿跑 make defconfig，否则显式 =y 包会被重置为 n）
./scripts/feeds update -a -f
./scripts/feeds install -a

# 4. 编译（【必须】经 build.sh，切勿裸跑 make！）
#    WSL 默认 PATH 含 /mnt/c/Program Files (x86) 等 Windows 路径，OpenWrt 会把它重新拼进
#    uboot 子 make 的 PATH=...，其中 '(' 会让 bash 报：
#      bash: -c: line 1: syntax error near unexpected token '('
#      ERROR: package/boot/uboot-rockchip failed to build (build variant: nanopi-m4b-rk3399)
#    build.sh 会先把 PATH 重置为干净的 Linux 路径来规避此问题；若仍检测到危险字符会直接报错退出。
bash 25.12/build.sh -j"$(nproc)" V=s

# 5. 产物
ls bin/targets/rockchip/armv8/*nanopi-m4b*.img*
```

### 方式 B：GitHub Actions（手动触发，版本可选）

仓库内置 `.github/workflows/build.yml`（已合并 24.10 / 25.12，无需各版本单独维护）：

1. 在 Actions 页面选择 **Build iStoreOS NanoPi M4B** → **Run workflow**
2. 在 `version` 下拉中选择 **24.10** 或 **25.12**（默认 25.12）；可选填
   `istoreos_repo` / `build_threads`（multi / single）
3. 工作流按所选版本克隆对应分支、移入对应子目录、套用 `apply.sh` / `build.sh`
4. 构建完成后，镜像按 `yyyy-mm-dd_原镜像名` 重命名，增量追加发布到固定 tag
   （24.10 → `iStoreOS-24.10`；25.12 → `iStoreOS-25.12`）
5. 每次运行同时上传展开后的 `.config` 与 `manifest` 作为诊断产物（失败也会上传）

---

## WiFi（AP6256 / BCM4345/9）

- 驱动 `brcmfmac` 由 mac80211 backports 提供（24.10: 6.12.96；25.12: 6.18.26），已内含 43456 支持。
- `005` 固件包提供 `brcmfmac43456-sdio.{bin,txt,clm_blob}` 与板级软链。
- **固件升级（彻底修复，主手段）**：随 armbian 提供的旧固件 `7.45.96.2 (FWID 01-1813af84, 2017)`
  社区确认在 AP 模式下 "known to crash"，仅靠关闭功能位无法根除。`005` 补丁已把 `.bin` 换成
  Raspberry Pi 官方维护的 `7.84.17.1 (r871554, FWID 01-3d9e1d87, 2020-05-14)` —— 该版本在
  43456/AP6256 的 AP 模式下稳定性显著更好，是社区验证过的"彻底修复"。
  NVRAM(`*.txt`，板级校准)与 CLM blob 仍取自 armbian（其 `clm_blob` 与 RPi 逐字节相同），
  保留 AP6256 板级参数，避免混用 RPi 板级 nvram 造成校准偏差。
  回退：把 `005` 补丁 `.bin` 的 `RPI_FW_URL` 改回 `ARMBIAN_FW_URL` 并用旧 HASH
  `3167956a7b2cffc4cfcaf6a282b95728c529eebef18a5d9e6d9ff32de32cc67c` 即可。
- `files/etc/modprobe.d/brcmfmac.conf`（`feature_disable` 兜底，不能 100% 根除崩溃）：
  `options brcmfmac roamoff=1 feature_disable=0x28A000`。位序严格对照内核 6.12
  `brcmfmac/feature.h` 的 enum（0 基，位 N=1<<N）：
  `0x28A000 = bit13(FWSUP) + bit15(MONITOR_FLAG) + bit19(SAE) + bit21(DUMP_OBSS)`。
  - FWSUP(bit13)：关闭固件内置 supplicant，改由 hostapd 软件实现。
  - SAE(bit19)：关闭 WPA3-SAE（该固件本就不支持 WPA3，hostapd 侧用 **WPA2** 即可）。
  - DUMP_OBSS(bit21)：关闭 ACS 邻频扫描 dump（关闭后 ACS 退化为软件扫描，无害）。
  - roamoff=1：禁用固件内部 roaming 引擎（老固件 roaming 引擎有 bug，易触发复位）。
  - 若仍出现**扫描相关**崩溃，可追加 bit22(SCAN_V2) → `0x68A000`（回退旧扫描 API，无害）。
- `files/etc/hotplug.d/ieee80211/99-brcmfmac-recover`（看门狗，兜底中的兜底）：固件崩溃后 brcmfmac
  会把 SDIO 复位并以**新 phy 索引**(phy0→phy1→…) 重枚举，netifd/hostapd 仍绑定旧
  phy 导致 AP 不自愈。该脚本在新 wiphy `add` 时自动 `wifi up` 重建 AP，无需人工重开。
- wpad 冲突化解（24.10 的 `config.r4se` 已直接选 `wpad-openssl`；25.12 的 `apply.sh` 额外把
  `wpad-basic-mbedtls` / `hostapd-openssl` 统一为 `wpad-openssl=y`，因其同时提供 hostapd + wpa-supplicant，
  支持 AP 与 Client）。25.12 取消 `wpad-basic-mbedtls` 时会顺带失去 `libmbedtls` 的传递依赖，
  故 `apply.sh` / `build.sh` 显式保 `CONFIG_PACKAGE_libmbedtls=y`（mbedTLS 3.x 一个包编出
  libmbedtls/libmbedcrypto/libmbedx509 三个 .so，libcurl / px5g 依赖它）。

---

## HDMI 显示

- `003` + `apply.sh` 的 `config-*` 内联注入：启用 `CONFIG_ROCKCHIP_VOP=y`（rk3399 VOP1）、
  `CONFIG_ROCKCHIP_INNO_HDMI=y`（inno HDMI PHY）、`CONFIG_ROCKCHIP_DW_HDMI=y`、
  `CONFIG_DRM_ROCKCHIP=y` 与 **`CONFIG_DRM_FBDEV_EMULATION=y`**。
- 25.12（内核 6.12）**已移除** `CONFIG_FRAMEBUFFER_CONSOLE`；tty0 帧缓冲控制台由 `DRM_FBDEV_EMULATION` 的
  DRM fbdev client 提供，`004` 的 `console=tty0` 把它设为首选控制台。24.10（内核 6.6）仍保留 `FRAMEBUFFER_CONSOLE=y`。
- `files/etc/uci-defaults/91-hdmi-console-tty1` 在首启向 `/etc/inittab` 追加
  `tty1::askfirst:/usr/libexec/login.sh`，让 HDMI 屏出现登录提示（用 askfirst + login，
  而非 getty，避免 busybox 无 getty 时 procd 反复重生报错）。

---

## 已知问题与限制

- **`brcmf_c_process_txcap_blob: no txcap_blob available (err=-2)` 这条 dmesg 是正常现象，无害**。
  它是 upstream brcmfmac 对“Apple 设备 TxCap 校准 blob”的探测，非 Apple 板无此 blob，打印 info 后直接
  `return 0` 继续初始化；WiFi 照常工作。无需处理。
- **WPA3 不可用**：`brcmfmac.conf` 关闭了 SAE（`feature_disable` 含 bit15，2017 年老固件不支持 WPA3），
  hostapd 侧用 **WPA2** 即可。关闭 DUMP_OBSS 后 ACS 自动选频退化为软件扫描。
- **WiFi 默认关闭**：iStoreOS 默认不开启无线，需手动：
  ```bash
  uci set wireless.radio0.disabled='0'
  uci set wireless.default_radio0.disabled='0'
  uci commit wireless
  wifi up
  ```
  （OpenWrt 的 `10-wifi-detect` hotplug 会在 brcmfmac 注册出 `wlan0` 时自动生成含 AP 的 `/etc/config/wireless`。）
- **5GHz 取决于国家码 / 监管域**：如 5GHz 不出现，确认已设置监管域（如 CN）。
- **蓝牙（Bluetooth）未适配**：本仓库**未包含**蓝牙支持。M4B 板载 BT 为 BCM4345C5（走 UART + 内核原生
  btbcm serdev），如需使用可另行适配，不在本集合范围内。
- **烧录验证仅覆盖 SDCard，未覆盖 eMMC**：固件（镜像刷写、开机、HDMI、WiFi 等）目前只在 **SDCard** 上完成
  验证；**尚未在 eMMC 上验证**。若刷入板载 eMMC，请自行确认启动链路（U-Boot SPL / 分区布局）与运行稳定性，风险自负。
- **U-Boot SPL 修复仅 24.10 需要**：25.12 用 U-Boot 2025.10，SPL IO-domain 软重启修复已上游化，
  故 25.12 **不再包含** 300–303 补丁。若误把 24.10 的 300–303 带入 25.12 会 `Reversed patch detected` 失败。
- **不要 `make defconfig`**：官方 buildinfo 含大量显式 `=y` 包，defconfig 会将其重置为 `n`，
  导致镜像缩水、依赖断裂。保持 `apply.sh` + `build.sh` 走 oldconfig 流程。
- **干净 PATH（WSL 必看）**：WSL 下务必经 `build.sh`（或手动
  `export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin`）再 `make`，
  否则 uboot 子 make 会因 Windows 挂载路径里的 `(` 报语法错误。
- **`DEVICE_DTS` 不要带 `rockchip/` 前缀**：rockchip 构建系统会自动把 `rockchip/` 拼到 `DEVICE_DTS` 前。
  M4B 必须写 `DEVICE_DTS := rk3399-nanopi-m4b`（内核 DTS 自 Linux 5.12 主线化，位于
  `arch/arm64/boot/dts/rockchip/`）。若误写成 `rockchip/rk3399-nanopi-m4b` 会拼成
  `rockchip/rockchip/...` 导致 dtb 编译 `No such file or directory`。

---

## 验证状态

| 项 | 状态 | 说明 |
|----|------|------|
| 补丁 `git apply` / `--check` | ✅ 已静态验证 | 24.10：干净 HEAD `fb971407ff` 上 001–005 + 300–303 均通过；880-01 在 backports-6.12.96 验证。25.12：001–005 在 istoreos-25.12 验证；880-01 在 backports-6.18.26 验证 |
| WiFi 功能 | ✅ 运行期验证（用户提供 dmesg） | 固件加载成功、AP 接口 `phy0-ap0` 起来并桥接进 `br-lan` |
| brcmfmac 崩溃修复 | 🛠️ 已修(待复测) | 根因为 2017 固件 7.45.96.2 在 AP 模式 "known to crash"；005 补丁已换 RPi 7.84.17.1(主手段) + feature_disable 兜底(0x28A000) + 99-brcmfmac-recover 看门狗自愈。实测日志曾约每 15 分钟崩溃一次（phy0→phy1→phy2→phy3 递增），升级固件后待复测确认 |
| 端到端编译 | ⏳ 待人工验证 | AI 无法编译，请使用者按上文步骤实编 |
| HDMI 显示 | ✅ 运行期验证（烧录后） | 用户实测 HDMI 显示正常（tty1 控制台 + 帧缓冲输出） |
| AP 模式关联站点信号 | 🛠️ 补丁已就位、待运行期验证 | 880-01 让 brcmfmac 在 AP 模式上报 `NL80211_STA_INFO_SIGNAL` |
| eMMC 烧录 | ⏳ 未验证 | 仅在 SDCard 上验证过，eMMC 未验证（见「已知问题」） |
| 蓝牙 | ❌ 不支持 | 见「已知问题」 |

---

## 如何反馈问题

请在使用中遇到以下情况时反馈（建议附日志原文）：

1. **编译报错**：贴出 `make` 失败片段（含 `apply.sh` 校验段输出，务必带 `V=s`）。
2. **运行异常**：贴出设备 `dmesg`、`logread`、`uci show wireless` 等相关输出。
3. **功能缺失**：如 HDMI 无显示、WiFi 起不来、5GHz 缺失、稳定性差等。

反馈渠道：GitHub Issue / 你与 AI 的对话窗口。AI 会据此定位根因并迭代更新补丁。

> **建议遇到问题直接交由 AI 处理**：本仓库的全部补丁与脚本本就由 AI 生成，遇到编译/运行问题，
> 把报错与日志贴回给 AI 对话窗口，由 AI 定位并迭代修复通常是最快的路径。
>
> **作者声明（仅为分享）**：作者发布此仓库**仅供技术分享与学习**，并非维护一个会被持续支持的正式项目。
> 作者**不保证会及时（甚至不一定会）修复**你反馈的问题。如需可靠修复，请优先采用上面的 AI 处理路径，
> 或在遵循许可证前提下自行修改、派生（fork）本仓库。

---

## 许可证

补丁与脚本按 “原样（as-is）” 提供，无担保。固件文件版权归 Broadcom / Ampak / Armbian 等原始权利方，
本仓库仅做构建系统集成，不重新分发固件二进制。
