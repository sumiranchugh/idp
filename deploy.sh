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
export AAP_BASE_URL AAP_TOKEN AAP_JOB_TEMPLATE_ID
export GITHUB_REPO_BASE GITHUB_TOKEN

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
    -e "s|__SN_BASE_URL__|${SN_BASE_URL}|g" \
    -e "s|__AAP_BASE_URL__|${AAP_BASE_URL}|g" \
    -e "s|__AAP_JOB_TEMPLATE_ID__|${AAP_JOB_TEMPLATE_ID}|g" \
    "$src" > "$dst"
}

mkdir -p "$TMPDIR/devhub" "$TMPDIR/workflows" "$TMPDIR/templates" "$TMPDIR/catalog"

for dir in devhub workflows templates catalog; do
  for f in "$dir"/*.yaml; do
    [[ -f "$SCRIPT_DIR/$f" ]] || continue
    substitute "$SCRIPT_DIR/$f" "$TMPDIR/$f"
  done
done

# ── Ensure namespaces exist ───────────────────────────────────────────────────
echo "==> Ensuring namespace $RHDH_NAMESPACE exists..."
oc get namespace "$RHDH_NAMESPACE" &>/dev/null || oc new-project "$RHDH_NAMESPACE" --skip-config-write

echo "==> Ensuring namespace vms exists..."
oc get namespace vms &>/dev/null || oc new-project vms --skip-config-write

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

if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  oc apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: backstage-github-token
  namespace: ${RHDH_NAMESPACE}
  labels:
    rhdh.redhat.com/ext-config-sync: "true"
type: Opaque
stringData:
  GITHUB_TOKEN: "${GITHUB_TOKEN}"
EOF
else
  echo "    (skipping backstage-github-token — GITHUB_TOKEN is empty)"
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

# ── Deploy SonataFlow workflow + callback route ──────────────────────────────
echo "==> Applying SonataFlow workflow..."
for f in "$TMPDIR"/workflows/*.yaml; do
  [[ -f "$f" ]] && oc apply -f "$f"
done

echo "==> Ensuring callback route for SonataFlow workflow..."
oc apply -f - <<EOF
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: vm-provisioning-approval
  namespace: ${RHDH_NAMESPACE}
spec:
  host: vm-provisioning-approval-${RHDH_NAMESPACE}.${CLUSTER_DOMAIN}
  port:
    targetPort: web
  tls:
    termination: edge
  to:
    kind: Service
    name: vm-provisioning-approval
    weight: 100
EOF

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

# ── RBAC conditional policy: developer sees only owned entities + shared kinds ─
echo "==> Applying RBAC conditional policy for developer role..."
PSQL_POD=$(oc get pod -n "$RHDH_NAMESPACE" -l postgres-operator.crunchydata.com/role=master -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || \
           oc get pod -n "$RHDH_NAMESPACE" -l statefulset.kubernetes.io/pod-name=backstage-psql-${RHDH_NAMESPACE}-0 -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || \
           echo "backstage-psql-${RHDH_NAMESPACE}-0")

oc exec "$PSQL_POD" -n "$RHDH_NAMESPACE" -- psql -U postgres -d backstage_plugin_permission -c "
DELETE FROM \"role-condition-policies\" WHERE \"roleEntityRef\" = 'role:default/developer' AND \"pluginId\" = 'catalog';
INSERT INTO \"role-condition-policies\" (\"roleEntityRef\", \"result\", \"pluginId\", \"resourceType\", \"permissions\", \"conditionsJson\")
VALUES (
  'role:default/developer',
  'CONDITIONAL',
  'catalog',
  'catalog-entity',
  '[\"read\"]',
  '{\"anyOf\":[{\"rule\":\"IS_ENTITY_OWNER\",\"resourceType\":\"catalog-entity\",\"params\":{\"claims\":[\"group:default/application-team\"]}},{\"rule\":\"IS_ENTITY_KIND\",\"resourceType\":\"catalog-entity\",\"params\":{\"kinds\":[\"template\",\"system\",\"group\",\"user\",\"location\",\"api\"]}}]}'
);
" 2>/dev/null && echo "    Conditional policy applied." || echo "    WARNING: Could not apply conditional policy. Apply manually via RBAC admin UI."

# ── Configure AAP resources ──────────────────────────────────────────────────
if [[ -n "${AAP_BASE_URL:-}" && "${AAP_BASE_URL}" != *"placeholder"* ]]; then
  echo ""
  echo "==> Configuring AAP..."

  AAP_ADMIN_PASS=$(oc get secret aap-platform-admin-password -n aap -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || true)
  if [[ -z "$AAP_ADMIN_PASS" ]]; then
    echo "    WARNING: Could not read AAP admin password from secret. Skipping AAP setup."
  else
    AAP_AUTH="-u admin:${AAP_ADMIN_PASS}"

    # OpenShift SA for AAP → K8s API
    echo "    Creating OpenShift ServiceAccount for AAP..."
    oc apply -f - <<SAEOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: aap-vm-provisioner
  namespace: vms
---
apiVersion: v1
kind: Secret
metadata:
  name: aap-vm-provisioner-token
  namespace: vms
  annotations:
    kubernetes.io/service-account.name: aap-vm-provisioner
type: kubernetes.io/service-account-token
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: aap-vm-provisioner-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - kind: ServiceAccount
    name: aap-vm-provisioner
    namespace: vms
SAEOF
    sleep 3
    OCP_TOKEN=$(oc get secret aap-vm-provisioner-token -n vms -o jsonpath='{.data.token}' | base64 -d)

    # Create AAP Project
    echo "    Creating AAP project..."
    curl -sk -X POST ${AAP_AUTH} -H "Content-Type: application/json" \
      "${AAP_BASE_URL}/api/controller/v2/projects/" \
      -d "{\"name\":\"vms\",\"description\":\"VM provisioning playbooks\",\"organization\":1,\"scm_type\":\"git\",\"scm_url\":\"${GITHUB_REPO_BASE%%/blob/*}.git\",\"scm_branch\":\"main\",\"scm_update_on_launch\":true}" >/dev/null 2>&1

    # Create OpenShift Credential
    echo "    Creating OpenShift credential..."
    curl -sk -X POST ${AAP_AUTH} -H "Content-Type: application/json" \
      "${AAP_BASE_URL}/api/controller/v2/credentials/" \
      -d "{\"name\":\"openshift-virtualization\",\"description\":\"OpenShift API for VM provisioning\",\"organization\":1,\"credential_type\":3,\"inputs\":{\"host\":\"${CLUSTER_API_URL}\",\"bearer_token\":\"${OCP_TOKEN}\",\"verify_ssl\":false}}" >/dev/null 2>&1

    # Create localhost Inventory + host
    echo "    Creating localhost inventory..."
    INV_RESULT=$(curl -sk -X POST ${AAP_AUTH} -H "Content-Type: application/json" \
      "${AAP_BASE_URL}/api/controller/v2/inventories/" \
      -d '{"name":"localhost","description":"Localhost inventory for API-based playbooks","organization":1}' 2>&1)
    INV_ID=$(echo "$INV_RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || true)
    if [[ -n "$INV_ID" ]]; then
      curl -sk -X POST ${AAP_AUTH} -H "Content-Type: application/json" \
        "${AAP_BASE_URL}/api/controller/v2/hosts/" \
        -d "{\"name\":\"localhost\",\"inventory\":${INV_ID},\"variables\":\"{\\\"ansible_connection\\\": \\\"local\\\"}\"}" >/dev/null 2>&1
    fi

    # Wait for project sync
    echo "    Waiting for project sync..."
    PROJECT_ID=$(curl -sk ${AAP_AUTH} "${AAP_BASE_URL}/api/controller/v2/projects/?name=vms" 2>&1 | \
      python3 -c "import sys,json; r=json.load(sys.stdin)['results']; print(r[0]['id'] if r else '')" 2>/dev/null || true)
    if [[ -n "$PROJECT_ID" ]]; then
      for i in $(seq 1 30); do
        STATUS=$(curl -sk ${AAP_AUTH} "${AAP_BASE_URL}/api/controller/v2/projects/${PROJECT_ID}/" 2>&1 | \
          python3 -c "import sys,json; print(json.load(sys.stdin).get('status',''))" 2>/dev/null || true)
        [[ "$STATUS" == "successful" ]] && break
        sleep 3
      done
    fi

    # Create Job Template
    echo "    Creating job template..."
    JT_RESULT=$(curl -sk -X POST ${AAP_AUTH} -H "Content-Type: application/json" \
      "${AAP_BASE_URL}/api/controller/v2/job_templates/" \
      -d "{\"name\":\"Create RHEL VM\",\"description\":\"Create a RHEL VM on OpenShift Virtualization with NGINX\",\"organization\":1,\"project\":${PROJECT_ID:-7},\"playbook\":\"ansible/playbooks/create-rhel-vm.yml\",\"inventory\":${INV_ID:-2},\"ask_variables_on_launch\":true}" 2>&1)
    JT_ID=$(echo "$JT_RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || true)

    # Associate credential
    if [[ -n "$JT_ID" ]]; then
      CRED_ID=$(curl -sk ${AAP_AUTH} "${AAP_BASE_URL}/api/controller/v2/credentials/?name=openshift-virtualization" 2>&1 | \
        python3 -c "import sys,json; r=json.load(sys.stdin)['results']; print(r[0]['id'] if r else '')" 2>/dev/null || true)
      if [[ -n "$CRED_ID" ]]; then
        curl -sk -X POST ${AAP_AUTH} -H "Content-Type: application/json" \
          "${AAP_BASE_URL}/api/controller/v2/job_templates/${JT_ID}/credentials/" \
          -d "{\"id\":${CRED_ID}}" >/dev/null 2>&1
      fi
      echo "    Job template created (ID: ${JT_ID})"
      echo ""
      echo "    *** IMPORTANT: Set AAP_JOB_TEMPLATE_ID=${JT_ID} in your .env file ***"
      echo "    *** Then re-run deploy.sh to update the workflow specs ConfigMap    ***"
    fi

    # Create AAP token with write scope for RHDH proxy
    echo "    Creating AAP token with write scope..."
    TOKEN_RESULT=$(curl -sk -X POST ${AAP_AUTH} -H "Content-Type: application/json" \
      "${AAP_BASE_URL}/api/gateway/v1/tokens/" \
      -d '{"description":"RHDH integration","scope":"write"}' 2>&1)
    NEW_AAP_TOKEN=$(echo "$TOKEN_RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('token',''))" 2>/dev/null || true)
    if [[ -n "$NEW_AAP_TOKEN" ]]; then
      echo "    AAP token created: ${NEW_AAP_TOKEN}"
      echo ""
      echo "    *** IMPORTANT: Set AAP_TOKEN=${NEW_AAP_TOKEN} in your .env file ***"
    fi

    echo "    AAP configuration complete!"
  fi
else
  echo ""
  echo "==> Skipping AAP setup (AAP_BASE_URL not set)"
fi

echo ""
echo "============================================"
echo " RHDH deployed to: https://${ROUTE_URL:-$RHDH_ROUTE}"
echo " Superadmin user : $RHDH_SUPERADMIN"
echo " Keycloak SSO    : $KEYCLOAK_BASE_URL/realms/$KEYCLOAK_REALM"
echo "============================================"
