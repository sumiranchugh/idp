# ServiceNow Business Rules for VM Provisioning

## Active Rules

### 1. RHDH - Notify SonataFlow on CR Approval

**sys_id:** `126383e42f0ecb109217a8aa6fa4e335`

Fires when a Change Request is approved. Sends a CloudEvent to the SonataFlow
workflow's `/callback` endpoint to resume the approval flow.

- Table: `change_request`
- When: `after` update
- Filter: `approval=approved^u_backstage_entity_idSTARTSWITHrhel-vm-provisioning`

**Key design decisions:**
- Always uses the external OpenShift route URL (SN is external, cannot reach
  internal Kubernetes service URLs)
- Sends `ce-kogitoprocrefid` header with the workflow instance ID for process
  context propagation to Data Index
- Uses `ce-type: vmApprovalDecision` (no dots — dots break SmallRye property parsing)

```javascript
(function executeRule(current, previous) {
  if (current.approval != 'approved' || previous.approval == 'approved') return;

  var crSysId = current.sys_id.toString();
  var crNumber = current.number.toString();
  var workflowInstanceId = current.u_workflow_instance_id ? current.u_workflow_instance_id.toString() : '';

  // Always use the external OpenShift route — SN is external and cannot reach
  // internal Kubernetes service URLs that the workflow might store.
  var callbackUrl = 'https://vm-provisioning-approval-developer-hub.apps.cluster-k5zwd.dyn.redhatworkshops.io/callback';

  var r = new sn_ws.RESTMessageV2();
  r.setEndpoint(callbackUrl);
  r.setHttpMethod('POST');
  r.setRequestHeader('Content-Type', 'application/json');
  r.setRequestHeader('ce-specversion', '1.0');
  r.setRequestHeader('ce-type', 'vmApprovalDecision');
  r.setRequestHeader('ce-source', 'servicenow');
  r.setRequestHeader('ce-id', crSysId + '-approved');
  r.setRequestHeader('ce-sncrsysid', crSysId);
  if (workflowInstanceId) {
    r.setRequestHeader('ce-kogitoprocrefid', workflowInstanceId);
  }
  r.setRequestBody(JSON.stringify({approved: true, crNumber: crNumber}));
  var resp = r.execute();
  gs.info('SonataFlow callback CR ' + crNumber + ' instanceId=' + workflowInstanceId + ' HTTP ' + resp.getStatusCode());

})(current, previous);
```

## Disabled Rules

### 2. RHDH - Provision VM on CR Approval (DISABLED)

**sys_id:** `db84eee82f0acb109217a8aa6fa4e36a`

Previously active. Disabled because:
- Tried to trigger AAP directly from SN (AAP is triggered by the workflow, not SN)
- Used wrong CloudEvent format (`vm.approval.decision` instead of `vmApprovalDecision`)
- Used internal cluster URL that SN cannot reach
- Had a broad filter (`approvalCHANGES`) that would fire on any CR approval change

## Custom Fields on change_request

| Field | Label | Type | Purpose |
|-------|-------|------|---------|
| `u_backstage_entity_id` | Backstage Entity ID | string | Links CR to RHDH catalog entity |
| `u_workflow_instance_id` | Workflow Instance ID | string | SonataFlow process instance ID for callback correlation |
| `u_callback_url` | Callback URL | string | Stored by workflow (internal URL, not used by BR) |
| `u_incident_sys_id` | Incident Sys ID | string | Links CR to associated Incident |
| `u_vm_name` | VM Name | string | VM configuration |
| `u_vm_namespace` | VM Namespace | string | VM configuration |
| `u_vm_rhel_version` | RHEL Version | string | VM configuration |
| `u_vm_cpus` | VM CPUs | string | VM configuration |
| `u_vm_memory` | VM Memory | string | VM configuration |
| `u_vm_disk_size` | VM Disk Size | string | VM configuration |
| `u_vm_user` | VM User | string | VM configuration |
| `u_aap_triggered` | AAP Triggered | string | Guard flag (legacy) |
