resource "random_id" "mac_suffix" {
  byte_length = 3
}

locals {
  mac_address = "52:54:00:${substr(random_id.mac_suffix.hex, 0, 2)}:${substr(random_id.mac_suffix.hex, 2, 2)}:${substr(random_id.mac_suffix.hex, 4, 2)}"
}

# Base Ubuntu 24.04 cloud image, downloaded once and reused as a backing
# volume for the VM disk (copy-on-write).
resource "libvirt_volume" "ubuntu_base" {
  name   = "ubuntu-24.04-base.qcow2"
  pool   = var.libvirt_pool_name
  source = var.ubuntu_cloud_image_url
  format = "qcow2"
}

# Splunk VM root disk, backed by the Ubuntu base image.
resource "libvirt_volume" "splunk_disk" {
  name           = "${var.vm_name}.qcow2"
  pool           = var.libvirt_pool_name
  base_volume_id = libvirt_volume.ubuntu_base.id
  size           = var.disk_size_bytes
  format         = "qcow2"
}

# cloud-init seed disk: creates the admin user, injects the SSH key,
# configures DHCP networking, and enables qemu-guest-agent.
resource "libvirt_cloudinit_disk" "commoninit" {
  name = "${var.vm_name}-cloudinit.iso"
  pool = var.libvirt_pool_name

  user_data = templatefile("${path.module}/cloud-init/user-data.yaml.tftpl", {
    hostname              = var.vm_hostname
    timezone              = var.timezone
    admin_username        = var.admin_username
    ssh_public_key        = var.ssh_public_key
    admin_password_hash   = var.admin_password_hash
    splunk_install_script = file("${path.module}/scripts/install-splunk.sh")
  })

  meta_data = templatefile("${path.module}/cloud-init/meta-data.yaml.tftpl", {
    hostname = var.vm_hostname
  })

  network_config = templatefile("${path.module}/cloud-init/network-config.yaml.tftpl", {
    mac_address = local.mac_address
  })
}

resource "libvirt_domain" "splunk" {
  name   = var.vm_name
  memory = var.memory_mb
  vcpu   = var.vcpu

  cloudinit = libvirt_cloudinit_disk.commoninit.id

  # Expose the host CPU instruction set to the guest. This is important for
  # validating Splunk on the i5-13500 host rather than inheriting the NAS CPU
  # limitations encountered by the Docker deployment.
  cpu {
    mode = "host-passthrough"
  }

  disk {
    volume_id = libvirt_volume.splunk_disk.id
  }

  # macvtap in bridge mode against the Pop!_OS host's physical PC-segment
  # interface. The VM receives a normal DHCP lease from OPNsense.
  network_interface {
    macvtap        = var.network_interface
    mac            = local.mac_address
    wait_for_lease = true
  }

  console {
    type        = "pty"
    target_type = "serial"
    target_port = "0"
  }

  graphics {
    type        = "spice"
    listen_type = "address"
    autoport    = true
  }

  qemu_agent = true

  boot_device {
    dev = ["hd"]
  }
}
