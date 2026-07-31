/* SPDX-License-Identifier: MIT
 *
 * Phobos
 */

package phobos

import (
	"bufio"
	"bytes"
	"context"
	"encoding/binary"
	"io"
	"math/rand"
	"net"
	"net/netip"
	"strconv"
	"testing"
	"time"
)

type fakeSocks5Server struct {
	listener net.Listener
	key      []byte
	masking  Masking
	media    MediaParams
	login    string
	password string
}

func startFakeSocks5Server(t *testing.T, key []byte, masking Masking, media MediaParams, login, password string) *fakeSocks5Server {
	t.Helper()
	listener, err := net.Listen("tcp4", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("unable to listen: %v", err)
	}
	server := &fakeSocks5Server{listener: listener, key: key, masking: masking, media: media, login: login, password: password}
	t.Cleanup(func() { listener.Close() })
	go server.run()
	return server
}

func (s *fakeSocks5Server) addr() netip.AddrPort {
	return s.listener.Addr().(*net.TCPAddr).AddrPort()
}

func (s *fakeSocks5Server) run() {
	for {
		conn, err := s.listener.Accept()
		if err != nil {
			return
		}
		go s.handle(newObfConn(conn, s.key, s.masking, s.media))
	}
}

func (s *fakeSocks5Server) handle(conn *obfConn) {
	defer conn.Close()
	reader := bufio.NewReader(conn)

	var greeting [2]byte
	if _, err := io.ReadFull(reader, greeting[:]); err != nil {
		return
	}
	methods := make([]byte, greeting[1])
	if _, err := io.ReadFull(reader, methods); err != nil {
		return
	}

	chosen := byte(methodNoAuth)
	if len(s.login) > 0 {
		chosen = methodUserPass
	}
	if _, err := conn.Write([]byte{socks5Version, chosen}); err != nil {
		return
	}
	if chosen == methodUserPass && !s.checkCredentials(conn, reader) {
		return
	}

	header := make([]byte, 262)
	if _, err := io.ReadFull(reader, header[:4]); err != nil {
		return
	}
	command := header[1]
	target, err := readTarget(reader, header[3:])
	if err != nil {
		return
	}

	switch command {
	case cmdConnect:
		s.serveConnect(conn, reader, target)
	case cmdUDPAssociate:
		s.serveUDP(conn, reader)
	default:
		conn.Write(buildReply(replyCommandNotSupported, netip.AddrPort{}))
	}
}

func (s *fakeSocks5Server) checkCredentials(conn *obfConn, reader *bufio.Reader) bool {
	var head [2]byte
	if _, err := io.ReadFull(reader, head[:]); err != nil {
		return false
	}
	login := make([]byte, head[1])
	io.ReadFull(reader, login)
	var passwordLength [1]byte
	io.ReadFull(reader, passwordLength[:])
	password := make([]byte, passwordLength[0])
	io.ReadFull(reader, password)

	if string(login) != s.login || string(password) != s.password {
		conn.Write([]byte{userPassVersion, 0x01})
		return false
	}
	conn.Write([]byte{userPassVersion, 0x00})
	return true
}

func (s *fakeSocks5Server) serveConnect(conn *obfConn, reader *bufio.Reader, target socks5Target) {
	host := target.domain
	if target.atyp != atypDomain {
		addr, _ := target.addrPort()
		host = addr.Addr().String()
	}
	upstream, err := net.Dial("tcp", net.JoinHostPort(host, strconv.Itoa(int(target.port))))
	if err != nil {
		conn.Write(buildReply(replyGeneralFailure, netip.AddrPort{}))
		return
	}
	defer upstream.Close()
	if _, err := conn.Write(buildReply(replySucceeded, netip.AddrPort{})); err != nil {
		return
	}
	go io.Copy(upstream, reader)
	io.Copy(conn, upstream)
}

func (s *fakeSocks5Server) serveUDP(conn *obfConn, reader *bufio.Reader) {
	if _, err := conn.Write(buildReply(replySucceeded, netip.AddrPort{})); err != nil {
		return
	}
	out := make([]byte, s5AccMax)
	for {
		var header [2]byte
		if _, err := io.ReadFull(reader, header[:]); err != nil {
			return
		}
		frame := make([]byte, binary.BigEndian.Uint16(header[:]))
		if _, err := io.ReadFull(reader, frame); err != nil {
			return
		}
		target, offset, err := parseUDPHeader(frame)
		if err != nil {
			return
		}
		source, _ := target.addrPort()
		echoed, err := buildUDPFrame(targetFromAddrPort(source), frame[offset:], out)
		if err != nil {
			return
		}
		if _, err := conn.Write(echoed); err != nil {
			return
		}
	}
}

func startEchoServer(t *testing.T) net.Addr {
	t.Helper()
	listener, err := net.Listen("tcp4", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("unable to listen: %v", err)
	}
	t.Cleanup(func() { listener.Close() })
	go func() {
		for {
			conn, err := listener.Accept()
			if err != nil {
				return
			}
			go func() {
				defer conn.Close()
				io.Copy(conn, conn)
			}()
		}
	}()
	return listener.Addr()
}

func startEchoServer6(t *testing.T) net.Addr {
	t.Helper()
	listener, err := net.Listen("tcp6", "[::1]:0")
	if err != nil {
		t.Skipf("IPv6 loopback unavailable: %v", err)
	}
	t.Cleanup(func() { listener.Close() })
	go func() {
		for {
			conn, err := listener.Accept()
			if err != nil {
				return
			}
			go func() {
				defer conn.Close()
				io.Copy(conn, conn)
			}()
		}
	}()
	return listener.Addr()
}

var socks5TestKey = []byte("Ic0OGtSf1BdMmMDzs7GmYRuPS/HGmNXsSU9EOWEeuQI=")

var socks5TestCases = []struct {
	name    string
	masking Masking
	media   MediaParams
}{
	{"none", MaskingNone, MediaParams{}},
	{"stun", MaskingSTUN, MediaParams{}},
	{"media", MaskingMEDIA, MediaParams{PayloadType: 102, SSRC: 0xC0FFEE, TimestampStep: 3000}},
	{"tls", MaskingTLS, MediaParams{}},
}

func TestSocks5ClientConnect(t *testing.T) {
	echo := startEchoServer(t)
	echoPort := uint16(echo.(*net.TCPAddr).Port)

	for _, tc := range socks5TestCases {
		t.Run(tc.name, func(t *testing.T) {
			server := startFakeSocks5Server(t, socks5TestKey, tc.masking, tc.media, "user", "pass")
			client := NewSocks5Client(Socks5Config{
				Target:   server.addr(),
				Key:      socks5TestKey,
				Masking:  tc.masking,
				Media:    tc.media,
				Login:    "user",
				Password: "pass",
				Logf:     t.Logf,
			})

			conn, err := client.DialTCP(context.Background(), "127.0.0.1", echoPort)
			if err != nil {
				t.Fatalf("dial failed: %v", err)
			}
			defer conn.Close()

			payload := make([]byte, 200*1024)
			rand.New(rand.NewSource(31)).Read(payload)

			go func() {
				conn.Write(payload)
			}()
			received := make([]byte, len(payload))
			conn.SetReadDeadline(time.Now().Add(15 * time.Second))
			if _, err := io.ReadFull(conn, received); err != nil {
				t.Fatalf("read failed: %v", err)
			}
			if !bytes.Equal(received, payload) {
				t.Fatal("echoed payload does not match")
			}
		})
	}
}

func TestSocks5ClientUDP(t *testing.T) {
	for _, tc := range socks5TestCases {
		t.Run(tc.name, func(t *testing.T) {
			server := startFakeSocks5Server(t, socks5TestKey, tc.masking, tc.media, "", "")
			client := NewSocks5Client(Socks5Config{
				Target:  server.addr(),
				Key:     socks5TestKey,
				Masking: tc.masking,
				Media:   tc.media,
				Logf:    t.Logf,
			})

			session, err := client.DialUDP(context.Background())
			if err != nil {
				t.Fatalf("udp associate failed: %v", err)
			}
			defer session.Close()

			destination := netip.MustParseAddrPort("8.8.8.8:53")
			buf := make([]byte, s5AccMax)
			for i := range 8 {
				payload := bytes.Repeat([]byte{byte(i)}, 100+i*137)
				if err := session.WriteTo(payload, destination); err != nil {
					t.Fatalf("write failed: %v", err)
				}
				n, source, err := session.ReadFrom(buf)
				if err != nil {
					t.Fatalf("read failed: %v", err)
				}
				if source != destination {
					t.Fatalf("source = %v, want %v", source, destination)
				}
				if !bytes.Equal(buf[:n], payload) {
					t.Fatalf("datagram %d does not match", i)
				}
			}
		})
	}
}

func TestSocks5ClientConnectIPv6Target(t *testing.T) {
	echo := startEchoServer6(t)
	echoPort := uint16(echo.(*net.TCPAddr).Port)

	server := startFakeSocks5Server(t, socks5TestKey, MaskingNone, MediaParams{}, "", "")
	client := NewSocks5Client(Socks5Config{Target: server.addr(), Key: socks5TestKey, Logf: t.Logf})

	conn, err := client.DialTCP(context.Background(), "::1", echoPort)
	if err != nil {
		t.Fatalf("dial failed: %v", err)
	}
	defer conn.Close()

	payload := []byte("phobos-ipv6-target")
	if _, err := conn.Write(payload); err != nil {
		t.Fatalf("write failed: %v", err)
	}
	received := make([]byte, len(payload))
	conn.SetReadDeadline(time.Now().Add(15 * time.Second))
	if _, err := io.ReadFull(conn, received); err != nil {
		t.Fatalf("read failed: %v", err)
	}
	if !bytes.Equal(received, payload) {
		t.Fatal("echoed payload does not match")
	}
}

func TestSocks5ClientUDPIPv6Target(t *testing.T) {
	server := startFakeSocks5Server(t, socks5TestKey, MaskingNone, MediaParams{}, "", "")
	client := NewSocks5Client(Socks5Config{Target: server.addr(), Key: socks5TestKey, Logf: t.Logf})

	session, err := client.DialUDP(context.Background())
	if err != nil {
		t.Fatalf("udp associate failed: %v", err)
	}
	defer session.Close()

	destination := netip.MustParseAddrPort("[2001:4860:4860::8888]:53")
	payload := []byte("phobos-ipv6-datagram")
	if err := session.WriteTo(payload, destination); err != nil {
		t.Fatalf("write failed: %v", err)
	}
	buf := make([]byte, s5AccMax)
	n, source, err := session.ReadFrom(buf)
	if err != nil {
		t.Fatalf("read failed: %v", err)
	}
	if source != destination {
		t.Fatalf("source = %v, want %v", source, destination)
	}
	if !bytes.Equal(buf[:n], payload) {
		t.Fatal("echoed datagram does not match")
	}
}

func TestSocks5ClientRejectsWrongCredentials(t *testing.T) {
	server := startFakeSocks5Server(t, socks5TestKey, MaskingSTUN, MediaParams{}, "user", "pass")
	client := NewSocks5Client(Socks5Config{
		Target:   server.addr(),
		Key:      socks5TestKey,
		Masking:  MaskingSTUN,
		Login:    "user",
		Password: "wrong",
		Logf:     t.Logf,
	})
	if _, err := client.DialTCP(context.Background(), "127.0.0.1", 80); err == nil {
		t.Fatal("expected an authentication failure")
	}
}

func TestSocks5LocalListener(t *testing.T) {
	echo := startEchoServer(t)
	echoPort := uint16(echo.(*net.TCPAddr).Port)
	server := startFakeSocks5Server(t, socks5TestKey, MaskingMEDIA, socks5MediaParamsForTest(), "user", "pass")

	client := NewSocks5Client(Socks5Config{
		Target:     server.addr(),
		Key:        socks5TestKey,
		Masking:    MaskingMEDIA,
		Media:      socks5MediaParamsForTest(),
		Login:      "user",
		Password:   "pass",
		ListenPort: 0,
		Logf:       t.Logf,
	})
	client.config.ListenPort = freePort(t)
	if err := client.Start(); err != nil {
		t.Fatalf("unable to start the listener: %v", err)
	}
	defer client.Stop()

	conn, err := net.Dial("tcp4", net.JoinHostPort("127.0.0.1", strconv.Itoa(int(client.ListenPort()))))
	if err != nil {
		t.Fatalf("unable to reach the local listener: %v", err)
	}
	defer conn.Close()

	conn.Write(buildGreeting(methodNoAuth, methodUserPass))
	var method [2]byte
	if _, err := io.ReadFull(conn, method[:]); err != nil {
		t.Fatalf("no method reply: %v", err)
	}
	if method[1] != methodUserPass {
		t.Fatalf("method = %d, want %d", method[1], methodUserPass)
	}
	credentials, _ := buildUserPass("user", "pass")
	conn.Write(credentials)
	if _, err := io.ReadFull(conn, method[:]); err != nil || method[1] != 0 {
		t.Fatalf("authentication rejected: %v", err)
	}

	conn.Write(buildRequest(cmdConnect, targetFromHostPort("127.0.0.1", echoPort)))
	buf := make([]byte, 262)
	reply, _, err := readReply(conn, buf)
	if err != nil || reply != replySucceeded {
		t.Fatalf("connect refused: reply=%d err=%v", reply, err)
	}

	payload := []byte("phobos socks5 through the local listener")
	conn.Write(payload)
	received := make([]byte, len(payload))
	conn.SetReadDeadline(time.Now().Add(10 * time.Second))
	if _, err := io.ReadFull(conn, received); err != nil {
		t.Fatalf("read failed: %v", err)
	}
	if !bytes.Equal(received, payload) {
		t.Fatal("echoed payload does not match")
	}
}

func socks5MediaParamsForTest() MediaParams {
	return MediaParams{PayloadType: 102, SSRC: 0xC0FFEE, TimestampStep: 3000}
}

func freePort(t *testing.T) uint16 {
	t.Helper()
	listener, err := net.Listen("tcp4", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("unable to reserve a port: %v", err)
	}
	port := uint16(listener.Addr().(*net.TCPAddr).Port)
	listener.Close()
	return port
}
