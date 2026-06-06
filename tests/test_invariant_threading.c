#include <check.h>
#include <stdlib.h>
#include <string.h>

/* We need to test that the packet processing function in threading.c
 * does not allow memcpy to overflow pp->data when length exceeds the
 * allocated buffer size. We include the relevant header and call the
 * actual function. Since the vulnerable code is in threading.c's packet
 * handling, we simulate by calling the function that processes incoming
 * packets with oversized length values.
 */

/* Include the project headers to access the packet processing interface */
#include "wg-obfuscator/threading.h"

/* Maximum expected packet data size (typical WireGuard max is ~1500-4096) */
#ifndef MAX_PACKET_SIZE
#define MAX_PACKET_SIZE 4096
#endif

START_TEST(test_buffer_read_never_exceeds_declared_length)
{
    /* Invariant: memcpy into pp->data must never copy more bytes than
     * the allocated size of pp->data, regardless of the length parameter
     * received from the network. */

    struct {
        size_t length;
        const char *desc;
    } cases[] = {
        { MAX_PACKET_SIZE * 2,  "2x overflow" },
        { MAX_PACKET_SIZE * 10, "10x overflow" },
        { MAX_PACKET_SIZE + 1,  "boundary +1" },
        { MAX_PACKET_SIZE,      "exact boundary" },
        { 64,                   "valid small packet" },
    };
    int num_cases = sizeof(cases) / sizeof(cases[0]);

    for (int i = 0; i < num_cases; i++) {
        size_t length = cases[i].length;
        unsigned char *buffer = calloc(length, 1);
        ck_assert_ptr_nonnull(buffer);
        memset(buffer, 'A', length);

        /* Allocate a packet structure with known guard bytes after data */
        size_t alloc_size = MAX_PACKET_SIZE + 64; /* 64 bytes guard zone */
        unsigned char *raw = calloc(1, sizeof(struct pending_packet) + alloc_size);
        ck_assert_ptr_nonnull(raw);

        struct pending_packet *pp = (struct pending_packet *)raw;
        /* Set guard pattern after the valid data area */
        unsigned char *guard = pp->data + MAX_PACKET_SIZE;
        memset(guard, 0xDE, 64);

        /* Call the packet receive/process function with untrusted length */
        int ret = process_incoming_packet(pp, buffer, length);

        /* Either the function rejects oversized input (ret != 0)
         * or it truncates — but guard bytes must be intact */
        if (length > MAX_PACKET_SIZE) {
            /* Must reject or truncate */
            if (ret == 0) {
                /* If accepted, verify no overflow into guard zone */
                for (int j = 0; j < 64; j++) {
                    ck_assert_msg(guard[j] == 0xDE,
                        "Heap overflow detected at guard[%d] with length=%zu (%s)",
                        j, length, cases[i].desc);
                }
            }
        } else {
            /* Valid size: should succeed without overflow */
            for (int j = 0; j < 64; j++) {
                ck_assert_msg(guard[j] == 0xDE,
                    "Unexpected overflow at guard[%d] with valid length=%zu",
                    j, length);
            }
        }

        free(raw);
        free(buffer);
    }
}
END_TEST

Suite *security_suite(void)
{
    Suite *s;
    TCase *tc_core;

    s = suite_create("Security");
    tc_core = tcase_create("Core");

    tcase_add_test(tc_core, test_buffer_read_never_exceeds_declared_length);
    suite_add_tcase(s, tc_core);

    return s;
}

int main(void)
{
    int number_failed;
    Suite *s;
    SRunner *sr;

    s = security_suite();
    sr = srunner_create(s);

    srunner_run_all(sr, CK_NORMAL);
    number_failed = srunner_ntests_failed(sr);
    srunner_free(sr);

    return (number_failed == 0) ? EXIT_SUCCESS : EXIT_FAILURE;
}