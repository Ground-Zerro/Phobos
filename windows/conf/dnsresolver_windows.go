/* SPDX-License-Identifier: MIT
 *
 * Copyright (C) 2019-2026 WireGuard LLC. All Rights Reserved.
 */

package conf

import (
	"log"
	"net/netip"
	"time"
	"unsafe"

	"golang.zx2c4.com/wireguard/windows/tunnel/winipcfg"

	"golang.org/x/sys/windows"
	"golang.zx2c4.com/wireguard/windows/services"
)

func resolveHostname(name string) (resolvedIPString string, err error) {
	maxTries := 10
	if services.StartedAtBoot() {
		maxTries *= 3
	}
	for i := 0; i < maxTries; i++ {
		if i > 0 {
			time.Sleep(time.Second * 4)
		}
		resolvedIPString, err = resolveHostnameOnce(name)
		if err == nil {
			return
		}
		if err == windows.WSATRY_AGAIN {
			log.Printf("Temporary DNS error when resolving %s, so sleeping for 4 seconds", name)
			continue
		}
		if err == windows.WSAHOST_NOT_FOUND && services.StartedAtBoot() {
			log.Printf("Host not found when resolving %s at boot time, so sleeping for 4 seconds", name)
			continue
		}
		return
	}
	return
}

func resolveHostnameOnce(name string) (resolvedIPString string, err error) {
	hints := windows.AddrinfoW{
		Family:   windows.AF_UNSPEC,
		Socktype: windows.SOCK_DGRAM,
		Protocol: windows.IPPROTO_IP,
	}
	var result *windows.AddrinfoW
	name16, err := windows.UTF16PtrFromString(name)
	if err != nil {
		return
	}
	err = windows.GetAddrInfoW(name16, nil, &hints, &result)
	if err != nil {
		return
	}
	if result == nil {
		err = windows.WSAHOST_NOT_FOUND
		return
	}
	defer windows.FreeAddrInfoW(result)
	var v6 netip.Addr
	for ; result != nil; result = result.Next {
		if result.Family != windows.AF_INET && result.Family != windows.AF_INET6 {
			continue
		}
		addr := (*winipcfg.RawSockaddrInet)(unsafe.Pointer(result.Addr)).Addr()
		if addr.Is4() {
			return addr.String(), nil
		} else if !v6.IsValid() && addr.Is6() {
			v6 = addr
		}
	}
	if v6.IsValid() {
		return v6.String(), nil
	}
	err = windows.WSAHOST_NOT_FOUND
	return
}

func resolveEndpoint(endpoint *Endpoint) error {
	if endpoint.IsEmpty() {
		return nil
	}
	resolved, err := resolveHostname(endpoint.Host)
	if err != nil {
		return err
	}
	endpoint.Host = resolved
	return nil
}

func (config *Config) ResolveEndpoints() error {
	for i := range config.Peers {
		if err := resolveEndpoint(&config.Peers[i].Endpoint); err != nil {
			return err
		}
		if o := config.Peers[i].Obfuscation; o != nil {
			if err := resolveEndpoint(&o.Target); err != nil {
				return err
			}
		}
	}
	if config.Obfuscation != nil {
		if err := resolveEndpoint(&config.Obfuscation.Target); err != nil {
			return err
		}
	}
	return nil
}
