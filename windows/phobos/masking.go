/* SPDX-License-Identifier: MIT
 *
 * Phobos
 */

package phobos

import (
	"net/netip"
	"strings"
	"time"
)

type Masking int

const (
	MaskingNone Masking = iota
	MaskingSTUN
	MaskingMEDIA
	MaskingTLS
)

var maskingNames = map[Masking]string{
	MaskingNone:  "none",
	MaskingSTUN:  "STUN",
	MaskingMEDIA: "MEDIA",
	MaskingTLS:   "TLS",
}

func (m Masking) String() string {
	if name, ok := maskingNames[m]; ok {
		return name
	}
	return maskingNames[MaskingNone]
}

func ParseMasking(value string) (Masking, bool) {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case "", "none", "off":
		return MaskingNone, true
	case "stun":
		return MaskingSTUN, true
	case "media":
		return MaskingMEDIA, true
	case "tls":
		return MaskingTLS, true
	}
	return MaskingNone, false
}

type MediaParams struct {
	PayloadType   uint8
	SSRC          uint32
	TimestampStep uint16
}

type SendFunc func(p []byte) (int, error)

type Masker interface {
	TimerInterval() time.Duration
	OnHandshakeRequest(sendForward SendFunc)
	OnDataUnwrap(buf []byte, length int, src netip.AddrPort, sendBack SendFunc) int
	OnDataWrap(buf []byte, length int) int
	OnTimer(sendToServer SendFunc)
}

func NewMasker(masking Masking, media MediaParams) Masker {
	switch masking {
	case MaskingSTUN:
		return &maskerSTUN{rng: newRNG32()}
	case MaskingMEDIA:
		return &maskerMedia{rng: newRNG32(), params: media}
	}
	return nil
}

func sendBindingRequest(send SendFunc, rng *rng32) {
	var buf [stunBindingReqSize]byte
	send(buf[:stunBuildBindingRequest(buf[:], rng)])
}
