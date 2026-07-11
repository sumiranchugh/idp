# ServiceNow Business Rule Update

The SN Business Rule "RHDH - Notify SonataFlow on CR Approval" needs these changes
to switch from direct CloudEvent POST to the HTTP callback pattern.

## Changes

### 1. URL path: `/` → `/callback`

Old:
```
var url = 'https://vm-provisioning-approval-developer-hub.apps.cluster-k5zwd.dyn.redhatworkshops.io/';
```

New:
```
var callbackUrl = current.u_callback_url.toString();
// Falls back to known URL if callback URL not stored yet
if (!callbackUrl) {
    callbackUrl = 'https://vm-provisioning-approval-developer-hub.apps.cluster-k5zwd.dyn.redhatworkshops.io/callback';
}
```

### 2. CloudEvent type: `vm.approval.decision` → `vmApprovalDecision`

Change the `ce-type` header from `vm.approval.decision` to `vmApprovalDecision`.
The channel name in the quarkus-http connector config must match the CloudEvent type
exactly, and dots in channel names break SmallRye property parsing.

### 3. Add `ce-kogitoprocrefid` header

The `kogitoprocrefid` CloudEvent extension tells the SonataFlow runtime which
workflow instance to resume. Without it, process context propagation to Data Index
breaks — node exit events have null processInstanceId and get dropped.

```javascript
request.setRequestHeader('ce-kogitoprocrefid', current.u_workflow_instance_id.toString());
```

## Complete Updated Business Rule Script

```javascript
(function executeRule(current, previous) {
    var request = new sn_ws.RESTMessageV2();

    // Read callback URL stored by the workflow's callback action
    var callbackUrl = current.u_callback_url.toString();
    if (!callbackUrl) {
        callbackUrl = 'https://vm-provisioning-approval-developer-hub.apps.cluster-k5zwd.dyn.redhatworkshops.io/callback';
    }
    request.setEndpoint(callbackUrl);
    request.setHttpMethod('POST');

    // Binary CloudEvent format
    request.setRequestHeader('Content-Type', 'application/json');
    request.setRequestHeader('ce-specversion', '1.0');
    request.setRequestHeader('ce-id', gs.generateGUID());
    request.setRequestHeader('ce-source', 'servicenow');
    request.setRequestHeader('ce-type', 'vmApprovalDecision');
    request.setRequestHeader('ce-sncrsysid', current.sys_id.toString());
    request.setRequestHeader('ce-kogitoprocrefid', current.u_workflow_instance_id.toString());

    var body = {
        approved: true,
        sncrsysid: current.sys_id.toString(),
        cr_number: current.number.toString()
    };
    request.setRequestBody(JSON.stringify(body));

    var response = request.execute();
    gs.info('SonataFlow callback response: ' + response.getStatusCode());
})(current, previous);
```

## Business Rule Filter (unchanged)

- Table: `change_request`
- When: `after` update
- Filter: `approval=approved^u_backstage_entity_idSTARTSWITHrhel-vm-provisioning`
