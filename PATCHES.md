# Patches

Ledger of wiring quirks and gomobile mechanics that make the three
upstreams co-exist in one Go module. The cores themselves are unpatched
— if that ever changes, see "Future source patches" at the bottom.

Pinned versions live in `go/go.mod`. The daily upstream-watch workflow
keeps them current; see `README.md` for the release flow.

## go.mod overrides (`go/go.mod`)

### tools.go to anchor `golang.org/x/mobile/bind`

`gomobile bind` invokes `gobind` from a temporary directory, and `gobind`
imports `golang.org/x/mobile/bind`. In module mode, that import has to
appear somewhere in our module's import graph for `go list` to find it.
`go/tools.go` does so under `//go:build tools`, so the package never
compiles into the framework but `go.mod` keeps the require.

**On upstream bump.** No action — this is a gomobile mechanic.

### `-ldflags="-s -w"` so archive validation doesn't demand a dSYM

`Scripts/build.sh` strips Go-side debug info via `-ldflags="-s -w"`
(`-s` = strip symbol table, `-w` = strip DWARF). With no DWARF in the
binary the validator does not look for a dSYM and the warning goes
away. Side effects:

- Framework is much smaller.
- No Go-side symbolication in Apple crash reports.

**On upstream bump.** No action — this is a gomobile mechanic.

## Source patches

None. Xray-core, sing-box, and mihomo all build unmodified from their
published Go-module tags. See "Future source patches" if that ever
needs to change.

## Wiring quirks per core

These are not patches but call-site requirements that the wrappers in
`go/` already encode. Listed here so they survive a future rewrite.

### TUN inbound: each core consumes the utun fd directly

We don't ship a userland tun→socks bridge. Each core owns its own TUN
inbound, with the FD plumbed differently:

- **Xray-core**: read from the `xray.tun.fd` env var (see
  `proxy/tun/tun_darwin.go`). `go/xray.go` sets it before
  `core.StartInstance`.
- **sing-box**: read via an `adapter.PlatformInterface` whose
  `OpenInterface` is invoked by the tun inbound. The interface is
  registered on the `box.Options.Context` via
  `service.ContextWith[adapter.PlatformInterface]`. See
  `go/singbox.go` for the minimal implementation; only
  `OpenInterface`, `UnderNetworkExtension` and the
  `CreateDefaultInterfaceMonitor` no-op stub do meaningful work.
- **mihomo**: written into `cfg.General.Tun.FileDescriptor` between
  `executor.ParseWithBytes` and `hub.ApplyConfig`. The wire-level
  YAML key is `tun.file-descriptor`, but we keep the FD out of the
  config string so users can't accidentally pin a stale value.

For sing-box and mihomo we `syscall.Dup` the FD before handing it to
sing-tun — its `Close()` always closes the wrapped `os.File`, so a
non-dup'd path would tear down NEPacketTunnelFlow's underlying utun
out from under the Network Extension. Xray's darwin tun path checks
`ownsFd` and skips `Close()` when the FD came in externally, so we
don't dup there.

### Xray-core: needs `_ "main/distro/all"` and `_ "main/json"`

`distro/all` registers every inbound/outbound/transport via init().
`main/json` registers the JSON config loader and transitively pulls
in `infra/conf` and `proxy/tun`, which is what registers the `tun`
inbound type in the JSON loader's protocol map.
`core.StartInstance("json", …)` fails without both. See
`go/xray.go`.

### sing-box: gomobile bind needs `-tags=with_*`

sing-box keeps optional subsystems behind Go build tags. With no tag
set, the corresponding `*_stub.go` files compile in and the feature
returns "not included in this build" errors at runtime.

`Scripts/build.sh` enables the full sing-box tag matrix minus three
known-broken-on-Apple-platforms or known-deprecated tags (see
exclusions below). The advertised list is reproducible — re-derive it
any time against the module cache:

```bash
( cd go && go mod download github.com/sagernet/sing-box )
grep -rh '^//go:build' "$(go env GOMODCACHE)/github.com/sagernet/sing-box@$(awk '/sing-box v/{print $2; exit}' go/go.mod)/" \
  | grep -oE 'with_[a-zA-Z0-9_]+' | sort -u
```

Currently shipped (12):

| Tag                   | Unlocks                                        |
| --------------------- | ---------------------------------------------- |
| `with_acme`           | ACME certificate provisioning for inbounds     |
| `with_ccm`            | Apple-CCM service registry                     |
| `with_clash_api`      | clash REST/WebSocket API (yacd talks to this)  |
| `with_dhcp`           | DHCP DNS transport                             |
| `with_grpc`           | gRPC transport                                 |
| `with_gvisor`         | gVisor netstack for TUN inbound                |
| `with_ocm`            | Outbound Connection Management                 |
| `with_quic`           | QUIC transports — Hysteria/Hysteria2/TUIC      |
| `with_tailscale`      | Tailscale endpoint                             |
| `with_utls`           | uTLS fingerprinting (and inbound REALITY)      |
| `with_v2ray_api`      | v2ray stats API                                |
| `with_wireguard`      | wireguard outbound                             |

Excluded:

| Tag                   | Why                                                                |
| --------------------- | ------------------------------------------------------------------ |
| `with_naive_outbound` | Pulls in `sagernet/cronet-go/all`, which has no Go files for iOS.  |
| `with_ech`            | Deprecated in 1.13 — ECH moved to Go stdlib; tag's `_stub.go` now intentionally fails the build with that explanation. |
| `with_reality_server` | Deprecated in 1.13 — folded into `with_utls`; same intentional-build-error pattern. |

When sing-box adds a new `with_*` stub, the grep above will surface
it; append to `BUILD_TAGS` in `Scripts/build.sh`. If a new tag's stub
fails the build the way `with_ech` does, that's sing-box telling you
the feature has been merged elsewhere.

### sing-box: must pass `include.Context(ctx)` into `box.New`

sing-box 1.10+ requires the inbound/outbound/endpoint/DNS-transport/
service registries to be attached to the context that `box.New` is
called with. The `github.com/sagernet/sing-box/include` package's
`Context(ctx)` helper bundles them in one call.

If you only pass `context.Background()`, `box.New` parses the JSON but
cannot instantiate `socks`, `direct`, `vmess`, etc., and returns an
error. From iOS's perspective the Network Extension dies the instant
the tunnel comes up. See `EverywhereCore/singbox.go`.

**On upstream bump.** Verify `include.Context` is still the canonical
entry point — the registry surface has been refactored a couple of
times in 1.x.

### mihomo: must call `hub.ApplyConfig`, not `executor.ApplyConfig`

mihomo has two `ApplyConfig` functions:

- `executor.ApplyConfig(cfg, force)` — sets up DNS, proxies, rules,
  inbound listeners (socks-port, http-port, mixed-port…). Does **not**
  start the external-controller HTTP/WS API server.
- `hub.ApplyConfig(cfg)` — wraps `applyRoute(cfg)` (which calls
  `route.ReCreateServer` and *that* boots the API server) followed by
  `executor.ApplyConfig(cfg, true)`.

If you call only `executor.ApplyConfig`, the SOCKS inbound and the
tunnel work fine, but the clash REST API never starts and yacd shows
"cannot connect to 127.0.0.1:9090". `go/mihomo.go` calls
`hub.ApplyConfig`.

`hub.ApplyConfig` returns no error — failures inside it are logged via
mihomo's own logger.

## Future source patches

The Go module cache is read-only by design, so patching upstream
sources in place is not an option. If an upstream change ever requires
a source-level fix:

1. Fork the upstream to `github.com/NodePassProject/<repo>` and apply the
   change on a branch.
2. Add a `replace` directive to `go/go.mod`:
   `replace github.com/x/y => github.com/NodePassProject/y vX.Y.Z`.
3. Append a section here describing **why**, **what file**, and **what
   the upstream-correct fix would be** so we can drop the fork when
   upstream catches up.
4. Update `.github/workflows/upstream-watch.yml` to watch the fork's
   `@latest` instead, or to skip that core's auto-bump entirely.
