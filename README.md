# NanoPi M4B (RK3399) iStoreOS 24.10 适配补丁集

把 FriendlyElec **NanoPi M4B**（RK3399 + Ampak AP6256 无线模组）适配进 **iStoreOS 24.10**
（基于 OpenWrt）的一份补丁 + 脚本集合：让官方上游（istoreos-24.10，commit `fb971407ff`）能编译出
可启动的 M4B 镜像，并修好 HDMI 显示、WiFi（AP6256 / BCM4345/9）与 U-Boot SPL 软重启等问题。

---

## ⚠️ 生成方式声明（AI-Generated）

> **本仓库内的全部内容均由 AI 在对话中自动生成，未经人工逐行审阅内核 / 构建系统源码。**
> 包括但不限于：9 个补丁文件（001–005、300–303）、`apply.sh`、`build.sh`、两个 `files/` 覆盖层、
> `.config` / `feeds.conf.default`，以及这份 README 本身。
>
> 其中 `.config` 与 `feeds.conf.default` 是基于 **iStoreOS 官方 NanoPi R4SE 固件**
> （<https://fw.koolcenter.com/iStoreOS/r4se/>）发布包里的 `config.buildinfo` / `feeds.buildinfo`
> 生成，目的是**复刻官方原版固件的功能选型**（软件包集合、默认 feeds 源等），再在此之上叠加 M4B 专属设备与
> 驱动配置。R4SE 与 M4B 同为 RK3399 平台，故可直接借用其构建配置基线。

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
- 固件基础：iStoreOS 24.10（OpenWrt 衍生），内核 6.6.144，U-Boot 2024.10
- brcmfmac 驱动来自 mac80211 **backports 6.12.96**（iStoreOS 已自带 43456 CLM 支持）
- 推荐构建环境：WSL2（Debian/Ubuntu 系），干净 PATH

---

## 目录结构

```
all-patches/
├── apply.sh                      # 一键套用全部补丁 + 覆盖层 + 配置（核心脚本）
├── build.sh                      # 编译包装器（清理 PATH 后透传 make 参数）
├── .config                       # 预设配置：基于 iStoreOS 官方 R4SE 的 config.buildinfo 生成（复刻原版功能），再叠加 M4B 设备 + WiFi 栈 + wpad-openssl
├── feeds.conf.default            # feeds 配置：基于官方 R4SE 的 feeds.buildinfo 生成
├── 001-armv8.mk-add-nanopi-m4b.patch        # 构建系统：注入 M4B 设备
├── 002-uboot-rockchip-add-nanopi-m4b.patch  # 构建系统：注入 M4B U-Boot 变体
├── 003-modules-drm-rockchip-rk3399-vop-hdmi.patch  # 内核模块：DRM/HDMI kmod
├── 004-bootscript-console-tty0.patch          # bootscript：内核 cmdline console=tty0
├── 005-brcmfmac-firmware-43456-sdio.patch    # 新增 AP6256 固件包
├── 300-rk3399-nanopi4-spl-io-domain-dts.patch   # U-Boot SPL IO-domain（DTS）
├── 301-rockchip-io-domain-spl-kconfig.patch     # U-Boot SPL IO-domain（Kconfig）
├── 302-rk8xx-regulator-spl.patch               # U-Boot SPL rk8xx 稳压器
├── 303-nanopi-m4b-spl-io-domain-defconfig.patch  # U-Boot SPL defconfig 使能
├── files/
│   ├── etc/uci-defaults/91-hdmi-console-tty1   # HDMI 屏 tty1 登录控制台
│   └── etc/modprobe.d/brcmfmac.conf            # brcmfmac 稳定性修复
└── config.r4se.{buildinfo,seed}  # 官方 R4SE buildinfo 源文件（生成 .config 的基线，非 M4B 运行时必需）
```

---

## 补丁与脚本清单

### 构建系统 / 内核补丁（`git apply`，由 `apply.sh` [2/6] 套用）

| 文件 | 作用目标 | 内容 |
|------|----------|------|
| `001-armv8.mk-add-nanopi-m4b.patch` | `target/linux/rockchip/image/armv8.mk` | 新增 `DEVICE_friendlyarm_nanopi-m4b`（含 `nanopi-m4b-rk3399` U-Boot 选择、DTB 名）。**必需**，上游无 M4B |
| `002-uboot-rockchip-add-nanopi-m4b.patch` | `package/boot/uboot-rockchip/Makefile` | 新增 `nanopi-m4b-rk3399` U-Boot 变体。**必需** |
| `003-modules-drm-rockchip-rk3399-vop-hdmi.patch` | `target/linux/rockchip/modules.mk` | 新增 RK3399 VOP / DW-HDMI / INNO-HDMI-PHY 等显示内核模块包 |
| `004-bootscript-console-tty0.patch` | `target/linux/rockchip/image/default.bootscript` | 内核命令行 `console=tty0`，让显示输出到 HDMI 帧缓冲控制台 |
| `005-brcmfmac-firmware-43456-sdio.patch` | `package/firmware/brcmfmac-firmware-43456/Makefile`（新增） | AP6256 固件包：从 `armbian/firmware` 固定 commit `f50a2a21bcdb77a562b3976930c5c6b521a1df08` 拉取 `brcmfmac43456-sdio.{bin,txt,clm_blob}`，装到 `/lib/firmware/brcm/`，并软链板级 `brcmfmac43456-sdio.friendlyarm,nanopi-m4b.{bin,txt}`。**WiFi 必需** |

> 注：HDMI 显示栈的 `config-6.6` 内建开关（DRM / ROCKCHIP_VOP / DW_HDMI / FRAMEBUFFER_CONSOLE 等）
> 由 `apply.sh` 的 **[3/6]** 步骤以 Python 内联改写 `target/linux/rockchip/armv8/config-6.6` 注入
> （该步骤在脚本内被注释为 HDMI 配置内联注入，**没有独立 patch 文件**）。因此务必用 `apply.sh` 套用，
> 勿仅手工 `git apply` 前 5 个补丁。

### U-Boot SPL 补丁（`cp` 到 `package/boot/uboot-rockchip/patches/`，由 `apply.sh` [5/6] 套用）

修复 M4B 在 SPL 阶段 IO-domain 未上电导致软重启异常的问题：

| 文件 | 作用目标 |
|------|----------|
| `300-rk3399-nanopi4-spl-io-domain-dts.patch` | `arch/arm/dts/rk3399-nanopi4-u-boot.dtsi` |
| `301-rockchip-io-domain-spl-kconfig.patch` | `drivers/misc/Kconfig`、`drivers/power/regulator/Kconfig` |
| `302-rk8xx-regulator-spl.patch` | `drivers/power/regulator/rk8xx.c` |
| `303-nanopi-m4b-spl-io-domain-defconfig.patch` | `configs/nanopi-m4b-rk3399_defconfig` |

### `files/` 覆盖层（构建期并入 rootfs，由 `apply.sh` [6/6] 复制）

- `etc/uci-defaults/91-hdmi-console-tty1`：首启向 `/etc/inittab` 追加 `tty1::askfirst:/usr/libexec/login.sh`，
  让 HDMI 屏出现登录控制台（该板内核 console 默认指向 `ttyFIQ0` 调试串口）。使用 `askfirst + login.sh` 而非
  `getty`，避免 busybox 缺 getty 导致 procd 反复重启缺失二进制。
- `etc/modprobe.d/brcmfmac.conf`：
  `options brcmfmac roamoff=1 feature_disable=0x282000` ——
  关闭固件对 FWSUP / SAE / DUMP_OBSS 的支持并禁用固件内部 roaming 引擎，修复 AP6256 在 AP 模式下固件不定时
  崩溃、反复 `mmc_hw_reset` 复位的问题（社区对同类 brcmfmac 崩溃的标准修法）。

### 脚本

- `apply.sh`：在 iStoreOS 源码根目录运行，**六步**完成适配——净化 PATH、重置源码、git apply 001–005、
  内联注入 HDMI config、SPL 补丁落盘、复制 `files/` + 配置，并做全套校验。
- `build.sh`：编译包装器，清理 PATH（去掉 WSL 挂载的 Windows 路径）后透传任意 `make` 参数。

---

## 使用方法

```bash
# 1) 取得 iStoreOS 24.10 源码（以 ~/istoreos 为例）
git clone <iStoreOS 24.10 仓库> ~/istoreos
cd ~/istoreos

# 2) 套用全部补丁与配置（脚本自动把自身目录当作补丁源）
bash ~/istoreos/all-patches/apply.sh ~/istoreos
#   或直接在 all-patches 目录内执行： bash apply.sh

# 3) 更新并安装 feeds、归一化配置
./scripts/feeds update -a && ./scripts/feeds install -a
make defconfig

# 4) 编译（务必用干净 PATH，见下方“WSL PATH 坑”）
bash ~/istoreos/all-patches/build.sh -j$(nproc)
#   等价于： export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
#            make -j$(nproc)
```

产物：`bin/targets/rockchip/armv8/` 下的 `*-nanopi-m4b-*.img.gz` / `*.img` 等。

### WSL PATH 坑（务必注意）

若你的 WSL shell 的 `PATH` 含 Windows 挂载路径（如 `/mnt/c/Program Files (x86)/...`），
OpenWrt 会把它拼进 U-Boot 子 `make` 的 `PATH=...`，空格被转成冒号后其中的 `(` 会让 uboot 编译报
`bash: -c: line 1: syntax error near unexpected token '('`。**必须用精简 PATH 启动 make**（`build.sh` 已处理）。

---

## 已知问题与限制

- **`brcmf_c_process_txcap_blob: no txcap_blob available (err=-2)` 这条 dmesg 是正常现象，无害**。
  它是 upstream brcmfmac 对“Apple 设备 TxCap 校准 blob”的探测，非 Apple 板无此 blob，打印 info 后直接
  `return 0` 继续初始化；WiFi 照常工作（固件随后正常加载、AP 接口正常起来）。无需处理。
- **WPA3 不可用**：`brcmfmac.conf` 关闭了 SAE（`feature_disable` 含 bit19），因 2017 年老固件不支持 WPA3。
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
  验证；**尚未在 eMMC 上验证**。若刷入板载 eMMC，请自行确认启动链路（U-Boot SPL / 分区布局）与运行稳定性，
  风险自负。

---

## 验证状态

| 项 | 状态 | 说明 |
|----|------|------|
| 补丁 `git apply` / `--check` | ✅ 已静态验证 | 在干净 HEAD `fb971407ff` 上 001–005 + 300–303 均通过 |
| WiFi 功能 | ✅ 运行期验证（用户提供 dmesg） | 固件加载成功、AP 接口 `phy0-ap0` 起来并桥接进 `br-lan` |
| brcmfmac 崩溃修复 | ✅ 运行期验证 | 该次启动 dmesg 无 `brcmf_fw_crashed`，旧崩溃循环已消除 |
| 端到端编译 | ⏳ 待人工验证 | AI 无法编译，请使用者按上文步骤实编 |
| HDMI 显示 | ✅ 运行期验证（烧录后） | 用户实测 HDMI 显示正常（tty1 控制台 + 帧缓冲输出） |
| eMMC 烧录 | ⏳ 未验证 | 仅在 SDCard 上验证过，eMMC 未验证（见“已知问题”） |
| 蓝牙 | ❌ 不支持 | 见“已知问题” |

---

## 如何反馈问题

请在使用中遇到以下情况时反馈（建议附日志原文）：

1. **编译报错**：贴出 `make` 失败片段（含 `apply.sh` 校验段输出）。
2. **运行异常**：贴出设备 `dmesg`、`logread`、`uci show wireless` 等相关输出。
3. **功能缺失**：如 HDMI 无显示、WiFi 起不来、5GHz 缺失、稳定性差等。

反馈渠道：GitHub Issue / 你与 AI 的对话窗口。AI 会据此定位根因并迭代更新补丁。

> **建议遇到问题直接交由 AI 处理**：本仓库的全部补丁与脚本本就由 AI 生成，遇到编译/运行问题，
> 把报错与日志（见上）贴回给 AI 对话窗口，由 AI 定位并迭代修复通常是最快的路径。
>
> **作者声明（仅为分享）**：作者发布此仓库**仅供技术分享与学习**，并非维护一个会被持续支持的正式项目。
> 作者**不保证会及时（甚至不一定会）修复**你反馈的问题。如需可靠修复，请优先采用上面的 AI 处理路径，
> 或在遵循许可证的前提下自行修改、派生（fork）本仓库。

---

## 许可证

补丁与脚本按 “原样（as-is）” 提供，无担保。固件文件版权归 Broadcom / Ampak / Armbian 等原始权利方，
本仓库仅做构建系统集成，不重新分发固件二进制。
