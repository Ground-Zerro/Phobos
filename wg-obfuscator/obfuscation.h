#ifndef _OBFUSCATION_H_
#define _OBFUSCATION_H_

#include <stdint.h>

#if defined(__x86_64__) || defined(__i386__) || defined(_M_X64) || defined(_M_IX86)
#include <immintrin.h>
#include <cpuid.h>
#define ARCH_X86
#endif

#if defined(__aarch64__) || defined(__arm__) || defined(_M_ARM64) || defined(_M_ARM)
#if defined(__ARM_NEON) || defined(__aarch64__)
#include <arm_neon.h>
#define ARCH_ARM_NEON
#endif
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

#ifdef ARCH_X86
static volatile int cpu_features_detected = 0;
static volatile int cpu_has_avx2 = 0;

static inline void detect_cpu_features(void) {
    if (cpu_features_detected) return;
    unsigned int eax, ebx, ecx, edx;
    if (__get_cpuid(7, &eax, &ebx, &ecx, &edx)) {
        cpu_has_avx2 = (ebx & (1 << 5)) != 0;
    }
    cpu_features_detected = 1;
}
#endif

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
#ifdef ARCH_X86
    detect_cpu_features();
#endif
}

static inline uint8_t is_obfuscated(uint8_t *data) {
    uint32_t packet_type = WG_TYPE(data);
    return !(packet_type >= 1 && packet_type <= 4);
}

#ifdef ARCH_X86

__attribute__((target("avx2")))
static inline void xor_data_avx2(uint8_t *buffer, int length, char *key, int key_length) {
    uint8_t crc = 0;
    int i = 0;
    const int step = 32;

    for (; i + step <= length; i += step) {
        uint8_t crcs[32];
        for (int j = 0; j < 32; j++) {
            uint8_t inbyte = key[(i + j) % key_length] + length + key_length;
            crc = crc8_table[crc ^ inbyte];
            crcs[j] = crc;
        }

        __m256i buf_vec = _mm256_loadu_si256((__m256i*)(buffer + i));
        __m256i crc_vec = _mm256_loadu_si256((__m256i*)crcs);
        buf_vec = _mm256_xor_si256(buf_vec, crc_vec);
        _mm256_storeu_si256((__m256i*)(buffer + i), buf_vec);
    }

    for (; i < length; i++) {
        uint8_t inbyte = key[i % key_length] + length + key_length;
        crc = crc8_table[crc ^ inbyte];
        buffer[i] ^= crc;
    }
}

static inline void xor_data_sse2(uint8_t *buffer, int length, char *key, int key_length) {
    uint8_t crc = 0;
    int i = 0;
    const int step = 16;

    for (; i + step <= length; i += step) {
        uint8_t crcs[16];
        for (int j = 0; j < 16; j++) {
            uint8_t inbyte = key[(i + j) % key_length] + length + key_length;
            crc = crc8_table[crc ^ inbyte];
            crcs[j] = crc;
        }

        __m128i buf_vec = _mm_loadu_si128((__m128i*)(buffer + i));
        __m128i crc_vec = _mm_loadu_si128((__m128i*)crcs);
        buf_vec = _mm_xor_si128(buf_vec, crc_vec);
        _mm_storeu_si128((__m128i*)(buffer + i), buf_vec);
    }

    for (; i < length; i++) {
        uint8_t inbyte = key[i % key_length] + length + key_length;
        crc = crc8_table[crc ^ inbyte];
        buffer[i] ^= crc;
    }
}

#endif

#ifdef ARCH_ARM_NEON

static inline void xor_data_neon(uint8_t *buffer, int length, char *key, int key_length) {
    uint8_t crc = 0;
    int i = 0;
    const int step = 16;

    for (; i + step <= length; i += step) {
        uint8_t crcs[16];
        for (int j = 0; j < 16; j++) {
            uint8_t inbyte = key[(i + j) % key_length] + length + key_length;
            crc = crc8_table[crc ^ inbyte];
            crcs[j] = crc;
        }

        uint8x16_t buf_vec = vld1q_u8(buffer + i);
        uint8x16_t crc_vec = vld1q_u8(crcs);
        buf_vec = veorq_u8(buf_vec, crc_vec);
        vst1q_u8(buffer + i, buf_vec);
    }

    for (; i < length; i++) {
        uint8_t inbyte = key[i % key_length] + length + key_length;
        crc = crc8_table[crc ^ inbyte];
        buffer[i] ^= crc;
    }
}

#endif

static inline void xor_data_scalar(uint8_t *buffer, int length, char *key, int key_length) {
    uint8_t crc = 0;
    const int unroll = 8;
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

        uint8_t inbyte4 = key[(i + 4) % key_length] + length + key_length;
        crc = crc8_table[crc ^ inbyte4];
        buffer[i + 4] ^= crc;

        uint8_t inbyte5 = key[(i + 5) % key_length] + length + key_length;
        crc = crc8_table[crc ^ inbyte5];
        buffer[i + 5] ^= crc;

        uint8_t inbyte6 = key[(i + 6) % key_length] + length + key_length;
        crc = crc8_table[crc ^ inbyte6];
        buffer[i + 6] ^= crc;

        uint8_t inbyte7 = key[(i + 7) % key_length] + length + key_length;
        crc = crc8_table[crc ^ inbyte7];
        buffer[i + 7] ^= crc;
    }

    for (; i < length; i++) {
        uint8_t inbyte = key[i % key_length] + length + key_length;
        crc = crc8_table[crc ^ inbyte];
        buffer[i] ^= crc;
    }
}

static inline void xor_data(uint8_t *buffer, int length, char *key, int key_length) {
    if (!crc8_table_initialized) init_crc8_table();

#ifdef ARCH_X86
    if (cpu_has_avx2 && length >= 32) {
        xor_data_avx2(buffer, length, key, key_length);
    } else if (length >= 16) {
        xor_data_sse2(buffer, length, key, key_length);
    } else {
        xor_data_scalar(buffer, length, key, key_length);
    }
#elif defined(ARCH_ARM_NEON)
    if (length >= 16) {
        xor_data_neon(buffer, length, key, key_length);
    } else {
        xor_data_scalar(buffer, length, key, key_length);
    }
#else
    xor_data_scalar(buffer, length, key, key_length);
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