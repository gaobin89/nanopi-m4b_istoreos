#!/bin/bash
# 在 WSL 中编译 iStoreOS（NanoPi M4B）的安全包装器。
#
# 用法（在 istoreos 源码根目录执行）：
#   bash ~/istoreos/24.10/build.sh defconfig
#   bash ~/istoreos/24.10/build.sh -j$(nproc)
# 或直接透传任意 make 参数：
#   bash ~/istoreos/24.10/build.sh menuconfig
#
# 作用：清理 PATH（去掉 WSL 挂载的 Windows 路径 /mnt/c/Program Files (x86)/...）。
# 否则 OpenWrt 会把环境 PATH 重新拼进 uboot 子 make 的 PATH=... 里，
# 其中 '(' 会被 bash 当成子shell开头，导致：
#   bash: -c: line 1: syntax error near unexpected token '('
# 这正是 nanopi-m4b-rk3399 的 U-Boot 首次编译报错的根因。
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# 定位源码根目录（脚本位于 <源码根>/24.10/build.sh）
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IST="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$IST" || { echo "build.sh: 无法进入源码根目录 $IST"; exit 1; }
[ -d target/linux/rockchip ] || { echo "build.sh: $IST 不像 iStoreOS 源码树"; exit 1; }

# 防御：若 PATH 仍残留 Windows 挂载或括号（例如有人绕过本脚本裸跑 make），提前给出可读报错。
if printf '%s' "$PATH" | grep -qE '/mnt/[a-zA-Z]|[()]'; then
  echo "build.sh: 致命 - PATH 仍含 Windows 挂载路径或括号字符，构建会在 U-Boot 处失败。" >&2
  echo "          请始终通过本脚本构建： bash 24.10/build.sh -j\$(nproc) V=s" >&2
  exit 1
fi

if [ ! -f .config ]; then
  echo "build.sh: 致命 - 当前无 .config，请先运行： bash 24.10/apply.sh" >&2
  exit 1
fi

# ---- 断言（M4B 设备必须已选，否则构建毫无意义）----
if grep -q '^CONFIG_DEVICE_friendlyarm_nanopi-m4b=y$' .config; then
  echo "  M4B 设备已选 ok"
else
  echo "  !! 致命：.config 未选 M4B 设备（请先 bash 24.10/apply.sh）" >&2
  exit 1
fi

# ---- 强制重建包元数据索引（24.10 CI 失败根因修复，与 25.12 同源）----
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
