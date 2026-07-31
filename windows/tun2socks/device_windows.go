/* SPDX-License-Identifier: MIT
 *
 * Phobos
 */

package tun2socks

import (
	"context"
	"errors"
	"sync/atomic"

	"golang.org/x/sys/windows"
	"golang.zx2c4.com/wireguard/windows/wintun"
	"gvisor.dev/gvisor/pkg/buffer"
	"gvisor.dev/gvisor/pkg/tcpip"
	"gvisor.dev/gvisor/pkg/tcpip/header"
	"gvisor.dev/gvisor/pkg/tcpip/link/channel"
	"gvisor.dev/gvisor/pkg/tcpip/stack"
)

const linkQueueDepth = 512

type device struct {
	session  *wintun.Session
	endpoint *channel.Endpoint
	cancel   context.CancelFunc
	done     chan struct{}

	reportedDrop atomic.Bool
}

func newDevice(session *wintun.Session, mtu uint32) *device {
	return &device{
		session:  session,
		endpoint: channel.New(linkQueueDepth, mtu, ""),
		done:     make(chan struct{}, 2),
	}
}

func (d *device) start(logf func(string, ...any)) {
	ctx, cancel := context.WithCancel(context.Background())
	d.cancel = cancel
	go d.pumpInbound(ctx, logf)
	go d.pumpOutbound(ctx, logf)
}

func (d *device) stop() {
	if d.cancel != nil {
		d.cancel()
	}
	d.endpoint.Close()
	<-d.done
	<-d.done
}

func (d *device) pumpInbound(ctx context.Context, logf func(string, ...any)) {
	defer func() { d.done <- struct{}{} }()
	event := d.session.ReadWaitEvent()
	for {
		if ctx.Err() != nil {
			return
		}
		packet, err := d.session.ReceivePacket()
		switch {
		case err == nil:
			d.inject(packet)
			d.session.ReleaseReceivePacket(packet)
		case errors.Is(err, wintun.ErrNoMorePackets):
			if _, err := windows.WaitForSingleObject(event, 250); err != nil {
				logf("tun2socks: wait failed: %v", err)
				return
			}
		default:
			if ctx.Err() == nil {
				logf("tun2socks: adapter read failed: %v", err)
			}
			return
		}
	}
}

func (d *device) inject(packet []byte) {
	if len(packet) < 1 {
		return
	}
	var protocol tcpip.NetworkProtocolNumber
	switch header.IPVersion(packet) {
	case header.IPv4Version:
		protocol = header.IPv4ProtocolNumber
	case header.IPv6Version:
		protocol = header.IPv6ProtocolNumber
	default:
		return
	}
	buf := stack.NewPacketBuffer(stack.PacketBufferOptions{
		Payload: buffer.MakeWithData(packet),
	})
	d.endpoint.InjectInbound(protocol, buf)
	buf.DecRef()
}

func (d *device) pumpOutbound(ctx context.Context, logf func(string, ...any)) {
	defer func() { d.done <- struct{}{} }()
	for {
		packet := d.endpoint.ReadContext(ctx)
		if packet == nil {
			return
		}
		view := packet.ToView()
		size := view.Size()
		out, err := d.session.AllocateSendPacket(size)
		if err == nil {
			view.Read(out)
			d.session.SendPacket(out)
		} else if !d.reportedDrop.Swap(true) {
			logf("tun2socks: adapter send ring is full, dropping packets: %v", err)
		}
		view.Release()
		packet.DecRef()
	}
}
