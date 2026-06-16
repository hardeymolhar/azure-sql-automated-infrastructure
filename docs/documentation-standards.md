# Documentation & Decision-Communication Standards

How we write down and justify decisions on this Azure SQL platform. The principles are
adapted from Tom Greever's *Articulating Design Decisions* (O'Reilly, 2nd ed.) — a book about
a designer getting **support** from non-designer stakeholders in a meeting. Swap "designer" for
**architect/DBA/SRE** and "stakeholder" for **security, operations, leadership, and auditors**,
and the same playbook applies to infrastructure: our diagrams, Terraform modules, and Ansible
playbooks don't speak for themselves, so we have to explain *why they are shaped this way* in a
form that survives long after the conversation.

This is the detailed companion to the **"Working as the project's design historian"** section of
[CLAUDE.md](../CLAUDE.md), and it codifies the bar the write-ups in this folder already set
(Context → Decision → Rationale → trade-off tables → Mermaid). The audience for everything we
write is the same audience the book names: **cloud architects, DBAs, infrastructure engineers,
security engineers, and operations** — none of them carrying the author's context.

---

## The translation at a glance

| Book principle (chapter) | Our documentation standard |
|---|---|
| The **Big Three** questions (Ch 1) | Every significant decision answers: problem solved, effect on operators/workload, why better than alternatives |
| The **IDEAL Response** (Ch 8) | The canonical **decision record** template (Identify · Describe · Empathize · Appeal · Lock in) |
| Convert **"likes" → "works"** (Ch 4) | Justify against requirements/SLOs/threat model/cost — never "I prefer" |
| **Include the *why*** (Ch 4) | Record *what* **and** *why*; a decision without its rationale has no future value |
| **Appeal to a nobler motive** (Ch 6) + Parkinson's Law of Triviality (Ch 10) | Tie every decision to the platform goals (RTO/RPO, no public surface, CMK); keep them front-and-center to stop bike-shedding |
| **Represent the user** (Ch 6) | The "user" is the on-call DBA, the auditor, and the banking workload — write for *their* pain |
| **Demonstrate effectiveness / show a comparison** (Ch 6) | Show, don't tell: Mermaid diagrams + before/after + side-by-side trade-off tables |
| **Give them a choice / the Rubik's cube** (Ch 6) | State the trade-off explicitly — every infra change moves another face of the cube |
| **Good-notes attributes** (Ch 4) | The documentation quality bar (accessible · organized · specific · definitive · actionable · referenced · forward-looking) |
| **Set the context** (Ch 3) | Every doc/record opens with scope, status, lifecycle stage, and related decisions |
| **Architectural evolution as milestones** (Ch 10) | Supersede, don't silently overwrite; record original → why insufficient → change → impact |
| **When you're wrong** (Ch 10) | Honest post-mortems: mistake · root cause · symptoms · correct understanding · prevention |
| **Avoid jargon / shared vocabulary** (Ch 4–5) | Define WSFC/AG/DES/CMK/TDE on first use; keep a glossary |
| **Manage expectations** (Ch 10) | State what is **built** vs **planned** and the known limitations — honestly |
| **Follow up fast / bank account of trust** (Ch 9–10) | Decisions live in the repo, not in chat; consistency is what earns trust |

---

## 1. Answer the "Big Three" for every significant decision

The book's foundation is three questions a designer must answer about any choice. Translated to
this platform, every infrastructure decision should answer:

1. **What problem or risk does it solve?** — tie it to a real failure mode (zone outage, public
   exposure, key compromise, data loss) or requirement.
2. **How does it affect the people who run and depend on it?** — the on-call DBA, the security
   reviewer, the auditor, and the banking workload itself. (The book's *"how does it affect the
   user?"*)
3. **Why is it better than the alternatives?** — what else was considered, and why was it rejected.

If you can't answer all three, the decision isn't ready to document or merge.

## 2. The decision record — our IDEAL template

The book's **IDEAL Response** is the shape every significant decision write-up should take. It
subsumes the Context/Decision/Rationale/Alternatives/Consequences structure already referenced in
[CLAUDE.md](../CLAUDE.md). Put these in the relevant `docs/` write-up, an ADR, or the PR/commit
that introduces the change:

```
## ADR-NNN: <short title>            <!-- e.g. ADR-007: AG listener via internal load balancer -->
Status:   Proposed | Accepted | Superseded by ADR-MMM
Date:     YYYY-MM-DD        Audience: architects · DBAs · security · ops
Track:    PaaS | IaaS       Related: ADR-NNN, docs/<file>.md

**Identify the problem**   — what risk/constraint forces a choice?
**Describe the solution**  — what we chose, concretely (resource, module, setting).
**Empathize with the operator/user** — how it helps the DBA/auditor/workload; what it costs them.
**Appeal to the platform goals** — which goal it serves (RTO 15–30 min, RPO ≤ 5 min, no public
                                    surface, CMK ownership, cost ceiling).
**Alternatives & trade-off** — what else was considered and what we sacrificed by choosing this.
**Lock in agreement**      — who approved, and the explicit decision (not "we discussed it").
**Operational impact**     — effect on deploy, runbooks, monitoring, on-call, and break-glass.
```

The "Lock in agreement" line matters: the book's whole thesis is that *forward momentum, not
consensus* is the goal — a record that ends without a stated, approved decision invites the same
debate next quarter.

## 3. Write about what *works*, not what you *like*

The single most-cited idea in the book: move stakeholders from preference ("I like…") to
effectiveness ("…works because…"). For infrastructure this means **every claim is anchored to a
requirement, SLO, threat model, or cost** — never taste.

- ❌ "We use an internal load balancer for the listener." (assertion)
- ✅ "A single-subnet Always On AG can't advertise a multi-subnet VNN listener, so an **internal
  load balancer** publishes the floating listener IP (`10.10.1.200`) and a TCP probe on `59999`
  tells the LB which replica owns the AG." (effectiveness — see
  [sql-server-on-vms-architecture.md](sql-server-on-vms-architecture.md))

If a reviewer's only objection is preference, the doc has done its job; if your only justification
is preference, it hasn't.

## 4. Always include the *why* — it is load-bearing

The book calls the missing *why* the biggest gap in design notes. In infra it is worse: a setting
recorded without its reason gets "cleaned up" by the next engineer and breaks production. Record
**what and why**, in one line each, especially for non-obvious choices:

- `allocation_unit_size = 65536` — **64 KB matches SQL Server's extent (8 × 8 KB pages)** so I/O
  aligns to the NTFS cluster.
- `SQLSVCACCOUNT = NT AUTHORITY\System` — sandbox simplification; **must change to a domain or
  certificate-based account** before Always On AG endpoints (cross-node auth) — see ADR for the
  HADR track.
- `force_wipe: false` — safety latch so re-runs **never reformat existing data** by accident.
- **Cloud Witness** over a file-share witness — no third node available; accepts a dependency on a
  storage account.

When someone asks "why did we do it this way?" months later, the answer must already be in the
repo.

## 5. Appeal to the goal, not the gadget

The book's "appeal to a nobler motive" — connect every decision to an agreed metric — is our
defense against **Parkinson's Law of Triviality** (bike-shedding on the easy-to-grasp detail while
the real risk goes undiscussed). Keep the platform's goals at the top of every design conversation
and write-up:

> **HA/DR** RTO 15–30 min, RPO ≤ 5 min · **No public exposure** (Private Endpoints, proxy/1433) ·
> **Data protection** TDE+CMK, Always Encrypted, DDM, auditing, classification · **Identity**
> Managed Identity + Entra ID.

If a discussion is stuck on whether a probe interval should be 5 s or 10 s while the witness/quorum
design is undecided, name the goal and defer the trivial item to a backlog — exactly the book's
"postpone the decision" tactic.

## 6. Show, don't tell

"Talk is cheap; a picture is worth a thousand words." Continue the repo's existing practice:

- **Mermaid diagrams** for topology and flow (the architecture docs already do this — keep the
  style).
- **Side-by-side / before-after** when proposing a change, so reviewers see the difference instead
  of imagining it.
- **Trade-off tables** with a "why" column — e.g. the LRS-per-zone vs ZRS table in
  [sql-server-on-vms-architecture.md](sql-server-on-vms-architecture.md), or the disk host-caching
  table.

## 7. State the trade-off explicitly (the Rubik's cube)

Every infra decision turns another face of the cube — cost, blast radius, latency, operational
load, security. The book insists we make the sacrifice visible so stakeholders choose with full
information. Always pair the decision with what it costs:

- **DES + CMK** over platform-managed keys → customer key ownership, **at the cost of** Key Vault /
  DES lifecycle management.
- **LRS zonal disks** over ZRS → cheaper and zone-pinned to the VM, **at the cost of** relying on
  AG replication (not the storage layer) for cross-zone durability.
- **Certificate-based HADR endpoints** over a domain → works in a no-AD sandbox, **at the cost of**
  certificate rotation and trust management.

## 8. The documentation quality bar

The book's seven attributes of good meeting notes are a precise checklist for our docs, ADRs, and
PR descriptions:

| Attribute | What it means here |
|---|---|
| **Accessible** | Lives in the repo (`docs/`, ADRs, PR/commit), linkable, not in chat or a DM |
| **Organized** | Scoped to one concern; ties to the specific module/resource/playbook |
| **Specific** | Names resources, settings, LUNs, ports, modules — and *who* decided |
| **Definitive** | Marks the decision clearly (`Status: Accepted`); open items flagged with `(?)` |
| **Actionable** | Has an owner and a next step, not just an observation |
| **Referenced** | Links the Terraform/Ansible/script, the Azure doc, and related ADRs |
| **Forward-looking** | Notes what's deferred to the next phase (e.g. the AG/WSFC build) |

## 9. Set the context up front

Mirror the book's "Set the Context" in every document header: **goal, where we are in the
lifecycle, status, audience, and related decisions.** A reader (or a future agent) should know in
ten seconds whether a doc describes the target state, the built state, or a proposal — and which
track (PaaS vs IaaS) it belongs to.

## 10. Track evolution as milestones — supersede, don't overwrite

The book treats replaced approaches as the most instructive part of the record. When a decision
changes, **don't silently edit history** — record the original design, the problem that exposed its
limits, the change, and the impact, and mark the old record `Superseded by ADR-NNN`. Be honest
about status: the VM track's **Always On AG / WSFC layer is planned and in progress, not yet
built**, so write about it as the target state, not as something running. (Illustrative milestones
worth this treatment: DNN-vs-internal-LB listener choice; standalone instance → AG; public access →
Private Endpoints.)

## 11. Document mistakes honestly

The book's counterintuitive lesson — admitting you were wrong *builds* trust — becomes our
post-mortem standard. When something breaks or a design proves wrong, record: **the mistake, its
root cause, the symptoms, the corrected understanding, and the preventive guidance.** Focus on the
fix, not blame. Examples of the kind of error worth a lessons-learned note: conflating AG-listener
routing with load balancing, or misjudging which node "owns" a WSFC resource. A documented mistake
is a guardrail; an undocumented one is a trap the next engineer re-discovers.

## 12. Write for the audience; kill unexplained jargon

Define acronyms on first use and keep a running glossary (WSFC, AG, FCI, DES, CMK, TDE, DDM, ILB,
DNN, RTO, RPO). The book warns that jargon alienates stakeholders and breaks the shared vocabulary
you need for agreement — and our audience spans security and operations engineers who don't live in
the SQL HADR world day-to-day.

## 13. Manage expectations: built vs planned, and known limits

Every architecture doc and ADR states **what is implemented, what is planned, and the known
limitations** (e.g. sandbox constraints: no Active Directory, no service-principal automation, HTTP
WinRM, Developer edition). The book's "manage expectations" is the difference between a project that
loses stakeholder trust and one that keeps it: never let a doc imply something is delivered when it
isn't.

## 14. Keep the record durable and searchable

Decisions belong in the repo — `docs/`, ADRs, PR descriptions, and commit messages — not in
meeting memory or chat threads. The book's "follow up fast" and "bank account of trust" both reduce
to one infra habit: **a searchable, consistent written record.** It lets a new engineer reconstruct
*why* without re-litigating, and consistency over time is precisely what earns the latitude to make
calls without every decision being second-guessed. Keep it concise — filter the cruft; a record
buried in noise is as good as no record.

---

## Quick reference — before you merge or close a decision

- [ ] Answers the **Big Three** (problem · effect on operators/workload · why over alternatives).
- [ ] Justified by a requirement/SLO/threat-model/cost — **"works," not "likes."**
- [ ] Includes the **why** for every non-obvious setting.
- [ ] Connected to a **platform goal** (RTO/RPO, no public surface, CMK, identity).
- [ ] States the **trade-off** (what it costs / what it sacrifices).
- [ ] Has a **diagram, comparison, or trade-off table** where it aids understanding.
- [ ] Meets the **quality bar** (accessible · organized · specific · definitive · actionable ·
      referenced · forward-looking).
- [ ] Marks **status** and supersedes prior records instead of overwriting them.
- [ ] Honest about **built vs planned** and **known limitations**.

## Worked example (the IDEAL template applied)

> **ADR-007: Publish the Always On AG listener through an Azure internal load balancer**
> **Status:** Accepted · **Track:** IaaS · **Audience:** architects · DBAs · network · ops
>
> **Identify the problem** — Both AG replicas live in one subnet across two availability zones; we
> need a single, stable client endpoint that survives a zone loss.
> **Describe the solution** — A Standard, internal, zone-redundant load balancer owns the floating
> listener IP (`10.10.1.200`) with a TCP health probe on `59999`; only the replica currently
> holding the AG answers.
> **Empathize with the operator/user** — Clients reconnect transparently on failover; the on-call
> DBA isn't paged to repoint connection strings.
> **Appeal to the platform goals** — Serves the HA target (survive a zone loss) with a single
> listener endpoint.
> **Alternatives & trade-off** — Multi-subnet VNN listener (needs replicas in separate subnets);
> DNN listener (SQL 2019 CU8+, removes the LB entirely). Chosen approach adds Azure networking to
> build and reason about, in exchange for fast, transparent client reconnect.
> **Lock in agreement** — Approved by network + DBA leads; the LB and probe/NSG rules are owned by
> `scripts/shell/test-env/load-balancer.sh`.
> **Operational impact** — Two NSG rules (`AzureLoadBalancer` + `VirtualNetwork` → 1433/59999)
> resolved against whichever NSG is attached to each node's NIC; the listener silently fails if the
> probe port is blocked, so add it to monitoring.
