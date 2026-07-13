#ifndef _SOCKS5_H_
#define _SOCKS5_H_

#include <stdint.h>
#include <pthread.h>
#include <netinet/in.h>
#include "wg-obfuscator.h"

#define SOCKS5_MAX_WORKERS 256
#define SOCKS5_MAX_ROUTES  257

struct socks5_conn;

typedef struct {
    uint8_t kind;
    int fd;
    struct sockaddr_in fwd;
    uint8_t has_fwd;
} socks5_listen_t;

typedef struct socks5_worker {
    pthread_t thread_id;
    int worker_index;
    int cpu;
    int epfd;
    int listen_sock;
    struct socks5_conn *conns;
    struct socks5_conn *dead;
    long last_cleanup_time;
    struct socks5_context *ctx;
    volatile int running;
} socks5_worker_t;

typedef struct socks5_context {
    int num_workers;
    socks5_worker_t workers[SOCKS5_MAX_WORKERS];
    int listen_sock;
    in_addr_t listen_addr;
    uint16_t listen_port;
    socks5_listen_t routes[SOCKS5_MAX_ROUTES];
    int route_count;
    obfuscator_config_t *config;
    char *xor_key;
    int key_length;
    struct sockaddr_in forward_addr;
    volatile int running;
} socks5_context_t;

int socks5_init(socks5_context_t *ctx, obfuscator_config_t *config);
int socks5_start(socks5_context_t *ctx, obfuscator_config_t *config,
                 char *xor_key, int key_length, struct sockaddr_in *forward_addr,
                 in_addr_t listen_addr, uint16_t listen_port);
void socks5_shutdown(socks5_context_t *ctx);
void socks5_join(socks5_context_t *ctx);

typedef void (*socks5_socket_protect_cb)(int fd);
void socks5_set_socket_protect(socks5_socket_protect_cb cb);

#endif
