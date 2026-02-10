#!/bin/bash

# Script to provision Grafana credentials in a Kubernetes secret.

set -e

# --- Configuration ---
NAMESPACE="${1}"
LOGIN="${2}"
PASSWORD="${3}"
URL="${4}"
SECRET_NAME="grafana-creds"

# --- Helpers ---
decode_base64() {
  if base64 --help 2>&1 | grep -q -- "--decode"; then
    base64 --decode
  else
    base64 -D
  fi
}

# --- Validation ---
if [[ -z "$NAMESPACE" ]]; then
  echo "❌ Error: Namespace is required."
  echo "Usage: $0 <namespace> <login> <password> <url>"
  exit 1
fi

if [[ -z "$LOGIN" ]]; then
  echo "❌ Error: Login is required."
  echo "Usage: $0 <namespace> <login> <password> <url>"
  exit 1
fi

if [[ -z "$PASSWORD" ]]; then
  echo "❌ Error: Password is required."
  echo "Usage: $0 <namespace> <login> <password> <url>"
  exit 1
fi

if [[ -z "$URL" ]]; then
  echo "❌ Error: URL is required."
  echo "Usage: $0 <namespace> <login> <password> <url>"
  exit 1
fi

# --- Script ---
echo "🚀 Starting secret provisioning for '$SECRET_NAME'..."

# 1. Ensure the namespace exists.
echo "📄 Checking for namespace '$NAMESPACE'..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - > /dev/null

# 2. Build the instanceCredentials JSON string
INSTANCE_CREDENTIALS="{\"auth\":\"${LOGIN}:${PASSWORD}\",\"url\":\"${URL}\"}"

# 3. Create or update the secret.
if kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
  echo "ℹ️  Secret '$SECRET_NAME' already exists in namespace '$NAMESPACE'. Updating..."
  kubectl create secret generic "$SECRET_NAME" \
    --from-literal="login"="$LOGIN" \
    --from-literal="password"="$PASSWORD" \
    --from-literal="url"="$URL" \
    --from-literal="instanceCredentials"="$INSTANCE_CREDENTIALS" \
    -n "$NAMESPACE" \
    --dry-run=client -o yaml | kubectl apply -f -
  echo "🎉 Secret '$SECRET_NAME' updated in namespace '$NAMESPACE'."
else
  echo "✨ Creating the new secret..."
  kubectl create secret generic "$SECRET_NAME" \
    --from-literal="login"="$LOGIN" \
    --from-literal="password"="$PASSWORD" \
    --from-literal="url"="$URL" \
    --from-literal="instanceCredentials"="$INSTANCE_CREDENTIALS" \
    -n "$NAMESPACE"
  echo "🎉 Secret '$SECRET_NAME' created in namespace '$NAMESPACE'."
fi

# 4. Verify the secret contents.
echo "🔎 Verifying the secret..."
DECODED_LOGIN=$(kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.data.login}' | decode_base64)
DECODED_PASSWORD=$(kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.data.password}' | decode_base64)
DECODED_URL=$(kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.data.url}' | decode_base64)
DECODED_INSTANCE_CREDS=$(kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.data.instanceCredentials}' | decode_base64)

if [[ "$DECODED_LOGIN" == "$LOGIN" ]] && \
   [[ "$DECODED_PASSWORD" == "$PASSWORD" ]] && \
   [[ "$DECODED_URL" == "$URL" ]] && \
   [[ "$DECODED_INSTANCE_CREDS" == "$INSTANCE_CREDENTIALS" ]]; then
  echo "✅ Verification successful! The secret contains the correct values."
  echo "   Login: $DECODED_LOGIN"
  echo "   URL: $DECODED_URL"
  echo "   Password: [REDACTED]"
  echo "   Instance Credentials: $DECODED_INSTANCE_CREDS"
else
  echo "❌ Verification FAILED. The secret values do not match the input."
  exit 1
fi
