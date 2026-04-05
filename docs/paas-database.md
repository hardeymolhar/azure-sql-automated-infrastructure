# Design and Deployment of Secure Azure SQL PaaS with Private Endpoints, Customer-Managed Keys, and Cross-Region High Availability


## Problem OverView

1. What problem does it solve
Core Problem (Banking/Fintech Context)

Your architecture solves three high-risk failure domains:

1. Availability Risk
Single-region database → downtime = financial loss
Your solution:
Failover Groups → automatic regional failover
Geo-replication → per-database redundancy
2. Security Risk
Public SQL endpoints → attack surface
Microsoft-managed keys → no control over encryption lifecycle

Your solution:

Private Endpoints → zero public exposure
Key Vault (CMK) → full control over encryption keys
3. Operational Risk
Manual failover and key handling
Inconsistent database replication

Your solution:

Automated failover policy (with grace period)
Centralized key lifecycle + identity-based access


## Stack vs Core Features

| Stack | Core Features |
|------|--------------|
| Azure SQL | Failover Groups (multi-DB HA), Geo-replication (selective DB HA) |
| Terraform | Infrastructure as Code (repeatable deployment), Dependency orchestration (ordered deployment) |
| Key Vault | Customer Managed Key -based Transparent Data Encryption, Key rotation policies (lifecycle management) |
| Private Endpoints | Private-only access (no public endpoints), Network isolation (VNet-restricted access) |

