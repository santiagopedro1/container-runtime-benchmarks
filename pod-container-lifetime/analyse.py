import csv
import statistics
import numpy as np

def ns_to_ms(ns):
    return ns / 1_000_000

def analyze_timings(filename):
    pod_create_times = []
    container_create_times = []

    with open(filename, newline='') as csvfile:
        reader = csv.DictReader(csvfile)
        for row in reader:
            pod_create_times.append(int(row['Pod Create (ns)']))
            container_create_times.append(int(row['Container Create (ns)']))

    def stats(arr):
        arr_sorted = sorted(arr)
        return {
            'min': min(arr),
            'max': max(arr),
            'average': statistics.mean(arr),
            'stddev': statistics.stdev(arr) if len(arr) > 1 else 0,
            'p99': np.percentile(arr_sorted, 99)
        }

    pod_stats = stats(pod_create_times)
    container_stats = stats(container_create_times)

    def print_stats(name, stats_dict):
        print(f"{name} (ms):")
        for k, v in stats_dict.items():
            print(f"  {k}: {ns_to_ms(v):.3f}")
        print()

    print_stats("Pod Create Time", pod_stats)
    print_stats("Container Create Time", container_stats)

if __name__ == "__main__":
    import sys
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <benchmark_results.csv>")
        sys.exit(1)
    analyze_timings(sys.argv[1])

