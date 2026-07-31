#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <ctype.h>
#include <unistd.h>
#include <time.h>
#include "compat_net.h"
#include <sys/socket.h>
#include <sys/time.h>
#include "resolve.h"
#include "wg-obfuscator.h"

#define DNS_PORT 53
#define DNS_MAX_NS 4
#define DNS_TIMEOUT_SEC 3
#define DNS_BUF_SIZE 1500
#define DNS_TYPE_A 1
#define DNS_TYPE_AAAA 28

#define RESOLVE_RETRY_START_DELAY_SEC 1
#define RESOLVE_RETRY_MAX_DELAY_SEC 20
#define RESOLVE_RETRY_TOTAL_SEC 120

socklen_t sockaddr_size(const struct sockaddr_storage *ss) {
    return ss->ss_family == AF_INET6 ? (socklen_t)sizeof(struct sockaddr_in6)
                                     : (socklen_t)sizeof(struct sockaddr_in);
}

void sockaddr_set_port(struct sockaddr_storage *ss, uint16_t port) {
    if (ss->ss_family == AF_INET6) ((struct sockaddr_in6 *)ss)->sin6_port = htons(port);
    else ((struct sockaddr_in *)ss)->sin_port = htons(port);
}

uint16_t sockaddr_get_port(const struct sockaddr_storage *ss) {
    return ss->ss_family == AF_INET6 ? ntohs(((const struct sockaddr_in6 *)ss)->sin6_port)
                                     : ntohs(((const struct sockaddr_in *)ss)->sin_port);
}

void sockaddr_from_ipv4(struct sockaddr_storage *ss, uint32_t addr_be, uint16_t port) {
    struct sockaddr_in *a = (struct sockaddr_in *)ss;
    memset(ss, 0, sizeof(*ss));
    a->sin_family = AF_INET;
    a->sin_addr.s_addr = addr_be;
    a->sin_port = htons(port);
}

void sockaddr_any(struct sockaddr_storage *ss, int family, uint16_t port) {
    memset(ss, 0, sizeof(*ss));
    ss->ss_family = (sa_family_t)family;
    sockaddr_set_port(ss, port);
}

int sockaddr_map_to_ipv6(const struct sockaddr_storage *in, struct sockaddr_storage *out) {
    if (in->ss_family == AF_INET6) {
        if (out != in) *out = *in;
        return 0;
    }
    if (in->ss_family != AF_INET) return -1;
    uint32_t v4 = ((const struct sockaddr_in *)in)->sin_addr.s_addr;
    uint16_t port = ((const struct sockaddr_in *)in)->sin_port;
    struct sockaddr_in6 *a = (struct sockaddr_in6 *)out;
    memset(out, 0, sizeof(*out));
    a->sin6_family = AF_INET6;
    a->sin6_port = port;
    a->sin6_addr.s6_addr[10] = 0xFF;
    a->sin6_addr.s6_addr[11] = 0xFF;
    memcpy(a->sin6_addr.s6_addr + 12, &v4, 4);
    return 0;
}

const char *sockaddr_text(const struct sockaddr_storage *ss, char *buf, size_t cap) {
    char ip[INET6_ADDRSTRLEN];
    if (ss->ss_family == AF_INET6) {
        const struct sockaddr_in6 *a = (const struct sockaddr_in6 *)ss;
        if (!inet_ntop(AF_INET6, &a->sin6_addr, ip, sizeof(ip))) ip[0] = 0;
        snprintf(buf, cap, "[%s]:%u", ip, ntohs(a->sin6_port));
    } else {
        const struct sockaddr_in *a = (const struct sockaddr_in *)ss;
        if (!inet_ntop(AF_INET, &a->sin_addr, ip, sizeof(ip))) ip[0] = 0;
        snprintf(buf, cap, "%s:%u", ip, ntohs(a->sin_port));
    }
    return buf;
}

int split_host_port(char *spec, char **host, int *port) {
    if (!spec || !*spec) return -1;
    char *port_text;
    if (*spec == '[') {
        char *end = strchr(spec, ']');
        if (!end || end[1] != ':') return -1;
        *end = 0;
        *host = spec + 1;
        port_text = end + 2;
    } else {
        char *colon = strrchr(spec, ':');
        if (!colon || colon == spec) return -1;
        *colon = 0;
        *host = spec;
        port_text = colon + 1;
    }
    char *endp = NULL;
    long value = strtol(port_text, &endp, 10);
    if (!endp || *endp || value <= 0 || value > 65535) return -1;
    *port = (int)value;
    return **host ? 0 : -1;
}

static int resolved_has_family(const resolved_host_t *r, int family) {
    for (int i = 0; i < r->count; i++) {
        if (r->addr[i].ss_family == family) return 1;
    }
    return 0;
}

static void resolved_add(resolved_host_t *r, int family, const void *addr) {
    if (r->count >= RESOLVED_MAX || resolved_has_family(r, family)) return;
    struct sockaddr_storage *ss = &r->addr[r->count];
    memset(ss, 0, sizeof(*ss));
    if (family == AF_INET6) {
        struct sockaddr_in6 *a = (struct sockaddr_in6 *)ss;
        a->sin6_family = AF_INET6;
        memcpy(&a->sin6_addr, addr, 16);
    } else {
        struct sockaddr_in *a = (struct sockaddr_in *)ss;
        a->sin_family = AF_INET;
        memcpy(&a->sin_addr, addr, 4);
    }
    r->count++;
}

static int ipv6_egress_usable(void) {
    static int cached = -1;
    int known = __atomic_load_n(&cached, __ATOMIC_RELAXED);
    if (known >= 0) return known;

    int usable = 0;
    int sock = socket(AF_INET6, SOCK_DGRAM, 0);
    if (sock >= 0) {
        struct sockaddr_in6 probe;
        memset(&probe, 0, sizeof(probe));
        probe.sin6_family = AF_INET6;
        probe.sin6_port = htons(DNS_PORT);
        inet_pton(AF_INET6, "2000::", &probe.sin6_addr);
        if (connect(sock, (struct sockaddr *)&probe, sizeof(probe)) == 0) {
            struct sockaddr_in6 local;
            socklen_t len = sizeof(local);
            if (getsockname(sock, (struct sockaddr *)&local, &len) == 0 &&
                !IN6_IS_ADDR_UNSPECIFIED(&local.sin6_addr) &&
                !IN6_IS_ADDR_LINKLOCAL(&local.sin6_addr) &&
                !IN6_IS_ADDR_LOOPBACK(&local.sin6_addr)) {
                usable = 1;
            }
        }
        close(sock);
    }
    __atomic_store_n(&cached, usable, __ATOMIC_RELAXED);
    return usable;
}

static void resolved_order(resolved_host_t *r) {
    if (r->count < 2) return;
    int preferred = ipv6_egress_usable() ? AF_INET6 : AF_INET;
    if (r->addr[0].ss_family != preferred) {
        struct sockaddr_storage tmp = r->addr[0];
        r->addr[0] = r->addr[1];
        r->addr[1] = tmp;
    }
}

static void hosts_lookup(const char *host, int family, resolved_host_t *out) {
    FILE *f = fopen("/etc/hosts", "r");
    if (!f) return;
    char line[1024];
    while (out->count < RESOLVED_MAX && fgets(line, sizeof(line), f)) {
        char *hash = strchr(line, '#');
        if (hash) *hash = 0;
        char *save = NULL;
        char *ip = strtok_r(line, " \t\r\n", &save);
        if (!ip) continue;
        uint8_t raw[16];
        int entry_family;
        if (inet_pton(AF_INET, ip, raw) == 1) entry_family = AF_INET;
        else if (inet_pton(AF_INET6, ip, raw) == 1) entry_family = AF_INET6;
        else continue;
        if (family != AF_UNSPEC && family != entry_family) continue;
        char *name;
        while ((name = strtok_r(NULL, " \t\r\n", &save)) != NULL) {
            if (strcasecmp(name, host) == 0) {
                resolved_add(out, entry_family, raw);
                break;
            }
        }
    }
    fclose(f);
}

static int read_nameservers(struct sockaddr_storage *servers, int max) {
    FILE *f = fopen("/etc/resolv.conf", "r");
    if (!f) return 0;
    char line[512];
    int n = 0;
    while (n < max && fgets(line, sizeof(line), f)) {
        char *save = NULL;
        char *kw = strtok_r(line, " \t\r\n", &save);
        if (!kw || strcmp(kw, "nameserver") != 0) continue;
        char *ip = strtok_r(NULL, " \t\r\n", &save);
        if (!ip) continue;
        struct sockaddr_storage *ss = &servers[n];
        memset(ss, 0, sizeof(*ss));
        if (inet_pton(AF_INET, ip, &((struct sockaddr_in *)ss)->sin_addr) == 1) {
            ss->ss_family = AF_INET;
        } else if (inet_pton(AF_INET6, ip, &((struct sockaddr_in6 *)ss)->sin6_addr) == 1) {
            ss->ss_family = AF_INET6;
        } else {
            continue;
        }
        sockaddr_set_port(ss, DNS_PORT);
        n++;
    }
    fclose(f);
    return n;
}

static int encode_qname(uint8_t *out, int out_size, const char *host) {
    int pos = 0;
    const char *label = host;
    while (*label) {
        const char *dot = strchr(label, '.');
        int len = dot ? (int)(dot - label) : (int)strlen(label);
        if (len <= 0 || len > 63 || pos + len + 1 >= out_size) return -1;
        out[pos++] = (uint8_t)len;
        memcpy(out + pos, label, len);
        pos += len;
        if (!dot) break;
        label = dot + 1;
    }
    if (pos + 1 >= out_size) return -1;
    out[pos++] = 0;
    return pos;
}

static int skip_name(const uint8_t *buf, int len, int pos) {
    while (pos < len) {
        uint8_t b = buf[pos];
        if ((b & 0xC0) == 0xC0) return pos + 2;
        if (b == 0) return pos + 1;
        pos += b + 1;
    }
    return -1;
}

static int build_query(uint8_t *out, int cap, const char *host, uint16_t id, uint16_t qtype) {
    if (cap < 16) return -1;
    out[0] = id >> 8;
    out[1] = id & 0xFF;
    out[2] = 0x01;
    out[3] = 0x00;
    out[4] = 0x00;
    out[5] = 0x01;
    memset(out + 6, 0, 6);
    int qlen = encode_qname(out + 12, cap - 12 - 4, host);
    if (qlen < 0) return -1;
    int pos = 12 + qlen;
    out[pos++] = (qtype >> 8) & 0xFF;
    out[pos++] = qtype & 0xFF;
    out[pos++] = 0x00;
    out[pos++] = 0x01;
    return pos;
}

static int parse_answer(const uint8_t *buf, int len, int *family, uint8_t *addr) {
    if (len < 12) return -1;
    if (buf[3] & 0x0F) return -1;
    int qd = (buf[4] << 8) | buf[5];
    int an = (buf[6] << 8) | buf[7];
    int pos = 12;
    for (int i = 0; i < qd; i++) {
        pos = skip_name(buf, len, pos);
        if (pos < 0) return -1;
        pos += 4;
    }
    for (int i = 0; i < an && pos + 10 <= len; i++) {
        pos = skip_name(buf, len, pos);
        if (pos < 0 || pos + 10 > len) return -1;
        int type = (buf[pos] << 8) | buf[pos + 1];
        int rdlen = (buf[pos + 8] << 8) | buf[pos + 9];
        pos += 10;
        if (pos + rdlen > len) return -1;
        if (type == DNS_TYPE_A && rdlen == 4) {
            memcpy(addr, buf + pos, 4);
            *family = AF_INET;
            return 0;
        }
        if (type == DNS_TYPE_AAAA && rdlen == 16) {
            memcpy(addr, buf + pos, 16);
            *family = AF_INET6;
            return 0;
        }
        pos += rdlen;
    }
    return -1;
}

typedef struct {
    uint16_t id;
    uint16_t type;
    int answered;
} dns_question_t;

static int dns_lookup(const char *host, int family, resolved_host_t *out) {
    struct sockaddr_storage servers[DNS_MAX_NS];
    int ns_count = read_nameservers(servers, DNS_MAX_NS);
    if (ns_count == 0) return -1;

    uint16_t base_id = (uint16_t)(time(NULL) ^ (uintptr_t)host);
    dns_question_t questions[2];
    int question_count = 0;
    if (family == AF_UNSPEC || family == AF_INET6) {
        questions[question_count++] = (dns_question_t){ (uint16_t)(base_id ^ 0xA6A6), DNS_TYPE_AAAA, 0 };
    }
    if (family == AF_UNSPEC || family == AF_INET) {
        questions[question_count++] = (dns_question_t){ (uint16_t)(base_id ^ 0x1414), DNS_TYPE_A, 0 };
    }

    uint8_t packet[DNS_BUF_SIZE];
    for (int s = 0; s < ns_count; s++) {
        int sock = socket(servers[s].ss_family, SOCK_DGRAM, 0);
        if (sock < 0) continue;
        struct timeval tv = { .tv_sec = DNS_TIMEOUT_SEC, .tv_usec = 0 };
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
        if (connect(sock, (struct sockaddr *)&servers[s], sockaddr_size(&servers[s])) != 0) {
            close(sock);
            continue;
        }

        int pending = 0;
        for (int i = 0; i < question_count; i++) {
            if (questions[i].answered) continue;
            int qlen = build_query(packet, sizeof(packet), host, questions[i].id, questions[i].type);
            if (qlen < 0) {
                close(sock);
                return -1;
            }
            if (send(sock, packet, qlen, 0) == qlen) pending++;
        }

        while (pending > 0) {
            int rlen = (int)recv(sock, packet, sizeof(packet), 0);
            if (rlen < 12) break;
            uint16_t rid = (uint16_t)((packet[0] << 8) | packet[1]);
            for (int i = 0; i < question_count; i++) {
                if (questions[i].answered || questions[i].id != rid) continue;
                questions[i].answered = 1;
                pending--;
                int answer_family;
                uint8_t raw[16];
                if (parse_answer(packet, rlen, &answer_family, raw) == 0) {
                    resolved_add(out, answer_family, raw);
                }
                break;
            }
        }
        close(sock);
        if (out->count > 0) return 0;
    }
    return out->count > 0 ? 0 : -1;
}

int resolve_host(const char *host, int family, resolved_host_t *out) {
    if (!host || !*host || !out) return -1;
    out->count = 0;

    uint8_t raw[16];
    if ((family == AF_UNSPEC || family == AF_INET) && inet_pton(AF_INET, host, raw) == 1) {
        resolved_add(out, AF_INET, raw);
        return 0;
    }
    if ((family == AF_UNSPEC || family == AF_INET6) && inet_pton(AF_INET6, host, raw) == 1) {
        resolved_add(out, AF_INET6, raw);
        return 0;
    }

    hosts_lookup(host, family, out);
    if (out->count == 0 && dns_lookup(host, family, out) != 0) return -1;
    resolved_order(out);
    return out->count > 0 ? 0 : -1;
}

int resolve_ipv4(const char *host, struct in_addr *out) {
    resolved_host_t resolved;
    if (resolve_host(host, AF_INET, &resolved) != 0) return -1;
    *out = ((struct sockaddr_in *)&resolved.addr[0])->sin_addr;
    return 0;
}

static int sleep_interruptible(int seconds, const volatile sig_atomic_t *stop) {
    for (int i = 0; i < seconds; i++) {
        if (stop && *stop) return -1;
        sleep(1);
    }
    return (stop && *stop) ? -1 : 0;
}

int resolve_host_wait(const char *host, int family, resolved_host_t *out, const volatile sig_atomic_t *stop) {
    int delay = RESOLVE_RETRY_START_DELAY_SEC;
    int waited = 0;
    for (;;) {
        if (resolve_host(host, family, out) == 0) return 0;
        if (stop && *stop) return -1;
        if (waited >= RESOLVE_RETRY_TOTAL_SEC) {
            log(LL_ERROR, "Can't resolve '%s': DNS/network still unavailable after %d seconds of retries", host, waited);
            return -1;
        }
        log(LL_WARN, "Can't resolve '%s' (network not ready?), retrying in %d s", host, delay);
        if (sleep_interruptible(delay, stop) != 0) return -1;
        waited += delay;
        delay *= 2;
        if (delay > RESOLVE_RETRY_MAX_DELAY_SEC) delay = RESOLVE_RETRY_MAX_DELAY_SEC;
    }
}

int resolve_ipv4_wait(const char *host, struct in_addr *out, const volatile sig_atomic_t *stop) {
    resolved_host_t resolved;
    if (resolve_host_wait(host, AF_INET, &resolved, stop) != 0) return -1;
    *out = ((struct sockaddr_in *)&resolved.addr[0])->sin_addr;
    return 0;
}
