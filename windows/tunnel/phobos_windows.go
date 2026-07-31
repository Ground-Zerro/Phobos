/* SPDX-License-Identifier: MIT
 *
 * Phobos
 */

package tunnel

import (
	"fmt"
	"log"
	"net/netip"
	"strings"
	"sync"
	"syscall"

	"golang.org/x/sys/windows"
	"golang.zx2c4.com/wireguard/windows/conf"
	"golang.zx2c4.com/wireguard/windows/phobos"
	"golang.zx2c4.com/wireguard/windows/tunnel/winipcfg"
)

const (
	ipUnicastIf   = 31
	ipv6UnicastIf = 31
)

type stickySocket struct {
	raw    syscall.RawConn
	family winipcfg.AddressFamily
}

type stickyBinder struct {
	mu       sync.Mutex
	ourLUID  winipcfg.LUID
	index    [2]uint32
	resolved [2]bool
	tracked  []stickySocket
	watchers []winipcfg.ChangeCallback
}

func familyOf(network string) winipcfg.AddressFamily {
	if strings.HasSuffix(network, "6") {
		return windows.AF_INET6
	}
	return windows.AF_INET
}

func familySlot(family winipcfg.AddressFamily) int {
	if family == windows.AF_INET6 {
		return 1
	}
	return 0
}

func (b *stickyBinder) control(network, address string, c syscall.RawConn) error {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.apply(stickySocket{raw: c, family: familyOf(network)})
}

func (b *stickyBinder) controlAndTrack(network, address string, c syscall.RawConn) error {
	b.mu.Lock()
	defer b.mu.Unlock()
	socket := stickySocket{raw: c, family: familyOf(network)}
	b.tracked = append(b.tracked, socket)
	return b.apply(socket)
}

func (b *stickyBinder) apply(socket stickySocket) error {
	index, err := b.indexFor(socket.family)
	if err != nil {
		return err
	}
	if index == 0 {
		return nil
	}

	var setErr error
	err = socket.raw.Control(func(handle uintptr) {
		if socket.family == windows.AF_INET {
			setErr = windows.SetsockoptInt(windows.Handle(handle), windows.IPPROTO_IP, ipUnicastIf, int(hostToNetworkLong(index)))
		} else {
			setErr = windows.SetsockoptInt(windows.Handle(handle), windows.IPPROTO_IPV6, ipv6UnicastIf, int(index))
		}
	})
	if err != nil {
		return err
	}
	return setErr
}

func (b *stickyBinder) indexFor(family winipcfg.AddressFamily) (uint32, error) {
	slot := familySlot(family)
	if b.resolved[slot] {
		return b.index[slot], nil
	}
	_, index, err := findDefaultRoute(family, b.ourLUID)
	if err != nil {
		return 0, err
	}
	b.index[slot], b.resolved[slot] = index, true
	return index, nil
}

func (b *stickyBinder) rebind() {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.resolved = [2]bool{}
	live := b.tracked[:0]
	for _, socket := range b.tracked {
		if _, err := b.indexFor(socket.family); err != nil {
			live = append(live, socket)
			continue
		}
		if err := b.apply(socket); err != nil {
			continue
		}
		live = append(live, socket)
	}
	b.tracked = live
}

func (b *stickyBinder) watchDefaultRoutes(ourLUID winipcfg.LUID) error {
	b.mu.Lock()
	b.ourLUID = ourLUID
	b.mu.Unlock()
	b.rebind()

	callback, err := winipcfg.RegisterRouteChangeCallback(func(notificationType winipcfg.MibNotificationType, route *winipcfg.MibIPforwardRow2) {
		if route != nil && route.DestinationPrefix.PrefixLength == 0 {
			b.rebind()
		}
	})
	if err != nil {
		return err
	}
	b.mu.Lock()
	b.watchers = append(b.watchers, callback)
	b.mu.Unlock()
	return nil
}

func (b *stickyBinder) stopWatching() {
	b.mu.Lock()
	watchers := b.watchers
	b.watchers = nil
	b.mu.Unlock()
	for _, callback := range watchers {
		callback.Unregister()
	}
}

func hostToNetworkLong(value uint32) uint32 {
	return value>>24 | value>>8&0xFF00 | value<<8&0xFF0000 | value<<24
}

type obfuscation struct {
	binder  stickyBinder
	proxies []*phobos.UDPProxy
}

func startObfuscation(config *conf.Config, ourLUID winipcfg.LUID) (*obfuscation, error) {
	needed := false
	for i := range config.Peers {
		if config.Peers[i].Obfuscation != nil {
			needed = true
			break
		}
	}
	if !needed {
		return nil, nil
	}

	o := &obfuscation{binder: stickyBinder{ourLUID: ourLUID}}
	for i := range config.Peers {
		settings := config.Peers[i].Obfuscation
		if settings == nil {
			continue
		}
		target, err := resolvedEndpoint(&settings.Target)
		if err != nil {
			o.stop()
			return nil, err
		}
		proxy := phobos.NewUDPProxy(phobos.UDPProxyConfig{
			Target:          target,
			Key:             []byte(settings.Key),
			Masking:         settings.Masking,
			Media:           settings.MediaParams(),
			MaxDummy:        int(settings.MaxDummy),
			ObfuscateBytes:  int(settings.ObfuscateBytes),
			UpstreamControl: o.binder.controlAndTrack,
			Logf:            log.Printf,
		})
		if err := proxy.Start(); err != nil {
			o.stop()
			return nil, err
		}
		o.proxies = append(o.proxies, proxy)
		config.Peers[i].Endpoint = conf.Endpoint{Host: "127.0.0.1", Port: proxy.ListenPort()}
	}
	return o, nil
}

func (o *obfuscation) stop() {
	if o == nil {
		return
	}
	o.binder.stopWatching()
	for _, proxy := range o.proxies {
		proxy.Stop()
	}
	o.proxies = nil
}

func (o *obfuscation) watchDefaultRoutes(ourLUID winipcfg.LUID) error {
	if o == nil {
		return nil
	}
	return o.binder.watchDefaultRoutes(ourLUID)
}

func resolvedEndpoint(endpoint *conf.Endpoint) (netip.AddrPort, error) {
	addr, err := netip.ParseAddr(endpoint.Host)
	if err != nil {
		return netip.AddrPort{}, fmt.Errorf("obfuscator target %q is not resolved: %w", endpoint.Host, err)
	}
	return netip.AddrPortFrom(addr, endpoint.Port), nil
}
