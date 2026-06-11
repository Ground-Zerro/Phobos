#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <signal.h>
#include <time.h>
#include "wg-obfuscator.h"
#include "config.h"
#include "obfuscation.h"
#include "masking.h"
#include "threading.h"
#include "resolve.h"

int verbose = LL_DEFAULT;
char section_name[256] = DEFAULT_INSTANCE_NAME;

static threading_context_t threading_ctx = {0};
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
        if (resolve_ipv4(binding, &client_ip) != 0) {
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

    if (!config.listen_port_set) {
        log(LL_ERROR, "'source-lport' is not set");
        exit(EXIT_FAILURE);
    }
    if (!config.forward_host_port_set) {
        log(LL_ERROR, "'target' is not set");
        exit(EXIT_FAILURE);
    }
    if (!config.xor_key_set) {
        log(LL_ERROR, "'key' is not set");
        exit(EXIT_FAILURE);
    }

    char *port_delimiter = strchr(config.forward_host_port, ':');
    if (port_delimiter == NULL) {
        log(LL_ERROR, "Invalid target host:port format: %s", config.forward_host_port);
        exit(EXIT_FAILURE);
    }
    *port_delimiter = 0;
    strncpy(target_host, config.forward_host_port, sizeof(target_host) - 1);
    target_host[sizeof(target_host) - 1] = 0;
    target_port = atoi(port_delimiter + 1);
    if (target_port <= 0 || target_port > 65535) {
        log(LL_ERROR, "Invalid target port: %s", port_delimiter + 1);
        exit(EXIT_FAILURE);
    }

    key_length = strlen(config.xor_key);
    if (key_length == 0) {
        log(LL_ERROR, "Key is not set");
        exit(EXIT_FAILURE);
    }

    if (config.client_interface_set) {
        struct in_addr a;
        if (resolve_ipv4(config.client_interface, &a) != 0) {
            log(LL_ERROR, "Invalid source interface '%s'", config.client_interface);
            exit(EXIT_FAILURE);
        }
        listen_addr = a.s_addr;
    }

    memset(&forward_addr, 0, sizeof(forward_addr));
    forward_addr.sin_family = AF_INET;
    if (resolve_ipv4(target_host, &forward_addr.sin_addr) != 0) {
        log(LL_ERROR, "Can't resolve hostname '%s'", target_host);
        exit(EXIT_FAILURE);
    }
    forward_addr.sin_port = htons(target_port);

    log(LL_INFO, "Listening on %s:%d", inet_ntoa(*(struct in_addr *)&listen_addr), config.listen_port);
    log(LL_INFO, "Target: %s:%d", target_host, target_port);
    if (config.masking_handler_set) {
        log(LL_INFO, "Using masking type: %s", config.masking_handler ? config.masking_handler->name : "none");
    }

    parse_static_bindings(&config);

    if (threading_init(&threading_ctx, &config) != 0) {
        log(LL_ERROR, "Failed to initialize threading");
        exit(EXIT_FAILURE);
    }

    signal(SIGINT, on_signal);
    signal(SIGTERM, on_signal);

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
