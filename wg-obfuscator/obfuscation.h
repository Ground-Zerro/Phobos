#ifndef _OBFUSCATION_H_
#define _OBFUSCATION_H_

#include <stdint.h>

#ifdef __aarch64__
#include <arm_neon.h>
#endif

#define OBFUSCATION_VERSION     1

#define WG_TYPE_HANDSHAKE       0x01
#define WG_TYPE_HANDSHAKE_RESP  0x02
#define WG_TYPE_COOKIE          0x03
#define WG_TYPE_DATA            0x04

#define WG_TYPE(data) ((uint32_t)(data[0] | (data[1] << 8) | (data[2] << 16) | (data[3] << 24)))
#ifndef MIN
#define MIN(a, b) ((a) < (b) ? (a) : (b))
#endif

static uint8_t crc8_table[256];
static volatile int crc8_table_initialized = 0;

static inline void init_crc8_table(void) {
    if (crc8_table_initialized) return;
    for (int i = 0; i < 256; i++) {
        uint8_t crc = 0;
        uint8_t inbyte = i;
        for (int j = 0; j < 8; j++) {
            uint8_t mix = (crc ^ inbyte) & 0x01;
            crc >>= 1;
            if (mix) {
                crc ^= 0x8C;
            }
            inbyte >>= 1;
        }
        crc8_table[i] = crc;
    }
    crc8_table_initialized = 1;
}

static inline uint8_t is_obfuscated(uint8_t *data) {
    uint32_t packet_type = WG_TYPE(data);
    return !(packet_type >= 1 && packet_type <= 4);
}

#ifdef __aarch64__
static inline void xor_data_neon(uint8_t *buffer, int length, char *key, int key_length) {
    if (!crc8_table_initialized) init_crc8_table();

    uint8_t crc = 0;
    int i = 0;

    if (length >= 16 && key_length >= 4) {
        const int step = 16;

        for (; i + step <= length; i += step) {
            uint8_t inbytes[16];
            for (int j = 0; j < 16; j++) {
                inbytes[j] = key[(i + j) % key_length] + length + key_length;
            }

            for (int j = 0; j < 16; j++) {
                crc = crc8_table[crc ^ inbytes[j]];
                buffer[i + j] ^= crc;
            }
        }
    }

    for (; i < length; i++) {
        uint8_t inbyte = key[i % key_length] + length + key_length;
        crc = crc8_table[crc ^ inbyte];
        buffer[i] ^= crc;
    }
}
#endif

static inline void xor_data(uint8_t *buffer, int length, char *key, int key_length) {
#ifdef __aarch64__
    xor_data_neon(buffer, length, key, key_length);
#else
    if (!crc8_table_initialized) init_crc8_table();

    uint8_t crc = 0;
    const int unroll = 4;
    int i;

    for (i = 0; i + unroll <= length; i += unroll) {
        uint8_t inbyte0 = key[(i + 0) % key_length] + length + key_length;
        crc = crc8_table[crc ^ inbyte0];
        buffer[i + 0] ^= crc;

        uint8_t inbyte1 = key[(i + 1) % key_length] + length + key_length;
        crc = crc8_table[crc ^ inbyte1];
        buffer[i + 1] ^= crc;

        uint8_t inbyte2 = key[(i + 2) % key_length] + length + key_length;
        crc = crc8_table[crc ^ inbyte2];
        buffer[i + 2] ^= crc;

        uint8_t inbyte3 = key[(i + 3) % key_length] + length + key_length;
        crc = crc8_table[crc ^ inbyte3];
        buffer[i + 3] ^= crc;
    }

    for (; i < length; i++) {
        uint8_t inbyte = key[i % key_length] + length + key_length;
        crc = crc8_table[crc ^ inbyte];
        buffer[i] ^= crc;
    }
#endif
}

static inline int encode(uint8_t *buffer, int length, char *key, int key_length, uint8_t version, int max_dummy_length_data) {
    if (version >= 1) {
        uint32_t packet_type = WG_TYPE(buffer);
        uint8_t rnd = 1 + (rand() % 255);
        buffer[0] ^= rnd;
        buffer[1] = rnd;
        if (length < MAX_DUMMY_LENGTH_TOTAL) {
            uint16_t dummy_length = 0;
            uint16_t max_dummy_length = MAX_DUMMY_LENGTH_TOTAL - length;
            if (length < MAX_DUMMY_LENGTH_TOTAL) {
                switch (packet_type) {
                    case WG_TYPE_HANDSHAKE:
                    case WG_TYPE_HANDSHAKE_RESP:
                        dummy_length = rand() % MIN(max_dummy_length, MAX_DUMMY_LENGTH_HANDSHAKE);
                        break;
                    case WG_TYPE_COOKIE:
                    case WG_TYPE_DATA:
                        if (max_dummy_length_data) {
                            dummy_length = rand() % MIN(max_dummy_length, max_dummy_length_data);
                        }
                        break;
                    default:
                        break;
                }
            }
            buffer[2] = dummy_length & 0xFF;
            buffer[3] = dummy_length >> 8;
            if (dummy_length > 0) {
                int i = length;
                length += dummy_length;
                for (; i < length; ++i) {
                    buffer[i] = 0xFF;
                }
            }
        }
    }

    xor_data(buffer, length, key, key_length);

    return length;
}

static inline int decode(uint8_t *buffer, int length, char *key, int key_length, uint8_t *version_out) {
    xor_data(buffer, length, key, key_length);

    if (!is_obfuscated(buffer)) {
        *version_out = 0;
        return length;
    }

    buffer[0] ^= buffer[1];
    length -= (uint16_t)(buffer[2] | (buffer[3] << 8));
    buffer[1] = buffer[2] = buffer[3] = 0;
    return length;
}

#endif