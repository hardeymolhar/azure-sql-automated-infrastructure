# Design and Deployment of Secure Azure SQL PaaS with Private Endpoints, Customer-Managed Keys, and Cross-Region High Availability


## Problem OverView

In banking and fintech, a database outage is not just a technical incident; it is a business interruption, a security concern, and a trust problem. A single-region SQL deployment with public access and manual recovery may work in a test environment, but in production it creates three serious risks:
downtime,
exposure,
and operational failure.

 When the database goes down, transactions stop. When access is public, the attack surface grows. When recovery depends on manual action, mistakes become expensive.

This project removes those risks by combining Failover Groups, Geo-replication, Private Endpoints, and Key Vault-managed encryption. The result is a database platform designed for continuity, security, and controlled recovery rather than hope and manual intervention.




## Stack vs Core Features

| Stack | Core Features |
|------|--------------|
| Azure SQL | Failover Groups (multi-DB HA), Geo-replication (selective DB HA) |
| Terraform | Infrastructure as Code (repeatable deployment), Dependency orchestration (ordered deployment) |
| Key Vault | Customer Managed Key based Transparent Data Encryption, Key rotation policies (lifecycle management) |
| Private Endpoints | Private-only access (no public endpoints), Network isolation (VNet-restricted access) |

