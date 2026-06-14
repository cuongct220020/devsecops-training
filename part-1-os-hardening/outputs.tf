output "vm_name" {
  description = "Name of the provisioned libvirt domain."
  value       = libvirt_domain.vm.name
}

output "vm_ip_address" {
  description = "DHCP-leased IPv4 address of the VM. SSH here to begin the audit."
  value       = libvirt_domain.vm.network_interface[0].addresses[0]
}

output "ssh_command" {
  description = "Ready-to-run SSH command for the provisioned VM."
  value       = "ssh ${var.ssh_username}@${libvirt_domain.vm.network_interface[0].addresses[0]}"
}
