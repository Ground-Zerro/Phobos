/* SPDX-License-Identifier: MIT
 *
 * Phobos
 */

package phobos

import "encoding/binary"

const (
	s5FramePayloadMax = 1024
	s5AccMax          = 2048
	s5EncodeReadMax   = 12288
	s5BufferSize      = 16384

	rtpTCPHeaderSize = 2 + rtpHeaderSize
	tlsRecordHeader  = 5
)

type s5Encoder struct {
	stream rtpStream
	rng    rng32
}

func (e *s5Encoder) frameSize(masking Masking, payload int) int {
	switch masking {
	case MaskingSTUN:
		return stunDataIndHeaderSize + payload + stunPadding(payload)
	case MaskingTLS:
		return tlsRecordHeader + payload
	default:
		return rtpTCPHeaderSize + payload
	}
}

func stunPadding(payload int) int {
	return (4 - payload&3) & 3
}

func (e *s5Encoder) encode(masking Masking, params MediaParams, src, out []byte) int {
	if masking == MaskingMEDIA && !e.stream.initialized {
		e.stream.init(params, &e.rng)
	}
	written := 0
	for len(src) > 0 {
		chunk := min(len(src), s5FramePayloadMax)
		if written+e.frameSize(masking, chunk) > len(out) {
			return -1
		}
		switch masking {
		case MaskingSTUN:
			written += e.encodeSTUN(src[:chunk], out[written:])
		case MaskingTLS:
			written += encodeTLS(src[:chunk], out[written:])
		default:
			written += e.encodeMedia(src[:chunk], out[written:])
		}
		src = src[chunk:]
	}
	return written
}

func (e *s5Encoder) encodeSTUN(src, out []byte) int {
	payload := len(src)
	padding := stunPadding(payload)
	messageLength := 4 + payload + padding

	binary.BigEndian.PutUint16(out, stunDataIndication)
	binary.BigEndian.PutUint16(out[2:], uint16(messageLength))
	copy(out[4:8], stunCookie[:])
	e.rng.fill(out[8:20])
	binary.BigEndian.PutUint16(out[20:], stunAttrData)
	binary.BigEndian.PutUint16(out[22:], uint16(payload))
	copy(out[24:], src)
	clear(out[24+payload : 24+payload+padding])
	return stunDataIndHeaderSize + payload + padding
}

func encodeTLS(src, out []byte) int {
	out[0] = 0x17
	out[1] = 0x03
	out[2] = 0x03
	binary.BigEndian.PutUint16(out[3:], uint16(len(src)))
	copy(out[tlsRecordHeader:], src)
	return tlsRecordHeader + len(src)
}

func (e *s5Encoder) encodeMedia(src, out []byte) int {
	binary.BigEndian.PutUint16(out, uint16(rtpHeaderSize+len(src)))
	e.stream.writeHeader(out[2:])
	copy(out[rtpTCPHeaderSize:], src)
	return rtpTCPHeaderSize + len(src)
}

type s5Decoder struct {
	acc  [s5AccMax]byte
	used int
	work [s5AccMax + s5EncodeReadMax + 16]byte
}

func (d *s5Decoder) decode(masking Masking, params MediaParams, in, out []byte) int {
	if len(in) > s5EncodeReadMax {
		return -1
	}
	total := copy(d.work[:], d.acc[:d.used])
	total += copy(d.work[total:], in)

	pos, written := 0, 0
	for {
		consumed, produced := d.decodeFrame(masking, params, d.work[pos:total], out[written:])
		if consumed < 0 {
			return -1
		}
		if consumed == 0 {
			break
		}
		pos += consumed
		written += produced
	}

	left := total - pos
	if left > s5AccMax {
		return -1
	}
	copy(d.acc[:left], d.work[pos:total])
	d.used = left
	return written
}

func (d *s5Decoder) decodeFrame(masking Masking, params MediaParams, in, out []byte) (int, int) {
	switch masking {
	case MaskingSTUN:
		return decodeSTUNFrame(in, out)
	case MaskingTLS:
		return decodeTLSFrame(in, out)
	default:
		return decodeMediaFrame(params, in, out)
	}
}

func decodeSTUNFrame(in, out []byte) (int, int) {
	if len(in) < stunDataIndHeaderSize {
		return 0, 0
	}
	if [4]byte(in[4:8]) != stunCookie {
		return -1, 0
	}
	if binary.BigEndian.Uint16(in) != stunDataIndication {
		return -1, 0
	}
	total := stunHeaderSize + int(binary.BigEndian.Uint16(in[2:]))
	if total < stunDataIndHeaderSize || total > s5AccMax {
		return -1, 0
	}
	if len(in) < total {
		return 0, 0
	}
	if binary.BigEndian.Uint16(in[20:]) != stunAttrData {
		return -1, 0
	}
	payload := int(binary.BigEndian.Uint16(in[22:]))
	if stunDataIndHeaderSize+payload > total || payload > len(out) {
		return -1, 0
	}
	copy(out, in[stunDataIndHeaderSize:stunDataIndHeaderSize+payload])
	return total, payload
}

func decodeTLSFrame(in, out []byte) (int, int) {
	if len(in) < tlsRecordHeader {
		return 0, 0
	}
	if in[0] != 0x17 || in[1] != 0x03 || in[2] != 0x03 {
		return -1, 0
	}
	payload := int(binary.BigEndian.Uint16(in[3:]))
	if payload < 1 || payload > s5AccMax {
		return -1, 0
	}
	if len(in) < tlsRecordHeader+payload {
		return 0, 0
	}
	if payload > len(out) {
		return -1, 0
	}
	copy(out, in[tlsRecordHeader:tlsRecordHeader+payload])
	return tlsRecordHeader + payload, payload
}

func decodeMediaFrame(params MediaParams, in, out []byte) (int, int) {
	if len(in) < 2 {
		return 0, 0
	}
	length := int(binary.BigEndian.Uint16(in))
	if length < rtpHeaderSize || length > s5AccMax {
		return -1, 0
	}
	if len(in) < 2+length {
		return 0, 0
	}
	if in[2]&0xC0 != 0x80 {
		return -1, 0
	}
	if params.PayloadType != 0 && in[3]&0x7F != params.PayloadType {
		return -1, 0
	}
	payload := length - rtpHeaderSize
	if payload > len(out) {
		return -1, 0
	}
	copy(out, in[rtpTCPHeaderSize:2+length])
	return 2 + length, payload
}
