//go:build phoboscref

/* SPDX-License-Identifier: MIT
 *
 * Phobos
 */

package phobos

import (
	"bytes"
	"math/rand"
	"testing"

	"golang.zx2c4.com/wireguard/windows/phobos/cobf"
	"golang.zx2c4.com/wireguard/windows/phobos/cref"
)

var referenceKeys = [][]byte{
	[]byte("k"),
	[]byte("phobos"),
	[]byte("Ic0OGtSf1BdMmMDzs7GmYRuPS/HGmNXsSU9EOWEeuQI="),
	bytes.Repeat([]byte{0xFE}, 200),
}

func TestXORMatchesReference(t *testing.T) {
	rng := rand.New(rand.NewSource(1))
	for _, key := range referenceKeys {
		for _, length := range []int{1, 4, 16, 63, 64, 148, 1499, 1500, 1501, 4096, 9000} {
			data := make([]byte, length)
			rng.Read(data)
			want := cref.XOR(data, key)
			got := bytes.Clone(data)
			NewObfuscator(key).xorData(got)
			if !bytes.Equal(got, want) {
				t.Fatalf("xor mismatch: keylen=%d length=%d", len(key), length)
			}
		}
	}
}

func TestXORCacheMatchesReference(t *testing.T) {
	rng := rand.New(rand.NewSource(2))
	key := referenceKeys[2]
	obfuscator := NewObfuscator(key)
	for range 300 {
		length := 1 + rng.Intn(1600)
		data := make([]byte, length)
		rng.Read(data)
		want := cref.XOR(data, key)
		got := bytes.Clone(data)
		obfuscator.xorData(got)
		if !bytes.Equal(got, want) {
			t.Fatalf("cached xor mismatch at length %d", length)
		}
	}
}

func TestStreamCipherMatchesReference(t *testing.T) {
	rng := rand.New(rand.NewSource(3))
	for _, key := range referenceKeys {
		for _, length := range []int{1, 64, 65, 1000, 20000} {
			data := make([]byte, length)
			rng.Read(data)
			split := length / 3
			want := cref.Stream(data, key, split)
			got := bytes.Clone(data)
			cipher := cobf.NewStreamCipher(key)
			cipher.Apply(got[:split])
			cipher.Apply(got[split:])
			if !bytes.Equal(got, want) {
				t.Fatalf("stream cipher mismatch: keylen=%d length=%d", len(key), length)
			}
		}
	}
}

var wireLengths = []int{32, 64, 92, 148, 176, 1024, 1420, 2000, 9000}

func goEncode(key, payload []byte, maxDummy, obfuscateBytes int) []byte {
	buf := make([]byte, BufferSize)
	copy(buf, payload)
	n := NewObfuscator(key).Encode(buf, len(payload), maxDummy, obfuscateBytes)
	if n < 0 {
		return nil
	}
	return buf[:n]
}

func goDecode(key, encoded []byte, obfuscateBytes int) []byte {
	buf := bytes.Clone(encoded)
	n := NewObfuscator(key).Decode(buf, len(buf), obfuscateBytes)
	if n < 0 {
		return nil
	}
	return buf[:n]
}

func wirePacket(rng *rand.Rand, length int) []byte {
	payload := make([]byte, length)
	rng.Read(payload)
	payload[0] = byte(1 + rng.Intn(4))
	payload[1], payload[2], payload[3] = 0, 0, 0
	return payload
}

func TestDecodeAgreesWithReference(t *testing.T) {
	rng := rand.New(rand.NewSource(4))
	for _, key := range referenceKeys {
		for _, obfuscateBytes := range []int{0, 4, 16, 64} {
			for _, length := range append([]int{4, 8, 16}, wireLengths...) {
				encoded := cref.Encode(wirePacket(rng, length), key, DefaultMaxDummy, obfuscateBytes, BufferSize)
				if !bytes.Equal(goDecode(key, encoded, obfuscateBytes), cref.Decode(encoded, key, obfuscateBytes)) {
					t.Fatalf("decode disagrees with reference: keylen=%d length=%d obf=%d", len(key), length, obfuscateBytes)
				}
			}
		}
	}
}

func TestEncodeDecodeInteropWithReference(t *testing.T) {
	rng := rand.New(rand.NewSource(5))
	for _, key := range referenceKeys {
		for _, obfuscateBytes := range []int{0, 16, 64, 148, 200, 512} {
			for _, length := range wireLengths {
				for range 16 {
					payload := wirePacket(rng, length)

					encoded := cref.Encode(payload, key, DefaultMaxDummy, obfuscateBytes, BufferSize)
					if !bytes.Equal(cref.Decode(encoded, key, obfuscateBytes), payload) {
						t.Fatalf("C cannot decode its own output: keylen=%d length=%d obf=%d", len(key), length, obfuscateBytes)
					}
					if !bytes.Equal(goDecode(key, encoded, obfuscateBytes), payload) {
						t.Fatalf("go cannot decode C output: keylen=%d length=%d obf=%d", len(key), length, obfuscateBytes)
					}

					encoded = goEncode(key, payload, DefaultMaxDummy, obfuscateBytes)
					if !bytes.Equal(cref.Decode(encoded, key, obfuscateBytes), payload) {
						t.Fatalf("C cannot decode Go output: keylen=%d length=%d obf=%d", len(key), length, obfuscateBytes)
					}
				}
			}
		}
	}
}
