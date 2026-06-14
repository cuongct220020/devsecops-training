terraform {
  required_version = ">= 1.5.0"

  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.7"
    }
  }
}

provider "libvirt" {
  uri = var.libvirt_uri
}

# --- Base cloud image -------------------------------------------------------
# Pull the official Ubuntu 24.04 (Noble) cloud image as the immutable backing
# volume. The VM disk is a copy-on-write clone of this base.
resource "libvirt_volume" "base" {
  name   = "${var.vm_name}-base.qcow2"
  pool   = var.pool_name
  source = var.base_image_url
  format = "qcow2"
}

resource "libvirt_volume" "root" {
  name           = "${var.vm_name}-root.qcow2"
  pool           = var.pool_name
  base_volume_id = libvirt_volume.base.id
  size           = var.disk_size
  format         = "qcow2"
}

# --- cloud-init -------------------------------------------------------------
# A deliberately *vanilla* configuration. We only inject an SSH key so we can
# log in; everything else stays at distro defaults so OpenSCAP has plenty to
# flag on the baseline scan (Lab 1.3, Step 2).
data "template_file" "user_data" {
  template = file("${path.module}/cloud-init/user-data.yaml")

  vars = {
    ssh_username   = var.ssh_username
    ssh_public_key = trimspace(file(pathexpand(var.ssh_public_key)))
  }
}

data "template_file" "network_config" {
  template = file("${path.module}/cloud-init/network-config.yaml")
}

resource "libvirt_cloudinit_disk" "init" {
  name           = "${var.vm_name}-cloudinit.iso"
  pool           = var.pool_name
  user_data      = data.template_file.user_data.rendered
  network_config = data.template_file.network_config.rendered
}

# --- Domain (the VM) --------------------------------------------------------
resource "libvirt_domain" "vm" {
  name      = var.vm_name
  memory    = var.memory
  vcpu      = var.vcpu
  cloudinit = libvirt_cloudinit_disk.init.id

  cpu {
    mode = "host-passthrough"
  }

  network_interface {
    network_name   = var.network_name
    wait_for_lease = true
  }

  disk {
    volume_id = libvirt_volume.root.id
  }

  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  console {
    type        = "pty"
    target_type = "virtio"
    target_port = "1"
  }

  graphics {
    type        = "spice"
    listen_type = "address"
    autoport    = true
  }
}
