# Zuul Merge Queue - Minimal Setup

Minimal Zuul configuration for merge queue with rebase->external checks->squash merge workflow.

## Features

- **Rebase before merge**: Changes are rebased onto target branch
- **Wait for external checks**: Zuul waits for GitHub Actions/other CI to complete
- **No speculative merges**: One change at a time (window: 0)
- **Squash merge**: All commits squashed on merge
- **Pause mechanism**: Create issue with `pause-merges` label to stop merges (uses same GitHub App credentials as Zuul)
- **No database required**: Works with just Zookeeper for coordination

## Prerequisites

1. **GitHub App** - Create at https://github.com/settings/apps/new
   - **Required before deployment!**
   - Permissions needed:
     - Checks: Read & Write
     - Contents: Read & Write
     - Issues: Read
     - Pull Requests: Read & Write
   - Subscribe to events: Pull Request, Pull Request Review, Check Suite, Check Run
   - **Install the app** on your repositories
   - Note the **App ID** and **Installation ID** (from installation settings)
   - Generate and download the **private key**

2. **Kubernetes cluster** with kubectl configured
   - For local development: [Minikube](#local-development-with-minikube--ngrok)

3. **yq** - YAML processor (install: `brew install yq` or `apt install yq`)

4. **No PostgreSQL required** - Uses Zookeeper for coordination only

## Setup

### 1. Configure Everything in One Place 🔴 REQUIRED 🔴

**Edit `zuul-config.yaml` with your settings:**

```bash
# 1. Prepare your files:
#    - GitHub App private key (.pem file)
#    - SSH private key for git operations
#    - GitHub Personal Access Token (optional, for pause functionality)

# 2. Edit the configuration:
vim zuul-config.yaml

# 3. Run setup to generate Kubernetes YAML:
./setup.sh
```

**The `zuul-config.yaml` file contains:**
- GitHub App credentials
- SSH key paths
- Repository configuration

**Example configuration:**
```yaml
github:
  app_id: "12345"
  webhook_token: "my-webhook-secret"
  app_private_key_path: "./github-app-private-key.pem"

ssh:
  private_key_path: "./id_ed25519"  # Supports any SSH key type (id_rsa, id_ed25519, etc.)

repositories:
  config_repo: "myorg/zuul-config"
  target_repos:
    - "myorg/repo1"
    - "myorg/repo2"

pause_checker:
  check_repos:                       # Repositories to check for pause issues
    - "myorg/repo1"                  # Uses same GitHub App credentials as Zuul (no separate installation_id needed)
```

### 2. Deploy to Kubernetes

```bash
# After running ./setup.sh, deploy everything:
kubectl apply -f k8s/

# Check pods are running:
kubectl get pods -n zuul
```

**That's it!** Edit one file, run setup script, deploy with kubectl.

**Security Note:** Secrets are created directly in Kubernetes (not stored in YAML files) to prevent accidental exposure.

### 5. Configure GitHub Webhook

Get the webhook URL:

```bash
kubectl get svc zuul-web -n zuul
```

In your GitHub repo settings, add webhook:
- URL: `http://<EXTERNAL-IP>:9000/api/connection/github/payload`
- Content type: `application/json`
- Secret: Your webhook token from secrets
- Events: Pull requests, Pull request reviews, Check suites, Check runs

## Usage

### Merging a PR

1. Create a pull request with your changes
2. Ensure your external CI (GitHub Actions, etc.) runs tests on the PR
3. Get approval from someone with write permission
4. Add label `merge` to the PR
5. Zuul will:
   - Add PR to merge queue
   - Rebase PR onto target branch
   - Wait for ALL external checks to pass
   - Squash merge when all checks succeed

### Pausing Merges

**Pause checker uses the same GitHub App credentials as Zuul** (no separate installation_id needed). You can pause all merges by creating an issue with the `pause-merges` label:

```bash
gh issue create --title "Pause merges for deployment" --label "pause-merges"
```

The pause-checker will stop the scheduler within 5 minutes.

**Resume** by closing the issue:

```bash
gh issue close <issue-number>
```

**Note:** The pause checker automatically uses the same GitHub App credentials (app_id, installation_id, private key) as Zuul - no additional configuration needed!


## Architecture

```
┌─────────────┐
│ GitHub      │
│  - PRs      │
│  - Reviews  │
│  - Checks   │
└──────┬──────┘
       │
       ↓
┌─────────────┐
│ zuul-       │ ← Manages merge queue
│ scheduler   │   Waits for external checks
└──────┬──────┘
       │
       ↓
┌─────────────┐
│ zuul-       │ ← Handles git operations
│ executor    │   (rebase/merge)
└──────┬──────┘
       │
       ↓
┌─────────────┐
│ External    │ ← Runs tests/checks
│ CI Systems  │   (GitHub Actions, etc.)
└──────┬──────┘
       │
       ↓
┌─────────────┐
│ GitHub      │ ← Reports check status
└──────┬──────┘
       │
       ↓
┌─────────────┐
│ zuul-       │ ← Squash merge when
│ scheduler   │   all checks pass
└─────────────┘
```

## Monitoring

Web UI disabled (requires database). Monitor via logs:

```bash
kubectl logs -n zuul -l app=zuul-scheduler -f
kubectl logs -n zuul -l app=zuul-executor -f
```

## Troubleshooting

### Common Issues

- **PR not merging**: Check that all external CI checks are passing
- **Checks not recognized**: Ensure your CI system reports status to GitHub
- **Rebase conflicts**: Resolve conflicts in your PR branch

Check logs:

```bash
kubectl logs -n zuul -l app=zuul-scheduler
kubectl logs -n zuul -l app=zuul-executor
kubectl logs -n zuul -l job-name=pause-checker
```

## Local Development with Minikube & Ngrok

For testing Zuul locally without a cloud Kubernetes cluster:

### 1. Install Prerequisites

```bash
# Install Minikube
brew install minikube  # macOS
# OR download from https://minikube.sigs.k8s.io/docs/start/

# Install ngrok for webhook tunneling
brew install ngrok/ngrok/ngrok  # macOS
# OR download from https://ngrok.com/download

# Install kubectl if not already installed
brew install kubectl  # macOS
```

### 2. Start Minikube

```bash
# Start Minikube with sufficient resources
minikube start --cpus=2 --memory=4096 --disk-size=20g

# Enable ingress addon (optional, for web UI access)
minikube addons enable ingress

# Verify cluster is running
kubectl get nodes
```

### 3. Set Up Ngrok for Webhooks

```bash
# Authenticate ngrok (get token from https://dashboard.ngrok.com/get-started/your-authtoken)
ngrok config add-authtoken YOUR_NGROK_TOKEN

# Start ngrok tunnel on port 9000 (Zuul webhook port)
ngrok http 9000

# Copy the HTTPS URL shown by ngrok (e.g., https://abc123.ngrok.io)
# This will be your webhook URL
```

### 4. Configure and Deploy Zuul

```bash
# 1. Edit zuul-config.yaml with your settings
vim zuul-config.yaml

# 2. Run setup script to generate configs
./setup.sh

# 3. Deploy to Minikube
kubectl apply -f k8s/
```

### 5. Configure GitHub Webhook

1. **Get the LoadBalancer IP:**
   ```bash
   minikube service zuul-web -n zuul --url
   # Returns: http://192.168.49.2:30000
   ```

2. **Set up ngrok webhook URL:**
   - Go to your GitHub repository → Settings → Webhooks
   - **Payload URL:** `https://your-ngrok-url.ngrok.io/api/connection/github/payload`
   - **Content type:** `application/json`
   - **Secret:** Your webhook token from step 4
   - **Events:** Pull requests, Pull request reviews, Check suites, Check runs

### 6. Access Zuul Web UI (Optional)

```bash
# Port forward to access web UI locally
kubectl port-forward svc/zuul-web -n zuul 8080:9000

# Open in browser: http://localhost:8080
```

### 7. Monitor and Debug

```bash
# Check all pods
kubectl get pods -n zuul -w

# View Zuul logs
kubectl logs -n zuul -l app=zuul-scheduler -f

# Check webhook delivery in GitHub
# Go to repository → Settings → Webhooks → Recent Deliveries
```

### 8. Cleanup

```bash
# Stop ngrok (Ctrl+C)

# Delete Zuul deployment
kubectl delete namespace zuul

# Stop Minikube
minikube stop
```

### Troubleshooting Local Setup

- **Minikube won't start:** Try `minikube delete && minikube start`
- **Webhook not working:** Check ngrok is running and URL is correct
- **Pods not starting:** Check `kubectl describe pod <pod-name> -n zuul`
- **Permission issues:** Ensure your SSH keys have correct permissions (`chmod 600 ~/.ssh/id_ed25519` or `chmod 600 ~/.ssh/id_rsa`)

### 💡 Pro Tips

- Use `minikube dashboard` for visual pod monitoring
- Add `alias k="kubectl"` to your shell for faster commands
- Keep ngrok running in a separate terminal tab
- Test with a small test repository first
