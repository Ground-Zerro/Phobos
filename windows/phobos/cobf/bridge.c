/* SPDX-License-Identifier: MIT
 *
 * Phobos
 */

#include <stdint.h>
#include <string.h>

#include "obfuscation.h"
#include "socks5_proto.c"
#include "bridge.h"

int cobf_encode(uint8_t *buffer, int length, const char *key, int key_length,
                int max_dummy_data, int obfuscate_bytes) {
    return encode(buffer, length, (char *)key, key_length, OBFUSCATION_VERSION,
                  max_dummy_data, obfuscate_bytes);
}

int cobf_decode(uint8_t *buffer, int length, const char *key, int key_length,
                int obfuscate_bytes, uint8_t *version_out) {
    return decode(buffer, length, (char *)key, key_length, version_out, obfuscate_bytes);
}

void cobf_xor(uint8_t *buffer, int length, const char *key, int key_length) {
    xor_data(buffer, length, (char *)key, key_length);
}

int cobf_stream_size(void) {
    return (int)sizeof(stream_cipher_t);
}

void cobf_stream_init(void *state, const char *key, int key_length) {
    stream_cipher_init((stream_cipher_t *)state, key, key_length);
}

void cobf_stream_apply(void *state, uint8_t *buffer, int length) {
    stream_cipher_apply((stream_cipher_t *)state, buffer, length);
}

int cobf_parse_target(const uint8_t *buf, int len, uint8_t *atyp_out,
                      int *addrlen_out, uint16_t *port_out) {
    socks5_target_t t;
    memset(&t, 0, sizeof(t));
    int consumed = socks5_parse_target(buf, len, 0, &t);
    if (consumed <= 0) return consumed;
    *atyp_out = t.atyp;
    *addrlen_out = t.addrlen;
    *port_out = t.port;
    return consumed;
}

int cobf_build_target(uint8_t *out, int cap, uint8_t atyp,
                      const uint8_t *addr, int addrlen, uint16_t port) {
    socks5_target_t t;
    memset(&t, 0, sizeof(t));
    if (addrlen < 0 || addrlen > (int)sizeof(t.addr)) return -1;
    t.atyp = atyp;
    memcpy(t.addr, addr, (size_t)addrlen);
    t.addrlen = addrlen;
    t.port = port;
    return socks5_build_target(out, cap, &t);
}
