#!/usr/bin/env bash
# ============================================================
# Ceph Lab - Bootstrap Script
# Run this from the admin node after Terraform provisioning
#
# Usage: ./bootstrap-ceph.sh <MON_IP> <OSD1_IP> <OSD2_IP> <OSD3_IP>
# ============================================================

set -euo pipefail

MON_IP="${1:?Usage: $0 <MON_IP> <OSD1_IP> <OSD2_IP> <OSD3_IP>}"
OSD1_IP="${2:?}"
OSD2_IP="${3:?}"
OSD3_IP="${4:?}"

ADMIN_IP=$(hostname -I | awk '{print $1}')
ALL_HOSTS=("$MON_IP" "$OSD1_IP" "$OSD2_IP" "$OSD3_IP")

echo "============================================"
echo "  Ceph Lab Bootstrap"
echo "============================================"
echo "  Admin:  $ADMIN_IP (this host)"
echo "  MON:    $MON_IP"
echo "  OSD 1:  $OSD1_IP"
echo "  OSD 2:  $OSD2_IP"
echo "  OSD 3:  $OSD3_IP"
echo "============================================"

# ----------------------------------------------------------
# Step 1: Prepare all nodes (run commands over SSH)
# ----------------------------------------------------------
echo ""
echo ">>> Step 1: Preparing all nodes..."

prepare_node() {
    local ip="$1"
    local name="$2"
    echo "  Preparing $name ($ip)..."
    ssh -o StrictHostKeyChecking=no "ubuntu@$ip" bash -s <<'REMOTE'
        sudo apt-get update -qq
        sudo apt-get upgrade -y -qq
        sudo apt-get install -y -qq python3 lvm2 chrony podman
        sudo systemctl enable --now chrony
REMOTE
}

prepare_node "$MON_IP"  "mon"
prepare_node "$OSD1_IP" "osd-1"
prepare_node "$OSD2_IP" "osd-2"
prepare_node "$OSD3_IP" "osd-3"

# ----------------------------------------------------------
# Step 2: Install cephadm on admin node
# ----------------------------------------------------------
echo ""
echo ">>> Step 2: Installing cephadm on admin node..."

sudo apt-get update -qq
sudo apt-get install -y -qq python3 lvm2 chrony podman cephadm

# ----------------------------------------------------------
# Step 3: Bootstrap the cluster on the MON node
# ----------------------------------------------------------
echo ""
echo ">>> Step 3: Bootstrapping Ceph cluster..."
echo "  (This installs the first MON + MGR on $MON_IP)"

# Install cephadm on the MON node via apt (scp of the binary breaks in Reef+
# because cephadm now depends on the cephadmlib package)
ssh -o StrictHostKeyChecking=no "ubuntu@$MON_IP" bash -s <<'PREREMOTE'
    sudo apt-get update -qq
    sudo apt-get install -y -qq cephadm
PREREMOTE

ssh -o StrictHostKeyChecking=no "ubuntu@$MON_IP" bash -s <<REMOTE
    sudo cephadm bootstrap \
        --mon-ip $MON_IP \
        --initial-dashboard-user admin \
        --initial-dashboard-password ceph-lab-2024 \
        --allow-fqdn-hostname \
        --skip-monitoring-stack \
        --single-host-defaults
REMOTE

echo ""
echo ">>> Step 3b: Copying ceph config and keyring to admin node..."

ssh "ubuntu@$MON_IP" 'sudo cat /etc/ceph/ceph.conf' > /tmp/ceph.conf
ssh "ubuntu@$MON_IP" 'sudo cat /etc/ceph/ceph.client.admin.keyring' > /tmp/ceph.client.admin.keyring

sudo mkdir -p /etc/ceph
sudo cp /tmp/ceph.conf /etc/ceph/ceph.conf
sudo cp /tmp/ceph.client.admin.keyring /etc/ceph/ceph.client.admin.keyring
sudo chmod 640 /etc/ceph/ceph.client.admin.keyring
sudo chown root:ubuntu /etc/ceph/ceph.client.admin.keyring

# Install ceph-common for CLI tools on admin
sudo cephadm install ceph-common

# ----------------------------------------------------------
# Step 4: Copy SSH key from MON to allow orchestrator access
# ----------------------------------------------------------
echo ""
echo ">>> Step 4: Distributing Ceph SSH public key to all nodes..."

CEPH_PUBKEY=$(ssh "ubuntu@$MON_IP" 'sudo cephadm shell -- ceph cephadm get-pub-key 2>/dev/null')

for ip in "${ALL_HOSTS[@]}"; do
    ssh -o StrictHostKeyChecking=no "ubuntu@$ip" \
        "echo '$CEPH_PUBKEY' | sudo tee -a /root/.ssh/authorized_keys > /dev/null"
done

# ----------------------------------------------------------
# Step 5: Add hosts to the cluster
# ----------------------------------------------------------
echo ""
echo ">>> Step 5: Adding hosts to the Ceph cluster..."

ssh "ubuntu@$MON_IP" sudo cephadm shell -- ceph orch host add ceph-lab-osd-1 "$OSD1_IP"
ssh "ubuntu@$MON_IP" sudo cephadm shell -- ceph orch host add ceph-lab-osd-2 "$OSD2_IP"
ssh "ubuntu@$MON_IP" sudo cephadm shell -- ceph orch host add ceph-lab-osd-3 "$OSD3_IP"

# ----------------------------------------------------------
# Step 6: Add OSDs (use all available devices)
# ----------------------------------------------------------
echo ""
echo ">>> Step 6: Adding OSDs from available devices..."
echo "  Waiting 30s for host discovery..."
sleep 30

ssh "ubuntu@$MON_IP" sudo cephadm shell -- ceph orch apply osd --all-available-devices

echo ""
echo ">>> Waiting 60s for OSDs to come up..."
sleep 60

# ----------------------------------------------------------
# Step 7: Create a test pool and enable dashboard
# ----------------------------------------------------------
echo ""
echo ">>> Step 7: Creating test resources..."

ceph osd pool create test-pool 32 32 replicated
ceph osd pool set test-pool size 3
ceph osd pool application enable test-pool rbd

# Create an RBD image for testing
rbd create test-pool/test-image --size 1024

echo ""
echo "============================================"
echo "  Ceph Lab is READY"
echo "============================================"
echo ""
echo "  Dashboard:  https://$MON_IP:8443"
echo "  User:       admin"
echo "  Password:   ceph-lab-2024"
echo ""
echo "  Quick check from admin node:"
echo "    ceph -s"
echo "    ceph osd tree"
echo "    ceph df"
echo ""
echo "  Test pool:  test-pool (size 3, 32 PGs)"
echo "  Test image: test-pool/test-image (1 GiB)"
echo "============================================"
