variable "vm_name" {
  description = "libvirt domain name for the Splunk VM"
  type        = string
  default     = "splunk"
}

variable "vm_hostname" {
  description = "Hostname set inside the guest via cloud-init"
  type        = string
  default     = "splunk"
}

variable "vcpu" {
  description = "Number of vCPUs allocated to the Splunk VM"
  type        = number
  default     = 4
}

variable "memory_mb" {
  description = "RAM in MiB allocated to the Splunk VM (8192 = 8 GiB)"
  type        = number
  default     = 8192
}

variable "disk_size_bytes" {
  description = "Root disk size in bytes (100 GiB)"
  type        = number
  default     = 107374182400
}

variable "libvirt_pool_name" {
  description = "Existing libvirt storage pool used for the VM disks"
  type        = string
  default     = "default"
}

variable "ubuntu_cloud_image_url" {
  description = "URL of the Ubuntu 24.04 LTS (Noble) amd64 cloud image"
  type        = string
  default     = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
}

variable "network_interface" {
  description = "Physical Pop!_OS interface used for the macvtap connection to the PC segment"
  type        = string
  default     = "enp4s0"
}

variable "ssh_public_key" {
  description = "SSH public key injected via cloud-init for the admin user"
  type        = string
  # No default: supply this through terraform.tfvars (gitignored) or -var.
}

variable "admin_username" {
  description = "Administrative username created inside the guest via cloud-init"
  type        = string
  default     = "splunkadmin"
}

variable "timezone" {
  description = "Guest timezone"
  type        = string
  default     = "Pacific/Honolulu"
}

variable "admin_password_hash" {
  description = "SHA-512 password hash for console login"
  type        = string
  sensitive   = true
}
