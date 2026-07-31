//go:build phoboscref

/* SPDX-License-Identifier: MIT
 *
 * Phobos
 */

package phobos

import (
	"bytes"
	"encoding/binary"
	"hash/crc32"
	"math/rand"
	"net/netip"
	"testing"

	"golang.zx2c4.com/wireguard/windows/phobos/cref"
)

var referenceAddrs = []netip.AddrPort{
	netip.MustParseAddrPort("127.0.0.1:51820"),
	netip.MustParseAddrPort("10.0.0.7:1"),
	netip.MustParseAddrPort("203.0.113.42:65535"),
}

func TestStunBindingSuccessMatchesReference(t *testing.T) {
	rng := rand.New(rand.NewSource(6))
	for _, addr := range referenceAddrs {
		txid := make([]byte, 12)
		rng.Read(txid)
		want := cref.StunBindingSuccess(txid, addr)
		got := make([]byte, 128)
		n := stunBuildBindingSuccess(got, txid, addr)
		if n < 0 || !bytes.Equal(got[:n], want) {
			t.Fatalf("binding success mismatch for %v:\n got %x\nwant %x", addr, got[:max(n, 0)], want)
		}
	}
}

func TestStunBindingRequestMatchesReference(t *testing.T) {
	var rng rng32 = 12345
	buf := make([]byte, 128)
	n := stunBuildBindingRequest(buf, &rng)
	reference := cref.StunBindingRequest()

	if n != len(reference) {
		t.Fatalf("binding request size mismatch: got %d want %d", n, len(reference))
	}
	if !bytes.Equal(buf[:8], reference[:8]) {
		t.Fatalf("header mismatch: got %x want %x", buf[:8], reference[:8])
	}
	if !bytes.Equal(buf[20:24], reference[20:24]) {
		t.Fatalf("fingerprint attribute header mismatch: got %x want %x", buf[20:24], reference[20:24])
	}
	fingerprinted := bytes.Clone(buf[:20])
	fingerprinted[2], fingerprinted[3] = 0, 0
	want := cref.CRC32(fingerprinted) ^ stunFingerprintXOR
	if got := binary.BigEndian.Uint32(buf[24:]); got != want {
		t.Fatalf("fingerprint mismatch: got %08x want %08x", got, want)
	}
}

func TestCRC32MatchesReference(t *testing.T) {
	rng := rand.New(rand.NewSource(11))
	for _, length := range []int{0, 1, 20, 32, 1000} {
		data := make([]byte, length)
		rng.Read(data)
		if got, want := crc32.ChecksumIEEE(data), cref.CRC32(data); got != want {
			t.Fatalf("crc32 mismatch at length %d: got %08x want %08x", length, got, want)
		}
	}
}

func TestStunFramingInteropWithReference(t *testing.T) {
	rng := rand.New(rand.NewSource(7))
	var maskerRNG rng32 = 999
	for _, length := range []int{1, 4, 148, 1024, 1420} {
		payload := make([]byte, length)
		rng.Read(payload)

		buf := make([]byte, BufferSize)
		copy(buf, payload)
		n := stunWrapDataIndication(buf, length, &maskerRNG)
		if n < 0 {
			t.Fatalf("go wrap failed at length %d", length)
		}
		if !bytes.Equal(cref.StunUnwrap(buf[:n]), payload) {
			t.Fatalf("C cannot unwrap Go STUN frame at length %d", length)
		}

		frame := cref.StunWrap(payload, BufferSize)
		buf = make([]byte, BufferSize)
		copy(buf, frame)
		n = stunUnwrapDataIndication(buf, len(frame))
		if n < 0 || !bytes.Equal(buf[:n], payload) {
			t.Fatalf("Go cannot unwrap C STUN frame at length %d", length)
		}
	}
}

func TestMediaFramingInteropWithReference(t *testing.T) {
	rng := rand.New(rand.NewSource(8))
	params := MediaParams{PayloadType: 102, SSRC: 0xDEADBEEF, TimestampStep: 3000}
	for _, length := range []int{4, 148, 1024, 1420} {
		payload := make([]byte, length)
		rng.Read(payload)

		masker := NewMasker(MaskingMEDIA, params)
		buf := make([]byte, BufferSize)
		copy(buf, payload)
		n := masker.OnDataWrap(buf, length)
		if n < 0 {
			t.Fatalf("go wrap failed at length %d", length)
		}
		if !bytes.Equal(cref.MediaUnwrap(buf[:n], params.PayloadType, params.SSRC), payload) {
			t.Fatalf("C cannot unwrap Go RTP frame at length %d", length)
		}

		frame := cref.MediaWrap(payload, params.PayloadType, params.SSRC, params.TimestampStep, BufferSize)
		buf = make([]byte, BufferSize)
		copy(buf, frame)
		n = NewMasker(MaskingMEDIA, params).OnDataUnwrap(buf, len(frame), referenceAddrs[0], nil)
		if n < 0 || !bytes.Equal(buf[:n], payload) {
			t.Fatalf("Go cannot unwrap C RTP frame at length %d", length)
		}
	}
}

func TestMediaHeaderMatchesReferenceLayout(t *testing.T) {
	params := MediaParams{PayloadType: 111, SSRC: 0x01020304, TimestampStep: 1500}
	payload := bytes.Repeat([]byte{0x33}, 64)

	buf := make([]byte, BufferSize)
	copy(buf, payload)
	n := NewMasker(MaskingMEDIA, params).OnDataWrap(buf, len(payload))
	reference := cref.MediaWrap(payload, params.PayloadType, params.SSRC, params.TimestampStep, BufferSize)

	if n != len(reference) {
		t.Fatalf("frame length mismatch: got %d want %d", n, len(reference))
	}
	if buf[0] != reference[0] || buf[1] != reference[1] {
		t.Fatalf("RTP flags/payload type mismatch: got %x want %x", buf[:2], reference[:2])
	}
	if !bytes.Equal(buf[8:12], reference[8:12]) {
		t.Fatalf("SSRC mismatch: got %x want %x", buf[8:12], reference[8:12])
	}
	if !bytes.Equal(buf[rtpHeaderSize:n], reference[rtpHeaderSize:]) {
		t.Fatal("payload mismatch")
	}
}

func TestMediaPresetsMatchReference(t *testing.T) {
	if len(mediaPresets) != 50 {
		t.Fatalf("preset table size drifted: %d", len(mediaPresets))
	}
	seen := map[mediaPreset]bool{}
	for _, preset := range mediaPresets {
		if preset.payloadType < 96 || preset.payloadType > 127 {
			t.Fatalf("payload type %d outside the dynamic RTP range", preset.payloadType)
		}
		seen[preset] = true
	}
	for range 4000 {
		var payloadType uint8
		step := cref.PickMediaPreset(&payloadType)
		if !seen[mediaPreset{payloadType, step}] {
			t.Fatalf("reference produced preset {%d,%d} missing from the Go table", payloadType, step)
		}
	}
}
