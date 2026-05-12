# Design and Deployment of Secure Azure SQL PaaS with Cross-Region High Availability

![GitHub release](https://img.shields.io/github/v/release/hardeymolhar/azure-sql-automated-infrastructure)
![CI](https://github.com/hardeymolhar/azure-sql-automated-infrastructure/actions/workflows/ci.yml/badge.svg)
![Azure](https://img.shields.io/badge/Azure-SQL-blue)
![Terraform](https://img.shields.io/badge/Terraform-IaC-purple)
![Ansible](https://img.shields.io/badge/Ansible-Automation-red)
![Dotnet](https://img.shields.io/badge/.NET-8.0-512BD4)

## 🔴 Problem Overview

In banking and fintech payment systems, a database outage is not just a technical incident; it is a

- business interruption,
- a security concern,
- and a trust problem.

 A single-region SQL deployment with public access and manual recovery introduces three serious risks:
 
| Risk                | Description          | Business Impact             |
| ------------------- | -------------------- | --------------------------- |
| Downtime            | No high availability | Transactions stop           |
| Exposure            | Public endpoints     | Increased attack surface    |
| Operational Failure | Manual recovery      | Slow + error-prone recovery |


``` mermaid

flowchart TD
    A[Database Outage] --> B[Transactions Fail]
    A --> C[Service Downtime]
    A --> D[Manual Recovery Delay]

    B --> E[Revenue Loss]
    C --> F[Customer Frustration]
    D --> G[Operational Errors]

    F --> H[Loss of Trust]
    G --> H
    E --> H

```


## 🎯 Engineering Objective

Design and Deploy a secure, highly available Azure SQL platform that:

- meets RTO (15–30 min) and RPO (≤ 5 min) targets
- eliminates public exposure through private connectivity
- enables automated, cross-region failover


| Problem      | Solution               | Azure Feature     |
| ------------ | ---------------------- | ----------------- |
| Downtime     | Automatic failover     | Failover Groups   |
| Data Loss    | Continuous replication | Geo-replication   |
| Exposure     | Private access only    | Private Endpoints |
| Key Security | Encryption control     | Key Vault         |

```mermaid
flowchart LR
    A[Business Requirement: Low RTO/RPO] --> B[Failover Groups]
    A --> C[Geo-Replication]

    D[Security Requirement] --> E[Private Endpoints]
    D --> F[Key Vault]

    B --> G[High Availability]
    C --> G

    E --> H[Network Isolation]
    F --> I[Data Protection]
```

## User Impact

This diagram shows how key engineering decisions translate into measurable user and business outcomes.

``` mermaid
flowchart LR

    subgraph Engineering Decisions
        A1[Failover Groups]
        A2[Geo-Replication]
        A3[Private Endpoints]
        A4[Proxy Connection Policy]
        A5[Key Vault + CMK]
    end

    subgraph System Effects
        B1[Automatic Failover]
        B2[Data Replication]
        B3[Network Isolation]
        B4[Controlled Connectivity]
        B5[Data Encryption]
    end

    subgraph User Impact
        C1[Minimal Downtime]
        C2[No Data Loss]
        C3[Secure Transactions]
        C4[Consistent Access]
        C5[Regulatory Compliance]
    end

    A1 --> B1 --> C1
    A2 --> B2 --> C2
    A3 --> B3 --> C3
    A4 --> B4 --> C4
    A5 --> B5 --> C5
```

## 🏗️ System Architecture


``` mermaid
flowchart LR

    subgraph Client Layer
        P[Application VM]
    end

    subgraph Network Layer
        PE_SQL[Private Endpoint SQL]
        PE_KV[Private Endpoint Key Vault]
    end

    subgraph Security Layer
        KV[Key Vault]
    end

    subgraph Primary Region
        FG[Failover Group Endpoint]
        SQLP[SQL Primary]
    end

    subgraph Secondary Region
        SQLS[SQL Secondary]
    end

    subgraph Observability
        AM[Azure Monitor]
        LA[Log Analytics Workspace]
        WB[Workbooks and Alerts]
    end

    P --> PE_SQL
    P --> PE_KV

    PE_SQL --> FG
    FG --> SQLP
    SQLP -->|Geo Replication| SQLS

    SQLP -->|CMK| KV
    PE_KV --> KV

    P --> AM
    SQLP --> AM
    SQLS --> AM
    KV --> AM

    AM --> LA
    LA --> WB

```

## 🌍 Region Selection (RPO/RTO Driven)

| Role             | Region         |
|------------------|---------------|
| Primary          | Central India |
| Secondary        | South India   |

**Trade-off Consideration**

| Option                          | Impact                              |
|---------------------------------|-------------------------------------|
| Nearby regions (chosen)         | Better RPO, faster RTO              |
| Distant regions (e.g., India → Europe) | Higher latency → worse RPO |



##  🔌 Connection Policy Selection

| Policy   | Connectivity Model                  | Network Requirement              | Performance | Suitability for Banking Environment |
|----------|------------------------------------|----------------------------------|------------|-------------------------------------|
| Proxy ✅ | Gateway-only (port 1433)           | Minimal (single port)            | Lower      | ✅ Best fit (controlled, compliant)  |
| Redirect | Direct to database node            | Requires ports 11000–11999 open  | High       | ❌ Not suitable (breaks lockdown)    |
| Default  | Redirect → Proxy fallback          | Depends on environment           | Variable   | ⚠️ Unpredictable behavior           |

---

**Decision:**  
Proxy was intentionally selected to enforce **strict network control and deterministic connectivity**, ensuring alignment with real-world banking security constraints where dynamic port access is restricted.



## 🧪 Replication Strategy (Failover Groups / Geo-Replication)

This architecture intentionally combines Failover Groups and Active Geo-Replication within the same Azure SQL environment to evaluate their operational behavior and recovery characteristics.

The environment provisions 20 databases:

- 10 databases use Failover Groups for automated failover and managed replication  
- 10 databases use Active Geo-Replication with manually managed secondary databases  

This design enables direct comparison of failover behavior, recovery time, and operational complexity across both models.


## 🔐 Security and Encryption (Key Vault + CMK)

To meet security and compliance requirements, the architecture implements Transparent Data Encryption (TDE) using Customer-Managed Keys (CMK) stored in Azure Key Vault.

### Key Components

| Component | Role |
|----------|------|
| Azure SQL Server | Encrypts data at rest |
| Managed Identity | Authenticates SQL Server to Key Vault |
| Key Vault | Secure storage for encryption keys |
| Customer-Managed Key (CMK) | Used for TDE encryption |

---

### 🔑 Encryption Flow

```mermaid
flowchart LR
    SQL[Azure SQL Server] --> MI[Managed Identity]
    MI --> KV[Key Vault]
    KV --> KEY[Customer Managed Key]
    KEY --> SQL
```




#### 🔐 Security Controls

```mermaid
flowchart TD
    DB[Core Banking Tables] --> AE[Always Encrypted]
    DB --> DDM[Dynamic Data Masking]
    DB --> AUD[Auditing]
    DB --> DC[Data Classification]

    AE --> AE1[PAN / Card Number]
    AE --> AE2[Tokens / Sensitive IDs]

    DDM --> DDM1[Email]
    DDM --> DDM2[Phone]
    DDM --> DDM3[Partial PAN]

    AUD --> AUD1[INSERT Activity]
    AUD --> AUD2[SELECT Access]

    DC --> DC1[PII Data]
    DC --> DC2[Cardholder Data]
```



## SQL Database Auditing

![Auditing](docs/images/audit-logs.png)


---

## Data Classification

![Data Classification](docs/images/data-classification.png)

---

## Dynamic Data Masking Demonstration

Dynamic Data Masking (DDM) was applied to sensitive financial and identity-related columns to reduce unnecessary exposure of sensitive data to non-privileged users.

### Regular User View

The regular contained database user (`db_datareader`) can query the table, but masked columns such as account numbers, usernames, and operational secrets remain partially or fully obfuscated.

![Regular User View](docs/images/regular-user.png)

---

### Admin User View

Administrative users such as the Microsoft Entra administrator can view original unmasked values.

![Admin View](docs/images/admin.png)


## Always Encrypted Demonstration

This demonstration validates:

- Azure Key Vault integration
- Column Master Key (CMK) and Column Encryption Key (CEK) configuration
- client-side encryption using Powershell SqlClient

![Always Encrypted](docs/images/always-encrypted.png)

[![Watch Demo Video](https://img.shields.io/badge/Watch-Always_Encrypted_Demo-0078D4?style=for-the-badge&logo=microsoftazure)](docs/videos/always-encrypted.mp4)



## Workload Simulation and Validation

This phase introduces workload simulation to validate how the Azure SQL architecture behaves under realistic operational conditions.

Both Python and .NET implementations were evaluated during testing.

| Capability | Python (`pyodbc`) | .NET (`Microsoft.Data.SqlClient`) |
|---|---|---|
| Azure SQL Connectivity | ✅ | ✅ |
| Managed Identity Authentication | ✅ | ✅ |
| Batch Workloads | ✅ | ✅ |
| Always Encrypted Support | Limited | Full |
| Azure Key Vault CMK Integration | Limited | Native |
| Client-Side Decryption | Inconsistent | Fully Supported |


The .NET implementation became the primary workload engine because the official `Microsoft.Data.SqlClient` driver provides native support for:

- Always Encrypted
- Azure Key Vault integration
- Client-side encryption and decryption
- Deterministic and randomized encryption handling
- Secure inserts into encrypted columns


## .NET Workload Simulator

| Directory | Purpose |
|---|---|
| [`./scripts/dotnet/`](./scripts/dotnet/) | Always Encrypted validation and secure workload simulation |



## Python Workload Scripts

| Script | Purpose |
|---|---|
| [`./scripts/python/`](./scripts/python/) | Initial Deployment Using Python |

---




# Automation Workflow

Ansible will be used to automate the deployment process by configuring the Azure VM, installing required drivers and dependencies, and deploying the Python workload scripts automatically.

The workload simulator will then execute realistic database activities such as:

* Batch inserts for high-volume transaction ingestion
* Concurrent database operations to simulate multiple workloads
* Large updates and deletes to test transaction log and IO behavior


``` mermaid
flowchart LR

    A[Use Ansible to Configure Azure VM
    Install .NET 8 SDK • ODBC Drivers • SQL Tools]

    -->

    B[Deploy .NET Workload Scripts to the VM
    Automated Provisioning and Execution]

    -->

    C[Connect Securely to Azure SQL
    Using Managed Identity]

    -->

    D[Execute Realistic Database Workloads
    Batch Inserts • Concurrent Operations • Updates • Deletes]

    -->



    E[Collect Azure SQL Metrics and Logs
    DTU • CPU • Log IO • Data IO • Sessions]

    -->

    F[Analyze Database Performance,
    Scalability, and Security Impact]

```



<h2>Playbooks and Automation Files</h2>

<ul>
  <li><a href="./ansible/playbooks/">Ansible Playbooks Directory</a></li>
  <li><a href="./ansible/requirements.yml">Ansible Requirements File</a></li>
</ul>

<h2>Python Workload and Connectivity Scripts</h2>

<ul>
  <li>
    <a href="./scripts/python/managed-identity-connection.py">
      Establishing Connection Using Contained User With Managed Identity
    </a>
  </li>

  <li>
    <a href="./scripts/python/batch-inserts.py">
      Batch Insert Workload Script
    </a>
  </li>

  <li>
    <a href="./scripts/python/concurrency.py">
      Concurrency Workload Script
    </a>
  </li>
</ul>



![Ansible Deployment](docs/images/ansible-demo.png)

[![Watch Ansible Demo](https://img.shields.io/badge/Watch-Ansible_Demo-EE0000?style=for-the-badge&logo=ansible)](docs/videos/ansible-demo.mp4)







## Sandbox Constraints and Deployment Tradeoffs

This project was tested in the Whizlabs Azure sandbox environment.

The sandbox is:

- temporary
- dynamically provisioned
- identity restricted
- time limited

Because of these limitations, some engineering decisions were intentionally optimized for rapid deployment and testing rather than full production-style CI/CD automation.

---

## Key Constraint

The sandbox does not allow:

- RBAC Assignments to other identities
- Federated Identity (OIDC)
- Service Principal-based automation


This means GitHub Actions cannot securely authenticate to Azure for full infrastructure deployment.

---

## Deployment Decision

Because of the sandbox restrictions:

| Purpose | Approach Used |
|---|---|
| Infrastructure Deployment | Local Bash Orchestration |
| Azure Authentication | Local `az login` session |
| VM Configuration | Ansible |
| SQL Configuration | PowerShell |
| Workload Simulation | .NET |



---

## Rapid Deployment Workflow

```mermaid
flowchart LR

    A[Local Azure Login]

    -->

    B[Bash Deployment Orchestration]

    -->

    C[Azure Resource Deployment]

    -->

    D[Ansible VM Configuration]

    -->

    E[.NET Workload Execution]

    -->

    F[Azure SQL Stress Testing]