# SQL Server Failover Cluster Instance on a Workgroup Cluster: 

> **Status — superseded (2026-07-02).** This document records the project's
> *original* Active Directory–detached (workgroup) design. The IaaS track has since
> been re-based onto a **domain-based** architecture: a dedicated Windows Server
> 2022 Domain Controller (AD DS + DNS) is now a first-class dependency, and the
> WSFC + Always On AG use Kerberos/domain trust instead of workgroup certificates.
> This file is kept as the historical baseline; see
> [02_Active_Directory_Migration.md](02_Active_Directory_Migration.md) for the
> decision record, rationale, and the new deployment sequence.

### What this project is

The project is a self-contained, reproducible lab that mirrors an enterprise high-availability SQL Server deployment while deliberately removing one of its most common dependencies: a Windows Active Directory domain. The entire environment runs on Azure Virtual Machines using Windows Server 2022 and a supported edition of SQL Server, and it targets the same clustering concepts a production DBA must understand — quorum, cluster resources, health probing, shared storage, and transparent client failover.


### Why an Active Directory–detached workgroup cluster

Windows Server 2016 introduced support for **workgroup clusters** (also called Active Directory–detached or multi-domain clusters), which form a WSFC without requiring all nodes to belong to the same Active Directory domain. This project adopts that model for three reasons: 

it **reduces infrastructure dependencies** to the cluster and database tiers; 
it **exposes the mechanics** the domain would otherwise hide, by forcing certificate-based authentication and locally managed, identical service accounts across nodes; and it **fits constrained lab environments** where a domain cannot be assumed. 

The trade-off is accepted deliberately: a workgroup cluster forgoes Kerberos-based domain authentication and centralized identity management, which is acceptable for a learning environment but is a factor to weigh carefully before adopting the pattern in production.

