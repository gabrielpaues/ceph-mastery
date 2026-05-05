# ============================================================
# Outputs - IP addresses for SSH and cluster configuration
# ============================================================

output "admin_ip" {
  description = "IP address of the admin node"
  value       = module.admin.IPv4
}

output "mon_ip" {
  description = "IP address of the MON node"
  value       = module.mon.IPv4
}

output "osd_ips" {
  description = "IP addresses of the OSD nodes"
  value       = [for osd in module.osd : osd.IPv4]
}

output "all_hosts" {
  description = "Summary of all hosts for quick reference"
  value = {
    admin = {
      name = "${var.cluster_name}-admin"
      ip   = module.admin.IPv4
    }
    mon = {
      name = "${var.cluster_name}-mon"
      ip   = module.mon.IPv4
    }
    osds = [for i, osd in module.osd : {
      name = "${var.cluster_name}-osd-${i + 1}"
      ip   = osd.IPv4
    }]
  }
}
