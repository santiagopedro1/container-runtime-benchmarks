#!/bin/bash

if [ -z "$1" ]; then
  echo "Usage: $0 <runtime> [num_runs]"
  echo "Valid runtimes: containerd, crio, crio-optimized"
  exit 1
fi

RUNTIME="$1"
NUM_RUNS="${2:-10}"

# Determine runtime socket
case "$RUNTIME" in
  containerd)
    RUNTIME_ENDPOINT="unix:///run/containerd/containerd.sock"
    POD_CONFIG="pod-config.json"
    CONTAINER_CONFIG="container-config.json"
    ;;
  crio)
    RUNTIME_ENDPOINT="unix:///run/crio/crio.sock"
    POD_CONFIG="pod-config.json"
    CONTAINER_CONFIG="container-config.json"
    ;;
  crio-optimized)
    RUNTIME_ENDPOINT="unix:///run/crio/crio.sock"
    POD_CONFIG="pod-config-crio-optimized.json"
    CONTAINER_CONFIG="container-config-crio-optimized.json"
    ;;
  *)
    echo "Unsupported runtime: $RUNTIME"
    exit 1
    ;;
esac

OUTPUT_FILE="benchmark_results_${RUNTIME}.csv"

export CONTAINER_RUNTIME_ENDPOINT=$RUNTIME_ENDPOINT
export IMAGE_SERVICE_ENDPOINT=$RUNTIME_ENDPOINT

crictl rmp -f $(crictl ps -aq) > /dev/null 2>&1
crictl rm -f $(crictl ps -a -q) > /dev/null 2>&1

echo "Benchmarking container creation with runtime: $RUNTIME"
echo "Results will be saved to: $OUTPUT_FILE"
echo "Running $NUM_RUNS iterations..."

crictl pull alpine:latest

echo "Run,Pod Create (ns),Container Create (ns),Container Status CreatedAt (ns)" > "$OUTPUT_FILE"

UID_VAL="benchmarking-uid-$(date +%s%N)"
sed -i "s/REPLACE_UID/$UID_VAL/g" "$POD_CONFIG"

for i in $(seq 1 "$NUM_RUNS"); do
  POD_CREATE_START=$(date +%s%N)
  POD_ID=$(crictl runp "$POD_CONFIG")
  POD_CREATE_END=$(date +%s%N)

  CONTAINER_CREATE_START=$(date +%s%N)
  CONTAINER_ID=$(crictl create "$POD_ID" "$CONTAINER_CONFIG" "$POD_CONFIG")
  CONTAINER_CREATE_END=$(date +%s%N)
  CONTAINER_STATUS_CREATEDAT=$(crictl inspect "$CONTAINER_ID" | jq -r '.status.createdAt')

  POD_CREATE_TIME=$((POD_CREATE_END - POD_CREATE_START))
  CONTAINER_CREATE_TIME=$((CONTAINER_CREATE_END - CONTAINER_CREATE_START))

  echo "$i,$POD_CREATE_TIME,$CONTAINER_CREATE_TIME,$CONTAINER_STATUS_CREATEDAT" >> "$OUTPUT_FILE"

  crictl stop "$CONTAINER_ID" > /dev/null 2>&1
  crictl rm "$CONTAINER_ID" > /dev/null 2>&1
  crictl stopp "$POD_ID" > /dev/null 2>&1
  crictl rmp "$POD_ID" > /dev/null 2>&1
done

echo "Benchmarking complete. Results saved to $OUTPUT_FILE"

