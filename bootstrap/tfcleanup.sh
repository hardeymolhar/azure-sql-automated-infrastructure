#!/usr/bin/env bash
set -euo pipefail

# Resolve bootstrap directory
BOOTSTRAP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Define project root (parent of bootstrap)
PROJECT_ROOT="$(cd "$BOOTSTRAP_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

echo "Running cleanup from project root: $PROJECT_ROOT"


sed -i '/^rg = \[/,/^]/d' bootstrap/terraform.tfvars



sed -i '/^rg = \[/,/^]/d' terraform/terraform.tfvars

awk '
/data[[:space:]]+"terraform_remote_state"[[:space:]]+"storage"[[:space:]]*{/ {
  in_block=1
}

in_block && /config[[:space:]]*=[[:space:]]*{/ {
  depth=1
  while (depth > 0 && getline) {
    depth += gsub(/{/, "{")
    depth -= gsub(/}/, "}")
  }
  next
}

{ print }
' terraform/data.tf > tmp.tf && mv tmp.tf terraform/data.tf


awk '
/^terraform[[:space:]]*{/ {skip=1; depth=1; next}
skip {
    depth += gsub(/{/, "{")
    depth -= gsub(/}/, "}")
    if (depth == 0) skip=0
    next
}
{print}
' bootstrap/backend.tf > tmp.tf && mv tmp.tf bootstrap/backend.tf


awk '
/^terraform[[:space:]]*{/ {skip=1; depth=1; next}
skip {
    depth += gsub(/{/, "{")
    depth -= gsub(/}/, "}")
    if (depth == 0) skip=0
    next
}
{print}
' terraform/backend.tf > tmp.tf && mv tmp.tf terraform/backend.tf


# Remove Terraform artifacts across project
find . -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null || true
find . -type f -name "terraform.tfstate" -delete 2>/dev/null || true
find . -type f -name "terraform.tfstate.backup" -delete 2>/dev/null || true
find . -type f -name ".terraform.lock.hcl" -delete 2>/dev/null || true
find . -type f -name "tfplan" -delete 2>/dev/null || true

echo "Cleanup complete."