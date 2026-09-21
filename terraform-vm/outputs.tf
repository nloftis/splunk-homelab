output "vm_name" {
  description = "libvirt domain name"
  value       = libvirt_domain.splunk.name
}

output "mac_address" {
  description = "MAC address assigned to the Splunk VM"
  value       = local.mac_address
}

output "ip_address" {
  description = "DHCP address resolved through qemu-guest-agent"
  value       = try(libvirt_domain.splunk.network_interface[0].addresses[0], "not yet available")
}

output "ssh_connection_hint" {
  description = "Ready-to-use SSH command using the resolved guest address"
  value       = "ssh ${var.admin_username}@${try(libvirt_domain.splunk.network_interface[0].addresses[0], "<ip-from-opnsense-dhcp-leases>")}"
}
