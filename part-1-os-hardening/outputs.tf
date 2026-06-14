output "nodes" {
  description = "Map of node name => leased IPv4 address."
  value       = { for k, d in libvirt_domain.vm : k => d.network_interface[0].addresses[0] }
}

output "ssh_commands" {
  description = "Ready-to-run SSH commands for each node."
  value = {
    for k, d in libvirt_domain.vm :
    k => "ssh ${var.ssh_username}@${d.network_interface[0].addresses[0]}"
  }
}
