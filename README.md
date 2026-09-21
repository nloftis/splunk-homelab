# Splunk Homelab

A homelab project for deploying, operating, and evaluating Splunk Enterprise
using real network and security telemetry.

The project provides two deployment approaches:

- **Docker Compose** — a containerized Splunk deployment on a Synology NAS.
- **Terraform / KVM** — a reproducible virtual-machine deployment using
  Terraform, libvirt/KVM, Ubuntu, and cloud-init.

The environments provide hands-on experience with Splunk administration,
log ingestion, search, security monitoring, infrastructure-as-code, and
deployment lifecycle management.

## Repository Structure

```text
splunk-homelab/
├── README.md
├── docker-compose/
│   ├── README.md
│   └── ...
├── docs/
│   └── ...
└── terraform-vm/
    ├── README.md
    ├── cloud-init/
    └── ...
```

### Docker Compose

The original implementation deploys Splunk Enterprise using Docker Compose
on a Synology NAS.

Deployment instructions, architecture, configuration, platform constraints,
and Docker-specific troubleshooting are documented in:

[Docker Compose deployment](docker-compose/README.md)

### Terraform / KVM

The VM implementation uses Terraform and libvirt/KVM to provision an Ubuntu
virtual machine, with initial system configuration performed through
cloud-init.

The goal of this deployment path is to provide a reproducible infrastructure
environment that can be created, validated, destroyed, and recreated from
source.

Deployment instructions, architecture, Terraform configuration, validation,
and VM-specific considerations are documented in:

[Terraform / KVM deployment](terraform-vm/README.md)

## Project Goals

- Gain hands-on experience deploying and administering Splunk Enterprise.
- Ingest and analyze real network and security telemetry.
- Practice infrastructure-as-code and reproducible deployment techniques.
- Explore deployment lifecycle, persistence, and operational behavior.
- Compare Splunk with other security and observability platforms used in the
  homelab.

## Related Projects

This project complements other security and observability environments in
the homelab:

- [wazuh-homelab](https://github.com/nloftis/wazuh-homelab)
- [opnsense-observability-stack](https://github.com/nloftis/opnsense-observability-stack)

Together, these projects provide practical experience with different
approaches to security monitoring, telemetry collection, indexing, search,
observability, and infrastructure automation.

## Status

Both deployment paths are retained in this repository for experimentation
and comparison.

The Docker Compose environment contains the original Splunk deployment and
associated operational testing.

The Terraform/KVM environment currently provides the reproducible base VM
infrastructure. Splunk provisioning on the VM is the next implementation
phase.
