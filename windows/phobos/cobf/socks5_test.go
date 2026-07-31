/* SPDX-License-Identifier: MIT
 *
 * Phobos
 */

package cobf

import (
	"bytes"
	"testing"
)

const (
	atypIPv4   = 0x01
	atypDomain = 0x03
	atypIPv6   = 0x04
)

var ipv6Addr = []byte{0x20, 0x01, 0x0d, 0xb8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1}

// Locks the wire layout of the SOCKS5 address block. The domain case carries
// the RFC 1928 length prefix, which the C builder once omitted while the C
// parser required it -- every UDP ASSOCIATE to a hostname was dropped and the
// session torn down.
var targetVectors = []struct {
	name string
	atyp byte
	addr []byte
	port uint16
	wire []byte
}{
	{"ipv4", atypIPv4, []byte{203, 0, 113, 7}, 51820,
		[]byte{0x01, 203, 0, 113, 7, 0xCA, 0x6C}},
	{"domain", atypDomain, []byte("example.com"), 53,
		[]byte{0x03, 11, 'e', 'x', 'a', 'm', 'p', 'l', 'e', '.', 'c', 'o', 'm', 0, 53}},
	{"ipv6", atypIPv6, ipv6Addr, 443,
		append(append([]byte{0x04}, ipv6Addr...), 0x01, 0xBB)},
}

func TestBuildTargetMatchesWireLayout(t *testing.T) {
	for _, tc := range targetVectors {
		out := make([]byte, MaxTargetSize)
		n := BuildTarget(out, tc.atyp, tc.addr, tc.port)
		if n < 0 {
			t.Fatalf("%s: build refused a %d byte buffer", tc.name, len(out))
		}
		if !bytes.Equal(out[:n], tc.wire) {
			t.Errorf("%s: built %x, want %x", tc.name, out[:n], tc.wire)
		}
	}
}

func TestParseTargetMatchesWireLayout(t *testing.T) {
	for _, tc := range targetVectors {
		atyp, addr, port, consumed := ParseTarget(tc.wire)
		if consumed != len(tc.wire) {
			t.Fatalf("%s: consumed %d of %d bytes", tc.name, consumed, len(tc.wire))
		}
		if atyp != tc.atyp || port != tc.port || !bytes.Equal(addr, tc.addr) {
			t.Errorf("%s: parsed atyp %d addr %x port %d, want %d, %x and %d",
				tc.name, atyp, addr, port, tc.atyp, tc.addr, tc.port)
		}
	}
}

func TestParseTargetReportsIncompleteAndUnsupported(t *testing.T) {
	for _, tc := range targetVectors {
		for cut := 1; cut < len(tc.wire); cut++ {
			if _, _, _, consumed := ParseTarget(tc.wire[:cut]); consumed != 0 {
				t.Fatalf("%s: truncated to %d bytes returned %d, want 0", tc.name, cut, consumed)
			}
		}
	}
	if _, _, _, consumed := ParseTarget([]byte{0x02, 1, 2, 3, 4, 0, 0}); consumed >= 0 {
		t.Errorf("unsupported ATYP returned %d, want a negative result", consumed)
	}
}

func TestBuildTargetRejectsShortBuffer(t *testing.T) {
	for _, tc := range targetVectors {
		out := make([]byte, len(tc.wire)-1)
		if n := BuildTarget(out, tc.atyp, tc.addr, tc.port); n >= 0 {
			t.Errorf("%s: build accepted a buffer one byte too small", tc.name)
		}
	}
}
