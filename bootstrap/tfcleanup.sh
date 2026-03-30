#!/usr/bin/env bash
set -euo pipefail

# Resolve bootstrap directory
BOOTSTRAP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Define project root (parent of bootstrap)
PROJECT_ROOT="$(cd "$BOOTSTRAP_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

echo "Running cleanup from project root: $PROJECT_ROOT"

# Remove Terraform artifacts across project
find . -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null || true
find . -type f -name "terraform.tfstate" -delete 2>/dev/null || true
find . -type f -name "terraform.tfstate.backup" -delete 2>/dev/null || true
find . -type f -name ".terraform.lock.hcl" -delete 2>/dev/null || true
find . -type f -name "tfplan" -delete 2>/dev/null || true

echo "Cleanup complete."