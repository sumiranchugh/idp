#!/bin/bash
# Setup script for AAP OpenShift credentials
# This creates a ServiceAccount and configures AAP to use it

set -e

echo "=== AAP OpenShift Credential Setup ==="
echo ""

# Configuration
NAMESPACE="ansible-automation-platform"
SA_NAME="ansible-sa"
AAP_URL="https://aap-platform-ansible-automation-platform.apps.cluster-k5zwd.dyn.redhatworkshops.io"

# Get AAP admin password
echo "Getting AAP admin password..."
AAP_PASSWORD=$(oc get secret aap-platform-admin-password -n $NAMESPACE -o jsonpath='{.data.password}' | base64 -d)

if [[ -z "$AAP_PASSWORD" ]]; then
  echo "❌ Error: Could not get AAP admin password"
  exit 1
fi

echo "✅ AAP admin password retrieved"
echo ""

# Step 1: Create ServiceAccount
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 1: Creating ServiceAccount"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

cat <<EOF | oc apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: $SA_NAME
  namespace: $NAMESPACE
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: ${SA_NAME}-cluster-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: $SA_NAME
  namespace: $NAMESPACE
EOF

echo ""
echo "✅ ServiceAccount created with cluster-admin role"
echo ""

# Step 2: Get ServiceAccount token
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 2: Generating ServiceAccount token"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Create token with 10 year validity
TOKEN=$(oc create token $SA_NAME -n $NAMESPACE --duration=87600h)

if [[ -z "$TOKEN" ]]; then
  echo "❌ Error: Could not create token"
  exit 1
fi

echo "✅ Token created (10 year validity)"
echo "Token: ${TOKEN:0:50}... (truncated for security)"
echo ""

# Step 3: Get AAP organization
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 3: Getting AAP organization"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

ORG_ID=$(curl -k -s -u admin:$AAP_PASSWORD \
  "${AAP_URL}/api/controller/v2/organizations/" | jq -r '.results[0].id')

echo "Organization ID: $ORG_ID"
echo ""

# Step 4: Get Kubernetes credential type
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 4: Finding Kubernetes credential type"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

CRED_TYPE_ID=$(curl -k -s -u admin:$AAP_PASSWORD \
  "${AAP_URL}/api/controller/v2/credential_types/" | \
  jq -r '.results[] | select(.name | contains("OpenShift") or contains("Kubernetes")) | .id' | head -1)

echo "Credential Type ID: $CRED_TYPE_ID"
echo ""

# Step 5: Check if credential already exists
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 5: Checking existing credentials"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

EXISTING_CRED=$(curl -k -s -u admin:$AAP_PASSWORD \
  "${AAP_URL}/api/controller/v2/credentials/" | \
  jq -r '.results[] | select(.name=="openshift-virtualization") | .id')

if [[ -n "$EXISTING_CRED" ]]; then
  echo "⚠️  Credential 'openshift-virtualization' already exists (ID: $EXISTING_CRED)"
  echo "Updating existing credential..."

  # Update credential
  curl -k -s -u admin:$AAP_PASSWORD -X PATCH \
    "${AAP_URL}/api/controller/v2/credentials/${EXISTING_CRED}/" \
    -H "Content-Type: application/json" \
    -d "{
      \"inputs\": {
        \"host\": \"https://kubernetes.default.svc\",
        \"bearer_token\": \"$TOKEN\",
        \"verify_ssl\": false
      }
    }" > /dev/null

  CRED_ID=$EXISTING_CRED
  echo "✅ Credential updated"
else
  # Step 6: Create credential
  echo "Creating new credential..."
  echo ""

  CRED_RESPONSE=$(curl -k -s -u admin:$AAP_PASSWORD -X POST \
    "${AAP_URL}/api/controller/v2/credentials/" \
    -H "Content-Type: application/json" \
    -d "{
      \"name\": \"openshift-virtualization\",
      \"credential_type\": $CRED_TYPE_ID,
      \"organization\": $ORG_ID,
      \"inputs\": {
        \"host\": \"https://kubernetes.default.svc\",
        \"bearer_token\": \"$TOKEN\",
        \"verify_ssl\": false
      }
    }")

  CRED_ID=$(echo "$CRED_RESPONSE" | jq -r '.id')

  if [[ "$CRED_ID" == "null" || -z "$CRED_ID" ]]; then
    echo "❌ Error creating credential:"
    echo "$CRED_RESPONSE" | jq '.'
    exit 1
  fi

  echo "✅ Credential created (ID: $CRED_ID)"
fi

echo ""

# Step 7: Attach to job template (if exists)
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 7: Attaching credential to job template"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

JOB_TEMPLATE_ID=$(curl -k -s -u admin:$AAP_PASSWORD \
  "${AAP_URL}/api/controller/v2/job_templates/" | \
  jq -r '.results[] | select(.name=="create-vm") | .id')

if [[ -n "$JOB_TEMPLATE_ID" ]]; then
  echo "Found job template 'create-vm' (ID: $JOB_TEMPLATE_ID)"

  # Check if credential already attached
  ALREADY_ATTACHED=$(curl -k -s -u admin:$AAP_PASSWORD \
    "${AAP_URL}/api/controller/v2/job_templates/${JOB_TEMPLATE_ID}/" | \
    jq -r ".summary_fields.credentials[] | select(.id==$CRED_ID) | .id")

  if [[ -n "$ALREADY_ATTACHED" ]]; then
    echo "✅ Credential already attached to job template"
  else
    curl -k -s -u admin:$AAP_PASSWORD -X POST \
      "${AAP_URL}/api/controller/v2/job_templates/${JOB_TEMPLATE_ID}/credentials/" \
      -H "Content-Type: application/json" \
      -d "{\"id\": $CRED_ID}" > /dev/null

    echo "✅ Credential attached to job template"
  fi
else
  echo "⚠️  Job template 'create-vm' not found - create it manually and add this credential"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Setup Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Summary:"
echo "- ServiceAccount: $SA_NAME"
echo "- Namespace: $NAMESPACE"
echo "- AAP Credential ID: $CRED_ID"
echo "- AAP Credential Name: openshift-virtualization"
echo ""
echo "You can now use this credential in your AAP job templates!"
