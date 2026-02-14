#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <pthread.h>
#include <errno.h>
#include <sys/socket.h>
#include <sched.h>
#include "threading.h"
#include "wg-obfuscator.h"
#include "obfuscation.h"
#include "masking.h"

extern client_entry_t *conn_table;

int detect_cpu_cores(void) {
#ifdef _SC_NPROCESSORS_ONLN
    long cores = sysconf(_SC_NPROCESSORS_ONLN);
    if (cores > 0) return (int)cores;
#endif
    return 1;
}

static void queue_init(packet_queue_t *queue) {
    queue->head = 0;
    queue->tail = 0;
    queue->shutdown = 0;
}

static void process_packet_from_client(packet_job_t *job, obfuscator_config_t *config,
                                       char *xor_key, int key_length, int listen_sock,
                                       struct sockaddr_in *forward_addr) {
    uint8_t *buffer = job->buffer;
    int length = job->length;
    struct sockaddr_in *sender_addr = &job->addr;
    long now = job->timestamp_ms;

    client_entry_t *client_entry = find_client_safe(sender_addr);

    uint8_t obfuscated = length >= 4 && is_obfuscated(buffer);
    masking_handler_t *masking_handler = config->masking_handler;

    if (obfuscated) {
        length = masking_unwrap_from_client(buffer, length, config, client_entry,
                                           listen_sock, sender_addr, forward_addr, &masking_handler);
        if (length <= 0) return;
    }

    if (length < 4) return;

    uint8_t version = client_entry ? client_entry->version : OBFUSCATION_VERSION;

    if (obfuscated) {
        int original_length = length;
        length = decode(buffer, length, xor_key, key_length, &version);
        if (length < 4 || length > original_length) return;
    }

    uint32_t packet_type = WG_TYPE(buffer);

    if (packet_type == WG_TYPE_HANDSHAKE) {
        if (!client_entry) {
            client_entry = new_client_entry(config, sender_addr, forward_addr);
            if (!client_entry) return;
            client_entry->last_activity_time = now;
            client_entry->masking_handler = masking_handler;
        }
        if (!obfuscated) {
            masking_on_handshake_req_from_client(config, client_entry, listen_sock, sender_addr, forward_addr);
        }
        client_entry->handshake_direction = DIR_CLIENT_TO_SERVER;
        client_entry->last_handshake_request_time = now;
    } else if (packet_type == WG_TYPE_HANDSHAKE_RESP) {
        if (!client_entry) return;
        if (now - client_entry->last_handshake_request_time > HANDSHAKE_TIMEOUT) return;
        if (client_entry->handshake_direction != DIR_SERVER_TO_CLIENT) return;
        client_entry->handshaked = 1;
        client_entry->client_obfuscated = obfuscated;
        client_entry->server_obfuscated = !obfuscated;
        client_entry->last_handshake_time = now;
    } else if (!client_entry || !client_entry->handshaked) {
        return;
    }

    if (version < client_entry->version) {
        client_entry->version = version;
    }

    if (!obfuscated && client_entry) {
        length = encode(buffer, length, xor_key, key_length, client_entry->version,
                       config->max_dummy_length_data);
        if (length < 4) return;
        length = masking_data_wrap_to_server(buffer, length, config, client_entry, listen_sock, forward_addr);
    }

    if (client_entry) {
        while (client_entry->pending_head != client_entry->pending_tail) {
            pending_packet_t *pp = &client_entry->pending_sends[client_entry->pending_tail % PENDING_SEND_SIZE];
            ssize_t r = send(client_entry->server_sock, pp->data, pp->length, MSG_DONTWAIT);
            if (r < 0 && (errno == EAGAIN || errno == EWOULDBLOCK))
                break;
            client_entry->pending_tail++;
        }

        ssize_t r = send(client_entry->server_sock, buffer, length, MSG_DONTWAIT);
        if (r < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
            int pending_count = client_entry->pending_head - client_entry->pending_tail;
            if (pending_count < PENDING_SEND_SIZE) {
                pending_packet_t *pp = &client_entry->pending_sends[client_entry->pending_head % PENDING_SEND_SIZE];
                memcpy(pp->data, buffer, length);
                pp->length = length;
                client_entry->pending_head++;
            }
        }
        client_entry->last_activity_time = now;
    }
}

static int process_packet_from_server(packet_job_t *job, obfuscator_config_t *config,
                                      char *xor_key, int key_length, int listen_sock,
                                      struct sockaddr_in *forward_addr) {
    uint8_t *buffer = job->buffer;
    int length = job->length;
    client_entry_t *client_entry = job->client;

    if (!client_entry) return 0;

    long now = job->timestamp_ms;

    uint8_t obfuscated = length >= 4 && is_obfuscated(buffer);

    if (obfuscated) {
        length = masking_unwrap_from_server(buffer, length, config, client_entry, listen_sock, forward_addr);
        if (length <= 0) return 0;
    }

    if (length < 4) return 0;

    uint8_t version = client_entry->version;

    if (obfuscated) {
        int original_length = length;
        length = decode(buffer, length, xor_key, key_length, &version);
        if (length < 4 || length > original_length) return 0;
    }

    uint32_t packet_type = WG_TYPE(buffer);

    if (packet_type == WG_TYPE_HANDSHAKE) {
        if (!obfuscated) {
            masking_on_handshake_req_from_server(config, client_entry, listen_sock, &client_entry->client_addr, forward_addr);
        }
        client_entry->handshake_direction = DIR_SERVER_TO_CLIENT;
        client_entry->last_handshake_request_time = now;
    } else if (packet_type == WG_TYPE_HANDSHAKE_RESP) {
        if (now - client_entry->last_handshake_request_time > HANDSHAKE_TIMEOUT) return 0;
        if (client_entry->handshake_direction != DIR_CLIENT_TO_SERVER) return 0;
        client_entry->handshaked = 1;
        client_entry->client_obfuscated = !obfuscated;
        client_entry->server_obfuscated = obfuscated;
        client_entry->last_handshake_time = now;
    } else if (!client_entry->handshaked) {
        return 0;
    }

    if (version < client_entry->version) {
        client_entry->version = version;
    }

    if (!obfuscated) {
        length = encode(buffer, length, xor_key, key_length, client_entry->version,
                       config->max_dummy_length_data);
        if (length < 4) return 0;
        length = masking_data_wrap_to_client(buffer, length, config, client_entry, listen_sock, forward_addr);
    }

    client_entry->last_activity_time = now;
    job->length = length;
    return length;
}

#if defined(__linux__)
#define SEND_BATCH 16

static void *worker_thread_server_func(void *arg) {
    worker_thread_t *worker = (worker_thread_t *)arg;
    int idle_count = 0;
    struct mmsghdr send_hdrs[SEND_BATCH];
    struct iovec send_iovs[SEND_BATCH];

    log(LL_DEBUG, "Worker thread #%d started (sendmmsg)", worker->worker_index);

    while (worker->running) {
        int batch_count = 0;

        while (batch_count < SEND_BATCH) {
            packet_job_t *job = queue_peek(worker->queue);
            if (!job) break;

            uint32_t next_t = (worker->queue->tail + 1) & QUEUE_MASK;
            __builtin_prefetch(&worker->queue->jobs[next_t], 0, 1);

            int result = process_packet_from_server(job, worker->config, worker->xor_key,
                                                    worker->key_length, worker->listen_sock,
                                                    worker->forward_addr);
            if (result > 0 && job->client) {
                int idx = batch_count;
                send_iovs[idx].iov_base = job->buffer;
                send_iovs[idx].iov_len = job->length;
                send_hdrs[idx].msg_hdr.msg_name = &job->client->client_addr;
                send_hdrs[idx].msg_hdr.msg_namelen = sizeof(job->client->client_addr);
                send_hdrs[idx].msg_hdr.msg_iov = &send_iovs[idx];
                send_hdrs[idx].msg_hdr.msg_iovlen = 1;
                send_hdrs[idx].msg_hdr.msg_control = NULL;
                send_hdrs[idx].msg_hdr.msg_controllen = 0;
                send_hdrs[idx].msg_hdr.msg_flags = 0;
                batch_count++;
            }
            queue_consume(worker->queue);
        }

        if (batch_count > 0) {
            sendmmsg(worker->listen_sock, send_hdrs, batch_count, MSG_DONTWAIT);
            idle_count = 0;
        } else {
            if (__atomic_load_n(&worker->queue->shutdown, __ATOMIC_RELAXED))
                break;
            if (++idle_count > 256) {
                usleep(100);
                idle_count = 256;
            } else {
                sched_yield();
            }
        }
    }

    log(LL_DEBUG, "Worker thread #%d stopped", worker->worker_index);
    return NULL;
}
#endif

static void *worker_thread_func(void *arg) {
    worker_thread_t *worker = (worker_thread_t *)arg;
    int idle_count = 0;

    log(LL_DEBUG, "Worker thread #%d started", worker->worker_index);

    while (worker->running) {
        packet_job_t *job = queue_peek(worker->queue);
        if (!job) {
            if (__atomic_load_n(&worker->queue->shutdown, __ATOMIC_RELAXED))
                break;
            if (++idle_count > 256) {
                usleep(100);
                idle_count = 256;
            } else {
                sched_yield();
            }
            continue;
        }
        idle_count = 0;

        uint32_t next_tail = (worker->queue->tail + 1) & QUEUE_MASK;
        __builtin_prefetch(&worker->queue->jobs[next_tail], 0, 1);

        if (job->is_from_client) {
            process_packet_from_client(job, worker->config, worker->xor_key,
                                      worker->key_length, worker->listen_sock,
                                      worker->forward_addr);
        } else {
            int result = process_packet_from_server(job, worker->config, worker->xor_key,
                                                    worker->key_length, worker->listen_sock,
                                                    worker->forward_addr);
            if (result > 0 && job->client) {
                sendto(worker->listen_sock, job->buffer, job->length, MSG_DONTWAIT,
                       (struct sockaddr *)&job->client->client_addr,
                       sizeof(job->client->client_addr));
            }
        }
        queue_consume(worker->queue);
    }

    log(LL_DEBUG, "Worker thread #%d stopped", worker->worker_index);
    return NULL;
}

int threading_init(threading_context_t *ctx, obfuscator_config_t *config) {
    memset(ctx, 0, sizeof(threading_context_t));

    ctx->num_cores = detect_cpu_cores();
    log(LL_INFO, "Detected %d logical CPU(s)", ctx->num_cores);

    if (ctx->num_cores <= 1) {
        log(LL_INFO, "Using single-threaded mode");
        ctx->mode = THREAD_MODE_SINGLE;
        ctx->num_workers = 0;
    } else if (ctx->num_cores <= 4) {
        log(LL_INFO, "Using dual-threaded mode (1 main + 2 workers)");
        ctx->mode = THREAD_MODE_DUAL;
        ctx->num_workers = 2;
    } else {
        log(LL_INFO, "Using multi-threaded mode (1 main + 2 workers)");
        ctx->mode = THREAD_MODE_MULTI;
        ctx->num_workers = 2;
    }

    if (ctx->mode != THREAD_MODE_SINGLE) {
        queue_init(&ctx->client_queue);
        queue_init(&ctx->server_queue);
    }

    return 0;
}

int threading_start(threading_context_t *ctx, int listen_sock, obfuscator_config_t *config,
                    char *xor_key, int key_length, struct sockaddr_in *forward_addr) {
    if (ctx->mode == THREAD_MODE_SINGLE) return 0;

    ctx->running = 1;

    packet_queue_t *queues[2] = { &ctx->client_queue, &ctx->server_queue };

    for (int i = 0; i < ctx->num_workers; i++) {
        worker_thread_t *worker = &ctx->workers[i];
        worker->worker_index = i;
        worker->queue = queues[i];
        worker->listen_sock = listen_sock;
        worker->config = config;
        worker->xor_key = xor_key;
        worker->key_length = key_length;
        worker->forward_addr = forward_addr;
        worker->running = 1;

        void *(*thread_func)(void *) = worker_thread_func;
#if defined(__linux__)
        if (i == 1)
            thread_func = worker_thread_server_func;
#endif
        if (pthread_create(&worker->thread_id, NULL, thread_func, worker) != 0) {
            log(LL_ERROR, "Failed to create worker thread #%d: %s", i, strerror(errno));
            return -1;
        }
    }

    log(LL_INFO, "Started %d worker thread(s)", ctx->num_workers);
    return 0;
}

void threading_shutdown(threading_context_t *ctx) {
    if (ctx->mode == THREAD_MODE_SINGLE) return;

    log(LL_INFO, "Shutting down threading system...");

    ctx->running = 0;

    __atomic_store_n(&ctx->client_queue.shutdown, 1, __ATOMIC_RELEASE);
    __atomic_store_n(&ctx->server_queue.shutdown, 1, __ATOMIC_RELEASE);

    for (int i = 0; i < ctx->num_workers; i++) {
        worker_thread_t *worker = &ctx->workers[i];
        worker->running = 0;

        if (worker->thread_id) {
            pthread_join(worker->thread_id, NULL);
            log(LL_DEBUG, "Worker thread #%d joined", i);
        }
    }

    log(LL_INFO, "Threading system shut down");
}
