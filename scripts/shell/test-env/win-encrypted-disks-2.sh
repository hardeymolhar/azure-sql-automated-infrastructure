#!/bin/bash
source "$(dirname "$0")/env.conf"
set -euo pipefail

# =========================================================
# WINDOWS SQL VM 2 (NODE 2) — ENCRYPTED DATA DISKS (SSE-CMK via DES)
# ---------------------------------------------------------
# Node-2 counterpart of win-encrypted-disks.sh. Same configuration — 4 CMK
# encrypted managed disks (data / log / tempdb / backup) attached at LUN 0-3 —
# but the disks use the $WIN_*_DISK_2 names and are created in $WIN_VM_ZONE_2
# (Zone 2) so they can attach to the Zone-2 VM ($WIN_VM_NAME_2). The Disk
# Encryption Set ($WIN_DES_NAME) is regional and shared with Node 1.
#
# Run order: AFTER win-sql-vm-2.sh (the VM must exist before disks can attach).
# Idempotent: re-running skips resources that already exist / are attached.
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

# =========================================================
# CONTEXT — Key Vault, subscription, CMK key URL
# =========================================================

KV_NAME="$(az keyvault list --resource-group "$RESOURCE_GROUP" --query "[?contains(name, '$RESOURCE_SUFFIX')].name | [0]" -o tsv)"
SUBSCRIPTION_ID="$(az account show --query id -o tsv)"

DISK_ENCRYPTION_KEY_URL="$(az keyvault key show \
  --vault-name "$KV_NAME" \
  --name "$DISK_ENCRYPTION_SET_KEY" \
  --query key.kid \
  -o tsv)"

echo -e "${YELLOW}Key Vault:        $KV_NAME${NC}"
echo -e "${YELLOW}CMK key URL:      $DISK_ENCRYPTION_KEY_URL${NC}"

KV_ID="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.KeyVault/vaults/$KV_NAME"
WIN_DES_ID="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Compute/diskEncryptionSets/$WIN_DES_NAME"

# =========================================================
# ENSURE THE DISK ENCRYPTION SET EXISTS (shared with Node 1)
# =========================================================

if resource_exists "az disk-encryption-set show --resource-group $RESOURCE_GROUP --name $WIN_DES_NAME"; then
  echo -e "${YELLOW}Disk encryption set $WIN_DES_NAME already exists. Skipping creation...${NC}"
else
  echo -e "${BLUE}Creating disk encryption set $WIN_DES_NAME...${NC}"

  az disk-encryption-set create \
    --name "$WIN_DES_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --source-vault "$KV_ID" \
    --key-url "$DISK_ENCRYPTION_KEY_URL"
fi

# =========================================================
# GRANT THE DES IDENTITY WRAP/UNWRAP ON THE KEY VAULT
# =========================================================

DES_PRINCIPAL_ID="$(az disk-encryption-set show \
  --name "$WIN_DES_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query identity.principalId \
  -o tsv)"

echo -e "${GREEN}DES principal ID: $DES_PRINCIPAL_ID${NC}"

az keyvault set-policy \
  --name "$KV_NAME" \
  --object-id "$DES_PRINCIPAL_ID" \
  --key-permissions get wrapKey unwrapKey

# =========================================================
# CREATE ENCRYPTED MANAGED DISKS (Zone 2)
# ---------------------------------------------------------
# Each disk is encrypted at rest with the customer-managed key via the DES and
# created in Zone 2 so it can attach to the Zone-2 VM.
# =========================================================

create_encrypted_disk() {
  local disk_name="$1"
  local size_gb="$2"

  if resource_exists "az disk show --resource-group $RESOURCE_GROUP --name $disk_name"; then
    echo -e "${YELLOW}Disk $disk_name already exists. Skipping...${NC}"
  else
    echo -e "${BLUE}Creating encrypted disk $disk_name (${size_gb} GB)...${NC}"

    az disk create \
      --resource-group "$RESOURCE_GROUP" \
      --name "$disk_name" \
      --location "$LOCATION" \
      --zone "$WIN_VM_ZONE_2" \
      --size-gb "$size_gb" \
      --sku "$WIN_DISK_SKU" \
      --disk-encryption-set "$WIN_DES_ID"
  fi
}

echo -e "${YELLOW}Creating encrypted managed disks...${NC}"
create_encrypted_disk "$WIN_DATA_DISK_2"   "$WIN_DATA_DISK_SIZE"
create_encrypted_disk "$WIN_LOG_DISK_2"    "$WIN_LOG_DISK_SIZE"
create_encrypted_disk "$WIN_TEMP_DISK_2"   "$WIN_TEMP_DISK_SIZE"
create_encrypted_disk "$WIN_BACKUP_DISK_2" "$WIN_BACKUP_DISK_SIZE"

# =========================================================
# ATTACH DISKS TO THE WINDOWS VM (LUN 0-3)
# ---------------------------------------------------------
# Caching follows SQL-Server-on-Azure-VM guidance:
#   data/tempdb -> ReadOnly, log/backup -> None.
# =========================================================

attach_disk() {
  local disk_name="$1"
  local lun="$2"
  local caching="$3"

  if az vm show \
      --resource-group "$RESOURCE_GROUP" \
      --name "$WIN_VM_NAME_2" \
      --query "storageProfile.dataDisks[?name=='$disk_name']" \
      -o tsv | grep -q "$disk_name"; then

    echo -e "${YELLOW}Disk $disk_name already attached. Skipping...${NC}"
  else
    echo -e "${BLUE}Attaching $disk_name at LUN $lun (caching $caching)...${NC}"

    local disk_id
    disk_id="$(az disk show \
      --resource-group "$RESOURCE_GROUP" \
      --name "$disk_name" \
      --query id \
      -o tsv)"

    az vm disk attach \
      --resource-group "$RESOURCE_GROUP" \
      --vm-name "$WIN_VM_NAME_2" \
      --ids "$disk_id" \
      --lun "$lun" \
      --caching "$caching"

    echo -e "${GREEN}$disk_name attached.${NC}"
  fi
}

echo -e "${YELLOW}Attaching encrypted disks to $WIN_VM_NAME_2...${NC}"
attach_disk "$WIN_DATA_DISK_2"   0 ReadOnly
attach_disk "$WIN_LOG_DISK_2"    1 None
attach_disk "$WIN_TEMP_DISK_2"   2 ReadOnly
attach_disk "$WIN_BACKUP_DISK_2" 3 None

# =========================================================
# SUMMARY
# =========================================================

echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}Windows SQL VM (Node 2) encrypted disks ready.${NC}"
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}VM:${NC}                $WIN_VM_NAME_2  (Zone $WIN_VM_ZONE_2)"
echo -e "${GREEN}Disk encryption:${NC}   SSE-CMK via $WIN_DES_NAME"
echo -e "${GREEN}LUN 0 (DATA):${NC}      $WIN_DATA_DISK_2   -> drive F: (SQLDATA)"
echo -e "${GREEN}LUN 1 (LOG):${NC}       $WIN_LOG_DISK_2    -> drive G: (SQLLOG)"
echo -e "${GREEN}LUN 2 (TEMPDB):${NC}    $WIN_TEMP_DISK_2   -> drive T: (SQLTEMPDB)"
echo -e "${GREEN}LUN 3 (BACKUP):${NC}    $WIN_BACKUP_DISK_2 -> drive H: (SQLBACKUP)"
echo ""
echo -e "${GREEN}Next:${NC} run vm-config.sh to partition/format the drives in-guest"
echo -e "      (ansible/playbooks/windows-dbdrive-configuration.yml)."
echo -e "${GREEN}==========================================${NC}"
