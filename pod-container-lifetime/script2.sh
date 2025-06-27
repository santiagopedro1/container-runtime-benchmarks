#!/bin/bash

# 🧪 Usage: ./benchmark_crictl.sh <runtime-name> <pod-count> [replica-count]
if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Usage: $0 <runtime-name> <pod-count> [replica-count]"
  exit 1
fi

RUNTIME="$1"
POD_COUNT="$2"
REPLICA_COUNT="${3:-1}"
POD_PREFIX="crictl-pod-${RUNTIME}"
RESULTS_DIR="results"
OUTPUT_CSV="${RESULTS_DIR}/pod_crictl_${RUNTIME}.csv"
NAMESPACE="benchmark"
IMAGE="docker.io/library/nginx"

mkdir -p "$RESULTS_DIR"
# Updated header for nanosecond values
echo "pod,createdAt_ns,startedAt_ns,latency_ns" > "$OUTPUT_CSV"

# Ensure namespace exists
kubectl create namespace ${NAMESPACE} >/dev/null 2>&1

for i in $(seq 1 $POD_COUNT); do
  for r in $(seq 1 $REPLICA_COUNT); do
    POD_NAME="${POD_PREFIX}-${i}-${r}"

    # Create pod with short sleep command
    kubectl run "$POD_NAME" \
      --image=$IMAGE \
      --image-pull-policy=Never \
      --namespace=${NAMESPACE} \
      --restart=Never \
      --command -- sleep 10

    # Wait for pod to become Ready
    kubectl wait --for=condition=Ready pod/"$POD_NAME" --namespace=${NAMESPACE} --timeout=60s >/dev/null || echo "⚠️ Pod $POD_NAME not Ready"

    # Get pod UID
    POD_UID=$(kubectl get pod $POD_NAME -n $NAMESPACE -o jsonpath='{.status.containerStatuses[0].containerID}' | sed 's|containerd://||')
	echo $POD_UID

    # Run crictl inspectp via minikube ssh
    if [ -n "$POD_UID" ]; then
      POD_JSON=$(minikube ssh "sudo crictl inspect \"$POD_UID\"" 2>/dev/null)
    else
      echo "⚠️ Could not get UID for pod $POD_NAME. Skipping crictl inspect."
      POD_JSON="{}"
    fi

    CREATED_AT_NS=$(echo "$POD_JSON" | jq -r '.status.createdAt')
    STARTED_AT_NS=$(echo "$POD_JSON" | jq -r '.status.containers[0].startedAt')

    # Calculate latency in nanoseconds directly
    if [[ "$CREATED_AT_NS" =~ ^[0-9]+$ ]] && [[ "$STARTED_AT_NS" =~ ^[0-9]+$ ]]; then
      LATENCY_NS=$(echo "$STARTED_AT_NS - $CREATED_AT_NS" | bc)
    else
      CREATED_AT_NS="N/A"
      STARTED_AT_NS="N/A"
      LATENCY_NS="N/A"
      echo "⚠️ Could not get valid timestamps for pod $POD_NAME. createdAt: '$CREATED_AT_NS', startedAt: '$STARTED_AT_NS'"
    fi

    echo "$POD_NAME,$CREATED_AT_NS,$STARTED_AT_NS,$LATENCY_NS" >> "$OUTPUT_CSV"

    # Delete pod
    # kubectl delete pod "$POD_NAME" --namespace=${NAMESPACE} --wait=false >/dev/null

    sleep 2
  done
done

# kubectl delete namespace ${NAMESPACE} >/dev/null
echo "📊 Done! Results saved to $OUTPUT_CSV"