#ifndef _THREADING_H_
#define _THREADING_H_

#include <stdint.h>
#include <pthread.h>
#include <netinet/in.h>
#include "wg-obfuscator.h"

#define MAX_WORKER_THREADS 256
#define RX_BATCH 16
#define WORKER_BUF_SIZE 2048
#define WORKER_FRAME_MAX 32

typedef struct worker_ctx {
    pthread_t thread_id;
    int worker_index;
    int cpu;
    int is_maintainer;
    int listen_sock;
    int epfd;
    obfuscator_config_t *config;
    char *xor_key;
    int key_length;
    struct sockaddr_in *forward_addr;
    long last_cleanup_time;
    volatile int running;
} worker_ctx_t;

typedef struct {
    int num_workers;
    worker_ctx_t workers[MAX_WORKER_THREADS];
    int listen_sock;
    int epfd;
    in_addr_t listen_addr;
    uint16_t listen_port;
    volatile int running;
} threading_context_t;

int threading_init(threading_context_t *ctx, obfuscator_config_t *config);
int threading_start(threading_context_t *ctx, obfuscator_config_t *config,
                    char *xor_key, int key_length, struct sockaddr_in *forward_addr,
                    in_addr_t listen_addr, uint16_t listen_port);
void threading_join(threading_context_t *ctx);
void threading_shutdown(threading_context_t *ctx);

#endif
