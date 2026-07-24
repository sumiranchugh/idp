# Zero to Prod with Zero Friction

## Self-Service Infrastructure & Application Delivery through Red Hat Developer Hub

---

## What is Red Hat Developer Hub?

You already have ServiceNow for change management, Ansible for automation, and OpenShift for infrastructure. Each one works. The gap is that they're disconnected — an approved change request in ServiceNow doesn't automatically trigger Ansible provisioning, and neither system gives the requestor a single place to track the full lifecycle from request to running workload.

Red Hat Developer Hub (RHDH) is Red Hat's supported distribution of [Backstage](https://backstage.io) — an internal portal that **connects your existing tools** into a single self-service interface. It provides:

- **Software Catalog** — A single place to discover and manage all your software assets (services, APIs, VMs, infrastructure)
- **Software Templates** — Self-service forms that create ServiceNow records, trigger Ansible automation, and register results — all through your existing governance
- **Plugin Ecosystem** — Extensible with plugins for ServiceNow, Ansible, Kubernetes, ArgoCD, and more — all surfaced in one UI
- **RBAC** — Role-based access control so each team sees what they need and platform owners control what's allowed

Nothing changes about your ServiceNow process or your approval workflows. What changes is that the handoff from "approved" to "done" becomes automated, auditable, and visible in one place.

---

## The Story

Meet **solnarchitect** (user1), an infrastructure solutions architect on the Application Team. They need a RHEL virtual machine to host a Flask-based microservice. Today, that means creating an incident in ServiceNow, filing a change request, waiting for approval, then coordinating with the infrastructure team for manual provisioning. After the VM is up, someone has to go back and close the ServiceNow records. The governance works — but the provisioning and lifecycle tracking are manual.

With Developer Hub, solnarchitect fills out one form. ServiceNow handles approval the way it always does. Everything after the approval — provisioning, application deployment, security hardening, catalog registration, and closing the ServiceNow records — happens automatically.

**platowner** (user2) is the Platform Owner who designed and manages this self-service golden path — the templates, workflows, playbooks, and RBAC policies that make it all work. platowner sees everything — all workflow runs, all provisioned infrastructure, all ServiceNow records — from a single pane of glass. solnarchitect only sees what's relevant to their team.

---

## Act 1: The Golden Path — Everything as Code

> **Capability: Infrastructure and Application Definitions as Code**

Before solnarchitect ever clicks a button, platowner has defined the entire service offering as code, stored in Git, version-controlled and auditable.

### What to show

1. **Open the Git repository** — `github.com/sumiranchugh/idp`

   Walk through the structure:

   | Path | Purpose |
   |------|---------|
   | `templates/` | Scaffolder templates — the self-service forms |
   | `workflows/` | SonataFlow orchestration — the approval + provisioning pipeline |
   | `ansible/playbooks/` | Ansible automation — VM creation, app deployment, hardening |
   | `catalog/` | Backstage catalog entities — the service catalog |
   | `devhub/` | RHDH platform configuration — plugins, RBAC, secrets |

2. **Highlight key files:**

   - **`templates/request-vm-servicenow-template.yaml`** — The user-facing template designed by platowner. Defines the form fields, validation rules, and the 4-step execution pipeline (create SN incident, create SN change request, move to assessment, start orchestrator workflow). This is the "golden path" definition.

   - **`ansible/playbooks/create-rhel-vm.yml`** — The provisioning playbook. Two plays: Play 1 creates the VM on OpenShift Virtualization with cloud-init, networking, and routes. Play 2 SSHes into the VM, creates the service account, deploys the Flask app from PyPI, hardens security, and configures access controls. Everything is parameterized and repeatable.

   - **`ansible/playbooks/configure-aap.yml`** — Even AAP itself is configured as code. This playbook creates the project, credentials, inventories, and job templates in AAP using the `awx.awx` collection. No manual AAP setup required.

   - **`workflows/sonataflow-vm-provisioning.yaml`** — The SonataFlow workflow definition. 8 states orchestrating the full lifecycle from approval through provisioning to catalog registration and ServiceNow closure.

### Key message

> "Every aspect of this service — the form users see, the approval workflow, the provisioning logic, the security controls, the platform configuration — lives in Git. It's reviewable, auditable, version-controlled, and repeatable across environments."

---

## Act 2: The Self-Service Experience

> **Capability: Self-Service Portal**

### What to show

1. **Log in as solnarchitect (user1)** at the RHDH portal

   URL: `https://backstage-developer-hub-developer-hub.apps.cluster-z5jjn.dyn.redhatworkshops.io`

   solnarchitect authenticates via Keycloak SSO — the same identity provider the organization already uses. This is the only interface they touch — they don't need to open ServiceNow to create an incident or file a change request manually.

2. **Navigate to Create > Templates**

   solnarchitect sees the template catalog. Find **"Run Flask App on RHEL VM"**.

   > Point out: solnarchitect sees only what they're authorized to see. The RBAC policy (configured by platowner) gives them the `developer` role — they can run templates and view the catalog, but they cannot manage RBAC or delete entities.

3. **Fill out the request form** (3 pages):

   **Page 1 — VM Configuration:**
   | Field | Value | Notes |
   |-------|-------|-------|
   | VM Name | `demo-vm-01` | Regex-validated: lowercase, alphanumeric, hyphens |
   | Namespace | `vms` | Default |
   | RHEL Version | `RHEL 9 (Latest)` | Dropdown with RHEL 8 option |
   | CPU Cores | `2` | Range: 1-16 |
   | Memory | `4 GiB` | Preset options up to 32 GiB |
   | Disk Size | `30 GiB` | Preset options up to 200 GiB |

   **Page 2 — Access & Purpose:**
   | Field | Value | Notes |
   |-------|-------|-------|
   | VM Username | `cloud-user` | Default |
   | SSH Public Key | *(paste key)* | Optional — enables passwordless SSH to the service account |
   | Business Justification | `"Need a RHEL VM to host the new inventory microservice for Q3 release"` | **Required** — feeds into ServiceNow approval |

   **Page 3 — Review:**
   Shows the 4-step process: Submit > Manager Review > Auto-Provision > Notification

4. **Click Create**

   The template executes 4 steps in sequence — show the progress:

   - Step 1: ServiceNow Incident created (for RHDH tracking)
   - Step 2: ServiceNow Change Request created (for manager approval)
   - Step 3: Change Request moved to Assessment (activates Approve/Reject buttons)
   - Step 4: Orchestrator workflow started

5. **Show the output page**

   solnarchitect gets:
   - A link to **track the workflow** in the Orchestrator
   - A link to the **ServiceNow Incident** (tracking record)
   - A link to the **ServiceNow Change Request** (approval record)
   - A summary table of all parameters

### Key message

> "solnarchitect filled out one form in one portal. The platform created the ServiceNow incident and change request using your existing ServiceNow instance, initiated the approval process through your existing change management workflow, and started the orchestration. solnarchitect didn't need to open ServiceNow, learn Ansible, or have OpenShift access — they just asked for what they needed."

---

## Act 3: Your Existing Approval Process

> **Capability: ServiceNow Approval Integration**

The workflow is now paused, waiting for manager approval. No provisioning happens until your change management process is satisfied.

### What to show

1. **Open ServiceNow** — `https://dev423121.service-now.com`

   Navigate to the Change Request. It looks exactly like any other CR in your instance — because it is one. Show:
   - All VM parameters captured in custom fields (`u_vm_name`, `u_vm_cpus`, etc.)
   - The business justification from solnarchitect's request
   - Assignment to the **Application Development** group
   - State: **Assess** with **Approve / Reject** buttons visible
   - The linked Incident record for audit trail
   
   > Your change managers review and approve this CR exactly the way they review any other change request. Nothing new to learn.

2. **Show the Orchestrator in RHDH** (as platowner/user2)

   Navigate to the Orchestrator page. The workflow instance shows status: **"Pending Manager Approval"**. The workflow is in a callback state — it's not polling. It will resume only when ServiceNow sends a CloudEvent.

3. **Approve the Change Request in ServiceNow**

   Click **Approve**. Behind the scenes:
   - ServiceNow's Business Rule fires
   - It POSTs a CloudEvent to the SonataFlow callback URL
   - The CloudEvent carries `ce-kogitoprocrefid` matching the workflow instance ID
   - The workflow resumes automatically

4. **Return to RHDH Orchestrator** — the workflow status changes to **"VM Provisioning In Progress"**

### Key message

> "Your approval process stays in ServiceNow where it belongs — nothing changes for your change managers. The workflow waited patiently for approval, and resumed automatically the moment it was granted via a CloudEvent callback. The entire approval chain is recorded in ServiceNow exactly as it would be for any other change request."

---

## Act 4: Automated Provisioning — Ansible in Action

> **Capabilities: RHEL VM Provisioning + Application Deployment + Service Account Creation + Access Management**

The workflow has triggered Ansible Automation Platform. The provisioning playbook is now running.

### What to show

1. **Open AAP** — `https://aap-platform-aap.apps.cluster-z5jjn.dyn.redhatworkshops.io`

   Navigate to Jobs. Show the running job. Walk through the task output:

   **Phase 1 — Infrastructure (Play 1: localhost):**
   - Generates ephemeral Ed25519 SSH key pair (bootstrap access — never stored in OpenShift)
   - Generates random 24-character password (stored only in AAP artifacts)
   - Creates the KubeVirt VirtualMachine with cloud-init (no password in VM spec — only the public key)
   - Waits for VM to boot and become ready
   - Creates SSH Service (ClusterIP port 22)
   - Creates HTTP Service (ClusterIP port 80)
   - Creates OpenShift Route with TLS edge termination
   - Waits for SSH to become reachable
   - Sends completion CloudEvent back to the SonataFlow workflow

   **Phase 2 — Configuration (Play 2: SSH into VM):**
   - Creates service account `svc_demo_vm_01` with dedicated home directory
   - **Security hardening:**
     - Sets random password (hashed, `no_log` — not visible in job output)
     - Locks root account entirely
     - Removes cloud-init default sudoers
     - Disables wheel group sudo
     - Removes bootstrap SSH key
     - Disables SSH password authentication
     - Disables SSH root login
     - Restarts sshd
   - Installs Flask from PyPI
   - Deploys the web application with systemd service
   - Verifies the application responds on port 80
   - Grants limited sudo: only `systemctl restart/status webapp` and `journalctl`
   - Injects the requestor's SSH public key into the service account

2. **Show the security model** (talking point, or show `oc get vm -o yaml`):

   | Security Control | Implementation |
   |-----------------|----------------|
   | No password in VM spec | cloud-init only has the ephemeral public key |
   | SSH password auth disabled | `PasswordAuthentication no` in sshd_config |
   | Root locked | `password_lock: true` + `PermitRootLogin no` |
   | No default sudo | cloud-init sudoers removed, wheel group disabled |
   | Least-privilege sudo | Service account can only manage the webapp service |
   | Random password | 24 chars, stored only in AAP job artifacts |
   | Bootstrap key cleaned up | Ephemeral key deleted after provisioning |

### Key message

> "In under 10 minutes, Ansible provisioned a RHEL VM, deployed a Flask application, created a dedicated service account, hardened the security posture, and granted least-privilege access — all without any human intervention. The password is random per VM and stored only in AAP, invisible to anyone with OpenShift access."

---

## Act 5: The Result — Everything in One Place

> **Capability: Service Catalog + Lifecycle Tracking**

The workflow has completed. The VM is registered in the catalog. ServiceNow records are closed.

### What to show

1. **The new VM entity in the catalog**

   Navigate to the catalog. A new Resource entity **"RHEL VM: demo-vm-01"** has appeared — it was created automatically by the workflow (pushed to Git, registered in Backstage).

   Show the entity page tabs:
   - **Overview** — VM details, links to the live application, health check, access control page
   - **Kubernetes** — Shows the VirtualMachine and VirtualMachineInstance custom resources live from OpenShift
   - **Topology** — Visual topology view of the VM and its services
   - **ServiceNow** — The incident record linked to this VM

2. **Click the Application link** — opens the live Flask app

   Show the dashboard: hostname, kernel version, uptime, Python version, running user (`svc_demo_vm_01`).

   Click **Access Control** (`/access`) — shows:
   - Service account name and shell
   - Allowed sudo commands (systemctl restart/status webapp, journalctl)
   - Denied commands (yum/dnf install, useradd, rm -rf, shutdown)

   Click **Health Check** (`/health`) — returns JSON: `{"status": "healthy", "app": "demo-vm-01"}`

3. **The parent component — single pane of glass**

   Navigate to **RHEL VM Provisioning Service** (`rhel-vm-provisioning` component).

   This is platowner's view. Show:
   - **ServiceNow tab** — ALL incidents across ALL VMs, aggregated. Shows both open and resolved.
   - **Kubernetes tab** — ALL VMs provisioned by this service (matched by label `provisioned-by=rhel-vm-provisioning`)
   - **Topology tab** — Visual map of all VM workloads
   - **Workflows tab** — ALL orchestrator workflow runs (only visible here, not on individual VM entities)

4. **ServiceNow — records auto-closed**

   Return to ServiceNow. Show:
   - The Incident is **Resolved** with close notes: "VM demo-vm-01 provisioned successfully. Status: Running. SSH: ssh cloud-user@..."
   - The Change Request is **Closed** with close code: "successful"
   - Full audit trail: every state transition recorded
   
   > This is what usually requires a manual follow-up — someone remembering to go back and close the ticket. Here it happens automatically, with accurate details, the moment the workflow completes.

### Key message

> "The solutions architect got their VM. The platform owner sees everything from one dashboard. ServiceNow has the complete audit trail — incident resolved, change request closed, every state transition recorded. Nothing changed about your ServiceNow process. What changed is that the handoff from 'approved' to 'done' is now automated, auditable, and visible in one place."

---

## Act 6: Platform Governance — The Owner's View

> **Capability: RBAC + Governance**

### What to show

1. **Log in as solnarchitect (user1)** — show what they see:
   - The Software Catalog shows only entities **owned by their team** (application-team) — their VMs, their resources
   - They can also see shared kinds (Components, Templates, Systems, etc.) in read-only mode
   - They can run templates and view their own workflow runs
   - They cannot access the RBAC admin page

2. **Log in as platowner (user2)** — show the difference:
   - platowner sees **everything** in the catalog — all entities across all teams
   - The parent component shows all ServiceNow tickets, all VMs, all workflow runs
   - The **Orchestrator** page shows all workflow instances across all users
   - The **RBAC** page in the sidebar lets platowner manage roles and permissions
   - platowner can refresh, delete, and manage catalog entities

3. **RBAC page** — Show the role assignments:
   - `developer` role: conditional catalog access (own group + shared kinds), scaffolder use, orchestrator use
   - `admin` role: full catalog access, orchestrator admin views, RBAC management
   - platowner configured these roles — they control who sees what

4. **AAP job artifacts** — Only AAP admins can retrieve the randomly generated VM password. It's not in OpenShift, not in Git, not in ServiceNow.

---

## Technical Architecture

```
Infra Solutions Architect (solnarchitect)
    |
    v
Red Hat Developer Hub ──── Keycloak SSO (authentication)
    |                        |
    |  1. Submit request     |  RBAC (authorization)
    v                        |
Scaffolder Template ─────────┘
    |
    |  2. Create SN records
    v
ServiceNow ──────────────── Manager approves CR
    |
    |  3. CloudEvent callback
    v
SonataFlow Orchestrator ──── Workflow state management
    |                        PostgreSQL persistence
    |  4. Launch AAP job
    v
Ansible Automation Platform
    |
    |  5. Provision + Configure
    v
OpenShift Virtualization
    |
    |  KubeVirt VM + Services + Route
    v
RHEL VM
    |── Flask app (systemd, port 80)
    |── Service account (svc_*)
    |── Security hardening (locked root, no password SSH)
    |── Limited sudo (webapp management only)
    |
    |  6. Register in catalog
    v
Backstage Catalog ──────── Git-backed entity (GitHub API)
    |
    |  7. Close SN records
    v
ServiceNow ──────────────── Incident resolved, CR closed
```

---

## Success Criteria Mapping

| Criteria | Status | Evidence |
|----------|--------|----------|
| User can request a service through RHDH | Done | Template "Run Flask App on RHEL VM" with 3-page wizard |
| ServiceNow approval is initiated and completed | Done | Incident + Change Request created, CR moved to Assess, approval triggers callback, both auto-closed on completion |
| RHEL VM is automatically provisioned | Done | KubeVirt VM with DataVolumeTemplate, cloud-init, SSH/HTTP services, OpenShift Route |
| Application is installed and configured | Done | Flask app from PyPI, systemd service, health check verification, config.json |
| Service account is created with appropriate access | Done | `svc_<vm_name>` user, SSH key injection, limited NOPASSWD sudo, locked root, no password SSH |
| Repeatable, auditable, automated workflow | Done | Git-backed IaC, SonataFlow 8-state orchestration, SN audit trail, AAP job logs, RBAC enforcement |

---

## Environment Details

| Component | URL |
|-----------|-----|
| Red Hat Developer Hub | `https://backstage-developer-hub-developer-hub.apps.cluster-z5jjn.dyn.redhatworkshops.io` |
| Ansible Automation Platform | `https://aap-platform-aap.apps.cluster-z5jjn.dyn.redhatworkshops.io` |
| ServiceNow | `https://dev423121.service-now.com` |
| OpenShift Console | `https://console-openshift-console.apps.cluster-z5jjn.dyn.redhatworkshops.io` |

| User | Role | Credentials |
|------|------|-------------|
| user1 (solnarchitect — Infra Solutions Architect) | developer | Keycloak SSO |
| user2 (platowner — Platform Owner / Workflow Owner) | admin + rbac_admin | Keycloak SSO |

---

## Beyond the PoC — What's Next

This demo establishes a **reusable pattern** that extends your existing ServiceNow and Ansible investments:

- **Additional service offerings** — The same template/workflow/playbook pattern extends to databases, middleware, Kubernetes namespaces, or any infrastructure service — each one creating and closing ServiceNow records through your existing change management process
- **Multi-cluster** — The configuration is templatized with `__PLACEHOLDER__` tokens and a `deploy.sh` script — switching clusters requires only updating a `.env` file
- **Enterprise identity** — Keycloak integration supports LDAP/AD federation for production SSO
- **Cost tracking** — ServiceNow records can feed into your existing chargeback/showback models
- **Compliance** — Every action is logged in ServiceNow, AAP, and Git — the same audit trail your compliance team already uses, now populated automatically
