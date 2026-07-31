//go:build phoboscref

/* SPDX-License-Identifier: MIT
 *
 * Phobos
 */

package cref

/*
#cgo CFLAGS: -I${SRCDIR}/../../../src/phobos-obfuscator -DMAX_DUMMY_LENGTH_TOTAL=1024 -DMAX_DUMMY_LENGTH_HANDSHAKE=512
#include <stdlib.h>
#include <string.h>
#include "obfuscation.h"

static void ref_xor(unsigned char *buf, int len, char *key, int keylen) {
    xor_data(buf, len, key, keylen);
}

static void ref_stream(unsigned char *buf, int len, int split, char *key, int keylen) {
    stream_cipher_t s;
    stream_cipher_init(&s, key, keylen);
    stream_cipher_apply(&s, buf, split);
    stream_cipher_apply(&s, buf + split, len - split);
}

static int ref_encode(unsigned char *buf, int len, char *key, int keylen, int maxdummy, int obfbytes) {
    return encode(buf, len, key, keylen, OBFUSCATION_VERSION, maxdummy, obfbytes);
}

static int ref_decode(unsigned char *buf, int len, char *key, int keylen, int obfbytes) {
    unsigned char version = 0;
    return decode(buf, len, key, keylen, &version, obfbytes);
}
*/
import "C"

import (
	"bytes"
	"unsafe"
)

const Available = true

func keyArgs(key []byte) (*C.char, C.int) {
	return (*C.char)(unsafe.Pointer(unsafe.SliceData(key))), C.int(len(key))
}

func XOR(data, key []byte) []byte {
	out := bytes.Clone(data)
	k, kl := keyArgs(key)
	C.ref_xor((*C.uchar)(unsafe.SliceData(out)), C.int(len(out)), k, kl)
	return out
}

func Stream(data, key []byte, split int) []byte {
	out := bytes.Clone(data)
	k, kl := keyArgs(key)
	C.ref_stream((*C.uchar)(unsafe.SliceData(out)), C.int(len(out)), C.int(split), k, kl)
	return out
}

func Encode(data, key []byte, maxDummy, obfuscateBytes, capacity int) []byte {
	buf := make([]byte, capacity)
	copy(buf, data)
	k, kl := keyArgs(key)
	n := C.ref_encode((*C.uchar)(unsafe.SliceData(buf)), C.int(len(data)), k, kl, C.int(maxDummy), C.int(obfuscateBytes))
	if n < 0 {
		return nil
	}
	return buf[:int(n)]
}

func Decode(data, key []byte, obfuscateBytes int) []byte {
	buf := bytes.Clone(data)
	k, kl := keyArgs(key)
	n := C.ref_decode((*C.uchar)(unsafe.SliceData(buf)), C.int(len(buf)), k, kl, C.int(obfuscateBytes))
	if n < 0 {
		return nil
	}
	return buf[:int(n)]
}
