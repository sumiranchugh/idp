# Zero to Prod with Zero Friction — Teleprompter Script

> Read naturally, not word-for-word. Pause at [PAUSE] marks. Actions in **[brackets]** are screen directions.

---

## Opening — The Problem and the Portal (1.5 minutes)

You have the tools. ServiceNow for change management. Ansible for automation. OpenShift for infrastructure. Each one works. [PAUSE]

But they work in silos. When someone needs a VM today, they file a ticket in ServiceNow. A change manager approves it — in ServiceNow. Then someone picks up that approval and manually kicks off an Ansible job. When the VM is ready, someone else updates the CMDB. And if you want to know the full status — from request to running workload — you're checking three or four different consoles and hoping the information is current.

The pieces are automated. But the end-to-end process is not orchestrated. There's no single place where a requestor can ask for infrastructure and track it through approval, provisioning, and into production. And there's no single place where a platform owner can see all provisioned assets, all workflow runs, and all governance records together.

That's what Red Hat Developer Hub solves. It's an internal portal — Red Hat's supported distribution of Backstage — that becomes the **single pane of glass** for all your software assets and the **orchestration layer** that ties your existing tools together into governed, self-service golden paths. [PAUSE]

Your tools don't change. Your processes don't change. What Developer Hub adds is the orchestration between them and a unified catalog of everything that gets provisioned — with full RBAC so each team sees exactly what they should.

We have two personas today. **solnarchitect** is an infrastructure solutions architect who needs a RHEL VM. **platowner** is the platform owner who designed this golden path — connecting Developer Hub, ServiceNow, Ansible, and OpenShift into one orchestrated workflow with guardrails at every step.

---

## Act 1 — Everything as Code (2 minutes)

**[Show the GitHub repo: github.com/sumiranchugh/idp]**

Before anyone fills out a form, platowner has defined the entire service offering as code. This is the golden path — and every guardrail is built in. Let me walk you through what's here.

**[Point to the folder structure]**

The `templates` folder has the Scaffolder templates — these define the self-service forms with validation rules. The `workflows` folder has the SonataFlow orchestration — the engine that ties approval to provisioning to catalog registration in a single pipeline. `ansible/playbooks` has the automation. `catalog` has the Backstage catalog entities. And `devhub` has the platform configuration — plugins, RBAC, secrets.

**[Open templates/request-vm-servicenow-template.yaml]**

This is the template platowner designed. It defines three pages of form fields with validation — regex on VM names, dropdown constraints on CPU and memory, a required business justification field. These are the guardrails. A requestor can't skip the justification. They can't name a VM with uppercase characters. The golden path enforces organizational standards at the point of request. [PAUSE]

The template also defines a four-step execution pipeline — create a ServiceNow incident, create a change request, move it to assessment, and start the orchestrator workflow. One click from the user triggers a coordinated sequence across ServiceNow and SonataFlow.

**[Open ansible/playbooks/create-rhel-vm.yml]**

And this is what runs after approval. Two plays — the first creates the VM on OpenShift Virtualization with cloud-init, networking, and routes. The second SSHes in, creates a service account, deploys a Flask app, and hardens the security posture. Every security control — locked root, disabled password SSH, least-privilege sudo — is enforced by the playbook, not left to the requestor. [PAUSE]

The key point: everything lives in Git. The self-service form, the orchestration pipeline, the provisioning logic, the security controls. platowner can update any guardrail through a pull request. It's version-controlled, auditable, and repeatable.

---

## Act 2 — The Self-Service Experience (2 minutes)

**[Log in to RHDH as user1 / solnarchitect]**

Now let's see what this looks like for the requestor. This is solnarchitect — an infrastructure solutions architect. They need a RHEL VM to host a microservice. They've logged into Developer Hub through Keycloak SSO.

This is the only interface solnarchitect touches. One portal. They don't open ServiceNow. They don't log into Ansible. They don't touch the OpenShift console. Developer Hub orchestrates all of that behind the scenes.

**[Navigate to Create > Templates > "Run Flask App on RHEL VM"]**

solnarchitect sees the template catalog — only the templates they're authorized to use. Let's click Choose.

**[Fill out Page 1 — VM Configuration]**

We name the VM, pick the namespace, choose RHEL 9, set CPU, memory, and disk size. Notice the validation — the VM name only accepts lowercase alphanumeric with hyphens. Memory is a constrained dropdown. These guardrails are baked into the template by platowner.

**[Fill out Page 2 — Access and Purpose]**

Here we set the VM username and optionally paste an SSH public key. And this field — "Business Justification" — is required. This text flows into the ServiceNow change request. It's a governance control — no justification, no VM.

**[Fill out Page 3 — Review, then click Create]**

Now watch. [PAUSE]

Step one — ServiceNow incident created. Step two — change request created with all the VM parameters. Step three — the CR is moved to Assess state. Step four — the SonataFlow orchestrator starts and immediately pauses, waiting for approval.

One form submission. Four coordinated actions across two systems. solnarchitect gets links to track everything — the workflow, the incident, the change request — all from right here in Developer Hub. That's the single pane of glass in action.

---

## Act 3 — Governance Built In (1.5 minutes)

**[Open ServiceNow — dev423121.service-now.com]**

Here's the governance layer. The workflow is paused. Nothing gets provisioned until approval is granted. This is a guardrail — not optional, not bypassable.

**[Navigate to the Change Request]**

The change request is in ServiceNow exactly where your change managers expect it. All the VM parameters are in custom fields. The business justification is here. State is Assess, Approve and Reject are visible. Your change managers work in ServiceNow the way they always do — Developer Hub doesn't change that.

**[Switch to RHDH Orchestrator view as platowner / user2]**

Meanwhile, in Developer Hub, the Orchestrator shows the workflow in a "Pending Manager Approval" state. It's a callback — not polling. The workflow will resume only when a CloudEvent arrives from ServiceNow.

**[Go back to ServiceNow and click Approve]**

I approve the change request. A ServiceNow Business Rule fires a CloudEvent to SonataFlow. The workflow resumes. [PAUSE]

That's the orchestration. The approval happens in ServiceNow. The provisioning is triggered automatically. No one has to copy a ticket number from ServiceNow and paste it into Ansible. No one has to manually start a job. Developer Hub orchestrates the handoff.

---

## Act 4 — Automated Provisioning with Guardrails (2 minutes)

**[Open AAP — Jobs page, show the running job]**

Ansible Automation Platform is running the provisioning playbook. Let's watch.

**[Walk through the job output]**

Phase one — infrastructure. Ansible generates an ephemeral SSH key pair for bootstrap access. It creates the KubeVirt virtual machine with cloud-init. It waits for the VM to boot. Then it creates the SSH service, the HTTP service, and the OpenShift route with TLS edge termination.

Phase two — configuration and hardening. This is where the security guardrails are enforced. Ansible SSHes into the VM and creates a dedicated service account. Then it locks the VM down — random 24-character password, root account locked, default sudo removed, SSH password authentication disabled, root login disabled. After that, it deploys the Flask application with a systemd service, verifies it responds, and grants the service account limited sudo — only systemctl restart and status for the webapp. Finally, it injects the requestor's SSH key and removes the bootstrap key. [PAUSE]

Let me highlight what platowner has built into this playbook as guardrails. There is no password anywhere in the VM spec — cloud-init only has the ephemeral public key. SSH password authentication is disabled. Root is locked. The service account gets least-privilege sudo — not full admin. The random password is stored only in AAP job artifacts — invisible to anyone with OpenShift access. And the bootstrap key is cleaned up after provisioning.

These security controls are not optional. They're not a checklist someone follows manually. They're enforced by the playbook every single time. That's what a golden path with guardrails means.

---

## Act 5 — The Single Pane of Glass (2.5 minutes)

**[Navigate to the RHDH catalog — find the new VM entity]**

The workflow has completed. Let me show you what Developer Hub looks like now — this is where the single pane of glass really comes together.

A new Resource entity has appeared in the catalog — registered automatically. Nobody had to manually add it.

**[Click into the VM entity page]**

Look at what's unified in one place. The Overview tab shows VM details and links. The Kubernetes tab shows the VirtualMachine and VirtualMachineInstance custom resources — live from OpenShift. The Topology tab shows a visual view. And the ServiceNow tab shows the incident record linked to this VM. [PAUSE]

Kubernetes data, ServiceNow data, application links — all on one entity page. Before Developer Hub, you'd check the OpenShift console for VM status, ServiceNow for the ticket, and maybe SSH into the box to verify the app. Now it's one page.

**[Click the Application URL link]**

Here's the live Flask app. Hostname, kernel version, uptime, Python version, and the running user — the service account, not root.

**[Click Access Control]**

This page shows the service account, its allowed sudo commands, and what's denied. Visibility into the security posture right from the catalog.

**[Navigate to the parent component — RHEL VM Provisioning Service]**

Now here's platowner's view — the real single pane of glass. The ServiceNow tab shows all incidents across all VMs — not just this one. The Kubernetes tab shows every VM provisioned by this service. The Workflows tab shows every orchestrator run. One place to see all provisioned assets, all governance records, all workflow history.

**[Show ServiceNow — records auto-closed]**

And the lifecycle is complete. Back in ServiceNow — the incident is resolved with close notes including the VM name, status, and SSH details. The change request is closed with close code "successful." Every state transition recorded. [PAUSE]

The full loop — from request through approval, provisioning, catalog registration, to ServiceNow closure — orchestrated end to end. No manual follow-ups. No stale tickets. The orchestration handles the lifecycle, and the catalog reflects the current state.

---

## Act 6 — RBAC — Who Sees What (1.5 minutes)

**[Log in as user1 / solnarchitect]**

Guardrails aren't just about provisioning — they're about visibility too. This is solnarchitect. Look at the catalog. They see entities owned by the Application Team — their VMs, their resources. They see shared kinds — components, templates, systems — in read-only mode. They can run templates and view their workflow runs.

**[Point out what's NOT visible]**

But they cannot access the RBAC admin page. They don't see the orchestrator admin view. They can't delete or manage entities they don't own. The catalog is scoped to what's relevant to them.

**[Log in as user2 / platowner]**

Now compare with platowner. platowner sees everything. All entities across all teams. The parent component with all ServiceNow tickets, all VMs, all workflow runs. The Orchestrator page shows all workflow instances across all users. And the RBAC page lets platowner manage roles and permissions.

**[Show the RBAC page briefly]**

The "developer" role gets conditional catalog access — entities owned by their group plus shared kinds. The "admin" role gets full access. These are enforced at the API level, not just UI filtering. Every plugin respects the same RBAC boundary. [PAUSE]

This is what it means to have a governed portal. platowner controls the golden paths, the guardrails, and the visibility — all from Developer Hub.

---

## Closing (1 minute)

Let me step back and frame what you just saw. [PAUSE]

You have ServiceNow, Ansible, and OpenShift. Each one works. But when solnarchitect needs a VM, they're navigating between those systems, and the handoffs between them are manual.

Developer Hub sits on top as the single pane of glass and the orchestration layer. One portal where a solutions architect fills out a form with built-in guardrails. One orchestrated pipeline that coordinates ServiceNow approval, Ansible provisioning, security hardening, and catalog registration — end to end. One catalog where every provisioned asset is visible with its Kubernetes state, its ServiceNow records, and its application health — all in one place. And RBAC that controls who sees what and who can do what across every plugin.

The tools don't change. The processes don't change. What Developer Hub adds is the orchestration between them, the catalog that unifies them, and the guardrails that govern them. [PAUSE]

One portal. Full orchestration. Every guardrail in place. Zero friction.

---

## Timing Guide

| Section | Duration |
|---------|----------|
| Opening — Problem and Portal | 1:30 |
| Act 1 — Everything as Code | 2:00 |
| Act 2 — Self-Service Experience | 2:00 |
| Act 3 — Governance Built In | 1:30 |
| Act 4 — Provisioning with Guardrails | 2:00 |
| Act 5 — Single Pane of Glass | 2:30 |
| Act 6 — RBAC | 1:30 |
| Closing | 1:00 |
| **Total** | **~14 minutes** |

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
