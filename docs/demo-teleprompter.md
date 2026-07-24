# Zero to Prod with Zero Friction — Teleprompter Script

> Read naturally, not word-for-word. Pause at [PAUSE] marks. Actions in **[brackets]** are screen directions.

---

## Opening — The Problem and the Portal (1 minute)

You already have ServiceNow. You already have change management, approval workflows, and audit trails. That side works. [PAUSE]

The gap is what happens after the approval. Someone approves a change request in ServiceNow — and then what? A different team picks up the ticket, manually provisions a VM, manually configures it, manually updates ServiceNow when it's done. The requestor has no visibility. The approver has no feedback loop. And nobody has a single place to see the full lifecycle — from request, through approval, to running workload.

Red Hat Developer Hub closes that gap. It's an internal portal — Red Hat's supported distribution of Backstage — that connects your existing ServiceNow governance with automated provisioning. The requestor fills out one form. ServiceNow handles approval the way it always does. And everything after that — provisioning, configuration, security hardening, catalog registration, closing the ServiceNow records — happens automatically.

Your ServiceNow processes don't change. Your approvers keep working in ServiceNow. What changes is that the handoff from "approved" to "done" becomes instant and auditable. [PAUSE]

We have two personas today. **solnarchitect** is an infrastructure solutions architect who needs a RHEL VM. **platowner** is the platform owner who designed this self-service workflow — connecting Developer Hub, ServiceNow, Ansible, and OpenShift into a single golden path.

---

## Act 1 — Everything as Code (2 minutes)

**[Show the GitHub repo: github.com/sumiranchugh/idp]**

Before anyone fills out a form, platowner has defined the entire service offering as code. Let me walk you through what's in this repo.

**[Point to the folder structure]**

The `templates` folder has the Scaffolder templates — these define the self-service forms. The `workflows` folder has the SonataFlow orchestration — the pipeline that ties ServiceNow approval to Ansible provisioning. `ansible/playbooks` has the automation for VM creation and application deployment. `catalog` has the Backstage catalog entities. And `devhub` has the platform configuration — plugins, RBAC, secrets.

**[Open templates/request-vm-servicenow-template.yaml]**

This is the user-facing template that platowner designed. It defines three pages of form fields with validation rules, and a four-step execution pipeline — create a ServiceNow incident, create a change request, move it to assessment, and start the orchestrator workflow. Notice — the template talks directly to your ServiceNow instance via the REST API. It creates the incident, the change request, and moves the CR to the Assess state so the Approve and Reject buttons are active for your change managers.

**[Open ansible/playbooks/create-rhel-vm.yml]**

And this is the provisioning playbook. Two plays — the first creates the VM on OpenShift Virtualization with cloud-init, networking, and routes. The second SSHes into the VM, creates a service account, deploys a Flask app from PyPI, and hardens the security posture. Every parameter is configurable. Nothing is hardcoded. [PAUSE]

The key point — everything lives in Git. The form, the ServiceNow integration, the approval-to-provisioning pipeline, the security controls. It's version-controlled, auditable, and repeatable. platowner can update any part of this workflow through a pull request.

---

## Act 2 — The Self-Service Experience (2 minutes)

**[Log in to RHDH as user1 / solnarchitect]**

Now let's switch to the requestor's perspective. This is solnarchitect — an infrastructure solutions architect. They need a RHEL VM to host a microservice for their team. They've logged into Developer Hub through Keycloak SSO.

Notice — this is the only interface solnarchitect touches. They don't open ServiceNow to create an incident. They don't file a change request manually. The portal does that for them — using your existing ServiceNow instance and your existing change management process.

**[Navigate to Create > Templates > "Run Flask App on RHEL VM"]**

solnarchitect sees the template catalog. Let's find "Run Flask App on RHEL VM" and click Choose.

**[Fill out Page 1 — VM Configuration]**

We name the VM, pick the namespace, choose RHEL 9, set CPU, memory, and disk size. Notice the validation — the VM name only accepts lowercase alphanumeric with hyphens. These guardrails are built into the template by platowner.

**[Fill out Page 2 — Access and Purpose]**

Here we set the VM username and optionally paste an SSH public key. And this field — "Business Justification" — is required. This text flows directly into the ServiceNow change request description. Your change managers see exactly what the requestor wrote, just as if they'd filed the CR manually.

**[Fill out Page 3 — Review, then click Create]**

Now watch the four steps execute. [PAUSE]

Step one — ServiceNow incident created for tracking. Step two — change request created with all the VM parameters in custom fields. Step three — the CR is moved to Assess, which activates the Approve and Reject buttons in your ServiceNow instance. Step four — the SonataFlow orchestrator workflow starts and immediately pauses, waiting for approval.

solnarchitect gets links to the workflow, the incident, and the change request — all from right here. They can click through to ServiceNow if they want to check the CR status, or they can track everything from this portal.

---

## Act 3 — Your Existing Approval Process (1.5 minutes)

**[Open ServiceNow — dev423121.service-now.com]**

Here's the important part for your team. The workflow is paused. Nothing gets provisioned until your change management process is satisfied.

**[Navigate to the Change Request]**

Look at this change request. It looks exactly like any other CR in your ServiceNow instance — because it is one. All the VM parameters are captured in custom fields. The business justification from solnarchitect's form is right here. It's assigned to the Application Development group. State is Assess. Approve and Reject buttons are visible.

Your change managers don't need to learn anything new. They review and approve this CR the same way they review every other change request. [PAUSE]

**[Switch to RHDH Orchestrator view as platowner / user2]**

Meanwhile, if we look at the orchestrator in Developer Hub, the workflow shows "Pending Manager Approval." It's in a callback state — not polling. It's waiting for a CloudEvent from ServiceNow.

**[Go back to ServiceNow and click Approve]**

Now I approve the change request. Behind the scenes, a ServiceNow Business Rule fires and sends a CloudEvent to the SonataFlow callback URL. The workflow resumes automatically. No manual handoff. No second ticket. The approval in ServiceNow directly triggers the provisioning pipeline. [PAUSE]

That's the integration — your approval process stays in ServiceNow where it belongs. The automation picks up exactly where your change managers leave off.

---

## Act 4 — Automated Provisioning (2 minutes)

**[Open AAP — Jobs page, show the running job]**

The workflow has triggered Ansible Automation Platform. Let's watch the provisioning playbook run.

**[Walk through the job output]**

Phase one — infrastructure. Ansible generates an ephemeral SSH key pair for bootstrap access. It creates the KubeVirt virtual machine with cloud-init. It waits for the VM to boot. Then it creates the SSH service, the HTTP service, and the OpenShift route with TLS edge termination. And it waits for SSH to become reachable.

Phase two — configuration. Ansible SSHes into the VM using that ephemeral key and creates a dedicated service account. Then it hardens the VM — it sets a random 24-character password, locks the root account, removes default sudo access, disables SSH password authentication, disables root login, and restarts sshd. After that, it installs Flask from PyPI, deploys the web application with a systemd service, verifies the app responds on port 80, and grants limited sudo — only systemctl restart and status for the webapp service. Finally, it injects the requestor's SSH public key and removes the bootstrap key. [PAUSE]

Let me highlight the security model. There is no password anywhere in the VM spec — cloud-init only has the ephemeral public key. SSH password authentication is disabled. Root is locked. The service account gets least-privilege sudo. And the random password is stored only in AAP job artifacts — invisible to anyone with OpenShift access.

This runs the same way every time. No manual steps. No configuration drift.

---

## Act 5 — The Result and the Closed Loop (2 minutes)

**[Navigate to the RHDH catalog — find the new VM entity]**

The workflow has completed. A new Resource entity has appeared in the catalog — registered automatically by the workflow.

**[Click into the VM entity page]**

Look at the tabs. Overview shows VM details and links. The Kubernetes tab shows the VirtualMachine and VirtualMachineInstance custom resources live from OpenShift. The Topology tab shows a visual view. And here's what matters for your ServiceNow team — the ServiceNow tab shows the incident record linked to this VM, right inside Developer Hub.

**[Click the Application URL link]**

Here's the live Flask app. Hostname, kernel version, uptime, Python version, and the running user — the service account, not root.

**[Click Access Control]**

This page shows the service account, its allowed sudo commands, and what's denied. Least privilege, enforced by Ansible.

**[Navigate to the parent component — RHEL VM Provisioning Service]**

Now let's see platowner's view. The ServiceNow tab shows all incidents across all VMs — your ServiceNow data surfaced right inside the portal. The Kubernetes tab shows all VMs provisioned by this service. The Workflows tab shows all orchestrator runs. One place for everything.

**[Show ServiceNow — records auto-closed]**

And here's the closed loop. Back in ServiceNow — the incident is resolved with close notes including the VM name, status, and SSH access details. The change request is closed with close code "successful." Every state transition recorded. [PAUSE]

This is what usually takes a manual follow-up — someone remembering to go back and close the ticket after provisioning. Here it happens automatically, with accurate details, the moment the workflow completes.

---

## Act 6 — RBAC in Action (1.5 minutes)

**[Log in as user1 / solnarchitect]**

Let's talk about access control. This is solnarchitect — the infrastructure solutions architect. Look at the catalog. They see entities owned by the Application Team — their VMs, their resources. They can also see components, templates, systems, and other shared entity types in read-only mode. They can run templates and view their workflow runs.

**[Point out what's NOT visible]**

But they cannot access the RBAC admin page. They don't have the orchestrator admin view. They can't delete or manage entities they don't own.

**[Log in as user2 / platowner]**

Now compare with platowner — the platform owner. platowner sees everything. All entities across all teams. The parent component with all ServiceNow tickets, all VMs, all workflow runs. The Orchestrator page shows all workflow instances across all users. And the RBAC page lets platowner manage roles and permissions.

**[Show the RBAC page briefly]**

The role named "developer" gets conditional catalog access — users in that role see entities owned by their group plus all shared kinds. The admin role gets full access. These are enforced at the API level — not just UI filtering. [PAUSE]

platowner controls exactly what each team can see and do, and that enforcement is consistent across the UI, the API, and every plugin.

---

## Closing (45 seconds)

Let me recap what you just saw. [PAUSE]

An infrastructure solutions architect filled out one form. The platform created ServiceNow records using your existing change management process. A change manager approved the CR in ServiceNow — exactly the way they approve any other change. That approval automatically triggered VM provisioning, application deployment, security hardening, and catalog registration. And when it was done, ServiceNow was updated and closed automatically — the full loop.

Nothing changed about your ServiceNow process. What changed is that everything after the approval is automated, auditable, and visible in one place. And this pattern extends — databases, middleware, namespaces, any infrastructure service you want to offer as self-service through your existing governance.

One portal. Your existing ServiceNow. Full automation. Zero friction. [PAUSE]

---

## Timing Guide

| Section | Duration |
|---------|----------|
| Opening — Problem and Portal | 1:00 |
| Act 1 — Everything as Code | 2:00 |
| Act 2 — Self-Service Experience | 2:00 |
| Act 3 — Your Existing Approval Process | 1:30 |
| Act 4 — Provisioning | 2:00 |
| Act 5 — Result and Closed Loop | 2:00 |
| Act 6 — RBAC | 1:30 |
| Closing | 0:45 |
| **Total** | **~13 minutes** |

## Quick Reference — URLs and Credentials

| What | URL |
|------|-----|
| RHDH | `https://backstage-developer-hub-developer-hub.apps.cluster-z5jjn.dyn.redhatworkshops.io` |
| AAP | `https://aap-platform-aap.apps.cluster-z5jjn.dyn.redhatworkshops.io` |
| ServiceNow | `https://dev423121.service-now.com` |
| Git Repo | `https://github.com/sumiranchugh/idp` |

| User | Display Name | Role | Persona |
|------|-------------|------|---------|
| user1 | solnarchitect | developer | Infrastructure Solutions Architect — requests VMs |
| user2 | platowner | admin + rbac_admin | Platform Owner — designs and manages the golden path |
