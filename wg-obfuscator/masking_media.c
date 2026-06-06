#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <arpa/inet.h>
#include "wg-obfuscator.h"
#include "masking.h"
#include "masking_media.h"
#include "masking_stun.h"
#include "obfuscation.h"

typedef struct {
    uint8_t pt;
    uint16_t ts_step;
} media_preset_t;

/* Common H.264-over-RTP (payload type, timestamp step = 90000/fps) combinations
   seen in WebRTC, RTSP IP-cameras and streaming. Used when media-pt/media-clock = 0. */
static const media_preset_t media_presets[] = {
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
};
#define MEDIA_PRESET_COUNT (sizeof(media_presets) / sizeof(media_presets[0]))

typedef struct {
    uint16_t seq[2];
    uint32_t timestamp[2];
    uint32_t ssrc[2];
    uint16_t ts_step[2];
    uint8_t pt[2];
    uint8_t init_mask;
} media_state_t;

_Static_assert(sizeof(media_state_t) <= 32, "media_state_t must fit in client masking_priv");

static int media_build_frame(uint8_t *header, int payload_length,
                                obfuscator_config_t *config,
                                client_entry_t *client,
                                direction_t direction) {
    (void)payload_length;
    media_state_t *state = (media_state_t *)client->masking_priv;
    int dir = direction & 1;
    if (!(state->init_mask & (1 << dir))) {
        fast_rng_init();
        state->seq[dir] = (uint16_t)fast_rand();
        state->timestamp[dir] = fast_rand();
        if (config->media_ssrc) {
            state->ssrc[dir] = config->media_ssrc;
        } else {
            uint32_t r = fast_rand();
            state->ssrc[dir] = r ? r : 0x1u;
        }
        const media_preset_t *preset = &media_presets[fast_rand() % MEDIA_PRESET_COUNT];
        state->pt[dir] = config->media_payload_type ? config->media_payload_type : preset->pt;
        state->ts_step[dir] = config->media_ts_step ? config->media_ts_step : preset->ts_step;
        state->init_mask |= (1 << dir);
    }

    header[0] = 0x80;
    header[1] = 0x80 | (state->pt[dir] & 0x7F);
    header[2] = state->seq[dir] >> 8;
    header[3] = state->seq[dir] & 0xFF;
    uint32_t timestamp = htonl(state->timestamp[dir]);
    memcpy(header + 4, &timestamp, 4);
    uint32_t ssrc = htonl(state->ssrc[dir]);
    memcpy(header + 8, &ssrc, 4);

    state->seq[dir]++;
    state->timestamp[dir] += state->ts_step[dir];

    return RTP_HEADER_SIZE;
}

static int media_on_data_wrap(uint8_t *buffer, int length,
                                obfuscator_config_t *config,
                                client_entry_t *client,
                                direction_t direction,
                                const struct sockaddr_in *src_addr,
                                const struct sockaddr_in *dest_addr,
                                send_data_callback_t send_back_callback,
                                send_data_callback_t send_forward_callback) {
    if (length + RTP_HEADER_SIZE > BUFFER_SIZE) {
        log(LL_WARN, "Can't wrap data in RTP, data too large (%d bytes)", length);
        return -ENOMEM;
    }

    memmove(buffer + RTP_HEADER_SIZE, buffer, length);
    media_build_frame(buffer, length, config, client, direction);

    return length + RTP_HEADER_SIZE;
}

static int media_on_data_unwrap(uint8_t *buffer, int length,
                                obfuscator_config_t *config,
                                client_entry_t *client,
                                direction_t direction,
                                const struct sockaddr_in *src_addr,
                                const struct sockaddr_in *dest_addr,
                                send_data_callback_t send_back_callback,
                                send_data_callback_t send_forward_callback) {
    if (stun_check_magic(buffer, length)) {
        return stun_on_data_unwrap(buffer, length, config, client, direction, src_addr, dest_addr, send_back_callback, send_forward_callback);
    }

    if (length < RTP_HEADER_SIZE + 4) {
        return -EINVAL;
    }
    if ((buffer[0] & 0xC0) != 0x80) {
        return -EINVAL;
    }
    if (config->media_payload_type && (buffer[1] & 0x7F) != config->media_payload_type) {
        return -EINVAL;
    }
    if (config->media_ssrc) {
        uint32_t ssrc;
        memcpy(&ssrc, buffer + 8, 4);
        if (ssrc != htonl(config->media_ssrc)) {
            return -EINVAL;
        }
    }

    int data_len = length - RTP_HEADER_SIZE;
    memmove(buffer, buffer + RTP_HEADER_SIZE, data_len);
    return data_len;
}

masking_handler_t media_masking_handler = {
    .name = "MEDIA",
    .on_handshake_req = stun_on_handshake_req,
    .on_data_wrap = media_on_data_wrap,
    .on_data_unwrap = media_on_data_unwrap,
    .on_timer = stun_on_timer,
    .build_frame = media_build_frame,
    .timer_interval_s = 5,
};
