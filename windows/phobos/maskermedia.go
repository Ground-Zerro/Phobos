/* SPDX-License-Identifier: MIT
 *
 * Phobos
 */

package phobos

import (
	"encoding/binary"
	"net/netip"
	"time"
)

const rtpHeaderSize = 12

type mediaPreset struct {
	payloadType   uint8
	timestampStep uint16
}

var mediaPresets = [...]mediaPreset{
	{96, 3000}, {96, 3600}, {96, 3750}, {96, 1500}, {96, 6000},
	{97, 3000}, {97, 3600}, {97, 4500}, {97, 9000}, {97, 18000},
	{98, 3000}, {98, 3600}, {98, 3750}, {98, 1500}, {98, 6000},
	{99, 3000}, {99, 3600}, {100, 3000}, {100, 1500}, {100, 3750},
	{102, 3000}, {102, 1500}, {102, 3600}, {104, 3000}, {104, 1500},
	{106, 3000}, {106, 3750}, {108, 3000}, {108, 1500}, {110, 3000},
	{112, 3000}, {112, 3600}, {114, 3000}, {114, 1500}, {116, 3000},
	{118, 3000}, {119, 3000}, {120, 3000}, {122, 3000}, {123, 3000},
	{124, 3000}, {125, 3000}, {125, 1500}, {126, 3000}, {127, 3000},
	{127, 1500}, {127, 3750}, {96, 1502}, {96, 3003}, {97, 3753},
}

type rtpStream struct {
	sequence      uint16
	timestamp     uint32
	ssrc          uint32
	timestampStep uint16
	payloadType   uint8
	initialized   bool
}

func (s *rtpStream) init(params MediaParams, rng *rng32) {
	s.sequence = uint16(rng.next())
	s.timestamp = rng.next()
	if params.SSRC != 0 {
		s.ssrc = params.SSRC
	} else if s.ssrc = rng.next(); s.ssrc == 0 {
		s.ssrc = 1
	}
	preset := mediaPresets[rng.below(len(mediaPresets))]
	s.payloadType = preset.payloadType
	if params.PayloadType != 0 {
		s.payloadType = params.PayloadType
	}
	s.timestampStep = preset.timestampStep
	if params.TimestampStep != 0 {
		s.timestampStep = params.TimestampStep
	}
	s.initialized = true
}

func (s *rtpStream) writeHeader(buf []byte) {
	buf[0] = 0x80
	buf[1] = 0x80 | (s.payloadType & 0x7F)
	binary.BigEndian.PutUint16(buf[2:], s.sequence)
	binary.BigEndian.PutUint32(buf[4:], s.timestamp)
	binary.BigEndian.PutUint32(buf[8:], s.ssrc)
	s.sequence++
	s.timestamp += uint32(s.timestampStep)
}

type maskerMedia struct {
	rng    rng32
	params MediaParams
	stream rtpStream
}

func (m *maskerMedia) TimerInterval() time.Duration {
	return 5 * time.Second
}

func (m *maskerMedia) OnHandshakeRequest(sendForward SendFunc) {
	sendBindingRequest(sendForward, &m.rng)
}

func (m *maskerMedia) OnDataUnwrap(buf []byte, length int, src netip.AddrPort, sendBack SendFunc) int {
	if stunHasMagic(buf[:length]) {
		return stunHandleIncoming(buf, length, src, sendBack)
	}
	if length < rtpHeaderSize+4 {
		return -1
	}
	if buf[0]&0xC0 != 0x80 {
		return -1
	}
	if m.params.PayloadType != 0 && buf[1]&0x7F != m.params.PayloadType {
		return -1
	}
	if m.params.SSRC != 0 && binary.BigEndian.Uint32(buf[8:]) != m.params.SSRC {
		return -1
	}
	payloadLength := length - rtpHeaderSize
	copy(buf[:payloadLength], buf[rtpHeaderSize:length])
	return payloadLength
}

func (m *maskerMedia) OnDataWrap(buf []byte, length int) int {
	if length+rtpHeaderSize > len(buf) {
		return -1
	}
	if !m.stream.initialized {
		m.stream.init(m.params, &m.rng)
	}
	copy(buf[rtpHeaderSize:rtpHeaderSize+length], buf[:length])
	m.stream.writeHeader(buf)
	return length + rtpHeaderSize
}

func (m *maskerMedia) OnTimer(sendToServer SendFunc) {
	sendBindingRequest(sendToServer, &m.rng)
}
