/* SPDX-License-Identifier: MIT
 *
 * Phobos
 */

package phobos

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"net/netip"
	"testing"

	"golang.zx2c4.com/wireguard/windows/phobos/cobf"
)

func digestOf(data []byte) string {
	sum := sha256.Sum256(data)
	return hex.EncodeToString(sum[:])
}

func mustDecodeHex(t *testing.T, value string) []byte {
	t.Helper()
	data, err := hex.DecodeString(value)
	if err != nil {
		t.Fatalf("bad hex vector: %v", err)
	}
	return data
}

func TestMaskMatchesGolden(t *testing.T) {
	for _, vector := range maskVectors {
		buf := make([]byte, vector.length)
		NewObfuscator([]byte(vector.key)).xorData(buf)
		if got := digestOf(buf); got != vector.digest {
			t.Errorf("mask digest mismatch for key %q length %d: got %s want %s",
				vector.key, vector.length, got, vector.digest)
		}
	}
}

func TestMaskCacheStaysConsistent(t *testing.T) {
	obfuscator := NewObfuscator([]byte("Ic0OGtSf1BdMmMDzs7GmYRuPS/HGmNXsSU9EOWEeuQI="))
	for _, vector := range maskVectors {
		if vector.key != "Ic0OGtSf1BdMmMDzs7GmYRuPS/HGmNXsSU9EOWEeuQI=" {
			continue
		}
		for range 3 {
			buf := make([]byte, vector.length)
			obfuscator.xorData(buf)
			if got := digestOf(buf); got != vector.digest {
				t.Fatalf("cached mask drifted at length %d", vector.length)
			}
		}
	}
}

func TestStreamCipherMatchesGolden(t *testing.T) {
	for _, vector := range streamVectors {
		buf := make([]byte, vector.length)
		cipher := cobf.NewStreamCipher([]byte(vector.key))
		cipher.Apply(buf[:vector.split])
		cipher.Apply(buf[vector.split:])
		if got := digestOf(buf); got != vector.digest {
			t.Errorf("stream digest mismatch for key %q length %d split %d: got %s want %s",
				vector.key, vector.length, vector.split, got, vector.digest)
		}
	}
}

func TestDecodeMatchesGolden(t *testing.T) {
	for _, vector := range decodeVectors {
		encoded := mustDecodeHex(t, vector.encoded)
		want := mustDecodeHex(t, vector.decoded)
		buf := bytes.Clone(encoded)
		n := NewObfuscator([]byte(vector.key)).Decode(buf, len(buf), vector.obfuscateBytes)
		if n < 0 || !bytes.Equal(buf[:n], want) {
			t.Errorf("decode mismatch for key %q obfuscateBytes %d", vector.key, vector.obfuscateBytes)
		}
	}
}

func TestEncodeIsDecodable(t *testing.T) {
	for _, vector := range decodeVectors {
		payload := mustDecodeHex(t, vector.decoded)
		buf := make([]byte, BufferSize)
		copy(buf, payload)
		n := NewObfuscator([]byte(vector.key)).Encode(buf, len(payload), DefaultMaxDummy, vector.obfuscateBytes)
		if n < 0 {
			t.Fatalf("encode failed for key %q", vector.key)
		}
		n = NewObfuscator([]byte(vector.key)).Decode(buf[:n], n, vector.obfuscateBytes)
		if n < 0 || !bytes.Equal(buf[:n], payload) {
			t.Errorf("round trip failed for key %q obfuscateBytes %d", vector.key, vector.obfuscateBytes)
		}
	}
}

func TestBindingSuccessMatchesGolden(t *testing.T) {
	for _, vector := range bindingSuccessVectors {
		txid := mustDecodeHex(t, vector.txid)
		want := mustDecodeHex(t, vector.out)
		buf := make([]byte, 128)
		n := stunBuildBindingSuccess(buf, txid, netip.MustParseAddrPort(vector.addr))
		if n < 0 || !bytes.Equal(buf[:n], want) {
			t.Errorf("binding success mismatch for %s", vector.addr)
		}
	}
}

func TestStunFramingRoundTrip(t *testing.T) {
	var rng rng32 = 7
	for _, length := range []int{1, 4, 148, 1420, BufferSize - stunDataIndHeaderSize} {
		payload := make([]byte, length)
		for i := range payload {
			payload[i] = byte(i)
		}
		buf := make([]byte, BufferSize)
		copy(buf, payload)
		n := stunWrapDataIndication(buf, length, &rng)
		if n < 0 {
			t.Fatalf("wrap failed at length %d", length)
		}
		if !stunHasMagic(buf[:n]) || stunMessageType(buf) != stunDataIndication {
			t.Fatalf("wrapped frame is not a STUN data indication at length %d", length)
		}
		if unwrapped := stunUnwrapDataIndication(buf, n); unwrapped != length || !bytes.Equal(buf[:length], payload) {
			t.Fatalf("unwrap failed at length %d", length)
		}
	}
}

func TestStunWrapRejectsOverflow(t *testing.T) {
	var rng rng32 = 7
	buf := make([]byte, 64)
	if stunWrapDataIndication(buf, 60, &rng) >= 0 {
		t.Fatal("expected overflow rejection")
	}
}

func TestMediaFramingRoundTrip(t *testing.T) {
	params := MediaParams{PayloadType: 102, SSRC: 0xDEADBEEF, TimestampStep: 3000}
	masker := NewMasker(MaskingMEDIA, params)
	for _, length := range []int{4, 148, 1420} {
		payload := make([]byte, length)
		for i := range payload {
			payload[i] = byte(i * 7)
		}
		buf := make([]byte, BufferSize)
		copy(buf, payload)
		n := masker.OnDataWrap(buf, length)
		if n != length+rtpHeaderSize {
			t.Fatalf("unexpected wrapped length %d", n)
		}
		unwrapped := NewMasker(MaskingMEDIA, params).OnDataUnwrap(buf, n, netip.AddrPort{}, nil)
		if unwrapped != length || !bytes.Equal(buf[:length], payload) {
			t.Fatalf("media round trip failed at length %d", length)
		}
	}
}

func TestMediaSequenceAdvances(t *testing.T) {
	masker := NewMasker(MaskingMEDIA, MediaParams{PayloadType: 96, SSRC: 1, TimestampStep: 3000})
	buf := make([]byte, BufferSize)
	masker.OnDataWrap(buf, 64)
	first := [12]byte(buf[:12])
	masker.OnDataWrap(buf, 64)
	second := [12]byte(buf[:12])

	if first[0] != 0x80 || first[1] != 0x80|96 {
		t.Fatalf("unexpected RTP header start %x", first[:2])
	}
	if bytes.Equal(first[2:4], second[2:4]) {
		t.Fatal("RTP sequence number did not advance")
	}
	if bytes.Equal(first[4:8], second[4:8]) {
		t.Fatal("RTP timestamp did not advance")
	}
	if !bytes.Equal(first[8:12], second[8:12]) {
		t.Fatal("RTP SSRC must stay stable across frames")
	}
}

func TestParseMasking(t *testing.T) {
	for value, want := range map[string]Masking{
		"":      MaskingNone,
		"none":  MaskingNone,
		"NONE":  MaskingNone,
		" stun": MaskingSTUN,
		"MEDIA": MaskingMEDIA,
		"tls":   MaskingTLS,
	} {
		got, ok := ParseMasking(value)
		if !ok || got != want {
			t.Errorf("ParseMasking(%q) = %v, %v", value, got, ok)
		}
	}
	if _, ok := ParseMasking("quic"); ok {
		t.Error("expected unknown masking to be rejected")
	}
}
