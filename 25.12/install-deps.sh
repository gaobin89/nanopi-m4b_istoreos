#!/bin/bash
# iStoreOS 25.12 (NanoPi M4B / RK3399) 构建主机依赖安装脚本
#
# 适用：Debian / Ubuntu（含 WSL2 Ubuntu，即你的真实开发环境）
# 作用：一次性把编译 iStoreOS-25.12 所需的宿主工具装齐，并做可用性自检。
#
# 用法：
#   chmod +x install-deps.sh
#   ./install-deps.sh              # 默认 Ubuntu/Debian，用 sudo 装包
#   SUDO= ./install-deps.sh        # 已是 root 时，跳过 sudo 前缀
#
# 说明：
#   - iStoreOS 25.12 关键变化决定了一批依赖：
#       * 内核 6.12   -> 需要 libelf-dev / zlib1g-dev / flex / bison / bc / perl（内核与模块构建）
#       * mac80211 backports 6.18.26 以 .tar.zst 分发的形态被构建系统拉取 -> 需要 zstd
#       * U-Boot 2025.10 -> 需要 python3 / swig / make / perl / device-tree-compiler
#       * feeds / 工具链 -> 需要 git / rsync / file / unzip / wget / curl / ccache
#   - 本脚本只装「宿主工具」，不拉取源码树、不下载 dl。真正下载源码请用 apply.sh 配套流程。
#   - 在 WSL Ubuntu 里 git 是原生的，文件已是 LF，不存在 Windows Git Bash 的 autocrlf 污染，
#     无需额外设置 core.autocrlf。

set -euo pipefail

# ----------------------------------------------------------------------------
# 0. 运行环境与权限
# ----------------------------------------------------------------------------
SUDO="${SUDO:-sudo}"

if [ "$(id -u)" -eq 0 ]; then
  SUDO=""   # 已经是 root，去掉 sudo 前缀
fi

echo "==> 检测发行版 ..."
if [ -r /etc/os-release ]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  echo "    发行版: ${PRETTY_NAME:-$NAME $VERSION_ID}"
else
  echo "    警告: 未找到 /etc/os-release，按通用 Debian/Ubuntu 处理"
  ID=debian
fi

case "${ID:-debian}" in
  ubuntu|debian|linuxmint|raspbian|kali)
    PKG_MGR=apt
    ;;
  fedora|centos|rhel|rocky|almalinux)
    PKG_MGR=dnf
    ;;
  arch|manjaro)
    PKG_MGR=pacman
    ;;
  opensuse*|sles)
    PKG_MGR=zypper
    ;;
  *)
    echo "错误: 未支持的发行版 ID='${ID:-未知}'，请手动安装依赖或补充本脚本。" >&2
    exit 1
    ;;
esac

# ----------------------------------------------------------------------------
# 1. 依赖清单（按用途分组，仅 Ubuntu/Debian 的 apt 名）
# ----------------------------------------------------------------------------
# 编译工具链
TOOLCHAIN=(
  build-essential          # gcc g++ make 等
  clang                    # 部分包优先用 clang（可选但官方推荐）
  ccache                   # 命中缓存，大幅加速重编
  gcc-multilib g++-multilib # 32 位兼容（OpenWrt 工具链需要）
  patch quilt              # 补丁管理（套用 25.12 补丁集 / 调补丁时用）
  perl                     # U-Boot / 内核构建脚本依赖
  pkg-config
)

# 解释器与脚本依赖
INTERP=(
  python3
  python3-dev
  python3-distutils
  python3-setuptools
  python3-venv            # 25.12 构建流程中可能用到 venv
  python3-pyelftools      # 处理 ELF（部分镜像打包步骤）
)

# 内核 / 设备树 / 模块构建
KERNEL=(
  flex bison bc
  libncurses5-dev         # make menuconfig 终端界面
  libelf-dev              # 内核模块构建
  zlib1g-dev
  device-tree-compiler    # dtc，RK3399 DTB 生成
  libssl-dev              # 内核/工具链需要 openssl 头
)

# 网络与归档 / 下载
NET_ARC=(
  git
  rsync
  wget curl
  unzip
  file
  zstd                    # 6.18.26 backports 为 .tar.zst，构建系统需 zstd 解包
  xz-utils
  jq                      # 解析 JSON（可选，便于排错）
)

# 杂项（文档/打包，按需）
MISC=(
  gettext
  gawk
  intltool
  libfuse-dev
  squashfs-tools
  uglifyjs                # 部分 luci 资源压缩
)

ALL_DEPS=( "${TOOLCHAIN[@]}" "${INTERP[@]}" "${KERNEL[@]}" "${NET_ARC[@]}" "${MISC[@]}" )

# ----------------------------------------------------------------------------
# 2. 安装
# ----------------------------------------------------------------------------
echo "==> 更新软件包索引 ..."
$SUDO apt-get update -y

echo "==> 安装构建依赖（共 ${#ALL_DEPS[@]} 个）..."
$SUDO apt-get install -y "${ALL_DEPS[@]}"

# ----------------------------------------------------------------------------
# 3. 可用性自检
# ----------------------------------------------------------------------------
echo "==> 校验关键工具版本 ..."
check() {
  local name="$1"; shift
  if command -v "$name" >/dev/null 2>&1; then
    local ver
    ver=$("$@" 2>&1 | head -1)
    printf "  [OK]   %-14s %s\n" "$name" "${ver:-present}"
  else
    printf "  [MISS] %-14s 未找到，请检查上面的安装日志\n" "$name"
    return 1
  fi
}

RC=0
check gcc gcc --version           || RC=1
check g++ g++ --version           || RC=1
check make make --version         || RC=1
check git git --version           || RC=1
check python3 python3 --version   || RC=1
check flex flex --version         || RC=1
check bison bison --version       || RC=1
check ccache ccache --version     || RC=1
check dtc dtc --version           || RC=1
check zstd zstd --version         || RC=1
check rsync rsync --version       || RC=1

# Python 版本建议 >= 3.10（25.12 构建脚本依赖较新语法）
pyver=$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null || echo "0.0")
echo "    检测到 python3 版本: $pyver"
if awk "BEGIN{exit !($pyver < 3.10)}"; then
  echo "    提示: python3 < 3.10，可能与 25.12 构建流程不兼容，建议升级到 3.10+。"
fi

# ----------------------------------------------------------------------------
# 4. 可选建议（不强制）
# ----------------------------------------------------------------------------
echo ""
echo "==> 完成。接下来在 iStoreOS 源码树中："
echo "   1) 把本目录(25.12)放到源码树内，或按需 cp 到 WSL 仓库："
echo "      //wsl.localhost/Ubuntu/home/gaobin/nanopi-m4b_istoreos/25.12/"
echo "   2) 套用补丁与覆盖层："
echo "      bash 25.12/apply.sh            # 默认 ISTOREOS=~/istoreos（可传参覆盖）"
echo "   3) 更新并安装 feeds："
echo "      ./scripts/feeds update -a -f && ./scripts/feeds install -a"
echo "   4) 载入配置并构建："
echo "      cp 25.12/config.r4se .config && make defconfig"
echo "      bash 25.12/build.sh            # 或: make -j\$(nproc)"
echo ""
echo "==> 提示：WSL 经 9P 挂载 Windows 目录时 IO 很慢，建议把源码树放在 WSL 原生"
echo "    ext4 路径（如 ~/nanopi-m4b_istoreos）而非 /mnt/c/ 下，可显著加速编译。"
echo ""

exit $RC
