#include "vmlinux.h"
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_core_read.h>
#include <bpf/bpf_tracing.h>
#include <bpf/bpf_endian.h>

struct {
    __uint(type, BPF_MAP_TYPE_HASH);
    __type(key, __be32);  // IPv4 address
    __type(value, __u64); // Count
    __uint(max_entries, 10240);
} connreq_count_map SEC(".maps");

struct {
    __uint(type, BPF_MAP_TYPE_ARRAY);
    __type(key, __u32);  // Array index
    __type(value, __u16); // dest port
    __uint(max_entries, 1);
} dest_port_input SEC(".maps");

SEC("kprobe/tcp_conn_request")
int BPF_KPROBE(tcp_conn_request_monitor, struct request_sock_ops *rsk_ops,
               const struct tcp_request_sock_ops *af_ops,
               struct sock *sk, struct sk_buff *skb)
{
    struct tcphdr *tcp;
    struct iphdr *ip;
    __be32 src_ip;
    u16 dest_port;
    u64 *count, zero = 1;

    // Access the TCP header
    tcp = (struct tcphdr *)(BPF_CORE_READ(skb, head) + BPF_CORE_READ(skb, transport_header));
    dest_port = bpf_ntohs(BPF_CORE_READ(tcp, dest));

    u32 key = 0;
    __u16 *input_port = bpf_map_lookup_elem(&dest_port_input, &key);
    if (input_port == NULL || dest_port != *input_port) {
        return 0;
    }

    // Get the IP header
    ip = (struct iphdr *)(BPF_CORE_READ(skb, head) + BPF_CORE_READ(skb, network_header));
    
    // Check if it's an IPv4 packet
    __u8 version = BPF_CORE_READ_BITFIELD_PROBED(ip, version);
    if (version != 4) {
        return 0;
    }

    // Extract the source IP address
    src_ip = BPF_CORE_READ(ip, saddr);

    // Update the count map
    count = bpf_map_lookup_elem(&connreq_count_map, &src_ip);
    if (count) {
        __sync_fetch_and_add(count, 1);
    } else {
        bpf_map_update_elem(&connreq_count_map, &src_ip, &zero, BPF_ANY);
    }

    bpf_printk("tcp_conn_request from src_ip: %x, dest_port: %u\n", bpf_ntohl(src_ip), dest_port);

    return 0;
}

char LICENSE[] SEC("license") = "GPL";
