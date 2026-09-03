#!/bin/bash
# 在 WSL 中编译 iStoreOS（NanoPi M4B）的安全包装器。
#
# 用法（在 istoreos 源码根目录执行）：
#   bash ~/istoreos/all-patches/build.sh defconfig
#   bash ~/istoreos/all-patches/build.sh -j$(nproc)
# 或直接透传任意 make 参数：
#   bash ~/istoreos/all-patches/build.sh menuconfig
#
# 作用：清理 PATH（去掉 WSL 挂载的 Windows 路径 /mnt/c/Program Files (x86)/...）。
# 否则 OpenWrt 会把环境 PATH 重新拼进 uboot 子 make 的 PATH=... 里，
# 其中 '(' 会被 bash 当成子shell开头，导致：
#   bash: -c: line 1: syntax error near unexpected token '('
# 这正是 nanopi-m4b-rk3399 的 U-Boot 首次编译报错的根因。
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
exec make "$@"
