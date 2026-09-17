#!/bin/bash
# NanoPi M4B (RK3399) iStoreOS 25.12 适配：一键套用全部补丁与覆盖层
#
# 用法：
#   bash ~/istoreos/25.12/apply.sh ~/istoreos
# 或（脚本自动把自身所在目录当作 PATCHES，ISTOREOS 默认 ~/istoreos）：
#   bash apply.sh
#
# 与 24.10 适配的差异（本脚本已据此调整）：
#   - 内核 6.6 -> 6.12（config 文件为 config-6.12）
#   - mac80211 backports 6.12.96 -> 6.18.26（brcmfmac 来自此，880-01 仍适用）
#   - U-Boot 2024.10 -> 2025.10：SPL IO-domain 软重启修复（24.10 的 300-303）
#     已在 U-Boot 2025.10 上游化，故 25.12 丢弃 300-303，仅保留 002（注册 M4B U-Boot 变体）。
#   - 6.12 内核移除了 CONFIG_FRAMEBUFFER_CONSOLE（fbcon 改为 DRM fbdev client），
#     故 007 不再注入该符号，改为依赖 CONFIG_DRM_FBDEV_EMULATION=y 提供 HDMI 控制台。
#   - 24.10 的 005/880-01 对 25.12 仍逐字适用（已 git apply --check 验证）。
#
# 补丁职责：
#   - 001 / 002 【必需，不可删】：M4B 设备与 U-Boot 并未合入 istoreos-25.12 上游。
#       已用 25.12 上游 armv8.mk / uboot-rockchip/Makefile 验证 clean 基线两者均无
#       nanopi-m4b。全新 clone 必须先 git apply 001 / 002 才能编译出 M4B 镜像。
#   - 005【WiFi 必需】：新增 AP6256(BCM43456) 固件包
#       package/firmware/brcmfmac-firmware-43456，从 armbian/firmware 固定 commit
#       拉取 brcmfmac43456-sdio.{bin,txt,clm_blob} 安装到 /lib/firmware/brcm/。
#       原 001 误把固件包名写成 4356（M4/M4V2/T4 的 AP6356S 才用），M4B 必须 43456。
#   - 003(modules.mk) + 007(config-6.12 inline)：HDMI 显示栈 built-in（rk3399 VOP +
#       inno HDMI phy + DRM fbdev 控制台），与 004(default.bootscript) 协同。
#   - 004：kernel cmdline 加 console=tty0，让 HDMI 屏出现虚拟控制台。
#
# files/ 覆盖层：
#   - 91-hdmi-console-tty1：首启向 /etc/inittab 追加 tty1 getty（HDMI 登录控制台）。
#   - etc/modprobe.d/brcmfmac.conf：feature_disable=0x28A000(roamoff=1) 为崩溃的
#     【兜底】层修复，关闭 FWSUP(bit13)/SAE(bit19)/DUMP_OBSS(bit21)/MONITOR_FLAG(bit15)。
#     但真正根因是 armbian 随附的 2017 固件 7.45.96.2 在 AP 模式 "known to crash"，
#     仅靠关闭功能位无法根除；彻底修复靠 005 补丁把 .bin 换成 RPi 7.84.17.1（见 005 注释）。

set -u

IST="${1:-$HOME/istoreos}"
IST="$(eval echo "$IST")"
PATCHES="$(cd "$(dirname "$0")" && pwd)"   # 本脚本所在目录 = 25.12

echo "ISTOREOS = $IST"
echo "PATCHES  = $PATCHES"
cd "$IST" || { echo "错误：无法进入 $IST"; exit 1; }
[ -d target/linux/rockchip ] || { echo "错误：$IST 不像 iStoreOS 源码树（缺 target/linux/rockchip）"; exit 1; }

# ---- 0) 净化 PATH + 重置源码到 origin/istoreos-25.12 最新 + 清理受影响产物 ----
echo "==> [1/6] 净化 PATH、重置源码到 origin/istoreos-25.12 最新、清理受影响产物"
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "错误：$IST 不是 git 仓库，停止"; exit 1; }
git fetch --all --tags 2>&1 | tail -n 3 || echo "  (fetch 失败，离线模式：仅重置本地)"
TARGET=""
if git rev-parse --verify "origin/istoreos-25.12" >/dev/null 2>&1; then
  TARGET="origin/istoreos-25.12"
elif UP=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null); [ -n "$UP" ]; then
  TARGET="$UP"
fi
if [ -n "$TARGET" ]; then
  echo "  -> git reset --hard $TARGET"
  git reset --hard "$TARGET"
else
  echo "  -> 未找到 origin/istoreos-25.12 且未配置 upstream，git reset --hard HEAD"
  git reset --hard HEAD
fi
# 仅移除验证残留(保留 build_dir/staging_dir/bin/dl/.ccache/feeds/tmp/25.12)
git clean -ffdx -e build_dir -e staging_dir -e bin -e dl -e .ccache -e feeds -e tmp -e 25.12
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
# 强制刷新固件下载缓存：005 把 .bin 源从 armbian 切到 RPi，但文件名未变，
# OpenWrt 的 dl/.brcmfmac43456-sdio.bin.ok 戳记按文件名记、不按 hash 复核，旧戳在时
# 会复用缓存里的旧 .bin 而不重下（HASH 钉死也拦不住，戳记优先级更高）。
# 清掉 .bin 与其 .ok 戳，强制下次 make 重新下载 RPi 固件源。
rm -f dl/brcmfmac43456-sdio.bin dl/brcmfmac43456-sdio.txt dl/brcmfmac43456-sdio.clm_blob \
      dl/.brcmfmac43456-sdio.bin.ok dl/.brcmfmac43456-sdio.txt.ok dl/.brcmfmac43456-sdio.clm_blob.ok 2>/dev/null \
   && echo "  已清理 dl/ 旧 43456 固件缓存（强制重下 RPi 源）" || true
# 强制刷新 OpenWrt 包数据库缓存：005 新建的 package/firmware/brcmfmac-firmware-43456
# 若因 tmp/.packageinfo 比该 Makefile 新而被扫描器跳过，下面这条能让 make 重新扫描并登记，
# 否则 CONFIG_PACKAGE_brcmfmac-firmware-43456-sdio=y 会被 syncconfig 当未知符号剥掉。
rm -f tmp/.packageinfo tmp/.packages tmp/.config-package.in 2>/dev/null && echo "  已删除陈旧 tmp/.packageinfo（强制下次 make 重新扫描包）" || true

# ---- 2) 007 inline：config-6.12 显示栈 built-in（HDMI，rk3399）----
echo "==> [3/6] 007 inline：config-6.12 显示栈 built-in"
python3 - <<'PY'
import re
p="target/linux/rockchip/armv8/config-6.12"
want={
 "CONFIG_PHY_ROCKCHIP_INNO_HDMI":"y",   # rk3399 HDMI PHY（AP6256 走 inno HDMI）
 "CONFIG_DRM":"y",
 "CONFIG_DRM_ROCKCHIP":"y",
 "CONFIG_ROCKCHIP_IOMMU":"y",
 "CONFIG_ROCKCHIP_VOP":"y",             # rk3399 用 VOP1（VOP2 为 rk3568/rk3588）
 "CONFIG_ROCKCHIP_VOP2":"n",
 "CONFIG_ROCKCHIP_DW_HDMI":"y",
 "CONFIG_ROCKCHIP_DW_HDMI_QP":"n",
 "CONFIG_DRM_DISPLAY_CONNECTOR":"y",
 "CONFIG_DRM_FBDEV_EMULATION":"y",      # 6.12 的帧缓冲控制台由 DRM fbdev client 提供
 "CONFIG_FB":"y",
 # 注意：6.12 已移除 CONFIG_FRAMEBUFFER_CONSOLE（fbcon 改为 DRM fbdev client），
 # 故此处不再注入，避免 oldconfig 报 unknown symbol。tty0 控制台靠上面
 # DRM_FBDEV_EMULATION=y + 004 的 console=tty0 实现。
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
print("  007 applied (HDMI display stack built-in, 6.12)")
PY

# ---- 3) 安全体检：config-6.12 不应被注入内核无线符号 ----
echo "==> [4/6] 内核 kconfig 无线符号体检（WiFi 走 backports，不进内核 kconfig）"
python3 - <<'PY'
import re
p="target/linux/rockchip/armv8/config-6.12"
watch=("CONFIG_CFG80211","CONFIG_MAC80211","CONFIG_BRCMUTIL","CONFIG_BRCMFMAC")
bad=[ln for ln in open(p).read().splitlines()
     if re.match(r'^#?\s*(%s)\s*=' % "|".join(watch), ln)]
if bad:
    print("  !! 残留内核无线符号，必须删除：")
    for ln in bad: print("     "+ln)
else:
    print("  ok（brcmfmac 由 mac80211 backports 6.18.26 提供，内核 kconfig 保持上游原样）")
PY

# ---- 4) 补丁落盘：mac80211 backports brcmfmac(880) ----
echo "==> [5/6] cp 880-* -> package/kernel/mac80211/patches/brcm/"
mkdir -p package/kernel/mac80211/patches/brcm
cp "$PATCHES"/880-*.patch package/kernel/mac80211/patches/brcm/
echo "  已复制 880-*（brcmfmac AP 模式 station signal 修复，适配 6.18.26）"

# ---- 5) files/ 覆盖层 + feeds.r4se + config.r4se ----
echo "==> [6/6] cp files/ 覆盖层 + feeds.r4se + config.r4se"
mkdir -p files
cp -rf "$PATCHES"/files/. files/
cp "$PATCHES/feeds.r4se" feeds.conf.default
rm -f feeds.conf
[ -e .config ] && mv -f .config .config.orig
cp "$PATCHES/config.r4se" .config

# wpad 冲突化解（与 24.10 一致）：官方 25.12 buildinfo 同时选了
#   CONFIG_PACKAGE_wpad-basic-mbedtls=m 与 CONFIG_PACKAGE_hostapd-openssl=y，
# 二者都 PROVIDES hostapd 虚拟包，会导致 package/install 阶段依赖冲突。
# 这里统一为 wpad-openssl（同时提供 hostapd + wpa-supplicant，支持 AP 与 Client），
# 并取消与之冲突的两个包，保证 M4B 镜像可正常出 AP+Client。
echo "==> [6/6] wpad 冲突化解：统一为 wpad-openssl"
sed -i 's/^CONFIG_PACKAGE_wpad-basic-mbedtls=.*/# CONFIG_PACKAGE_wpad-basic-mbedtls is not set/' .config
sed -i 's/^CONFIG_PACKAGE_hostapd-openssl=.*/# CONFIG_PACKAGE_hostapd-openssl is not set/' .config
# wpad-openssl 已统一提供 hostapd 与 wpa-supplicant 两个虚拟包，
# 故显式选中的 wpa-supplicant-openssl 会与它在 wpa-supplicant 虚拟包上冲突，必须取消，
# 否则 final image 打包阶段会报 "multiple providers for wpa-supplicant" 而失败。
sed -i 's/^CONFIG_PACKAGE_wpa-supplicant-openssl=.*/# CONFIG_PACKAGE_wpa-supplicant-openssl is not set/' .config
sed -i '/^CONFIG_PACKAGE_wpad-openssl=/d' .config
echo "CONFIG_PACKAGE_wpad-openssl=y" >> .config

# ---- mbedTLS（关键）----
# 25.x 的 libcurl / px5g-mbedtls 链接 mbedTLS 的三个 .so：
#   libmbedtls.so.NN / libmbedcrypto.so.NN / libmbedx509.so.NN
# 三者全部由 OpenWrt 的 libmbedtls 包（mbedTLS 3.x）一次性编出——
# 该包的 Makefile 同时安装这三个 .so，并不存在独立的
# Package/libmbedcrypto / Package/libmbedx509 kconfig 符号。
# 故只需显式选中 CONFIG_PACKAGE_libmbedtls=y；切勿写
# libmbedcrypto / libmbedx509 的 =y（它们是幽灵符号，会被 syncconfig
# 剥掉，反而导致每次 menuconfig 弹“配置已更新”）。
# 取消 wpad-basic-mbedtls 后传递依赖起点丢失，必须显式保 libmbedtls。
sed -i '/^CONFIG_PACKAGE_libmbedtls=/d' .config
echo "CONFIG_PACKAGE_libmbedtls=y" >> .config

# curl TLS 后端：iStoreOS/OpenWrt 25.x 默认且唯一稳定的是 mbedTLS（CONFIG_LIBCURL_MBEDTLS）。
# curl 实际只编译 mbedTLS 后端，LIBCURL_OPENSSL 符号会被 oldconfig 丢弃并回退默认 mbedTLS，
# 故显式选 mbedTLS 后端，让 curl 的 libmbedtls 依赖正确建立，与系统其余
# （px5g-mbedtls / ustream-mbedtls）保持一致，体积也最小。
sed -i '/^CONFIG_LIBCURL_OPENSSL=/d' .config
sed -i '/^CONFIG_LIBCURL_MBEDTLS=/d' .config
echo "CONFIG_LIBCURL_MBEDTLS=y" >> .config

# ---- 校验（curl 后端 / libmbedtls 为致命项，缺失直接退出）----
echo "==> 校验"
grep -nE "CONFIG_PHY_ROCKCHIP_INNO_HDMI=|CONFIG_DRM_ROCKCHIP=|CONFIG_ROCKCHIP_VOP=" target/linux/rockchip/armv8/config-6.12
ls package/kernel/mac80211/patches/brcm/ | grep -E "^880-" && echo "  880-* ok（brcmfmac AP 模式 station signal 修复）"
grep -q "CONFIG_TARGET_DEVICE_rockchip_armv8_DEVICE_friendlyarm_nanopi-m4b=y" .config && echo "  M4B 设备已选 ok" || echo "  !! .config 未选 M4B 设备"

# curl 后端必须是 mbedTLS（iStoreOS/OpenWrt 25.x 默认后端），openssl 符号无效会被回退
if grep -q "^CONFIG_LIBCURL_MBEDTLS=y\$" .config; then
  echo "  curl TLS 后端 = mbedTLS ok（iStoreOS 默认后端，libmbedtls 依赖链成立）"
else
  echo "  !! 致命：curl TLS 后端不是 mbedTLS（LIBCURL_MBEDTLS 未生效），libcurl 依赖链会断"
  exit 1
fi
# libmbedtls 必须构建（它一个包就编出 libmbedtls/libmbedcrypto/libmbedx509
# 三个 .so，libcurl / px5g 的 mbedTLS 依赖全靠它）。幽灵符号 libmbedcrypto /
# libmbedx509 不应出现，若出现说明 kconfig 漂移、会被剥掉——这里只认 libmbedtls。
if grep -q "^CONFIG_PACKAGE_libmbedtls=y\$" .config; then
  echo "  libmbedtls=y ok（提供 libmbedtls/libmbedcrypto/libmbedx509 .so，libcurl/px5g 依赖）"
else
  echo "  !! 致命：libmbedtls 未选（libcurl 打包将报 missing dependencies for libmbedcrypto.so.*）"
  exit 1
fi
test -f files/etc/uci-defaults/91-hdmi-console-tty1 && echo "  files/ 覆盖层(91-hdmi-console-tty1) 已就位 ok" || echo "  !! files/ 覆盖层缺失（91-hdmi-console-tty1 未复制）"
test -f files/etc/modprobe.d/brcmfmac.conf && echo "  files/ 覆盖层(brcmfmac.conf) 已就位 ok" || echo "  !! files/ 覆盖层缺失（brcmfmac.conf 未复制）"

# WiFi 固件包必须显式选中：CONFIG_ALL_KMODS=y 仅覆盖 kmod-* 内核模块，
# 不会自动选 firmware 类固件包；漏选会导致 brcmfmac 加载固件 -2(ENOENT)、
# HT clock 超时、整板无 WiFi（25.12 首编即因此缺失，24.10 因配置已选而正常）。
sed -i '/^CONFIG_PACKAGE_brcmfmac-firmware-43456-sdio=/d' .config
echo "CONFIG_PACKAGE_brcmfmac-firmware-43456-sdio=y" >> .config
echo "==> WiFi 栈校验"
for k in kmod-brcmfmac kmod-cfg80211 kmod-mac80211 kmod-brcmutil \
         brcmfmac-firmware-43456-sdio wpad-openssl wifi-scripts \
         wireless-regdb iw iwinfo; do
  if   grep -q "^CONFIG_PACKAGE_${k}=y\$" .config; then echo "  ${k}=y ok（打进镜像）";
  elif grep -q "^CONFIG_PACKAGE_${k}=m\$" .config; then echo "  ${k}=m ok（模块，打进镜像）";
  else echo "  !! 缺 ${k}（旧版为 =y；若 ALL_KMODS=y 则 brcmfmac 以 =m 提供，可忽略 kmod-*）"; fi
done
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
echo "  # 不跑 make defconfig：官方 buildinfo 含大量显式 =y 包，defconfig 会将其重置为 n"
echo "  # 交给 build.sh 的 make 走 oldconfig，与本地流程一致，保住全部显式 =y 包。"
echo "  PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin make -j\$(nproc)"
echo
echo "  ★ 关键：在 WSL 里编译前务必清理 PATH！"
echo "    你的 shell 若含 Windows 挂载路径（/mnt/c/Program Files (x86)/...），"
echo "    OpenWrt 会把它拼进 uboot 子 make 的 PATH=...，其中 '(' 导致："
echo "      bash: -c: line 1: syntax error near unexpected token '('"
echo "    务必用精简 PATH 启动 make（build.sh 已带干净 PATH 前缀）。"

echo
echo "########## 构建前必做核对 ##########"
echo "在 WSL 的 ~/istoreos 下执行："
echo "  grep -nE '^CONFIG_LIBCURL_MBEDTLS=|^CONFIG_PACKAGE_libmbedtls=' .config"
echo "必须看到："
echo "  CONFIG_LIBCURL_MBEDTLS=y      <-- curl 默认 mbedTLS 后端"
echo "  CONFIG_PACKAGE_libmbedtls=y   <-- 一个包就编出 libmbedtls/libmbedcrypto/libmbedx509 三个 .so"
echo "且 不能 看到："
echo "  CONFIG_LIBCURL_OPENSSL=y      <-- 绝不能出现（iStoreOS curl 不识别，会回退 mbedTLS）"
echo "  CONFIG_PACKAGE_libmbedcrypto=y / libmbedx509=y  <-- 幽灵符号，不存在独立包，会被 syncconfig 剥掉"
