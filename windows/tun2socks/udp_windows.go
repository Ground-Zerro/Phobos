/* SPDX-License-Identifier: MIT
 *
 * Phobos
 */

package tun2socks

import (
	"context"
	"net"
	"net/netip"
	"sync"
	"time"
)

const (
	udpIdleTimeout  = 60 * time.Second
	udpDatagramSize = 2000
)

type udpRelay struct {
	session PacketSession
	logf    func(string, ...any)

	mu     sync.Mutex
	flows  map[netip.AddrPort]net.Conn
	closed bool

	release func()
}

type udpMultiplexer struct {
	dialer Dialer
	logf   func(string, ...any)

	mu     sync.Mutex
	relays map[netip.AddrPort]*udpRelay
	closed bool
}

func newUDPMultiplexer(dialer Dialer, logf func(string, ...any)) *udpMultiplexer {
	return &udpMultiplexer{dialer: dialer, logf: logf, relays: make(map[netip.AddrPort]*udpRelay)}
}

func (m *udpMultiplexer) attach(source, target netip.AddrPort, conn net.Conn) {
	relay, err := m.relayFor(source)
	if err != nil {
		m.logf("tun2socks: cannot open a UDP session for %v: %v", source, err)
		conn.Close()
		return
	}
	if !relay.register(target, conn) {
		conn.Close()
		return
	}
	go relay.pumpFlow(target, conn)
}

func (m *udpMultiplexer) relayFor(source netip.AddrPort) (*udpRelay, error) {
	m.mu.Lock()
	if m.closed {
		m.mu.Unlock()
		return nil, net.ErrClosed
	}
	if relay, ok := m.relays[source]; ok {
		m.mu.Unlock()
		return relay, nil
	}
	m.mu.Unlock()

	session, err := m.dialer.DialUDP(context.Background())
	if err != nil {
		return nil, err
	}

	m.mu.Lock()
	if existing, ok := m.relays[source]; ok {
		m.mu.Unlock()
		session.Close()
		return existing, nil
	}
	relay := &udpRelay{
		session: session,
		logf:    m.logf,
		flows:   make(map[netip.AddrPort]net.Conn),
		release: func() { m.forget(source) },
	}
	if m.closed {
		m.mu.Unlock()
		session.Close()
		return nil, net.ErrClosed
	}
	m.relays[source] = relay
	m.mu.Unlock()

	go relay.pumpSession()
	return relay, nil
}

func (m *udpMultiplexer) forget(source netip.AddrPort) {
	m.mu.Lock()
	delete(m.relays, source)
	m.mu.Unlock()
}

func (m *udpMultiplexer) close() {
	m.mu.Lock()
	m.closed = true
	relays := make([]*udpRelay, 0, len(m.relays))
	for _, relay := range m.relays {
		relays = append(relays, relay)
	}
	m.relays = make(map[netip.AddrPort]*udpRelay)
	m.mu.Unlock()

	for _, relay := range relays {
		relay.close()
	}
}

func (r *udpRelay) register(target netip.AddrPort, conn net.Conn) bool {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.closed {
		return false
	}
	if previous, ok := r.flows[target]; ok {
		previous.Close()
	}
	r.flows[target] = conn
	return true
}

func (r *udpRelay) unregister(target netip.AddrPort) {
	r.mu.Lock()
	delete(r.flows, target)
	empty := len(r.flows) == 0
	r.mu.Unlock()
	if empty {
		r.close()
	}
}

func (r *udpRelay) close() {
	r.mu.Lock()
	if r.closed {
		r.mu.Unlock()
		return
	}
	r.closed = true
	flows := make([]net.Conn, 0, len(r.flows))
	for _, conn := range r.flows {
		flows = append(flows, conn)
	}
	r.flows = nil
	r.mu.Unlock()

	r.session.Close()
	for _, conn := range flows {
		conn.Close()
	}
	if r.release != nil {
		r.release()
	}
}

func (r *udpRelay) pumpFlow(target netip.AddrPort, conn net.Conn) {
	defer r.unregister(target)
	defer conn.Close()

	buf := make([]byte, udpDatagramSize)
	for {
		conn.SetReadDeadline(time.Now().Add(udpIdleTimeout))
		n, err := conn.Read(buf)
		if err != nil {
			return
		}
		if err := r.session.WriteTo(buf[:n], target); err != nil {
			return
		}
	}
}

func (r *udpRelay) pumpSession() {
	buf := make([]byte, udpDatagramSize)
	for {
		n, source, err := r.session.ReadFrom(buf)
		if err != nil {
			r.close()
			return
		}
		r.mu.Lock()
		conn := r.flows[source]
		r.mu.Unlock()
		if conn == nil {
			continue
		}
		if _, err := conn.Write(buf[:n]); err != nil {
			conn.Close()
		}
	}
}
