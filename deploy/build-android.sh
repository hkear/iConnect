#!/bin/bash
# ============================================================
#  iConnect Android 交叉编译脚本(Windows git-bash / Linux 可用)
#  产出: target/aarch64-linux-android/{debug,release}/iconnectd
#  前置: rustup + NDK r26d + protoc(见 docs/android-port-plan.md 阶段1)
# ============================================================
set -e

# --- 1. 环境变量(按本机实际路径修改) ---
export PATH="/c/Users/Kay/.cargo/bin:$LOCALAPPDATA/Android/tools/bin:$PATH"
export NDK="${NDK:-$LOCALAPPDATA/Android/Sdk/android-ndk-r26d}"
export TOOLBIN="$NDK/toolchains/llvm/prebuilt/windows-x86_64/bin"
export PROTOC="${PROTOC:-$LOCALAPPDATA/Android/tools/bin/protoc.exe}"

# 注意: 链接器走 .cargo/config.toml 的 [target.aarch64-linux-android]
# (clang.exe + link-arg, 避免 NDK .cmd 包装器的 cmd 引号问题)
# 这里只设置 C 编译(cc crate / bindgen 用)
export CC_aarch64_linux_android="$TOOLBIN/aarch64-linux-android24-clang.cmd"
export AR_aarch64_linux_android="$TOOLBIN/llvm-ar"

# --- 2. 默认 features 减去 kcp(kcp-sys 需要 libclang, 暂缺) ---
FEATURES="wireguard,websocket,smoltcp,tun,socks5,quic,faketcp,magic-dns,zstd"

MODE="${1:-debug}"
shift || true
case "$MODE" in
  check)  cargo check  -p iconnectd --target aarch64-linux-android --no-default-features --features "$FEATURES" "$@" ;;
  release) cargo build -p iconnectd --target aarch64-linux-android --release --no-default-features --features "$FEATURES" "$@" ;;
  *)      cargo build -p iconnectd --target aarch64-linux-android --no-default-features --features "$FEATURES" "$@" ;;
esac

echo ""
echo "产出: target/aarch64-linux-android/$([ "$MODE" = release ] && echo release || echo debug)/iconnectd"
