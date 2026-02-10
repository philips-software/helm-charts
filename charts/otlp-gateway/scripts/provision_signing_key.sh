#!/bin/bash

# FINAL SCRIPT: Creates a secret with a random, verified alphanumeric value.

set -e

# --- Configuration ---
NAMESPACE="${1:-otlp-gateway}"
SECRET_NAME="otlp-gateway-signing-key"
KEY_IN_SECRET="key"

# --- Helpers ---
generate_alphanumeric_secret() {
  local length=${1:-32}
  local secret=""

  while [[ ${#secret} -lt ${length} ]]; do
    local needed=$((length - ${#secret}))
    secret+=$(LC_ALL=C tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c "${needed}")
  done

  echo "${secret:0:length}"
}

decode_base64() {
  if base64 --help 2>&1 | grep -q -- "--decode"; then
    base64 --decode
  else
    base64 -D
  fi
}

# --- Script ---
echo "🚀 Starting secret generation for '$SECRET_NAME'..."

# 1. Ensure the namespace exists.
echo "📄 Checking for namespace '$NAMESPACE'..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - > /dev/null

# 2. Create the secret only if it does not already exist.
if kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
  echo "ℹ️  Secret '$SECRET_NAME' already exists in namespace '$NAMESPACE'. Skipping creation."
else
  echo "🔑 Generating a random alphanumeric value..."
  SECRET_VALUE=$(generate_alphanumeric_secret 32)
  echo "✅ New random value generated."

  echo "✨ Creating the new secret..."
  kubectl create secret generic "$SECRET_NAME" \
    --from-literal="$KEY_IN_SECRET"="$SECRET_VALUE" \
    -n "$NAMESPACE"
  echo "🎉 Secret '$SECRET_NAME' created in namespace '$NAMESPACE'."
fi

# 3. Verify the DECODED secret from the cluster is alphanumeric.
echo "🔎 Verifying the DECODED secret..."
# Uses portable decoding that works on macOS and Linux.
DECODED_KEY=$(kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.data.key}' | decode_base64)

# This regex check confirms the decoded value contains ONLY 32 alphanumeric characters.
if [[ "$DECODED_KEY" =~ ^[a-zA-Z0-9]{32}$ ]]; then
  echo "✅ Verification successful! The decoded secret is purely alphanumeric."
  echo "   Decoded Value: $DECODED_KEY"
else
  echo "❌ Verification FAILED. The decoded secret is not alphanumeric."
  echo "   Decoded Value: $DECODED_KEY"
  exit 1
fi
