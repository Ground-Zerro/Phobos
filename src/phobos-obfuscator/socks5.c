#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <pthread.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <arpa/inet.h>
#include "socks5.h"
#include "wg-obfuscator.h"
#include "obfuscation.h"
#include "runtime.h"
#include "socks5_mask.h"
#include "socks5_proto.h"
#include "resolve.h"
#include "config.h"

#define S5_PRECLASS 64

#define SOCKS5_BUF          16384
#define SOCKS5_BACKLOG      1024
#define SOCKS5_EPOLL_EVENTS 64

static volatile unsigned int socks5_client_count = 0;

#define TAG_LISTEN 0
#define TAG_DOWN   1
#define TAG_UP     2
#define TAG_UDP    3

typedef struct { uint8_t kind; struct socks5_conn *conn; } sock_tag_t;

typedef struct socks5_conn {
    int down_fd;
    int up_fd;
    sock_tag_t down_tag;
    sock_tag_t up_tag;
    stream_cipher_t c2s;
    stream_cipher_t s2c;
    uint8_t to_up[SOCKS5_BUF];
    int to_up_len;
    int to_up_off;
    uint8_t to_down[SOCKS5_BUF];
    int to_down_len;
    int to_down_off;
    uint8_t down_rd_closed;
    uint8_t up_rd_closed;
    uint8_t up_connecting;
    uint8_t mask_type;
    uint8_t classified;
    uint8_t down_is_raw;
    uint8_t dead;
    uint8_t role;
    uint8_t phase;
    uint8_t hstate;
    s5_enc_t enc;
    s5_dec_t dec;
    uint8_t preclass[S5_PRECLASS];
    int preclass_len;
    uint8_t hs[600];
    int hs_len;
    uint8_t hs_up[600];
    int hs_up_len;
    int udp_fd;
    sock_tag_t udp_tag;
    struct sockaddr_in app_udp_addr;
    uint8_t app_udp_known;
    uint8_t udp_acc[2048];
    int udp_acc_len;
    long last_activity;
    int user_index;
    struct socks5_conn *next;
    struct socks5_conn *prev;
} socks5_conn_t;

typedef struct {
    uint64_t up_bytes;
    uint64_t down_bytes;
    uint32_t conns;
    long last_activity;
} s5_user_stats_t;

static s5_user_stats_t s5_user_stats[MAX_SOCKS5_USERS];

static void s5_stats_traffic(socks5_conn_t *c, int up, int bytes) {
    if (c->user_index < 0 || bytes <= 0) return;
    s5_user_stats_t *s = &s5_user_stats[c->user_index];
    __atomic_fetch_add(up ? &s->up_bytes : &s->down_bytes, (uint64_t)bytes, __ATOMIC_RELAXED);
    __atomic_store_n(&s->last_activity, now_ms(), __ATOMIC_RELAXED);
}

#define S5_PHASE_HS    0
#define S5_PHASE_RELAY 1
#define S5_PHASE_UDP   2

// role=client handshake states: role=client never terminates the real SOCKS5
// protocol itself -- it transparently relays the greeting/method-select/
// RFC1929/CONNECT exchange between the local application and role=server,
// which is the real endpoint. The only state that isn't pure passthrough is
// CHS_UDP_REPLY, where the local UDP relay socket's bind address must be
// substituted for the server's.
#define CHS_GREETING       0
#define CHS_METHOD_REPLY   1
#define CHS_USERPASS       2
#define CHS_USERPASS_REPLY 3
#define CHS_REQUEST        4
#define CHS_UDP_REPLY      5

// role=server handshake states: role=server is a real SOCKS5 server,
// including real RFC1929 username/password validation against
// config->socks5_users.
#define SHS_GREETING 0
#define SHS_USERPASS 1
#define SHS_REQUEST  2

struct socks5_worker;
static int client_udp_setup(struct socks5_worker *w, struct socks5_conn *c, const obfuscator_config_t *config);
static int server_udp_setup(struct socks5_worker *w, struct socks5_conn *c, const obfuscator_config_t *config, const uint8_t *rest, int rest_len);
static int udp_relay_event(struct socks5_worker *w, struct socks5_conn *c, const obfuscator_config_t *config);
static int udp_control_event(struct socks5_worker *w, struct socks5_conn *c, const obfuscator_config_t *config, uint32_t events);
static int udp_deliver_frames(struct socks5_conn *c,
                              const uint8_t *raw_in, int in_len, int is_client);
static int push_down(socks5_conn_t *c, const obfuscator_config_t *config, const uint8_t *raw, int rawn);

static socks5_socket_protect_cb s5_protect_cb = NULL;

void socks5_set_socket_protect(socks5_socket_protect_cb cb) {
    s5_protect_cb = cb;
}

#ifdef __linux__
#include <sys/epoll.h>
#ifndef EPOLLEXCLUSIVE
#define EPOLLEXCLUSIVE (1u << 28)
#endif

static void tune_socket(int fd, obfuscator_config_t *config) {
    (void)config;
    int one = 1;
    setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one));
}

static void mark_exit_socket(int fd, const obfuscator_config_t *config) {
    if (config->socks5_role == S5_ROLE_SERVER && config->fwmark) {
        setsockopt(fd, SOL_SOCKET, SO_MARK, &config->fwmark, sizeof(config->fwmark));
    }
    if (s5_protect_cb) {
        s5_protect_cb(fd);
    }
}

static void epoll_set(int epfd, int fd, uint32_t events, void *tag) {
    struct epoll_event e;
    e.events = events;
    e.data.ptr = tag;
    epoll_ctl(epfd, EPOLL_CTL_MOD, fd, &e);
}

static uint32_t wants_down(const socks5_conn_t *c) {
    uint32_t ev = 0;
    if (!c->down_rd_closed && c->to_up_len == 0) ev |= EPOLLIN;
    if (c->to_down_off < c->to_down_len) ev |= EPOLLOUT;
    return ev;
}

static uint32_t wants_up(const socks5_conn_t *c) {
    uint32_t ev = 0;
    if (!c->up_connecting && !c->up_rd_closed && c->to_down_len == 0) ev |= EPOLLIN;
    if (c->up_connecting || c->to_up_off < c->to_up_len) ev |= EPOLLOUT;
    return ev;
}

static void refresh_epoll(socks5_worker_t *w, socks5_conn_t *c) {
    epoll_set(w->epfd, c->down_fd, wants_down(c), &c->down_tag);
    if (c->up_fd >= 0) epoll_set(w->epfd, c->up_fd, wants_up(c), &c->up_tag);
}

static void conn_detach(socks5_worker_t *w, socks5_conn_t *c) {
    epoll_ctl(w->epfd, EPOLL_CTL_DEL, c->down_fd, NULL);
    close(c->down_fd);
    if (c->up_fd >= 0) {
        epoll_ctl(w->epfd, EPOLL_CTL_DEL, c->up_fd, NULL);
        close(c->up_fd);
        c->up_fd = -1;
    }
    if (c->udp_fd > 0) {
        epoll_ctl(w->epfd, EPOLL_CTL_DEL, c->udp_fd, NULL);
        close(c->udp_fd);
        c->udp_fd = -1;
    }
    if (c->prev) c->prev->next = c->next; else w->conns = c->next;
    if (c->next) c->next->prev = c->prev;
    if (c->user_index >= 0) {
        s5_user_stats_t *s = &s5_user_stats[c->user_index];
        __atomic_fetch_sub(&s->conns, 1, __ATOMIC_RELAXED);
        __atomic_store_n(&s->last_activity, now_ms(), __ATOMIC_RELAXED);
    }
    __atomic_fetch_sub(&socks5_client_count, 1, __ATOMIC_RELAXED);
}

static void conn_free(socks5_worker_t *w, socks5_conn_t *c) {
    conn_detach(w, c);
    free(c);
}

static void conn_close(socks5_worker_t *w, socks5_conn_t *c) {
    if (c->dead) return;
    conn_detach(w, c);
    c->dead = 1;
    c->next = w->dead;
    w->dead = c;
}

static int conn_finished(const socks5_conn_t *c) {
    return c->down_rd_closed && c->up_rd_closed
        && c->to_up_off >= c->to_up_len && c->to_down_off >= c->to_down_len;
}

static int flush_to_up(socks5_conn_t *c) {
    int start = c->to_up_off;
    while (c->to_up_off < c->to_up_len) {
        ssize_t n = write(c->up_fd, c->to_up + c->to_up_off, c->to_up_len - c->to_up_off);
        if (n > 0) {
            c->to_up_off += (int)n;
        } else if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
            s5_stats_traffic(c, 1, c->to_up_off - start);
            return 0;
        } else if (n < 0 && errno == EINTR) {
            continue;
        } else {
            s5_stats_traffic(c, 1, c->to_up_off - start);
            return -1;
        }
    }
    s5_stats_traffic(c, 1, c->to_up_off - start);
    c->to_up_off = c->to_up_len = 0;
    if (c->down_rd_closed) shutdown(c->up_fd, SHUT_WR);
    return 0;
}

static int flush_to_down(socks5_conn_t *c) {
    int start = c->to_down_off;
    while (c->to_down_off < c->to_down_len) {
        ssize_t n = write(c->down_fd, c->to_down + c->to_down_off, c->to_down_len - c->to_down_off);
        if (n > 0) {
            c->to_down_off += (int)n;
        } else if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
            s5_stats_traffic(c, 0, c->to_down_off - start);
            return 0;
        } else if (n < 0 && errno == EINTR) {
            continue;
        } else {
            s5_stats_traffic(c, 0, c->to_down_off - start);
            return -1;
        }
    }
    s5_stats_traffic(c, 0, c->to_down_off - start);
    c->to_down_off = c->to_down_len = 0;
    if (c->up_rd_closed) shutdown(c->down_fd, SHUT_WR);
    return 0;
}

static int read_from_down(socks5_conn_t *c) {
    ssize_t n = read(c->down_fd, c->to_up, SOCKS5_BUF);
    if (n > 0) {
        stream_cipher_apply(&c->c2s, c->to_up, (int)n);
        c->to_up_len = (int)n;
        c->to_up_off = 0;
        return c->up_connecting ? 0 : flush_to_up(c);
    }
    if (n == 0) {
        c->down_rd_closed = 1;
        if (c->to_up_off >= c->to_up_len) shutdown(c->up_fd, SHUT_WR);
        return 0;
    }
    if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) return 0;
    return -1;
}

static int read_from_up(socks5_conn_t *c) {
    ssize_t n = read(c->up_fd, c->to_down, SOCKS5_BUF);
    if (n > 0) {
        stream_cipher_apply(&c->s2c, c->to_down, (int)n);
        c->to_down_len = (int)n;
        c->to_down_off = 0;
        return flush_to_down(c);
    }
    if (n == 0) {
        c->up_rd_closed = 1;
        if (c->to_down_off >= c->to_down_len) shutdown(c->down_fd, SHUT_WR);
        return 0;
    }
    if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) return 0;
    return -1;
}

static _Thread_local uint8_t s5_scratch[S5_ENCODE_READ_MAX];

static int masked_read(socks5_conn_t *c, const obfuscator_config_t *config, int from_up) {
    int src_fd = from_up ? c->up_fd : c->down_fd;
    uint8_t *dst;
    int *dl, *doff;
    stream_cipher_t *cipher;
    if (from_up) {
        dst = c->to_down; dl = &c->to_down_len; doff = &c->to_down_off; cipher = &c->s2c;
    } else {
        dst = c->to_up; dl = &c->to_up_len; doff = &c->to_up_off; cipher = &c->c2s;
    }

    int base = c->preclass_len;
    if (base) memcpy(s5_scratch, c->preclass, base);
    ssize_t n = read(src_fd, s5_scratch + base, S5_ENCODE_READ_MAX - base);
    if (n == 0) {
        if (from_up) {
            c->up_rd_closed = 1;
            if (c->to_down_off >= c->to_down_len) shutdown(c->down_fd, SHUT_WR);
        } else {
            c->down_rd_closed = 1;
            if (c->to_up_off >= c->to_up_len) shutdown(c->up_fd, SHUT_WR);
        }
        return 0;
    }
    if (n < 0) {
        if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) return 0;
        return -1;
    }
    int total = base + (int)n;
    c->preclass_len = 0;

    if (!c->classified) {
        int f = s5_mask_is_framed(c->mask_type, config, s5_scratch, total);
        if (f < 0) {
            if (total <= S5_PRECLASS) {
                memcpy(c->preclass, s5_scratch, total);
                c->preclass_len = total;
                return 0;
            }
            f = 0;
        }
        c->down_is_raw = from_up ? (uint8_t)f : (uint8_t)(!f);
        c->classified = 1;
    }

    int is_encode = from_up ? !c->down_is_raw : c->down_is_raw;
    if (is_encode) {
        stream_cipher_apply(cipher, s5_scratch, total);
        int outn = s5_mask_encode(c->mask_type, &c->enc, config, s5_scratch, total, dst, SOCKS5_BUF);
        if (outn < 0) return -1;
        *dl = outn;
        *doff = 0;
    } else {
        int outn = s5_mask_decode(c->mask_type, &c->dec, config, s5_scratch, total, dst, SOCKS5_BUF);
        if (outn < 0) return -1;
        if (outn > 0) stream_cipher_apply(cipher, dst, outn);
        *dl = outn;
        *doff = 0;
    }

    if (from_up) return flush_to_down(c);
    return c->up_connecting ? 0 : flush_to_up(c);
}

static int finish_connect(socks5_conn_t *c, const obfuscator_config_t *config) {
    int err = 0;
    socklen_t len = sizeof(err);
    if (getsockopt(c->up_fd, SOL_SOCKET, SO_ERROR, &err, &len) < 0 || err != 0) return -1;
    c->up_connecting = 0;
    if (c->role == S5_ROLE_SERVER && c->phase != S5_PHASE_UDP) {
        // Real SOCKS5 CONNECT reply -- role=server is a genuine terminating
        // SOCKS5 server, so the app (relayed transparently via role=client)
        // must see a real reply here, not an optimistic ack.
        uint8_t rep[10];
        socks5_build_reply(rep, S5_REP_OK);
        if (push_down(c, config, rep, 10) < 0) return -1;
    }
    return flush_to_up(c);
}

static int dial_up(socks5_worker_t *w, socks5_conn_t *c, const struct sockaddr_in *addr) {
    int fd = socket(AF_INET, SOCK_STREAM | SOCK_NONBLOCK, 0);
    if (fd < 0) return -1;
    tune_socket(fd, w->ctx->config);
    mark_exit_socket(fd, w->ctx->config);
    c->up_fd = fd;
    c->up_tag.conn = c;
    c->up_tag.kind = TAG_UP;
    int cr = connect(fd, (const struct sockaddr *)addr, sizeof(*addr));
    if (cr < 0 && errno != EINPROGRESS) return -1;
    c->up_connecting = 1;
    struct epoll_event e;
    e.data.ptr = &c->up_tag;
    e.events = wants_up(c);
    if (epoll_ctl(w->epfd, EPOLL_CTL_ADD, fd, &e) != 0) return -1;
    return 0;
}

// Pushes raw (already real-protocol) bytes upward (client-role only: local
// app -> obfuscated link to server-role), applying obfuscation/masking.
static int push_up(socks5_conn_t *c, const obfuscator_config_t *config, const uint8_t *raw, int rawn) {
    static _Thread_local uint8_t tmp[SOCKS5_BUF];
    if (c->mask_type) {
        if (rawn > (int)sizeof(tmp)) return -1;
        memcpy(tmp, raw, rawn);
        stream_cipher_apply(&c->c2s, tmp, rawn);
        int outn = s5_mask_encode(c->mask_type, &c->enc, config, tmp, rawn, c->to_up, SOCKS5_BUF);
        if (outn < 0) return -1;
        c->to_up_len = outn;
    } else {
        if (rawn > SOCKS5_BUF) return -1;
        memcpy(c->to_up, raw, rawn);
        stream_cipher_apply(&c->c2s, c->to_up, rawn);
        c->to_up_len = rawn;
    }
    c->to_up_off = 0;
    return c->up_connecting ? 0 : flush_to_up(c);
}

// Pushes raw real-protocol bytes downward: role=client forwards them
// untouched to the local app (down side is raw there); role=server encodes
// its own real SOCKS5 replies before they reach the obfuscated link to
// role=client (down side is obfuscated there).
static int push_down(socks5_conn_t *c, const obfuscator_config_t *config, const uint8_t *raw, int rawn) {
    if (c->down_is_raw) {
        if (rawn > SOCKS5_BUF) return -1;
        memcpy(c->to_down, raw, rawn);
        c->to_down_len = rawn;
    } else {
        static _Thread_local uint8_t tmp[SOCKS5_BUF];
        if (rawn > (int)sizeof(tmp)) return -1;
        memcpy(tmp, raw, rawn);
        stream_cipher_apply(&c->s2c, tmp, rawn);
        if (c->mask_type) {
            int outn = s5_mask_encode(c->mask_type, &c->enc, config, tmp, rawn, c->to_down, SOCKS5_BUF);
            if (outn < 0) return -1;
            c->to_down_len = outn;
        } else {
            memcpy(c->to_down, tmp, rawn);
            c->to_down_len = rawn;
        }
    }
    c->to_down_off = 0;
    return flush_to_down(c);
}

static int decode_down_raw(socks5_conn_t *c, const obfuscator_config_t *config,
                           uint8_t *in, int in_len, uint8_t *out, int out_cap) {
    if (c->mask_type) {
        int outn = s5_mask_decode(c->mask_type, &c->dec, config, in, in_len, out, out_cap);
        if (outn < 0) return -1;
        if (outn > 0) stream_cipher_apply(&c->c2s, out, outn);
        return outn;
    }
    if (in_len > out_cap) return -1;
    memcpy(out, in, in_len);
    stream_cipher_apply(&c->c2s, out, in_len);
    return in_len;
}

// Decodes bytes arriving on role=client's up_fd (server-role's obfuscated
// replies) back into real SOCKS5 bytes.
static int decode_up_raw(socks5_conn_t *c, const obfuscator_config_t *config,
                          uint8_t *in, int in_len, uint8_t *out, int out_cap) {
    if (c->mask_type) {
        int outn = s5_mask_decode(c->mask_type, &c->dec, config, in, in_len, out, out_cap);
        if (outn < 0) return -1;
        if (outn > 0) stream_cipher_apply(&c->s2c, out, outn);
        return outn;
    }
    if (in_len > out_cap) return -1;
    memcpy(out, in, in_len);
    stream_cipher_apply(&c->s2c, out, in_len);
    return in_len;
}

static int socks5_auth_index(const obfuscator_config_t *config,
                             const char *login, int login_len,
                             const char *password, int password_len) {
    for (int i = 0; i < config->socks5_user_count; i++) {
        const socks5_cred_t *u = &config->socks5_users[i];
        if (u->login_len == login_len && u->password_len == password_len &&
            memcmp(u->login, login, (size_t)login_len) == 0 &&
            memcmp(u->password, password, (size_t)password_len) == 0)
            return i;
    }
    return -1;
}

// role=client is a transparent (obfuscated) relay for the real SOCKS5
// handshake: it never decides methods or replies itself. It only inspects
// message boundaries (via the existing real-protocol parsers) so it knows
// when to hand off into pure relay (CONNECT) or into UDP ASSOCIATE's local
// socket setup -- both decisions are made by role=server, the real endpoint.
static int client_handshake(socks5_worker_t *w, socks5_conn_t *c, const obfuscator_config_t *config) {
    uint8_t buf[512];
    ssize_t n = read(c->down_fd, buf, sizeof(buf));
    if (n == 0) return -1;
    if (n < 0) return (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) ? 0 : -1;
    if (c->hs_len + (int)n > (int)sizeof(c->hs)) return -1;
    memcpy(c->hs + c->hs_len, buf, n);
    c->hs_len += (int)n;

    if (c->hstate == CHS_GREETING) {
        int g = socks5_parse_greeting(c->hs, c->hs_len);
        if (g < 0) return -1;
        if (g == 0) return 0;
        if (dial_up(w, c, &w->ctx->forward_addr) < 0) return -1;
        if (push_up(c, config, c->hs, g) < 0) return -1;
        memmove(c->hs, c->hs + g, c->hs_len - g);
        c->hs_len -= g;
        c->hstate = CHS_METHOD_REPLY;
        return 0;
    }

    if (c->hstate == CHS_USERPASS) {
        char login[S5_CRED_MAX], password[S5_CRED_MAX];
        int login_len, password_len;
        int r = socks5_parse_userpass(c->hs, c->hs_len, login, &login_len, password, &password_len);
        if (r < 0) return -1;
        if (r == 0) return 0;
        if (push_up(c, config, c->hs, r) < 0) return -1;
        memmove(c->hs, c->hs + r, c->hs_len - r);
        c->hs_len -= r;
        c->hstate = CHS_USERPASS_REPLY;
        return 0;
    }

    if (c->hstate == CHS_REQUEST) {
        socks5_target_t t;
        int r = socks5_parse_request(c->hs, c->hs_len, &t);
        if (r < 0) return -1;
        if (r == 0) return 0;
        if (push_up(c, config, c->hs, r) < 0) return -1;
        memmove(c->hs, c->hs + r, c->hs_len - r);
        c->hs_len -= r;
        if (t.cmd == S5_CMD_UDP) {
            c->hstate = CHS_UDP_REPLY;
            return 0;
        }
        // CONNECT (or any other cmd -- role=server validates for real): from
        // here on it's a pure opaque relay, including the real reply flowing
        // back down through the generic data path.
        c->phase = S5_PHASE_RELAY;
        return 0;
    }

    // Stray local bytes while waiting on role=server (method-select,
    // userpass status, or UDP bind reply) -- a compliant app shouldn't send
    // anything yet.
    return -1;
}

// Handles bytes arriving on role=client's up_fd (role=server's real replies)
// while still in the handshake phase. Everything is forwarded down to the
// real app untouched, except the UDP ASSOCIATE reply, whose bind address
// must point at role=client's own local UDP relay socket, not role=server's.
static int client_handshake_up(socks5_worker_t *w, socks5_conn_t *c, const obfuscator_config_t *config) {
    static _Thread_local uint8_t rbuf[S5_ENCODE_READ_MAX];
    static _Thread_local uint8_t plain[SOCKS5_BUF];

    ssize_t n = read(c->up_fd, rbuf, sizeof(rbuf));
    if (n == 0) return -1;
    if (n < 0) return (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) ? 0 : -1;

    int pn = decode_up_raw(c, config, rbuf, (int)n, plain, sizeof(plain));
    if (pn < 0) return -1;
    if (pn > 0) {
        if (c->hs_up_len + pn > (int)sizeof(c->hs_up)) return -1;
        memcpy(c->hs_up + c->hs_up_len, plain, pn);
        c->hs_up_len += pn;
    }

    for (;;) {
        if (c->hstate == CHS_METHOD_REPLY || c->hstate == CHS_USERPASS_REPLY) {
            if (c->hs_up_len < 2) return 0;
            uint8_t second_byte = c->hs_up[1];
            if (push_down(c, config, c->hs_up, 2) < 0) return -1;
            memmove(c->hs_up, c->hs_up + 2, c->hs_up_len - 2);
            c->hs_up_len -= 2;
            c->hstate = (c->hstate == CHS_METHOD_REPLY && second_byte == S5_METHOD_USERPASS)
                ? CHS_USERPASS : CHS_REQUEST;
            continue;
        }
        if (c->hstate == CHS_UDP_REPLY) {
            uint8_t rep;
            socks5_target_t t;
            int r = socks5_parse_reply(c->hs_up, c->hs_up_len, &rep, &t);
            if (r < 0) return -1;
            if (r == 0) return 0;
            memmove(c->hs_up, c->hs_up + r, c->hs_up_len - r);
            c->hs_up_len -= r;
            if (rep != S5_REP_OK) {
                uint8_t out[10];
                socks5_build_reply(out, rep);
                push_down(c, config, out, 10);
                return -1;
            }
            if (client_udp_setup(w, c, config) < 0) return -1;
            if (c->hs_up_len > 0) {
                int dl = udp_deliver_frames(c, c->hs_up, c->hs_up_len, 1);
                c->hs_up_len = 0;
                if (dl < 0) return -1;
            }
            return 0;
        }
        // No handler for the current state expects up-side data (we've
        // moved on to a state that waits on the local app instead) --
        // that's normal once fully drained, not a protocol violation.
        if (c->hs_up_len == 0) return 0;
        return -1;
    }
}

// role=server is a real, terminating SOCKS5 server: real method negotiation
// (including RFC1929 username/password), real CONNECT/UDP ASSOCIATE handling.
static int server_handshake(socks5_worker_t *w, socks5_conn_t *c, const obfuscator_config_t *config) {
    static _Thread_local uint8_t rbuf[S5_ENCODE_READ_MAX];
    static _Thread_local uint8_t raw[SOCKS5_BUF];
    static _Thread_local uint8_t combined[600 + SOCKS5_BUF];

    ssize_t n = read(c->down_fd, rbuf, sizeof(rbuf));
    if (n == 0) return -1;
    if (n < 0) return (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) ? 0 : -1;

    int rawn = decode_down_raw(c, config, rbuf, (int)n, raw, sizeof(raw));
    if (rawn < 0) return -1;
    if (rawn == 0) return 0;

    int total = 0;
    if (c->hs_len) { memcpy(combined, c->hs, c->hs_len); total = c->hs_len; }
    memcpy(combined + total, raw, rawn);
    total += rawn;
    c->hs_len = 0;

    if (c->hstate == SHS_GREETING) {
        int g = socks5_parse_greeting(combined, total);
        if (g < 0) return -1;
        if (g == 0) {
            if (total > (int)sizeof(c->hs)) return -1;
            memcpy(c->hs, combined, total);
            c->hs_len = total;
            return 0;
        }
        const uint8_t *methods;
        int mcount;
        if (socks5_greeting_methods(combined, g, &methods, &mcount) < 0) return -1;
        int has_userpass = 0, has_noauth = 0;
        for (int i = 0; i < mcount; i++) {
            if (methods[i] == S5_METHOD_USERPASS) has_userpass = 1;
            if (methods[i] == S5_METHOD_NOAUTH) has_noauth = 1;
        }
        uint8_t chosen = config->socks5_user_count > 0
            ? (has_userpass ? S5_METHOD_USERPASS : S5_METHOD_NONE)
            : (has_noauth ? S5_METHOD_NOAUTH : S5_METHOD_NONE);

        uint8_t rep[2];
        socks5_build_method(rep, chosen);
        if (push_down(c, config, rep, 2) < 0) return -1;
        if (chosen == S5_METHOD_NONE) return -1;

        int leftover = total - g;
        if (leftover > 0) {
            if (leftover > (int)sizeof(c->hs)) return -1;
            memcpy(c->hs, combined + g, leftover);
            c->hs_len = leftover;
        }
        c->hstate = (chosen == S5_METHOD_USERPASS) ? SHS_USERPASS : SHS_REQUEST;
        return 0;
    }

    if (c->hstate == SHS_USERPASS) {
        char login[S5_CRED_MAX], password[S5_CRED_MAX];
        int login_len, password_len;
        int r = socks5_parse_userpass(combined, total, login, &login_len, password, &password_len);
        if (r < 0) return -1;
        if (r == 0) {
            if (total > (int)sizeof(c->hs)) return -1;
            memcpy(c->hs, combined, total);
            c->hs_len = total;
            return 0;
        }
        int user_index = socks5_auth_index(config, login, login_len, password, password_len);
        uint8_t rep[2];
        socks5_build_userpass_reply(rep, user_index >= 0 ? 0x00 : 0x01);
        if (push_down(c, config, rep, 2) < 0) return -1;
        if (user_index < 0) {
            log(LL_WARN, "SOCKS5 auth failed for login '%.*s'", login_len, login);
            return -1;
        }
        c->user_index = user_index;
        s5_user_stats_t *s = &s5_user_stats[user_index];
        __atomic_fetch_add(&s->conns, 1, __ATOMIC_RELAXED);
        __atomic_store_n(&s->last_activity, now_ms(), __ATOMIC_RELAXED);
        int leftover = total - r;
        if (leftover > 0) {
            if (leftover > (int)sizeof(c->hs)) return -1;
            memcpy(c->hs, combined + r, leftover);
            c->hs_len = leftover;
        }
        c->hstate = SHS_REQUEST;
        return 0;
    }

    // SHS_REQUEST
    socks5_target_t t;
    int r = socks5_parse_request(combined, total, &t);
    if (r < 0) return -1;
    if (r == 0) {
        if (total > (int)sizeof(c->hs)) return -1;
        memcpy(c->hs, combined, total);
        c->hs_len = total;
        return 0;
    }

    if (t.cmd == S5_CMD_UDP) {
        return server_udp_setup(w, c, config, combined + r, total - r);
    }
    if (t.cmd != S5_CMD_CONNECT) {
        uint8_t rep[10];
        socks5_build_reply(rep, S5_REP_NOTSUP);
        push_down(c, config, rep, 10);
        return -1;
    }

    char host[256];
    if (socks5_target_host(&t, host, sizeof(host)) != 0) return -1;
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    if (resolve_ipv4(host, &addr.sin_addr) != 0) {
        log(LL_DEBUG, "SOCKS5 server: can't resolve %s", host);
        uint8_t rep[10];
        socks5_build_reply(rep, S5_REP_FAIL);
        push_down(c, config, rep, 10);
        return -1;
    }
    addr.sin_port = htons(t.port);

    int leftover = total - r;
    if (leftover > 0) {
        if (leftover > SOCKS5_BUF) return -1;
        memcpy(c->to_up, combined + r, leftover);
        c->to_up_len = leftover;
        c->to_up_off = 0;
    }
    c->phase = S5_PHASE_RELAY;
    if (dial_up(w, c, &addr) < 0) return -1;
    log(LL_DEBUG, "SOCKS5 server: connect to %s:%d", host, t.port);
    return 0;
}

static int build_udp_tunnel_frame(const socks5_target_t *t, const uint8_t *data, int dlen, uint8_t *out, int cap) {
    int hl = socks5_udp_build_header(out + 2, t);
    int body = hl + dlen;
    if (2 + body > cap) return -1;
    memcpy(out + 2 + hl, data, dlen);
    out[0] = (body >> 8) & 0xFF;
    out[1] = body & 0xFF;
    return 2 + body;
}

static int tunnel_send(socks5_conn_t *c, const obfuscator_config_t *config, int from_client,
                       const uint8_t *raw, int rawn) {
    uint8_t *dst;
    int *dlen, *doff;
    stream_cipher_t *cipher;
    if (from_client) { dst = c->to_up; dlen = &c->to_up_len; doff = &c->to_up_off; cipher = &c->c2s; }
    else { dst = c->to_down; dlen = &c->to_down_len; doff = &c->to_down_off; cipher = &c->s2c; }

    if (*doff > 0) {
        if (*doff < *dlen) memmove(dst, dst + *doff, *dlen - *doff);
        *dlen -= *doff;
        *doff = 0;
    }
    if (*dlen + rawn + 64 > SOCKS5_BUF) return 0;

    static _Thread_local uint8_t tmp[2048];
    if (rawn > (int)sizeof(tmp)) return 0;
    memcpy(tmp, raw, rawn);
    stream_cipher_apply(cipher, tmp, rawn);
    if (c->mask_type) {
        int outn = s5_mask_encode(c->mask_type, &c->enc, config, tmp, rawn, dst + *dlen, SOCKS5_BUF - *dlen);
        if (outn < 0) return -1;
        *dlen += outn;
    } else {
        memcpy(dst + *dlen, tmp, rawn);
        *dlen += rawn;
    }
    if (from_client) return c->up_connecting ? 0 : flush_to_up(c);
    return flush_to_down(c);
}

static int udp_deliver_frames(socks5_conn_t *c,
                              const uint8_t *raw_in, int in_len, int is_client) {
    static _Thread_local uint8_t comb[2048 + SOCKS5_BUF];
    if (in_len > SOCKS5_BUF) return -1;
    int total = c->udp_acc_len;
    if (total) memcpy(comb, c->udp_acc, total);
    memcpy(comb + total, raw_in, in_len);
    total += in_len;

    int pos = 0;
    while (total - pos >= 2) {
        int L = (comb[pos] << 8) | comb[pos + 1];
        if (L < 4 || L > 2002) return -1;
        if (total - pos < 2 + L) break;
        socks5_target_t t;
        int data_off;
        if (socks5_udp_parse(comb + pos + 2, L, &t, &data_off) < 0) return -1;
        const uint8_t *data = comb + pos + 2 + data_off;
        int dl = L - data_off;
        if (is_client) {
            uint8_t out[2048];
            int hl = socks5_udp_build_header(out, &t);
            if (hl + dl <= (int)sizeof(out) && c->app_udp_known) {
                memcpy(out + hl, data, dl);
                sendto(c->udp_fd, out, hl + dl, MSG_DONTWAIT,
                       (struct sockaddr *)&c->app_udp_addr, sizeof(c->app_udp_addr));
            }
        } else {
            char host[256];
            struct sockaddr_in dst;
            if (socks5_target_host(&t, host, sizeof(host)) == 0) {
                memset(&dst, 0, sizeof(dst));
                dst.sin_family = AF_INET;
                if (resolve_ipv4(host, &dst.sin_addr) == 0) {
                    dst.sin_port = htons(t.port);
                    ssize_t sent = sendto(c->udp_fd, data, dl, MSG_DONTWAIT, (struct sockaddr *)&dst, sizeof(dst));
                    if (sent > 0) s5_stats_traffic(c, 1, (int)sent);
                }
            }
        }
        pos += 2 + L;
    }
    int left = total - pos;
    if (left > (int)sizeof(c->udp_acc)) return -1;
    if (left) memmove(c->udp_acc, comb + pos, left);
    c->udp_acc_len = left;
    return 0;
}

static int udp_tunnel_recv(socks5_conn_t *c, const obfuscator_config_t *config,
                           int fd, stream_cipher_t *cipher, int is_client) {
    static _Thread_local uint8_t rb[S5_ENCODE_READ_MAX];
    static _Thread_local uint8_t raw[SOCKS5_BUF];
    ssize_t n = read(fd, rb, sizeof(rb));
    if (n == 0) return -1;
    if (n < 0) return (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) ? 0 : -1;
    int rawn;
    if (c->mask_type) {
        rawn = s5_mask_decode(c->mask_type, &c->dec, config, rb, (int)n, raw, sizeof(raw));
        if (rawn < 0) return -1;
        if (rawn > 0) stream_cipher_apply(cipher, raw, rawn);
    } else {
        if (n > (int)sizeof(raw)) return -1;
        memcpy(raw, rb, n);
        stream_cipher_apply(cipher, raw, (int)n);
        rawn = (int)n;
    }
    if (rawn > 0) return udp_deliver_frames(c, raw, rawn, is_client);
    return 0;
}

static int udp_register(socks5_worker_t *w, socks5_conn_t *c, in_addr_t bind_addr) {
    int fd = socket(AF_INET, SOCK_DGRAM | SOCK_NONBLOCK, 0);
    if (fd < 0) return -1;
    mark_exit_socket(fd, w->ctx->config);
    struct sockaddr_in a;
    memset(&a, 0, sizeof(a));
    a.sin_family = AF_INET;
    a.sin_addr.s_addr = bind_addr;
    a.sin_port = 0;
    if (bind(fd, (struct sockaddr *)&a, sizeof(a)) < 0) { close(fd); return -1; }
    c->udp_fd = fd;
    c->udp_tag.conn = c;
    c->udp_tag.kind = TAG_UDP;
    struct epoll_event e;
    e.data.ptr = &c->udp_tag;
    e.events = EPOLLIN;
    if (epoll_ctl(w->epfd, EPOLL_CTL_ADD, fd, &e) != 0) { close(fd); c->udp_fd = -1; return -1; }
    return 0;
}

// Called once role=server has confirmed a successful UDP ASSOCIATE (real
// SOCKS5 reply already consumed by the caller). Opens the local UDP relay
// socket for the real app and replies with ITS bind address/port -- never
// role=server's, which the app could not reach directly.
static int client_udp_setup(struct socks5_worker *w, struct socks5_conn *c, const obfuscator_config_t *config) {
    struct sockaddr_in local;
    socklen_t ll = sizeof(local);
    if (getsockname(c->down_fd, (struct sockaddr *)&local, &ll) != 0) return -1;

    if (udp_register(w, c, local.sin_addr.s_addr) < 0) return -1;

    struct sockaddr_in ua;
    socklen_t ul = sizeof(ua);
    if (getsockname(c->udp_fd, (struct sockaddr *)&ua, &ul) != 0) return -1;

    uint8_t rep[10];
    socks5_build_reply(rep, S5_REP_OK);
    rep[3] = S5_ATYP_IPV4;
    memcpy(rep + 4, &local.sin_addr.s_addr, 4);
    memcpy(rep + 8, &ua.sin_port, 2);
    if (push_down(c, config, rep, 10) < 0) return -1;

    c->phase = S5_PHASE_UDP;
    return 0;
}

static int server_udp_setup(struct socks5_worker *w, struct socks5_conn *c, const obfuscator_config_t *config, const uint8_t *rest, int rest_len) {
    if (udp_register(w, c, INADDR_ANY) < 0) return -1;

    struct sockaddr_in ua;
    socklen_t ul = sizeof(ua);
    if (getsockname(c->udp_fd, (struct sockaddr *)&ua, &ul) != 0) return -1;

    uint8_t rep[10];
    socks5_build_reply(rep, S5_REP_OK);
    rep[3] = S5_ATYP_IPV4;
    // role=client substitutes its own local bind address before this reaches
    // the app, so the exact address here is irrelevant -- only the port
    // matters for symmetry with a real SOCKS5 server's reply shape.
    memset(rep + 4, 0, 4);
    memcpy(rep + 8, &ua.sin_port, 2);
    if (push_down(c, config, rep, 10) < 0) return -1;

    c->phase = S5_PHASE_UDP;
    if (rest_len > 0) return udp_deliver_frames(c, rest, rest_len, 0);
    return 0;
}

static int udp_relay_event(struct socks5_worker *w, struct socks5_conn *c, const obfuscator_config_t *config) {
    (void)w;
    static _Thread_local uint8_t dg[65536];
    for (;;) {
        struct sockaddr_in src;
        socklen_t sl = sizeof(src);
        ssize_t n = recvfrom(c->udp_fd, dg, sizeof(dg), MSG_DONTWAIT, (struct sockaddr *)&src, &sl);
        if (n < 0) {
            if (errno == EAGAIN || errno == EWOULDBLOCK) break;
            if (errno == EINTR) continue;
            break;
        }
        if (n == 0) continue;
        uint8_t raw[2048];
        if (c->role == S5_ROLE_CLIENT) {
            socks5_target_t t;
            int data_off;
            if (socks5_udp_parse(dg, (int)n, &t, &data_off) < 0) continue;
            if (!c->app_udp_known) { c->app_udp_addr = src; c->app_udp_known = 1; }
            int fl = build_udp_tunnel_frame(&t, dg + data_off, (int)n - data_off, raw, sizeof(raw));
            if (fl < 0) continue;
            if (tunnel_send(c, config, 1, raw, fl) < 0) return -1;
        } else {
            socks5_target_t t;
            t.atyp = S5_ATYP_IPV4;
            memcpy(t.addr, &src.sin_addr.s_addr, 4);
            t.addrlen = 4;
            t.port = ntohs(src.sin_port);
            int fl = build_udp_tunnel_frame(&t, dg, (int)n, raw, sizeof(raw));
            if (fl < 0) continue;
            if (tunnel_send(c, config, 0, raw, fl) < 0) return -1;
        }
    }
    return 0;
}

static int udp_control_event(struct socks5_worker *w, struct socks5_conn *c, const obfuscator_config_t *config, uint32_t events) {
    (void)w;
    if (c->role == S5_ROLE_CLIENT) {
        if (events & EPOLLOUT) { if (flush_to_down(c) < 0) return -1; }
        if (events & EPOLLIN) {
            uint8_t b[256];
            ssize_t n = read(c->down_fd, b, sizeof(b));
            if (n == 0) return -1;
            if (n < 0 && !(errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR)) return -1;
        }
        return 0;
    }
    if (events & EPOLLOUT) { if (flush_to_down(c) < 0) return -1; }
    if (events & EPOLLIN) return udp_tunnel_recv(c, config, c->down_fd, &c->c2s, 0);
    return 0;
}

static void accept_new(socks5_worker_t *w, socks5_listen_t *route) {
    socks5_context_t *ctx = w->ctx;
    for (;;) {
        struct sockaddr_in peer;
        socklen_t plen = sizeof(peer);
        int down_fd = accept4(route->fd, (struct sockaddr *)&peer, &plen, SOCK_NONBLOCK);
        if (down_fd < 0) {
            if (errno == EAGAIN || errno == EWOULDBLOCK) break;
            if (errno == EINTR) continue;
            break;
        }

        if (__atomic_load_n(&socks5_client_count, __ATOMIC_RELAXED) >= (unsigned)ctx->config->max_clients) {
            log(LL_WARN, "Maximum number of clients reached (%d), dropping connection", ctx->config->max_clients);
            close(down_fd);
            continue;
        }

        socks5_conn_t *c = calloc(1, sizeof(socks5_conn_t));
        if (!c) {
            log(LL_ERROR, "Failed to allocate connection");
            close(down_fd);
            continue;
        }

        c->down_fd = down_fd;
        c->up_fd = -1;
        c->udp_fd = -1;
        c->down_tag.conn = c;
        c->down_tag.kind = TAG_DOWN;
        c->up_tag.conn = c;
        c->up_tag.kind = TAG_UP;
        c->mask_type = (uint8_t)s5_mask_type(ctx->config);
        c->role = (uint8_t)ctx->config->socks5_role;
        c->user_index = -1;
        c->last_activity = now_ms();
        stream_cipher_init(&c->c2s, ctx->xor_key, ctx->key_length);
        stream_cipher_init(&c->s2c, ctx->xor_key, ctx->key_length);
        tune_socket(down_fd, ctx->config);

        if (c->role == S5_ROLE_RELAY) {
            int up_fd = socket(AF_INET, SOCK_STREAM | SOCK_NONBLOCK, 0);
            if (up_fd < 0) {
                serror("Failed to create upstream socket");
                close(down_fd);
                free(c);
                continue;
            }
            c->phase = S5_PHASE_RELAY;
            c->up_fd = up_fd;
            c->up_connecting = 1;
            tune_socket(up_fd, ctx->config);
            int cr = connect(up_fd, (struct sockaddr *)&route->fwd, sizeof(route->fwd));
            if (cr < 0 && errno != EINPROGRESS) {
                serror("Failed to connect upstream");
                close(down_fd);
                close(up_fd);
                free(c);
                continue;
            }
            struct epoll_event e;
            e.data.ptr = &c->down_tag;
            e.events = wants_down(c);
            epoll_ctl(w->epfd, EPOLL_CTL_ADD, down_fd, &e);
            e.data.ptr = &c->up_tag;
            e.events = wants_up(c);
            epoll_ctl(w->epfd, EPOLL_CTL_ADD, up_fd, &e);
        } else {
            c->phase = S5_PHASE_HS;
            c->classified = 1;
            c->down_is_raw = (c->role == S5_ROLE_CLIENT) ? 1 : 0;
            c->hstate = 0; // CHS_GREETING / SHS_GREETING
            struct epoll_event e;
            e.data.ptr = &c->down_tag;
            e.events = EPOLLIN;
            epoll_ctl(w->epfd, EPOLL_CTL_ADD, down_fd, &e);
        }

        c->next = w->conns;
        c->prev = NULL;
        if (w->conns) w->conns->prev = c;
        w->conns = c;
        __atomic_fetch_add(&socks5_client_count, 1, __ATOMIC_RELAXED);
        log(LL_DEBUG, "New connection from %s:%d", inet_ntoa(peer.sin_addr), ntohs(peer.sin_port));
    }
}

static void handle_event(socks5_worker_t *w, sock_tag_t *tag, uint32_t events, long now) {
    socks5_conn_t *c = tag->conn;
    const obfuscator_config_t *cfg = w->ctx->config;
    int rc = 0;

    if (tag->kind == TAG_UDP) {
        rc = udp_relay_event(w, c, cfg);
    } else if (tag->kind == TAG_UP) {
        if ((events & (EPOLLERR | EPOLLHUP)) && c->up_connecting) { conn_close(w, c); return; }
        if (c->up_connecting && (events & EPOLLOUT)) {
            if (finish_connect(c, cfg) < 0) { conn_close(w, c); return; }
        } else if (c->phase == S5_PHASE_UDP) {
            if (events & EPOLLOUT) rc |= flush_to_up(c);
            if ((events & EPOLLIN) && rc == 0) rc |= udp_tunnel_recv(c, cfg, c->up_fd, &c->s2c, 1);
        } else if (c->phase == S5_PHASE_HS && c->role == S5_ROLE_CLIENT) {
            if (events & EPOLLOUT) rc |= flush_to_up(c);
            if ((events & EPOLLIN) && rc == 0) rc |= client_handshake_up(w, c, cfg);
        } else {
            if (events & EPOLLOUT) rc |= flush_to_up(c);
            if ((events & EPOLLIN) && rc == 0)
                rc |= c->mask_type ? masked_read(c, cfg, 1) : read_from_up(c);
        }
    } else if (c->phase == S5_PHASE_HS) {
        if (events & EPOLLOUT) rc |= flush_to_down(c);
        if ((events & EPOLLIN) && rc == 0)
            rc |= (c->role == S5_ROLE_CLIENT) ? client_handshake(w, c, cfg) : server_handshake(w, c, cfg);
    } else if (c->phase == S5_PHASE_UDP) {
        rc = udp_control_event(w, c, cfg, events);
    } else {
        if (events & EPOLLOUT) rc |= flush_to_down(c);
        if ((events & EPOLLIN) && rc == 0)
            rc |= c->mask_type ? masked_read(c, cfg, 0) : read_from_down(c);
    }

    if (rc < 0) { conn_close(w, c); return; }
    c->last_activity = now;
    if (c->phase != S5_PHASE_UDP && conn_finished(c)) { conn_close(w, c); return; }
    refresh_epoll(w, c);
}

static void s5_stats_write(const obfuscator_config_t *config, long now) {
    char tmp_path[sizeof(config->socks5_stats_path) + 8];
    snprintf(tmp_path, sizeof(tmp_path), "%s.tmp", config->socks5_stats_path);
    FILE *f = fopen(tmp_path, "w");
    if (!f) return;
    for (int i = 0; i < config->socks5_user_count; i++) {
        const s5_user_stats_t *s = &s5_user_stats[i];
        uint64_t up = __atomic_load_n(&s->up_bytes, __ATOMIC_RELAXED);
        uint64_t down = __atomic_load_n(&s->down_bytes, __ATOMIC_RELAXED);
        uint32_t conns = __atomic_load_n(&s->conns, __ATOMIC_RELAXED);
        long last = __atomic_load_n(&s->last_activity, __ATOMIC_RELAXED);
        if (!up && !down && !conns && !last) continue;
        fprintf(f, "%.*s %llu %llu %u %ld\n",
                config->socks5_users[i].login_len, config->socks5_users[i].login,
                (unsigned long long)up, (unsigned long long)down, conns,
                last ? now - last : -1L);
    }
    fclose(f);
    rename(tmp_path, config->socks5_stats_path);
}

static void worker_cleanup(socks5_worker_t *w, long now) {
    long timeout = w->ctx->config->idle_timeout;
    socks5_conn_t *cur = w->conns;
    while (cur) {
        socks5_conn_t *next = cur->next;
        if (now - cur->last_activity >= timeout) {
            log(LL_DEBUG, "Removing idle connection");
            conn_free(w, cur);
        }
        cur = next;
    }
}

static void socks5_worker_run(socks5_worker_t *w) {
    pin_to_cpu(w->cpu);
    struct epoll_event events[SOCKS5_EPOLL_EVENTS];

    while (w->running) {
        int n = epoll_wait(w->epfd, events, SOCKS5_EPOLL_EVENTS, 1000);
        long now = now_ms();

        for (int i = 0; i < n; i++) {
            uint8_t kind = *(const uint8_t *)events[i].data.ptr;
            if (kind == TAG_LISTEN) {
                accept_new(w, (socks5_listen_t *)events[i].data.ptr);
            } else {
                sock_tag_t *tag = (sock_tag_t *)events[i].data.ptr;
                if (!tag->conn->dead) handle_event(w, tag, events[i].events, now);
            }
        }

        while (w->dead) {
            socks5_conn_t *d = w->dead;
            w->dead = d->next;
            free(d);
        }

        if (now - w->last_cleanup_time >= ITERATE_INTERVAL) {
            worker_cleanup(w, now);
            w->last_cleanup_time = now;
            if (w->worker_index == 0 && w->ctx->config->socks5_stats_path[0] &&
                w->ctx->config->socks5_role == S5_ROLE_SERVER) {
                s5_stats_write(w->ctx->config, now);
            }
        }
    }

    socks5_conn_t *cur = w->conns;
    while (cur) {
        socks5_conn_t *next = cur->next;
        conn_free(w, cur);
        cur = next;
    }
}

static void *socks5_worker_main(void *arg) {
    socks5_worker_t *w = (socks5_worker_t *)arg;
    log(LL_DEBUG, "SOCKS5 worker #%d started (cpu %d)", w->worker_index, w->cpu);
    socks5_worker_run(w);
    log(LL_DEBUG, "SOCKS5 worker #%d stopped", w->worker_index);
    return NULL;
}

static int open_listen_socket(socks5_context_t *ctx, uint16_t port) {
    int sock = socket(AF_INET, SOCK_STREAM | SOCK_NONBLOCK, 0);
    if (sock < 0) {
        serror("Can't create listen socket");
        return -1;
    }
    int one = 1;
    setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = ctx->listen_addr;
    addr.sin_port = htons(port);
    if (bind(sock, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        serror("Failed to bind listen socket to %s:%d", inet_ntoa(addr.sin_addr), port);
        close(sock);
        return -1;
    }
    if (listen(sock, SOCKS5_BACKLOG) < 0) {
        serror("Failed to listen");
        close(sock);
        return -1;
    }
    return sock;
}

static int add_route(socks5_context_t *ctx, uint16_t port, const struct sockaddr_in *fwd, int has_fwd) {
    if (ctx->route_count >= SOCKS5_MAX_ROUTES) {
        log(LL_ERROR, "Too many TCP bindings (max %d)", SOCKS5_MAX_ROUTES);
        return -1;
    }
    int fd = open_listen_socket(ctx, port);
    if (fd < 0) return -1;
    socks5_listen_t *r = &ctx->routes[ctx->route_count++];
    r->kind = TAG_LISTEN;
    r->fd = fd;
    r->has_fwd = (uint8_t)has_fwd;
    if (has_fwd) r->fwd = *fwd;
    return 0;
}

static int parse_tcp_bindings(socks5_context_t *ctx, obfuscator_config_t *config) {
    char *binding = strtok(config->static_bindings, ",");
    while (binding) {
        binding = trim(binding);
        char *colon1 = strchr(binding, ':');
        char *colon2 = colon1 ? strrchr(binding, ':') : NULL;
        if (!colon1 || colon2 == colon1) {
            log(LL_ERROR, "Invalid TCP binding format: %s (expected lport:host:rport)", binding);
            return -1;
        }
        *colon1 = 0;
        *colon2 = 0;
        int lport = atoi(binding);
        char *host = colon1 + 1;
        int rport = atoi(colon2 + 1);
        if (lport <= 0 || lport > 65535 || rport <= 0 || rport > 65535) {
            log(LL_ERROR, "Invalid port in TCP binding");
            return -1;
        }
        struct sockaddr_in fwd;
        memset(&fwd, 0, sizeof(fwd));
        fwd.sin_family = AF_INET;
        if (resolve_ipv4_wait(host, &fwd.sin_addr, config->stop) != 0) {
            log(LL_ERROR, "Can't resolve host '%s' for TCP binding", host);
            return -1;
        }
        fwd.sin_port = htons(rport);
        if (add_route(ctx, (uint16_t)lport, &fwd, 1) < 0) return -1;
        log(LL_INFO, "TCP binding: listen %d -> %s:%d", lport, host, rport);
        binding = strtok(NULL, ",");
    }
    return 0;
}

int socks5_start(socks5_context_t *ctx, obfuscator_config_t *config,
                 char *xor_key, int key_length, struct sockaddr_in *forward_addr,
                 in_addr_t listen_addr, uint16_t listen_port) {
    ctx->config = config;
    ctx->xor_key = xor_key;
    ctx->key_length = key_length;
    ctx->forward_addr = *forward_addr;
    ctx->listen_addr = listen_addr;
    ctx->listen_port = listen_port;
    ctx->route_count = 0;
    ctx->running = 1;

    if (add_route(ctx, listen_port, forward_addr, config->forward_host_port_set) < 0) return -1;
    if (config->socks5_role == S5_ROLE_RELAY && config->static_bindings_set) {
        if (parse_tcp_bindings(ctx, config) < 0) return -1;
    }
    ctx->listen_sock = ctx->routes[0].fd;

    for (int i = 0; i < ctx->num_workers; i++) {
        socks5_worker_t *w = &ctx->workers[i];
        w->ctx = ctx;
        w->listen_sock = ctx->listen_sock;
        w->conns = NULL;
        w->last_cleanup_time = 0;
        w->running = 1;
        w->epfd = epoll_create1(0);
        if (w->epfd < 0) {
            serror("epoll_create1");
            return -1;
        }
        for (int r = 0; r < ctx->route_count; r++) {
            struct epoll_event e;
            e.events = EPOLLIN | EPOLLEXCLUSIVE;
            e.data.ptr = &ctx->routes[r];
            if (epoll_ctl(w->epfd, EPOLL_CTL_ADD, ctx->routes[r].fd, &e) != 0) {
                e.events = EPOLLIN;
                epoll_ctl(w->epfd, EPOLL_CTL_ADD, ctx->routes[r].fd, &e);
            }
        }
        if (pthread_create(&w->thread_id, NULL, socks5_worker_main, w) != 0) {
            log(LL_ERROR, "Failed to create SOCKS5 worker #%d: %s", i, strerror(errno));
            return -1;
        }
    }
    log(LL_INFO, "Started %d SOCKS5 worker thread(s), %d listen route(s)", ctx->num_workers, ctx->route_count);
    return 0;
}

#else

int socks5_start(socks5_context_t *ctx, obfuscator_config_t *config,
                 char *xor_key, int key_length, struct sockaddr_in *forward_addr,
                 in_addr_t listen_addr, uint16_t listen_port) {
    (void)ctx; (void)config; (void)xor_key; (void)key_length;
    (void)forward_addr; (void)listen_addr; (void)listen_port;
    log(LL_ERROR, "SOCKS5 mode requires Linux (epoll)");
    return -1;
}

#endif

int socks5_init(socks5_context_t *ctx, obfuscator_config_t *config) {
    memset(ctx, 0, sizeof(*ctx));

    int order[SOCKS5_MAX_WORKERS];
    int navail = detect_topology(order, SOCKS5_MAX_WORKERS);

    int limit = cgroup_cpu_limit();
    if (limit > 0 && limit < navail) navail = limit;

    int n = config->threads > 0 ? config->threads : navail;
    if (n < 1) n = 1;
    if (n > SOCKS5_MAX_WORKERS) n = SOCKS5_MAX_WORKERS;

    ctx->num_workers = n;
    for (int i = 0; i < n; i++) {
        ctx->workers[i].worker_index = i;
        ctx->workers[i].cpu = (i < navail) ? order[i] : -1;
    }
    log(LL_INFO, "SOCKS5 mode: %d worker(s)", n);
    return 0;
}

void socks5_shutdown(socks5_context_t *ctx) {
    ctx->running = 0;
    for (int i = 0; i < ctx->num_workers; i++) {
        ctx->workers[i].running = 0;
    }
}

void socks5_join(socks5_context_t *ctx) {
    for (int i = 0; i < ctx->num_workers; i++) {
        if (ctx->workers[i].thread_id) {
            pthread_join(ctx->workers[i].thread_id, NULL);
        }
    }
#ifdef __linux__
    for (int i = 0; i < ctx->num_workers; i++) {
        if (ctx->workers[i].epfd > 0) close(ctx->workers[i].epfd);
    }
    for (int r = 0; r < ctx->route_count; r++) {
        if (ctx->routes[r].fd > 0) close(ctx->routes[r].fd);
    }
#endif
}
