# =============================================================================
# terraform_flat — flat-file Terraform root for the IaaS + PaaS SQL estate
# =============================================================================
#
# WHAT THIS ROOT IS
# -----------------
# A declarative replacement for the imperative az-CLI pipeline in
# scripts/shell/test-env/, driven by db-deploy.sh. It is a FLAT root by design:
# every resource is declared in a topic file at this level, with no modules. The
# modular root at terraform/ still exists and is untouched — the two are separate
# roots with separate state keys (see backend.tf).
#
#
# !! THESE ARE ALTERNATIVES, NOT COMPLEMENTS !!
# ---------------------------------------------
# This root OWNS the resources that db-deploy.sh STEPs 1, 1b, 2, 3, 5, 6, 7, 8, 9,
# 10 and 13-19 create. Running those shell scripts AND `terraform apply` against
# the same resource group produces ResourceAlreadyExists on the VNet and roughly
# forty other resources. Pick one.
#
# If a sandbox already has the shell-built estate (check `inventory.ini` for live
# node IPs), either target a fresh resource group or plan an import campaign
# before the first apply.
#
#
# DEPLOYMENT ORDER
# ----------------
# db-deploy.sh encoded its ordering in comments and `sleep`. Here it is a real
# dependency graph, so the order below is what Terraform DERIVES, not what it is
# told. It is documented for readers, not for the tool.
#
#   network.tf    VNet, subnets, NSGs, NICs, public IPs        (STEP 1)
#                 Private DNS zone + link + A records          (STEP 1b)
#                    |
#                    v
#   bootstrap/    Storage account -> 4 containers -> 119 MB lab blob -> container
#                 SAS                                            (STEP 2)
#                 NOT part of this root. A SEPARATE Terraform root, applied first
#                 by bootstrap/cleanup.sh, whose outputs this root reads back via
#                 data.terraform_remote_state.bootstrap (see data.tf). It also
#                 holds the state blob this root's storage outputs come from.
#                    |
#   security.tf   Key Vault -> Terraform access policy -> 3 CMKs + 3 secrets
#                 -> Disk Encryption Sets -> DES access policies (STEP 3, 5, 8, 10)
#                    |
#                    v
#   compute.tf    2 Windows SQL nodes (zones 1 and 2) + WinRM bootstrap
#                 8 encrypted zonal data disks + attachments     (STEPs 7-10)
#                 Linux VM + 4 disks, gated off by default       (STEPs 5-6)
#                    |
#                    v
#   database.tf   SQL server + Entra admin + firewall + database + CMK TDE
#                 + auditing + backup retention                  (STEPs 13-15, 17-18)
#   monitoring.tf Log Analytics + diagnostics + action group + 6 alerts
#                                                                (STEPs 15-16, 19)
#                    |
#                    v
#   vm-config.sh  Ansible in-guest configuration, driven entirely by
#                 `terraform output`                             (STEP 12)
#
# STEP 20 (identity.sh) is intentionally NOT converted: it is T-SQL database
# initialisation via sqlcmd, not infrastructure. outputs.tf exports everything it
# needs so it can still be run afterwards.
#
#
# WHAT IS NOT CONVERTED
# ---------------------
# All of these are commented out in db-deploy.sh today and were outside the
# requested scope. Recorded here so the gap is explicit rather than implied:
#   bastion.sh, load-balancer.sh, application-security-group.sh,
#   sql-engine-access.sh, cluster-nsg-rules.sh, identity.sh, encrypted-cek.ps1
#
# The internal load balancer is the significant one: var.ag_listener_ip is
# published in private DNS by network.tf, but nothing yet answers on it. Until
# load-balancer.sh is converted, the AG listener remains a planned component.
#
#
# ONE ESCAPE HATCH
# ----------------
# azurerm 4.75.0 has no resource for automatic tuning, so it is implemented as
# terraform_data + local-exec and labelled as such at its definition:
#   database.tf  terraform_data.sql_automatic_tuning
# Ordering is graph-managed; state and drift detection are not. See var.enable_cli_shims.
#
# There was a second shim, terraform_data.xevent_stored_access_policy in storage.tf.
# It went with storage when that moved to bootstrap/ and has NOT been re-created
# there — the XEvent stored access policy is currently unmanaged, as is the
# firewall lockdown to Deny that storage.tf also owned. var.xevent_policy_name,
# var.xevent_policy_expiry, var.blob_soft_delete_days and var.storage_account_name
# are the leftovers of that file and are now unused by this root.
#
# =============================================================================

# This root creates NO azurerm_resource_group. The Whizlabs sandbox issues resource
# groups and the signed-in principal cannot create them, so the RG is an input
# (var.resource_group_name). Same convention as the modular root.
