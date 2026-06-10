#ifndef _RESOLVE_H_
#define _RESOLVE_H_

#include <netinet/in.h>

int resolve_ipv4(const char *host, struct in_addr *out);

#endif
