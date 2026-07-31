#ifndef _RESOLVE_H_
#define _RESOLVE_H_

#include "compat_net.h"
#include <signal.h>
#include <stdint.h>
#include <stddef.h>

#define RESOLVED_MAX 2

typedef struct {
    struct sockaddr_storage addr[RESOLVED_MAX];
    int count;
} resolved_host_t;

int resolve_ipv4(const char *host, struct in_addr *out);
int resolve_ipv4_wait(const char *host, struct in_addr *out, const volatile sig_atomic_t *stop);

int resolve_host(const char *host, int family, resolved_host_t *out);
int resolve_host_wait(const char *host, int family, resolved_host_t *out, const volatile sig_atomic_t *stop);

int split_host_port(char *spec, char **host, int *port);

socklen_t sockaddr_size(const struct sockaddr_storage *ss);
void sockaddr_set_port(struct sockaddr_storage *ss, uint16_t port);
uint16_t sockaddr_get_port(const struct sockaddr_storage *ss);
void sockaddr_from_ipv4(struct sockaddr_storage *ss, uint32_t addr_be, uint16_t port);
void sockaddr_any(struct sockaddr_storage *ss, int family, uint16_t port);
int sockaddr_map_to_ipv6(const struct sockaddr_storage *in, struct sockaddr_storage *out);
const char *sockaddr_text(const struct sockaddr_storage *ss, char *buf, size_t cap);

#endif
