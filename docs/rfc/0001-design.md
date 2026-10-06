# RFC 0001: multi-region-failover design

- **Status:** Accepted (M1 implemented)
- **Author:** EquinoxWN
- **Created:** 2026

## Problem

A whole AWS region does go down now and then, and an application in one region goes down with
it. Running in a second region costs money, and a second region that is never exercised does not
work when it is needed: its configuration drifts, its database is behind or missing, and nobody
knows how long switching takes. This project builds a two-region setup whose standby is cheap but
always running, keeps both regions provably built the same way, and (in later milestones) measures
how long a failover takes and how much data it loses.

## Goals

- **M1 (this RFC):**
  - One Terraform module (`modules/regional_stack`) builds a complete region: VPC over two
    availability zones with public and private subnets and one NAT gateway, an HTTPS load balancer
    (TLS 1.3 policy, plain HTTP only redirects), the API on ECS Fargate in private subnets without
    public IPs, CloudWatch logs encrypted with the region's KMS key, and an Aurora PostgreSQL
    cluster reachable only from the API's security group.
  - The root module instantiates it twice: the primary (three tasks, a writer and a reader) and a
    warm standby (one task, one instance) in another region. An Aurora Global Database ties the two
    clusters together: the primary writes, the standby receives storage-level replication.
  - Input validation refuses configurations that would not fail over: the same region twice, a
    standby of zero (pilot light, not warm), a standby larger than the primary, overlapping VPC
    ranges, and images not pinned by digest.
  - `terraform test` plans and applies everything against mocked AWS providers (no account
    needed) and asserts the security and shape of both regions.
  - A Go checker parses the root module and fails if the two stacks differ in anything but the
    region's role; it also estimates each stack's fixed monthly cost from its sizing.
- **M2:** Route 53 health-check failover, a drill script that promotes the secondary cluster and
  scales the standby while k6 keeps sending traffic.
- **M3:** measured RTO and RPO from request logs, a runbook and a teardown, and the standby's cost
  from a real bill.

## Non-goals

- Active-active writes in both regions (conflict resolution is a different project).
- Deploying to a real AWS account in CI: M1 is verified offline; M3 runs the drill in a sandbox
  account and tears it down.

## Proposed design

```
                    Aurora Global Database (encrypted, deletion protection)
                   /                                        \
 us-east-1: module "primary"                     us-west-2: module "standby"
   VPC, 2 AZs, NAT gateway                         same module, same image digest
   ALB (HTTPS, TLS 1.3) -> Fargate x3              ALB (HTTPS, TLS 1.3) -> Fargate x1
   Aurora writer + reader (own KMS key)            Aurora secondary x1 (own KMS key),
   credentials in Secrets Manager                  replicates the primary, no credentials
```

- **Warm, not pilot light:** the standby runs one task and one database instance so a failover
  scales an already working stack instead of creating one; that costs about half of the primary's
  fixed price (see the results) and is the trade-off this project measures.
- **Failover-friendly lifecycle:** the cluster ignores changes to its global-cluster membership
  and replication source, because after a promotion AWS swaps the roles and Terraform must not
  undo that.
- **Least exposure:** only the load balancer is public; the database accepts connections only
  from the API's security group, uses IAM authentication, and the API runs with a read-only root
  filesystem. Each region's KMS key lets that region's CloudWatch Logs use it only for the stack's
  own log group.

## Alternatives considered

| Option | Why not (yet) |
|---|---|
| Backup and restore in the second region | Cheapest, but recovery takes hours; this project targets minutes. |
| Pilot light (database replica only, no compute) | Cheaper, but the first failover is also the first time the standby's compute runs. The validation refuses a standby of zero for that reason. |
| Active-active | Lowest RTO, but needs multi-region writes and conflict handling; out of scope. |
| Copy-pasted per-region Terraform | Drift is guaranteed; one module instantiated twice, plus a checker that rejects differences, keeps them identical. |
| Testing against a real AWS account in CI | Slow, costly and needs credentials in CI; mocked providers check the configuration's logic for free, and the drill (M2, M3) tests the real thing. |

## Measurement plan

- M1: `terraform test` assertions; parity check; fixed monthly cost estimate per stack.
- M2 and M3: RTO from the first failed request to the first success through the standby, RPO
  from writes acknowledged before the outage and missing afterwards, under k6 load.

## Milestones

- **M1 (done):** regional module, two-region root with Aurora Global Database, validation, mocked
  `terraform test`, parity checker and cost estimate.
- **M2:** Route 53 failover and the drill script.
- **M3:** measured RTO and RPO, runbook, teardown, real cost.

## Risks and open questions

- Mocked providers check Terraform's logic and the provider's argument validation, not AWS's
  behaviour; an apply in a real account can still fail (for example on service quotas). M3's
  drill covers that.
- The cost table holds list prices copied when it was written; prices change, so the estimate
  says which date it uses and that usage-based charges are excluded.
- Aurora Global Database replication lag is usually under a second but not guaranteed; RPO is
  measured in M3 rather than assumed.
