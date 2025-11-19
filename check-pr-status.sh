#!/bin/bash
# Check if Zuul is processing PRs and webhook status

echo "🔍 Checking Zuul PR Processing Status..."
echo ""

# Check scheduler logs for PR/webhook activity
echo "=== Recent Webhook/PR Activity ==="
kubectl logs -n zuul -l app=zuul-scheduler --tail=200 2>&1 | grep -iE "webhook|pull_request|event|github.*event|check|status" | tail -15

echo ""
echo "=== Recent GitHub Connection Activity ==="
kubectl logs -n zuul -l app=zuul-scheduler --tail=100 2>&1 | grep -iE "github|connection|auth|repository" | tail -10

echo ""
echo "=== Pipeline Configuration ==="
echo "Your pipeline requires:"
echo "  • 'merge' label on PR (to enter queue)"
echo "  • All external checks to pass (status contexts)"
echo ""
echo "=== What Zuul Should Do ==="
echo "1. When PR gets 'merge' label:"
echo "   • Create a check run (status: in_progress)"
echo "   • Comment on PR: 'This change has entered the merge queue...'"
echo "   • Rebase PR to latest base branch"
echo "   • Wait for all external checks to pass"
echo ""
echo "2. When all checks pass:"
echo "   • Update check run (status: success)"
echo "   • Comment: '✅ All checks passed! Change merged successfully.'"
echo "   • Squash merge the PR"
echo ""
echo "=== To Test ==="
echo "1. Ensure webhook is configured in GitHub repo settings"
echo "2. Add 'merge' label to your PR"
echo "3. Watch logs: kubectl logs -n zuul -l app=zuul-scheduler -f"
echo "4. Check PR for Zuul check run and comments"

