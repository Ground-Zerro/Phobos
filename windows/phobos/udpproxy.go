/* SPDX-License-Identifier: MIT
 *
 * Phobos
 */

package phobos

import (
	"context"
	"errors"
	"fmt"
	"net"
	"net/netip"
	"sync"
	"sync/atomic"
	"syscall"
	"time"
)

type SocketControl func(network, address string, c syscall.RawConn) error

type UDPProxyConfig struct {
	Target          netip.AddrPort
	Key             []byte
	Masking         Masking
	Media           MediaParams
	MaxDummy        int
	ObfuscateBytes  int
	UpstreamControl SocketControl
	Logf            func(format string, args ...any)
}

type UDPProxy struct {
	config UDPProxyConfig

	listener   *net.UDPConn
	upstream   *net.UDPConn
	listenPort uint16

	maskerMu sync.Mutex
	masker   Masker

	client  atomic.Pointer[netip.AddrPort]
	running atomic.Bool

	sawTunnel   atomic.Bool
	sawServer   atomic.Bool
	sawRejected atomic.Bool

	wait sync.WaitGroup
	done chan struct{}
}

func NewUDPProxy(config UDPProxyConfig) *UDPProxy {
	if config.Logf == nil {
		config.Logf = func(string, ...any) {}
	}
	return &UDPProxy{config: config, done: make(chan struct{})}
}

func (p *UDPProxy) ListenPort() uint16 {
	return p.listenPort
}

func (p *UDPProxy) Start() error {
	if len(p.config.Key) == 0 {
		return errors.New("obfuscation key is empty")
	}
	if !p.config.Target.IsValid() {
		return errors.New("obfuscator target is not resolved")
	}

	listener, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1)})
	if err != nil {
		return fmt.Errorf("unable to open loopback socket: %w", err)
	}

	dialer := net.Dialer{Control: p.config.UpstreamControl}
	conn, err := dialer.DialContext(context.Background(), "udp", p.config.Target.String())
	if err != nil {
		listener.Close()
		return fmt.Errorf("unable to open upstream socket: %w", err)
	}

	p.listener = listener
	p.upstream = conn.(*net.UDPConn)
	p.listenPort = uint16(listener.LocalAddr().(*net.UDPAddr).Port)
	p.masker = NewMasker(p.config.Masking, p.config.Media)
	p.running.Store(true)

	p.spawn(p.clientLoop)
	p.spawn(p.serverLoop)
	if p.masker != nil {
		p.spawn(p.timerLoop)
	}

	p.config.Logf("Obfuscator started: 127.0.0.1:%d -> %v (masking %v)", p.listenPort, p.config.Target, p.config.Masking)
	return nil
}

func (p *UDPProxy) Stop() {
	if !p.running.Swap(false) {
		return
	}
	close(p.done)
	p.listener.Close()
	p.upstream.Close()
	p.wait.Wait()
	p.config.Logf("Obfuscator stopped: 127.0.0.1:%d -> %v", p.listenPort, p.config.Target)
}

func (p *UDPProxy) spawn(loop func()) {
	p.wait.Add(1)
	go func() {
		defer p.wait.Done()
		loop()
	}()
}

func (p *UDPProxy) sendToServer(packet []byte) (int, error) {
	return p.upstream.Write(packet)
}

func (p *UDPProxy) sendToClient(packet []byte) (int, error) {
	client := p.client.Load()
	if client == nil {
		return 0, nil
	}
	return p.listener.WriteToUDPAddrPort(packet, *client)
}

func (p *UDPProxy) reject(stage string, length int) {
	if !p.sawRejected.Swap(true) {
		p.config.Logf("Obfuscator: server packet of %d bytes rejected at %s stage, check that masking and key match the server preset", length, stage)
	}
}

func (p *UDPProxy) fail(what string, err error) {
	if p.running.Load() {
		p.config.Logf("Obfuscator %s failed: %v", what, err)
	}
}

func (p *UDPProxy) clientLoop() {
	buf := make([]byte, BufferSize)
	obfuscator := NewObfuscator(p.config.Key)
	for {
		n, source, err := p.listener.ReadFromUDPAddrPort(buf)
		if err != nil {
			p.fail("loopback read", err)
			return
		}
		if n < 4 {
			continue
		}
		packetType := PacketType(buf)
		if !IsKnownPacketType(packetType) {
			continue
		}

		if client := p.client.Load(); client == nil || *client != source {
			p.client.Store(&source)
		}
		if !p.sawTunnel.Swap(true) {
			p.config.Logf("Obfuscator: first packet from tunnel, %d bytes from %v", n, source)
		}

		length := obfuscator.Encode(buf, n, p.config.MaxDummy, p.config.ObfuscateBytes)
		if length < 0 {
			continue
		}
		if p.masker != nil {
			length = p.wrap(buf, length, packetType == TypeHandshake)
			if length <= 0 {
				continue
			}
		}
		if _, err := p.sendToServer(buf[:length]); err != nil {
			p.fail("upstream write", err)
			return
		}
	}
}

func (p *UDPProxy) serverLoop() {
	buf := make([]byte, BufferSize)
	obfuscator := NewObfuscator(p.config.Key)
	for {
		n, err := p.upstream.Read(buf)
		if err != nil {
			p.fail("upstream read", err)
			return
		}
		if !p.sawServer.Swap(true) {
			p.config.Logf("Obfuscator: first packet from server, %d bytes", n)
		}
		if p.client.Load() == nil {
			continue
		}

		length := n
		if p.masker != nil {
			length = p.unwrap(buf, length)
			if length < 0 {
				p.reject("masking", n)
				continue
			}
			if length == 0 {
				continue
			}
		}
		if length < 4 {
			p.reject("length", n)
			continue
		}
		length = obfuscator.Decode(buf, length, p.config.ObfuscateBytes)
		if length < 4 || !IsKnownPacketType(PacketType(buf)) {
			p.reject("key", n)
			continue
		}
		if _, err := p.sendToClient(buf[:length]); err != nil {
			p.fail("loopback write", err)
			return
		}
	}
}

func (p *UDPProxy) timerLoop() {
	ticker := time.NewTicker(p.masker.TimerInterval())
	defer ticker.Stop()
	for {
		select {
		case <-p.done:
			return
		case <-ticker.C:
			if p.client.Load() == nil {
				continue
			}
			p.maskerMu.Lock()
			p.masker.OnTimer(p.sendToServer)
			p.maskerMu.Unlock()
		}
	}
}

func (p *UDPProxy) wrap(buf []byte, length int, handshake bool) int {
	p.maskerMu.Lock()
	defer p.maskerMu.Unlock()
	if handshake {
		p.masker.OnHandshakeRequest(p.sendToServer)
	}
	return p.masker.OnDataWrap(buf, length)
}

func (p *UDPProxy) unwrap(buf []byte, length int) int {
	p.maskerMu.Lock()
	defer p.maskerMu.Unlock()
	return p.masker.OnDataUnwrap(buf, length, p.config.Target, p.sendToServer)
}
