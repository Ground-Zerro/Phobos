/* SPDX-License-Identifier: MIT
 *
 * Phobos
 */

package phobos

import (
	"crypto/rand"
	"encoding/binary"
)

type rng32 uint32

func newRNG32() rng32 {
	var seed [4]byte
	rand.Read(seed[:])
	state := binary.LittleEndian.Uint32(seed[:])
	if state == 0 {
		state = 1
	}
	return rng32(state)
}

func (r *rng32) next() uint32 {
	x := uint32(*r)
	x ^= x << 13
	x ^= x >> 17
	x ^= x << 5
	*r = rng32(x)
	return x
}

func (r *rng32) below(n int) int {
	if n <= 1 {
		return 0
	}
	return int(r.next() % uint32(n))
}

func (r *rng32) fill(p []byte) {
	for len(p) >= 4 {
		binary.LittleEndian.PutUint32(p, r.next())
		p = p[4:]
	}
	if len(p) > 0 {
		v := r.next()
		for i := range p {
			p[i] = byte(v >> (i * 8))
		}
	}
}
