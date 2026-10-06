# ADR 0002: A warm standby built from the same module, joined by an Aurora Global Database

- **Status:** Accepted

## Context

The second region can be cold (backups only), pilot light (data replicated, no compute), warm
(everything running at minimal size) or hot (full size, maybe active-active). Each step up costs
more and fails over faster and more reliably. The database is the hard part: application servers
can be started in minutes, data cannot be copied in minutes.

## Decision

Run a warm standby: the same Terraform module as the primary with smaller sizing (one Fargate task,
one Aurora instance), in a different region, with its Aurora cluster joined to the primary's
through an Aurora Global Database. Validation refuses a standby with zero tasks or instances, a
standby larger than the primary, and both stacks in one region.

## Consequences

- At failover the database is already in the region with recent data, and the API is already
  serving health checks there; the drill only has to promote the cluster, scale the service and
  move DNS.
- The standby's fixed cost is about 54% of the primary's with the default sizing (estimate from
  list prices), mostly the one Aurora instance; it is the price of not starting from zero.
- Encryption keys are per region (each cluster and log group uses its own KMS key), so losing a
  region does not lose the key the standby needs.
