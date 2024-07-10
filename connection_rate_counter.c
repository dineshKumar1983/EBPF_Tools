#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/resource.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <bpf/libbpf.h>
#include <bpf/bpf.h>
#include <time.h>
#include "uthash.h"
#include "connection_rate_counter.skel.h"

static volatile sig_atomic_t exiting = 0;
static struct connection_rate_counter_bpf *skel;


static void sig_handler(int sig)
{
    exiting = 1;
}

// Define a struct for storing IP stats in the hashmap
struct ip_stats {
    __be32 ip;
    __u64 prev_count;
    time_t prev_time;
    UT_hash_handle hh;  // Makes this structure hashable
};

static struct ip_stats *stats_map = NULL; // Hashmap to store IP stats

void printstats(void)
{
    int fd = -1;
    time_t curr_time;
    __u64 value;
    double rate;

    while (!exiting) {
        if (fd < 0) {
            fd = bpf_map__fd(skel->maps.connreq_count_map);
            if (fd < 0) {
                fprintf(stderr, "Failed to get map file descriptor\n");
                break;
            }
        }

        __be32 prev_key = 0, key;
        struct ip_stats *stats_entry = NULL;

        curr_time = time(NULL);

        while (bpf_map_get_next_key(fd, prev_key ? &prev_key : NULL, &key) == 0) {
            if (bpf_map_lookup_elem(fd, &key, &value) == 0) {
                char ip_str[INET_ADDRSTRLEN];
                inet_ntop(AF_INET, &key, ip_str, INET_ADDRSTRLEN);

                // Find or create an entry in the stats map for the current IP
                HASH_FIND(hh, stats_map, &key, sizeof(__be32), stats_entry);
                if (!stats_entry) {
                    stats_entry = (struct ip_stats *)malloc(sizeof(struct ip_stats));
                    if (!stats_entry) {
                        perror("malloc");
                        exit(EXIT_FAILURE);
                    }
                    memset(stats_entry, 0, sizeof(struct ip_stats));
                    stats_entry->ip = key;
                    stats_entry->prev_time = curr_time;
                    HASH_ADD(hh, stats_map, ip, sizeof(__be32), stats_entry);
                }

                // Calculate the rate of connections per second for this IP
                if (curr_time > stats_entry->prev_time) {
                    rate = (double)(value - stats_entry->prev_count) / (curr_time - stats_entry->prev_time);
                } else {
                    rate = 0.0;
                }

                // Print the statistics for this IP
                printf("IP: %s, Count: %llu, Rate: %.2f connections/sec\n", ip_str, value, rate);

                // Update the stats entry for the next iteration
                stats_entry->prev_count = value;
                stats_entry->prev_time = curr_time;
            }
            prev_key = key;
        }

        printf("\n");
        sleep(1);
    }

    // Free the hashmap
    struct ip_stats *current_entry, *tmp;
    HASH_ITER(hh, stats_map, current_entry, tmp) {
        HASH_DEL(stats_map, current_entry);
        free(current_entry);
    }
}

int main(int argc, char **argv)
{
    int err = 0;

    struct rlimit rlim = {
        .rlim_cur = 512UL << 20,
        .rlim_max = 512UL << 20,
    };

    err = setrlimit(RLIMIT_MEMLOCK, &rlim);
    if (err) {
        fprintf(stderr, "Failed to change rlimit\n");
        return 1;
    }

    skel = connection_rate_counter_bpf__open_and_load();
    if (!skel) {
        fprintf(stderr, "Failed to open and load BPF object\n");
        return 1;
    }

    __u32 key = 0;
    __u16 dest_port = 6379;
    err = bpf_map__update_elem(skel->maps.dest_port_input, &key, sizeof(key), &dest_port, sizeof(dest_port), BPF_ANY);
    if (err) {
        fprintf(stderr, "Failed to update dest_port_input map: %d\n", err);
        goto cleanup;
    }

    err = connection_rate_counter_bpf__attach(skel);
    if (err) {
        fprintf(stderr, "Failed to attach BPF programs\n");
        goto cleanup;
    }

    signal(SIGINT, sig_handler);
    signal(SIGTERM, sig_handler);

    printf("Successfully started! Monitoring TCP connection requests to port %d...\n", dest_port);

    printstats();

cleanup:
    connection_rate_counter_bpf__destroy(skel);
    return err != 0;
}

