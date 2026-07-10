#!/bin/bash
# ============================================================
# ServiceNow Setup Script for VM Provisioning Integration
# ============================================================
# Replace the DUMMY values below with your real instance details
# before running.
#
# Usage:
#   chmod +x setup-servicenow.sh
#   ./setup-servicenow.sh
# ============================================================

set -e

# ─── CONFIGURATION — swap these when your SN instance is ready ───────────────
SN_INSTANCE="dev00000"                                      # e.g. dev12345
SN_URL="https://${SN_INSTANCE}.service-now.com"
SN_USER="admin"
SN_PASSWORD="YOUR_SERVICENOW_PASSWORD"                      # from SN welcome email

AAP_URL="https://aap-platform-ansible-automation-platform.apps.cluster-k5zwd.dyn.redhatworkshops.io"
AAP_TOKEN="YOUR_AAP_TOKEN"                              # run: oc get secret aap-platform-admin-password -n ansible-automation-platform -o jsonpath='{.data.password}' | base64 -d
AAP_JOB_TEMPLATE_ID="9"

RHDH_URL="https://backstage-developer-hub-developer-hub.apps.cluster-k5zwd.dyn.redhatworkshops.io"
# ─────────────────────────────────────────────────────────────────────────────

SN_AUTH="$SN_USER:$SN_PASSWORD"
HEADERS=('-H' 'Content-Type: application/json' '-H' 'Accept: application/json')

echo "============================================================"
echo "Setting up ServiceNow for VM Provisioning Integration"
echo "Instance: $SN_URL"
echo "============================================================"

# ── 1. Verify connectivity ────────────────────────────────────────────────────
echo ""
echo "[1/6] Verifying ServiceNow connectivity..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -u "$SN_AUTH" "$SN_URL/api/now/table/sys_user?sysparm_limit=1")
if [[ "$HTTP_CODE" != "200" ]]; then
  echo "ERROR: Cannot connect to $SN_URL (HTTP $HTTP_CODE). Check credentials."
  exit 1
fi
echo "    ✅ Connected to $SN_URL"

# ── 2. Create RHDH integration user ──────────────────────────────────────────
echo ""
echo "[2/6] Creating RHDH integration user..."
USER_RESP=$(curl -s -u "$SN_AUTH" "${HEADERS[@]}" -X POST \
  "$SN_URL/api/now/table/sys_user" \
  -d "{
    \"user_name\": \"rhdh_integration\",
    \"first_name\": \"Red Hat\",
    \"last_name\": \"Developer Hub\",
    \"email\": \"rhdh@integration.local\",
    \"active\": true,
    \"password_needs_reset\": false
  }")

USER_SYS_ID=$(echo "$USER_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['result']['sys_id'])" 2>/dev/null)
if [[ -z "$USER_SYS_ID" ]]; then
  echo "    ⚠️  User may already exist, fetching existing..."
  USER_SYS_ID=$(curl -s -u "$SN_AUTH" \
    "$SN_URL/api/now/table/sys_user?sysparm_query=user_name=rhdh_integration&sysparm_fields=sys_id" \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['result'][0]['sys_id'])" 2>/dev/null)
fi
echo "    ✅ Integration user sys_id: $USER_SYS_ID"

# Set password for integration user
curl -s -u "$SN_AUTH" "${HEADERS[@]}" -X PATCH \
  "$SN_URL/api/now/table/sys_user/$USER_SYS_ID" \
  -d '{"user_password": "RedHat123!"}' > /dev/null

# Assign itil role to integration user
ROLE_RESP=$(curl -s -u "$SN_AUTH" \
  "$SN_URL/api/now/table/sys_user_role?sysparm_query=name=itil&sysparm_fields=sys_id")
ITIL_ROLE_ID=$(echo "$ROLE_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['result'][0]['sys_id'])" 2>/dev/null)

curl -s -u "$SN_AUTH" "${HEADERS[@]}" -X POST \
  "$SN_URL/api/now/table/sys_user_has_role" \
  -d "{\"user\": \"$USER_SYS_ID\", \"role\": \"$ITIL_ROLE_ID\"}" > /dev/null
echo "    ✅ ITIL role assigned"

# ── 3. Create VM Provisioning Catalog Item ────────────────────────────────────
echo ""
echo "[3/6] Creating VM Provisioning Catalog Item..."

# Get Service Catalog sys_id
CATALOG_ID=$(curl -s -u "$SN_AUTH" \
  "$SN_URL/api/now/table/sc_catalog?sysparm_query=title=Service+Catalog&sysparm_fields=sys_id" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['result'][0]['sys_id'])" 2>/dev/null)

# Create catalog category
CAT_RESP=$(curl -s -u "$SN_AUTH" "${HEADERS[@]}" -X POST \
  "$SN_URL/api/now/table/sc_category" \
  -d "{
    \"title\": \"Infrastructure\",
    \"catalog\": \"$CATALOG_ID\",
    \"description\": \"Infrastructure provisioning services\"
  }")
CATEGORY_ID=$(echo "$CAT_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['result']['sys_id'])" 2>/dev/null || echo "")

# Create catalog item
ITEM_RESP=$(curl -s -u "$SN_AUTH" "${HEADERS[@]}" -X POST \
  "$SN_URL/api/now/table/sc_cat_item" \
  -d "{
    \"name\": \"Provision RHEL Virtual Machine\",
    \"short_description\": \"Request a RHEL virtual machine on OpenShift Virtualization\",
    \"description\": \"Self-service provisioning of RHEL VMs via Ansible Automation Platform. Requires manager approval before provisioning begins.\",
    \"category\": \"$CATEGORY_ID\",
    \"active\": true,
    \"availability\": \"on_both\",
    \"sc_ic_item_staging\": false
  }")

CATALOG_ITEM_SYS_ID=$(echo "$ITEM_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['result']['sys_id'])" 2>/dev/null)
echo "    ✅ Catalog item sys_id: $CATALOG_ITEM_SYS_ID"

# ── 4. Create catalog item variables (form fields) ────────────────────────────
echo ""
echo "[4/6] Adding catalog item variables..."

create_variable() {
  local name=$1 label=$2 type=$3 default=$4 mandatory=$5 order=$6
  curl -s -u "$SN_AUTH" "${HEADERS[@]}" -X POST \
    "$SN_URL/api/now/table/item_option_new" \
    -d "{
      \"cat_item\": \"$CATALOG_ITEM_SYS_ID\",
      \"name\": \"$name\",
      \"question_text\": \"$label\",
      \"type\": \"$type\",
      \"default_value\": \"$default\",
      \"mandatory\": $mandatory,
      \"order\": $order
    }" > /dev/null
  echo "    + Variable: $label"
}

# type 6 = single-line text, type 7 = multi-line text, type 3 = yes/no, type 5 = select box
create_variable "vm_name"       "VM Name"          "6" ""          "true"  100
create_variable "vm_namespace"  "Namespace"        "6" "vms"       "true"  200
create_variable "rhel_version"  "RHEL Version"     "6" "9"         "true"  300
create_variable "vm_cpus"       "CPU Cores"        "6" "2"         "true"  400
create_variable "vm_memory"     "Memory"           "6" "4Gi"       "true"  500
create_variable "vm_disk_size"  "Disk Size"        "6" "30Gi"      "true"  600
create_variable "vm_user"       "VM Username"      "6" "cloud-user" "false" 700
create_variable "justification" "Business Justification" "7" "" "true" 800

echo "    ✅ Variables created"

# ── 5. Create REST Message for AAP integration ────────────────────────────────
echo ""
echo "[5/6] Creating AAP REST Message integration..."

# Create REST message
REST_MSG_RESP=$(curl -s -u "$SN_AUTH" "${HEADERS[@]}" -X POST \
  "$SN_URL/api/now/table/sys_rest_message" \
  -d "{
    \"name\": \"AAP - Launch VM Provisioning Job\",
    \"rest_endpoint\": \"$AAP_URL/api/controller/v2/job_templates/$AAP_JOB_TEMPLATE_ID/launch/\",
    \"authentication_type\": \"basic\",
    \"basic_auth_user_name\": \"admin\",
    \"basic_auth_password\": \"dummy_replace_with_aap_password\"
  }")

REST_MSG_ID=$(echo "$REST_MSG_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['result']['sys_id'])" 2>/dev/null)

# Create HTTP method on the REST message
curl -s -u "$SN_AUTH" "${HEADERS[@]}" -X POST \
  "$SN_URL/api/now/table/sys_rest_message_fn" \
  -d "{
    \"rest_message\": \"$REST_MSG_ID\",
    \"name\": \"launch\",
    \"http_method\": \"post\",
    \"content\": \"{\\\"extra_vars\\\": {\\\"vm_name\\\": \\\"\${vm_name}\\\", \\\"vm_namespace\\\": \\\"\${vm_namespace}\\\", \\\"vm_cpus\\\": \${vm_cpus}, \\\"vm_memory\\\": \\\"\${vm_memory}\\\", \\\"vm_disk_size\\\": \\\"\${vm_disk_size}\\\", \\\"rhel_version\\\": \\\"\${rhel_version}\\\", \\\"vm_user\\\": \\\"\${vm_user}\\\"}}\"
  }" > /dev/null

echo "    ✅ AAP REST Message created (sys_id: $REST_MSG_ID)"
echo "    ⚠️  Update AAP password in: System Web Services → REST Messages → 'AAP - Launch VM Provisioning Job'"

# ── 6. Output summary ─────────────────────────────────────────────────────────
echo ""
echo "============================================================"
echo "✅ ServiceNow Setup Complete!"
echo "============================================================"
echo ""
echo "Catalog Item sys_id : $CATALOG_ITEM_SYS_ID"
echo "REST Message sys_id : $REST_MSG_ID"
echo "Integration user    : rhdh_integration / RedHat123!"
echo ""
echo "Manual steps still required (cannot be scripted via REST API):"
echo ""
echo "A) Create Approval Workflow:"
echo "   1. Go to: Flow Designer → Create New Flow"
echo "   2. Name: 'VM Provisioning Approval'"
echo "   3. Trigger: Service Catalog → 'Provision RHEL Virtual Machine'"
echo "   4. Add Action: 'Ask for Approval' → Approver: Manager of requester"
echo "   5. Add If/Else: If approved → Add Action: REST Step using 'AAP - Launch VM Provisioning Job'"
echo "   6. If rejected → Update request state to 'Rejected'"
echo "   7. Activate the flow"
echo ""
echo "B) Update AAP password in REST Message:"
echo "   1. System Web Services → REST Messages → 'AAP - Launch VM Provisioning Job'"
echo "   2. Update Basic Auth password to your AAP admin password"
echo "   OR change auth to use token: Authorization header = Bearer $AAP_TOKEN"
echo ""
echo "C) Add RHDH back-link in approval email:"
echo "   Include this URL in SN notification template:"
echo "   $RHDH_URL"
echo ""
echo "Next: Run apply-rhdh-sn-config.sh to update Developer Hub"
echo "============================================================"
