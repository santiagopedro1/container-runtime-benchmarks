#!/bin/bash

# 🧪 Usage: ./benchmark.sh <runtime-name> <pod-count> [replica-count]
if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Usage: $0 <runtime-name> <pod-count> [replica-count]"
  exit 1
fi

RUNTIME="$1"
POD_COUNT="$2"
REPLICA_COUNT="${3:-1}"  # default to 1 replica if not provided

POD_PREFIX="benchmark-pod-${RUNTIME}"
RESULTS_DIR="results"
OUTPUT_CSV="${RESULTS_DIR}/pod_latency_${RUNTIME}-${REPLICA_COUNT}.csv"
NAMESPACE="benchmark"
IMAGE="docker.io/library/nginx"

# Ensure results directory exists
mkdir -p "$RESULTS_DIR"

# Write CSV header
echo "pod,start_time,ready_time,latency_sec,delete_latency_sec" > "$OUTPUT_CSV"

# Create namespace
kubectl create namespace ${NAMESPACE} >/dev/null 2>&1

for i in $(seq 1 $POD_COUNT); do
  for r in $(seq 1 $REPLICA_COUNT); do
    POD_NAME="${POD_PREFIX}-${i}-${r}"
    echo "🚀 Creating pod $POD_NAME..."

    kubectl run "$POD_NAME" \
      --image=$IMAGE \
      --image-pull-policy=Never \
      --namespace=${NAMESPACE} \
      --restart=Never \
      --command -- sleep 1

    if kubectl wait --for=condition=Ready pod/"$POD_NAME" --namespace=${NAMESPACE} --timeout=60s >/dev/null; then
      START_TIME=$(kubectl get pod "$POD_NAME" --namespace=${NAMESPACE} -o json | jq -r '.status.startTime')
      READY_TIME=$(kubectl get pod "$POD_NAME" --namespace=${NAMESPACE} -o json | jq -r '.status.conditions[] | select(.type=="Ready" and .status=="True") | .lastTransitionTime')

      START_EPOCH=$(date -d "$START_TIME" +%s)
      READY_EPOCH=$(date -d "$READY_TIME" +%s)
      LATENCY=$((READY_EPOCH - START_EPOCH))

      echo "📤 Deleting pod $POD_NAME..."
      kubectl delete pod "$POD_NAME" --namespace=${NAMESPACE} --wait=false >/dev/null

      for j in $(seq 1 30); do
        sleep 1
        if ! kubectl get pod "$POD_NAME" --namespace=${NAMESPACE} >/dev/null 2>&1; then
          break
        fi
      done

      echo "$POD_NAME,$LATENCY" >> "$OUTPUT_CSV"
      echo "✅ $POD_NAME ready in ${LATENCY}s, deleted in ${DELETE_LATENCY}s"
    else
      echo "❌ $POD_NAME did not become ready in time"
      echo "$POD_NAME,ERROR,ERROR,ERROR,ERROR" >> "$OUTPUT_CSV"
      kubectl delete pod "$POD_NAME" --namespace=${NAMESPACE} --wait=false >/dev/null
    fi

    sleep 2
  done
done

# Cleanup namespace
echo "🧹 Cleaning up namespace..."
kubectl delete namespace ${NAMESPACE} >/dev/null

echo "📊 Benchmark complete. Results saved to $OUTPUT_CSV"
