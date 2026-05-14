
#!/bin/bash
# =========================================================
# COLORS
# =========================================================
set -euo pipefail
source "$(dirname "$0")/env.conf"


# =========================================================
# CONFIGURATION
# =========================================================

NEW_ID="$RESOURCE_SUFFIX"

TARGET_DIR="$PROJECT_ROOT/scripts/shell/test-env"

BACKUP_DIR="$PROJECT_ROOT/.backups"

# =========================================================
# VALIDATION
# =========================================================

if [[ ! -d "$TARGET_DIR" ]]; then
  echo -e "${RED}Directory does not exist:${NC} $TARGET_DIR"
  exit 1
fi

mkdir -p "$BACKUP_DIR"

TIMESTAMP=$(date +%Y%m%d-%H%M%S)

echo -e "${BLUE}=========================================================${NC}"
echo -e "${YELLOW}Replacing dashed numeric suffixes...${NC}"
echo -e "${GREEN}New Identifier :${NC} $NEW_ID"
echo -e "${GREEN}Target Directory:${NC} $TARGET_DIR"
echo -e "${GREEN}Backup Directory:${NC} $BACKUP_DIR"
echo -e "${GREEN}Timestamp       :${NC} $TIMESTAMP"
echo -e "${BLUE}=========================================================${NC}"

# =========================================================
# PROCESS FILES
# =========================================================

find "$TARGET_DIR" \
  -path "*/.backups/*" -prune -o \
  -type f \
  \( -name "*.sh" -o -name "*.ps1" \) \
  -print | while read -r file; do


  # =========================================================
  # DETECT INFRASTRUCTURE RESOURCE IDENTIFIERS
  # =========================================================

  if grep -Eq '\b(vm|vnet|subnet|nsg|nic|pip|kv|sql-des|des|disk|data-disk|log-disk|temp-disk|backup-disk)-[0-9a-zA-Z-]+\b' "$file"; then

    echo -e "${GREEN}Updating:${NC} $file"


    # =========================================================
    # CREATE UNIQUE BACKUP FILE
    # =========================================================

    safe_name=$(echo "$file" | tr '/' '_')

    backup_file="$BACKUP_DIR/${safe_name}.${TIMESTAMP}.bak"

    cp "$file" "$backup_file"

    echo -e "${BLUE}Backup created:${NC} $backup_file"

    # =========================================================
    # REPLACE INFRASTRUCTURE RESOURCE SUFFIXES
    # Example:
    # vm-9r5-1n4-77 -> vm-9r5-1n4-77
    # kv-9r5-1n4-77 -> kv-9r5-1n4-77
    # sql-des-9r5-1n4-77 -> sql-des-9r5-1n4-77
    # =========================================================

perl -pi -e "s/([\"'=:\x20])(vm|vnet|subnet|nsg|nic|pip|kv|sql-des|des|data-dsk|log-dsk|temp-dsk|backup-dsk)-[a-zA-Z0-9-]+/\1\2-$NEW_ID/g" "$file"
  fi

done

# =========================================================
# VALIDATION
# =========================================================

echo -e "${BLUE}=========================================================${NC}"
echo -e "${GREEN}Replacement complete.${NC}"
echo -e "${BLUE}=========================================================${NC}"

echo -e "${YELLOW}Modified files:${NC}"
grep -RE '\b(vm|vnet|subnet|nsg|nic|pip|kv|sql-des|des|disk|data-dsk|log-disk|temp-disk|backup-disk)-[0-9a-zA-Z-]+\b' "$TARGET_DIR" || true

echo -e "${BLUE}=========================================================${NC}"
echo -e "${GREEN}Backup files stored in:${NC}"
echo "$BACKUP_DIR"
echo -e "${BLUE}=========================================================${NC}"