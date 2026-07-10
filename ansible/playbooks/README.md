# RHEL VM Provisioning on OpenShift Virtualization

Ansible playbooks for creating, managing, and deleting RHEL virtual machines on OpenShift Virtualization.

## Prerequisites

1. **OpenShift Virtualization** installed (✅ already installed on your cluster)
2. **RHEL boot sources** available in `openshift-virtualization-os-images` namespace
3. **Storage class** available (default: `ocs-external-storagecluster-ceph-rbd`)
4. **Ansible collections** installed (kubernetes.core, community.general)

## Playbooks

### 1. Create RHEL VM (`create-rhel-vm.yml`)

Creates a new RHEL virtual machine with specified configuration.

**Variables:**
- `vm_name` - Name of the VM (required)
- `vm_namespace` - Namespace to create VM in (default: `vms`)
- `vm_cpus` - Number of CPUs (default: `2`)
- `vm_memory` - Memory size (default: `4Gi`)
- `vm_disk_size` - Root disk size (default: `50Gi`)
- `rhel_version` - RHEL version: `9` or `8` (default: `9`)
- `vm_user` - VM username (default: `cloud-user`)
- `vm_password` - VM password (default: `redhat`)
- `ssh_public_key` - SSH public key for authentication (optional)
- `environment` - Environment tag: `development`, `staging`, `production`
- `expose_ssh_route` - Create external SSH route (default: `false`)

**Example:**
```bash
ansible-playbook playbooks/create-rhel-vm.yml \
  -e vm_name=test-rhel9 \
  -e vm_cpus=4 \
  -e vm_memory=8Gi \
  -e vm_disk_size=100Gi \
  -e rhel_version=9
```

### 2. Delete RHEL VM (`delete-rhel-vm.yml`)

Deletes a VM and all associated resources.

**Variables:**
- `vm_name` - Name of the VM to delete (required)
- `vm_namespace` - Namespace of the VM (default: `vms`)

**Example:**
```bash
ansible-playbook playbooks/delete-rhel-vm.yml \
  -e vm_name=test-rhel9 \
  -e vm_namespace=vms
```

### 3. List VMs (`list-vms.yml`)

Lists all VMs in a namespace.

**Variables:**
- `vm_namespace` - Namespace to list VMs from (default: `vms`)

**Example:**
```bash
ansible-playbook playbooks/list-vms.yml \
  -e vm_namespace=vms
```

## Setup in Ansible Automation Platform

### 1. Create Project

1. Login to AAP: https://ansible-controller-ansible-automation-platform.apps.cluster-k5zwd.dyn.redhatworkshops.io
2. Go to **Projects** → **Add**
3. Fill in:
   - **Name:** `OpenShift VM Provisioning`
   - **Organization:** `Default`
   - **Source Control Type:** `Git`
   - **Source Control URL:** `<your-git-repo-url>` (after you push this to Git)
   - **Source Control Branch/Tag/Commit:** `main`
   - **Update Revision on Launch:** ✓

### 2. Create Credentials

#### OpenShift Credential

1. Go to **Credentials** → **Add**
2. Fill in:
   - **Name:** `openshift-cluster`
   - **Credential Type:** `OpenShift or Kubernetes API Bearer Token`
   - **OpenShift or Kubernetes API Endpoint:** `https://api.cluster-k5zwd.dyn.redhatworkshops.io:6443`
   - **API authentication bearer token:** (Use a ServiceAccount token - see below)
   - **Verify SSL:** ✓ (or uncheck for testing)

**To get ServiceAccount token:**
```bash
# Create ServiceAccount for Ansible
oc create sa ansible-vm-provisioner -n ansible-automation-platform

# Grant cluster-admin (or specific permissions)
oc adm policy add-cluster-role-to-user cluster-admin -z ansible-vm-provisioner -n ansible-automation-platform

# Get token
oc create token ansible-vm-provisioner -n ansible-automation-platform --duration=87600h
# Copy this token and paste it in AAP credential
```

### 3. Create Job Template

1. Go to **Templates** → **Add** → **Job Template**
2. Fill in:
   - **Name:** `Create RHEL VM on OpenShift`
   - **Job Type:** `Run`
   - **Inventory:** `Demo Inventory`
   - **Project:** `OpenShift VM Provisioning`
   - **Playbook:** `playbooks/create-rhel-vm.yml`
   - **Credentials:** Select `openshift-cluster`
   - **Verbosity:** `1 (Verbose)`
   - **Options:**
     - ✓ Enable Webhook
     - ✓ Concurrent Jobs
     - ✓ Prompt on launch: Variables

3. **Add Survey:**
   - Click **Survey** tab → **Add**
   
   **Question 1: VM Name**
   - Prompt: `VM Name`
   - Answer Variable Name: `vm_name`
   - Answer Type: `Text`
   - Required: ✓
   - Min/Max Length: 3/30
   
   **Question 2: Namespace**
   - Prompt: `Namespace`
   - Answer Variable Name: `vm_namespace`
   - Answer Type: `Text`
   - Default: `vms`
   - Required: ✓
   
   **Question 3: CPU Count**
   - Prompt: `CPU Cores`
   - Answer Variable Name: `vm_cpus`
   - Answer Type: `Integer`
   - Minimum: `1`
   - Maximum: `16`
   - Default: `2`
   - Required: ✓
   
   **Question 4: Memory**
   - Prompt: `Memory Size`
   - Answer Variable Name: `vm_memory`
   - Answer Type: `Multiple Choice (single select)`
   - Multiple Choice Options:
     - `2Gi`
     - `4Gi`
     - `8Gi`
     - `16Gi`
     - `32Gi`
   - Default: `4Gi`
   - Required: ✓
   
   **Question 5: Disk Size**
   - Prompt: `Disk Size`
   - Answer Variable Name: `vm_disk_size`
   - Answer Type: `Multiple Choice (single select)`
   - Multiple Choice Options:
     - `20Gi`
     - `50Gi`
     - `100Gi`
     - `200Gi`
     - `500Gi`
   - Default: `50Gi`
   - Required: ✓
   
   **Question 6: RHEL Version**
   - Prompt: `RHEL Version`
   - Answer Variable Name: `rhel_version`
   - Answer Type: `Multiple Choice (single select)`
   - Multiple Choice Options:
     - `9`
     - `8`
   - Default: `9`
   - Required: ✓
   
   **Question 7: Environment**
   - Prompt: `Environment`
   - Answer Variable Name: `environment`
   - Answer Type: `Multiple Choice (single select)`
   - Multiple Choice Options:
     - `development`
     - `staging`
     - `production`
   - Default: `development`
   - Required: ✓
   
   **Question 8: VM Username**
   - Prompt: `VM Username`
   - Answer Variable Name: `vm_user`
   - Answer Type: `Text`
   - Default: `cloud-user`
   - Required: ✓
   
   **Question 9: VM Password**
   - Prompt: `VM Password`
   - Answer Variable Name: `vm_password`
   - Answer Type: `Password`
   - Default: `redhat`
   - Required: ✓

4. **Save** the template

### 4. Test the Job Template

1. Go to **Templates** → Find your template → Click **Launch** (rocket icon)
2. Fill in the survey questions
3. Click **Next** → **Launch**
4. Watch the job output
5. When complete, check OpenShift:
   ```bash
   oc get vm -n vms
   oc get vmi -n vms
   ```

## Accessing VMs

### From Inside Cluster

```bash
# SSH to VM (from a pod in the cluster)
ssh cloud-user@<vm-name>-ssh.<namespace>.svc.cluster.local
```

### From Outside Cluster (using virtctl)

```bash
# Install virtctl
wget https://github.com/kubevirt/kubevirt/releases/download/v1.1.0/virtctl-v1.1.0-linux-amd64
chmod +x virtctl-v1.1.0-linux-amd64
sudo mv virtctl-v1.1.0-linux-amd64 /usr/local/bin/virtctl

# Access VM console
virtctl console <vm-name> -n <namespace>

# SSH to VM (creates SSH tunnel)
virtctl ssh cloud-user@<vm-name> -n <namespace>
```

### Using OpenShift Console

1. Navigate to **Virtualization** → **VirtualMachines**
2. Select your namespace
3. Click on VM name
4. Click **Console** tab to access the VM console

## Troubleshooting

### VM not starting

```bash
# Check VM status
oc get vm <vm-name> -n <namespace> -o yaml

# Check VMI events
oc describe vmi <vm-name> -n <namespace>

# Check DataVolume
oc get dv <vm-name>-disk -n <namespace>
```

### DataVolume stuck in Pending

```bash
# Check PVC
oc get pvc -n <namespace>

# Check storage class
oc get storageclass

# Check CDI pods
oc get pods -n openshift-cnv | grep cdi
```

### Boot source not found

```bash
# List available boot sources
oc get pvc -n openshift-virtualization-os-images

# If RHEL images don't exist, create them:
oc apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: rhel9
  namespace: openshift-virtualization-os-images
  labels:
    app: containerized-data-importer
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 30Gi
  storageClassName: ocs-external-storagecluster-ceph-rbd
  dataSource:
    kind: DataSource
    name: rhel9
    apiGroup: cdi.kubevirt.io
EOF
```

## Next Steps

1. Push this repository to Git (GitHub, GitLab, Gitea, etc.)
2. Create AAP Project pointing to the Git repo
3. Set up credentials in AAP
4. Create job templates with surveys
5. Generate AAP API token
6. Integrate with Developer Hub

