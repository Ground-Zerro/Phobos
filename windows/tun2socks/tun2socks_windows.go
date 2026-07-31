/* SPDX-License-Identifier: MIT
 *
 * Phobos
 */

package tun2socks

import (
	"context"
	"fmt"
	"io"
	"net"
	"net/netip"
	"sync"

	"golang.zx2c4.com/wireguard/windows/wintun"
	"gvisor.dev/gvisor/pkg/tcpip"
	"gvisor.dev/gvisor/pkg/tcpip/adapters/gonet"
	"gvisor.dev/gvisor/pkg/tcpip/network/ipv4"
	"gvisor.dev/gvisor/pkg/tcpip/network/ipv6"
	"gvisor.dev/gvisor/pkg/tcpip/stack"
	"gvisor.dev/gvisor/pkg/tcpip/transport/tcp"
	"gvisor.dev/gvisor/pkg/tcpip/transport/udp"
	"gvisor.dev/gvisor/pkg/waiter"
)

const (
	nicID           = 1
	tcpReceiveQueue = 0
	tcpMaxInFlight  = 2048
)

type PacketSession interface {
	WriteTo(payload []byte, target netip.AddrPort) error
	ReadFrom(buf []byte) (int, netip.AddrPort, error)
	Close() error
}

type Dialer interface {
	DialTCP(ctx context.Context, host string, port uint16) (net.Conn, error)
	DialUDP(ctx context.Context) (PacketSession, error)
}

type Config struct {
	Session *wintun.Session
	MTU     uint32
	Dialer  Dialer
	Logf    func(format string, args ...any)
}

type Tunnel struct {
	config Config
	device *device
	stack  *stack.Stack
	udp    *udpMultiplexer

	closeOnce sync.Once
}

func Start(config Config) (*Tunnel, error) {
	if config.Logf == nil {
		config.Logf = func(string, ...any) {}
	}
	if config.Dialer == nil {
		return nil, fmt.Errorf("tun2socks: no dialer configured")
	}

	t := &Tunnel{config: config, device: newDevice(config.Session, config.MTU)}
	t.udp = newUDPMultiplexer(config.Dialer, config.Logf)
	t.stack = stack.New(stack.Options{
		NetworkProtocols:   []stack.NetworkProtocolFactory{ipv4.NewProtocol, ipv6.NewProtocol},
		TransportProtocols: []stack.TransportProtocolFactory{tcp.NewProtocol, udp.NewProtocol},
	})

	if err := t.stack.CreateNIC(nicID, t.device.endpoint); err != nil {
		return nil, fmt.Errorf("tun2socks: unable to create the NIC: %v", err)
	}
	t.stack.SetPromiscuousMode(nicID, true)
	t.stack.SetSpoofing(nicID, true)
	t.stack.SetRouteTable([]tcpip.Route{
		{Destination: header4Subnet(), NIC: nicID},
		{Destination: header6Subnet(), NIC: nicID},
	})

	t.stack.SetTransportProtocolHandler(tcp.ProtocolNumber,
		tcp.NewForwarder(t.stack, tcpReceiveQueue, tcpMaxInFlight, t.handleTCP).HandlePacket)
	t.stack.SetTransportProtocolHandler(udp.ProtocolNumber,
		udp.NewForwarder(t.stack, t.handleUDP).HandlePacket)

	t.device.start(config.Logf)
	return t, nil
}

func (t *Tunnel) Stop() {
	t.closeOnce.Do(func() {
		t.udp.close()
		t.device.stop()
		t.stack.Close()
		t.stack.Wait()
	})
}

func header4Subnet() tcpip.Subnet {
	subnet, _ := tcpip.NewSubnet(tcpip.AddrFrom4([4]byte{}), tcpip.MaskFromBytes(make([]byte, 4)))
	return subnet
}

func header6Subnet() tcpip.Subnet {
	subnet, _ := tcpip.NewSubnet(tcpip.AddrFrom16([16]byte{}), tcpip.MaskFromBytes(make([]byte, 16)))
	return subnet
}

func endpointAddrPort(address tcpip.Address, port uint16) netip.AddrPort {
	addr, _ := netip.AddrFromSlice(address.AsSlice())
	return netip.AddrPortFrom(addr.Unmap(), port)
}

func (t *Tunnel) handleTCP(request *tcp.ForwarderRequest) {
	id := request.ID()
	target := endpointAddrPort(id.LocalAddress, id.LocalPort)

	go func() {
		remote, dialErr := t.config.Dialer.DialTCP(context.Background(), target.Addr().String(), target.Port())
		if dialErr != nil {
			t.config.Logf("tun2socks: cannot reach %v: %v", target, dialErr)
			request.Complete(true)
			return
		}
		defer remote.Close()

		var queue waiter.Queue
		endpoint, err := request.CreateEndpoint(&queue)
		if err != nil {
			request.Complete(true)
			return
		}
		request.Complete(false)

		local := gonet.NewTCPConn(&queue, endpoint)
		defer local.Close()
		relay(local, remote)
	}()
}

func relay(local, remote net.Conn) {
	var wait sync.WaitGroup
	wait.Add(2)
	go func() {
		defer wait.Done()
		io.Copy(remote, local)
		if closer, ok := remote.(interface{ CloseWrite() error }); ok {
			closer.CloseWrite()
		} else {
			remote.Close()
		}
	}()
	go func() {
		defer wait.Done()
		io.Copy(local, remote)
		if closer, ok := local.(interface{ CloseWrite() error }); ok {
			closer.CloseWrite()
		} else {
			local.Close()
		}
	}()
	wait.Wait()
}

func (t *Tunnel) handleUDP(request *udp.ForwarderRequest) {
	id := request.ID()
	source := endpointAddrPort(id.RemoteAddress, id.RemotePort)
	target := endpointAddrPort(id.LocalAddress, id.LocalPort)

	var queue waiter.Queue
	endpoint, err := request.CreateEndpoint(&queue)
	if err != nil {
		return
	}
	go t.udp.attach(source, target, gonet.NewUDPConn(&queue, endpoint))
}
