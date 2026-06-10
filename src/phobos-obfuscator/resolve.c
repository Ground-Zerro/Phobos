#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <ctype.h>
#include <unistd.h>
#include <time.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <sys/time.h>
#include "resolve.h"

#define DNS_PORT 53
#define DNS_MAX_NS 4
#define DNS_TIMEOUT_SEC 3
#define DNS_BUF_SIZE 1500

static int parse_hosts_file(const char *host, struct in_addr *out) {
    FILE *f = fopen("/etc/hosts", "r");
    if (!f) return -1;
    char line[1024];
    int found = -1;
    while (found != 0 && fgets(line, sizeof(line), f)) {
        char *hash = strchr(line, '#');
        if (hash) *hash = 0;
        char *save = NULL;
        char *ip = strtok_r(line, " \t\r\n", &save);
        if (!ip) continue;
        struct in_addr addr;
        if (inet_pton(AF_INET, ip, &addr) != 1) continue;
        char *name;
        while ((name = strtok_r(NULL, " \t\r\n", &save)) != NULL) {
            if (strcasecmp(name, host) == 0) {
                *out = addr;
                found = 0;
                break;
            }
        }
    }
    fclose(f);
    return found;
}

static int read_nameservers(struct in_addr *servers, int max) {
    FILE *f = fopen("/etc/resolv.conf", "r");
    if (!f) return 0;
    char line[512];
    int n = 0;
    while (n < max && fgets(line, sizeof(line), f)) {
        char *save = NULL;
        char *kw = strtok_r(line, " \t\r\n", &save);
        if (!kw || strcmp(kw, "nameserver") != 0) continue;
        char *ip = strtok_r(NULL, " \t\r\n", &save);
        if (ip && inet_pton(AF_INET, ip, &servers[n]) == 1) n++;
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

static int parse_response(const uint8_t *buf, int len, uint16_t id, struct in_addr *out) {
    if (len < 12) return -1;
    if (((buf[0] << 8) | buf[1]) != id) return -1;
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
        if (type == 1 && rdlen == 4) {
            memcpy(&out->s_addr, buf + pos, 4);
            return 0;
        }
        pos += rdlen;
    }
    return -1;
}

static int dns_query(const char *host, struct in_addr *out) {
    struct in_addr servers[DNS_MAX_NS];
    int ns_count = read_nameservers(servers, DNS_MAX_NS);
    if (ns_count == 0) return -1;

    uint8_t query[DNS_BUF_SIZE];
    uint16_t id = (uint16_t)(time(NULL) ^ (uintptr_t)host);
    query[0] = id >> 8;
    query[1] = id & 0xFF;
    query[2] = 0x01;
    query[3] = 0x00;
    query[4] = 0x00; query[5] = 0x01;
    query[6] = query[7] = query[8] = query[9] = query[10] = query[11] = 0x00;
    int qlen = encode_qname(query + 12, sizeof(query) - 12 - 4, host);
    if (qlen < 0) return -1;
    int pos = 12 + qlen;
    query[pos++] = 0x00; query[pos++] = 0x01;
    query[pos++] = 0x00; query[pos++] = 0x01;

    for (int s = 0; s < ns_count; s++) {
        int sock = socket(AF_INET, SOCK_DGRAM, 0);
        if (sock < 0) continue;
        struct timeval tv = { .tv_sec = DNS_TIMEOUT_SEC, .tv_usec = 0 };
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
        struct sockaddr_in addr;
        memset(&addr, 0, sizeof(addr));
        addr.sin_family = AF_INET;
        addr.sin_port = htons(DNS_PORT);
        addr.sin_addr = servers[s];
        if (connect(sock, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
            close(sock);
            continue;
        }
        if (send(sock, query, pos, 0) != pos) {
            close(sock);
            continue;
        }
        uint8_t resp[DNS_BUF_SIZE];
        int rlen = recv(sock, resp, sizeof(resp), 0);
        close(sock);
        if (rlen > 0 && parse_response(resp, rlen, id, out) == 0) {
            return 0;
        }
    }
    return -1;
}

int resolve_ipv4(const char *host, struct in_addr *out) {
    if (!host || !*host) return -1;
    if (inet_pton(AF_INET, host, out) == 1) return 0;
    if (parse_hosts_file(host, out) == 0) return 0;
    return dns_query(host, out);
}
