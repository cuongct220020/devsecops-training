variable "libvirt_uri" {
  description = "Libvirt connection URI for the local KVM host."
  type        = string
  default     = "qemu:///system"
}

# Cluster nodes provisioned for the whole series. node1 doubles as the Lab 1
# OpenSCAP hardening target and the Lab 2 RKE2 master; node2 is the worker.
variable "nodes" {
  description = "Map of node name => {vcpu, memory_mib} to provision."
  type = map(object({
    vcpu       = number
    memory_mib = number
  }))
  default = {
    "node1-master" = { vcpu = 2, memory_mib = 4096 }
    "node2-worker" = { vcpu = 2, memory_mib = 3072 }
  }
}

variable "name_prefix" {
  description = "Prefix for libvirt domain and volume names."
  type        = string
  default     = "devsecops"
}

variable "disk_size" {
  description = "Root disk size in bytes (default 20 GiB)."
  type        = number
  default     = 21474836480
}

variable "pool_name" {
  description = "Libvirt storage pool to hold the VM volumes."
  type        = string
  default     = "default"
}

variable "network_name" {
  description = "Libvirt network the VMs attach to."
  type        = string
  default     = "default"
}

variable "base_image_url" {
  description = "Ubuntu 24.04 (Noble) cloud image URL."
  type        = string
  default     = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
}

variable "ssh_username" {
  description = "Default login user provisioned via cloud-init."
  type        = string
  default     = "labadmin"
}

variable "ssh_public_key" {
  description = "Path to the SSH public key injected into the VMs for passwordless login."
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}
