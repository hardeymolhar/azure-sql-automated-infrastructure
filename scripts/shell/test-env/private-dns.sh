#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.conf"

# =========================================================
# PRIVATE DNS ZONE — corp.internal
# ---------------------------------------------------------
# Provides name resolution for WSFC cluster objects without Active Directory DNS.
# VMs in the linked VNet resolve records via the Azure DNS resolver (168.63.129.16).
#
# Record strategy is a HYBRID:
#   - Node VM records (ms-<suffix>, cs-<suffix> -> private IP) are created
#     AUTOMATICALLY by Azure auto-registration. The VNet link below is created
#     with --registration-enabled true, so each Windows node registers its own
#     A record the moment the VM is created (Steps 7/9), then keeps it in sync on
#     IP change / delete. No runtime IP discovery needed here.
#   - aglistener (ILB front-end VIP) and sqlcluster (WSFC CNO) are NOT virtual
#     machines, so auto-registration cannot create them. They are seeded manually
#     below from the static IPs in env.conf:
#       aglistener.<zone> -> LB_PRIVATE_IP   (10.10.1.200) — AG listener via ILB
#       sqlcluster.<zone> -> WSFC_CLUSTER_IP  (10.10.1.201) — WSFC CNO static IP
#
# Prerequisite: network.sh must have run (VNet must exist). This script must run
# BEFORE the node VMs are created so auto-registration is active when they boot.
# =========================================================

VNET_LINK_NAME="vnet-res-ind-112$RESOURCE_SUFFIX"

resource_exists() { eval "$1" >/dev/null 2>&1; }

# =========================================================
# CREATE THE PRIVATE DNS ZONE
# =========================================================
if resource_exists "az network private-dns zone show --resource-group $RESOURCE_GROUP --name $PRIVATE_DNS_ZONE"; then
  echo -e "${YELLOW}Private DNS zone $PRIVATE_DNS_ZONE already exists.${NC}"
else
  echo -e "${BLUE}Creating Private DNS zone $PRIVATE_DNS_ZONE...${NC}"
  az network private-dns zone create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$PRIVATE_DNS_ZONE"
fi

# =========================================================
# LINK THE ZONE TO THE VNET (auto-registration ON)
# ---------------------------------------------------------
# registration-enabled=true: Windows node VMs auto-register their A records.
# Idempotent — create the link if missing, otherwise just ensure registration
# is enabled on the existing link.
# =========================================================
VNET_ID=$(az network vnet show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$VNET_NAME" \
  --query id -o tsv)

if az network private-dns link vnet show \
     --resource-group "$RESOURCE_GROUP" \
     --zone-name "$PRIVATE_DNS_ZONE" \
     --name "$VNET_LINK_NAME" >/dev/null 2>&1; then
  az network private-dns link vnet update \
    --resource-group "$RESOURCE_GROUP" \
    --zone-name "$PRIVATE_DNS_ZONE" \
    --name "$VNET_LINK_NAME" \
    --registration-enabled true \
    --output none
  echo -e "${YELLOW}VNet link $VNET_LINK_NAME present; node auto-registration enabled.${NC}"
else
  echo -e "${BLUE}Linking zone $PRIVATE_DNS_ZONE to VNet $VNET_NAME...${NC}"
  az network private-dns link vnet create \
    --resource-group "$RESOURCE_GROUP" \
    --zone-name "$PRIVATE_DNS_ZONE" \
    --name "$VNET_LINK_NAME" \
    --virtual-network "$VNET_ID" \
    --registration-enabled true \
    --output none
  echo -e "${GREEN}Linked $VNET_NAME to $PRIVATE_DNS_ZONE (node auto-registration on).${NC}"
fi

# =========================================================
# HELPER — set an A record to a single IP (idempotent)
# ---------------------------------------------------------
# Delete any existing set, recreate it with a low TTL, add the one address.
# Three straight-line az calls — no loops, no read-back queries.
# =========================================================
upsert_a_record() {
  local name="$1" ip="$2"
  az network private-dns record-set a delete \
    --resource-group "$RESOURCE_GROUP" \
    --zone-name "$PRIVATE_DNS_ZONE" \
    --name "$name" \
    --yes --output none 2>/dev/null || true
  az network private-dns record-set a create \
    --resource-group "$RESOURCE_GROUP" \
    --zone-name "$PRIVATE_DNS_ZONE" \
    --name "$name" \
    --ttl 60 --output none
  az network private-dns record-set a add-record \
    --resource-group "$RESOURCE_GROUP" \
    --zone-name "$PRIVATE_DNS_ZONE" \
    --record-set-name "$name" \
    --ipv4-address "$ip" \
    --output none
  echo -e "${GREEN}  $name.$PRIVATE_DNS_ZONE -> $ip${NC}"
}

# =========================================================
# SEED STATIC A RECORDS (non-VM resources only)
# =========================================================
echo -e "${BLUE}Seeding static A records (AG listener + WSFC CNO)...${NC}"
upsert_a_record "aglistener" "$LB_PRIVATE_IP"
upsert_a_record "sqlcluster" "$WSFC_CLUSTER_IP"

echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}Private DNS zone $PRIVATE_DNS_ZONE configured.${NC}"
echo -e "${GREEN}  AG listener:  aglistener.$PRIVATE_DNS_ZONE -> $LB_PRIVATE_IP${NC}"
echo -e "${GREEN}  WSFC CNO:     sqlcluster.$PRIVATE_DNS_ZONE -> $WSFC_CLUSTER_IP${NC}"
echo -e "${GREEN}  Node records: auto-registered by each VM on creation (Steps 7/9)${NC}"
echo -e "${GREEN}==========================================${NC}"
