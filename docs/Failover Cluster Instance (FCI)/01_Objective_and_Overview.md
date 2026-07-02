# SQL Server Failover Cluster Instance on a Workgroup Cluster: Objective and Overview

This document introduces a lab project that designs and deploys a highly available **SQL Server Failover Cluster Instance (FCI)** on **Windows Server 2022** Azure Virtual Machines, built on top of an **Active Directory–detached Windows Server Failover Cluster (Workgroup Cluster)**. It establishes the purpose, scope, and reasoning behind the project so that readers understand *why* the environment is shaped the way it is before proceeding to the implementation chapters. It is an orientation document, not an installation guide.

## Objective

The objective of this project is to build a functioning SQL Server FCI in an environment where **Active Directory Domain Services (AD DS) are intentionally omitted**, and to use that constraint as a means of studying the internal mechanics of Windows Server Failover Clustering.

By the end of the series, a reader will be able to:

- Explain the relationship between a **Windows Server Failover Cluster (WSFC)**, its **cluster resources**, and the **SQL Server FCI** that depends on them.
- Describe how a cluster establishes node membership, quorum, and shared identity **without a domain controller**, and how a workgroup cluster differs from a domain-joined cluster.
- Provision the supporting Azure infrastructure — virtual machines, networking, and shared or replicated storage — required for an FCI on infrastructure-as-a-service (IaaS).
- Configure certificate-based authentication and consistent local identities across nodes to replace the trust relationships an Active Directory domain would normally provide.
- Reason about the failover behavior of an FCI, including how client connections reconnect after a node fails, and where an **Azure Internal Load Balancer** fits into publishing the clustered SQL Server network name.
- Evaluate the **trade-offs** of a workgroup cluster relative to a traditional AD-integrated deployment, and identify which decisions are lab-appropriate versus production-appropriate.

The emphasis throughout is on **architecture and comprehension** rather than command sequences. Each component is introduced with the problem it solves, the alternatives that were considered, and the consequences of the choice, so that readers can transfer the reasoning to their own environments rather than reproducing a fixed set of steps.

## Project Overview

### What this project is

The project is a self-contained, reproducible lab that mirrors an enterprise high-availability SQL Server deployment while deliberately removing one of its most common dependencies: a Windows Active Directory domain. The entire environment runs on Azure Virtual Machines using Windows Server 2022 and a supported edition of SQL Server, and it targets the same clustering concepts a production DBA must understand — quorum, cluster resources, health probing, shared storage, and transparent client failover.

### Why it was created

Most published guidance for SQL Server FCIs assumes an existing Active Directory domain, because AD DS traditionally supplies the machine trust, computer accounts, and DNS that a cluster relies on. That assumption obscures *what the domain is actually providing* and makes the cluster harder to study in isolation. This project was created to make those responsibilities explicit. By removing the domain, each service the domain would normally deliver — authentication, name resolution, and a shared security context — must be provided deliberately, which turns an implicit dependency into a visible, teachable design decision.

### The problem it addresses

Building a full AD DS environment purely to learn clustering adds cost, provisioning time, and moving parts that are unrelated to the clustering concepts themselves. In an identity-restricted or short-lived lab — such as an Azure sandbox subscription — standing up domain controllers may be impractical or unavailable. The **workgroup cluster** removes that barrier: it allows a WSFC and a SQL Server FCI to be assembled with fewer infrastructure dependencies, so the learner can focus on the cluster and database layers directly.

### Why an Active Directory–detached workgroup cluster

Windows Server 2016 introduced support for **workgroup clusters** (also called Active Directory–detached or multi-domain clusters), which form a WSFC without requiring all nodes to belong to the same Active Directory domain. This project adopts that model for three reasons: it **reduces infrastructure dependencies** to the cluster and database tiers; it **exposes the mechanics** the domain would otherwise hide, by forcing certificate-based authentication and locally managed, identical service accounts across nodes; and it **fits constrained lab environments** where a domain cannot be assumed. The trade-off is accepted deliberately: a workgroup cluster forgoes Kerberos-based domain authentication and centralized identity management, which is acceptable for a learning environment but is a factor to weigh carefully before adopting the pattern in production.

### Why SQL Server FCI is the focus

A Failover Cluster Instance provides **instance-level high availability**: the entire SQL Server instance — its databases, logins, SQL Agent jobs, and configuration — fails over as a unit between cluster nodes, presenting a single virtual network name to clients. This makes the FCI the clearest lens for studying how SQL Server integrates with the underlying WSFC, because the database engine is registered directly as a cluster resource and its availability is governed by cluster health. It contrasts usefully with **Always On availability groups**, which provide database-level protection and do not require shared storage; understanding the FCI first gives readers the foundation to reason about that distinction later.

### Who this project is for

This material is written for **SQL Server DBAs, infrastructure and cloud engineers, and Microsoft DP-300 certification candidates** who want a rigorous, production-inspired understanding of SQL Server high availability on Azure IaaS. It assumes familiarity with SQL Server administration and basic Azure networking, but it does not assume prior experience building failover clusters. Although the deployment is performed in a lab, every architectural decision is aligned with Microsoft best practices where applicable, so that the concepts learned here remain valid when carried into a domain-joined, production-grade environment.
