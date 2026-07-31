/* SPDX-License-Identifier: MIT
 *
 * Phobos
 */

package cobf

import (
	"bytes"
	"math/rand"
	"testing"
)

var testKeys = [][]byte{
	[]byte("k"),
	[]byte("phobos"),
	[]byte("Ic0OGtSf1BdMmMDzs7GmYRuPS/HGmNXsSU9EOWEeuQI="),
	bytes.Repeat([]byte{0xFE}, 200),
}

var wireLengths = []int{32, 64, 92, 148, 176, 1024, 1420, 2000, 9000}

func wirePacket(rng *rand.Rand, length int) []byte {
	payload := make([]byte, length)
	rng.Read(payload)
	payload[0] = byte(1 + rng.Intn(4))
	payload[1], payload[2], payload[3] = 0, 0, 0
	return payload
}

func roundTrip(t *testing.T, key, payload []byte, obfuscateBytes int) {
	t.Helper()
	buf := make([]byte, 65535)
	copy(buf, payload)
	n := Encode(buf, len(payload), key, 4, obfuscateBytes)
	if n < 4 {
		t.Fatalf("encode returned %d: keylen=%d length=%d obf=%d",
			n, len(key), len(payload), obfuscateBytes)
	}
	got, _ := Decode(buf, n, key, obfuscateBytes)
	if got != len(payload) || !bytes.Equal(buf[:got], payload) {
		t.Fatalf("round trip corrupted the payload: keylen=%d length=%d obf=%d encoded=%d decoded=%d",
			len(key), len(payload), obfuscateBytes, n, got)
	}
}

// Covers the window where the encoder used to pick a different obfuscation
// span than the decoder: obfuscate-bytes at or above the payload length.
func TestEncodeDecodeRoundTrip(t *testing.T) {
	rng := rand.New(rand.NewSource(1))
	for _, key := range testKeys {
		for _, obfuscateBytes := range []int{0, 16, 64, 148, 200, 512} {
			for _, length := range wireLengths {
				for range 16 {
					roundTrip(t, key, wirePacket(rng, length), obfuscateBytes)
				}
			}
		}
	}
}

func TestStreamCipherRoundTrip(t *testing.T) {
	rng := rand.New(rand.NewSource(2))
	for _, key := range testKeys {
		for _, length := range []int{1, 64, 65, 1000, 20000} {
			payload := make([]byte, length)
			rng.Read(payload)

			buf := bytes.Clone(payload)
			split := length / 3
			enc := NewStreamCipher(key)
			enc.Apply(buf[:split])
			enc.Apply(buf[split:])
			if length > 4 && bytes.Equal(buf, payload) {
				t.Fatalf("stream cipher left the payload untouched at length %d", length)
			}

			dec := NewStreamCipher(key)
			dec.Apply(buf[:split])
			dec.Apply(buf[split:])
			if !bytes.Equal(buf, payload) {
				t.Fatalf("stream cipher round trip failed: keylen=%d length=%d", len(key), length)
			}
		}
	}
}

func keystream(key []byte, length int) []byte {
	buf := make([]byte, length)
	XOR(buf, length, key)
	return buf
}

// The C keystream cache is thread-local and was once keyed by packet length
// and key length alone, so a second key of the same length silently inherited
// the first key's keystream -- and the poison outlived the goroutine, because
// Go reuses OS threads. Two keys of equal length must produce different
// keystreams for the same packet length.
func TestKeysOfEqualLengthKeepSeparateKeystreams(t *testing.T) {
	keyA := []byte("aaaaaa")
	keyB := []byte("bbbbbb")
	if len(keyA) != len(keyB) {
		t.Fatal("the test needs two keys of equal length")
	}

	for _, length := range []int{32, 148, 1420, 1500} {
		a := keystream(keyA, length)
		b := keystream(keyB, length)
		if bytes.Equal(a, b) {
			t.Fatalf("keys of equal length share a keystream at length %d: %x", length, a[:8])
		}
	}

	rng := rand.New(rand.NewSource(3))
	for range 200 {
		for _, length := range []int{32, 148, 1420} {
			roundTrip(t, keyA, wirePacket(rng, length), 0)
			roundTrip(t, keyB, wirePacket(rng, length), 0)
		}
	}
}
