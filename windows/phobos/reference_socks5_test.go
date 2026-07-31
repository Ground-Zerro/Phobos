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

	"golang.zx2c4.com/wireguard/windows/phobos/cref"
)

var socks5Maskings = map[Masking]int{MaskingSTUN: 1, MaskingMEDIA: 2, MaskingTLS: 3}

var socks5MediaParams = MediaParams{PayloadType: 102, SSRC: 0xC0FFEE, TimestampStep: 3000}

func TestSocks5FramingGoEncodeCDecode(t *testing.T) {
	rng := rand.New(rand.NewSource(21))
	for masking, id := range socks5Maskings {
		for _, length := range []int{1, 64, 1023, 1024, 1025, 4096, s5EncodeReadMax} {
			payload := make([]byte, length)
			rng.Read(payload)

			var encoder s5Encoder
			out := make([]byte, s5BufferSize+length)
			n := encoder.encode(masking, socks5MediaParams, payload, out)
			if n < 0 {
				t.Fatalf("%v: go encode failed at length %d", masking, length)
			}

			cref.Socks5Reset()
			var decoded []byte
			for offset := 0; offset < n; offset += s5EncodeReadMax {
				chunk := out[offset:min(offset+s5EncodeReadMax, n)]
				decoded = append(decoded, cref.Socks5Decode(id, socks5MediaParams.PayloadType, socks5MediaParams.SSRC, chunk, s5BufferSize)...)
			}
			if !bytes.Equal(decoded, payload) {
				t.Fatalf("%v: C cannot decode Go frames at length %d", masking, length)
			}
		}
	}
}

func TestSocks5FramingCEncodeGoDecode(t *testing.T) {
	rng := rand.New(rand.NewSource(22))
	for masking, id := range socks5Maskings {
		for _, length := range []int{1, 64, 1023, 1024, 1025, 4096} {
			payload := make([]byte, length)
			rng.Read(payload)

			cref.Socks5Reset()
			frames := cref.Socks5Encode(id, socks5MediaParams.PayloadType, socks5MediaParams.SSRC,
				socks5MediaParams.TimestampStep, payload, s5BufferSize+length)
			if frames == nil {
				t.Fatalf("%v: C encode failed at length %d", masking, length)
			}

			var decoder s5Decoder
			out := make([]byte, s5BufferSize+length)
			n := decoder.decode(masking, socks5MediaParams, frames, out)
			if n < 0 || !bytes.Equal(out[:n], payload) {
				t.Fatalf("%v: Go cannot decode C frames at length %d", masking, length)
			}
		}
	}
}

func TestSocks5FramingDecodesAcrossChunks(t *testing.T) {
	rng := rand.New(rand.NewSource(23))
	for masking, id := range socks5Maskings {
		payload := make([]byte, 4096)
		rng.Read(payload)

		cref.Socks5Reset()
		frames := cref.Socks5Encode(id, socks5MediaParams.PayloadType, socks5MediaParams.SSRC,
			socks5MediaParams.TimestampStep, payload, s5BufferSize*2)

		var decoder s5Decoder
		out := make([]byte, s5BufferSize)
		var assembled []byte
		for offset := 0; offset < len(frames); offset += 7 {
			chunk := frames[offset:min(offset+7, len(frames))]
			n := decoder.decode(masking, socks5MediaParams, chunk, out)
			if n < 0 {
				t.Fatalf("%v: chunked decode failed", masking)
			}
			assembled = append(assembled, out[:n]...)
		}
		if !bytes.Equal(assembled, payload) {
			t.Fatalf("%v: chunked decode produced %d bytes, want %d", masking, len(assembled), len(payload))
		}
	}
}

func TestSocks5FramingRejectsGarbage(t *testing.T) {
	for masking := range socks5Maskings {
		var decoder s5Decoder
		out := make([]byte, s5BufferSize)
		garbage := bytes.Repeat([]byte{0xA5}, 64)
		if n := decoder.decode(masking, socks5MediaParams, garbage, out); n >= 0 {
			t.Errorf("%v: garbage should not decode", masking)
		}
	}
}
