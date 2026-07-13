#ifndef _SOCKS5_MASK_H_
#define _SOCKS5_MASK_H_

#include <stdint.h>
#include "wg-obfuscator.h"

#define S5_MASK_NONE   0
#define S5_MASK_STUN   1
#define S5_MASK_MEDIA  2
#define S5_MASK_TLS    3

#define S5_FRAME_PAYLOAD_MAX 1024
#define S5_ACC_MAX           2048
#define S5_ENCODE_READ_MAX   12288

typedef struct {
    uint16_t seq;
    uint32_t ts;
    uint32_t ssrc;
    uint16_t ts_step;
    uint8_t pt;
    uint8_t init;
} s5_enc_t;

typedef struct {
    uint8_t acc[S5_ACC_MAX];
    int acc_len;
} s5_dec_t;

int s5_mask_type(const obfuscator_config_t *config);

int s5_mask_is_framed(int type, const obfuscator_config_t *config, const uint8_t *buf, int len);

int s5_mask_encode(int type, s5_enc_t *st, const obfuscator_config_t *config,
                   const uint8_t *src, int src_len, uint8_t *out, int out_cap);

int s5_mask_decode(int type, s5_dec_t *st, const obfuscator_config_t *config,
                   const uint8_t *in, int in_len, uint8_t *out, int out_cap);

#endif
