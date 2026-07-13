#ifndef _SOCKS5_PROTO_H_
#define _SOCKS5_PROTO_H_

#include <stdint.h>

#define S5_CMD_CONNECT     0x01
#define S5_CMD_UDP         0x03
#define S5_ATYP_IPV4       0x01
#define S5_ATYP_DOMAIN     0x03
#define S5_ATYP_IPV6       0x04
#define S5_REP_OK          0x00
#define S5_REP_FAIL        0x01
#define S5_REP_NOTSUP      0x07
#define S5_METHOD_NOAUTH   0x00
#define S5_METHOD_USERPASS 0x02
#define S5_METHOD_NONE     0xFF

// Max length of a RFC1929 username/password field (protocol allows up to 255).
#define S5_CRED_MAX 256

typedef struct {
    uint8_t cmd;
    uint8_t atyp;
    uint8_t addr[256];
    int addrlen;
    uint16_t port;
} socks5_target_t;

int socks5_parse_greeting(const uint8_t *buf, int len);
int socks5_greeting_methods(const uint8_t *buf, int len, const uint8_t **methods, int *count);
int socks5_build_method(uint8_t *out, uint8_t method);
int socks5_parse_request(const uint8_t *buf, int len, socks5_target_t *t);
int socks5_parse_reply(const uint8_t *buf, int len, uint8_t *rep, socks5_target_t *t);
int socks5_build_reply(uint8_t *out, uint8_t rep);

int socks5_parse_userpass(const uint8_t *buf, int len,
                          char *login, int *login_len,
                          char *password, int *password_len);
int socks5_build_userpass_reply(uint8_t *out, uint8_t status);

int socks5_target_host(const socks5_target_t *t, char *host, int host_cap);

int socks5_udp_parse(const uint8_t *buf, int len, socks5_target_t *t, int *data_off);
int socks5_udp_build_header(uint8_t *out, const socks5_target_t *t);

#endif
