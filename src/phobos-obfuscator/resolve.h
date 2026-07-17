#ifndef _RESOLVE_H_
#define _RESOLVE_H_

#include <netinet/in.h>
#include <signal.h>

int resolve_ipv4(const char *host, struct in_addr *out);
int resolve_ipv4_wait(const char *host, struct in_addr *out, const volatile sig_atomic_t *stop);

#endif
