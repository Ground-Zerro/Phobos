#include <stdint.h>
#include <string.h>
#include <stdio.h>
#include "socks5_proto.h"

int socks5_parse_greeting(const uint8_t *buf, int len) {
    if (len < 1) return 0;
    if (buf[0] != 0x05) return -1;
    if (len < 2) return 0;
    int n = buf[1];
    int total = 2 + n;
    if (len < total) return 0;
    return total;
}

int socks5_greeting_methods(const uint8_t *buf, int len, const uint8_t **methods, int *count) {
    if (len < 2) return -1;
    if (buf[0] != 0x05) return -1;
    int n = buf[1];
    if (len < 2 + n) return -1;
    *methods = buf + 2;
    *count = n;
    return 0;
}

int socks5_build_method(uint8_t *out, uint8_t method) {
    out[0] = 0x05;
    out[1] = method;
    return 2;
}

int socks5_parse_userpass(const uint8_t *buf, int len,
                          char *login, int *login_len,
                          char *password, int *password_len) {
    if (len < 2) return 0;
    if (buf[0] != 0x01) return -1;
    int ulen = buf[1];
    if (len < 2 + ulen + 1) return 0;
    int plen = buf[2 + ulen];
    if (len < 2 + ulen + 1 + plen) return 0;
    memcpy(login, buf + 2, ulen);
    *login_len = ulen;
    memcpy(password, buf + 2 + ulen + 1, plen);
    *password_len = plen;
    return 2 + ulen + 1 + plen;
}

int socks5_build_userpass_reply(uint8_t *out, uint8_t status) {
    out[0] = 0x01;
    out[1] = status;
    return 2;
}

int socks5_parse_target(const uint8_t *buf, int len, int off, socks5_target_t *t) {
    if (len < off + 1) return 0;
    t->atyp = buf[off];
    int p = off + 1;
    if (t->atyp == S5_ATYP_IPV4) {
        if (len < p + 4 + 2) return 0;
        memcpy(t->addr, buf + p, 4);
        t->addrlen = 4;
        p += 4;
    } else if (t->atyp == S5_ATYP_DOMAIN) {
        if (len < p + 1) return 0;
        int dl = buf[p];
        if (len < p + 1 + dl + 2) return 0;
        memcpy(t->addr, buf + p + 1, dl);
        t->addrlen = dl;
        p += 1 + dl;
    } else if (t->atyp == S5_ATYP_IPV6) {
        if (len < p + 16 + 2) return 0;
        memcpy(t->addr, buf + p, 16);
        t->addrlen = 16;
        p += 16;
    } else {
        return -1;
    }
    t->port = (buf[p] << 8) | buf[p + 1];
    return p + 2;
}

int socks5_parse_request(const uint8_t *buf, int len, socks5_target_t *t) {
    if (len < 4) return 0;
    if (buf[0] != 0x05) return -1;
    t->cmd = buf[1];
    int r = socks5_parse_target(buf, len, 3, t);
    return r;
}

int socks5_parse_reply(const uint8_t *buf, int len, uint8_t *rep, socks5_target_t *t) {
    if (len < 4) return 0;
    if (buf[0] != 0x05) return -1;
    *rep = buf[1];
    int r = socks5_parse_target(buf, len, 3, t);
    return r;
}

int socks5_build_reply(uint8_t *out, uint8_t rep) {
    out[0] = 0x05;
    out[1] = rep;
    out[2] = 0x00;
    out[3] = S5_ATYP_IPV4;
    memset(out + 4, 0, 4);
    out[8] = 0;
    out[9] = 0;
    return 10;
}

int socks5_build_reply_addr(uint8_t *out, int cap, uint8_t rep, const struct sockaddr_storage *ss) {
    socks5_target_t t;
    if (socks5_target_from_sockaddr(ss, &t) != 0) return -1;
    if (cap < 3) return -1;
    out[0] = 0x05;
    out[1] = rep;
    out[2] = 0x00;
    int n = socks5_build_target(out + 3, cap - 3, &t);
    if (n < 0) return -1;
    return 3 + n;
}

int socks5_target_to_sockaddr(const socks5_target_t *t, struct sockaddr_storage *out) {
    memset(out, 0, sizeof(*out));
    if (t->atyp == S5_ATYP_IPV4) {
        if (t->addrlen != 4) return -1;
        struct sockaddr_in *a = (struct sockaddr_in *)out;
        a->sin_family = AF_INET;
        memcpy(&a->sin_addr, t->addr, 4);
        a->sin_port = htons(t->port);
        return 0;
    }
    if (t->atyp == S5_ATYP_IPV6) {
        if (t->addrlen != 16) return -1;
        struct sockaddr_in6 *a = (struct sockaddr_in6 *)out;
        a->sin6_family = AF_INET6;
        memcpy(&a->sin6_addr, t->addr, 16);
        a->sin6_port = htons(t->port);
        return 0;
    }
    return -1;
}

int socks5_target_from_sockaddr(const struct sockaddr_storage *ss, socks5_target_t *t) {
    if (ss->ss_family == AF_INET) {
        const struct sockaddr_in *a = (const struct sockaddr_in *)ss;
        t->atyp = S5_ATYP_IPV4;
        memcpy(t->addr, &a->sin_addr, 4);
        t->addrlen = 4;
        t->port = ntohs(a->sin_port);
        return 0;
    }
    if (ss->ss_family == AF_INET6) {
        const struct sockaddr_in6 *a = (const struct sockaddr_in6 *)ss;
        t->port = ntohs(a->sin6_port);
        if (IN6_IS_ADDR_V4MAPPED(&a->sin6_addr)) {
            t->atyp = S5_ATYP_IPV4;
            memcpy(t->addr, a->sin6_addr.s6_addr + 12, 4);
            t->addrlen = 4;
            return 0;
        }
        t->atyp = S5_ATYP_IPV6;
        memcpy(t->addr, &a->sin6_addr, 16);
        t->addrlen = 16;
        return 0;
    }
    return -1;
}

int socks5_udp_parse(const uint8_t *buf, int len, socks5_target_t *t, int *data_off) {
    if (len < 4) return -1;
    if (buf[2] != 0) return -1;
    int r = socks5_parse_target(buf, len, 3, t);
    if (r <= 0) return -1;
    *data_off = r;
    return r;
}

int socks5_build_target(uint8_t *out, int cap, const socks5_target_t *t) {
    int prefix = (t->atyp == S5_ATYP_DOMAIN) ? 1 : 0;
    if (1 + prefix + t->addrlen + 2 > cap) return -1;
    out[0] = t->atyp;
    int p = 1;
    if (prefix) out[p++] = (uint8_t)t->addrlen;
    memcpy(out + p, t->addr, t->addrlen);
    p += t->addrlen;
    out[p] = (t->port >> 8) & 0xFF;
    out[p + 1] = t->port & 0xFF;
    return p + 2;
}

int socks5_udp_build_header(uint8_t *out, int cap, const socks5_target_t *t) {
    if (cap < 3) return -1;
    out[0] = 0;
    out[1] = 0;
    out[2] = 0;
    int n = socks5_build_target(out + 3, cap - 3, t);
    if (n < 0) return -1;
    return 3 + n;
}
