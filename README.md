# Container runtime benchmarks

Comparing the performance of CRI-O and containerd.

## Metrics

### Pod and Container Lifecycle
- Pod/container creation time
- Pod/container start-up latency
- Pod/container stop and deletion time

### Pod Density
- Gradually increase the number of pods on a node and monitor pod startup latency and overall node stability (e.g., CPU/memory usage, PLEG times in Kubernetes).
- Tools: kube-burner and k-bench

### I/O Performance IOPS
Storage I/O: Use tools like fio inside a container to benchmark filesystem read/write operations. Previous studies have shown that CRI-O can have an edge in write performance, while containerd may be faster for reads.
