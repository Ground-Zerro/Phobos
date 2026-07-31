/* SPDX-License-Identifier: MIT
 *
 * Phobos
 */

// Package cobf binds the shared wg-obfuscator C sources in
// src/phobos-obfuscator. It is the only implementation of the Phobos wire
// protocol in this tree; there is deliberately no Go port to drift from.
package cobf

/*
#cgo CFLAGS: -I${SRCDIR}/../../../src/phobos-obfuscator
#cgo windows LDFLAGS: -lws2_32
#include "bridge.h"
*/
import "C"

import "unsafe"

func keyPtr(key []byte) *C.char {
	return (*C.char)(unsafe.Pointer(unsafe.SliceData(key)))
}

// Encode obfuscates buffer[:length] in place and returns the new length,
// which may exceed length when the C side appends dummy padding.
func Encode(buffer []byte, length int, key []byte, maxDummyData, obfuscateBytes int) int {
	return int(C.cobf_encode((*C.uint8_t)(unsafe.SliceData(buffer)), C.int(length),
		keyPtr(key), C.int(len(key)), C.int(maxDummyData), C.int(obfuscateBytes)))
}

// Decode deobfuscates buffer[:length] in place and returns the payload length.
// version reports the protocol version detected in the packet header.
func Decode(buffer []byte, length int, key []byte, obfuscateBytes int) (n int, version uint8) {
	var v C.uint8_t
	n = int(C.cobf_decode((*C.uint8_t)(unsafe.SliceData(buffer)), C.int(length),
		keyPtr(key), C.int(len(key)), C.int(obfuscateBytes), &v))
	return n, uint8(v)
}

// XOR applies the keystream to buffer[:length] in place. Encode and Decode
// already do this; it is exported for the golden-vector regression tests.
func XOR(buffer []byte, length int, key []byte) {
	C.cobf_xor((*C.uint8_t)(unsafe.SliceData(buffer)), C.int(length), keyPtr(key), C.int(len(key)))
}

// StreamCipher is the continuous keystream used for SOCKS5 TCP streams. Its
// state lives in Go memory: the C struct holds no pointers, so it needs no
// manual lifecycle.
type StreamCipher struct {
	state []uint64
}

func NewStreamCipher(key []byte) *StreamCipher {
	words := (int(C.cobf_stream_size()) + 7) / 8
	s := &StreamCipher{state: make([]uint64, words)}
	C.cobf_stream_init(unsafe.Pointer(unsafe.SliceData(s.state)), keyPtr(key), C.int(len(key)))
	return s
}

func (s *StreamCipher) Apply(buffer []byte) {
	if len(buffer) == 0 {
		return
	}
	C.cobf_stream_apply(unsafe.Pointer(unsafe.SliceData(s.state)),
		(*C.uint8_t)(unsafe.SliceData(buffer)), C.int(len(buffer)))
}
