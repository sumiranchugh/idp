#!/bin/bash
# ============================================================
# Apply RHDH + ServiceNow integration config to OpenShift
# Run this AFTER your ServiceNow instance is ready
# ============================================================
# Replace placeholder values below before running

SN_INSTANCE="dev00000"                         # e.g. dev12345
SN_USER="rhdh_integration"
SN_PASSWORD="RHDHIntegration2024!"             # set during setup-servicenow.sh
SN_URL="https://${SN_INSTANCE}.service-now.com"

# ─────────────────────────────────────────────────────────────────
echo "Applying ServiceNow integration to Developer Hub..."
echo "ServiceNow: $SN_URL"
echo ""

# 1. Create/update DevHub secret with SN credentials
SN_BASIC_AUTH=$(echo -n "${SN_USER}:${SN_PASSWORD}" | base64)

oc create secret generic backstage-servicenow-secret \
  --namespace developer-hub \
  --from-literal=SN_BASE_URL="$SN_URL" \
  --from-literal=SN_USER="$SN_USER" \
  --from-literal=SN_PASSWORD="$SN_PASSWORD" \
  --from-literal=SN_BASIC_AUTH="$SN_BASIC_AUTH" \
  --dry-run=client -o yaml | oc apply -f -

echo "✅ Secret backstage-servicenow-secret created/updated"

# 2. Update the template files with real instance URL
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE_FILE="$SCRIPT_DIR/../templates/request-vm-servicenow-template.yaml"

sed -i.bak \
  -e "s|dev00000.service-now.com|${SN_INSTANCE}.service-now.com|g" \
  -e "s|cmhkaF9pbnRlZ3JhdGlvbjpSSERISW50ZWdyYXRpb24yMDI0IQ==|${SN_BASIC_AUTH}|g" \
  "$TEMPLATE_FILE"

echo "✅ Template updated with real ServiceNow instance URL"

# 3. Push updated template to GitHub
cd "$(git rev-parse --show-toplevel)"
git add developer-hub-config/templates/request-vm-servicenow-template.yaml
git commit -m "Update ServiceNow template with real instance: $SN_INSTANCE" || echo "(no changes to commit)"
git push origin main
echo "✅ Template pushed to GitHub"

# 4. Restart DevHub to pick up new secret
oc rollout restart deployment/backstage-developer-hub -n developer-hub
oc rollout status deployment/backstage-developer-hub -n developer-hub --timeout=300s
echo "✅ Developer Hub restarted"

echo ""
echo "============================================================"
echo "✅ Integration applied! Verify at:"
echo "   https://backstage-developer-hub-developer-hub.apps.cluster-k5zwd.dyn.redhatworkshops.io/create"
echo "   Look for: 'Request RHEL VM (With Approval)'"
echo "============================================================"
