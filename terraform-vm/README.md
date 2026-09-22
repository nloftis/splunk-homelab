# Splunk Enterprise — Terraform / KVM Deployment

This directory contains the Terraform configuration for provisioning the
virtual-machine deployment of the Splunk homelab.

Terraform uses libvirt/KVM to create an Ubuntu 24.04 LTS virtual machine.
Initial operating-system configuration is performed automatically with
cloud-init.

The objective is a reproducible deployment that can be created, destroyed,
and recreated from source rather than relying on a manually installed VM.

## Architecture

```text
Terraform
    |
    | qemu:///system
    v
libvirt / KVM
    |
    +-- Ubuntu 24.04 LTS cloud image
    |
    +-- qcow2 COW VM disk
    |
    +-- cloud-init configuration
    |     +-- administrative user
    |     +-- SSH public key
    |     +-- console password
    |     +-- network configuration
    |     +-- qemu-guest-agent
    |     +-- provisioning script
    |           +-- scripts/install-splunk.sh
    |
    +-- Splunk VM
          +-- 4 vCPU
          +-- 8 GB RAM
          +-- 100 GiB disk
          +-- host-passthrough CPU
          +-- macvtap networking
```

### VM Resources

| Resource | Configuration |
|---|---|
| Operating system | Ubuntu 24.04 LTS |
| vCPU | 4 |
| Memory | 8 GB |
| Disk | 100 GiB |
| Disk format | qcow2 COW |
| CPU mode | `host-passthrough` |
| Hypervisor | KVM / libvirt |
| Network | macvtap |
| Addressing | DHCP |
| Guest configuration | cloud-init |

### CPU

The VM uses the libvirt `host-passthrough` CPU mode rather than a generic
emulated CPU model.

This exposes the relevant capabilities of the physical processor to the
guest while retaining KVM virtualization. In particular, the guest has
access to AVX and AVX2 CPU instructions required by modern Splunk
components and lifecycle checks.

This also avoids the CPU instruction-set limitation encountered with the
Synology hardware used by the Docker deployment.

### Storage

The deployment uses the Ubuntu 24.04 LTS cloud image as a base image.

The VM itself uses a separate 100 GiB qcow2 copy-on-write disk backed by
that image. This avoids modifying the original cloud image and allows the
base image to be reused.

Because the VM disk depends on the backing image, the base image must
remain available while the dependent VM disk exists.

### cloud-init

Ubuntu cloud images include cloud-init for automated initial system
configuration.

Terraform renders the templates under `cloud-init/` and uses the libvirt
provider to create a cloud-init configuration disk attached to the VM.

The configuration provides:

- VM hostname and instance metadata
- administrative user creation
- SSH public-key configuration
- local console password configuration
- DHCP network configuration
- required base packages
- qemu guest agent configuration
- execution of the external provisioning script

The provisioning script is maintained separately under `scripts/` and is
injected into the guest by Terraform through the cloud-init template. This
keeps application provisioning logic separate from the cloud-init YAML while
avoiding any dependency on SSH connectivity from the KVM host.

This eliminates the need for a manual Ubuntu installation or initial guest
configuration.

### Networking

The VM uses a macvtap interface attached directly to the KVM host's physical
network interface.

The guest therefore participates in the existing network and obtains its
address from the existing DHCP infrastructure rather than using a separate
libvirt NAT network.

A generated locally administered MAC address is assigned to the VM.
Terraform uses the qemu guest agent to discover the resulting DHCP address.

#### macvtap host isolation

An important characteristic of this design is that the physical KVM host
cannot communicate directly with its own macvtap guest through the parent
interface.

The guest can communicate normally with other permitted systems on the
network, but direct host-to-guest communication through that interface is
not available.

This is inherent to the macvtap architecture rather than a guest networking
failure.

A Linux bridge, host-side macvlan interface, or separate management network
could be introduced if direct hypervisor-to-guest communication becomes
necessary.

## Requirements

The deployment requires:

- Terraform
- libvirt
- KVM
- access to the system libvirt instance
- a physical network interface suitable for macvtap
- DHCP service on the attached network
- an SSH public key for the guest administrative account

### Terraform Version

Terraform is managed locally with `tenv`.

The repository includes:

```text
.terraform-version
```

which currently specifies Terraform `1.12.2`.

The Terraform configuration requires Terraform 1.12.2 or later.

### Providers

The deployment uses:

- `dmacvicar/libvirt`
- `hashicorp/random`

The libvirt provider is deliberately constrained to the `0.8.x` release
line rather than automatically adopting the later provider rewrite.

Provider selections are recorded in:

```text
.terraform.lock.hcl
```

The lock file is committed to Git so that provider selection remains
reproducible.

Terraform connects to the system libvirt instance using:

```text
qemu:///system
```

## Repository Structure

```text
terraform-vm/
├── .gitignore
├── .terraform-version
├── .terraform.lock.hcl
├── README.md
├── main.tf
├── outputs.tf
├── providers.tf
├── terraform.tfvars.example
├── variables.tf
├── cloud-init/
│   ├── meta-data.yaml.tftpl
│   ├── network-config.yaml.tftpl
│   └── user-data.yaml.tftpl
└── scripts/
    └── install-splunk.sh
```

`providers.tf` defines the Terraform and provider requirements and configures
the libvirt connection.

`variables.tf` defines configurable deployment values.

`main.tf` defines the libvirt storage, cloud-init disk, virtual machine,
networking, and supporting resources.

`outputs.tf` exposes useful deployment information such as the VM name,
IP address, MAC address, and SSH connection hint.

`terraform.tfvars.example` provides an example local configuration without
containing environment-specific values.

The files under `cloud-init/` define the initial Ubuntu guest configuration.

`scripts/install-splunk.sh` contains the Splunk Enterprise provisioning logic
that cloud-init writes into the guest and executes during first boot. The
script installs Splunk Enterprise 10.4.3, performs the first start as the
package-created `splunk` service account, generates the initial `admin`
password, stops Splunk, enables the systemd-managed `Splunkd.service`, and
starts Splunk again through systemd. This path has been validated on a clean
deployment without SSH access from the KVM host.

## Configuration

Create a local Terraform variables file from the supplied example:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` and supply the required environment-specific values.

The SSH public key should contain the complete contents of the desired
public-key file. For example:

```bash
cat ~/.ssh/id_ed25519.pub
```

### Console Password Configuration

The console password is supplied as a SHA-512 password hash through the
sensitive Terraform variable `admin_password_hash`. This password exists for
local console authentication; it does not enable password authentication over
SSH.

Generate a suitable SHA-512 password hash locally:

```bash
openssl passwd -6
```

Enter the desired console password when prompted. Store the resulting `$6$...`
hash in the local `terraform.tfvars` file:

```hcl
admin_password_hash = "$6$..."
```

Do not store the plaintext password in Terraform source files.

The password hash follows this configuration path:

```text
terraform.tfvars
    |
    | admin_password_hash
    v
variables.tf
    |
    | sensitive Terraform variable
    v
main.tf
    |
    | templatefile(...)
    v
cloud-init/user-data.yaml.tftpl
    |
    | passwd: '${admin_password_hash}'
    | lock_passwd: false
    v
Ubuntu splunkadmin account
```

`variables.tf` declares the value as a sensitive Terraform variable:

```hcl
variable "admin_password_hash" {
  description = "SHA-512 password hash for console login"
  type        = string
  sensitive   = true
}
```

`main.tf` passes the Terraform variable into the cloud-init user-data template:

```hcl
user_data = templatefile("${path.module}/cloud-init/user-data.yaml.tftpl", {
  hostname              = var.vm_hostname
  timezone              = var.timezone
  admin_username        = var.admin_username
  ssh_public_key        = var.ssh_public_key
  admin_password_hash   = var.admin_password_hash
  splunk_install_script = file("${path.module}/scripts/install-splunk.sh")
})
```

The cloud-init template applies the hash to the administrative account:

```yaml
users:
  - name: ${admin_username}
    groups: [sudo]
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: false
    passwd: '${admin_password_hash}'
    ssh_authorized_keys:
      - ${ssh_public_key}

ssh_pwauth: false
disable_root: true
```

`lock_passwd: false` allows the configured password to be used for local
console authentication. `ssh_pwauth: false` separately keeps SSH password
authentication disabled, so SSH continues to require the configured public
key.

### Provisioning Script Flow

Application provisioning follows a similar source-controlled path and does
not require Terraform to establish an SSH connection to the guest:

```text
scripts/install-splunk.sh
        |
        | file(...)
        v
main.tf
        |
        | templatefile(...)
        v
cloud-init/user-data.yaml.tftpl
        |
        | write_files
        v
/usr/local/sbin/install-splunk.sh
        |
        | runcmd
        v
executed as root during first boot
```

`main.tf` reads `scripts/install-splunk.sh` with `file()` and supplies its
contents to the cloud-init template as `splunk_install_script`. The template
writes the script into the guest at `/usr/local/sbin/install-splunk.sh` with
root ownership and executable permissions. The cloud-init `runcmd` section
then executes the script during initial provisioning.

This design is particularly important with the current macvtap network
architecture: provisioning occurs entirely inside the guest during first boot
and therefore does not depend on direct SSH connectivity from the KVM host.

### Splunk Enterprise Provisioning

The provisioning script installs Splunk Enterprise 10.4.3 from the official
Linux AMD64 Debian package and uses `/opt/splunk` as `SPLUNK_HOME`. The package
creates the dedicated `splunk` account and owns the Splunk installation as
`splunk:splunk`.

The validated first-boot sequence is:

```text
install Splunk package as root
        |
        v
first Splunk start as splunk
        |
        +-- accept license noninteractively
        +-- generate and print initial admin password
        |
        v
stop Splunk as splunk
        |
        v
enable systemd boot-start as root
        |
        v
start Splunkd.service through systemd
```

The stop between first start and `enable boot-start` is required: Splunk
refuses to enable or disable boot-start while `splunkd` is running. Performing
the first start as the `splunk` account also avoids running Splunk Enterprise
as root.

The initial Splunk Web account is:

```text
username: admin
password: randomly generated during first boot
```

The generated password is printed by Splunk during provisioning and is
therefore captured in `/var/log/cloud-init-output.log`. If the original console
output is no longer visible, retrieve it inside the guest with:

```bash
sudo grep -A1 "Randomly generated admin password" /var/log/cloud-init-output.log
```

Store the recovered password in an appropriate password manager. Be aware that
the generated credential remains present in the cloud-init output log unless
that log is subsequently handled separately.

### Splunk Web Access

Splunk Web listens on TCP port 8000. The validated deployment listens on all
IPv4 interfaces and can be checked inside the guest with:

```bash
sudo ss -lntp | grep ':8000'
```

With macvtap networking, the Pop!_OS KVM host cannot open Splunk Web directly
through the guest's macvtap address. This is the same host-to-guest isolation
described in the networking section above; it is not a Splunk Web failure.

Access Splunk Web from another permitted network system or VM instead:

```text
http://<vm-ip>:8000
```

Access from another VM on the KVM host has been validated successfully.

`terraform.tfvars` is intentionally excluded from Git.

Other local Terraform data such as state files and the `.terraform/`
provider directory are also excluded.

The following reproducibility files are intentionally committed:

```text
.terraform-version
.terraform.lock.hcl
terraform.tfvars.example
```

## Deployment

Run Terraform from the `terraform-vm` directory:

```bash
cd terraform-vm
```

Initialize Terraform and install the required providers:

```bash
terraform init
```

Format and validate the configuration:

```bash
terraform fmt -recursive
terraform validate
```

Review the proposed infrastructure:

```bash
terraform plan
```

Create the infrastructure:

```bash
terraform apply
```

Terraform provisions the Ubuntu base image, VM disk, cloud-init
configuration, generated MAC address, and libvirt domain.

### Verify First-Boot Provisioning

Terraform can finish creating the virtual machine before cloud-init has
finished provisioning the guest. Connect to the VM console:

```bash
virsh console splunk
```

Then check cloud-init status:

```bash
cloud-init status --long
```

A successful deployment should report:

```text
status: done
extended_status: done
errors: []
recoverable_errors: {}
```

If provisioning is still running, or if cloud-init reports an error, monitor
the provisioning output with:

```bash
sudo tail -f /var/log/cloud-init-output.log
```

Splunk generates the initial `admin` password during its first startup. The
password is captured in the same cloud-init output log. Retrieve it with:

```bash
sudo grep -A1 "Randomly generated admin password" /var/log/cloud-init-output.log
```

The Splunk Web credentials are therefore:

```text
username: admin
password: <randomly generated password from cloud-init-output.log>
```

Save the generated password in an appropriate password manager. Because the
password remains in `/var/log/cloud-init-output.log`, treat that log as
sensitive.

## Outputs

After provisioning, Terraform provides:

```text
ip_address
mac_address
ssh_connection_hint
vm_name
```

For example:

```text
ip_address          = "192.168.10.x"
mac_address         = "52:54:00:xx:xx:xx"
ssh_connection_hint = "ssh splunkadmin@192.168.10.x"
vm_name             = "splunk"
```

The actual DHCP address and generated MAC address may vary between
deployments.

## Access

The guest administrative account is:

```text
splunkadmin
```

The account supports two deliberately separate authentication paths:

| Access path | Authentication | Status |
|---|---|---|
| libvirt serial console | Password | Enabled |
| SSH | Public key | Enabled |
| SSH | Password | Disabled |
| Root SSH | — | Disabled |

The SSH public key and the hashed local console password are supplied through
`terraform.tfvars`. Password-based SSH authentication remains disabled with
`ssh_pwauth: false`; enabling a password for local console authentication does
not enable password authentication over SSH.

Because the VM uses macvtap networking, the SSH connection hint assumes
the connection originates from a network host that can communicate with
the guest. Direct SSH access from the KVM host through the macvtap parent
interface is not available.

For administrative or recovery access from the KVM host, connect to the
libvirt serial console:

```bash
virsh console splunk
```

Press Enter if necessary to display the login prompt, then log in as
`splunkadmin` using the plaintext password corresponding to the configured
`admin_password_hash`.

To disconnect from `virsh console`, use the virsh escape sequence:

```text
Ctrl + ]
```

## Destroying and Recreating the VM

Terraform-managed infrastructure can be removed with:

```bash
terraform destroy
```

Review the proposed destruction before confirming it.

The VM is intended to be reproducible infrastructure rather than a
manually maintained machine. Configuration that is required for the
deployment should therefore be represented in Terraform, cloud-init, or
other source-controlled provisioning configuration rather than applied
manually to an individual VM.

A new deployment can then be created again with:

```bash
terraform apply
```

## Current Status

The Terraform configuration now provisions the complete Ubuntu/Splunk virtual
machine baseline, including:

- Ubuntu 24.04 LTS VM storage and macvtap networking
- cloud-init guest configuration
- SSH public-key configuration
- password-authenticated local console access
- qemu guest agent
- automated Splunk Enterprise 10.4.3 package installation
- noninteractive first-run initialization
- randomly generated initial Splunk `admin` password
- dedicated `splunk` service account execution
- systemd-managed `Splunkd.service`
- automatic Splunk startup after reboot

The complete path has been validated on a clean deployment.
`cloud-init status --long` completed with `status: done`, `extended_status: done`,
and no reported errors. `Splunkd.service` was confirmed `enabled` and `active`,
and the main `splunkd` process was confirmed to run as the `splunk` account.

A VM reboot was also tested. `Splunkd.service` started automatically after the
reboot and remained enabled and active. Splunk Web was confirmed listening on
`0.0.0.0:8000`, and a successful `admin` login was validated from another VM.
Direct browser access from the Pop!_OS KVM host remains unavailable because of
the intentional macvtap host-to-guest isolation described above.
