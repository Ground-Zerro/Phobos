#include <stdint.h>
#include <string.h>
#include <errno.h>
#include <arpa/inet.h>
#include "socks5_mask.h"
#include "masking.h"
#include "masking_stun.h"
#include "masking_media.h"
#include "obfuscation.h"

#define STUN_DATA_IND_HEADER 24
#define RTP_TCP_HEADER (2 + RTP_HEADER_SIZE)
#define TLS_REC_HEADER 5

int s5_mask_type(const obfuscator_config_t *config) {
    return config->socks5_mask;
}

int s5_mask_is_framed(int type, const obfuscator_config_t *config, const uint8_t *buf, int len) {
    if (type == S5_MASK_STUN) {
        if (len >= 1 && buf[0] != (STUN_TYPE_DATA_IND >> 8)) return 0;
        if (len >= 2 && buf[1] != (STUN_TYPE_DATA_IND & 0xFF)) return 0;
        if (len < 8) return -1;
        return memcmp(buf + 4, COOKIE_BE, 4) == 0 ? 1 : 0;
    }
    if (type == S5_MASK_MEDIA) {
        if (len >= 3 && (buf[2] & 0xC0) != 0x80) return 0;
        if (len >= 4 && config->media_payload_type && (buf[3] & 0x7F) != config->media_payload_type) return 0;
        if (config->media_ssrc) {
            if (len < 2 + RTP_HEADER_SIZE) return -1;
            uint32_t ssrc;
            memcpy(&ssrc, buf + 10, 4);
            return ssrc == htonl(config->media_ssrc) ? 1 : 0;
        }
        if (len < 4) return -1;
        return 1;
    }
    if (type == S5_MASK_TLS) {
        if (len >= 1 && buf[0] != 0x17) return 0;
        if (len >= 3 && (buf[1] != 0x03 || buf[2] != 0x03)) return 0;
        if (len < 3) return -1;
        return 1;
    }
    return 0;
}

static void enc_init(s5_enc_t *st, const obfuscator_config_t *config) {
    fast_rng_init();
    st->seq = (uint16_t)fast_rand();
    st->ts = fast_rand();
    if (config->media_ssrc) {
        st->ssrc = config->media_ssrc;
    } else {
        uint32_t r = fast_rand();
        st->ssrc = r ? r : 0x1u;
    }
    uint8_t preset_pt;
    uint16_t preset_step = media_pick_preset(&preset_pt);
    st->pt = config->media_payload_type ? config->media_payload_type : preset_pt;
    st->ts_step = config->media_ts_step ? config->media_ts_step : preset_step;
    st->init = 1;
}

static int encode_stun(const uint8_t *src, int payload, uint8_t *out) {
    int pad = (4 - (payload & 3)) & 3;
    int mlen = 4 + payload + pad;
    out[0] = STUN_TYPE_DATA_IND >> 8;
    out[1] = STUN_TYPE_DATA_IND & 0xFF;
    out[2] = (mlen >> 8) & 0xFF;
    out[3] = mlen & 0xFF;
    memcpy(out + 4, COOKIE_BE, 4);
    fast_rand_bytes(out + 8, 12);
    out[20] = STUN_ATTR_DATA >> 8;
    out[21] = STUN_ATTR_DATA & 0xFF;
    out[22] = (payload >> 8) & 0xFF;
    out[23] = payload & 0xFF;
    memcpy(out + 24, src, payload);
    if (pad) memset(out + 24 + payload, 0, pad);
    return 24 + payload + pad;
}

static int encode_tls(const uint8_t *src, int payload, uint8_t *out) {
    out[0] = 0x17;
    out[1] = 0x03;
    out[2] = 0x03;
    out[3] = (payload >> 8) & 0xFF;
    out[4] = payload & 0xFF;
    memcpy(out + TLS_REC_HEADER, src, payload);
    return TLS_REC_HEADER + payload;
}

static int encode_media(s5_enc_t *st, const uint8_t *src, int payload, uint8_t *out) {
    int L = RTP_HEADER_SIZE + payload;
    out[0] = (L >> 8) & 0xFF;
    out[1] = L & 0xFF;
    uint16_t seq = st->seq++;
    uint32_t ts = st->ts;
    st->ts += st->ts_step;
    out[2] = 0x80;
    out[3] = 0x80 | (st->pt & 0x7F);
    out[4] = seq >> 8;
    out[5] = seq & 0xFF;
    uint32_t nts = htonl(ts);
    memcpy(out + 6, &nts, 4);
    uint32_t nssrc = htonl(st->ssrc);
    memcpy(out + 10, &nssrc, 4);
    memcpy(out + 2 + RTP_HEADER_SIZE, src, payload);
    return RTP_TCP_HEADER + payload;
}

int s5_mask_encode(int type, s5_enc_t *st, const obfuscator_config_t *config,
                   const uint8_t *src, int src_len, uint8_t *out, int out_cap) {
    if (type == S5_MASK_MEDIA && !st->init) enc_init(st, config);
    int ip = 0, op = 0;
    while (ip < src_len) {
        int chunk = src_len - ip;
        if (chunk > S5_FRAME_PAYLOAD_MAX) chunk = S5_FRAME_PAYLOAD_MAX;
        int need;
        if (type == S5_MASK_STUN) need = STUN_DATA_IND_HEADER + chunk + ((4 - (chunk & 3)) & 3);
        else if (type == S5_MASK_TLS) need = TLS_REC_HEADER + chunk;
        else need = RTP_TCP_HEADER + chunk;
        if (op + need > out_cap) return -1;
        if (type == S5_MASK_STUN) op += encode_stun(src + ip, chunk, out + op);
        else if (type == S5_MASK_TLS) op += encode_tls(src + ip, chunk, out + op);
        else op += encode_media(st, src + ip, chunk, out + op);
        ip += chunk;
    }
    return op;
}

int s5_mask_decode(int type, s5_dec_t *st, const obfuscator_config_t *config,
                   const uint8_t *in, int in_len, uint8_t *out, int out_cap) {
    static _Thread_local uint8_t work[S5_ACC_MAX + S5_ENCODE_READ_MAX + 16];
    int wl = st->acc_len;
    if (wl) memcpy(work, st->acc, wl);
    if (in_len > S5_ENCODE_READ_MAX) return -1;
    memcpy(work + wl, in, in_len);
    wl += in_len;

    int pos = 0, outlen = 0;
    while (1) {
        int rem = wl - pos;
        if (type == S5_MASK_STUN) {
            if (rem < STUN_DATA_IND_HEADER) break;
            if (memcmp(work + pos + 4, COOKIE_BE, 4) != 0) return -1;
            uint16_t mtype = (work[pos] << 8) | work[pos + 1];
            if (mtype != STUN_TYPE_DATA_IND) return -1;
            uint16_t mlen = (work[pos + 2] << 8) | work[pos + 3];
            int total = 20 + mlen;
            if (total < STUN_DATA_IND_HEADER || total > (int)S5_ACC_MAX) return -1;
            if (rem < total) break;
            uint16_t at = (work[pos + 20] << 8) | work[pos + 21];
            if (at != STUN_ATTR_DATA) return -1;
            uint16_t dl = (work[pos + 22] << 8) | work[pos + 23];
            if (STUN_DATA_IND_HEADER + dl > total) return -1;
            if (outlen + dl > out_cap) return -1;
            memcpy(out + outlen, work + pos + STUN_DATA_IND_HEADER, dl);
            outlen += dl;
            pos += total;
        } else if (type == S5_MASK_TLS) {
            if (rem < TLS_REC_HEADER) break;
            if (work[pos] != 0x17 || work[pos + 1] != 0x03 || work[pos + 2] != 0x03) return -1;
            int L = (work[pos + 3] << 8) | work[pos + 4];
            if (L < 1 || L > (int)S5_ACC_MAX) return -1;
            if (rem < TLS_REC_HEADER + L) break;
            if (outlen + L > out_cap) return -1;
            memcpy(out + outlen, work + pos + TLS_REC_HEADER, L);
            outlen += L;
            pos += TLS_REC_HEADER + L;
        } else {
            if (rem < 2) break;
            int L = (work[pos] << 8) | work[pos + 1];
            if (L < RTP_HEADER_SIZE || L > (int)S5_ACC_MAX) return -1;
            if (rem < 2 + L) break;
            if ((work[pos + 2] & 0xC0) != 0x80) return -1;
            if (config->media_payload_type && (work[pos + 3] & 0x7F) != config->media_payload_type) return -1;
            int payload = L - RTP_HEADER_SIZE;
            if (outlen + payload > out_cap) return -1;
            memcpy(out + outlen, work + pos + 2 + RTP_HEADER_SIZE, payload);
            outlen += payload;
            pos += 2 + L;
        }
    }

    int left = wl - pos;
    if (left > (int)S5_ACC_MAX) return -1;
    if (left) memmove(st->acc, work + pos, left);
    st->acc_len = left;
    return outlen;
}
