#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${1:-.env}"

if [[ ! -f "$SCRIPT_DIR/$ENV_FILE" ]]; then
  echo "ERROR: $ENV_FILE not found. Copy .env.example to .env and fill in your values."
  exit 1
fi

# shellcheck source=/dev/null
source "$SCRIPT_DIR/$ENV_FILE"

# ── Derived values ────────────────────────────────────────────────────────────
export CLUSTER_DOMAIN CLUSTER_API_URL STORAGE_CLASS
export KEYCLOAK_BASE_URL KEYCLOAK_REALM
export OAUTH_CLIENT_ID OAUTH_CLIENT_SECRET
export RHDH_NAMESPACE RHDH_SUPERADMIN BACKEND_SECRET
export SN_BASE_URL SN_USERNAME SN_PASSWORD SN_BASIC_AUTH SN_TO_RHDH_TOKEN
export AAP_BASE_URL AAP_TOKEN
export GITHUB_REPO_BASE

RHDH_ROUTE="backstage-developer-hub-${RHDH_NAMESPACE}.${CLUSTER_DOMAIN}"
export RHDH_ROUTE

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "==> Cluster domain : $CLUSTER_DOMAIN"
echo "==> RHDH namespace : $RHDH_NAMESPACE"
echo "==> RHDH route     : $RHDH_ROUTE"
echo "==> Superadmin     : $RHDH_SUPERADMIN"
echo ""

# ── Substitute __PLACEHOLDERS__ in all yaml files ─────────────────────────────
substitute() {
  local src="$1" dst="$2"
  sed \
    -e "s|__CLUSTER_DOMAIN__|${CLUSTER_DOMAIN}|g" \
    -e "s|__CLUSTER_API_URL__|${CLUSTER_API_URL}|g" \
    -e "s|__KEYCLOAK_BASE_URL__|${KEYCLOAK_BASE_URL}|g" \
    -e "s|__KEYCLOAK_REALM__|${KEYCLOAK_REALM}|g" \
    -e "s|__RHDH_NAMESPACE__|${RHDH_NAMESPACE}|g" \
    -e "s|__RHDH_ROUTE__|${RHDH_ROUTE}|g" \
    -e "s|__RHDH_SUPERADMIN__|${RHDH_SUPERADMIN}|g" \
    -e "s|__GITHUB_REPO_BASE__|${GITHUB_REPO_BASE}|g" \
    -e "s|__STORAGE_CLASS__|${STORAGE_CLASS}|g" \
    "$src" > "$dst"
}

mkdir -p "$TMPDIR/devhub" "$TMPDIR/workflows"

for f in devhub/*.yaml; do
  substitute "$SCRIPT_DIR/$f" "$TMPDIR/$f"
done
for f in workflows/*.yaml; do
  substitute "$SCRIPT_DIR/$f" "$TMPDIR/$f"
done

# ── Ensure namespace exists ───────────────────────────────────────────────────
echo "==> Ensuring namespace $RHDH_NAMESPACE exists..."
oc get namespace "$RHDH_NAMESPACE" &>/dev/null || oc new-project "$RHDH_NAMESPACE" --skip-config-write

# ── Create secrets ────────────────────────────────────────────────────────────
echo "==> Creating secrets..."

oc apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: backstage-secrets
  namespace: ${RHDH_NAMESPACE}
  labels:
    rhdh.redhat.com/ext-config-sync: "true"
type: Opaque
stringData:
  BACKEND_SECRET: "${BACKEND_SECRET}"
EOF

oc apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: oauth-client
  namespace: ${RHDH_NAMESPACE}
  labels:
    rhdh.redhat.com/ext-config-sync: "true"
type: Opaque
stringData:
  OAUTH_CLIENT_ID: "${OAUTH_CLIENT_ID}"
  OAUTH_CLIENT_SECRET: "${OAUTH_CLIENT_SECRET}"
EOF

oc apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: backstage-servicenow-secret
  namespace: ${RHDH_NAMESPACE}
  labels:
    rhdh.redhat.com/ext-config-sync: "true"
type: Opaque
stringData:
  SERVICENOW_BASE_URL: "${SN_BASE_URL}"
  SN_BASE_URL: "${SN_BASE_URL}"
  SERVICENOW_USERNAME: "${SN_USERNAME}"
  SERVICENOW_PASSWORD: "${SN_PASSWORD}"
  SN_BASIC_AUTH: "${SN_BASIC_AUTH}"
EOF

oc apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: backstage-external-token-secret
  namespace: ${RHDH_NAMESPACE}
  labels:
    rhdh.redhat.com/ext-config-sync: "true"
type: Opaque
stringData:
  SN_TO_RHDH_TOKEN: "${SN_TO_RHDH_TOKEN}"
EOF

if [[ -n "${AAP_BASE_URL:-}" ]]; then
  oc apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: backstage-aap-secret
  namespace: ${RHDH_NAMESPACE}
  labels:
    rhdh.redhat.com/ext-config-sync: "true"
type: Opaque
stringData:
  AAP_BASE_URL: "${AAP_BASE_URL}"
  AAP_TOKEN: "${AAP_TOKEN}"
EOF
else
  echo "    (skipping backstage-aap-secret — AAP_BASE_URL is empty)"
  oc apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: backstage-aap-secret
  namespace: ${RHDH_NAMESPACE}
  labels:
    rhdh.redhat.com/ext-config-sync: "true"
type: Opaque
stringData:
  AAP_BASE_URL: "https://placeholder.example.com"
  AAP_TOKEN: "placeholder"
EOF
fi

# ── Kubernetes ServiceAccount + token for the K8S plugin ──────────────────────
echo "==> Setting up Kubernetes SA token..."
oc apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: rhdh-kubernetes
  namespace: ${RHDH_NAMESPACE}
---
apiVersion: v1
kind: Secret
metadata:
  name: rhdh-kubernetes-token
  namespace: ${RHDH_NAMESPACE}
  annotations:
    kubernetes.io/service-account.name: rhdh-kubernetes
type: kubernetes.io/service-account-token
EOF

# Wait for token to be populated
echo "    Waiting for SA token..."
for i in $(seq 1 30); do
  TOKEN=$(oc get secret rhdh-kubernetes-token -n "$RHDH_NAMESPACE" -o jsonpath='{.data.token}' 2>/dev/null || true)
  if [[ -n "$TOKEN" ]]; then break; fi
  sleep 1
done

if [[ -z "${TOKEN:-}" ]]; then
  echo "ERROR: SA token not populated after 30s"
  exit 1
fi

K8S_TOKEN=$(echo "$TOKEN" | base64 -d)
oc apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: kubernetes-sa-token
  namespace: ${RHDH_NAMESPACE}
  labels:
    rhdh.redhat.com/ext-config-sync: "true"
type: Opaque
stringData:
  K8S_SERVICE_ACCOUNT_TOKEN: "${K8S_TOKEN}"
  KUBERNETES_SA_TOKEN: "${K8S_TOKEN}"
EOF

# ── Apply manifests ───────────────────────────────────────────────────────────
echo "==> Applying ClusterRole + ClusterRoleBinding (from backstage instance)..."
oc apply -f "$TMPDIR/devhub/05-backstage-instance.yaml" --selector=""  2>/dev/null || true
oc apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: rhdh-kubernetes-reader
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: backstage-kubernetes-reader
subjects:
  - kind: ServiceAccount
    name: rhdh-kubernetes
    namespace: ${RHDH_NAMESPACE}
EOF

echo "==> Applying PVC..."
oc apply -f "$TMPDIR/devhub/06-dynamic-plugins-pvc.yaml"

echo "==> Applying RBAC policy..."
oc apply -f "$TMPDIR/devhub/08-rbac-policy.yaml"

echo "==> Applying dynamic plugins..."
oc apply -f "$TMPDIR/devhub/09-dynamic-plugins.yaml"

echo "==> Applying Backstage instance + app-config..."
oc apply -f "$TMPDIR/devhub/05-backstage-instance.yaml"

# ── Wait for pod ──────────────────────────────────────────────────────────────
echo ""
echo "==> Waiting for RHDH pod to start (this may take 3-5 minutes)..."
for i in $(seq 1 60); do
  PHASE=$(oc get pods -n "$RHDH_NAMESPACE" -l rhdh.redhat.com/app=backstage-developer-hub -o jsonpath='{.items[0].status.phase}' 2>/dev/null || true)
  if [[ "$PHASE" == "Running" ]]; then
    echo "    Pod is Running!"
    break
  fi
  if (( i % 10 == 0 )); then
    echo "    Still waiting... ($PHASE)"
  fi
  sleep 5
done

ROUTE_URL=$(oc get route backstage-developer-hub -n "$RHDH_NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || true)

echo ""
echo "============================================"
echo " RHDH deployed to: https://${ROUTE_URL:-$RHDH_ROUTE}"
echo " Superadmin user : $RHDH_SUPERADMIN"
echo " Keycloak SSO    : $KEYCLOAK_BASE_URL/realms/$KEYCLOAK_REALM"
echo "============================================"
