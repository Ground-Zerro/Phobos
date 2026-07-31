/* SPDX-License-Identifier: MIT
 *
 * Phobos
 */

package phobos

import (
	"encoding/binary"

	"golang.zx2c4.com/wireguard/windows/phobos/cobf"
)

const (
	TypeHandshake         = 1
	TypeHandshakeResponse = 2
	TypeCookie            = 3
	TypeData              = 4

	DefaultMaxDummy            = 4
	MediaObfuscateBytesDefault = 16

	BufferSize = 65535
)

func PacketType(buf []byte) uint32 {
	return binary.LittleEndian.Uint32(buf[:4])
}

func IsKnownPacketType(t uint32) bool {
	return t >= TypeHandshake && t <= TypeData
}

// Obfuscator applies the Phobos wire protocol to WireGuard packets. The
// protocol itself lives in the shared C sources under src/phobos-obfuscator,
// reached through package cobf -- this type is a binding, not a second
// implementation.
type Obfuscator struct {
	key []byte
}

func NewObfuscator(key []byte) *Obfuscator {
	return &Obfuscator{key: key}
}

func (o *Obfuscator) Encode(buf []byte, length, maxDummyData, obfuscateBytes int) int {
	if length < 4 {
		return -1
	}
	return cobf.Encode(buf, length, o.key, maxDummyData, obfuscateBytes)
}

func (o *Obfuscator) Decode(buf []byte, length, obfuscateBytes int) int {
	if length < 4 {
		return -1
	}
	n, _ := cobf.Decode(buf, length, o.key, obfuscateBytes)
	return n
}

func (o *Obfuscator) xorData(buf []byte) {
	cobf.XOR(buf, len(buf), o.key)
}
