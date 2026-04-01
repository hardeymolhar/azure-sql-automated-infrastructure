#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(pwd)"
VENV_DIR="$PROJECT_ROOT/venv"

REQ_TXT="$PROJECT_ROOT/requirements.txt"
REQ_YML="$PROJECT_ROOT/requirements.yml"
INVENTORY_FILE="$PROJECT_ROOT/inventory/inventory.ini"
COLLECTIONS_DIR="$PROJECT_ROOT/collections"

# -----------------------------
# Logging Helpers
# -----------------------------
log() { echo "[INFO] $1"; }
warn() { echo "[WARN] $1"; }

# -----------------------------
# System Dependencies
# -----------------------------
log "Checking system dependencies..."

MISSING_PKGS=()

for pkg in build-essential python3-dev libssl-dev libffi-dev python3-venv; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
        MISSING_PKGS+=("$pkg")
    fi
done

if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
    log "Installing missing packages: ${MISSING_PKGS[*]}"
    sudo apt-get update -y
    sudo apt-get install -y "${MISSING_PKGS[@]}"
else
    log "All system dependencies already installed"
fi

# -----------------------------
# Directory Structure
# -----------------------------
log "Ensuring directory structure..."

mkdir -p playbooks inventory "$COLLECTIONS_DIR"

# -----------------------------
# Safe File Creation (No Overwrite)
# -----------------------------
create_file_if_missing() {
    local file=$1
    local content=$2

    if [[ -f "$file" ]]; then
        log "$file exists — skipping"
    else
        echo "$content" > "$file"
        log "Created $file"
    fi
}

create_file_if_missing "$REQ_YML" "---
collections:
  - name: ansible.posix
  - name: community.general
"

create_file_if_missing "$INVENTORY_FILE" "[linux_vm]
azure-vm-01 ansible_host=74.235.232.224

[linux_vm:vars]
ansible_user=azureuser
ansible_ssh_private_key_file=/home/hardeymolhar/.ssh/dev/dev-key
ansible_connection=ssh

[windows]
win-dev-vm-1 ansible_host=20.124.201.53

[windows:vars]
ansible_user=azureuser
ansible_password=r3P1iKa5x_123
ansible_connection=winrm
ansible_port=5985
ansible_winrm_transport=ntlm
ansible_winrm_server_cert_validation=ignore
"

# -----------------------------
# Virtual Environment (Idempotent)
# -----------------------------
if [[ -d "$VENV_DIR" ]]; then
    log "Virtual environment exists — reusing"
else
    log "Creating virtual environment"
    python3 -m venv "$VENV_DIR"
fi

# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"

# -----------------------------
# Pip Safety Upgrade
# -----------------------------
log "Ensuring pip is up-to-date"
python -m pip install --upgrade pip >/dev/null

# -----------------------------
# Install Python Dependencies (Idempotent)
# -----------------------------
if pip show ansible >/dev/null 2>&1; then
    log "Ansible already installed — skipping"
else
    log "Installing Ansible"
    pip install ansible ansible-lint
fi

# -----------------------------
# Galaxy Collections (Non-destructive)
# -----------------------------
log "Installing missing collections only"

mkdir -p "$COLLECTIONS_DIR"

ansible-galaxy collection install \
    -r "$REQ_YML" \
    -p "$COLLECTIONS_DIR" \
    --upgrade

# NOTE:
# --upgrade = safe update (not blind overwrite like --force)

# -----------------------------
# Freeze Dependencies Safely
# -----------------------------
if [[ -f "$REQ_TXT" ]]; then
    warn "requirements.txt exists — creating backup"
    cp "$REQ_TXT" "$REQ_TXT.bak.$(date +%s)"
fi

log "Freezing dependencies"
pip freeze > "$REQ_TXT"

# -----------------------------
# Integrity Check
# -----------------------------
if ! command -v ansible >/dev/null; then
    echo "[ERROR] Ansible not installed correctly"
    exit 1
fi

log "Setup complete (idempotent + safe)"