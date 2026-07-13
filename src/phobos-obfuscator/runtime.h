#ifndef _RUNTIME_H_
#define _RUNTIME_H_

long now_ms(void);
int read_long_file(const char *path, long *out);
int detect_topology(int *order, int max);
int cgroup_cpu_limit(void);
void pin_to_cpu(int cpu);

#endif
