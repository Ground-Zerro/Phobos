/* SPDX-License-Identifier: MIT
 *
 * Phobos
 */

package phobos

import (
	"encoding/binary"
	"hash/crc32"
	"net/netip"
)

const (
	stunBindingRequest  = 0x0001
	stunBindingResponse = 0x0101
	stunDataIndication  = 0x0115

	stunAttrXORMapped   = 0x0020
	stunAttrFingerprint = 0x8028
	stunAttrData        = 0x0013

	stunHeaderSize        = 20
	stunDataIndHeaderSize = 24
	stunBindingReqSize    = stunHeaderSize + 8
	stunFingerprintXOR    = 0x5354554E
)

var stunCookie = [4]byte{0x21, 0x12, 0xA4, 0x42}

func stunHasMagic(buf []byte) bool {
	return len(buf) >= 8 && [4]byte(buf[4:8]) == stunCookie
}

func stunMessageType(buf []byte) uint16 {
	return binary.BigEndian.Uint16(buf)
}

func stunWriteHeader(buf []byte, messageType, messageLength uint16, txid []byte) {
	binary.BigEndian.PutUint16(buf, messageType)
	binary.BigEndian.PutUint16(buf[2:], messageLength)
	copy(buf[4:8], stunCookie[:])
	copy(buf[8:20], txid)
}

func stunWriteFingerprint(packet []byte, offset int) int {
	binary.BigEndian.PutUint16(packet[offset:], stunAttrFingerprint)
	binary.BigEndian.PutUint16(packet[offset+2:], 4)
	binary.BigEndian.PutUint32(packet[offset+4:], crc32.ChecksumIEEE(packet[:offset])^stunFingerprintXOR)
	return 8
}

func stunWriteXORMappedAddress(buf []byte, addr netip.AddrPort) int {
	binary.BigEndian.PutUint16(buf, stunAttrXORMapped)
	binary.BigEndian.PutUint16(buf[2:], 8)
	buf[4] = 0
	buf[5] = 0x01
	binary.BigEndian.PutUint16(buf[6:], addr.Port())
	buf[6] ^= stunCookie[0]
	buf[7] ^= stunCookie[1]
	ip := addr.Addr().As4()
	for i := range 4 {
		buf[8+i] = ip[i] ^ stunCookie[i]
	}
	return 12
}

func stunBuildBindingRequest(buf []byte, rng *rng32) int {
	var txid [12]byte
	rng.fill(txid[:])
	stunWriteHeader(buf, stunBindingRequest, 0, txid[:])
	length := stunWriteFingerprint(buf, stunHeaderSize)
	binary.BigEndian.PutUint16(buf[2:], uint16(length))
	return stunHeaderSize + length
}

func stunBuildBindingSuccess(buf, txid []byte, addr netip.AddrPort) int {
	if !addr.Addr().Is4() && !addr.Addr().Is4In6() {
		return -1
	}
	stunWriteHeader(buf, stunBindingResponse, 0, txid)
	length := stunWriteXORMappedAddress(buf[stunHeaderSize:], addr)
	length += stunWriteFingerprint(buf, stunHeaderSize+length)
	binary.BigEndian.PutUint16(buf[2:], uint16(length))
	return stunHeaderSize + length
}

func stunWrapDataIndication(buf []byte, length int, rng *rng32) int {
	if length+stunDataIndHeaderSize > len(buf) {
		return -1
	}
	copy(buf[stunDataIndHeaderSize:stunDataIndHeaderSize+length], buf[:length])
	var txid [12]byte
	rng.fill(txid[:])
	stunWriteHeader(buf, stunDataIndication, 0, txid[:])
	binary.BigEndian.PutUint16(buf[20:], stunAttrData)
	binary.BigEndian.PutUint16(buf[22:], uint16(length))
	return stunDataIndHeaderSize + length
}

func stunUnwrapDataIndication(buf []byte, length int) int {
	if length < stunDataIndHeaderSize {
		return -1
	}
	if stunMessageType(buf) != stunDataIndication {
		return -1
	}
	if int(binary.BigEndian.Uint16(buf[2:]))+stunHeaderSize > length {
		return -1
	}
	if binary.BigEndian.Uint16(buf[20:]) != stunAttrData {
		return -1
	}
	dataLength := int(binary.BigEndian.Uint16(buf[22:]))
	if dataLength+stunDataIndHeaderSize > length {
		return -1
	}
	copy(buf[:dataLength], buf[stunDataIndHeaderSize:stunDataIndHeaderSize+dataLength])
	return dataLength
}

func stunHandleIncoming(buf []byte, length int, src netip.AddrPort, sendBack SendFunc) int {
	switch stunMessageType(buf) {
	case stunBindingRequest:
		if length < stunHeaderSize {
			return -1
		}
		var txid [12]byte
		copy(txid[:], buf[8:20])
		responseLength := stunBuildBindingSuccess(buf, txid[:], src)
		if responseLength > 0 {
			sendBack(buf[:responseLength])
		}
		return 0
	case stunBindingResponse:
		return 0
	case stunDataIndication:
		return stunUnwrapDataIndication(buf, length)
	default:
		return 0
	}
}
