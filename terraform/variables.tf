# ============================================================
# Ceph Lab - Variables
# Adjust these to match your Safespring project
# ============================================================

variable "key_pair_name" {
  description = "Name of an existing OpenStack keypair"
  type        = string
}

variable "network" {
  description = "One of: default, private, public"
  type        = string
  default     = "default"
}

variable "image" {
  description = "OS image name (use openstack image list)"
  type        = string
  default     = "ubuntu-24.04"
}

variable "mon_flavor" {
  description = "Flavor for the MON/MGR/MDS node"
  type        = string
  default     = "l2.c2r4.100"
}

variable "osd_flavor" {
  description = "Flavor for OSD nodes"
  type        = string
  default     = "l2.c2r4.100"
}

variable "admin_flavor" {
  description = "Flavor for the admin/client node"
  type        = string
  default     = "l2.c2r4.100"
}

variable "osd_disk_size" {
  description = "Size in GB of the extra volume attached to each OSD node"
  type        = number
  default     = 30
}

variable "osd_disk_type" {
  description = "Volume type for OSD data disks (fast or large)"
  type        = string
  default     = "fast"
}

variable "osd_count" {
  description = "Number of OSD nodes (minimum 3 for replication)"
  type        = number
  default     = 3
}

variable "cluster_name" {
  description = "Prefix used for all instance names"
  type        = string
  default     = "ceph-lab"
}
