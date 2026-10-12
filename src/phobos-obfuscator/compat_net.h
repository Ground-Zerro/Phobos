#ifndef _COMPAT_NET_H_
#define _COMPAT_NET_H_

#ifdef _WIN32
#include <winsock2.h>
#include <ws2tcpip.h>
#else
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#endif

typedef struct {
    char s[INET_ADDRSTRLEN];
} ipv4_text_t;

static inline ipv4_text_t ipv4_text(struct in_addr addr) {
    ipv4_text_t text;
    if (!inet_ntop(AF_INET, &addr, text.s, sizeof(text.s))) text.s[0] = 0;
    return text;
}

#endif
