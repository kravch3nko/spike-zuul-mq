#!/bin/bash
# Restart all Zuul components

echo "🔄 Restarting all Zuul components..."

# Restart Zookeeper (StatefulSet)
echo "Restarting Zookeeper..."
kubectl delete pod zookeeper-0 -n zuul

# Restart Zuul Scheduler (Deployment)
echo "Restarting Zuul Scheduler..."
kubectl rollout restart deployment zuul-scheduler -n zuul

# Restart Zuul Executor (Deployment)
echo "Restarting Zuul Executor..."
kubectl rollout restart deployment zuul-executor -n zuul

# Restart Pause Checker (CronJob - delete pods)
echo "Restarting Pause Checker pods..."
kubectl delete pod -n zuul -l app=pause-checker 2>/dev/null || true

echo ""
echo "⏳ Waiting for pods to restart..."
sleep 10

echo ""
echo "📊 Current pod status:"
kubectl get pods -n zuul

echo ""
echo "✅ Restart complete! Monitor with:"
echo "   kubectl get pods -n zuul -w"
echo "   ./check-logs.sh"

echo "99999999999"
echo "11111111111