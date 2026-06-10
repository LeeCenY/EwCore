package evcore

import (
	"context"
	"net/netip"
	"os"
	"sync"
	"syscall"

	box "github.com/sagernet/sing-box"
	"github.com/sagernet/sing-box/adapter"
	"github.com/sagernet/sing-box/include"
	"github.com/sagernet/sing-box/option"
	tun "github.com/sagernet/sing-tun"
	"github.com/sagernet/sing/common/control"
	"github.com/sagernet/sing/common/json"
	"github.com/sagernet/sing/common/logger"
	"github.com/sagernet/sing/common/x/list"
	"github.com/sagernet/sing/service"
	"github.com/sagernet/sing/service/pause"
)

type singBoxRunner struct {
	box          *box.Box
	pauseManager pause.Manager
	platform     *singBoxPlatform
}

func (s *singBoxRunner) stop() error {
	if s.box != nil {
		return s.box.Close()
	}
	return nil
}

func (s *singBoxRunner) suspend() {
	if s.pauseManager != nil && !s.pauseManager.IsDevicePaused() {
		s.pauseManager.DevicePause()
	}
}

func (s *singBoxRunner) resume() {
	if s.pauseManager != nil && s.pauseManager.IsDevicePaused() {
		s.pauseManager.DeviceWake()
	}
}

func (s *singBoxRunner) updateDefaultInterface(name string, index int32, isExpensive, isConstrained bool) {
	if s.platform == nil || s.platform.monitor == nil {
		return
	}
	var nm adapter.NetworkManager
	if s.box != nil {
		nm = s.box.Network()
	}
	s.platform.monitor.updateDefault(nm, name, index, isExpensive, isConstrained)
}

func startSingBox(configContent string, tunFD, _ int) (coreRunner, error) {
	// include.Context attaches the built-in inbound/outbound/endpoint/
	// DNS-transport/service registries to the context. Without it
	// box.New cannot resolve types declared in the JSON (socks,
	// direct, vmess, …) and start fails immediately.
	ctx := include.Context(context.Background())

	// box.New runs pause.WithDefaultManager on its own copy of the
	// context, so the manager it installs is unreachable from out here.
	// Install one on our ctx up front and box.New will reuse it
	// (WithDefaultManager early-returns when a manager is already
	// registered), which lets us hand DevicePause/DeviceWake to the
	// NE's sleep/wake callbacks.
	ctx = pause.WithDefaultManager(ctx)
	pauseManager := service.FromContext[pause.Manager](ctx)

	pi := newSingBoxPlatform(tunFD)
	ctx = service.ContextWith[adapter.PlatformInterface](ctx, pi)

	options, err := json.UnmarshalExtendedContext[option.Options](ctx, []byte(configContent))
	if err != nil {
		return nil, err
	}
	b, err := box.New(box.Options{
		Context: ctx,
		Options: options,
	})
	if err != nil {
		return nil, err
	}
	if err := b.Start(); err != nil {
		_ = b.Close()
		return nil, err
	}
	return &singBoxRunner{box: b, pauseManager: pauseManager, platform: pi}, nil
}

// singBoxPlatform is the minimal adapter.PlatformInterface needed
// to inject an existing utun fd into sing-box's tun inbound.
//
// Layout matches libbox's stub (experimental/libbox/config.go), but
// `UsePlatformInterface` returns true so the tun inbound calls
// OpenInterface, and `UnderNetworkExtension` returns true so MTU
// defaults match the iOS NE constraints.
type singBoxPlatform struct {
	tunFD       int
	myAddresses []netip.Addr
	monitor     *singBoxInterfaceMonitor
}

func newSingBoxPlatform(tunFD int) *singBoxPlatform {
	return &singBoxPlatform{
		tunFD:   tunFD,
		monitor: newSingBoxInterfaceMonitor(),
	}
}

func (p *singBoxPlatform) Initialize(_ adapter.NetworkManager) error { return nil }

func (p *singBoxPlatform) UsePlatformAutoDetectInterfaceControl() bool { return false }
func (p *singBoxPlatform) AutoDetectInterfaceControl(_ int) error      { return nil }

func (p *singBoxPlatform) UsePlatformInterface() bool { return true }

func (p *singBoxPlatform) OpenInterface(options *tun.Options, _ option.TunPlatformOptions) (tun.Tun, error) {
	// Dup the fd so sing-tun's Close (which closes its os.File)
	// doesn't tear down the underlying NEPacketTunnelFlow utun while
	// the Network Extension still holds the original.
	dupFd, err := syscall.Dup(p.tunFD)
	if err != nil {
		return nil, err
	}
	options.FileDescriptor = dupFd
	for _, prefix := range options.Inet4Address {
		p.myAddresses = append(p.myAddresses, prefix.Addr())
	}
	for _, prefix := range options.Inet6Address {
		p.myAddresses = append(p.myAddresses, prefix.Addr())
	}
	return tun.New(*options)
}

func (p *singBoxPlatform) UsePlatformDefaultInterfaceMonitor() bool { return true }
func (p *singBoxPlatform) CreateDefaultInterfaceMonitor(_ logger.Logger) tun.DefaultInterfaceMonitor {
	return p.monitor
}

func (p *singBoxPlatform) UsePlatformNetworkInterfaces() bool { return false }
func (p *singBoxPlatform) NetworkInterfaces() ([]adapter.NetworkInterface, error) {
	return nil, os.ErrInvalid
}

func (p *singBoxPlatform) UnderNetworkExtension() bool              { return true }
func (p *singBoxPlatform) NetworkExtensionIncludeAllNetworks() bool { return false }

func (p *singBoxPlatform) ClearDNSCache()                       {}
func (p *singBoxPlatform) RequestPermissionForWIFIState() error { return nil }
func (p *singBoxPlatform) ReadWIFIState() adapter.WIFIState     { return adapter.WIFIState{} }
func (p *singBoxPlatform) SystemCertificates() []string         { return nil }

func (p *singBoxPlatform) UsePlatformConnectionOwnerFinder() bool { return false }
func (p *singBoxPlatform) FindConnectionOwner(_ *adapter.FindConnectionOwnerRequest) (*adapter.ConnectionOwner, error) {
	return nil, os.ErrInvalid
}

func (p *singBoxPlatform) UsePlatformWIFIMonitor() bool                   { return false }
func (p *singBoxPlatform) UsePlatformNotification() bool                  { return false }
func (p *singBoxPlatform) SendNotification(_ *adapter.Notification) error { return nil }
func (p *singBoxPlatform) MyInterfaceAddress() []netip.Addr               { return p.myAddresses }

// Uncomment when upstream-watch bumps to a stable 1.14.
//
// func (p *singBoxPlatform) UsePlatformNeighborResolver() bool { return false }
// func (p *singBoxPlatform) StartNeighborMonitor(_ adapter.NeighborUpdateListener) error {
// 	return os.ErrInvalid
// }
// func (p *singBoxPlatform) CloseNeighborMonitor(_ adapter.NeighborUpdateListener) error { return nil }
//
// func (p *singBoxPlatform) UsePlatformShell() bool    { return false }
// func (p *singBoxPlatform) CheckPlatformShell() error { return nil }
// func (p *singBoxPlatform) OpenShellSession(_ *adapter.PlatformUser, _ string, _ []string, _ string, _, _ int32) (adapter.ShellSession, error) {
// 	return nil, os.ErrInvalid
// }
// func (p *singBoxPlatform) LookupUser(_ string) (*adapter.PlatformUser, error) {
// 	return nil, os.ErrInvalid
// }
// func (p *singBoxPlatform) LookupSFTPServer() (string, error)     { return "", os.ErrInvalid }
// func (p *singBoxPlatform) ReadSystemSSHHostKey() ([]byte, error) { return nil, os.ErrInvalid }
// func (p *singBoxPlatform) TailscaleHostname() string             { return "" }

// singBoxInterfaceMonitor is a tun.DefaultInterfaceMonitor driven from
// outside Go — typically by an NWPathMonitor on the iOS side feeding
// Evcore.UpdateDefaultInterface. Without this, sing-box's router never
// learns that the underlying network changed and sockets pinned to a
// stale path keep retransmitting until OS-level timeouts.
//
// Layout mirrors libbox's `platformDefaultInterfaceMonitor`
// (experimental/libbox/monitor.go): refresh sing-box's cached
// interface list, look the new default up by index, fan callbacks
// out under a mutex. When the index is -1 we signal `no path` by
// calling callbacks with a nil interface, which the network manager
// translates into `pauseManager.NetworkPause`.
type singBoxInterfaceMonitor struct {
	access       sync.Mutex
	current      *control.Interface
	myInterfaces []string
	callbacks    list.List[tun.DefaultInterfaceUpdateCallback]
}

func newSingBoxInterfaceMonitor() *singBoxInterfaceMonitor {
	return &singBoxInterfaceMonitor{}
}

func (m *singBoxInterfaceMonitor) Start() error             { return nil }
func (m *singBoxInterfaceMonitor) Close() error             { return nil }
func (m *singBoxInterfaceMonitor) OverrideAndroidVPN() bool { return false }
func (m *singBoxInterfaceMonitor) AndroidVPNEnabled() bool  { return false }

func (m *singBoxInterfaceMonitor) DefaultInterface() *control.Interface {
	m.access.Lock()
	defer m.access.Unlock()
	return m.current
}

func (m *singBoxInterfaceMonitor) RegisterCallback(callback tun.DefaultInterfaceUpdateCallback) *list.Element[tun.DefaultInterfaceUpdateCallback] {
	m.access.Lock()
	defer m.access.Unlock()
	return m.callbacks.PushBack(callback)
}

func (m *singBoxInterfaceMonitor) UnregisterCallback(element *list.Element[tun.DefaultInterfaceUpdateCallback]) {
	m.access.Lock()
	defer m.access.Unlock()
	m.callbacks.Remove(element)
}

func (m *singBoxInterfaceMonitor) RegisterMyInterface(interfaceName string) {
	m.access.Lock()
	defer m.access.Unlock()
	m.myInterfaces = append(m.myInterfaces, interfaceName)
}

func (m *singBoxInterfaceMonitor) MyInterfaces() []string {
	m.access.Lock()
	defer m.access.Unlock()
	return m.myInterfaces
}

// updateDefault sets the monitor's default interface and fans out a
// callback. nm is used to refresh sing-box's cached interface list
// and resolve the new default by index — when the manager is missing
// (start-up race) or the lookup fails we still fire a synthetic
// control.Interface so the router gets at least a name/index.
func (m *singBoxInterfaceMonitor) updateDefault(nm adapter.NetworkManager, name string, index int32, _ bool, _ bool) {
	if nm != nil {
		_ = nm.UpdateInterfaces()
	}

	var newInterface *control.Interface
	if index >= 0 {
		if nm != nil {
			if iif, err := nm.InterfaceFinder().ByIndex(int(index)); err == nil {
				newInterface = iif
			}
		}
		if newInterface == nil {
			newInterface = &control.Interface{Name: name, Index: int(index)}
		}
	}

	m.access.Lock()
	old := m.current
	m.current = newInterface
	if newInterface != nil && old != nil && old.Index == newInterface.Index && old.Name == newInterface.Name {
		// Identical to the previous default — no need to fan callbacks
		// out and trigger a ResetNetwork.
		m.access.Unlock()
		return
	}
	callbacks := make([]tun.DefaultInterfaceUpdateCallback, 0, m.callbacks.Len())
	for el := m.callbacks.Front(); el != nil; el = el.Next() {
		callbacks = append(callbacks, el.Value)
	}
	m.access.Unlock()

	for _, callback := range callbacks {
		callback(newInterface, 0)
	}
}
