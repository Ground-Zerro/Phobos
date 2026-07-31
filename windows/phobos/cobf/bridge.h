/* SPDX-License-Identifier: MIT
 *
 * Phobos
 */

#ifndef _COBF_BRIDGE_H_
#define _COBF_BRIDGE_H_

#include <stdint.h>

int cobf_encode(uint8_t *buffer, int length, const char *key, int key_length,
                int max_dummy_data, int obfuscate_bytes);
int cobf_decode(uint8_t *buffer, int length, const char *key, int key_length,
                int obfuscate_bytes, uint8_t *version_out);
void cobf_xor(uint8_t *buffer, int length, const char *key, int key_length);

int cobf_stream_size(void);
void cobf_stream_init(void *state, const char *key, int key_length);
void cobf_stream_apply(void *state, uint8_t *buffer, int length);

int cobf_parse_target(const uint8_t *buf, int len, uint8_t *atyp_out,
                      int *addrlen_out, uint16_t *port_out);
int cobf_build_target(uint8_t *out, int cap, uint8_t atyp,
                      const uint8_t *addr, int addrlen, uint16_t port);

#endif
