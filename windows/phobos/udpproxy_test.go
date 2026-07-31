/* SPDX-License-Identifier: MIT
 *
 * Phobos
 */

package phobos

import (
	"bytes"
	"net"
	"net/netip"
	"testing"
	"time"
)

type fakeServer struct {
	conn           *net.UDPConn
	key            []byte
	masking        Masking
	media          MediaParams
	obfuscateBytes int
}

func startFakeServer(t *testing.T, key []byte, masking Masking, media MediaParams, obfuscateBytes int) *fakeServer {
	t.Helper()
	conn, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1)})
	if err != nil {
		t.Fatalf("unable to listen: %v", err)
	}
	server := &fakeServer{conn: conn, key: key, masking: masking, media: media, obfuscateBytes: obfuscateBytes}
	t.Cleanup(func() { conn.Close() })
	go server.run()
	return server
}

func (s *fakeServer) addr() netip.AddrPort {
	return s.conn.LocalAddr().(*net.UDPAddr).AddrPort()
}

func (s *fakeServer) run() {
	buf := make([]byte, BufferSize)
	obfuscator := NewObfuscator(s.key)
	masker := NewMasker(s.masking, s.media)
	for {
		n, source, err := s.conn.ReadFromUDPAddrPort(buf)
		if err != nil {
			return
		}
		send := func(p []byte) (int, error) { return s.conn.WriteToUDPAddrPort(p, source) }

		length := n
		if masker != nil {
			if length = masker.OnDataUnwrap(buf, length, source, send); length <= 0 {
				continue
			}
		}
		if length = obfuscator.Decode(buf, length, s.obfuscateBytes); length < 4 {
			continue
		}

		buf[0] = TypeHandshakeResponse
		length = obfuscator.Encode(buf, length, DefaultMaxDummy, s.obfuscateBytes)
		if masker != nil {
			if length = masker.OnDataWrap(buf, length); length <= 0 {
				continue
			}
		}
		send(buf[:length])
	}
}

func handshakePacket(length int) []byte {
	packet := make([]byte, length)
	for i := range packet {
		packet[i] = byte(i * 3)
	}
	packet[0], packet[1], packet[2], packet[3] = TypeHandshake, 0, 0, 0
	return packet
}

func TestUDPProxyRoundTrip(t *testing.T) {
	key := []byte("Ic0OGtSf1BdMmMDzs7GmYRuPS/HGmNXsSU9EOWEeuQI=")
	cases := []struct {
		name           string
		masking        Masking
		media          MediaParams
		obfuscateBytes int
	}{
		{"none", MaskingNone, MediaParams{}, 0},
		{"stun", MaskingSTUN, MediaParams{}, 0},
		{"media", MaskingMEDIA, MediaParams{PayloadType: 102, SSRC: 0xC0FFEE, TimestampStep: 3000}, MediaObfuscateBytesDefault},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			server := startFakeServer(t, key, tc.masking, tc.media, tc.obfuscateBytes)

			proxy := NewUDPProxy(UDPProxyConfig{
				Target:         server.addr(),
				Key:            key,
				Masking:        tc.masking,
				Media:          tc.media,
				MaxDummy:       DefaultMaxDummy,
				ObfuscateBytes: tc.obfuscateBytes,
				Logf:           t.Logf,
			})
			if err := proxy.Start(); err != nil {
				t.Fatalf("unable to start proxy: %v", err)
			}
			t.Cleanup(proxy.Stop)

			client, err := net.DialUDP("udp4", nil, &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1), Port: int(proxy.ListenPort())})
			if err != nil {
				t.Fatalf("unable to dial proxy: %v", err)
			}
			defer client.Close()

			for _, length := range []int{148, 92, 1420} {
				packet := handshakePacket(length)
				if _, err := client.Write(packet); err != nil {
					t.Fatalf("unable to send: %v", err)
				}

				client.SetReadDeadline(time.Now().Add(5 * time.Second))
				reply := make([]byte, BufferSize)
				n, err := client.Read(reply)
				if err != nil {
					t.Fatalf("no reply for length %d: %v", length, err)
				}
				if n != length {
					t.Fatalf("reply length %d, want %d", n, length)
				}
				expected := bytes.Clone(packet)
				expected[0] = TypeHandshakeResponse
				if !bytes.Equal(reply[:n], expected) {
					t.Fatalf("reply payload mismatch at length %d", length)
				}
			}
		})
	}
}

func TestUDPProxyRejectsEmptyKey(t *testing.T) {
	proxy := NewUDPProxy(UDPProxyConfig{Target: netip.MustParseAddrPort("127.0.0.1:1")})
	if err := proxy.Start(); err == nil {
		t.Fatal("expected an error for an empty key")
	}
}

func TestUDPProxyRejectsUnresolvedTarget(t *testing.T) {
	proxy := NewUDPProxy(UDPProxyConfig{Key: []byte("key")})
	if err := proxy.Start(); err == nil {
		t.Fatal("expected an error for an unresolved target")
	}
}

func TestUDPProxyStopIsIdempotent(t *testing.T) {
	server := startFakeServer(t, []byte("key"), MaskingNone, MediaParams{}, 0)
	proxy := NewUDPProxy(UDPProxyConfig{Target: server.addr(), Key: []byte("key"), Logf: t.Logf})
	if err := proxy.Start(); err != nil {
		t.Fatalf("unable to start proxy: %v", err)
	}
	proxy.Stop()
	proxy.Stop()
}
