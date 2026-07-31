/* SPDX-License-Identifier: MIT
 *
 * Phobos
 */

package phobos

import (
	"errors"
	"net"
	"sync"

	"golang.zx2c4.com/wireguard/windows/phobos/cobf"
)

var errFrameCorrupt = errors.New("phobos: corrupt obfuscated frame")

type obfConn struct {
	net.Conn
	masking Masking
	media   MediaParams

	writeMu      sync.Mutex
	writeCipher  *cobf.StreamCipher
	encoder      s5Encoder
	writeScratch []byte
	writeFrames  []byte

	readCipher *cobf.StreamCipher
	decoder    s5Decoder
	readRaw    []byte
	readPlain  []byte
	pending    []byte
	readErr    error
}

func newObfConn(conn net.Conn, key []byte, masking Masking, media MediaParams) *obfConn {
	c := &obfConn{
		Conn:        conn,
		masking:     masking,
		media:       media,
		writeCipher: cobf.NewStreamCipher(key),
		readCipher:  cobf.NewStreamCipher(key),
		readRaw:     make([]byte, s5EncodeReadMax),
	}
	if masking != MaskingNone {
		c.writeScratch = make([]byte, s5EncodeReadMax)
		c.writeFrames = make([]byte, s5BufferSize)
		c.readPlain = make([]byte, s5BufferSize)
	} else {
		c.writeScratch = make([]byte, s5EncodeReadMax)
	}
	return c
}

func (c *obfConn) Write(p []byte) (int, error) {
	c.writeMu.Lock()
	defer c.writeMu.Unlock()

	written := 0
	for len(p) > 0 {
		chunk := min(len(p), s5EncodeReadMax)
		plain := c.writeScratch[:chunk]
		copy(plain, p[:chunk])
		c.writeCipher.Apply(plain)

		wire := plain
		if c.masking != MaskingNone {
			n := c.encoder.encode(c.masking, c.media, plain, c.writeFrames)
			if n < 0 {
				return written, errFrameCorrupt
			}
			wire = c.writeFrames[:n]
		}
		if _, err := c.Conn.Write(wire); err != nil {
			return written, err
		}
		written += chunk
		p = p[chunk:]
	}
	return written, nil
}

func (c *obfConn) Read(p []byte) (int, error) {
	for len(c.pending) == 0 {
		if c.readErr != nil {
			return 0, c.readErr
		}
		n, err := c.Conn.Read(c.readRaw)
		if n > 0 {
			decoded, decodeErr := c.decodeChunk(c.readRaw[:n])
			if decodeErr != nil {
				return 0, decodeErr
			}
			c.pending = decoded
		}
		if err != nil {
			c.readErr = err
			if len(c.pending) == 0 {
				return 0, err
			}
		}
	}
	n := copy(p, c.pending)
	c.pending = c.pending[n:]
	return n, nil
}

func (c *obfConn) decodeChunk(raw []byte) ([]byte, error) {
	if c.masking == MaskingNone {
		c.readCipher.Apply(raw)
		return raw, nil
	}
	n := c.decoder.decode(c.masking, c.media, raw, c.readPlain)
	if n < 0 {
		return nil, errFrameCorrupt
	}
	plain := c.readPlain[:n]
	c.readCipher.Apply(plain)
	return plain, nil
}
