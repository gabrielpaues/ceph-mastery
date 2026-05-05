# ============================================================
# Ceph Lab on Safespring - Main Configuration
# ============================================================
#
# Architecture:
#   - 1x admin node   (cephadm bootstrap + client tools)
#   - 1x mon node     (MON + MGR + MDS)
#   - 3x osd nodes    (each with an extra data volume for the OSD)
#
# All nodes share an interconnect security group so they can
# talk freely to each other. The admin node also gets SSH from
# the outside world.
# ============================================================

terraform {
  required_version = ">= 1.0.0"
  required_providers {
    openstack = {
      source = "terraform-provider-openstack/openstack"
    }
  }
}

# ----------------------------------------------------------
# Security groups
# ----------------------------------------------------------

# Allow full traffic between cluster members
module "ceph_interconnect" {
  source             = "github.com/safespring-community/terraform-modules/v2-compute-security-group"
  name               = "${var.cluster_name}-interconnect"
  delete_default_rules = true
  description        = "Full connectivity between Ceph lab nodes"
  rules = {
    ingress = {
      direction       = "ingress"
      remote_group_id = "self"
    }
    egress = {
      direction       = "egress"
      remote_group_id = "self"
    }
  }
}

# Allow SSH + outbound internet (for package installs)
module "ceph_ssh" {
  source             = "github.com/safespring-community/terraform-modules/v2-compute-security-group"
  name               = "${var.cluster_name}-ssh"
  delete_default_rules = true
  description        = "SSH access and internet egress for Ceph lab"
  rules = {
    ssh = {
      direction   = "ingress"
      ip_protocol = "tcp"
      from_port   = "22"
      to_port     = "22"
      ethertype   = "IPv4"
      cidr        = "0.0.0.0/0"
    }
    ssh6 = {
      direction   = "ingress"
      ip_protocol = "tcp"
      from_port   = "22"
      to_port     = "22"
      ethertype   = "IPv6"
      cidr        = "::/0"
    }
    egress4 = {
      direction   = "egress"
      ethertype   = "IPv4"
      cidr        = "0.0.0.0/0"
    }
    egress6 = {
      direction   = "egress"
      ethertype   = "IPv6"
      cidr        = "::/0"
    }
  }
}

# Allow Ceph Dashboard (port 8443) from outside for monitoring
module "ceph_dashboard" {
  source             = "github.com/safespring-community/terraform-modules/v2-compute-security-group"
  name               = "${var.cluster_name}-dashboard"
  delete_default_rules = true
  description        = "Ceph Dashboard access"
  rules = {
    dashboard = {
      direction   = "ingress"
      ip_protocol = "tcp"
      from_port   = "8443"
      to_port     = "8443"
      ethertype   = "IPv4"
      cidr        = "0.0.0.0/0"
    }
  }
}

# ----------------------------------------------------------
# Admin / client node
# ----------------------------------------------------------

module "admin" {
  source          = "github.com/safespring-community/terraform-modules/v2-compute-instance"
  name            = "${var.cluster_name}-admin"
  key_pair_name   = var.key_pair_name
  network         = var.network
  image           = var.image
  flavor          = var.admin_flavor
  role            = "ceph_admin"
  security_groups = [
    module.ceph_interconnect.name,
    module.ceph_ssh.name,
    module.ceph_dashboard.name,
  ]
}

# ----------------------------------------------------------
# MON / MGR / MDS node
# ----------------------------------------------------------

module "mon" {
  source          = "github.com/safespring-community/terraform-modules/v2-compute-instance"
  name            = "${var.cluster_name}-mon"
  key_pair_name   = var.key_pair_name
  network         = var.network
  image           = var.image
  flavor          = var.mon_flavor
  role            = "ceph_mon"
  security_groups = [
    module.ceph_interconnect.name,
    module.ceph_ssh.name,
  ]
}

# ----------------------------------------------------------
# OSD nodes (with extra data volumes)
# ----------------------------------------------------------

module "osd" {
  count           = var.osd_count
  source          = "github.com/safespring-community/terraform-modules/v2-compute-instance"
  name            = "${var.cluster_name}-osd-${count.index + 1}"
  key_pair_name   = var.key_pair_name
  network         = var.network
  image           = var.image
  flavor          = var.osd_flavor
  role            = "ceph_osd"
  security_groups = [
    module.ceph_interconnect.name,
    module.ceph_ssh.name,
  ]
  data_disks = {
    "osd-data" = {
      size = var.osd_disk_size
      type = var.osd_disk_type
    }
  }
}
