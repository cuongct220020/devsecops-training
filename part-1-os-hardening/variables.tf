variable "libvirt_uri" {
  description = "Libvirt connection URI for the local KVM host."
  type        = string
  default     = "qemu:///system"
}

variable "vm_name" {
  description = "Name of the VM domain created in libvirt."
  type        = string
  default     = "ubuntu2404-hardening-lab"
}

variable "vcpu" {
  description = "Number of virtual CPUs for the VM."
  type        = number
  default     = 2
}

variable "memory" {
  description = "Memory for the VM in MiB."
  type        = number
  default     = 2048
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
  description = "Libvirt network the VM attaches to."
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
  description = "Path to the SSH public key injected into the VM for passwordless login."
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}
