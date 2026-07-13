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

static int parse_addr(const uint8_t *buf, int len, int off, socks5_target_t *t) {
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
    int r = parse_addr(buf, len, 3, t);
    return r;
}

int socks5_parse_reply(const uint8_t *buf, int len, uint8_t *rep, socks5_target_t *t) {
    if (len < 4) return 0;
    if (buf[0] != 0x05) return -1;
    *rep = buf[1];
    int r = parse_addr(buf, len, 3, t);
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

int socks5_target_host(const socks5_target_t *t, char *host, int host_cap) {
    if (t->atyp == S5_ATYP_IPV4) {
        if (t->addrlen != 4) return -1;
        snprintf(host, host_cap, "%u.%u.%u.%u", t->addr[0], t->addr[1], t->addr[2], t->addr[3]);
        return 0;
    }
    if (t->atyp == S5_ATYP_DOMAIN) {
        if (t->addrlen <= 0 || t->addrlen >= host_cap) return -1;
        memcpy(host, t->addr, t->addrlen);
        host[t->addrlen] = 0;
        return 0;
    }
    return -1;
}

int socks5_udp_parse(const uint8_t *buf, int len, socks5_target_t *t, int *data_off) {
    if (len < 4) return -1;
    if (buf[2] != 0) return -1;
    int r = parse_addr(buf, len, 3, t);
    if (r <= 0) return -1;
    *data_off = r;
    return r;
}

int socks5_udp_build_header(uint8_t *out, const socks5_target_t *t) {
    out[0] = 0;
    out[1] = 0;
    out[2] = 0;
    out[3] = t->atyp;
    memcpy(out + 4, t->addr, t->addrlen);
    int p = 4 + t->addrlen;
    out[p] = (t->port >> 8) & 0xFF;
    out[p + 1] = t->port & 0xFF;
    return p + 2;
}
