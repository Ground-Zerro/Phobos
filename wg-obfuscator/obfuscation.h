#ifndef _OBFUSCATION_H_
#define _OBFUSCATION_H_

#include <stdint.h>
#include <string.h>
#include <time.h>

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

#if defined(__x86_64__) || defined(__aarch64__)
#define XOR_CACHE_ENTRIES 32
#else
#define XOR_CACHE_ENTRIES 8
#endif
#define XOR_CACHE_MAX_LEN 1500

typedef struct {
    int length;
    int key_length;
    uint8_t mask[XOR_CACHE_MAX_LEN];
} xor_cache_entry_t;

static _Thread_local xor_cache_entry_t xor_cache[XOR_CACHE_ENTRIES];
static _Thread_local int xor_cache_count = 0;

#ifdef ARCH_X86
static volatile int cpu_features_detected = 0;
static volatile int cpu_has_avx2 = 0;
static volatile int cpu_has_avx512f = 0;

static inline void detect_cpu_features(void) {
    if (cpu_features_detected) return;
    unsigned int eax, ebx, ecx, edx;
    if (__get_cpuid(7, &eax, &ebx, &ecx, &edx)) {
        cpu_has_avx2 = (ebx & (1 << 5)) != 0;
        cpu_has_avx512f = (ebx & (1 << 16)) != 0;
    }
    cpu_features_detected = 1;
}
#endif

static _Thread_local uint32_t rng_state = 0;

static inline void fast_rng_init(void) {
    if (rng_state) return;
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    rng_state = (uint32_t)(ts.tv_nsec ^ ts.tv_sec ^ (uintptr_t)&rng_state);
    if (rng_state == 0) rng_state = 1;
}

static inline uint32_t fast_rand(void) {
    uint32_t x = rng_state;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    rng_state = x;
    return x;
}

static inline void fast_rand_bytes(uint8_t *p, size_t n) {
    while (n >= 4) {
        uint32_t r = fast_rand();
        memcpy(p, &r, 4);
        p += 4; n -= 4;
    }
    if (n > 0) {
        uint32_t r = fast_rand();
        for (size_t i = 0; i < n; i++) p[i] = (r >> (i * 8)) & 0xFF;
    }
}

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
    fast_rng_init();
#ifdef ARCH_X86
    detect_cpu_features();
#endif
}

static inline uint8_t is_obfuscated(uint8_t *data) {
    return data[0] < 1 || data[0] > 4 || data[1] | data[2] | data[3];
}

#ifdef ARCH_X86

__attribute__((target("avx2")))
static inline void xor_data_avx2(uint8_t *buffer, int length, char *key, int key_length) {
    uint8_t crc = 0;
    int i = 0;
    const int step = 32;
    uint8_t key_adj[256];
    const uint8_t base = (uint8_t)(length + key_length);
    for (int k = 0; k < key_length; k++) key_adj[k] = key[k] + base;
    int ki = 0;

    for (; i + step <= length; i += step) {
        uint8_t crcs[32];
        for (int j = 0; j < 32; j++) {
            crc = crc8_table[crc ^ key_adj[ki]];
            crcs[j] = crc;
            if (++ki >= key_length) ki = 0;
        }

        __m256i buf_vec = _mm256_loadu_si256((__m256i*)(buffer + i));
        __m256i crc_vec = _mm256_loadu_si256((__m256i*)crcs);
        buf_vec = _mm256_xor_si256(buf_vec, crc_vec);
        _mm256_storeu_si256((__m256i*)(buffer + i), buf_vec);
    }

    for (; i < length; i++) {
        crc = crc8_table[crc ^ key_adj[ki]];
        buffer[i] ^= crc;
        if (++ki >= key_length) ki = 0;
    }
}

__attribute__((target("avx512f")))
static inline void xor_data_avx512(uint8_t *buffer, int length, char *key, int key_length) {
    uint8_t crc = 0;
    int i = 0;
    const int step = 64;
    uint8_t key_adj[256];
    const uint8_t base = (uint8_t)(length + key_length);
    for (int k = 0; k < key_length; k++) key_adj[k] = key[k] + base;
    int ki = 0;

    for (; i + step <= length; i += step) {
        uint8_t crcs[64];
        for (int j = 0; j < 64; j++) {
            crc = crc8_table[crc ^ key_adj[ki]];
            crcs[j] = crc;
            if (++ki >= key_length) ki = 0;
        }

        __m512i buf_vec = _mm512_loadu_si512((__m512i*)(buffer + i));
        __m512i crc_vec = _mm512_loadu_si512((__m512i*)crcs);
        buf_vec = _mm512_xor_si512(buf_vec, crc_vec);
        _mm512_storeu_si512((__m512i*)(buffer + i), buf_vec);
    }

    for (; i < length; i++) {
        crc = crc8_table[crc ^ key_adj[ki]];
        buffer[i] ^= crc;
        if (++ki >= key_length) ki = 0;
    }
}

static inline void xor_data_sse2(uint8_t *buffer, int length, char *key, int key_length) {
    uint8_t crc = 0;
    int i = 0;
    const int step = 16;
    uint8_t key_adj[256];
    const uint8_t base = (uint8_t)(length + key_length);
    for (int k = 0; k < key_length; k++) key_adj[k] = key[k] + base;
    int ki = 0;

    for (; i + step <= length; i += step) {
        uint8_t crcs[16];
        for (int j = 0; j < 16; j++) {
            crc = crc8_table[crc ^ key_adj[ki]];
            crcs[j] = crc;
            if (++ki >= key_length) ki = 0;
        }

        __m128i buf_vec = _mm_loadu_si128((__m128i*)(buffer + i));
        __m128i crc_vec = _mm_loadu_si128((__m128i*)crcs);
        buf_vec = _mm_xor_si128(buf_vec, crc_vec);
        _mm_storeu_si128((__m128i*)(buffer + i), buf_vec);
    }

    for (; i < length; i++) {
        crc = crc8_table[crc ^ key_adj[ki]];
        buffer[i] ^= crc;
        if (++ki >= key_length) ki = 0;
    }
}

#endif

#ifdef ARCH_ARM_NEON

static inline void xor_data_neon(uint8_t *buffer, int length, char *key, int key_length) {
    uint8_t crc = 0;
    int i = 0;
    const int step = 16;
    uint8_t key_adj[256];
    const uint8_t base = (uint8_t)(length + key_length);
    for (int k = 0; k < key_length; k++) key_adj[k] = key[k] + base;
    int ki = 0;

    for (; i + step <= length; i += step) {
        uint8_t crcs[16];
        for (int j = 0; j < 16; j++) {
            crc = crc8_table[crc ^ key_adj[ki]];
            crcs[j] = crc;
            if (++ki >= key_length) ki = 0;
        }

        uint8x16_t buf_vec = vld1q_u8(buffer + i);
        uint8x16_t crc_vec = vld1q_u8(crcs);
        buf_vec = veorq_u8(buf_vec, crc_vec);
        vst1q_u8(buffer + i, buf_vec);
    }

    for (; i < length; i++) {
        crc = crc8_table[crc ^ key_adj[ki]];
        buffer[i] ^= crc;
        if (++ki >= key_length) ki = 0;
    }
}

#endif

static inline void xor_data_scalar(uint8_t *buffer, int length, char *key, int key_length) {
    uint8_t crc = 0;
    const int unroll = 8;
    int i;
    uint8_t key_adj[256];
    const uint8_t base = (uint8_t)(length + key_length);
    for (int k = 0; k < key_length; k++) key_adj[k] = key[k] + base;
    int ki = 0;

    for (i = 0; i + unroll <= length; i += unroll) {
        crc = crc8_table[crc ^ key_adj[ki]];
        buffer[i + 0] ^= crc;
        if (++ki >= key_length) ki = 0;

        crc = crc8_table[crc ^ key_adj[ki]];
        buffer[i + 1] ^= crc;
        if (++ki >= key_length) ki = 0;

        crc = crc8_table[crc ^ key_adj[ki]];
        buffer[i + 2] ^= crc;
        if (++ki >= key_length) ki = 0;

        crc = crc8_table[crc ^ key_adj[ki]];
        buffer[i + 3] ^= crc;
        if (++ki >= key_length) ki = 0;

        crc = crc8_table[crc ^ key_adj[ki]];
        buffer[i + 4] ^= crc;
        if (++ki >= key_length) ki = 0;

        crc = crc8_table[crc ^ key_adj[ki]];
        buffer[i + 5] ^= crc;
        if (++ki >= key_length) ki = 0;

        crc = crc8_table[crc ^ key_adj[ki]];
        buffer[i + 6] ^= crc;
        if (++ki >= key_length) ki = 0;

        crc = crc8_table[crc ^ key_adj[ki]];
        buffer[i + 7] ^= crc;
        if (++ki >= key_length) ki = 0;
    }

    for (; i < length; i++) {
        crc = crc8_table[crc ^ key_adj[ki]];
        buffer[i] ^= crc;
        if (++ki >= key_length) ki = 0;
    }
}

static inline void xor_generate_mask(uint8_t *mask, int length, char *key, int key_length) {
    uint8_t crc = 0;
    uint8_t key_adj[256];
    const uint8_t base = (uint8_t)(length + key_length);
    for (int k = 0; k < key_length; k++) key_adj[k] = key[k] + base;
    int ki = 0;
    for (int i = 0; i < length; i++) {
        crc = crc8_table[crc ^ key_adj[ki]];
        mask[i] = crc;
        if (++ki >= key_length) ki = 0;
    }
}

static inline xor_cache_entry_t *xor_cache_find(int length, int key_length) {
    for (int i = 0; i < xor_cache_count; i++) {
        if (xor_cache[i].length == length && xor_cache[i].key_length == key_length) {
            return &xor_cache[i];
        }
    }
    return NULL;
}

static inline void xor_apply_cached(uint8_t *buffer, int length, char *key, int key_length) {
    xor_cache_entry_t *entry = xor_cache_find(length, key_length);

    if (!entry && length <= XOR_CACHE_MAX_LEN) {
        if (xor_cache_count < XOR_CACHE_ENTRIES) {
            entry = &xor_cache[xor_cache_count++];
        } else {
            entry = &xor_cache[fast_rand() % XOR_CACHE_ENTRIES];
        }
        entry->length = length;
        entry->key_length = key_length;
        xor_generate_mask(entry->mask, length, key, key_length);
    }

    if (entry) {
        int i = 0;
#ifdef ARCH_X86
        for (; i + 16 <= length; i += 16) {
            __m128i buf_vec = _mm_loadu_si128((__m128i*)(buffer + i));
            __m128i mask_vec = _mm_loadu_si128((__m128i*)(entry->mask + i));
            _mm_storeu_si128((__m128i*)(buffer + i), _mm_xor_si128(buf_vec, mask_vec));
        }
#elif defined(ARCH_ARM_NEON)
        for (; i + 16 <= length; i += 16) {
            uint8x16_t buf_vec = vld1q_u8(buffer + i);
            uint8x16_t mask_vec = vld1q_u8(entry->mask + i);
            vst1q_u8(buffer + i, veorq_u8(buf_vec, mask_vec));
        }
#endif
        for (; i < length; i++) {
            buffer[i] ^= entry->mask[i];
        }
        return;
    }
}

static inline void xor_data(uint8_t *buffer, int length, char *key, int key_length) {
    if (!crc8_table_initialized) init_crc8_table();

    if (length <= XOR_CACHE_MAX_LEN) {
        xor_apply_cached(buffer, length, key, key_length);
        return;
    }

#ifdef ARCH_X86
    if (cpu_has_avx512f && length >= 64) {
        xor_data_avx512(buffer, length, key, key_length);
    } else if (cpu_has_avx2 && length >= 32) {
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
        uint8_t rnd = 1 + (fast_rand() % 255);
        buffer[0] ^= rnd;
        buffer[1] = rnd;
        if (length < MAX_DUMMY_LENGTH_TOTAL) {
            uint16_t dummy_length = 0;
            uint16_t max_dummy_length = MAX_DUMMY_LENGTH_TOTAL - length;
            if (length < MAX_DUMMY_LENGTH_TOTAL) {
                switch (packet_type) {
                    case WG_TYPE_HANDSHAKE:
                    case WG_TYPE_HANDSHAKE_RESP:
                        dummy_length = fast_rand() % MIN(max_dummy_length, MAX_DUMMY_LENGTH_HANDSHAKE);
                        break;
                    case WG_TYPE_COOKIE:
                    case WG_TYPE_DATA:
                        if (max_dummy_length_data) {
                            dummy_length = fast_rand() % MIN(max_dummy_length, max_dummy_length_data);
                        }
                        break;
                    default:
                        break;
                }
            }
            buffer[2] = dummy_length & 0xFF;
            buffer[3] = dummy_length >> 8;
            if (dummy_length > 0) {
                memset(buffer + length, 0xFF, dummy_length);
                length += dummy_length;
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