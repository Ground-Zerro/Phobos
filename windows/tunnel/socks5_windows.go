/* SPDX-License-Identifier: MIT
 *
 * Phobos
 */

package tunnel

import (
	"context"
	"fmt"
	"log"
	"net"
	"time"

	"golang.org/x/sys/windows"
	"golang.zx2c4.com/wireguard/windows/conf"
	"golang.zx2c4.com/wireguard/windows/phobos"
	"golang.zx2c4.com/wireguard/windows/services"
	"golang.zx2c4.com/wireguard/windows/tun2socks"
	"golang.zx2c4.com/wireguard/windows/tunnel/winipcfg"
	"golang.zx2c4.com/wireguard/windows/wintun"
)

const socks5RingCapacity = 0x400000

type socks5Dialer struct {
	client *phobos.Socks5Client
}

func (d socks5Dialer) DialTCP(ctx context.Context, host string, port uint16) (net.Conn, error) {
	return d.client.DialTCP(ctx, host, port)
}

func (d socks5Dialer) DialUDP(ctx context.Context) (tun2socks.PacketSession, error) {
	return d.client.DialUDP(ctx)
}

type socks5Tunnel struct {
	adapter *wintun.Adapter
	session *wintun.Session
	client  *phobos.Socks5Client
	stack   *tun2socks.Tunnel
	binder  stickyBinder
}

func createSocks5Adapter(config *conf.Config) (*wintun.Adapter, error) {
	var adapter *wintun.Adapter
	var err error
	for i := range 15 {
		if i > 0 {
			time.Sleep(time.Second)
			log.Printf("Retrying adapter creation after failure because system just booted (T+%v): %v", windows.DurationSinceBoot(), err)
		}
		adapter, err = wintun.CreateAdapter(config.Name, "Phobos", deterministicGUID(config))
		if err == nil || !services.StartedAtBoot() {
			break
		}
	}
	if err != nil {
		return nil, fmt.Errorf("Error creating adapter: %w", err)
	}
	if version, err := wintun.RunningVersion(); err != nil {
		log.Printf("Warning: unable to determine Wintun version: %v", err)
	} else {
		log.Printf("Using Wintun/%d.%d", (version>>16)&0xffff, version&0xffff)
	}
	return adapter, nil
}

func startSocks5Tunnel(config *conf.Config, adapter *wintun.Adapter, ourLUID winipcfg.LUID) (*socks5Tunnel, error) {
	settings := config.Obfuscation
	target, err := resolvedEndpoint(&settings.Target)
	if err != nil {
		return nil, err
	}

	t := &socks5Tunnel{adapter: adapter, binder: stickyBinder{ourLUID: ourLUID}}
	t.client = phobos.NewSocks5Client(phobos.Socks5Config{
		Target:     target,
		Key:        []byte(settings.Key),
		Masking:    settings.Masking,
		Media:      settings.MediaParams(),
		Login:      settings.Login,
		Password:   settings.Password,
		ListenPort: settings.SourceListenPort,
		Control:    t.binder.control,
		Logf:       log.Printf,
	})
	if err := t.client.Start(); err != nil {
		return nil, err
	}

	t.session, err = adapter.StartSession(socks5RingCapacity)
	if err != nil {
		t.stop()
		return nil, fmt.Errorf("Error starting adapter session: %w", err)
	}

	t.stack, err = tun2socks.Start(tun2socks.Config{
		Session: t.session,
		MTU:     uint32(config.Interface.MTU),
		Dialer:  socks5Dialer{client: t.client},
		Logf:    log.Printf,
	})
	if err != nil {
		t.stop()
		return nil, err
	}

	log.Printf("SOCKS5 tunnel up: %v (masking %v)", target, settings.Masking)
	return t, nil
}

func (t *socks5Tunnel) stop() {
	if t == nil {
		return
	}
	t.binder.stopWatching()
	if t.stack != nil {
		t.stack.Stop()
		t.stack = nil
	}
	if t.session != nil {
		t.session.End()
		t.session = nil
	}
	if t.client != nil {
		t.client.Stop()
		t.client = nil
	}
}

func (t *socks5Tunnel) watchDefaultRoutes(ourLUID winipcfg.LUID) error {
	if t == nil {
		return nil
	}
	return t.binder.watchDefaultRoutes(ourLUID)
}

func (t *socks5Tunnel) Reconfigure(*conf.Config) error {
	return nil
}
