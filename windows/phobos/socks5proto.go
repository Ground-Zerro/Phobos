/* SPDX-License-Identifier: MIT
 *
 * Phobos
 */

package phobos

import (
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"net/netip"
	"slices"
	"unsafe"

	"golang.zx2c4.com/wireguard/windows/phobos/cobf"
)

const (
	socks5Version = 0x05

	cmdConnect      = 0x01
	cmdUDPAssociate = 0x03

	atypIPv4   = 0x01
	atypDomain = 0x03
	atypIPv6   = 0x04

	methodNoAuth   = 0x00
	methodUserPass = 0x02
	methodNone     = 0xFF

	replySucceeded             = 0x00
	replyGeneralFailure        = 0x01
	replyCommandNotSupported   = 0x07
	replyAddressTypeNotAllowed = 0x08

	userPassVersion = 0x01
	credentialMax   = 255
)

var (
	errNotSocks5       = errors.New("phobos: not a SOCKS5 message")
	errUnsupportedATYP = errors.New("phobos: unsupported SOCKS5 address type")
)

type socks5Target struct {
	atyp   byte
	addr   []byte
	domain string
	port   uint16
}

func targetFromAddrPort(addr netip.AddrPort) socks5Target {
	if addr.Addr().Is4() || addr.Addr().Is4In6() {
		ip := addr.Addr().As4()
		return socks5Target{atyp: atypIPv4, addr: ip[:], port: addr.Port()}
	}
	ip := addr.Addr().As16()
	return socks5Target{atyp: atypIPv6, addr: ip[:], port: addr.Port()}
}

func targetFromHostPort(host string, port uint16) socks5Target {
	if addr, err := netip.ParseAddr(host); err == nil {
		return targetFromAddrPort(netip.AddrPortFrom(addr, port))
	}
	return socks5Target{atyp: atypDomain, domain: host, port: port}
}

func (t socks5Target) size() int {
	switch t.atyp {
	case atypIPv4:
		return 1 + 4 + 2
	case atypIPv6:
		return 1 + 16 + 2
	default:
		return 1 + 1 + len(t.domain) + 2
	}
}

func (t socks5Target) addrBytes() []byte {
	if t.atyp == atypDomain {
		return unsafe.Slice(unsafe.StringData(t.domain), len(t.domain))
	}
	return t.addr
}

func (t socks5Target) appendTo(out []byte) []byte {
	base := len(out)
	out = slices.Grow(out, t.size())
	n := cobf.BuildTarget(out[base:base+t.size()], t.atyp, t.addrBytes(), t.port)
	if n < 0 {
		return out[:base]
	}
	return out[:base+n]
}

func (t socks5Target) addrPort() (netip.AddrPort, bool) {
	addr, ok := netip.AddrFromSlice(t.addr)
	if !ok {
		return netip.AddrPort{}, false
	}
	return netip.AddrPortFrom(addr, t.port), true
}

func parseTarget(buf []byte) (socks5Target, int, error) {
	atyp, addr, port, consumed := cobf.ParseTarget(buf)
	switch {
	case consumed == 0:
		return socks5Target{}, 0, io.ErrUnexpectedEOF
	case consumed < 0:
		return socks5Target{atyp: buf[0]}, 0, errUnsupportedATYP
	}
	target := socks5Target{atyp: atyp, port: port}
	if atyp == atypDomain {
		target.domain = string(addr)
	} else {
		target.addr = addr
	}
	return target, consumed, nil
}

func buildGreeting(methods ...byte) []byte {
	out := make([]byte, 0, 2+len(methods))
	out = append(out, socks5Version, byte(len(methods)))
	return append(out, methods...)
}

func buildUserPass(login, password string) ([]byte, error) {
	if len(login) > credentialMax || len(password) > credentialMax {
		return nil, errors.New("phobos: SOCKS5 credentials are too long")
	}
	out := make([]byte, 0, 3+len(login)+len(password))
	out = append(out, userPassVersion, byte(len(login)))
	out = append(out, login...)
	out = append(out, byte(len(password)))
	return append(out, password...), nil
}

func buildRequest(command byte, target socks5Target) []byte {
	out := make([]byte, 0, 3+target.size())
	out = append(out, socks5Version, command, 0x00)
	return target.appendTo(out)
}

func buildReply(reply byte, bound netip.AddrPort) []byte {
	target := socks5Target{atyp: atypIPv4, addr: make([]byte, 4)}
	if bound.IsValid() {
		target = targetFromAddrPort(bound)
	}
	out := make([]byte, 0, 3+target.size())
	out = append(out, socks5Version, reply, 0x00)
	return target.appendTo(out)
}

func readReply(reader io.Reader, buf []byte) (byte, socks5Target, error) {
	if _, err := io.ReadFull(reader, buf[:4]); err != nil {
		return 0, socks5Target{}, err
	}
	if buf[0] != socks5Version {
		return 0, socks5Target{}, errNotSocks5
	}
	reply := buf[1]

	var addressLength int
	switch buf[3] {
	case atypIPv4:
		addressLength = 4
	case atypIPv6:
		addressLength = 16
	case atypDomain:
		if _, err := io.ReadFull(reader, buf[4:5]); err != nil {
			return reply, socks5Target{}, err
		}
		addressLength = 1 + int(buf[4])
		if _, err := io.ReadFull(reader, buf[5:4+addressLength+2]); err != nil {
			return reply, socks5Target{}, err
		}
		target, _, err := parseTarget(buf[3 : 4+addressLength+2])
		return reply, target, err
	default:
		return reply, socks5Target{}, errUnsupportedATYP
	}

	if _, err := io.ReadFull(reader, buf[4:4+addressLength+2]); err != nil {
		return reply, socks5Target{}, err
	}
	target, _, err := parseTarget(buf[3 : 4+addressLength+2])
	return reply, target, err
}

func buildUDPFrame(target socks5Target, payload []byte, out []byte) ([]byte, error) {
	body := 3 + target.size() + len(payload)
	if body > s5AccMax-2 {
		return nil, fmt.Errorf("phobos: UDP payload of %d bytes does not fit a tunnel frame", len(payload))
	}
	out = binary.BigEndian.AppendUint16(out[:0], uint16(body))
	out = append(out, 0x00, 0x00, 0x00)
	out = target.appendTo(out)
	return append(out, payload...), nil
}

func parseUDPHeader(frame []byte) (socks5Target, int, error) {
	if len(frame) < 4 || frame[2] != 0 {
		return socks5Target{}, 0, errNotSocks5
	}
	target, consumed, err := parseTarget(frame[3:])
	if err != nil {
		return target, 0, err
	}
	return target, 3 + consumed, nil
}
