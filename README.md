# Splunk Homelab

A homelab project for deploying, operating, and evaluating Splunk
Enterprise using real network and security telemetry.

The project provides two deployment approaches:

- **Docker Compose** — a containerized Splunk deployment on a
  Synology NAS.
- **Terraform / KVM** — a reproducible virtual-machine deployment
  using Terraform, libvirt/KVM, Ubuntu, and cloud-init.

The environments provide hands-on experience with Splunk administration,
log ingestion, search, security monitoring, infrastructure-as-code, and
deployment lifecycle management.

## Rationale

Wazuh and Grafana/Loki already provide detection and observability
across the home network. This project asks a different question: what
does the same event data look like through Splunk's ingestion, indexing,
and search model, and how does that compare in practice — not just on
paper — with the open-source security and observability stacks already
running in the homelab?

The project retains two Splunk deployment methods so the same functional
environment can be explored through both containerized and
infrastructure-as-code approaches.

On the Synology NAS, Splunk and Wazuh's indexer are not intended to run
concurrently. Toggling between them keeps each indexing workload's
resource footprint isolated on a host with a fixed 6 GB memory ceiling.
The Terraform/KVM deployment is independent of that NAS resource
constraint.

## Repository Structure

```text
splunk-homelab/
├── README.md
├── docker-compose/
│   ├── README.md
│   └── ...
├── docs/
│   └── post-deployment.md
└── terraform-vm/
    ├── README.md
    ├── cloud-init/
    └── ...
```

### Docker Compose

The Docker implementation deploys Splunk Enterprise 9.3.13 using Docker
Compose on a Synology DS224+.

Deployment instructions, Docker architecture, persistence, resource
constraints, validation, and platform-specific troubleshooting are
documented in:

[Docker Compose deployment](docker-compose/README.md)

### Terraform / KVM

The VM implementation deploys Splunk Enterprise 10.4.3 on an Ubuntu
24.04 virtual machine provisioned with Terraform and libvirt/KVM, with
initial system configuration performed through cloud-init.

This deployment path provides a reproducible infrastructure environment
that can be created, validated, destroyed, and recreated from source.

Deployment instructions, architecture, Terraform configuration,
validation, and VM-specific considerations are documented in:

[Terraform / KVM deployment](terraform-vm/README.md)

### Post-deployment configuration

Both deployment paths are intended to converge on the same functional
Splunk configuration. Common configuration for indexes, inputs,
ingestion, and validation belongs in:

[Post-deployment configuration](docs/post-deployment.md)

Where Splunk 9.3.13 and 10.4.3 or the underlying deployment methods
require different procedures, the post-deployment guide should identify
those differences explicitly while preserving the same intended
functional end state.

## Project Goals

- Gain hands-on experience deploying and administering Splunk
  Enterprise.
- Ingest and analyze real network and security telemetry.
- Practice infrastructure-as-code and reproducible deployment
  techniques.
- Explore deployment lifecycle, persistence, and operational behavior.
- Compare Splunk with other security and observability platforms used
  in the homelab.
- Maintain equivalent post-deployment functionality across the Docker
  and Terraform/KVM implementations where practical.

## Related Projects

This project complements other security and observability environments
in the homelab:

- [wazuh-homelab](https://github.com/nloftis/wazuh-homelab)
- [opnsense-observability-stack](https://github.com/nloftis/opnsense-observability-stack)

Together, these projects provide practical experience with different
approaches to security monitoring, telemetry collection, indexing,
search, observability, and infrastructure automation.

## Status

Both deployment paths are operational and retained for experimentation
and comparison.

- **Docker Compose:** Splunk Enterprise 9.3.13 is running on the
  Synology DS224+. Fresh provisioning, container restart, and full
  container removal/recreation with persistent Docker-managed volumes
  have been validated.
- **Terraform / KVM:** Splunk Enterprise 10.4.3 is running on the
  Ubuntu 24.04 VM provisioned through Terraform/KVM.

The next project phase is shared post-deployment configuration so both
environments ingest and analyze the intended homelab telemetry
consistently.
