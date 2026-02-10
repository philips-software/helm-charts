#!/bin/bash

# SCRIPT: Upserts a client CA certificate secret from a file.

set -e

# --- Configuration ---
NAMESPACE="otlp-gateway"
SECRET_NAME="otlp-gateway-client-ca"
KEY_IN_SECRET="client_ca.pem"

# --- Helpers ---
decode_base64() {
  if base64 --help 2>&1 | grep -q -- "--decode"; then
    base64 --decode
  else
    base64 -D
  fi
}

# --- Argument validation ---
if [[ $# -ne 1 ]]; then
  echo "❌ Error: Exactly one argument required."
  echo "Usage: $0 <ca-chain-file>"
  echo "Example: $0 /path/to/ca-chain.crt"
  exit 1
fi

CA_FILE="$1"

# Check if the CA file exists and is readable
if [[ ! -f "$CA_FILE" ]]; then
  echo "❌ Error: CA file '$CA_FILE' does not exist."
  exit 1
fi

if [[ ! -r "$CA_FILE" ]]; then
  echo "❌ Error: CA file '$CA_FILE' is not readable."
  exit 1
fi

# --- Script ---
echo "🚀 Starting client CA certificate upsert for '$SECRET_NAME'..."
echo "📁 Using CA file: $CA_FILE"

# 1. Ensure the namespace exists.
echo "📄 Checking for namespace '$NAMESPACE'..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - > /dev/null

# 2. Check if secret exists and handle accordingly
if kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
  echo "🔄 Secret '$SECRET_NAME' already exists. Updating $KEY_IN_SECRET..."
  
  # Update the existing secret
  kubectl create secret generic "$SECRET_NAME" \
    --from-file="$KEY_IN_SECRET"="$CA_FILE" \
    --dry-run=client -o yaml | \
    kubectl apply -f -
  
  echo "✅ Secret '$SECRET_NAME' updated in namespace '$NAMESPACE'."
else
  echo "✨ Creating new secret '$SECRET_NAME'..."
  
  # Create new secret
  kubectl create secret generic "$SECRET_NAME" \
    --from-file="$KEY_IN_SECRET"="$CA_FILE" \
    -n "$NAMESPACE"
  
  echo "🎉 Secret '$SECRET_NAME' created in namespace '$NAMESPACE'."
fi

# 3. Verify the secret contains the CA certificate
echo "🔎 Verifying the CA certificate in the secret..."
# Escape dots in the key name for jsonpath
ESCAPED_KEY=$(echo "$KEY_IN_SECRET" | sed 's/\./\\./g')
CERT_CONTENT=$(kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath="{.data.${ESCAPED_KEY}}" | decode_base64)

# Basic validation - check if it looks like a certificate
if echo "$CERT_CONTENT" | grep -q "BEGIN CERTIFICATE" && echo "$CERT_CONTENT" | grep -q "END CERTIFICATE"; then
  echo "✅ Verification successful! The secret contains a valid certificate."
  echo "📋 Certificate preview:"
  echo "$CERT_CONTENT" | head -3
  echo "   ... (certificate content) ..."
  echo "$CERT_CONTENT" | tail -3
else
  echo "❌ Verification FAILED. The secret does not contain a valid certificate format."
  echo "   Content preview: $(echo "$CERT_CONTENT" | head -c 100)..."
  exit 1
fi

echo "🎯 Client CA certificate upsert completed successfully!"
