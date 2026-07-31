/* SPDX-License-Identifier: MIT
 *
 * Copyright (C) 2019-2026 WireGuard LLC. All Rights Reserved.
 */

package conf

import (
	"net/netip"
	"unsafe"

	"golang.org/x/sys/windows"

	"golang.zx2c4.com/wireguard/windows/driver"
	"golang.zx2c4.com/wireguard/windows/tunnel/winipcfg"
)

func FromDriverConfiguration(interfaze *driver.Interface, existingConfig *Config) *Config {
	storedObfuscations := make(map[Key]*Obfuscation, len(existingConfig.Peers))
	for i := range existingConfig.Peers {
		if o := existingConfig.Peers[i].Obfuscation; o != nil {
			storedObfuscations[existingConfig.Peers[i].PublicKey] = o
		}
	}
	conf := Config{
		Name: existingConfig.Name,
		Interface: Interface{
			Addresses: existingConfig.Interface.Addresses,
			DNS:       existingConfig.Interface.DNS,
			DNSSearch: existingConfig.Interface.DNSSearch,
			MTU:       existingConfig.Interface.MTU,
			PreUp:     existingConfig.Interface.PreUp,
			PostUp:    existingConfig.Interface.PostUp,
			PreDown:   existingConfig.Interface.PreDown,
			PostDown:  existingConfig.Interface.PostDown,
			TableOff:  existingConfig.Interface.TableOff,
		},
	}
	if interfaze.Flags&driver.InterfaceHasPrivateKey != 0 {
		conf.Interface.PrivateKey = interfaze.PrivateKey
	}
	if interfaze.Flags&driver.InterfaceHasListenPort != 0 {
		conf.Interface.ListenPort = interfaze.ListenPort
	}
	var p *driver.Peer
	for i := uint32(0); i < interfaze.PeerCount; i++ {
		if p == nil {
			p = interfaze.FirstPeer()
		} else {
			p = p.NextPeer()
		}
		peer := Peer{}
		if p.Flags&driver.PeerHasPublicKey != 0 {
			peer.PublicKey = p.PublicKey
		}
		if p.Flags&driver.PeerHasPresharedKey != 0 {
			peer.PresharedKey = p.PresharedKey
		}
		if p.Flags&driver.PeerHasEndpoint != 0 {
			peer.Endpoint.Port = p.Endpoint.Port()
			peer.Endpoint.Host = p.Endpoint.Addr().String()
		}
		if p.Flags&driver.PeerHasPersistentKeepalive != 0 {
			peer.PersistentKeepalive = p.PersistentKeepalive
		}
		peer.TxBytes = Bytes(p.TxBytes)
		peer.RxBytes = Bytes(p.RxBytes)
		if p.LastHandshake != 0 {
			peer.LastHandshakeTime = HandshakeTime((p.LastHandshake - 116444736000000000) * 100)
		}
		var a *driver.AllowedIP
		for j := uint32(0); j < p.AllowedIPsCount; j++ {
			if a == nil {
				a = p.FirstAllowedIP()
			} else {
				a = a.NextAllowedIP()
			}
			var ip netip.Addr
			if a.AddressFamily == windows.AF_INET {
				ip = netip.AddrFrom4(*(*[4]byte)(a.Address[:4]))
			} else if a.AddressFamily == windows.AF_INET6 {
				ip = netip.AddrFrom16(*(*[16]byte)(a.Address[:16]))
			}
			peer.AllowedIPs = append(peer.AllowedIPs, netip.PrefixFrom(ip, int(a.Cidr)))
		}
		peer.Obfuscation = storedObfuscations[peer.PublicKey]
		conf.Peers = append(conf.Peers, peer)
	}
	return &conf
}

func (config *Config) ToDriverConfiguration() (*driver.Interface, uint32) {
	preallocation := unsafe.Sizeof(driver.Interface{}) + uintptr(len(config.Peers))*unsafe.Sizeof(driver.Peer{})
	for i := range config.Peers {
		preallocation += uintptr(len(config.Peers[i].AllowedIPs)) * unsafe.Sizeof(driver.AllowedIP{})
	}
	var c driver.ConfigBuilder
	c.Preallocate(uint32(preallocation))
	c.AppendInterface(&driver.Interface{
		Flags:      driver.InterfaceHasPrivateKey | driver.InterfaceHasListenPort,
		ListenPort: config.Interface.ListenPort,
		PrivateKey: config.Interface.PrivateKey,
		PeerCount:  uint32(len(config.Peers)),
	})
	for i := range config.Peers {
		flags := driver.PeerHasPublicKey | driver.PeerHasPersistentKeepalive
		if !config.Peers[i].PresharedKey.IsZero() {
			flags |= driver.PeerHasPresharedKey
		}
		var endpoint winipcfg.RawSockaddrInet
		if !config.Peers[i].Endpoint.IsEmpty() {
			addr, err := netip.ParseAddr(config.Peers[i].Endpoint.Host)
			if err == nil {
				flags |= driver.PeerHasEndpoint
				endpoint.SetAddrPort(netip.AddrPortFrom(addr, config.Peers[i].Endpoint.Port))
			}
		}
		c.AppendPeer(&driver.Peer{
			Flags:               flags,
			PublicKey:           config.Peers[i].PublicKey,
			PresharedKey:        config.Peers[i].PresharedKey,
			PersistentKeepalive: config.Peers[i].PersistentKeepalive,
			Endpoint:            endpoint,
			AllowedIPsCount:     uint32(len(config.Peers[i].AllowedIPs)),
		})
		for j := range config.Peers[i].AllowedIPs {
			a := &driver.AllowedIP{Cidr: uint8(config.Peers[i].AllowedIPs[j].Bits())}
			copy(a.Address[:], config.Peers[i].AllowedIPs[j].Addr().AsSlice())
			if config.Peers[i].AllowedIPs[j].Addr().Is4() {
				a.AddressFamily = windows.AF_INET
			} else if config.Peers[i].AllowedIPs[j].Addr().Is6() {
				a.AddressFamily = windows.AF_INET6
			}
			c.AppendAllowedIP(a)
		}
	}
	return c.Interface()
}
