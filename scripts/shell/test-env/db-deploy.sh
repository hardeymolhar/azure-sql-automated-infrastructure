#!/bin/bash
# =========================================================
# SANDBOX ENVIRONMENT NOTES
# =========================================================
# This deployment targets the Whizlabs Azure sandbox environment, which is
# time-bound and provisioned dynamically. Resource names/suffixes may vary
# between sessions, but the deployment workflow and ordering stay consistent.
# It intentionally optimizes for rapid, reproducible deployment within the
# sandbox's time limits.
#


set -euo pipefail

source "$(dirname "$0")/env.conf"

# ---------------------------------------------------------
# PHASE 0 - Baseline configuration
# ---------------------------------------------------------
# Seeds the variable/config files the later steps read.
echo -e "${BLUE}Baseline: pre-deployment variable configuration...${NC}"
# ./var-config.sh

# ---------------------------------------------------------
# PHASE 1 - Core infrastructure (foundation for everything)
# ---------------------------------------------------------
# Networking comes FIRST: storage and key vault below attach network rules that
# reference the subnet (and the subnet's service endpoints), so the VNet/subnet
# must already exist. VMs also need the NICs that network.sh creates.

# echo -e "${BLUE}STEP 1 - Virtual Network, subnets, NSGs, NICs, public IPs${NC}"
# ./network.sh

# # requires: network.sh (VNet + VNet link). Creates corp.internal Private DNS
# # Zone, links it to the VNet, and seeds A records for the AG listener, WSFC CNO,
# # and cluster node hostnames. Must run before the Ansible step so DNS resolves
# # from inside the VNet when cluster formation and AG listener binding happen.
# echo -e "${BLUE}STEP 1b - Private DNS Zone (corp.internal — AG listener, WSFC CNO, node records)${NC}"
# ./private-dns.sh

# echo -e "${BLUE}STEP 2 - Storage Account (backups, XEvents, diagnostics)${NC}"
# ./storage.sh

# echo -e "${BLUE}STEP 3 - Key Vault + encryption keys${NC}"
# ./key-vault.sh

# # requires: network.sh (needs the VNet + VM NSGs it adds rules to). Bastion only
# # depends on networking, so it can run any time after STEP 1.
# # echo -e "${BLUE}STEP 4 - Azure Bastion (private RDP/SSH to the VMs)${NC}"
# ./bastion.sh

# ---------------------------------------------------------
# PHASE 2 - Linux application VM
# ---------------------------------------------------------
# The Linux pattern is "disks first, then VM": encrypted-mgd-disks.sh CREATES
# the disk-encryption-set + managed disks, and app-vm.sh CREATES the VM and
# ATTACHES those disks.

# requires: key-vault.sh (the DES wraps a Key Vault key).
echo -e "${BLUE}STEP 5 - Disk Encryption Set + encrypted disks (Linux)${NC}"
./encrypted-mgd-disks.sh

# requires: network.sh (NIC) + STEP 5 (the disks it attaches).
echo -e "${BLUE}STEP 6 - Linux Application VM (creates VM, attaches disks)${NC}"
./app-vm.sh

# ---------------------------------------------------------
# PHASE 3 - Windows SQL Server nodes (Always On AG, 2 zones)
# ---------------------------------------------------------
# The Windows pattern is the reverse of Linux: "VM first, then disks", because
# win-encrypted-disks*.sh ATTACHES the disks to an existing VM. Node 1 is in
# zone 1, node 2 in zone 2 (HA across availability zones).

# requires: network.sh (the Windows NIC) + key-vault.sh (DES key).
echo -e "${BLUE}STEP 7 - Windows SQL VM - Node 1 (Zone 1)${NC}"
./win-sql-vm.sh

# requires: STEP 7 (the VM must exist before its disks can attach).
echo -e "${BLUE}STEP 8 - Encrypted disks for SQL Node 1${NC}"
./win-encrypted-disks.sh

# requires: network.sh (the second Windows NIC) + key-vault.sh (DES key).
echo -e "${BLUE}STEP 9 - Windows SQL VM - Node 2 (Zone 2)${NC}"
./win-sql-vm-2.sh

# requires: STEP 9 (the VM must exist before its disks can attach).
echo -e "${BLUE}STEP 10 - Encrypted disks for SQL Node 2${NC}"
./win-encrypted-disks-2.sh

# requires: BOTH nodes (STEP 7 + STEP 9) -- it adds both NICs to its backend
# pool to publish the Always On AG listener's floating IP.
echo -e "${BLUE}STEP 11 - Internal Load Balancer (AG listener)${NC}"
./load-balancer.sh

# requires: all SQL VMs exist (their NICs + public IPs). Groups every SQL VM into
# one ASG, then opens inbound 1433 from the client IP + each VM's public IP (ASG
# as the rule destination) so the Linux and Windows nodes can reach each other's
# SQL engine over the public internet (SSMS-style). Sources stay scoped (never
# 0.0.0.0/0), matching the SSH/RDP/WinRM client-IP rules.
echo -e "${BLUE}STEP 11b - SQL engine peer access (ASG + inbound 1433 allowlist)${NC}"
./application-security-group.sh
./sql-engine-access.sh

# requires: both Windows VMs up (NIC resolution). Creates asg-sqlcluster, attaches
# both Windows node NICs, and adds 5 inbound rules on each Windows NSG (priorities
# 100–140) for the cluster ports: 1433 SQL, 5022 HADR endpoint, 3343 heartbeat,
# 135 RPC endpoint mapper, 49152-65535 dynamic RPC. ASG-to-ASG rules are valid for
# intra-VNet traffic and correctly handle the no-AD workgroup cluster scenario.
echo -e "${BLUE}STEP 11c - WSFC cluster NSG rules (asg-sqlcluster, ports 1433/5022/3343/135/dyn-RPC)${NC}"
./cluster-nsg-rules.sh

# ---------------------------------------------------------
# PHASE 4 - In-guest configuration (Ansible)
# ---------------------------------------------------------
# requires: the VMs to be up with their disks attached (and WinRM enabled by the
# win-sql-vm*.sh scripts). Configures the data drives, installs packages, and
# sets up SQL Server inside the guests.
echo -e "${BLUE}STEP 12 - Configure VMs with Ansible (drives, packages, SQL)${NC}"
./vm-config.sh

# ---------------------------------------------------------
# PHASE 5 - Azure SQL Database (PaaS track)
# ---------------------------------------------------------
# This is the managed Azure SQL side. Order: create the server/DB, then layer
# server-level identity, then security/observability, then DB initialization.

# requires: the resource group (and network/monitoring if private endpoints /
# diagnostics are enabled inside it).
# echo -e "${BLUE}STEP 13 - Azure SQL Database (server + database)${NC}"
# ./sql-db.sh

# requires: STEP 13 (sets the Entra admin on the SQL server).
# echo -e "${BLUE}STEP 14 - Microsoft Entra administrator${NC}"
# ./set-entra-admin.sh

# requires: STEP 13 + storage.sh / Log Analytics (audit destination).
# echo -e "${BLUE}STEP 15 - SQL Auditing${NC}"
# ./sql-auditing.sh

# requires: STEP 13 + Log Analytics workspace (diagnostics destination).
# echo -e "${BLUE}STEP 16 - SQL Diagnostic Settings${NC}"
# ./diag-settings.sh

# requires: STEP 13 (backup policies apply to the database).
# echo -e "${BLUE}STEP 17 - SQL Backup policies${NC}"
# ./sqldb-backup.sh

# requires: STEP 13 (tuning options apply to the server/database).
# echo -e "${BLUE}STEP 18 - SQL Automatic Tuning${NC}"
# ./sql-automatic-tuning.sh

# requires: STEP 13 + STEP 16 (alerts fire on metrics emitted to monitoring).
# echo -e "${BLUE}STEP 19 - SQL Alerts and notifications${NC}"
# ./sql-alert.sh

# CMK / Always Encrypted permissions can take a minute to propagate before the
# database can be initialized against them -- wait, then initialize.
# echo -e "${YELLOW}Waiting 2 min for Always Encrypted / CMK to propagate...${NC}"
# sleep 120

# requires: STEP 13 (initializes the DB, query store, etc.).
# echo -e "${BLUE}STEP 20 - Initialize database + Query Store${NC}"
# ./identity.sh

# ---------------------------------------------------------
# PHASE 6 - Optional: drive a workload against the database
# ---------------------------------------------------------
# The block below looks up live resource names and feeds them to an Ansible
# workload playbook. It is commented out by default.
#
# Beginner notes on the lookups:
#   --query "..."         -> a JMESPath expression that filters/reshapes the
#                            JSON the az CLI returns, so we extract just one value.
#   -o tsv                -> output as plain text (no quotes/JSON) so it can be
#                            assigned straight into a shell variable.
#   [1].name              -> pick the SECOND resource group in the list (index is
#                            0-based). The sandbox hands you more than one RG and
#                            the workload RG is the second one -- this is a
#                            sandbox quirk, not a general Azure rule.
#   [?contains(name,'X')] -> keep only items whose name contains "X"; the
#                            trailing "| [0]" then takes the first match.

# echo "Fetching Azure outputs..."

# LIN_VM_IP=$(az vm list-ip-addresses \
#   --resource-group "$(az group list --query '[1].name' -o tsv)" \
#   --name "vm-stg-ind-103" \
#   --query "[0].virtualMachine.network.publicIpAddresses[0].ipAddress" \
#   -o tsv)

# SQL_SERVER_NAME=$(az sql server list \
#   --resource-group "$(az group list --query '[1].name' -o tsv)" \
#   --query "[?contains(name, '$RESOURCE_SUFFIX')].name | [0]" \
#   -o tsv)

# DATABASE_NAME=$(az sql db list \
#   --resource-group "$(az group list --query '[1].name' -o tsv)" \
#   --server "$SQL_SERVER_NAME" \
#   --query "[?contains(name, 'demo')].name | [0]" \
#   -o tsv)

# echo -e "${YELLOW}Running SQL workload playbook...${NC}"

# The "\" at the end of each line continues one long command onto the next line.
# ANSIBLE_CONFIG="$PROJECT_ROOT/ansible.cfg" ansible-playbook \
#   "$PROJECT_ROOT/ansible/playbooks/concurrency-v2.yml" \
#   -i "$INVENTORY_FILE" \
#   --extra-vars "sql_server_name=$SQL_SERVER_NAME \
#   database_name=$DATABASE_NAME \
#   worker_count=40 \
#   reporting_workers=12 \
#   deadlock_workers=6 \
#   session_holder_count=220 \
#   max_batches=0 \
#   min_batch_size=750 \
#   max_batch_size=2500 \
#   workload_duration_minutes=60 \
#   batch_delay_ms=0"

# echo -e "${GREEN}DEPLOYMENT PIPELINE COMPLETED${NC}"
