#!/bin/bash
# NanoPi M4B (RK3399) iStoreOS 适配：一键套用全部补丁与覆盖层
#
# 用法：
#   bash ~/istoreos/all-patches/apply.sh ~/istoreos
# 或（脚本自动把自身所在目录当作 PATCHES，ISTOREOS 默认 ~/istoreos）：
#   bash apply.sh
#
#   - 001 / 002 【必需，不可删】：M4B 设备与 U-Boot 并未合入 istoreos-24.10 上游。
#       已用 `git show HEAD:target/linux/rockchip/image/armv8.mk` 与
#       `git show HEAD:package/boot/uboot-rockchip/Makefile` 验证：
#       clean HEAD(fb971407ff) 两者均无 nanopi-m4b。因此全新 clone 必须先
#       git apply 001 / 002 才能编译出 M4B 镜像；删除它们将无法识别设备/UBoot。
#   - 005【WiFi 必需】：新增 AP6256(BCM43456) 固件包
#       package/firmware/brcmfmac-firmware-43456，从 armbian/firmware 固定
#       commit 拉取 brcmfmac43456-sdio.{bin,txt,clm_blob} 并安装到
#       /lib/firmware/brcm/（含 board 专用 nvram 软链）。原 001 误把固件包名
#       写成 4356（M4/M4V2/T4 的 AP6356S 才用），M4B 必须 43456。
#   - 其余已确认 OK 的非 WiFi 部分：
#       * U-Boot SPL IO-domain 软重启修复：300/301/302/303
#         （cp 到 package/boot/uboot-rockchip/patches/，由 U-Boot 构建消费）
#       * HDMI 显示栈：003(modules.mk) + 007(config-6.6 inline) —— 确认 OK
#       * bootscript 控制台：004(default.bootscript)
#
#   注：files/ 覆盖层恢复 91-hdmi-console-tty1（HDMI 屏 tty1 登录控制台，
#   见 [6/6] 的 cp）。92/93-wifi 与 15-set-regdom hotplug 仍不打包：WiFi 默认
#   关闭、由用户自行开启，iStoreOS 的 10-wifi-detect hotplug 会自动生成 AP 配置。
#
#   WiFi 完整功能（AP + Client）由以下协同保证：
#       * 内核/DTS 已 WiFi-ready（SDIO/MMC、pwrseq、蓝牙节点均在，无需补丁）
#       * brcmfmac 驱动（mac80211 backports 6.12.96）已含 43456 支持，
#         且 iStoreOS 已带 870-06 CLM-blob modinfo 补丁
#       * 005 固件包提供 bin/clm_blob/nvram
#       * .config 选入 kmod-brcmfmac + 无线栈 + wpad-openssl(AP&Client)
#                       + wifi-scripts(iw/hotplug 自动生成 AP)
#       * OpenWrt 的 10-wifi-detect hotplug 在 brcmfmac 注册出 wlan0 时自动
#         `wifi config` 生成含 AP(hostapd) 的 /etc/config/wireless
#
# 之后的交互步骤（feeds、defconfig、编译）见脚本末尾提示。

set -u

IST="${1:-$HOME/istoreos}"
IST="$(eval echo "$IST")"
PATCHES="$(cd "$(dirname "$0")" && pwd)"   # 本脚本所在目录 = all-patches

echo "ISTOREOS = $IST"
echo "PATCHES  = $PATCHES"
cd "$IST" || { echo "错误：无法进入 $IST"; exit 1; }
[ -d target/linux/rockchip ] || { echo "错误：$IST 不像 iStoreOS 源码树（缺 target/linux/rockchip）"; exit 1; }

# ---- 0) 净化 PATH + 重置到上游最新 + 清理受影响产物 ----
echo "==> [1/6] 净化 PATH、重置源码到 origin/istoreos-24.10 最新、清理受影响产物"
# 必须用精简 PATH：OpenWrt 构建会把环境 PATH 重新拼进子 make 的 PATH=... 里。
# 若环境 PATH 含 WSL 挂载的 Windows 路径（如 /mnt/c/Program Files (x86)/...），
# 经 OpenWrt 把空格转成冒号后会变成 .../(x86)/...，其中 '(' 会让 uboot 子 make
# 报 "syntax error near unexpected token '('"（本适配首次编译即踩中此坑）。
# 精简 PATH 同时保证 git / python3 可用（均位于 /usr/bin 或 /usr/local/bin）。
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "错误：$IST 不是 git 仓库，停止"; exit 1; }
git fetch --all --tags 2>&1 | tail -n 3 || echo "  (fetch 失败，离线模式：仅重置本地)"
TARGET=""
if git rev-parse --verify "origin/istoreos-24.10" >/dev/null 2>&1; then
  TARGET="origin/istoreos-24.10"
elif UP=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null); [ -n "$UP" ]; then
  TARGET="$UP"
fi
if [ -n "$TARGET" ]; then
  echo "  -> git reset --hard $TARGET"
  git reset --hard "$TARGET"
else
  echo "  -> 未找到 origin/istoreos-24.10 且未配置 upstream，git reset --hard HEAD"
  git reset --hard HEAD
fi
# 仅移除验证残留(保留 build_dir/staging_dir/bin/dl/.ccache/feeds/tmp/all-patches)
git clean -ffdx -e build_dir -e staging_dir -e bin -e dl -e .ccache -e feeds -e tmp -e all-patches
# 精确删除受影响编译子目录（其余用户态包与工具链保留，不触发全量重编）
rm -rf build_dir/target-aarch64_generic_musl/root-rockchip* \
       build_dir/target-aarch64_generic_musl/linux-rockchip_armv8 \
       build_dir/*uboot-rockchip* 2>/dev/null
echo "  已清理"

# ---- 1) 001/002/003/004/005 构建系统补丁（git apply）----
echo "==> [2/6] git apply 001..005（构建系统）"
for f in 001-armv8.mk-add-nanopi-m4b 002-uboot-rockchip-add-nanopi-m4b \
        003-modules-drm-rockchip-rk3399-vop-hdmi 004-bootscript-console-tty0 \
        005-brcmfmac-firmware-43456-sdio; do
  if git apply --whitespace=nowarn --check "$PATCHES/$f.patch" >/dev/null 2>&1; then
    git apply --whitespace=nowarn "$PATCHES/$f.patch" && echo "  APPLIED $f" || echo "  错误 $f"
  else
    echo "  跳过 $f（--check 不通过，请检查是否与基线冲突）"
  fi
done
grep -q "friendlyarm_nanopi-m4b" target/linux/rockchip/image/armv8.mk && echo "  M4B 设备已注入 armv8.mk ok" || echo "  !! armv8.mk 未含 M4B（001 未生效）"
grep -q "nanopi-m4b-rk3399" package/boot/uboot-rockchip/Makefile && echo "  M4B U-Boot 已注入 Makefile ok" || echo "  !! uboot Makefile 未含 M4B（002 未生效）"
test -f package/firmware/brcmfmac-firmware-43456/Makefile && echo "  43456 固件包 Makefile 已生成 ok" || echo "  !! 43456 固件包缺失（005 未生效）"

# ---- 2) 007 inline：config-6.6 显示栈 built-in（HDMI）----
echo "==> [3/6] 007 inline：config-6.6 显示栈 built-in"
python3 - <<'PY'
import re
p="target/linux/rockchip/armv8/config-6.6"
want={
 "CONFIG_PHY_ROCKCHIP_INNO_HDMI":"y",
 "CONFIG_DRM":"y",
 "CONFIG_DRM_ROCKCHIP":"y",
 "CONFIG_ROCKCHIP_IOMMU":"y",
 "CONFIG_ROCKCHIP_VOP":"y",
 "CONFIG_ROCKCHIP_VOP2":"n",
 "CONFIG_ROCKCHIP_DW_HDMI":"y",
 "CONFIG_ROCKCHIP_DW_HDMI_QP":"n",
 "CONFIG_DRM_DISPLAY_CONNECTOR":"y",
 "CONFIG_DRM_FBDEV_EMULATION":"y",
 "CONFIG_FB":"y",
 "CONFIG_FRAMEBUFFER_CONSOLE":"y",
 "CONFIG_FRAMEBUFFER_CONSOLE_DETECT_PRIMARY":"y",
}
lines=open(p).read().splitlines()
pat=re.compile(r'^#?\s*(CONFIG_[A-Z0-9_]+)\s*=')
pat2=re.compile(r'^#\s*(CONFIG_[A-Z0-9_]+)\s+is not set\s*$')
out=[]
for ln in lines:
    name=None
    m=pat.match(ln)
    if m: name=m.group(1)
    else:
        m2=pat2.match(ln)
        if m2: name=m2.group(1)
    if name in want:
        continue
    out.append(ln)
for k,v in want.items():
    out.append("%s=%s"%(k,v))
open(p,"w").write("\n".join(out)+"\n")
print("  007 applied (HDMI display stack built-in)")
PY

# ---- 3) 安全体检：config-6.6 不应被注入内核无线符号 ----
echo "==> [4/6] 内核 kconfig 无线符号体检（WiFi 走 backports，不进内核 kconfig）"
python3 - <<'PY'
import re
p="target/linux/rockchip/armv8/config-6.6"
watch=("CONFIG_CFG80211","CONFIG_MAC80211","CONFIG_BRCMUTIL","CONFIG_BRCMFMAC")
bad=[ln for ln in open(p).read().splitlines()
     if re.match(r'^#?\s*(%s)\s*=' % "|".join(watch), ln)]
if bad:
    print("  !! 残留内核无线符号，必须删除：")
    for ln in bad: print("     "+ln)
else:
    print("  ok（brcmfmac 由 mac80211 backports 提供，内核 kconfig 保持上游原样）")
PY

# ---- 4) 补丁落盘：U-Boot(300-303) + mac80211 backports brcmfmac(880) ----
echo "==> [5/6] cp 300-303 -> package/boot/uboot-rockchip/patches/"
mkdir -p package/boot/uboot-rockchip/patches
cp "$PATCHES"/300-rk3399-nanopi4-spl-io-domain-dts.patch \
   "$PATCHES"/301-rockchip-io-domain-spl-kconfig.patch \
   "$PATCHES"/302-rk8xx-regulator-spl.patch \
   "$PATCHES"/303-nanopi-m4b-spl-io-domain-defconfig.patch \
   package/boot/uboot-rockchip/patches/
echo "  已复制 300-303"

# 880 系列是 mac80211 backports 6.12.96 展开后，对 brcmfmac 驱动源码的额外补丁
# （OpenWrt 在 backports 阶段会按字母序合并 patches/brcm/ 下所有 *.patch 一起打）
echo "==> [5/6] cp 880-* -> package/kernel/mac80211/patches/brcm/"
mkdir -p package/kernel/mac80211/patches/brcm
cp "$PATCHES"/880-*.patch package/kernel/mac80211/patches/brcm/
echo "  已复制 880-*（brcmfmac AP 模式 station signal 修复）"

# ---- 5) files/ 覆盖层 + feeds.conf + .config ----
echo "==> [6/6] cp files/ 覆盖层 + feeds.conf.default + .config"
# files/ 覆盖层（OpenWrt 构建期直接并入 rootfs）：当前含
#   91-hdmi-console-tty1 —— 首启向 /etc/inittab 追加 tty1 getty，
#     让 HDMI 屏出现登录控制台（该板内核 cmdline console 默认指向 ttyFIQ0 调试串口）；
#   etc/modprobe.d/brcmfmac.conf —— 关闭 brcmfmac 的 FWSUP/SAE/DUMP_OBSS 功能
#     (feature_disable=0x282000) 并禁用固件 roaming 引擎(roamoff=1)，
#     修复 AP6256(BCM4345/9) 在 AP 模式下固件不定时崩溃、反复 mmc_hw_reset 复位的问题。
mkdir -p files
cp -rf "$PATCHES"/files/. files/
cp "$PATCHES/feeds.conf.default" feeds.conf.default
rm -f feeds.conf
[ -e .config ] && mv -f .config .config.orig
cp "$PATCHES/.config" .config

# ---- 校验 ----
echo "==> 校验"
grep -nE "CONFIG_PHY_ROCKCHIP_INNO_HDMI=|CONFIG_DRM_ROCKCHIP=|CONFIG_ROCKCHIP_VOP=" target/linux/rockchip/armv8/config-6.6
ls package/boot/uboot-rockchip/patches/ | grep -E "30[0-3]" && echo "  300-303 ok"
ls package/kernel/mac80211/patches/brcm/ | grep -E "^880-" && echo "  880-* ok（brcmfmac AP 模式 station signal 修复）"
grep -q "DEVICE_friendlyarm_nanopi-m4b=y" .config && echo "  M4B 设备已选 ok" || echo "  !! .config 未选 M4B 设备"
test -f files/etc/uci-defaults/91-hdmi-console-tty1 && echo "  files/ 覆盖层(91-hdmi-console-tty1) 已就位 ok" || echo "  !! files/ 覆盖层缺失（91-hdmi-console-tty1 未复制）"
test -f files/etc/modprobe.d/brcmfmac.conf && echo "  files/ 覆盖层(brcmfmac.conf) 已就位 ok" || echo "  !! files/ 覆盖层缺失（brcmfmac.conf 未复制）"

echo "==> WiFi 栈校验"
for k in kmod-brcmfmac kmod-cfg80211 kmod-mac80211 kmod-brcmutil \
         brcmfmac-firmware-43456-sdio wpad-openssl wifi-scripts \
         wireless-regdb iw iwinfo; do
  if   grep -q "^CONFIG_PACKAGE_${k}=y\$" .config; then echo "  ${k}=y ok（打进镜像）";
  else echo "  !! 缺 ${k}=y"; fi
done
# 冲突体检：wpad/hostapd/wpa-supplicant 只能有一个虚拟包提供者
for k in wpad-basic-mbedtls hostapd-openssl wpa-supplicant-openssl; do
  if grep -q "^CONFIG_PACKAGE_${k}=y\$" .config; then
    echo "  !! 冲突：${k}=y 与 wpad-openssl 在 hostapd/wpa-supplicant 虚拟包上冲突，请删除"
  else
    echo "  ${k} 未选 ok（无冲突）"
  fi
done

grep -qiE "openvswitch" .config && echo "  !! .config 含 openvswitch（会导致编译失败），请删除" || echo "  openvswitch 未选 ok"

echo
echo "############################################"
echo "# 机械套用完成。下面手动执行："
echo "############################################"
echo "  ./scripts/feeds update -a && ./scripts/feeds install -a"
echo "  make defconfig   # 归一化 .config（拉入 M4B DEVICE_PACKAGES；wpad-openssl 为单一提供者，不会重新引入 wpad-basic-mbedtls 冲突）"
echo "  # 若之后又改了 .config，可再清一次受影响子目录："
echo "  rm -rf build_dir/target-aarch64_generic_musl/root-rockchip* build_dir/target-aarch64_generic_musl/linux-rockchip_armv8 build_dir/*uboot-rockchip*"
echo
echo "  ★ 关键：在 WSL 里编译前务必清理 PATH！"
echo "    你的 shell 若含 Windows 挂载路径（/mnt/c/Program Files (x86)/...），"
echo "    OpenWrt 会把它拼进 uboot 子 make 的 PATH=...，其中 '(' 导致："
echo "      bash: -c: line 1: syntax error near unexpected token '('"
echo "    务必用精简 PATH 启动 make（下面这条已带干净 PATH 前缀，直接复制）："
echo "  PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin make -j\$(nproc)"
echo "  # 或者先执行： export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
