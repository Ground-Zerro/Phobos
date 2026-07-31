#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "compat_net.h"
#include <unistd.h>
#include <signal.h>
#include <time.h>
#include "wg-obfuscator.h"
#include "config.h"
#include "obfuscation.h"
#include "masking.h"
#include "threading.h"
#include "socks5.h"
#include "socks5_mask.h"
#include "resolve.h"

int verbose = LL_DEFAULT;
char section_name[256] = DEFAULT_INSTANCE_NAME;

static threading_context_t threading_ctx = {0};
static socks5_context_t socks5_ctx = {0};
static volatile sig_atomic_t stop_flag = 0;

static void on_signal(int signal) {
    (void)signal;
    stop_flag = 1;
}

void print_version(void) {
#ifdef COMMIT
#ifndef ARCH
    fprintf(stderr, "Starting PhobosWG (commit " COMMIT " @ " WG_OBFUSCATOR_GIT_REPO ")\n");
#else
    fprintf(stderr, "Starting PhobosWG (commit " COMMIT " @ " WG_OBFUSCATOR_GIT_REPO ") (" ARCH ")\n");
#endif
#else
#ifndef ARCH
    fprintf(stderr, "Starting PhobosWG v" WG_OBFUSCATOR_VERSION "\n");
#else
    fprintf(stderr, "Starting PhobosWG v" WG_OBFUSCATOR_VERSION " (" ARCH ")\n");
#endif
#endif
}

static int is_ipv6_literal(const char *host) {
    struct in6_addr addr;
    return inet_pton(AF_INET6, host, &addr) == 1;
}

static void parse_static_bindings(obfuscator_config_t *config) {
    if (!config->static_bindings[0]) return;

    char *binding = strtok(config->static_bindings, ",");
    while (binding) {
        binding = trim(binding);
        char *colon1 = strchr(binding, ':');
        char *colon2 = colon1 ? strchr(colon1 + 1, ':') : NULL;
        if (!colon1 || !colon2) {
            log(LL_ERROR, "Invalid static binding format: %s", binding);
            exit(EXIT_FAILURE);
        }
        *colon1 = 0;
        *colon2 = 0;

        struct in_addr client_ip;
        if (resolve_ipv4_wait(binding, &client_ip, config->stop) != 0) {
            log(LL_ERROR, "Can't resolve hostname '%s' for static binding", binding);
            exit(EXIT_FAILURE);
        }

        int remote_port = atoi(colon1 + 1);
        int local_port = atoi(colon2 + 1);
        if (remote_port <= 0 || remote_port > 65535 || local_port <= 0 || local_port > 65535) {
            log(LL_ERROR, "Invalid port in static binding '%s:%s:%s'", binding, colon1 + 1, colon2 + 1);
            exit(EXIT_FAILURE);
        }
        if (config->static_spec_count >= MAX_STATIC_BINDINGS) {
            log(LL_ERROR, "Too many static bindings (max %d)", MAX_STATIC_BINDINGS);
            exit(EXIT_FAILURE);
        }
        static_binding_t *s = &config->static_specs[config->static_spec_count++];
        s->client_ip = client_ip;
        s->remote_port = (uint16_t)remote_port;
        s->local_port = (uint16_t)local_port;
        log(LL_INFO, "Static binding: %s:%d <-> local %d <-> target", binding, remote_port, local_port);

        binding = strtok(NULL, ",");
    }
}

int main(int argc, char *argv[]) {
    obfuscator_config_t config;
    struct sockaddr_in forward_addr;
    char target_host[256] = {0};
    int target_port = -1;
    int key_length = 0;
    in_addr_t listen_addr = INADDR_ANY;

    print_version();

    if (parse_config(argc, argv, &config) != 0) {
        exit(EXIT_FAILURE);
    }
    config.stop = &stop_flag;

    signal(SIGINT, on_signal);
    signal(SIGTERM, on_signal);
    signal(SIGPIPE, SIG_IGN);

    int target_required = !(config.mode == MODE_SOCKS5 && config.socks5_role == S5_ROLE_SERVER);

    if (!config.listen_port_set) {
        log(LL_ERROR, "'source-lport' is not set");
        exit(EXIT_FAILURE);
    }
    if (target_required && !config.forward_host_port_set) {
        log(LL_ERROR, "'target' is not set");
        exit(EXIT_FAILURE);
    }
    if (!config.xor_key_set) {
        log(LL_ERROR, "'key' is not set");
        exit(EXIT_FAILURE);
    }
    if (config.mode == MODE_WIREGUARD && config.socks5_mask == S5_MASK_TLS) {
        log(LL_ERROR, "TLS masking is only available in socks5 mode");
        exit(EXIT_FAILURE);
    }

    memset(&forward_addr, 0, sizeof(forward_addr));
    forward_addr.sin_family = AF_INET;

    int socks5_mode = config.mode == MODE_SOCKS5;

    if (config.forward_host_port_set) {
        char *host;
        if (split_host_port(config.forward_host_port, &host, &target_port) != 0) {
            log(LL_ERROR, "Invalid target host:port format: %s (IPv6 as [addr]:port)", config.forward_host_port);
            exit(EXIT_FAILURE);
        }
        strncpy(target_host, host, sizeof(target_host) - 1);
        target_host[sizeof(target_host) - 1] = 0;
        if (socks5_mode) {
            if (resolve_host_wait(target_host, AF_UNSPEC, &config.resolved_forward, config.stop) != 0) {
                log(LL_ERROR, "Can't resolve target hostname '%s', exiting", target_host);
                exit(EXIT_FAILURE);
            }
            config.resolved_forward_set = 1;
        } else if (is_ipv6_literal(target_host)) {
            log(LL_ERROR, "IPv6 target '%s' requires socks5 mode", target_host);
            exit(EXIT_FAILURE);
        } else if (resolve_ipv4_wait(target_host, &forward_addr.sin_addr, config.stop) != 0) {
            log(LL_ERROR, "Can't resolve target hostname '%s', exiting", target_host);
            exit(EXIT_FAILURE);
        }
        forward_addr.sin_port = htons(target_port);
    }

    key_length = strlen(config.xor_key);
    if (key_length == 0) {
        log(LL_ERROR, "Key is not set");
        exit(EXIT_FAILURE);
    }

    if (config.client_interface_set) {
        if (socks5_mode) {
            resolved_host_t bind_to;
            if (resolve_host_wait(config.client_interface, AF_UNSPEC, &bind_to, config.stop) != 0) {
                log(LL_ERROR, "Invalid source interface '%s'", config.client_interface);
                exit(EXIT_FAILURE);
            }
            config.resolved_listen = bind_to.addr[0];
            config.resolved_listen_set = 1;
        } else if (is_ipv6_literal(config.client_interface)) {
            log(LL_ERROR, "IPv6 source interface '%s' requires socks5 mode", config.client_interface);
            exit(EXIT_FAILURE);
        } else {
            struct in_addr a;
            if (resolve_ipv4_wait(config.client_interface, &a, config.stop) != 0) {
                log(LL_ERROR, "Invalid source interface '%s'", config.client_interface);
                exit(EXIT_FAILURE);
            }
            listen_addr = a.s_addr;
        }
    } else if (socks5_mode) {
        sockaddr_any(&config.resolved_listen, AF_INET6, 0);
        config.resolved_listen_set = 1;
    }

    if (config.resolved_listen_set) {
        char text[INET6_ADDRSTRLEN + 8];
        struct sockaddr_storage shown = config.resolved_listen;
        sockaddr_set_port(&shown, (uint16_t)config.listen_port);
        log(LL_INFO, "Listening on %s", sockaddr_text(&shown, text, sizeof(text)));
    } else {
        log(LL_INFO, "Listening on %s:%d", inet_ntoa(*(struct in_addr *)&listen_addr), config.listen_port);
    }
    if (config.resolved_forward_set) {
        char text[INET6_ADDRSTRLEN + 8];
        struct sockaddr_storage shown = config.resolved_forward.addr[0];
        sockaddr_set_port(&shown, (uint16_t)target_port);
        log(LL_INFO, "Target: %s (%s)", target_host, sockaddr_text(&shown, text, sizeof(text)));
    } else if (config.forward_host_port_set) {
        log(LL_INFO, "Target: %s:%d", target_host, target_port);
    }

    if (config.mode == MODE_SOCKS5) {
        static const char *mask_names[] = { "none", "STUN", "MEDIA", "TLS" };
        static const char *role_names[] = { "relay", "client", "server" };
        log(LL_INFO, "SOCKS5 role: %s, masking: %s",
            role_names[config.socks5_role], mask_names[config.socks5_mask]);
        if (socks5_init(&socks5_ctx, &config) != 0) {
            log(LL_ERROR, "Failed to initialize SOCKS5 engine");
            exit(EXIT_FAILURE);
        }
        if (socks5_start(&socks5_ctx, &config, config.xor_key, key_length, &forward_addr,
                         listen_addr, (uint16_t)config.listen_port) != 0) {
            log(LL_ERROR, "Failed to start SOCKS5 engine");
            socks5_shutdown(&socks5_ctx);
            exit(EXIT_FAILURE);
        }
        log(LL_INFO, "SOCKS5 obfuscator successfully started");

        while (!stop_flag) {
            struct timespec ts = { .tv_sec = 1, .tv_nsec = 0 };
            nanosleep(&ts, NULL);
        }

        log(LL_INFO, "Stopping...");
        socks5_shutdown(&socks5_ctx);
        socks5_join(&socks5_ctx);
        log(LL_INFO, "Stopped.");
        return 0;
    }

    if (config.masking_handler_set) {
        log(LL_INFO, "Using masking type: %s", config.masking_handler ? config.masking_handler->name : "none");
    }

    parse_static_bindings(&config);

    if (threading_init(&threading_ctx, &config) != 0) {
        log(LL_ERROR, "Failed to initialize threading");
        exit(EXIT_FAILURE);
    }

    if (threading_start(&threading_ctx, &config, config.xor_key, key_length, &forward_addr,
                        listen_addr, (uint16_t)config.listen_port) != 0) {
        log(LL_ERROR, "Failed to start worker threads");
        threading_shutdown(&threading_ctx);
        exit(EXIT_FAILURE);
    }

    log(LL_INFO, "WireGuard obfuscator successfully started");

    while (!stop_flag) {
        struct timespec ts = { .tv_sec = 1, .tv_nsec = 0 };
        nanosleep(&ts, NULL);
    }

    log(LL_INFO, "Stopping...");
    threading_shutdown(&threading_ctx);
    threading_join(&threading_ctx);
    log(LL_INFO, "Stopped.");
    return 0;
}
