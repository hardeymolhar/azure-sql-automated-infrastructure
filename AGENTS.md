# AGENTS.md

Guidance for AI agents (and humans) working in this repository.

This file has two halves. The first half — **The project** — is reference: what this system is,
where everything lives, how to build and deploy it, and the rules and gotchas that keep it correct.
The second half — **How to work in this repository** — is behavior: the engineering discipline that
governs every change, and your standing job as the project's design historian. Read the reference to
orient yourself; apply the behavior to everything you do.

---

# The project

## What this project is

A **secure, cross-region-highly-available Azure SQL (PaaS) platform**, built as a
banking/fintech reference workload. It provisions everything with Terraform, configures
the database and a Linux workload VM with Ansible/PowerShell, and drives realistic
financial transaction load with a .NET 8 workload simulator.

The engineering goals (see [docs/paas-database.md](docs/paas-database.md) and
[README.md](README.md)) are:

- **HA / DR**: RTO 15–30 min, RPO ≤ 5 min via **Failover Groups** + **Active Geo-Replication**
- **No public exposure**: **Private Endpoints** for SQL and Key Vault; **Proxy** connection policy (port 1433 only)
- **Data protection**: **TDE with Customer-Managed Keys (CMK)** in Key Vault, **Always Encrypted**, **Dynamic Data Masking**, **Auditing**, **Data Classification**
- **Identity**: **Managed Identity** (SQL→Key Vault) and **Microsoft Entra ID** + SQL logins for users
- **Observability**: Azure Monitor → Log Analytics → Workbooks/Alerts

The screenshots in [docs/images/](docs/images/) are real captures of the deployed system
(Always Encrypted CEK/CMK backed by Azure Key Vault, DDM masked vs. admin views, auditing,
diagnostic settings, data classification). Treat the docs as accurate intent, but **verify
against code** — see "Doc vs. code drift" below.

## Repository layout

| Path | What lives here |
|---|---|
| [terraform/](terraform/) | **Main IaC.** Modular root composing `network`, `monitoring`, `sql`, `security`, `private-endpoints`, `vm` modules. |
| [terraform/modules/](terraform/modules/) | One module per concern. Each has `main.tf`, `variables.tf`, `outputs.tf`, `locals.tf`, `versions.tf`. |
| [bootstrap/](bootstrap/) | **Separate Terraform root** that creates the remote-state storage account (`tfstate225222`, ZRS). Run this *before* the main config. |
| [ansible/](ansible/) | Playbooks to configure the RHEL workload VM (install .NET 8 SDK, ODBC Driver 18, SQL tools) and run workloads. Inventory in [inventory.ini](inventory.ini). |
| [scripts/dotnet/](scripts/dotnet/) | **.NET 8 workload simulator** (`Microsoft.Data.SqlClient`). Projects: `batch-inserts`, `concurrency`, `concurrent-stress`, `controlled-workload`, `high-contention`, `managed-identity-connection`. Primary workload engine (full Always Encrypted + AKV + MI support). |
| [scripts/python/](scripts/python/) | Earlier `pyodbc` experiments (connection, batch inserts, concurrency, MI auth). Superseded by .NET for encrypted workloads. |
| [scripts/powershell/](scripts/powershell/) | SQL bootstrap (`init-db*.ps1`), firewall rules, Always Encrypted CEK setup. |
| [scripts/sql/](scripts/sql/) | Schema (`transactions`, `cards`, `accounts`, `channels`, `users`, `audit`), performance-monitoring queries, Always Encrypted DDL. |
| [scripts/shell/](scripts/shell/) | Orchestration: `init.sh` (bootstrap), `deploy.sh` (main deploy + Ansible). `test-env/` holds per-feature `az`/PowerShell setup scripts. |
| [scripts/yaml/](scripts/yaml/) | `cloud-init` templates for VM provisioning. |
| [docs/](docs/) | Architecture write-ups (`paas-database.md`), images, and demo videos. |
| [.github/workflows/](.github/workflows/) | `ci.yml` (validation only) and `deploy.yml` (manual `workflow_dispatch`). |

## Build, validate, and deploy

> **Prerequisites**: `terraform`, `az` CLI (logged in via `az login`), `ansible`, `.NET 8 SDK`,
> and an SSH keypair at `~/.ssh/ssh_key/vm-key/vm-key{,.pub}` (Terraform reads these with `file()`).

**Terraform (main config):**
```bash
cd terraform
terraform init                 # needs Azure auth for the azurerm remote-state backend
terraform validate             # works offline once providers are installed
terraform fmt -recursive
terraform plan  -var-file=terraform.tfvars   # needs az login + tfvars (both gitignored)
```
If the backend can't authenticate (expired token) or you only need to validate, use
`terraform init -backend=false` to install providers/modules locally, then `terraform validate`.

**Full deployment** (sandbox flow, run locally — *not* via CI):
1. `az login`
2. `scripts/shell/init.sh` — writes `rg`/var tfvars, then `terraform init/validate` the **bootstrap** root (creates the state storage account).
3. `scripts/shell/deploy.sh [env]` — `init -reconfigure` with a dynamic backend key (`${env}.tfstate`), `fmt`, `validate`, `plan -out=tfplan`, `apply`, then runs the Ansible configuration.
4. PowerShell scripts configure SQL (Entra admin, Always Encrypted CEK, auditing).
5. Run a .NET workload, e.g. `dotnet run --project scripts/dotnet/controlled-workload`.

**.NET workloads:**
```bash
dotnet build scripts/dotnet/<project>          # e.g. controlled-workload
dotnet run   --project scripts/dotnet/<project>
```

**CI** ([.github/workflows/ci.yml](.github/workflows/ci.yml)) is **validation-only** on push to `main`/PRs:
`dotnet build`, `yamllint .`, `ansible-lint ansible/playbooks/*.yml`, `shellcheck` on every `*.sh`,
PowerShell tokenize parse. There is **no automated infra deploy** — keep these linters green.

## Terraform module design (important)

The root module is an **orchestrator only**: it wires modules together and holds shared
`data`/`locals` (`client_ip`, RG/location lists). **Strict module boundaries apply:**

- Every Azure resource is owned by exactly **one** module.
- Modules **never** reference another module's resources directly (`azurerm_*.*`).
  Cross-module data flows through **outputs → root wiring → variables** only.
  e.g. `module.sql` consumes `log_analytics_workspace_id = module.monitoring.log_analytics_workspace_id`;
  `module.security` consumes SQL server IDs/identities; `module.private_endpoints` consumes
  subnet/Key Vault/SQL/DNS-zone IDs.
- A module's `outputs.tf` may only reference resources/variables/locals **declared in that module**.

Ownership map:

| Module | Owns |
|---|---|
| `network` | vnet, subnets, NSG/ASG (+ rules), NICs, public IPs, **bastion**, private DNS zones + vnet links |
| `monitoring` | Log Analytics Workspace |
| `sql` | SQL servers (primary + secondary), 20 databases, failover group, auditing, firewall rules, DB diagnostic settings |
| `security` | Key Vault, CMK key, access policies, `time_sleep`, SQL TDE |
| `private-endpoints` | Private Endpoints + DNS zone groups (SQL, Key Vault) |
| `vm` | Linux + Windows VMs, VM extension, managed disks + attachments |

Module dependency order is acyclic: `monitoring → sql → security`, `network → vm`,
and `{network, security, sql} → private_endpoints`. Preserve this when adding wiring —
do not introduce a cycle (e.g. don't make `monitoring` depend on `sql`).

When you add a resource that another module needs: add an **output** in the owner, a
**variable** in the consumer, and the **wiring line** in [terraform/main.tf](terraform/main.tf).

## Conventions

- **Providers**: `azurerm ~> 4.0` (+ `http`, `random`, `time`, `tls`, `local`). Declare per-module
  provider requirements in each module's `versions.tf`.
- **Remote state**: `azurerm` backend in the `tfstate225222` storage account; the state key is
  set dynamically per environment (`${ENV}.tfstate`). The **bootstrap** root creates this storage.
- **Naming**: a `random_string.suffix` (owned by the `sql` module) is threaded to other modules
  (e.g. Key Vault name) via `module.sql.name_suffix` — don't duplicate the random resource.
- **Secrets / inputs**: `*.tfvars`, `*.tfstate`, `.env`, `.vault_pass` are **gitignored**. Never
  commit them. `var.network_structure` (incl. an `AzureBastionSubnet`) must be supplied via tfvars.
- **Data model**: banking schema (`tbl_transactions`/`tbl_transactions_secure`, `cards`, `accounts`).
  Sensitive columns carry DDM + classification; PAN/token/`session_key` use Always Encrypted.
- **Docs**: architecture is explained with Mermaid diagrams; keep new diagrams in that style.

## Gotchas an agent should know

- **Sandbox constraints**: built/tested in a Whizlabs PAYG Azure sandbox — **temporary,
  identity-restricted, no RBAC-to-other-identities, no OIDC/federated identity, no service-principal
  automation**. That's why infra is deployed by **local Bash + `az login`**, not GitHub Actions.
  `deploy.yml` exists but cannot fully authenticate in the sandbox.
- **`terraform validate` evaluates `file()`**: it reads the SSH keys at
  `~/.ssh/ssh_key/vm-key/vm-key{,.pub}` (in `vm` and `security` modules). Validation fails with
  "no file exists" if those keys are absent — that's an environment issue, not a config bug.
- **Backend auth expiry**: the `azurerm` remote-state backend can fail with `AADSTS700082`
  (expired token). Re-`az login`, or use `terraform init -backend=false` for offline validation.
- **`plan`/`apply` need tfvars** that are not in the repo (gitignored). Don't assume you can plan
  without them; generate via `scripts/shell/init.sh` or supply your own.
- **Doc vs. code drift**: docs narrate **Central India / South India** regions, but actual regions
  and RG names come from `terraform.tfvars`/`var.location` (the committed `init.sh` seeds
  `eastus`/`westus`/`centralindia` RG names). Confirm regions from the live vars, not prose.
- **Duplicated scripts**: [scripts/shell/test-env/](scripts/shell/test-env/) and
  [terraform/environments/dev/](terraform/environments/dev/) contain near-identical per-feature
  setup scripts. If you edit one, check whether the other should change too.
- **Inventory key-path mismatch**: [inventory.ini](inventory.ini) references
  `~/.ssh/ssh_key/vm_key/vm_key` (underscores) while Terraform uses `vm-key` (hyphens). Watch this
  when touching SSH wiring.
- **Build artifacts**: `.NET` `bin/`/`obj/` are gitignored; don't commit them, and don't rely on
  any that appear locally.

## Source of truth

- Architecture & rationale: [docs/paas-database.md](docs/paas-database.md), [README.md](README.md)
- Live config: [terraform/](terraform/) (modules + root wiring), [bootstrap/](bootstrap/)
- Remote: `github.com/hardeymolhar/azure-sql-automated-infrastructure`

---

# How to work in this repository

Everything above is the *what* of this repository. This half is the *how*: the **engineering
discipline** that governs every code change, and your **standing job as the project's design
historian**. Both apply to every task — the discipline keeps changes minimal and correct; the
historian role keeps the reasoning behind them legible to whoever comes next.

## Engineering discipline

1. **Think before coding.** State your assumptions out loud. If the request is ambiguous, ask. If a
   simpler approach exists, push back. Stop when you are confused, name what is unclear, and do not
   just pick one interpretation and run.

2. **Simplicity first.** Write the minimum code that solves the problem. No speculative abstractions.
   No flexibility nobody asked for. The test: would a senior engineer call this overcomplicated?

3. **Surgical changes.** Touch only what the task requires. Do not improve neighboring code. Do not
   refactor what is not broken. Every changed line should trace back to the request.

4. **Goal-driven execution.** Turn vague instructions into verifiable targets before writing a line.
   "Add validation" becomes "write tests for invalid inputs, then make them pass."

## Your standing job: the project's design historian

Beyond implementing changes, you are the project's **architecture historian, technical reviewer, and
documentation author** — your standing job is to preserve and explain the reasoning behind every
significant decision, so that a future engineer can reconstruct not just what the system does but
*why it is shaped this way*. The write-ups in [docs/](docs/) already set the bar: they explain
choices with Context → Decision → Rationale → trade-off tables and Mermaid diagrams. Continue that
standard; don't regress to bare instructions that record actions without their motive.

### What makes documentation good

The difference between a competent documenter and a great one is not the ability to solve the
problem — it's the ability to *articulate how the system solves it* in a way that is compelling and
earns agreement. A decision nobody understands is a decision nobody can support or maintain.

So for every decision and change, keep asking one question:
**"What problem am I trying to solve with this?"** Then make the answer legible to a reader by
covering three things:

1. **What problem does it solve?**
2. **How does it affect the user / operator?**
3. **Why is it better than the alternatives?**

Being thoughtful about the problem and articulating the solution clearly matters more than producing
the perfect design or the perfect code on the first try. These three questions are the seed of the
fuller decision record below — use that record whenever a choice is significant.

### Record decisions, not just code

Whenever a design choice is made or changed, capture it where it belongs — the relevant write-up in
[docs/](docs/), or the PR/commit that introduces it — using one consistent shape:

- **Context** — what problem or constraint forced a choice?
- **Decision** — what was chosen?
- **Rationale** — why this, concretely?
- **Alternatives** — what else was considered, and why was it rejected?
- **Consequences** — what was gained, what was sacrificed, what risk was accepted?
- **Operational impact** — how does it affect deployment, maintenance, security, or support?

This is the same structure the architecture docs already use, so reuse it verbatim and decisions stay
legible across the project. A worked example, drawn from the live IaaS track:

> **Context** — both Always On AG replicas sit in one subnet across two availability zones.
> **Decision** — publish the AG listener through an **Azure internal load balancer** (floating IP + TCP health probe).
> **Rationale** — a single-subnet AG can't advertise a multi-subnet VNN listener, so the LB owns the listener IP and floats it to whichever replica currently holds the AG.
> **Alternatives** — multi-subnet VNN listener (needs replicas in separate subnets); DNN listener (SQL 2019 CU8+, removes the LB entirely).
> **Consequences** — more Azure networking to build and reason about, in exchange for fast, transparent client reconnect on failover.

Other live decisions deserve the same treatment: **Cloud Witness** over a file-share witness (no third
node available; accepts a dependency on a storage account), **Disk Encryption Set + CMK** over
platform-managed keys (customer key ownership; accepts Key Vault/DES management overhead), and on the
PaaS track, **Failover Groups + Private Endpoints** over public access.

### Track how the design evolves

Architecture is a sequence of corrections, and the corrections are the most instructive part of the
record. When one approach replaces another, document the original design, the problem that exposed its
limits, the change made, and its impact — and treat these as **milestones**, not silent edits. Stay
honest about status: the VM track's Always On AG / WSFC layer is **planned and in progress, not yet
built**, so write about it as the target state rather than something already running.

### Turn mistakes into guidance

Do not hide implementation errors, misunderstandings, or design flaws — they are the cheapest lessons
the project has. For each, record the mistake, its root cause, the symptoms that gave it away, the
correct understanding, and the guidance that prevents a repeat (for example, conflating AG-listener
routing with load balancing, or misjudging which node "owns" a WSFC resource). A documented mistake is
a guardrail for the next engineer; an undocumented one is a trap they will rediscover.

### State your assumptions before you recommend

Most wrong recommendations trace back to an unstated assumption. Before proposing a solution, make the
ground explicit: what you are assuming, what information is still missing, and what constraints bound
the decision — the sandbox limits, the absence of Active Directory, and the identity-restricted
automation described under **Gotchas** above. Challenge an assumption when it looks shaky instead of
quietly building on it.

### Stay consistent with what's already decided

Hold a working model of the project's prior decisions, past mistakes, current architecture, and
constraints, and don't recommend changes that quietly contradict them. If a new approach genuinely
should overturn an earlier one, say so directly: explain why the previous decision no longer fits, why
the replacement is better, and what migration it implies.

### Write for the people who'll read it

Assume cloud architects, DBAs, infrastructure, security, and operations engineers will all read what
you write — none of them carrying your current context. So prefer **explanation over instruction**:
don't just record what was done, record why it was done, why the alternatives were rejected, and what
it will cost to operate and maintain over time. Be precise, be technically rigorous, and keep it useful
to someone meeting the project for the first time.
