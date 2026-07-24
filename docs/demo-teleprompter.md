# Zero to Prod with Zero Friction — Teleprompter Script

> Read naturally, not word-for-word. Pause at [PAUSE] marks. Actions in **[brackets]** are screen directions.

---

## Opening (30 seconds)

What if a developer could go from needing a virtual machine to having a fully provisioned, hardened, production-ready RHEL VM — with a running application, a dedicated service account, and a complete audit trail — just by filling out a single form?

That's what we're going to show you today. [PAUSE]

We call this demo "Zero to Prod with Zero Friction." It brings together five Red Hat technologies — Developer Hub, Ansible Automation Platform, OpenShift Virtualization, SonataFlow, and ServiceNow — into one seamless self-service experience.

---

## Act 1 — Everything as Code (2 minutes)

**[Show the GitHub repo: github.com/sumiranchugh/idp]**

Before anyone clicks a button, the entire service offering is defined as code. Let me walk you through what's in this repo.

**[Point to the folder structure]**

The `templates` folder has the Scaffolder templates — these define the self-service forms that developers interact with. The `workflows` folder has the SonataFlow orchestration — that's the approval and provisioning pipeline. `ansible/playbooks` has the Ansible automation for VM creation and application deployment. `catalog` has the Backstage catalog entities. And `devhub` has the platform configuration — plugins, RBAC, secrets.

**[Open templates/request-vm-servicenow-template.yaml]**

This is the developer-facing template. It defines three pages of form fields with validation rules, and a four-step execution pipeline — create a ServiceNow incident, create a change request, move it to assessment, and start the orchestrator workflow. This is the golden path.

**[Open ansible/playbooks/create-rhel-vm.yml]**

And this is the provisioning playbook. Two plays — the first creates the VM on OpenShift Virtualization with cloud-init, networking, and routes. The second SSHes into the VM, creates a service account, deploys a Flask app from PyPI, and hardens the security posture. Every parameter is configurable. Nothing is hardcoded. [PAUSE]

The key message here — every aspect of this service lives in Git. It's reviewable, auditable, version-controlled, and repeatable across environments.

---

## Act 2 — The Developer Experience (2 minutes)

**[Log in to RHDH as user1 / solnarchitect]**

Now let's switch to the developer's perspective. This is solnarchitect — a solutions architect on the Application Team. They've logged in through Keycloak SSO — the same identity provider the organization already uses.

**[Navigate to Create > Templates > "Run Flask App on RHEL VM"]**

solnarchitect sees the template catalog. Let's find "Run Flask App on RHEL VM" and click Choose.

**[Fill out Page 1 — VM Configuration]**

We name the VM, pick the namespace, choose RHEL 9, set CPU, memory, and disk size. Notice the validation — the VM name only accepts lowercase alphanumeric with hyphens. These guardrails are built into the template.

**[Fill out Page 2 — Access and Purpose]**

Here we set the VM username and optionally an SSH public key. And this field is important — "Business Justification." This is required. Whatever solnarchitect types here feeds directly into the ServiceNow change request for manager approval.

**[Fill out Page 3 — Review, then click Create]**

Now watch the four steps execute in sequence. [PAUSE]

Step one — ServiceNow incident created. Step two — change request created. Step three — the change request is moved to assessment, which activates the approve and reject buttons. Step four — the orchestrator workflow starts.

solnarchitect gets links to track the workflow, the ServiceNow incident, and the change request. They filled out one form. Behind the scenes, the platform created two ServiceNow records, initiated the approval process, and started the orchestration workflow. They didn't need to know about ServiceNow, Ansible, or OpenShift.

---

## Act 3 — Governance and Approval (1.5 minutes)

**[Open ServiceNow — dev423121.service-now.com]**

The workflow is now paused. No provisioning happens until governance controls are satisfied.

**[Navigate to the Change Request]**

Look at this change request. All the VM parameters are captured — name, CPUs, memory, disk size. The business justification is right here. It's assigned to the Application Development group. And the state is Assess — with Approve and Reject buttons visible.

**[Switch to RHDH Orchestrator view as platowner / user2]**

If we look at the orchestrator in Developer Hub, the workflow shows "Pending Manager Approval." It's in a callback state — it's not polling. It will resume only when ServiceNow sends a CloudEvent.

**[Go back to ServiceNow and click Approve]**

Now I approve the change request. Behind the scenes, a ServiceNow Business Rule fires, posts a CloudEvent to the SonataFlow callback URL, and the workflow resumes automatically. [PAUSE]

The approval happened entirely within ServiceNow — the system the operations team already uses. No new tools to learn. The entire approval chain is recorded for audit and compliance.

---

## Act 4 — Automated Provisioning (2 minutes)

**[Open AAP — Jobs page, show the running job]**

The workflow has triggered Ansible Automation Platform. Let's watch the provisioning playbook run.

**[Walk through the job output]**

Phase one — infrastructure. Ansible generates an ephemeral SSH key pair for bootstrap access. It creates the KubeVirt virtual machine with cloud-init. It waits for the VM to boot. Then it creates the SSH service, the HTTP service, and the OpenShift route with TLS edge termination. And it waits for SSH to become reachable.

Phase two — configuration. Ansible SSHes into the VM using that ephemeral key and creates a dedicated service account. Then it hardens the VM — it sets a random 24-character password, locks the root account, removes default sudo access, disables SSH password authentication, disables root login, and restarts sshd. After that, it installs Flask from PyPI, deploys the web application with a systemd service, verifies the app responds on port 80, and grants limited sudo — only systemctl restart and status for the webapp service. Finally, it injects the developer's SSH public key and removes the bootstrap key. [PAUSE]

Let me highlight the security model. There is no password anywhere in the VM spec — cloud-init only has the ephemeral public key. SSH password authentication is disabled. Root is locked. The cloud-init default sudo is removed. The service account gets least-privilege sudo — only for managing the webapp service. And the random password is stored only in AAP job artifacts — invisible to anyone with OpenShift access.

---

## Act 5 — The Result (2 minutes)

**[Navigate to the RHDH catalog — find the new VM entity]**

The workflow has completed. Let's see what happened. A new Resource entity has appeared in the catalog — it was registered automatically by the workflow.

**[Click into the VM entity page]**

Look at the tabs. Overview shows VM details and links. The Kubernetes tab shows the VirtualMachine and VirtualMachineInstance custom resources live from OpenShift. The Topology tab shows a visual view of the VM and its services. And the ServiceNow tab shows the incident record linked to this VM.

**[Click the Application URL link]**

Here's the live Flask app. It shows the hostname, kernel version, uptime, Python version, and the running user — which is the service account, not root.

**[Click Access Control]**

This page shows the service account, its allowed sudo commands — systemctl restart and status for webapp, and journalctl. And it explicitly shows what's denied — yum install, useradd, rm -rf, shutdown. Least privilege, enforced by Ansible.

**[Navigate to the parent component — RHEL VM Provisioning Service]**

Now let's see the platform engineer's view. This is platowner's single pane of glass. The ServiceNow tab shows all incidents across all VMs. The Kubernetes tab shows all VMs provisioned by this service. And the Workflows tab shows all orchestrator workflow runs.

**[Show ServiceNow — records auto-closed]**

Back in ServiceNow — the incident is resolved with close notes including the VM name and SSH access details. The change request is closed with close code "successful." Full audit trail — every state transition recorded.

---

## Act 6 — RBAC in Action (1.5 minutes)

**[Log in as user1 / solnarchitect]**

Let's talk about access control. This is solnarchitect — the solutions architect. Look at the catalog. They see entities owned by the Application Team — their VMs, their resources. They can also see components, templates, systems, and other shared entity types. They can run templates and view their workflow runs.

**[Point out what's NOT visible]**

But they cannot access the RBAC admin page. They don't have the orchestrator admin view. They can't delete or manage entities they don't own.

**[Log in as user2 / platowner]**

Now compare with platowner — the platform owner. platowner sees everything. All entities across all teams. The parent component with all ServiceNow tickets, all VMs, all workflow runs. The Orchestrator page shows all workflow instances across all users. And the RBAC page in the sidebar lets platowner manage roles and permissions.

**[Show the RBAC page briefly]**

The developer role gets conditional catalog access — they see entities owned by their group plus all shared kinds. The admin role gets full access to everything. [PAUSE]

This isn't just a visibility demo. This is real RBAC enforcement — conditional policies evaluated at the API level, not just UI filtering.

---

## Closing (30 seconds)

So let's recap what just happened. A developer filled out a single form. The platform handled everything — governance through ServiceNow, approval, VM provisioning on OpenShift Virtualization, application deployment, security hardening, catalog registration, and record closure. All automated, all auditable, all repeatable.

And this is a reusable pattern. The same template-workflow-playbook model extends to databases, middleware, Kubernetes namespaces — any infrastructure service the organization wants to offer as self-service. [PAUSE]

Zero to prod. Zero friction. That's the power of an Internal Developer Platform built on Red Hat.

---

## Timing Guide

| Section | Duration |
|---------|----------|
| Opening | 0:30 |
| Act 1 — Everything as Code | 2:00 |
| Act 2 — Developer Experience | 2:00 |
| Act 3 — Governance | 1:30 |
| Act 4 — Provisioning | 2:00 |
| Act 5 — The Result | 2:00 |
| Act 6 — RBAC | 1:30 |
| Closing | 0:30 |
| **Total** | **~12 minutes** |

## Quick Reference — URLs and Credentials

| What | URL |
|------|-----|
| RHDH | `https://backstage-developer-hub-developer-hub.apps.cluster-z5jjn.dyn.redhatworkshops.io` |
| AAP | `https://aap-platform-aap.apps.cluster-z5jjn.dyn.redhatworkshops.io` |
| ServiceNow | `https://dev423121.service-now.com` |
| Git Repo | `https://github.com/sumiranchugh/idp` |

| User | Display Name | Role |
|------|-------------|------|
| user1 | solnarchitect | developer (Application Team) |
| user2 | platowner | admin + rbac_admin (Platform Team) |
