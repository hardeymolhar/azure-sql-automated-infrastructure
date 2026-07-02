#!/bin/bash
source "$(dirname "$0")/env.conf"
set -euo pipefail

# =========================================================
# INTERNAL LOAD BALANCER — Always On AG Listener
# ---------------------------------------------------------
# Provisions a Standard, INTERNAL load balancer that fronts the two Windows
# SQL Server VMs ($WIN_VM_NAME / $WIN_VM_NAME_2) and provides the "floating"
# IP address used by the Always On availability group listener.
#
# Per Microsoft guidance for an AG listener behind an ILB:
#   - Standard SKU, internal, in the SAME VNet/subnet as the SQL VMs.
#   - A static private frontend IP ($LB_PRIVATE_IP) = the listener IP.
#   - A TCP health probe on $PROBE_PORT (59999); the in-guest listener answers
#     on this port so the LB knows which node currently owns the AG.
#   - A load-balancing rule on 1433 with FLOATING IP (direct server return)
#     enabled — only one node owns the listener at a time. Floating IP is
#     IMMUTABLE after creation, so it is set here at create time.
#   - NSG rules allowing the AzureLoadBalancer service tag (probe source) and
#     intra-VNet traffic to 1433 + the probe port, or the probe is dropped and
#     the listener silently becomes unreachable.
# Ref: learn.microsoft.com/azure/azure-sql/virtual-machines/windows/
#      availability-group-load-balancer-portal-configure
# =========================================================

# =========================================================
# WHY SINGLE-SUBNET ALWAYS ON (DESIGN NOTE)
# ---------------------------------------------------------
# Both SQL nodes live in ONE subnet (SUBNET_NAME, 10.10.1.0/24 — see
# network.sh) yet still get HA by being pinned to different availability zones
# (WIN_VM_ZONE=1 / WIN_VM_ZONE_2=2 in env.conf). A single-subnet topology is
# deliberately chosen here because this is a Whizlabs PAYG sandbox: it is
# temporary, identity-restricted, and gives us a flat, easy-to-reason-about
# address space where the whole platform (Linux workload VM, both SQL nodes,
# private endpoints, Bastion) sits in one VNet without inter-subnet routing or
# extra NSG plumbing. The cost of that simplicity is that a single-subnet AG
# CANNOT advertise a multi-subnet listener, so it needs this internal load
# balancer to publish the listener's "floating" IP (10.10.1.200) and a TCP
# health probe (port 59999) to track which replica currently owns the AG. The
# trade-offs are real: failover is gated by probe detection latency (~probe
# interval x threshold) rather than DNS, the floating-IP/direct-server-return
# rule is immutable once created, and the LB is one more component (and a
# potential bottleneck/SPOF if it were not zone-redundant — Standard SKU here
# is). In PRODUCTION this would look different: replicas would sit in SEPARATE
# subnets (commonly one per zone, and a third in another region for DR via a
# distributed AG), which removes the load balancer entirely — a multi-subnet
# VNN listener (RegisterAllProvidersIP=1 + MultiSubnetFailover=true) or, on
# SQL 2019 CU8+/Windows 2016+, a DNN listener fails over via DNS in seconds
# with no probe and no SPOF. Prod would also drop the per-VM public IPs in
# favour of private-only access (Private Endpoints + Bastion), use HTTPS WinRM
# with real certs instead of sandbox HTTP, automate via OIDC/service principal
# rather than `az login`, and size up to Premium/Ultra disks and larger VM
# SKUs with a proper WSFC quorum (cloud witness). This script intentionally
# optimises for a reproducible single-subnet sandbox demo, not prod topology.
# =========================================================

# =========================================================
# HELPER FUNCTIONS
# =========================================================

resource_exists() {
  local resource_check_command="$1"

  if eval "$resource_check_command" >/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

# Resolve the NSG that actually governs a given NIC: prefer the NIC-level NSG,
# fall back to the subnet-stg-ind-103 NSG. Echoes the NSG name, or nothing if neither
# is attached. Keeps the LB rules self-correcting if NSG wiring later drifts.
resolve_nic_nsg() {
  local nic="$1" nsg_id subnet_id

  nsg_id=$(az network nic show -g "$RESOURCE_GROUP" -n "$nic" \
    --query "networkSecurityGroup.id" -o tsv 2>/dev/null)

  if [ -z "$nsg_id" ]; then
    subnet_id=$(az network nic show -g "$RESOURCE_GROUP" -n "$nic" \
      --query "ipConfigurations[0].subnet.id" -o tsv 2>/dev/null)
    [ -n "$subnet_id" ] && nsg_id=$(az network vnet subnet show --ids "$subnet_id" \
      --query "networkSecurityGroup.id" -o tsv 2>/dev/null)
  fi

  [ -n "$nsg_id" ] && basename "$nsg_id"
}

# =========================================================
# RESOLVE NIC NAMES + PRIVATE IPs FOR BOTH SQL VMs
# ---------------------------------------------------------
# Resolve the NIC actually attached to each VM (rather than trusting the
# configured name) so the script stays correct even if NIC wiring drifts.
# =========================================================

echo -e "${BLUE}Resolving NIC names for the Windows SQL VMs...${NC}"

WIN_VM1_NIC=$(az vm nic list \
  --resource-group "$RESOURCE_GROUP" \
  --vm-name "$WIN_VM_NAME" \
  --query "[0].id" \
  -o tsv | awk -F'/' '{print $NF}')

WIN_VM2_NIC=$(az vm nic list \
  --resource-group "$RESOURCE_GROUP" \
  --vm-name "$WIN_VM_NAME_2" \
  --query "[0].id" \
  -o tsv | awk -F'/' '{print $NF}')

echo -e "${GREEN}Node 1 NIC:${NC} $WIN_VM1_NIC"
echo -e "${GREEN}Node 2 NIC:${NC} $WIN_VM2_NIC"

echo -e "${BLUE}Resolving private IPs for the Windows SQL VMs...${NC}"

WIN_VM1_PRIVATE_IP=$(az vm show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$WIN_VM_NAME" \
  -d \
  --query privateIps \
  -o tsv)

WIN_VM2_PRIVATE_IP=$(az vm show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$WIN_VM_NAME_2" \
  -d \
  --query privateIps \
  -o tsv)

echo -e "${GREEN}Node 1 private IP:${NC} $WIN_VM1_PRIVATE_IP"
echo -e "${GREEN}Node 2 private IP:${NC} $WIN_VM2_PRIVATE_IP"

# =========================================================
# CREATE THE INTERNAL LOAD BALANCER
# =========================================================

if resource_exists "az network lb show --resource-group $RESOURCE_GROUP --name $LB_NAME"; then
  echo -e "${YELLOW}Load balancer already exists. Skipping creation...${NC}"
else
  echo -e "${BLUE}Creating internal load balancer...${NC}"

  # Standard SKU + a private frontend IP on the SQL subnet (no public IP) makes
  # this an INTERNAL load balancer; it is REGIONAL by default (global/cross-
  # region is a separate `az network cross-region-lb` resource, not a flag here).
  # The frontend IP is zone-redundant by default — correct for the zonal nodes.
  az network lb create \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --name "$LB_NAME" \
    --sku Standard \
    --frontend-ip-name "$LB_FRONTEND_NAME" \
    --vnet-name "$VNET_NAME" \
    --subnet "$SUBNET_NAME" \
    --private-ip-address "$LB_PRIVATE_IP"
fi

# =========================================================
# CREATE THE BACKEND ADDRESS POOL
# =========================================================

if resource_exists "az network lb address-pool show --resource-group $RESOURCE_GROUP --lb-name $LB_NAME --name $LB_BACKEND_POOL_NAME"; then
  echo -e "${YELLOW}Backend pool already exists. Skipping creation...${NC}"
else
  echo -e "${BLUE}Creating backend address pool...${NC}"

  az network lb address-pool create \
    --resource-group "$RESOURCE_GROUP" \
    --lb-name "$LB_NAME" \
    --name "$LB_BACKEND_POOL_NAME"
fi

# =========================================================
# ADD EACH VM's NIC IP-CONFIG TO THE BACKEND POOL
# ---------------------------------------------------------
# Resolve the ip-config name dynamically per NIC (do not assume "ipconfig1").
# `address-pool add` is idempotent, so it is safe to re-run.
# =========================================================

for NIC in "$WIN_VM1_NIC" "$WIN_VM2_NIC"; do
  IPCONFIG=$(az network nic show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$NIC" \
    --query "ipConfigurations[0].name" \
    -o tsv)

  echo -e "${BLUE}Adding $NIC ($IPCONFIG) to $LB_BACKEND_POOL_NAME...${NC}"

  az network nic ip-config address-pool add \
    --resource-group "$RESOURCE_GROUP" \
    --nic-name "$NIC" \
    --ip-config-name "$IPCONFIG" \
    --address-pool "$LB_BACKEND_POOL_NAME" \
    --lb-name "$LB_NAME"
done

# =========================================================
# HEALTH PROBE (TCP on the AG probe port)
# =========================================================

if resource_exists "az network lb probe show --resource-group $RESOURCE_GROUP --lb-name $LB_NAME --name $LB_PROBE_NAME"; then
  echo -e "${YELLOW}Health probe already exists. Skipping creation...${NC}"
else
  echo -e "${BLUE}Creating health probe (TCP/$PROBE_PORT)...${NC}"

  az network lb probe create \
    --resource-group "$RESOURCE_GROUP" \
    --lb-name "$LB_NAME" \
    --name "$LB_PROBE_NAME" \
    --protocol tcp \
    --port "$PROBE_PORT" \
    --interval 5 \
    --probe-threshold 2
fi

# =========================================================
# LOAD-BALANCING RULE (1433, floating IP / direct server return)
# =========================================================

if resource_exists "az network lb rule show --resource-group $RESOURCE_GROUP --lb-name $LB_NAME --name $LB_RULE_NAME"; then
  echo -e "${YELLOW}Load-balancing rule already exists. Skipping creation...${NC}"
else
  echo -e "${BLUE}Creating load-balancing rule (TCP/$SQL_PORT, floating IP)...${NC}"

  az network lb rule create \
    --resource-group "$RESOURCE_GROUP" \
    --lb-name "$LB_NAME" \
    --name "$LB_RULE_NAME" \
    --protocol Tcp \
    --frontend-port "$SQL_PORT" \
    --backend-port "$SQL_PORT" \
    --frontend-ip-name "$LB_FRONTEND_NAME" \
    --backend-pool-name "$LB_BACKEND_POOL_NAME" \
    --probe-name "$LB_PROBE_NAME" \
    --floating-ip true \
    --enable-tcp-reset true \
    --idle-timeout 30
fi

# =========================================================
# NSG RULES REQUIRED FOR THE LISTENER TO WORK
# ---------------------------------------------------------
# Without these the health probe (sourced from the AzureLoadBalancer service
# tag) is dropped and the listener becomes unreachable even though every
# command above "succeeded". We allow:
#   - AzureLoadBalancer -> 1433 + probe port  (health probe)
#   - VirtualNetwork    -> 1433 + probe port  (listener + inter-node traffic)
# Applied to BOTH Windows node NSGs (Node 1 + Node 2).
# =========================================================

add_lb_nsg_rules() {
  local nsg="$1"

  if resource_exists "az network nsg rule show --resource-group $RESOURCE_GROUP --nsg-name $nsg --name Allow-LB-Probe"; then
    echo -e "${YELLOW}[$nsg] Allow-LB-Probe already exists. Skipping...${NC}"
  else
    echo -e "${BLUE}[$nsg] Creating Allow-LB-Probe (AzureLoadBalancer -> $SQL_PORT,$PROBE_PORT)...${NC}"
    az network nsg rule create \
      --resource-group "$RESOURCE_GROUP" \
      --nsg-name "$nsg" \
      --name "Allow-LB-Probe" \
      --priority 1030 \
      --direction Inbound \
      --access Allow \
      --protocol Tcp \
      --source-address-prefixes AzureLoadBalancer \
      --source-port-ranges "*" \
      --destination-port-ranges "$SQL_PORT" "$PROBE_PORT"
  fi

  if resource_exists "az network nsg rule show --resource-group $RESOURCE_GROUP --nsg-name $nsg --name Allow-AG-Listener-VNet"; then
    echo -e "${YELLOW}[$nsg] Allow-AG-Listener-VNet already exists. Skipping...${NC}"
  else
    echo -e "${BLUE}[$nsg] Creating Allow-AG-Listener-VNet (VirtualNetwork -> $SQL_PORT,$PROBE_PORT)...${NC}"
    az network nsg rule create \
      --resource-group "$RESOURCE_GROUP" \
      --nsg-name "$nsg" \
      --name "Allow-AG-Listener-VNet" \
      --priority 1040 \
      --direction Inbound \
      --access Allow \
      --protocol Tcp \
      --source-address-prefixes VirtualNetwork \
      --source-port-ranges "*" \
      --destination-port-ranges "$SQL_PORT" "$PROBE_PORT"
  fi
}

# Target whatever NSG actually governs each node's NIC (NIC- or subnet-stg-ind-103),
# de-duped in case both nodes share one NSG. Self-corrects if wiring drifts.
LB_NSGS=()
for NIC in "$WIN_VM1_NIC" "$WIN_VM2_NIC"; do
  NSG=$(resolve_nic_nsg "$NIC")
  if [ -z "$NSG" ]; then
    echo -e "${YELLOW}WARN: no NSG on NIC $NIC; relying on Azure default NSG rules.${NC}"
    continue
  fi
  case " ${LB_NSGS[*]:-} " in
    *" $NSG "*) ;;                 # already queued
    *) LB_NSGS+=("$NSG") ;;
  esac
done

if [ ${#LB_NSGS[@]} -gt 0 ]; then
  for NSG in "${LB_NSGS[@]}"; do
    add_lb_nsg_rules "$NSG"
  done
fi

# =========================================================
# VALIDATION SUMMARY
# =========================================================

echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}Internal load balancer configured.${NC}"
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}LB name:${NC}       $LB_NAME"
echo -e "${GREEN}Listener IP:${NC}   $LB_PRIVATE_IP (frontend: $LB_FRONTEND_NAME)"
echo -e "${GREEN}Backend pool:${NC}  $LB_BACKEND_POOL_NAME -> $WIN_VM1_PRIVATE_IP, $WIN_VM2_PRIVATE_IP"
echo -e "${GREEN}Probe:${NC}         TCP/$PROBE_PORT   Rule: TCP/$SQL_PORT (floating IP)"
echo ""
echo -e "${YELLOW}Next:${NC} the in-guest WSFC + AG listener must be created with IP"
echo -e "      $LB_PRIVATE_IP and probe port $PROBE_PORT (Failover Cluster Manager"
echo -e "      / PowerShell on the primary replica)."
echo -e "${GREEN}==========================================${NC}"
