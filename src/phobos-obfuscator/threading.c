#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <pthread.h>
#include <errno.h>
#include <time.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <sched.h>
#include "threading.h"
#include "wg-obfuscator.h"
#include "obfuscation.h"
#include "masking.h"

#ifdef __linux__
#include <sys/epoll.h>
#ifndef EPOLLEXCLUSIVE
#define EPOLLEXCLUSIVE (1u << 28)
#endif
#endif

static client_entry_t *conn_table = NULL;
static pthread_rwlock_t table_lock = PTHREAD_RWLOCK_INITIALIZER;

typedef struct {
    int cpu;
    int sibling_index;
} cpu_slot_t;

static int read_long_file(const char *path, long *out) {
    FILE *f = fopen(path, "r");
    if (!f) return -1;
    long v;
    int r = fscanf(f, "%ld", &v);
    fclose(f);
    if (r != 1) return -1;
    *out = v;
    return 0;
}

static long read_cache_size(const char *path) {
    FILE *f = fopen(path, "r");
    if (!f) return 0;
    char buf[32];
    if (!fgets(buf, sizeof(buf), f)) {
        fclose(f);
        return 0;
    }
    fclose(f);
    long v = atol(buf);
    if (strchr(buf, 'M') || strchr(buf, 'm')) v *= 1024 * 1024;
    else if (strchr(buf, 'K') || strchr(buf, 'k')) v *= 1024;
    return v;
}

static long detect_cache_level(int want_level, int want_data) {
    char path[160], val[32];
    for (int i = 0; i < 10; i++) {
        long level = 0;
        snprintf(path, sizeof(path), "/sys/devices/system/cpu/cpu0/cache/index%d/level", i);
        if (read_long_file(path, &level) != 0) break;
        if (level != want_level) continue;
        snprintf(path, sizeof(path), "/sys/devices/system/cpu/cpu0/cache/index%d/type", i);
        FILE *f = fopen(path, "r");
        if (!f) continue;
        val[0] = 0;
        if (fgets(val, sizeof(val), f)) {}
        fclose(f);
        int is_data = (val[0] == 'D' || val[0] == 'U');
        if (want_data && !is_data) continue;
        snprintf(path, sizeof(path), "/sys/devices/system/cpu/cpu0/cache/index%d/size", i);
        long sz = read_cache_size(path);
        if (sz > 0) return sz;
    }
    return 0;
}

static int cgroup_cpu_limit(void) {
    long quota, period;
    FILE *f = fopen("/sys/fs/cgroup/cpu.max", "r");
    if (f) {
        char tok[32];
        if (fscanf(f, "%31s %ld", tok, &period) == 2) {
            fclose(f);
            if (strcmp(tok, "max") == 0 || period <= 0) return 0;
            quota = atol(tok);
            if (quota <= 0) return 0;
            int n = (int)((quota + period - 1) / period);
            return n > 0 ? n : 1;
        }
        fclose(f);
    }
    if (read_long_file("/sys/fs/cgroup/cpu/cpu.cfs_quota_us", &quota) == 0 &&
        read_long_file("/sys/fs/cgroup/cpu/cpu.cfs_period_us", &period) == 0) {
        if (quota <= 0 || period <= 0) return 0;
        int n = (int)((quota + period - 1) / period);
        return n > 0 ? n : 1;
    }
    return 0;
}

static long cpu_core_key(int cpu) {
    char path[128];
    long core = -1, pkg = 0;
    snprintf(path, sizeof(path), "/sys/devices/system/cpu/cpu%d/topology/core_id", cpu);
    read_long_file(path, &core);
    snprintf(path, sizeof(path), "/sys/devices/system/cpu/cpu%d/topology/physical_package_id", cpu);
    read_long_file(path, &pkg);
    if (core < 0) return ((long)cpu) | 0x40000000L;
    return (pkg << 16) | core;
}

static int detect_topology(int *order, int max) {
    cpu_set_t set;
    CPU_ZERO(&set);
    if (sched_getaffinity(0, sizeof(set), &set) != 0) {
        long n = sysconf(_SC_NPROCESSORS_ONLN);
        int count = n > 0 ? (int)n : 1;
        if (count > max) count = max;
        for (int i = 0; i < count; i++) order[i] = i;
        return count;
    }

    int avail[CPU_SETSIZE];
    int navail = 0;
    for (int c = 0; c < CPU_SETSIZE && navail < max; c++) {
        if (CPU_ISSET(c, &set)) avail[navail++] = c;
    }
    if (navail == 0) {
        order[0] = 0;
        return 1;
    }

    long keys[CPU_SETSIZE];
    cpu_slot_t slots[CPU_SETSIZE];
    for (int i = 0; i < navail; i++) {
        keys[i] = cpu_core_key(avail[i]);
        int sib = 0;
        for (int j = 0; j < i; j++) {
            if (keys[j] == keys[i]) sib++;
        }
        slots[i].cpu = avail[i];
        slots[i].sibling_index = sib;
    }

    int n = 0;
    int max_sib = 0;
    for (int i = 0; i < navail; i++) {
        if (slots[i].sibling_index > max_sib) max_sib = slots[i].sibling_index;
    }
    for (int s = 0; s <= max_sib; s++) {
        for (int i = 0; i < navail; i++) {
            if (slots[i].sibling_index == s) order[n++] = slots[i].cpu;
        }
    }
    return n;
}

static void pin_to_cpu(int cpu) {
    if (cpu < 0) return;
    cpu_set_t set;
    CPU_ZERO(&set);
    CPU_SET(cpu, &set);
    pthread_setaffinity_np(pthread_self(), sizeof(set), &set);
}

static long now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

static client_entry_t *table_find(struct sockaddr_in *addr) {
    client_entry_t *result;
    pthread_rwlock_rdlock(&table_lock);
    HASH_FIND(hh, conn_table, addr, sizeof(*addr), result);
    pthread_rwlock_unlock(&table_lock);
    return result;
}

static int worker_socket_opts(worker_ctx_t *w, int sock) {
#ifdef __linux__
    int pmtu = IP_PMTUDISC_DONT;
    setsockopt(sock, IPPROTO_IP, IP_MTU_DISCOVER, &pmtu, sizeof(pmtu));
    if (w->config->fwmark) {
        if (setsockopt(sock, SOL_SOCKET, SO_MARK, &w->config->fwmark, sizeof(w->config->fwmark)) < 0) {
            log(LL_WARN, "Failed to set 'firewall mark': %s", strerror(errno));
        }
    }
#endif
    int bufsize = 4 * 1024 * 1024;
    setsockopt(sock, SOL_SOCKET, SO_RCVBUF, &bufsize, sizeof(bufsize));
    setsockopt(sock, SOL_SOCKET, SO_SNDBUF, &bufsize, sizeof(bufsize));
    return 0;
}

static void epoll_add(int epfd, int fd, void *ptr) {
#ifdef __linux__
    struct epoll_event e;
    e.events = EPOLLIN | EPOLLEXCLUSIVE;
    e.data.ptr = ptr;
    if (epoll_ctl(epfd, EPOLL_CTL_ADD, fd, &e) != 0) {
        e.events = EPOLLIN;
        epoll_ctl(epfd, EPOLL_CTL_ADD, fd, &e);
    }
#else
    (void)epfd; (void)fd; (void)ptr;
#endif
}

static client_entry_t *make_client(worker_ctx_t *w, struct sockaddr_in *client_addr,
                                   int is_static, uint16_t local_port) {
    client_entry_t *entry = malloc(sizeof(client_entry_t));
    if (!entry) {
        log(LL_ERROR, "Failed to allocate memory for client entry");
        return NULL;
    }
    memset(entry, 0, sizeof(*entry));
    entry->version = OBFUSCATION_VERSION;
    memcpy(&entry->client_addr, client_addr, sizeof(entry->client_addr));
    entry->server_sock = socket(AF_INET, SOCK_DGRAM | SOCK_NONBLOCK, 0);
    if (entry->server_sock < 0) {
        serror("Failed to create server socket for client");
        free(entry);
        return NULL;
    }
    if (is_static) {
        entry->masking_handler = w->config->masking_handler;
        entry->our_addr.sin_family = AF_INET;
        entry->our_addr.sin_addr.s_addr = INADDR_ANY;
        entry->our_addr.sin_port = htons(local_port);
        if (bind(entry->server_sock, (struct sockaddr *)&entry->our_addr, sizeof(entry->our_addr)) < 0) {
            serror("Failed to bind static server socket to port %d", local_port);
            close(entry->server_sock);
            free(entry);
            return NULL;
        }
        entry->is_static = 1;
    }
    worker_socket_opts(w, entry->server_sock);
    connect(entry->server_sock, (struct sockaddr *)w->forward_addr, sizeof(*w->forward_addr));
    if (!is_static) {
        socklen_t alen = sizeof(entry->our_addr);
        getsockname(entry->server_sock, (struct sockaddr *)&entry->our_addr, &alen);
    }
    epoll_add(w->epfd, entry->server_sock, entry);
    HASH_ADD(hh, conn_table, client_addr, sizeof(entry->client_addr), entry);
    return entry;
}

static client_entry_t *worker_get_or_create(worker_ctx_t *w, struct sockaddr_in *sender, int allow_dynamic) {
    client_entry_t *entry;
    pthread_rwlock_wrlock(&table_lock);
    HASH_FIND(hh, conn_table, sender, sizeof(*sender), entry);
    if (entry) {
        pthread_rwlock_unlock(&table_lock);
        return entry;
    }
    if (HASH_COUNT(conn_table) >= (unsigned)w->config->max_clients) {
        pthread_rwlock_unlock(&table_lock);
        log(LL_ERROR, "Maximum number of clients reached (%d)", w->config->max_clients);
        return NULL;
    }
    for (int i = 0; i < w->config->static_spec_count; i++) {
        static_binding_t *s = &w->config->static_specs[i];
        if (s->client_ip.s_addr == sender->sin_addr.s_addr && htons(s->remote_port) == sender->sin_port) {
            entry = make_client(w, sender, 1, s->local_port);
            pthread_rwlock_unlock(&table_lock);
            if (entry) log(LL_INFO, "Activated static binding: %s:%d",
                           inet_ntoa(entry->client_addr.sin_addr), ntohs(entry->client_addr.sin_port));
            return entry;
        }
    }
    if (allow_dynamic) {
        entry = make_client(w, sender, 0, 0);
    }
    pthread_rwlock_unlock(&table_lock);
    return entry;
}

static int process_from_client(worker_ctx_t *w, uint8_t *buffer, int length,
                               struct sockaddr_in *sender, long now,
                               client_entry_t **client_out, uint8_t *frame, int *frame_len) {
    obfuscator_config_t *config = w->config;
    client_entry_t *client_entry = table_find(sender);
    if (!client_entry) {
        client_entry = worker_get_or_create(w, sender, 0);
    }

    uint8_t obfuscated = length >= 4 && is_obfuscated(buffer);
    masking_handler_t *masking_handler = config->masking_handler;
    if (obfuscated) {
        length = masking_unwrap_from_client(buffer, length, config, client_entry, w->listen_sock,
                                            sender, w->forward_addr, &masking_handler);
        if (length <= 0) return 0;
    }
    if (length < 4) return 0;

    uint8_t version = client_entry ? client_entry->version : OBFUSCATION_VERSION;

    if (obfuscated) {
        int original_length = length;
        length = decode(buffer, length, w->xor_key, w->key_length, &version, config->obfuscate_bytes);
        if (length < 4 || length > original_length) return 0;
    }

    uint32_t packet_type = WG_TYPE(buffer);

    if (packet_type == WG_TYPE_HANDSHAKE) {
        if (!client_entry) {
            client_entry = worker_get_or_create(w, sender, 1);
            if (!client_entry) return 0;
            client_entry->last_activity_time = now;
            client_entry->masking_handler = masking_handler;
        }
        if (!obfuscated) {
            masking_on_handshake_req_from_client(config, client_entry, w->listen_sock, sender, w->forward_addr);
        }
        client_entry->handshake_direction = DIR_CLIENT_TO_SERVER;
        client_entry->last_handshake_request_time = now;
    } else if (packet_type == WG_TYPE_HANDSHAKE_RESP) {
        if (!client_entry) return 0;
        if (now - client_entry->last_handshake_request_time > HANDSHAKE_TIMEOUT) return 0;
        if (client_entry->handshake_direction != DIR_SERVER_TO_CLIENT) return 0;
        client_entry->handshaked = 1;
        client_entry->client_obfuscated = obfuscated;
        client_entry->server_obfuscated = !obfuscated;
        client_entry->last_handshake_time = now;
    } else if (!client_entry || !client_entry->handshaked) {
        return 0;
    }

    if (version < client_entry->version) {
        client_entry->version = version;
    }

    *frame_len = 0;
    if (!obfuscated) {
        length = encode(buffer, length, w->xor_key, w->key_length, client_entry->version,
                        config->max_dummy_length_data, config->obfuscate_bytes);
        if (length < 4) return 0;
        *frame_len = masking_build_frame_to_server(frame, length, config, client_entry);
    }

    client_entry->last_activity_time = now;
    *client_out = client_entry;
    return length;
}

static int process_from_server(worker_ctx_t *w, client_entry_t *client_entry,
                               uint8_t *buffer, int length, long now,
                               uint8_t *frame, int *frame_len) {
    obfuscator_config_t *config = w->config;

    uint8_t obfuscated = length >= 4 && is_obfuscated(buffer);
    if (obfuscated) {
        length = masking_unwrap_from_server(buffer, length, config, client_entry, w->listen_sock, w->forward_addr);
        if (length <= 0) return 0;
    }
    if (length < 4) return 0;

    uint8_t version = client_entry->version;

    if (obfuscated) {
        int original_length = length;
        length = decode(buffer, length, w->xor_key, w->key_length, &version, config->obfuscate_bytes);
        if (length < 4 || length > original_length) return 0;
    }

    uint32_t packet_type = WG_TYPE(buffer);

    if (packet_type == WG_TYPE_HANDSHAKE) {
        if (!obfuscated) {
            masking_on_handshake_req_from_server(config, client_entry, w->listen_sock, &client_entry->client_addr, w->forward_addr);
        }
        client_entry->handshake_direction = DIR_SERVER_TO_CLIENT;
        client_entry->last_handshake_request_time = now;
    } else if (packet_type == WG_TYPE_HANDSHAKE_RESP) {
        if (now - client_entry->last_handshake_request_time > HANDSHAKE_TIMEOUT) return 0;
        if (client_entry->handshake_direction != DIR_CLIENT_TO_SERVER) return 0;
        if (!client_entry->handshaked && client_entry->masking_handler && !config->masking_handler_set) {
            log(LL_INFO, "Autodetected masking handler for client %s:%d: %s",
                inet_ntoa(client_entry->client_addr.sin_addr), ntohs(client_entry->client_addr.sin_port),
                client_entry->masking_handler->name);
        }
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

    *frame_len = 0;
    if (!obfuscated) {
        length = encode(buffer, length, w->xor_key, w->key_length, client_entry->version,
                        config->max_dummy_length_data, config->obfuscate_bytes);
        if (length < 4) return 0;
        *frame_len = masking_build_frame_to_client(frame, length, config, client_entry);
    }

    client_entry->last_activity_time = now;
    return length;
}

static void worker_cleanup(worker_ctx_t *w, long now) {
    pthread_rwlock_wrlock(&table_lock);
    client_entry_t *cur, *tmp;
    HASH_ITER(hh, conn_table, cur, tmp) {
        if (((now - cur->last_activity_time >= w->config->idle_timeout)
             || (!cur->handshaked && (now - cur->last_activity_time >= HANDSHAKE_TIMEOUT)))
            && !cur->is_static) {
            log(cur->handshaked ? LL_INFO : LL_DEBUG, "Removing idle client %s:%d",
                inet_ntoa(cur->client_addr.sin_addr), ntohs(cur->client_addr.sin_port));
#ifdef __linux__
            epoll_ctl(w->epfd, EPOLL_CTL_DEL, cur->server_sock, NULL);
#endif
            close(cur->server_sock);
            HASH_DEL(conn_table, cur);
            free(cur);
            continue;
        }
        if (cur->masking_handler && cur->masking_handler->timer_interval_s > 0
            && now - cur->last_masking_timer_time >= cur->masking_handler->timer_interval_s * 1000) {
            cur->last_masking_timer_time = now;
            masking_on_timer(w->config, cur, w->listen_sock, w->forward_addr);
        }
    }
    pthread_rwlock_unlock(&table_lock);
}

#ifdef __linux__

static void worker_run(worker_ctx_t *w) {
    pin_to_cpu(w->cpu);

    struct epoll_event events[64];
    struct mmsghdr rxh[RX_BATCH];
    struct iovec rxi[RX_BATCH];
    struct sockaddr_in rxa[RX_BATCH];
    static _Thread_local uint8_t rxb[RX_BATCH][WORKER_BUF_SIZE];
    struct mmsghdr txh[RX_BATCH];
    struct iovec txi[RX_BATCH][2];
    static _Thread_local uint8_t txf[RX_BATCH][WORKER_FRAME_MAX];

    while (w->running) {
        int n = epoll_wait(w->epfd, events, 64, 1000);
        long now = now_ms();

        for (int e = 0; e < n; e++) {
            client_entry_t *src_client = events[e].data.ptr;

            if (src_client == NULL) {
                for (int i = 0; i < RX_BATCH; i++) {
                    rxi[i].iov_base = rxb[i];
                    rxi[i].iov_len = WORKER_BUF_SIZE;
                    memset(&rxh[i].msg_hdr, 0, sizeof(rxh[i].msg_hdr));
                    rxh[i].msg_hdr.msg_name = &rxa[i];
                    rxh[i].msg_hdr.msg_namelen = sizeof(rxa[i]);
                    rxh[i].msg_hdr.msg_iov = &rxi[i];
                    rxh[i].msg_hdr.msg_iovlen = 1;
                }
                int rxn = recvmmsg(w->listen_sock, rxh, RX_BATCH, MSG_DONTWAIT | MSG_TRUNC, NULL);
                if (rxn <= 0) continue;

                int txn = 0;
                int txfd = -1;
                for (int b = 0; b < rxn; b++) {
                    int len = rxh[b].msg_len;
                    if (len < 1 || len > WORKER_BUF_SIZE) continue;
                    client_entry_t *client = NULL;
                    int frame_len = 0;
                    int out = process_from_client(w, rxb[b], len, &rxa[b], now, &client, txf[txn], &frame_len);
                    if (out <= 0 || !client) continue;

                    if (txn > 0 && txfd != client->server_sock) {
                        sendmmsg(txfd, txh, txn, MSG_DONTWAIT);
                        txn = 0;
                    }
                    txfd = client->server_sock;
                    memset(&txh[txn].msg_hdr, 0, sizeof(txh[txn].msg_hdr));
                    if (frame_len > 0) {
                        txi[txn][0].iov_base = txf[txn];
                        txi[txn][0].iov_len = frame_len;
                        txi[txn][1].iov_base = rxb[b];
                        txi[txn][1].iov_len = out;
                        txh[txn].msg_hdr.msg_iov = txi[txn];
                        txh[txn].msg_hdr.msg_iovlen = 2;
                    } else {
                        txi[txn][0].iov_base = rxb[b];
                        txi[txn][0].iov_len = out;
                        txh[txn].msg_hdr.msg_iov = txi[txn];
                        txh[txn].msg_hdr.msg_iovlen = 1;
                    }
                    txn++;
                }
                if (txn > 0) sendmmsg(txfd, txh, txn, MSG_DONTWAIT);
                continue;
            }

            for (int i = 0; i < RX_BATCH; i++) {
                rxi[i].iov_base = rxb[i];
                rxi[i].iov_len = WORKER_BUF_SIZE;
                memset(&rxh[i].msg_hdr, 0, sizeof(rxh[i].msg_hdr));
                rxh[i].msg_hdr.msg_iov = &rxi[i];
                rxh[i].msg_hdr.msg_iovlen = 1;
            }
            int rxn = recvmmsg(src_client->server_sock, rxh, RX_BATCH, MSG_DONTWAIT | MSG_TRUNC, NULL);
            if (rxn <= 0) continue;

            int txn = 0;
            for (int b = 0; b < rxn; b++) {
                int len = rxh[b].msg_len;
                if (len < 1 || len > WORKER_BUF_SIZE) continue;
                int frame_len = 0;
                int out = process_from_server(w, src_client, rxb[b], len, now, txf[txn], &frame_len);
                if (out <= 0) continue;

                memset(&txh[txn].msg_hdr, 0, sizeof(txh[txn].msg_hdr));
                txh[txn].msg_hdr.msg_name = &src_client->client_addr;
                txh[txn].msg_hdr.msg_namelen = sizeof(src_client->client_addr);
                if (frame_len > 0) {
                    txi[txn][0].iov_base = txf[txn];
                    txi[txn][0].iov_len = frame_len;
                    txi[txn][1].iov_base = rxb[b];
                    txi[txn][1].iov_len = out;
                    txh[txn].msg_hdr.msg_iov = txi[txn];
                    txh[txn].msg_hdr.msg_iovlen = 2;
                } else {
                    txi[txn][0].iov_base = rxb[b];
                    txi[txn][0].iov_len = out;
                    txh[txn].msg_hdr.msg_iov = txi[txn];
                    txh[txn].msg_hdr.msg_iovlen = 1;
                }
                txn++;
            }
            if (txn > 0) sendmmsg(w->listen_sock, txh, txn, MSG_DONTWAIT);
        }

        if (w->is_maintainer && now - w->last_cleanup_time >= ITERATE_INTERVAL) {
            worker_cleanup(w, now);
            w->last_cleanup_time = now;
        }
    }
}

#else

static void worker_run(worker_ctx_t *w) {
    pin_to_cpu(w->cpu);
    uint8_t buf[WORKER_BUF_SIZE];
    uint8_t frame[WORKER_FRAME_MAX];
    while (w->running) {
        struct sockaddr_in sender;
        socklen_t slen = sizeof(sender);
        int len = recvfrom(w->listen_sock, buf, sizeof(buf), 0, (struct sockaddr *)&sender, &slen);
        long now = now_ms();
        if (len > 0) {
            client_entry_t *client = NULL;
            int frame_len = 0;
            int out = process_from_client(w, buf, len, &sender, now, &client, frame, &frame_len);
            if (out > 0 && client) {
                if (frame_len > 0) {
                    uint8_t pkt[WORKER_BUF_SIZE + WORKER_FRAME_MAX];
                    memcpy(pkt, frame, frame_len);
                    memcpy(pkt + frame_len, buf, out);
                    send(client->server_sock, pkt, frame_len + out, MSG_DONTWAIT);
                } else {
                    send(client->server_sock, buf, out, MSG_DONTWAIT);
                }
            }
        }
        if (w->is_maintainer && now - w->last_cleanup_time >= ITERATE_INTERVAL) {
            worker_cleanup(w, now);
            w->last_cleanup_time = now;
        }
    }
}

#endif

static void *worker_main(void *arg) {
    worker_ctx_t *w = (worker_ctx_t *)arg;
    log(LL_DEBUG, "Worker #%d started (cpu %d)", w->worker_index, w->cpu);
    worker_run(w);
    log(LL_DEBUG, "Worker #%d stopped", w->worker_index);
    return NULL;
}

int threading_init(threading_context_t *ctx, obfuscator_config_t *config) {
    memset(ctx, 0, sizeof(*ctx));

    int order[MAX_WORKER_THREADS];
    int navail = detect_topology(order, MAX_WORKER_THREADS);

    int limit = cgroup_cpu_limit();
    if (limit > 0 && limit < navail) navail = limit;

    int n = config->threads > 0 ? config->threads : navail;
    if (n > navail && config->threads <= 0) n = navail;
    if (n < 1) n = 1;
    if (n > MAX_WORKER_THREADS) n = MAX_WORKER_THREADS;

    ctx->num_workers = n;
    for (int i = 0; i < n; i++) {
        ctx->workers[i].worker_index = i;
        ctx->workers[i].cpu = (i < navail) ? order[i] : -1;
        ctx->workers[i].is_maintainer = (i == 0);
    }

    long l1d = detect_cache_level(1, 1);
    long l2 = detect_cache_level(2, 0);
    if (l1d > 0) {
        int cap = (int)((l1d / 2) / (long)sizeof(xor_cache_entry_t));
        xor_set_cache_cap(cap);
    }
    log(LL_INFO, "CPU: %d worker(s), L1d=%ldKB L2=%ldKB, xor-cache=%d entries",
        n, l1d / 1024, l2 / 1024, xor_get_cache_cap());

    return 0;
}

static int open_listen_socket(threading_context_t *ctx, obfuscator_config_t *config) {
    int sock = socket(AF_INET, SOCK_DGRAM | SOCK_NONBLOCK, 0);
    if (sock < 0) {
        serror("Can't create listen socket");
        return -1;
    }
    int one = 1;
    setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
#ifdef __linux__
    int pmtu = IP_PMTUDISC_DONT;
    setsockopt(sock, IPPROTO_IP, IP_MTU_DISCOVER, &pmtu, sizeof(pmtu));
    if (config->fwmark) {
        setsockopt(sock, SOL_SOCKET, SO_MARK, &config->fwmark, sizeof(config->fwmark));
    }
#endif
    int bufsize = 4 * 1024 * 1024;
    setsockopt(sock, SOL_SOCKET, SO_RCVBUF, &bufsize, sizeof(bufsize));
    setsockopt(sock, SOL_SOCKET, SO_SNDBUF, &bufsize, sizeof(bufsize));

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = ctx->listen_addr;
    addr.sin_port = htons(ctx->listen_port);
    if (bind(sock, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        serror("Failed to bind listen socket to %s:%d", inet_ntoa(addr.sin_addr), ctx->listen_port);
        close(sock);
        return -1;
    }
    return sock;
}

int threading_start(threading_context_t *ctx, obfuscator_config_t *config,
                    char *xor_key, int key_length, struct sockaddr_in *forward_addr,
                    in_addr_t listen_addr, uint16_t listen_port) {
    ctx->listen_addr = listen_addr;
    ctx->listen_port = listen_port;
    ctx->running = 1;

    ctx->listen_sock = open_listen_socket(ctx, config);
    if (ctx->listen_sock < 0) return -1;

#ifdef __linux__
    ctx->epfd = epoll_create1(0);
    if (ctx->epfd < 0) {
        serror("epoll_create1");
        return -1;
    }
    epoll_add(ctx->epfd, ctx->listen_sock, NULL);
#endif

    for (int i = 0; i < ctx->num_workers; i++) {
        worker_ctx_t *w = &ctx->workers[i];
        w->config = config;
        w->xor_key = xor_key;
        w->key_length = key_length;
        w->forward_addr = forward_addr;
        w->listen_sock = ctx->listen_sock;
        w->epfd = ctx->epfd;
        w->running = 1;
        w->last_cleanup_time = 0;
        if (pthread_create(&w->thread_id, NULL, worker_main, w) != 0) {
            log(LL_ERROR, "Failed to create worker #%d: %s", i, strerror(errno));
            return -1;
        }
    }
    log(LL_INFO, "Started %d worker thread(s)", ctx->num_workers);
    return 0;
}

void threading_join(threading_context_t *ctx) {
    for (int i = 0; i < ctx->num_workers; i++) {
        if (ctx->workers[i].thread_id) {
            pthread_join(ctx->workers[i].thread_id, NULL);
        }
    }
}

void threading_shutdown(threading_context_t *ctx) {
    ctx->running = 0;
    for (int i = 0; i < ctx->num_workers; i++) {
        ctx->workers[i].running = 0;
    }
}
