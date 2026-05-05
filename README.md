# Ceph Operations Lab on Safespring

A hands-on learning environment for Ceph cluster operations, deployed on
Safespring OpenStack using the community Terraform modules.

## Architecture

```
+------------------+     +------------------+
|   admin node     |     |    mon node      |
|  (cephadm CLI,   |     |  (MON + MGR +    |
|   ceph-common,   |     |   Dashboard)     |
|   client tools)  |     |                  |
+--------+---------+     +--------+---------+
         |                        |
    [interconnect security group - full mesh]
         |                        |
+--------+---------+  +-----------+--------+  +-----------+--------+
|   osd-1 node     |  |   osd-2 node       |  |   osd-3 node       |
|  local disk +    |  |  local disk +      |  |  local disk +      |
|  30GB data vol   |  |  30GB data vol     |  |  30GB data vol     |
|  (OSD daemon)    |  |  (OSD daemon)      |  |  (OSD daemon)      |
+------------------+  +--------------------+  +--------------------+
```

## Quick Start

### 1. Deploy infrastructure

```bash
cd terraform/
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your keypair name, flavors, etc.

terraform init
terraform plan
terraform apply
```

Note the output IPs.

### 2. Bootstrap Ceph

```bash
# SSH to the admin node
ssh ubuntu@<ADMIN_IP>

# Copy the bootstrap script there (or git clone this repo)
# Then run:
chmod +x scripts/bootstrap-ceph.sh
./scripts/bootstrap-ceph.sh <MON_IP> <OSD1_IP> <OSD2_IP> <OSD3_IP>
```

### 3. Verify

```bash
ceph -s
ceph osd tree
```

### 4. Start the exercises

Open `exercises/EXERCISES.md` and work through them in order.

## Cleanup

```bash
cd terraform/
terraform destroy
```

## File Structure

```
ceph-lab/
  terraform/
    main.tf                    # Instance + security group definitions
    variables.tf               # All tunables
    outputs.tf                 # IP addresses for easy reference
    terraform.tfvars.example   # Template for your settings
  scripts/
    bootstrap-ceph.sh          # Installs and configures Ceph
  exercises/
    EXERCISES.md               # 9 hands-on exercises + mental models
  README.md                    # This file
```
