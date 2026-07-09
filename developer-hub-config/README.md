# Developer Hub Configuration

This repository contains configuration files for Red Hat Developer Hub deployment on OpenShift.

## Current Content

### Ansible Playbooks (ansible/playbooks/)

VM provisioning playbooks for OpenShift Virtualization:
- `create-rhel-vm.yml` - Provision RHEL VMs on OpenShift Virtualization
- `delete-rhel-vm.yml` - Delete VMs and cleanup resources
- `list-vms.yml` - List all VMs in a namespace

See `ansible/playbooks/README.md` for detailed documentation.

## Coming Soon

- Developer Hub operator installation files
- Developer Hub configuration and setup
- Complete integration guides

## Usage

For now, you can use the Ansible playbooks to provision VMs on OpenShift Virtualization.
See the playbooks README for requirements and usage instructions.
