# `terraform_flat` — declarative replacement for the `test-env` az-CLI pipeline

**Status:** built and validated; not yet applied against a live sandbox.
**Scope:** the IaaS substrate (network, storage, Key Vault, encrypted disks, two Windows SQL
nodes) plus the PaaS Azure SQL estate (PHASE 5, STEPs 13–19).
**Related:** [../CLAUDE.md](../CLAUDE.md) · [../docs/sql-server-on-vms-architecture.md](../docs/sql-server-on-vms-architecture.md) · [../docs/documentation-standards.md](../docs/documentation-standards.md)

---

## What problem this solves

[`scripts/shell/test-env/`](../scripts/shell/test-env/) provisions the IaaS track with about
fifteen `az` CLI scripts orchestrated by [`db-deploy.sh`](../scripts/shell/test-env/db-deploy.sh).
It works, and it was the right tool for exploring the design. But as the estate settled it started
paying the standing costs of imperative infrastructure:

- **No state, so no plan.** There is no way to ask "what would this change?" before it changes it.
- **Idempotency is hand-rolled.** Each script guards itself with a `resource_exists` helper.
  [`app-vm.sh:28`](../scripts/shell/test-env/app-vm.sh) calls that helper without it being defined
  anywhere in the repo, so under `set -euo pipefail` the script exits 127 immediately — which is
  why STEP 6 is commented out of the pipeline.
- **Ordering lives in comments.** `db-deploy.sh:27` explains that networking must come first;
  nothing enforces it.
- **Timing is guessed.** `storage.sh:89` waits `sleep 60` for a firewall change to propagate,
  `sql-db.sh:185` waits `sleep 30` for a managed identity, `key-vault.sh:55-63` polls `nslookup`
  in a loop.
- **The environment leaks into the config.** `env.conf` resolves `RESOURCE_GROUP` as
  `az group list --query "[1].name"` — an *index* into whatever the sandbox happened to return —
  and runs `az ad signed-in-user show`, `curl ipify` and `az vm list-ip-addresses` at source time.
- **Renaming is a text-rewrite.** `var-config.sh` changes the estate's name suffix by running
  `perl -pi -e` across every `.sh` and `.ps1`. That is where the literal
  `vnet-stg-ind-49stg-ind-49` in `private-dns.sh:27` came from: a double substitution.

This root converts the requested scripts into a **flat Terraform root**, so the same estate becomes
plannable, diffable, and destroyable, and — through [`outputs.tf`](outputs.tf) — consumable by
downstream pipelines.

---

## Decision record

### Decision 1 — A flat root, not another module tree

**Context.** The repo already has a modular root at [`../terraform/`](../terraform/) with six
modules and a strict boundary rule: every resource is owned by exactly one module, and cross-module
data flows only through outputs → root wiring → variables. That discipline pays off there because
the estate is multi-region and the modules genuinely encapsulate independent concerns.

**Decision.** `terraform_flat` declares every resource at the root level, split across topic files
(`network.tf`, `security.tf`, `compute.tf`, `database.tf`, `monitoring.tf`). Storage is the one
exception: it lives in the separate `bootstrap/` root and is consumed here through
`data.terraform_remote_state.bootstrap` — see "Storage lives in bootstrap/" below.

**Rationale.** The conversion target is a *single-region, single-resource-group sandbox estate*
whose scripts already share one flat namespace. Wrapping ~65 resources in modules would add an
indirection layer — a variable, an output and a wiring line per cross-file reference — that buys
nothing, because there is only one caller and nothing is reused. The DES → Key Vault access policy
→ managed disk chain in particular reads as one story in one file; split across a `security` and a
`compute` module it becomes three files and six declarations.

**Alternatives.** (a) Extend the existing modular root with the IaaS resources — rejected, because
it would entangle two independently-deployable estates in one state file. (b) A new modular root —
rejected as above; the abstraction has no second consumer to justify it.

**Consequences.** Reading the estate is easier; reusing a piece of it elsewhere is harder. If a
second environment ever needs the same shape, the honest migration is to promote topic files into
modules at that point, not to pre-build for it now.

**Operational impact.** Two roots now exist. They **must not share a state key** — see
[`backend.tf`](backend.tf), which uses `flat.tfstate` against the same storage account.

---

### Decision 2 — Own the network rather than look it up

**Context.** `network.sh` was not on the conversion list, but the requested scripts depend on it in
five places: the storage account's VNet rules need subnet IDs, both Windows VMs need NICs, the
private DNS link needs the VNet ID, Key Vault's ACL needs subnet IDs, and the SQL `AllowVMIP`
firewall rule needs a VM public IP.

**Decision.** [`network.tf`](network.tf) creates the VNet, both subnets, both Windows NSGs and
their eight rules, both NICs, and both public IPs.

**Rationale.** The alternative — `data "azurerm_subnet"` and friends — fails at *plan* time, not
gracefully at apply time, when the object does not exist. That would mean this root could not be
planned or validated until someone had first run `network.sh` against a live sandbox, which
disqualifies the entire offline verification gate below. It also makes the subnet service endpoints
a real graph edge: the storage VNet rule silently requires `Microsoft.Storage` on both subnets, and
under a data-source model Terraform has no way to know or enforce that.

**Alternatives.** Consume pre-existing network via data sources (rejected: unplannable offline,
service endpoints become an invisible precondition). A `var.create_network` hybrid (rejected:
Terraform cannot cleanly unify a counted resource and a counted data source behind one reference,
so every consumer would need `one()`/`coalesce()` across two addresses).

**Consequences.** `terraform_flat` and `db-deploy.sh` are now **alternatives, not complements**.
Running STEP 1 and then `terraform apply` against the same resource group fails with
`ResourceAlreadyExists`.

---

### Decision 3 — Express the storage Allow → Deny sequence as a dependency, not a sleep

**Context.** `storage.sh` creates the account open (`--default-action Allow`, line 38), does its
data-plane work through that window — two containers, a 119 MB blob, a stored access policy — then
locks it down (`--default-action Deny`, lines 337-343), with a bare `sleep 60` at line 89 hoping
the firewall change has propagated.

**Decision.** The account is declared with **no inline `network_rules{}` block**, so it is born
open. A separate `azurerm_storage_account_network_rules` resource applies the Deny posture, with
`depends_on` covering every data-plane resource.

**Rationale.** This is only expressible because the two forms are mutually exclusive in the
provider — a fact verified against the 4.75.0 binary. Adding `network_rules{}` to the account would
*deadlock the graph*: the account would be born Deny and the containers could never be created.
Splitting it converts a timing hope into a topological guarantee.

**Consequences.** A real operational hazard replaces a real timing bug: once locked, an apply from
a **different client IP** fails while the provider refreshes the container and blob. The failure is
in the refresh, not in a resource definition, which makes it confusing the first time. The rescue is
one command, and `var.storage_default_action` exists specifically for it:

```bash
terraform apply -var=storage_default_action=Allow   # reopen from the new IP
terraform apply                                     # re-lock
```

---

### Decision 4 — `terraform_data` shims for the two things azurerm cannot express

**Context.** Enumerating every resource schema in the azurerm 4.75.0 provider binary confirms there
is **no resource** for a storage container *stored access policy*, and **none** for Azure SQL
*automatic tuning* (STEP 18).

**Decision.** Both were implemented as `terraform_data` with a `local-exec` provisioner calling `az`,
gated on `var.enable_cli_shims`, and labelled as escape hatches at their definition sites.
Only one survives: [`database.tf`](database.tf)'s `terraform_data.sql_automatic_tuning`. The other,
`terraform_data.xevent_stored_access_policy`, lived in `storage.tf` and went with it when storage moved
to `bootstrap/`; it has **not** been re-created there, so the XEvent stored access policy is currently
unmanaged.

**Rationale.** `terraform_data` is a Terraform **core builtin** (≥ 1.4, which this repo already
requires), so it needs no additional provider. That matters concretely: the `null` and `azapi`
providers are not in the cached mirror, and adding either would break the offline verification gate.
`triggers_replace` keeps each shim from re-running on every apply.

The stored access policy is worth shimming rather than dropping because an **ad-hoc SAS cannot be
revoked** once issued, whereas a SAS derived from a stored access policy dies with the policy. The
XEvent database-scoped credential is long-lived, so revocability is the entire point.

**Alternatives.** Add the `azapi` provider (rejected: a sixth provider and a second auth path for
two small objects, and it breaks offline init). Drop both (rejected for the policy, since it
silently downgrades a revocable credential to an unrevocable one).

**Consequences — stated plainly.** Ordering is graph-managed; **state is not**. Terraform will never
report drift on either object, `terraform destroy` does not explicitly reverse them, and both need
`az` on `PATH` with an active login. They are escape hatches and are documented as such.

For automatic tuning the boundary is narrower still: `sql-automatic-tuning.sh` is *two* things — an
ARM control-plane setting **and** a set of `sqlcmd` T-SQL statements (`ALTER DATABASE ... SET
QUERY_STORE`). The shim covers only the ARM half. The T-SQL half is outside what any IaC tool
models and remains a post-apply script, which `outputs.tf` feeds.

---

### Decision 5 — `azurerm_virtual_machine_run_command` for the WinRM bootstrap

**Context.** A stock Windows Server image will not accept an Ansible connection: the WinRM HTTPS
listener does not exist, and `Enable-PSRemoting`'s own firewall rule is scoped to the local subnet
only, while Ansible connects from the internet. `win-sql-vm.sh:83-100` fixes both with a 13-line
`az vm run-command invoke`.

**Decision.** `azurerm_virtual_machine_run_command`, with the 13 statements preserved verbatim in
`local.winrm_bootstrap_script` ([`locals.tf`](locals.tf)).

**Rationale.** The obvious alternative — a `CustomScriptExtension`, which
[`../terraform/modules/vm/main.tf:128`](../terraform/modules/vm/main.tf) uses — has two concrete
problems. A failed extension leaves the VM in a `Failed` provisioning state that blocks every
subsequent apply until manually removed. And it forces all 13 statements into one `commandToExecute`
JSON string, meaning PowerShell escaped inside JSON inside HCL. A run command takes the script as a
plain heredoc, where the backslashes in `WSMan:\localhost\Listener` are literal and no PowerShell
variable (`$env:COMPUTERNAME`, `$winrmCert.Thumbprint`, `$_.Keys`) collides with Terraform's `${…}`
interpolation.

**Consequences.** A behavioural change worth knowing: `az vm run-command invoke` is a transient
action that re-ran on *every* `db-deploy.sh` pass. This is a persistent child resource that
re-executes only when the script changes or the VM is replaced. That is better — the unconditional
re-run was waste — but if WinRM breaks in-guest for an unrelated reason, `terraform apply` will not
silently repair it. Force a re-run explicitly:

```bash
terraform apply -replace='azurerm_virtual_machine_run_command.winrm["node1"]'
```

---

### Decision 6 — `time_rotating` for the lab-archive SAS, not `timestamp()`

**Context.** `vm-config.sh:76-93` minted a 7-day SAS with `az storage account keys list`, GNU/BSD
`date` arithmetic, and `az storage blob generate-sas`.

**Decision.** `data.azurerm_storage_account_blob_container_sas` with its window pinned by a
`time_rotating` resource ([`data.tf`](data.tf)).

**Rationale.** The obvious `start = timestamp()` recomputes on every plan, so the SAS — and every
output derived from it — shows a diff on every single run. That trains reviewers to skim diffs,
which is precisely when a real change slips past. `time_rotating` stores the window and advances it
once per period, so the value is stable between rotations and still never goes stale. This is a
deliberate improvement on
[`../terraform/modules/vm/data.tf`](../terraform/modules/vm/data.tf), which has the `timestamp()`
problem. For the same reason, the modular root's `infrastructure_json_export` output is **not**
carried over here.

**Consequences.** The SAS is computed locally from the account key and makes no network call, so it
still works after the storage firewall locks to Deny.

---

### Decision 7 — Single-region scalars instead of the modular root's region lists

**Context.** [`../terraform/variables.tf`](../terraform/variables.tf) declares `rg` and `location` as
`list(string)`, indexed into `primary_`/`secondary_`/`tertiary_` locals.

**Decision.** `terraform_flat` uses plain `var.resource_group_name` and `var.location` strings.

**Rationale.** The list form exists in the modular root because it is genuinely multi-region —
failover groups need a secondary. Every resource in this root is in one region and one resource
group, matching `env.conf`'s single `LOCATION="centralindia"`. Carrying a list to index `[0]` from
everywhere would imitate the shape of the other root without its reason.

**Consequences.** A deliberate, recorded inconsistency between the two roots rather than a silent
one. As in the modular root, **no `azurerm_resource_group` is created** — the sandbox issues them and
the signed-in principal cannot.

---

### Correction — where a faithful port was not possible

`sql-auditing.sh` sets three audit action groups on the **database**
(`SCHEMA_OBJECT_ACCESS_GROUP`, `DATABASE_OBJECT_CHANGE_GROUP`, `DATABASE_PERMISSION_CHANGE_GROUP`,
lines 68-79) and two on the **server**.

`azurerm_mssql_database_extended_auditing_policy` in 4.75.0 has **no**
`audit_actions_and_groups` attribute — its complete schema is `{database_id, enabled,
log_monitoring_enabled, retention_in_days, storage_*}`. Only the server-level resource accepts
action groups.

All five groups are therefore declared on the server policy, where they apply to every database on
the server. Audit coverage is identical; it is expressed in one place instead of two. This is
recorded because the initial implementation got it wrong — the attribute was verified on the server
resource and assumed on the database resource, and the editor's language server caught it. The
lesson generalises: **sibling resources in this provider do not share schemas**, and the only
reliable check is the provider binary itself.

---

## Layout

| File | Owns |
|---|---|
| [`versions.tf`](versions.tf) | Terraform ≥ 1.4.0; azurerm pinned to **4.75.0** exactly, plus `http` and `time` |
| [`providers.tf`](providers.tf) | `provider "azurerm"`, `resource_provider_registrations = "none"` |
| [`backend.tf`](backend.tf) | azurerm remote state, key `flat.tfstate` |
| [`variables.tf`](variables.tf) | ~50 inputs, each traced to its `env.conf` ancestor |
| [`terraform.tfvars.example`](terraform.tfvars.example) | Committable template (`*.tfvars` is gitignored) |
| [`locals.tf`](locals.tf) | All derived names, the disk/node/rule maps, the WinRM script, the rendered inventory |
| [`data.tf`](data.tf) | Client config, client IP, `terraform_remote_state` read of `bootstrap/` |
| [`main.tf`](main.tf) | Deployment-order narrative and the "these are alternatives" warning |
| [`network.tf`](network.tf) | VNet, 2 subnets, 2 NSGs + 8 rules, 2 NICs, 2 public IPs, private DNS zone/link/records |
| [`bootstrap/`](bootstrap/) | **Separate root.** Storage account, 4 containers, 119 MB lab blob, container SAS. Applied first; this root reads its outputs. XEvent policy shim and firewall lockdown are not (yet) re-created there |
| [`security.tf`](security.tf) | Key Vault, 3 CMKs, 3 secrets, access policies, 2 Disk Encryption Sets |
| [`compute.tf`](compute.tf) | 2 Windows SQL nodes, WinRM run commands, 8 encrypted disks; Linux track (gated) |
| [`database.tf`](database.tf) | SQL server, Entra admin, firewall rules, database, CMK TDE, auditing, retention, tuning shim |
| [`monitoring.tf`](monitoring.tf) | Log Analytics, diagnostic settings, action group, 6 metric alerts |
| [`outputs.tf`](outputs.tf) | Scalars, sensitive values, and composite artefacts for pipelines |
| [`vm-config.sh`](vm-config.sh) | Ansible bridge driven entirely by `terraform output` |

### Script → Terraform map

| Shell script | `db-deploy.sh` step | Replaced by |
|---|---|---|
| `network.sh` | 1 | `network.tf` |
| `private-dns.sh` | 1b | `network.tf` |
| `storage.sh` | 2 | `bootstrap/storage.tf` (separate root) |
| `key-vault.sh` | 3 | `security.tf` |
| `encrypted-mgd-disks.sh` | 5 | `security.tf` + `compute.tf` (gated) |
| `app-vm.sh` | 6 | `compute.tf` (gated) |
| `win-sql-vm.sh` / `win-sql-vm-2.sh` | 7, 9 | `compute.tf` |
| `win-encrypted-disks.sh` / `-2.sh` | 8, 10 | `security.tf` + `compute.tf` |
| `vm-config.sh` | 12 | `vm-config.sh` (rewritten) |
| `sql-db.sh` | 13 | `database.tf` |
| `set-entra-admin.sh` | 14 | `database.tf` (`azuread_administrator`) |
| `sql-auditing.sh` | 15 | `database.tf` + `monitoring.tf` |
| `diag-settings.sh` | 16 | `monitoring.tf` |
| `sqldb-backup.sh` | 17 | `database.tf` (retention blocks) |
| `sql-automatic-tuning.sh` | 18 | `database.tf` (shim, ARM half only) |
| `sql-alert.sh` | 19 | `monitoring.tf` |
| `var-config.sh` | 0 | Retired — `var.resource_suffix` replaces it |

**Not converted** (all commented out in `db-deploy.sh`, all outside the requested scope):
`bastion.sh`, `load-balancer.sh`, `application-security-group.sh`, `sql-engine-access.sh`,
`cluster-nsg-rules.sh`, `identity.sh` (STEP 20 — T-SQL, not infrastructure), `encrypted-cek.ps1`.

The internal load balancer is the significant one. `network.tf` publishes
`aglistener.corp.internal` → `10.10.1.200` in private DNS, but **nothing yet answers on that
address**. The Always On AG listener remains a *planned* component, not a running one.

---

## Usage

```bash
cp terraform.tfvars.example terraform.tfvars   # then edit — it is gitignored
az login

terraform -chdir=terraform_flat init -reconfigure -backend-config="key=flat.tfstate"
terraform -chdir=terraform_flat plan -var-file=terraform.tfvars -out=tfplan
terraform -chdir=terraform_flat apply tfplan

./terraform_flat/vm-config.sh                   # Ansible, driven by terraform output
```

## Verification

Runs offline, with no Azure credentials — the five providers are already cached under
`../terraform/.terraform/providers/`, which is a valid filesystem-mirror layout:

```bash
terraform fmt -check -recursive terraform_flat/
terraform -chdir=terraform_flat init -backend=false
terraform -chdir=terraform_flat validate
shellcheck terraform_flat/vm-config.sh
```

**Evidence at time of writing** — all four pass. `validate` is not a formality here: it evaluates
`file(pathexpand(...))` on the SSH keypair and `filemd5()`/`fileexists()` on the lab archive, and
type-checks every attribute against the 4.75.0 schema. It caught the
`azurerm_mssql_database_extended_auditing_policy` error recorded above.

**What `validate` cannot catch**, and therefore what remains unverified until a real apply: global
name uniqueness (`storage69987`, `khv-stg-ind-49`, `sqlserver-stg-ind-49`), sandbox quota for
`Standard_D8s_v3` and the 8124 GB disk, whether the required resource providers are pre-registered
(`resource_provider_registrations = "none"` means Terraform will not register them), whether the DES
grant lands before the first disk, and whether the WinRM bootstrap succeeds in-guest.

Post-apply checks are emitted as the `connection_commands` output:

```bash
terraform -chdir=terraform_flat output connection_commands
ansible -i inventory.ini windows_vm -m win_ping
```

---

## Known risks and limitations

1. **`terraform_flat` and `db-deploy.sh` are alternatives.** Running both against one resource group
   fails with `ResourceAlreadyExists` on ~40 resources. The current sandbox already holds a
   shell-built estate — [`../inventory.ini`](../inventory.ini) has live node IPs — so the first
   apply should target a **fresh resource group**, or be preceded by an import campaign.
2. **Key Vault purge protection is irreversible.** `var.kv_purge_protection` defaults to `true`,
   matching `key-vault.sh:19`. A `terraform destroy` then leaves a soft-deleted vault holding
   `khv-<suffix>` for 7 days, and a rebuild under the same name fails. Set it `false` for a sandbox
   you expect to recreate.
3. **Two objects are shimmed, not managed.** No drift detection on the XEvent stored access policy
   or automatic tuning; both need `az` on `PATH`.
4. **Three globally-unique names.** `storage69987`, `khv-<suffix>` and `sqlserver-<suffix>` can
   collide with another tenant. All are variables.
5. **Quota.** Node 1 is `Standard_D8s_v3`, and the four disks per node total ~15.2 TB — ~30 TB
   across both. `terraform.tfvars.example` carries a commented-out cheap profile.
6. **`time_sleep` is wall-clock, not a readiness probe.** A slow sandbox can still fail an apply.
   Re-running is safe: every resource here is idempotent.
7. **Both Windows NICs sit in `subnet-<suffix>`, not `subnet-win-<suffix>`.** Preserved from
   `network.sh:254`/`:360`. It looks like an oversight but is load-bearing: a single-subnet
   availability group cannot advertise a multi-subnet VNN listener, which is exactly why the design
   calls for an internal load balancer to float the listener IP. `subnet-win-<suffix>` is created,
   given a service endpoint and granted a storage VNet rule, but holds no NICs.
8. **Secrets.** Every credential variable is `sensitive = true` and sourced from the gitignored
   `terraform.tfvars`. This does **not** retroactively fix
   [`env.conf:158`](../scripts/shell/test-env/env.conf), which carries a plaintext password in git,
   nor [`../inventory.ini`](../inventory.ini), which is committed with `ansible_password`. Both
   warrant a separate cleanup; adding `inventory.ini` to `.gitignore` is the obvious first step, and
   this root now generates that file rather than depending on the committed copy.
9. **`resource_provider_registrations = "none"`** means the subscription must already have
   `Microsoft.Compute`, `KeyVault`, `Sql`, `OperationalInsights`, `Storage` and `Network`
   registered. If `Microsoft.OperationalInsights` is not, the workspace create fails obscurely.
10. **The AG listener has no backend.** See "Not converted" above.
