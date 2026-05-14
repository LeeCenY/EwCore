#!/usr/bin/env bash
# Builds EverywhereCore.xcframework via gomobile bind. The output is a
# fat xcframework with ios-arm64, ios-arm64_x86_64-simulator, and
# macos-arm64_x86_64 slices — one binary serves both Apple-platform
# consumers.
#
# The three core dependencies (mihomo, sing-box, xray-core) are
# resolved from the Go module proxy via go.mod, not vendored. Upstream
# version bumps land here through .github/workflows/upstream-watch.yml.
#
# gomobile produces a *static* framework — the binary inside .framework
# is an `ar` archive, not a Mach-O dylib. dsymutil cannot process that,
# so we strip Go-side debug info via -ldflags="-s -w" instead. Result:
# no dSYM is needed (or expected by Apple's archive validator), and
# the framework is also smaller. The trade-off is no Go stack
# symbolication in crash reports — but Go panics surface inside the
# runtime's own panic handler and rarely show up in Apple crash
# reports anyway.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE_DIR="$ROOT/go"
OUT="$ROOT/EverywhereCore.xcframework"

GOPATH="$(go env GOPATH)"
GOBIN="$GOPATH/bin"
PATH="$GOBIN:$PATH"
export PATH

if ! command -v gomobile >/dev/null 2>&1; then
    echo "→ installing gomobile + gobind"
    go install golang.org/x/mobile/cmd/gomobile@latest
    go install golang.org/x/mobile/cmd/gobind@latest
fi

cd "$CORE_DIR"
echo "→ go mod tidy"
go mod tidy

# Build tags enable optional features in upstream cores. We ship the
# subset that makes sense for an iOS NEPacketTunnelProvider client —
# inbound/server-only tags and big-tree extras (tailscale, anthropic/
# openai SDK service registries, ACME issuance, v2ray stats gRPC,
# DHCP DNS probing) are dropped. See PATCHES.md for the rationale.
BUILD_TAGS="\
with_clash_api \
with_grpc \
with_gvisor \
with_quic \
with_utls \
with_wireguard"

# -s: strip Go symbol table.  -w: strip DWARF.  Together they remove
# both the metadata Apple's archive validator wants a dSYM for and a
# noticeable chunk of binary size.
LDFLAGS="-s -w"

echo "→ gomobile bind tags=$BUILD_TAGS"
rm -rf "$OUT"
gomobile bind \
    -target=ios,iossimulator,macos \
    -tags="$BUILD_TAGS" \
    -ldflags="$LDFLAGS" \
    -o "$OUT" .

echo "✓ built $OUT"
du -sh "$OUT"
