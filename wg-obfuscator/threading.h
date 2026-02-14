#ifndef _THREADING_H_
#define _THREADING_H_

#include <stdint.h>
#include <pthread.h>
#include <sched.h>
#include "wg-obfuscator.h"

#define QUEUE_SIZE 4096
#define QUEUE_MASK (QUEUE_SIZE - 1)
#define QUEUE_BUFFER_SIZE 2048
#define MAX_WORKER_THREADS 16

typedef enum {
    THREAD_MODE_SINGLE = 0,
    THREAD_MODE_DUAL = 1,
    THREAD_MODE_MULTI = 2
} thread_mode_t;

typedef struct {
    uint8_t buffer[QUEUE_BUFFER_SIZE];
    int length;
    struct sockaddr_in addr;
    socklen_t addr_len;
    int is_from_client;
    client_entry_t *client;
    long timestamp_ms;
} packet_job_t;

typedef struct {
    volatile uint32_t head;
    volatile uint32_t tail;
    volatile int shutdown;
    packet_job_t jobs[QUEUE_SIZE];
} packet_queue_t;

typedef struct {
    pthread_t thread_id;
    int worker_index;
    packet_queue_t *queue;
    int listen_sock;
    obfuscator_config_t *config;
    char *xor_key;
    int key_length;
    struct sockaddr_in *forward_addr;
    volatile int running;
} worker_thread_t;

typedef struct {
    thread_mode_t mode;
    int num_cores;
    int num_workers;
    worker_thread_t workers[MAX_WORKER_THREADS];
    packet_queue_t client_queue;
    packet_queue_t server_queue;
    volatile int running;
} threading_context_t;

int detect_cpu_cores(void);
int threading_init(threading_context_t *ctx, obfuscator_config_t *config);
int threading_start(threading_context_t *ctx, int listen_sock, obfuscator_config_t *config,
                    char *xor_key, int key_length, struct sockaddr_in *forward_addr);
void threading_shutdown(threading_context_t *ctx);

static inline packet_job_t *queue_reserve(packet_queue_t *queue) {
    uint32_t head = queue->head;
    uint32_t next = (head + 1) & QUEUE_MASK;
    if (next == __atomic_load_n(&queue->tail, __ATOMIC_ACQUIRE))
        return NULL;
    return &queue->jobs[head];
}

static inline void queue_publish(packet_queue_t *queue) {
    __atomic_store_n(&queue->head, (queue->head + 1) & QUEUE_MASK, __ATOMIC_RELEASE);
}

static inline packet_job_t *queue_peek(packet_queue_t *queue) {
    uint32_t tail = queue->tail;
    if (tail == __atomic_load_n(&queue->head, __ATOMIC_ACQUIRE))
        return NULL;
    return &queue->jobs[tail];
}

static inline void queue_consume(packet_queue_t *queue) {
    __atomic_store_n(&queue->tail, (queue->tail + 1) & QUEUE_MASK, __ATOMIC_RELEASE);
}

#endif
