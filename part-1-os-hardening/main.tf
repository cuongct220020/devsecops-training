terraform {
  required_version = ">= 1.5.0"

  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = ">= 0.7.0, < 0.9.0" # 0.9.x is a schema rewrite; pin to classic API
    }
  }
}

provider "libvirt" {
  uri = var.libvirt_uri
}

# --- Base cloud image -------------------------------------------------------
# Pull the official Ubuntu 24.04 (Noble) cloud image once as the immutable
# backing volume. Each node disk is a copy-on-write clone of this base.
resource "libvirt_volume" "base" {
  name   = "${var.name_prefix}-base.qcow2"
  pool   = var.pool_name
  source = var.base_image_url
  format = "qcow2"
}

resource "libvirt_volume" "root" {
  for_each = var.nodes

  name           = "${var.name_prefix}-${each.key}-root.qcow2"
  pool           = var.pool_name
  base_volume_id = libvirt_volume.base.id
  size           = var.disk_size
  format         = "qcow2"
}

# --- cloud-init -------------------------------------------------------------
# Deliberately vanilla: we only inject an SSH key so we can log in; everything
# else stays at distro defaults so OpenSCAP has plenty to flag (Lab 1.3).
resource "libvirt_cloudinit_disk" "init" {
  for_each = var.nodes

  name = "${var.name_prefix}-${each.key}-cloudinit.iso"
  pool = var.pool_name

  user_data = templatefile("${path.module}/cloud-init/user-data.yaml", {
    hostname       = each.key
    ssh_username   = var.ssh_username
    ssh_public_key = trimspace(file(pathexpand(var.ssh_public_key)))
  })

  network_config = file("${path.module}/cloud-init/network-config.yaml")
}

# --- Domains (the VMs) ------------------------------------------------------
resource "libvirt_domain" "vm" {
  for_each = var.nodes

  name      = "${var.name_prefix}-${each.key}"
  memory    = each.value.memory_mib
  vcpu      = each.value.vcpu
  cloudinit = libvirt_cloudinit_disk.init[each.key].id

  cpu {
    mode = "host-passthrough"
  }

  network_interface {
    network_name   = var.network_name
    wait_for_lease = true
  }

  disk {
    volume_id = libvirt_volume.root[each.key].id
  }

  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  graphics {
    type        = "spice"
    listen_type = "address"
    autoport    = true
  }
}
