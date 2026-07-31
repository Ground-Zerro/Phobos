/* SPDX-License-Identifier: MIT
 *
 * Phobos
 */

package cobf

/*
#cgo CFLAGS: -I${SRCDIR}/../../../src/phobos-obfuscator
#include "bridge.h"
*/
import "C"

import "unsafe"

// MaxTargetSize is the largest SOCKS5 address block: ATYP, domain length,
// a 255-byte domain and the port.
const MaxTargetSize = 1 + 1 + 255 + 2

// ParseTarget decodes the ATYP/address/port block at the start of buf.
// consumed > 0 is the number of bytes read; consumed == 0 means buf is still
// incomplete; consumed < 0 means the address type is not supported. addr
// aliases buf rather than copying: the block always ends with the two port
// bytes, so its position follows from consumed and the address length.
func ParseTarget(buf []byte) (atyp byte, addr []byte, port uint16, consumed int) {
	if len(buf) == 0 {
		return 0, nil, 0, 0
	}
	var (
		cAtyp    C.uint8_t
		cAddrLen C.int
		cPort    C.uint16_t
	)
	consumed = int(C.cobf_parse_target((*C.uint8_t)(unsafe.SliceData(buf)), C.int(len(buf)),
		&cAtyp, &cAddrLen, &cPort))
	if consumed <= 0 {
		return 0, nil, 0, consumed
	}
	end := consumed - 2
	return byte(cAtyp), buf[end-int(cAddrLen) : end], uint16(cPort), consumed
}

// BuildTarget writes the ATYP/address/port block into out and returns its
// length, or -1 when out is too small. It never allocates.
func BuildTarget(out []byte, atyp byte, addr []byte, port uint16) int {
	if len(out) == 0 {
		return -1
	}
	var addrPtr *C.uint8_t
	if len(addr) > 0 {
		addrPtr = (*C.uint8_t)(unsafe.SliceData(addr))
	}
	return int(C.cobf_build_target((*C.uint8_t)(unsafe.SliceData(out)), C.int(len(out)),
		C.uint8_t(atyp), addrPtr, C.int(len(addr)), C.uint16_t(port)))
}
