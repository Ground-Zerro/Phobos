/* SPDX-License-Identifier: MIT
 *
 * Phobos
 */

package phobos

import (
	"net/netip"
	"time"
)

type maskerSTUN struct {
	rng rng32
}

func (m *maskerSTUN) TimerInterval() time.Duration {
	return 10 * time.Second
}

func (m *maskerSTUN) OnHandshakeRequest(sendForward SendFunc) {
	sendBindingRequest(sendForward, &m.rng)
}

func (m *maskerSTUN) OnDataUnwrap(buf []byte, length int, src netip.AddrPort, sendBack SendFunc) int {
	if !stunHasMagic(buf[:length]) {
		return -1
	}
	return stunHandleIncoming(buf, length, src, sendBack)
}

func (m *maskerSTUN) OnDataWrap(buf []byte, length int) int {
	return stunWrapDataIndication(buf, length, &m.rng)
}

func (m *maskerSTUN) OnTimer(sendToServer SendFunc) {
	sendBindingRequest(sendToServer, &m.rng)
}
