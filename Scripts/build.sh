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

# --- Symmetric varz patch -------------------------------------------------
# Two tailscale forks live in the dep graph: github.com/sagernet/tailscale
# (sing-box, gated on with_tailscale) and github.com/metacubex/tailscale
# (mihomo, unconditional). Each fork's tsweb/varz/init() registers five
# expvars with hardcoded names ("process_start_unix_time", "version",
# "go_version", "counter_uptime_sec", "gauge_goroutines"). expvar.Publish
# panics on duplicate names — two distinct module paths run two distinct
# init()s against the same process-global registry → boom on the second.
#
# We patch each fork in a writable copy of its module-cache source,
# prefix each published name with the fork's vendor so they coexist,
# and add `replace` directives so the build links the patched copies.
# Replaces are dropped on EXIT so go.mod stays clean in version control.
PATCHED_ROOT="$CORE_DIR/.patched"

cleanup_replaces() {
    go mod edit -dropreplace=github.com/sagernet/tailscale  2>/dev/null || true
    go mod edit -dropreplace=github.com/metacubex/tailscale 2>/dev/null || true
}
trap cleanup_replaces EXIT
# Start clean in case a prior interrupted run left a replace behind.
cleanup_replaces

echo "→ go mod tidy"
go mod tidy

apply_varz_patch() {
    local module="$1" prefix="$2" dirname="$3"
    local version
    version="$(go list -m -f '{{.Version}}' "$module" 2>/dev/null || true)"
    if [[ -z "$version" ]]; then
        echo "→ $module not in deps; skipping varz patch"
        return
    fi
    local gomodcache src dest
    gomodcache="$(go env GOMODCACHE)"
    src="$gomodcache/$module@$version"
    dest="$PATCHED_ROOT/$dirname@$version"
    if [[ ! -d "$src" ]]; then
        go mod download "$module@$version"
    fi
    # Cache by version: if already patched at this version, reuse.
    if [[ ! -f "$dest/tsweb/varz/varz.go" ]]; then
        rm -rf "$dest"
        mkdir -p "$dest"
        cp -R "$src/" "$dest/"
        chmod -R u+w "$dest"
        sed -i.bak \
            -e "s/expvar\.Publish(\"process_start_unix_time\"/expvar.Publish(\"${prefix}_process_start_unix_time\"/" \
            -e "s/expvar\.Publish(\"version\"/expvar.Publish(\"${prefix}_version\"/" \
            -e "s/expvar\.Publish(\"go_version\"/expvar.Publish(\"${prefix}_go_version\"/" \
            -e "s/expvar\.Publish(\"counter_uptime_sec\"/expvar.Publish(\"${prefix}_counter_uptime_sec\"/" \
            -e "s/expvar\.Publish(\"gauge_goroutines\"/expvar.Publish(\"${prefix}_gauge_goroutines\"/" \
            "$dest/tsweb/varz/varz.go"
        rm -f "$dest/tsweb/varz/varz.go.bak"
    fi
    go mod edit -replace "$module=$dest"
    echo "→ patched $module@$version (prefix=${prefix}_)"
}

apply_varz_patch github.com/sagernet/tailscale  sagernet  sagernet-tailscale
apply_varz_patch github.com/metacubex/tailscale metacubex metacubex-tailscale

# Build tags enable optional features in upstream cores. We ship the
# subset that makes sense for an iOS NEPacketTunnelProvider client —
# inbound/server-only tags and big-tree extras (anthropic/openai SDK
# service registries, ACME issuance, v2ray stats gRPC, DHCP DNS
# probing) are dropped. See PATCHES.md for the rationale.
BUILD_TAGS="\
with_clash_api \
with_grpc \
with_gvisor \
with_quic \
with_tailscale \
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
