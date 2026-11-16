#!/bin/bash
# Builds and installs katok from a local cheng80/katok checkout.
# Usage: scripts/install-katok.sh <katok-checkout> [install-dir]

set -euo pipefail

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    echo "사용법: $0 <katok 체크아웃 경로> [설치 디렉터리]" >&2
    exit 1
fi

if [ "$(uname -s)" != Darwin ] || [ "$(uname -m)" != arm64 ]; then
    echo "이 katok 빌드는 Apple Silicon Mac에서 지원합니다." >&2
    exit 1
fi

if [ ! -f "$1/Cargo.toml" ]; then
    echo "katok 체크아웃에서 Cargo.toml을 찾지 못했습니다: $1" >&2
    exit 1
fi

INSTALL_DIR="${2:-/opt/homebrew/bin}"
if [ ! -d "$INSTALL_DIR" ] || [ ! -w "$INSTALL_DIR" ]; then
    echo "설치 디렉터리가 없거나 쓰기 권한이 없습니다: $INSTALL_DIR" >&2
    exit 1
fi

KATOK_SOURCE="$(cd "$1" && pwd -P)"
cargo build --manifest-path "$KATOK_SOURCE/Cargo.toml" \
    --target-dir "$KATOK_SOURCE/target" --locked --release --bin katok

BINARY="$KATOK_SOURCE/target/release/katok"
"$BINARY" --version
install -m 755 "$BINARY" "$INSTALL_DIR/katok"
echo "설치 완료: $INSTALL_DIR/katok"
