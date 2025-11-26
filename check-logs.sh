#!/bin/bash
# Quick script to check logs for Zuul services

echo "1234567890"
echo "234567890"
echo "234567890"
echo "=== Pod Status ==="
kubectl get pods -n zuul

echo -e "\n=== Zuul Scheduler (last 30 lines) ==="
kubectl logs -n zuul -l app=zuul-scheduler --tail=30 2>&1 | tail -30

echo -e "\n=== Zuul Executor (last 30 lines) ==="
kubectl logs -n zuul -l app=zuul-executor --tail=30 2>&1 | tail -30

echo -e "\n=== Zookeeper (last 30 lines) ==="
kubectl logs -n zuul zookeeper-0 --tail=30 2>&1 | tail -30

echo -e "\n=== Quick Commands ==="
echo "# Follow scheduler logs: kubectl logs -n zuul -l app=zuul-scheduler -f"
echo "# Follow executor logs: kubectl logs -n zuul -l app=zuul-executor -f"
echo "# Follow zookeeper logs: kubectl logs -n zuul zookeeper-0 -f"
echo "# Check for errors: kubectl logs -n zuul -l app=zuul-scheduler --tail=100 | grep -i error"

