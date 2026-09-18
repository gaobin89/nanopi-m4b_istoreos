#!/bin/bash
# 在 WSL 中编译 iStoreOS（NanoPi M4B）的安全包装器。
#
# 用法（在 istoreos 源码根目录执行）：
#   bash 25.12/build.sh -j$(nproc)
#   bash 25.12/build.sh -j$(nproc) V=s
# 或直接透传任意 make 参数：
#   bash 25.12/build.sh menuconfig
#
# 作用：
#   1) 清理 PATH（去掉 WSL 挂载的 Windows 路径 /mnt/c/Program Files (x86)/...）。
#      否则 OpenWrt 会把环境 PATH 重新拼进 uboot 子 make 的 PATH=... 里，
#      其中 '(' 会被 bash 当成子shell开头，导致：
#        bash: -c: line 1: syntax error near unexpected token '('
#      这正是 nanopi-m4b-rk3399 的 U-Boot 首次编译报错的根因。
#   2) 自愈 + 断言：在 make 前强制把 curl 后端设为 mbedTLS、显式保 libmbedtls、
#      确认 M4B 设备已选；不满足则拒绝构建。
#
# 注意：本脚本只兜底关键构建项，完整套用（补丁、007、files/、wpad 冲突化解）
# 仍由 apply.sh 负责。首次或同步新补丁后，务必先 bash 25.12/apply.sh。

# 定位源码根目录（脚本位于 <源码根>/25.12/build.sh）
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IST="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$IST" || { echo "build.sh: 无法进入源码根目录 $IST"; exit 1; }
[ -d target/linux/rockchip ] || { echo "build.sh: $IST 不像 iStoreOS 源码树"; exit 1; }

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
# 防御：若 PATH 仍残留 Windows 挂载或括号（例如有人绕过本脚本裸跑 make），
# 提前给出可读报错并退出，避免再次出现难查的 uboot 子 make 语法错误。
if printf '%s' "$PATH" | grep -qE '/mnt/[a-zA-Z]|[()]'; then
  echo "build.sh: 致命 - PATH 仍含 Windows 挂载路径或括号字符，构建会在 U-Boot 处失败。" >&2
  echo "          请始终通过本脚本构建： bash 25.12/build.sh -j\$(nproc) V=s" >&2
  echo "          不要裸跑 make（WSL 默认 PATH 带 /mnt/c/Program Files (x86) 等）。" >&2
  exit 1
fi

# ---- 自愈：确保 .config 关键项正确（与 apply.sh 一致）----
if [ ! -f .config ]; then
  echo "build.sh: 致命 - 当前无 .config，请先运行： bash 25.12/apply.sh" >&2
  exit 1
fi

echo "==> build.sh 自愈：校验并修正 .config 关键项"
# curl 后端强制 mbedTLS（iStoreOS/OpenWrt 25.x 默认后端；openssl 符号无效会被回退）
sed -i '/^CONFIG_LIBCURL_OPENSSL=/d' .config
sed -i '/^CONFIG_LIBCURL_MBEDTLS=/d' .config
echo "CONFIG_LIBCURL_MBEDTLS=y" >> .config
# 显式保 libmbedtls（mbedTLS 3.x 一个包编出 libmbedtls/libmbedcrypto/libmbedx509
# 三个 .so；不存在独立的 libmbedcrypto / libmbedx509 kconfig 符号，勿写）
sed -i '/^CONFIG_PACKAGE_libmbedtls=/d' .config
echo "CONFIG_PACKAGE_libmbedtls=y" >> .config

# ---- 断言（任意一项不满足直接退出，绝不让构建跑到 curl 打包才崩）----
bad=0
if grep -q '^CONFIG_LIBCURL_MBEDTLS=y$' .config; then
  echo "  curl TLS 后端 = mbedTLS ok"
else
  echo "  !! 致命：curl 后端不是 mbedTLS（LIBCURL_MBEDTLS 未生效）" >&2
  bad=1
fi
if grep -q '^CONFIG_PACKAGE_libmbedtls=y$' .config; then
  echo "  libmbedtls=y ok（编出 libmbedtls/libmbedcrypto/libmbedx509 三个 .so，libcurl 依赖）"
else
  echo "  !! 致命：libmbedtls 未选，libcurl 打包将报 missing dependencies" >&2
  bad=1
fi
if grep -q '^CONFIG_TARGET_DEVICE_rockchip_armv8_DEVICE_friendlyarm_nanopi-m4b=y$' .config; then
  echo "  M4B 设备已选 ok"
else
  echo "  !! 致命：.config 未选 M4B 设备（请先 bash 25.12/apply.sh）" >&2
  bad=1
fi
if [ "$bad" -ne 0 ]; then
  echo "build.sh: 因上述致命项拒绝构建。请先执行： bash 25.12/apply.sh" >&2
  exit 1
fi

# ---- 强制重建包元数据索引（25.12 CI 失败根因修复）----
# feeds install -a 内部会先跑一遍 make 元数据扫描（"Collecting target info"），
# 但此刻 feed 包的 symlink 尚未建立，于是写入的 tmp/.packageinfo 缺少
# curl / libgcrypt / luci-lua-runtime / luci-theme-argon / attr 等包。
# 后续 build.sh 的 make 复用这份陈旧索引（不会重新扫描），oldconfig 把这些包
# 当未知符号丢弃（连种子里显式 =y 的 libgcrypt 也被剥），package/install 阶段
# opkg 报 "no such package" → Error 9 → world Error 2。
# 本地 WSL 构建树是持久化的，tmp/.packageinfo 早就在 symlink 建好后生成、是完整的，
# 所以本地能过、CI 崩——差异在“包树/索引状态”，不在主机 OS（两边都是 ubuntu-24.04）。
# 修复：在 make 前清掉陈旧索引缓存，此时 symlink 已就位，make 会重新扫描出完整索引。
echo "==> build.sh 自愈：清除陈旧包索引缓存，强制 make 重建完整 tmp/.packageinfo"
rm -f tmp/.packageinfo tmp/.packages tmp/.config-package.in tmp/info/.packages 2>/dev/null \
  && echo "  已删除陈旧 tmp/.packageinfo 等（下次 make 将重新扫描全部已安装 feed 包）" || true

echo "==> 启动 make $*"
exec make "$@"
