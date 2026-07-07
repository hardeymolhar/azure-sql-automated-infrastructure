# Milestone: Making Active Directory a First-Class Dependency

> Supersedes the workgroup-cluster design in
> [01_Objective_and_Overview.md](01_Objective_and_Overview.md).

## Context

The original lab (see doc 01) deliberately built the Windows SQL HA tier as an
**Active Directory–detached workgroup cluster** to minimise dependencies and expose
clustering mechanics. That model works, but it forgoes Kerberos, centralized identity,
and — most importantly for SQL Server HA — it forces **manual, per-node certificate
exchange** to establish cross-node trust for the HADR (database-mirroring) endpoints,
which is fiddly and error-prone to automate.

The project is now evolving toward an enterprise-representative **domain-based** SQL
Server 2022 clustered architecture. Active Directory must therefore become a
**first-class dependency** of the deployment pipeline — not a Domain Controller bolted
onto the existing flow, but a properly sequenced stage that every dependent stage waits
on.

Two facts about the *existing* infrastructure shaped this change:

1. The two Windows nodes (`ms-*` in Zone 1, `cs-*` in Zone 2) each own **separate**
   encrypted disks and are fronted by an **internal load balancer** listener using
   **HADR endpoints** — i.e. this is **Always On Availability Groups on a WSFC**, not a
   shared-storage Failover Cluster Instance.
2. The WSFC itself was never automated (the feature-install tasks were commented out and
   no `New-Cluster` existed), so the cluster tier was effectively unbuilt.

## Decision

- **Keep the Always On AG topology** (per-node disks + ILB listener + HADR endpoints)
  and place a **domain-joined WSFC** underneath it. No shared storage is introduced.
- **Introduce a dedicated Windows Server 2022 Domain Controller** (AD DS + DNS) in its
  own subnet + NSG with a **static private IP**.
- **Create a new, distinct AD domain** (`AD_DOMAIN_NAME`, default `sqlfci.local`) and
  **keep** the existing Azure Private DNS zone `corp.internal`. The DC's AD-integrated
  DNS is authoritative for the AD zone and **forwards to Azure's recursive resolver
  `168.63.129.16`**, which also resolves the VNet-linked `corp.internal` — so both zones
  resolve with no split-brain.
- **Single DC** for the sandbox (accepted single point of failure).
- **Cloud Witness** quorum on the existing Standard/LRS storage account (Microsoft's
  recommended quorum for AGs on Azure VMs; a disk witness would require Azure shared
  disks the AG design intentionally avoids).

## Rationale

- **Minimal architectural change.** The AG data path, zonal HA, disk layout, ILB
  listener, and naming/variable model are all preserved; only the trust substrate
  changes from workgroup certificates to domain Kerberos. Microsoft fully supports
  Always On AGs against an existing AD.
- **Kerberos removes the manual cert dance.** With both nodes domain-joined and the
  WSFC domain-based, the HADR endpoints authenticate via Kerberos automatically — the
  workgroup certificate exchange is deleted, not re-implemented.
- **Distinct AD domain + kept Private DNS zone avoids split-brain.** Reusing
  `corp.internal` as the AD zone would put AD-integrated DNS and Azure Private DNS in
  contention over the same name. A separate AD domain sidesteps that while the DC's
  forwarder keeps `corp.internal` (listener/CNO records) resolvable.
- **NIC-level DNS is the supported path.** Microsoft states the preferred DNS server
  should be set at the Azure NIC/VNet level, not inside the guest, so it survives
  reboots and DHCP. The pipeline sets it on the NICs; the playbook still performs the
  in-guest flush/register, all locator-record verification, and the domain join.

## Alternatives considered

| Alternative | Why rejected |
|---|---|
| True shared-storage **FCI** (`/Action=InstallFailoverCluster`, Azure shared disks, single zone) | Major rewrite; discards the cross-zone HA design and the per-node disk + ILB model. |
| Reuse `corp.internal` as the **AD domain**, retire the Private DNS zone | Cleaner in isolation, but the user chose to keep the Private DNS zone; a distinct AD domain avoids split-brain either way. |
| Set preferred DNS **in-guest only** | Works but is discouraged by Microsoft (DHCP/maintainability); NIC-level is authoritative, with in-guest kept as a verified safety net. |
| **Two DCs** for AD/DNS HA | Doubles VM/quota use in a temporary sandbox; single DC accepted as a documented lab trade-off. |
| **Disk witness** quorum | Requires Azure shared disks — contrary to the AG (non-shared) storage model. |

## Consequences

- **Gained:** enterprise-representative Kerberos identity; automated, cert-free HADR
  trust; a fully automated, dependency-ordered clustering tier that was previously
  manual.
- **Sacrificed / risk accepted:** one more VM to run and patch; the single DC is a SPOF;
  `sqlfci.local` uses a `.local` suffix (fine for a lab, overridable via `env.conf`).
- **Colloquial naming:** the folder says "FCI"; the built artifact remains Always On AG
  on a WSFC. The distinction is called out so a future reader isn't misled.

## Operational impact

- **New deployment sequence** (Bash orchestration unchanged in spirit; `dc-vm.sh` added
  to `db-deploy.sh`, playbook order updated in `vm-config.sh`):

  ```
  Generate Inventory (adds a [domain_controller] group)
   1. configure-domain-controller.yml   (AD DS + DNS + new forest)
   2. dbdrive-configuration.yml          (RHEL disks)
   3. vm-pkg.yml                         (RHEL packages)
   4. windows-dbdrive-configuration.yml  (Windows disks + DNS + domain join)
   5. configure-wsfc.yml                 (WSFC + Cloud Witness quorum)
   6. sql-server-on-rhel.yml             (SQL on RHEL)
   7. sql-server-on-windows.yml          (SQL + Always On/HADR; assumes AD/DNS/join/WSFC)
  ```

- **DNS design (split-brain-free):**

  ```
  SQL nodes ── DNS ──▶ Domain Controller (authoritative: sqlfci.local)
                              │ forwarder
                              ▼
                       168.63.129.16  (Azure recursive resolver)
                              │
                              ├─▶ corp.internal  (VNet-linked Azure Private DNS)
                              └─▶ public names
  ```

- **New infrastructure:** DC subnet `10.10.4.0/24`, NSG `nsg-dc-*` (AD DS/DNS ports from
  the VNet; RDP/WinRM from the operator IP), DC NIC static IP `10.10.4.4`, VM `dc-*`
  (`Standard_B2ms`, Windows Server 2022).
- **New variables** live in `scripts/shell/test-env/env.conf` (`DC_*`, `AD_*`,
  `AZURE_DNS_RESOLVER`, `WITNESS_STORAGE_ACCOUNT`); nothing is hardcoded in the scripts
  or playbooks.
- **New collection dependency:** `microsoft.ad` (forest promotion + domain join).
- **Idempotency:** every stage is safe to re-run — DC promotion, domain join, cluster
  creation, and quorum all skip when already in the desired state; prerequisite/validation
  failures abort the run rather than proceeding.

## Ownership map (single responsibility per stage)

| Stage | Owns |
|---|---|
| `network.sh` / `dc-vm.sh` | DC subnet, NSG, static-IP NIC, NIC-level DNS, DC VM + WinRM |
| `configure-domain-controller.yml` | AD DS + DNS roles, forest promotion, DNS forwarder, AD/DNS verification |
| `windows-dbdrive-configuration.yml` | (existing disks) **+** node DNS, locator-record verification, domain join |
| `configure-wsfc.yml` | Failover-Clustering feature, `Test-Cluster`, `New-Cluster`, Cloud Witness, health checks |
| `sql-server-on-windows.yml` | SQL engine/FCI-AG install, SSMS, config, Always On/HADR — **no clustering** |
