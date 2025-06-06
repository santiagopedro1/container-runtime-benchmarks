#!/bin/bash
kubectl apply -f density-deployment.yaml

for i in $(seq 10 10 200); do
    echo "Scaling to $i pods"
    kubectl scale deployment/density-app --replicas=$i
    sleep 5
    echo "Node status:"
    kubectl top node
    # Add a delay to observe stability
    sleep 30
done
