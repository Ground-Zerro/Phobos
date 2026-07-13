#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <time.h>
#include <sched.h>
#include <pthread.h>
#include "runtime.h"

typedef struct {
    int cpu;
    int sibling_index;
} cpu_slot_t;

long now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

int read_long_file(const char *path, long *out) {
    FILE *f = fopen(path, "r");
    if (!f) return -1;
    long v;
    int r = fscanf(f, "%ld", &v);
    fclose(f);
    if (r != 1) return -1;
    *out = v;
    return 0;
}

int cgroup_cpu_limit(void) {
    long quota, period;
    FILE *f = fopen("/sys/fs/cgroup/cpu.max", "r");
    if (f) {
        char tok[32];
        if (fscanf(f, "%31s %ld", tok, &period) == 2) {
            fclose(f);
            if (strcmp(tok, "max") == 0 || period <= 0) return 0;
            quota = atol(tok);
            if (quota <= 0) return 0;
            int n = (int)((quota + period - 1) / period);
            return n > 0 ? n : 1;
        }
        fclose(f);
    }
    if (read_long_file("/sys/fs/cgroup/cpu/cpu.cfs_quota_us", &quota) == 0 &&
        read_long_file("/sys/fs/cgroup/cpu/cpu.cfs_period_us", &period) == 0) {
        if (quota <= 0 || period <= 0) return 0;
        int n = (int)((quota + period - 1) / period);
        return n > 0 ? n : 1;
    }
    return 0;
}

static long cpu_core_key(int cpu) {
    char path[128];
    long core = -1, pkg = 0;
    snprintf(path, sizeof(path), "/sys/devices/system/cpu/cpu%d/topology/core_id", cpu);
    read_long_file(path, &core);
    snprintf(path, sizeof(path), "/sys/devices/system/cpu/cpu%d/topology/physical_package_id", cpu);
    read_long_file(path, &pkg);
    if (core < 0) return ((long)cpu) | 0x40000000L;
    return (pkg << 16) | core;
}

int detect_topology(int *order, int max) {
    cpu_set_t set;
    CPU_ZERO(&set);
    if (sched_getaffinity(0, sizeof(set), &set) != 0) {
        long n = sysconf(_SC_NPROCESSORS_ONLN);
        int count = n > 0 ? (int)n : 1;
        if (count > max) count = max;
        for (int i = 0; i < count; i++) order[i] = i;
        return count;
    }

    int avail[CPU_SETSIZE];
    int navail = 0;
    for (int c = 0; c < CPU_SETSIZE && navail < max; c++) {
        if (CPU_ISSET(c, &set)) avail[navail++] = c;
    }
    if (navail == 0) {
        order[0] = 0;
        return 1;
    }

    long keys[CPU_SETSIZE];
    cpu_slot_t slots[CPU_SETSIZE];
    for (int i = 0; i < navail; i++) {
        keys[i] = cpu_core_key(avail[i]);
        int sib = 0;
        for (int j = 0; j < i; j++) {
            if (keys[j] == keys[i]) sib++;
        }
        slots[i].cpu = avail[i];
        slots[i].sibling_index = sib;
    }

    int n = 0;
    int max_sib = 0;
    for (int i = 0; i < navail; i++) {
        if (slots[i].sibling_index > max_sib) max_sib = slots[i].sibling_index;
    }
    for (int s = 0; s <= max_sib; s++) {
        for (int i = 0; i < navail; i++) {
            if (slots[i].sibling_index == s) order[n++] = slots[i].cpu;
        }
    }
    return n;
}

void pin_to_cpu(int cpu) {
    if (cpu < 0) return;
    cpu_set_t set;
    CPU_ZERO(&set);
    CPU_SET(cpu, &set);
    sched_setaffinity(0, sizeof(set), &set);
}
