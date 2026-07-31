//go:build phoboscref

/* SPDX-License-Identifier: MIT
 *
 * Phobos
 */

package cref

/*
#include <stdint.h>
#include <string.h>
#include <arpa/inet.h>
#include "masking_stun.c"
#include "masking_media.c"
#include "socks5_mask.c"

int verbose = 0;
char section_name[256] = "cref";

static s5_enc_t ref_enc;
static s5_dec_t ref_dec;

static void ref_s5_reset(void) {
    memset(&ref_enc, 0, sizeof(ref_enc));
    memset(&ref_dec, 0, sizeof(ref_dec));
}

static void ref_s5_config(obfuscator_config_t *config, uint8_t pt, uint32_t ssrc, uint16_t ts_step) {
    memset(config, 0, sizeof(*config));
    config->media_payload_type = pt;
    config->media_ssrc = ssrc;
    config->media_ts_step = ts_step;
}

static int ref_s5_encode(int mask, uint8_t pt, uint32_t ssrc, uint16_t ts_step,
                         const uint8_t *src, int src_len, uint8_t *out, int out_cap) {
    obfuscator_config_t config;
    ref_s5_config(&config, pt, ssrc, ts_step);
    return s5_mask_encode(mask, &ref_enc, &config, src, src_len, out, out_cap);
}

static int ref_s5_decode(int mask, uint8_t pt, uint32_t ssrc,
                         const uint8_t *in, int in_len, uint8_t *out, int out_cap) {
    obfuscator_config_t config;
    ref_s5_config(&config, pt, ssrc, 0);
    return s5_mask_decode(mask, &ref_dec, &config, in, in_len, out, out_cap);
}

static int ref_stun_binding_success(uint8_t *out, const uint8_t *txid, const uint8_t *ip, uint16_t port) {
    struct sockaddr_in src;
    memset(&src, 0, sizeof(src));
    src.sin_family = AF_INET;
    memcpy(&src.sin_addr.s_addr, ip, 4);
    src.sin_port = htons(port);
    return stun_build_binding_success(out, txid, &src);
}

static uint32_t ref_crc32(const uint8_t *data, int length) {
    return crc32(data, (size_t)length);
}

static int ref_stun_binding_request(uint8_t *out) {
    return stun_build_binding_request(out);
}

static uint16_t ref_media_pick_preset(uint8_t *pt_out) {
    return media_pick_preset(pt_out);
}

static int ref_stun_wrap(uint8_t *buf, int payload_length) {
    memmove(buf + STUN_DATA_IND_HEADER, buf, payload_length);
    stun_build_frame(buf, payload_length, NULL, NULL, DIR_CLIENT_TO_SERVER);
    return STUN_DATA_IND_HEADER + payload_length;
}

static int ref_stun_unwrap(uint8_t *buf, int length) {
    int n = stun_unwrap(buf, length);
    if (n < 0) return n;
    memmove(buf, buf + STUN_DATA_IND_HEADER, n);
    return n;
}

static int ref_media_wrap(uint8_t *buf, int payload_length, uint8_t pt, uint32_t ssrc, uint16_t ts_step) {
    obfuscator_config_t config;
    client_entry_t client;
    memset(&config, 0, sizeof(config));
    memset(&client, 0, sizeof(client));
    config.media_payload_type = pt;
    config.media_ssrc = ssrc;
    config.media_ts_step = ts_step;
    memmove(buf + RTP_HEADER_SIZE, buf, payload_length);
    media_build_frame(buf, payload_length, &config, &client, DIR_CLIENT_TO_SERVER);
    return RTP_HEADER_SIZE + payload_length;
}

static int ref_media_unwrap(uint8_t *buf, int length, uint8_t pt, uint32_t ssrc) {
    obfuscator_config_t config;
    client_entry_t client;
    memset(&config, 0, sizeof(config));
    memset(&client, 0, sizeof(client));
    config.media_payload_type = pt;
    config.media_ssrc = ssrc;
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    int offset = 0;
    int n = media_on_data_unwrap(buf, length, &config, &client, DIR_SERVER_TO_CLIENT,
                                 &addr, &addr, NULL, NULL, &offset);
    if (n < 0) return n;
    memmove(buf, buf + offset, n);
    return n;
}

*/
import "C"

import (
	"bytes"

	"net/netip"
	"unsafe"
)

func StunBindingSuccess(txid []byte, addr netip.AddrPort) []byte {
	out := make([]byte, 128)
	ip := addr.Addr().As4()
	n := C.ref_stun_binding_success(
		(*C.uint8_t)(unsafe.SliceData(out)),
		(*C.uint8_t)(unsafe.SliceData(txid)),
		(*C.uint8_t)(&ip[0]),
		C.uint16_t(addr.Port()),
	)
	if n < 0 {
		return nil
	}
	return out[:int(n)]
}

func Socks5Reset() {
	C.ref_s5_reset()
}

func Socks5Encode(mask int, payloadType uint8, ssrc uint32, timestampStep uint16, src []byte, capacity int) []byte {
	out := make([]byte, capacity)
	n := C.ref_s5_encode(C.int(mask), C.uint8_t(payloadType), C.uint32_t(ssrc), C.uint16_t(timestampStep),
		(*C.uint8_t)(unsafe.SliceData(src)), C.int(len(src)),
		(*C.uint8_t)(unsafe.SliceData(out)), C.int(capacity))
	if n < 0 {
		return nil
	}
	return out[:int(n)]
}

func Socks5Decode(mask int, payloadType uint8, ssrc uint32, in []byte, capacity int) []byte {
	out := make([]byte, capacity)
	n := C.ref_s5_decode(C.int(mask), C.uint8_t(payloadType), C.uint32_t(ssrc),
		(*C.uint8_t)(unsafe.SliceData(in)), C.int(len(in)),
		(*C.uint8_t)(unsafe.SliceData(out)), C.int(capacity))
	if n < 0 {
		return nil
	}
	return out[:int(n)]
}

func CRC32(data []byte) uint32 {
	return uint32(C.ref_crc32((*C.uint8_t)(unsafe.SliceData(data)), C.int(len(data))))
}

func StunBindingRequest() []byte {
	out := make([]byte, 128)
	return out[:int(C.ref_stun_binding_request((*C.uint8_t)(unsafe.SliceData(out))))]
}

func PickMediaPreset(payloadType *uint8) uint16 {
	return uint16(C.ref_media_pick_preset((*C.uint8_t)(payloadType)))
}

func StunWrap(payload []byte, capacity int) []byte {
	buf := make([]byte, capacity)
	copy(buf, payload)
	n := C.ref_stun_wrap((*C.uint8_t)(unsafe.SliceData(buf)), C.int(len(payload)))
	return buf[:int(n)]
}

func StunUnwrap(frame []byte) []byte {
	buf := bytes.Clone(frame)
	n := C.ref_stun_unwrap((*C.uint8_t)(unsafe.SliceData(buf)), C.int(len(buf)))
	if n < 0 {
		return nil
	}
	return buf[:int(n)]
}

func MediaWrap(payload []byte, payloadType uint8, ssrc uint32, timestampStep uint16, capacity int) []byte {
	buf := make([]byte, capacity)
	copy(buf, payload)
	n := C.ref_media_wrap((*C.uint8_t)(unsafe.SliceData(buf)), C.int(len(payload)),
		C.uint8_t(payloadType), C.uint32_t(ssrc), C.uint16_t(timestampStep))
	return buf[:int(n)]
}

func MediaUnwrap(frame []byte, payloadType uint8, ssrc uint32) []byte {
	buf := bytes.Clone(frame)
	n := C.ref_media_unwrap((*C.uint8_t)(unsafe.SliceData(buf)), C.int(len(buf)),
		C.uint8_t(payloadType), C.uint32_t(ssrc))
	if n < 0 {
		return nil
	}
	return buf[:int(n)]
}
