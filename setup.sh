#!/bin/bash
# Zuul Setup Script
# Reads zuul-config.yaml and generates Kubernetes YAML files

set -e

CONFIG_FILE="zuul-config.yaml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "🚀 Setting up Zuul Merge Queue..."

# Check if config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}❌ ERROR: $CONFIG_FILE not found!${NC}"
    echo "Create $CONFIG_FILE with your configuration."
    exit 1
fi

# Check if yq is available for YAML parsing
if ! command -v yq &> /dev/null; then
    echo -e "${YELLOW}⚠️  WARNING: yq not found. Installing...${NC}"
    # Try to install yq
    if command -v brew &> /dev/null; then
        brew install yq
    elif command -v apt-get &> /dev/null; then
        sudo apt-get update && sudo apt-get install -y yq
    else
        echo -e "${RED}❌ ERROR: Please install yq manually: https://github.com/mikefarah/yq${NC}"
        exit 1
    fi
fi

# Read configuration values
GITHUB_APP_ID=$(yq '.github.app_id' "$CONFIG_FILE")
GITHUB_INSTALLATION_ID=$(yq '.github.installation_id' "$CONFIG_FILE")
WEBHOOK_TOKEN=$(yq '.github.webhook_token' "$CONFIG_FILE")
GITHUB_KEY_PATH=$(yq '.github.app_private_key_path' "$CONFIG_FILE")
SSH_KEY_PATH=$(yq '.ssh.private_key_path' "$CONFIG_FILE")
# Expand ~ in paths
SSH_KEY_PATH="${SSH_KEY_PATH/#\~/$HOME}"
GITHUB_KEY_PATH="${GITHUB_KEY_PATH/#\~/$HOME}"
CONFIG_REPO=$(yq '.repositories.config_repo' "$CONFIG_FILE")

# Read target repos as array
TARGET_REPOS=$(yq '.repositories.target_repos[]' "$CONFIG_FILE")

# Read pause checker repos (uses same GitHub App credentials as Zuul)
PAUSE_REPOS=$(yq '.pause_checker.check_repos[]' "$CONFIG_FILE" 2>/dev/null || echo "")

# Validate required fields
if [[ "$GITHUB_APP_ID" == "EDIT_ME" ]] || [[ "$GITHUB_INSTALLATION_ID" == "EDIT_ME" ]] || [[ "$WEBHOOK_TOKEN" == "EDIT_ME" ]] || [[ "$CONFIG_REPO" == "EDIT_ME"* ]]; then
    echo -e "${RED}❌ ERROR: Please edit $CONFIG_FILE and replace all EDIT_ME values!${NC}"
    exit 1
fi

# Check if key files exist
if [ ! -f "$GITHUB_KEY_PATH" ]; then
    echo -e "${RED}❌ ERROR: GitHub App private key not found: $GITHUB_KEY_PATH${NC}"
    exit 1
fi

if [ ! -f "$SSH_KEY_PATH" ]; then
    echo -e "${RED}❌ ERROR: SSH private key not found: $SSH_KEY_PATH${NC}"
    exit 1
fi

echo "📋 Configuration loaded:"
echo "   GitHub App ID: $GITHUB_APP_ID"
echo "   Installation ID: $GITHUB_INSTALLATION_ID"
echo "   Config Repo: $CONFIG_REPO"
echo "   Target Repos: $TARGET_REPOS"
if [ -n "$PAUSE_REPOS" ]; then
    echo "   Pause Checker Repos: $PAUSE_REPOS"
fi

# Create namespace if it doesn't exist
echo "📦 Creating namespace..."
kubectl create namespace zuul --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null || kubectl get namespace zuul >/dev/null 2>&1 || kubectl create namespace zuul

# Generate TLS certificates for Zookeeper (required by Zuul)
echo "🔒 Generating TLS certificates for Zookeeper (required by Zuul)..."
TLS_DIR=$(mktemp -d)
trap "rm -rf $TLS_DIR" EXIT

# Generate CA key and cert
openssl genrsa -out "$TLS_DIR/ca.key" 2048 2>/dev/null
openssl req -new -x509 -days 365 -key "$TLS_DIR/ca.key" -out "$TLS_DIR/ca.crt" \
  -subj "/CN=zuul-zookeeper-ca" 2>/dev/null

# Generate server key and cert (for Zookeeper server)
openssl genrsa -out "$TLS_DIR/server.key" 2048 2>/dev/null
openssl req -new -key "$TLS_DIR/server.key" -out "$TLS_DIR/server.csr" \
  -subj "/CN=zookeeper" 2>/dev/null
openssl x509 -req -in "$TLS_DIR/server.csr" -CA "$TLS_DIR/ca.crt" -CAkey "$TLS_DIR/ca.key" \
  -CAcreateserial -out "$TLS_DIR/server.crt" -days 365 2>/dev/null

# Generate client key and cert (for Zuul clients)
openssl genrsa -out "$TLS_DIR/client.key" 2048 2>/dev/null
openssl req -new -key "$TLS_DIR/client.key" -out "$TLS_DIR/client.csr" \
  -subj "/CN=zuul-client" 2>/dev/null
openssl x509 -req -in "$TLS_DIR/client.csr" -CA "$TLS_DIR/ca.crt" -CAkey "$TLS_DIR/ca.key" \
  -CAcreateserial -out "$TLS_DIR/client.crt" -days 365 2>/dev/null

# Create PKCS12 keystore for Zookeeper server (as per Zuul docs)
openssl pkcs12 -export -in "$TLS_DIR/server.crt" -inkey "$TLS_DIR/server.key" \
  -out "$TLS_DIR/server.p12" -password pass:changeit -name server 2>/dev/null

# Create PKCS12 truststore (CA cert only)
openssl pkcs12 -export -nokeys -in "$TLS_DIR/ca.crt" \
  -out "$TLS_DIR/truststore.p12" -password pass:changeit -name ca 2>/dev/null

# Create Zookeeper TLS secret
kubectl create secret generic zookeeper-tls \
  --namespace=zuul \
  --from-file=ca.crt="$TLS_DIR/ca.crt" \
  --from-file=server.crt="$TLS_DIR/server.crt" \
  --from-file=server.key="$TLS_DIR/server.key" \
  --from-file=server.p12="$TLS_DIR/server.p12" \
  --from-file=truststore.p12="$TLS_DIR/truststore.p12" \
  --from-file=client.crt="$TLS_DIR/client.crt" \
  --from-file=client.key="$TLS_DIR/client.key" \
  --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null || \
kubectl create secret generic zookeeper-tls \
  --namespace=zuul \
  --from-file=ca.crt="$TLS_DIR/ca.crt" \
  --from-file=server.crt="$TLS_DIR/server.crt" \
  --from-file=server.key="$TLS_DIR/server.key" \
  --from-file=server.p12="$TLS_DIR/server.p12" \
  --from-file=truststore.p12="$TLS_DIR/truststore.p12" \
  --from-file=client.crt="$TLS_DIR/client.crt" \
  --from-file=client.key="$TLS_DIR/client.key"

echo "✅ TLS certificates generated and stored in zookeeper-tls secret"

# Create secrets directly (no YAML file with secrets)
echo "🔐 Creating Kubernetes secrets..."
kubectl create secret generic zuul-secrets \
  --namespace=zuul \
  --from-literal=github-app-id="$GITHUB_APP_ID" \
  --from-literal=github-installation-id="$GITHUB_INSTALLATION_ID" \
  --from-literal=github-webhook-token="$WEBHOOK_TOKEN" \
  --from-file=github-app-key="$GITHUB_KEY_PATH" \
  --from-file=ssh-private-key="$SSH_KEY_PATH" \
  --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null || \
kubectl create secret generic zuul-secrets \
  --namespace=zuul \
  --from-literal=github-app-id="$GITHUB_APP_ID" \
  --from-literal=github-installation-id="$GITHUB_INSTALLATION_ID" \
  --from-literal=github-webhook-token="$WEBHOOK_TOKEN" \
  --from-file=github-app-key="$GITHUB_KEY_PATH" \
  --from-file=ssh-private-key="$SSH_KEY_PATH"

echo "✅ Secrets created (not stored in YAML files)"

# Generate config YAML
echo "⚙️  Generating configuration..."
cat > k8s/03-config.yaml << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: zuul-config
  namespace: zuul
data:
  zuul.conf: |
    [gearman]
    server=zuul-scheduler

    [zookeeper]
    hosts=zookeeper:2182
    tls_cert=/var/lib/zuul/tls/client.crt
    tls_key=/var/lib/zuul/tls/client.key
    tls_ca=/var/lib/zuul/tls/ca.crt

    [scheduler]
    tenant_config=/etc/zuul/main.yaml
    command_socket=/var/lib/zuul/command-socket/command.socket

    [merger]
    git_user_email=zuul@localhost
    git_user_name=Zuul

    [executor]
    private_key_file=/var/lib/zuul/ssh/ssh-key
    ansible_root=/var/lib/zuul/ansible-work

    [keystore]
    password=changeit

    [web]
    listen_address=0.0.0.0
    port=9000

    [connection "github"]
    driver=github
    app_id=$GITHUB_APP_ID
    app_key=/var/lib/zuul/github.pem
    webhook_token=$WEBHOOK_TOKEN

    [database]
    se

  main.yaml: |
    - tenant:
        name: main
        source:
          github:
            config-projects:
              - $CONFIG_REPO
            untrusted-projects:
EOF

# Add target repositories (excluding config repo if it's also in target_repos)
HAS_REPOS=false

TEMP_REPOS=$(mktemp)
echo "$TARGET_REPOS" | while read -r repo; do
    if [ -n "$repo" ] && [ "$repo" != "null" ] && [ "$repo" != "$CONFIG_REPO" ]; then
        echo "              - $repo" >> "$TEMP_REPOS"
        HAS_REPOS=true
    fi
done

# Append repos to config or add empty list
if [ -s "$TEMP_REPOS" ]; then
    cat "$TEMP_REPOS" >> k8s/03-config.yaml
else
    echo "              []" >> k8s/03-config.yaml
fi
rm -f "$TEMP_REPOS"

# Generate pause checker repos ConfigMap (pause checker YAML is static)
if [ -n "$PAUSE_REPOS" ]; then
    echo "🔄 Generating pause checker repos ConfigMap..."
    
    # Generate repos.txt content
    REPOS_FILE=$(mktemp)
    echo "# Repositories to check for pause issues" >> "$REPOS_FILE"
    echo "# This file is generated by setup.sh" >> "$REPOS_FILE"
    echo "" >> "$REPOS_FILE"
    echo "$PAUSE_REPOS" | while IFS= read -r repo; do
        if [ -n "$repo" ] && [ "$repo" != "null" ]; then
            echo "$repo" >> "$REPOS_FILE"
        fi
    done

    # Create/update ConfigMap
    kubectl create configmap pause-checker-repos \
      --namespace=zuul \
      --from-file=repos.txt="$REPOS_FILE" \
      --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null || \
    kubectl create configmap pause-checker-repos \
      --namespace=zuul \
      --from-file=repos.txt="$REPOS_FILE"

    rm -f "$REPOS_FILE"
    echo "✅ Pause checker repos ConfigMap created"
fi

echo ""
echo -e "${GREEN}✅ Setup complete!${NC}"
echo ""
echo "📋 Generated files:"
echo "   • Kubernetes secrets created directly (not in YAML)"
echo "   • k8s/03-config.yaml (with your repos)"
if [ -n "$PAUSE_REPOS" ]; then
    echo "   • pause-checker-repos ConfigMap (repos to check for pause issues)"
fi
echo ""
echo "🚀 Deploy with:"
echo "   kubectl apply -f k8s/"
echo ""
echo -e "${YELLOW}⚠️  IMPORTANT:${NC}"
echo "   • Secrets are created directly in Kubernetes (not in YAML files)"
echo "   • Review the generated YAML files (no secrets in them)"
echo "   • Ensure your GitHub App has proper permissions"
echo "   • Configure webhook in GitHub repository settings"
echo "2345678"