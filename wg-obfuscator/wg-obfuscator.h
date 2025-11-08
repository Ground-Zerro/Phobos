#ifndef _WG_OBFUSCATOR_H_
#define _WG_OBFUSCATOR_H_

#include <arpa/inet.h>
#include <errno.h>
#include <stdint.h>
#include "uthash.h"

#ifdef __linux__
#define USE_EPOLL
#endif

#ifdef USE_EPOLL
#include <sys/epoll.h>
#define MAX_EVENTS              1024
#else
#include <poll.h>
#endif

#define WG_OBFUSCATOR_VERSION "1.5"
#define WG_OBFUSCATOR_GIT_REPO "https://github.com/ClusterM/wg-obfuscator"

#define LL_DEFAULT      LL_INFO

#define BUFFER_SIZE                     65535
#define POLL_TIMEOUT                    5000
#define HANDSHAKE_TIMEOUT               5000
#define ITERATE_INTERVAL                1000
#define MAX_DUMMY_LENGTH_TOTAL          1024
#define MAX_DUMMY_LENGTH_HANDSHAKE      512

#define MAX_CLIENTS_DEFAULT             1024
#define IDLE_TIMEOUT_DEFAULT            300000
#define MAX_DUMMY_LENGTH_DATA_DEFAULT   4

#define DEFAULT_INSTANCE_NAME   "main"
#define LL_ERROR        0
#define LL_WARN         1
#define LL_INFO         2
#define LL_DEBUG        3
#define LL_TRACE        4

#define log(level, fmt, ...) { if (verbose >= (level))       \
    fprintf(stderr, "[%s][%c] " fmt "\n", section_name,      \
    (                                                               \
          (level) == LL_ERROR ? 'E'                                 \
        : (level) == LL_WARN  ? 'W'                                 \
        : (level) == LL_INFO  ? 'I'                                 \
        : (level) == LL_DEBUG ? 'D'                                 \
        : (level) == LL_TRACE ? 'T'                                 \
        : '?'                                                       \
    ), ##__VA_ARGS__);                                              \
}
#define trace(fmt, ...) if (verbose >= LL_TRACE) fprintf(stderr, fmt, ##__VA_ARGS__)
#define serror_level(level, fmt, ...) log(level, fmt " - %s (%d)", ##__VA_ARGS__, strerror(errno), errno)
#define serror(fmt, ...) serror_level(LL_ERROR, fmt, ##__VA_ARGS__)

typedef enum {
    DIR_CLIENT_TO_SERVER = 0,
    DIR_SERVER_TO_CLIENT = 1,
} direction_t;

struct masking_handler;
typedef struct masking_handler masking_handler_t;

typedef struct {
    int listen_port;
    char forward_host_port[256];
    char xor_key[256];
    char client_interface[256];
    char static_bindings[10 * 1024];
    int max_clients;
    long idle_timeout;
    int max_dummy_length_data;
    uint32_t fwmark;
    masking_handler_t *masking_handler;

    uint8_t listen_port_set;
    uint8_t forward_host_port_set;
    uint8_t xor_key_set;
    uint8_t client_interface_set;
    uint8_t static_bindings_set;
    uint8_t masking_handler_set;
} obfuscator_config_t;

typedef struct {
    struct sockaddr_in client_addr;
    int server_sock;
    masking_handler_t *masking_handler;
    struct sockaddr_in our_addr;
    uint8_t version;
    uint8_t handshaked          : 1;
    uint8_t handshake_direction : 1;
    uint8_t client_obfuscated   : 1;
    uint8_t server_obfuscated   : 1;
    uint8_t is_static           : 1;
    long last_activity_time;
    long last_handshake_request_time;
    long last_handshake_time;
    long last_masking_timer_time;
    UT_hash_handle hh;
} client_entry_t;

extern int verbose;
extern char section_name[256];

void print_version(void);

#endif
