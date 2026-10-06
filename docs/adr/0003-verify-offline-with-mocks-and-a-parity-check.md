# ADR 0003: Verify the infrastructure offline: mocked terraform test plus a parity checker

- **Status:** Accepted

## Context

The configuration must be checked on every change, but applying it to AWS takes tens of minutes,
costs money and needs cloud credentials in CI. `terraform validate` only checks syntax and types.
The failure this design fears most, the two regions slowly drifting apart, is not visible in
either region alone.

## Decision

- Use `terraform test` with `mock_provider` for both regions: the whole root module is planned and
  applied with fake AWS responses (realistic ARNs, so the provider's own argument validation still
  runs), and assertions check both regions' outputs: same zones, image, engine version and TLS
  policy; warm sizing; one encrypted, deletion-protected global database with credentials only in
  the primary; nothing private reachable from the internet. Five more runs check that invalid
  inputs are refused.
- Add a Go checker that parses the root module with HashiCorp's HCL library and compares the two
  module calls attribute by attribute: after replacing the role word they must be identical, each
  side may only refer to its own role, and the role values must be right.

## Consequences

- Every check runs in seconds without an AWS account; three deliberately injected bugs (public
  database instances, a standby outside the global database, tasks with public IPs) each make a
  `terraform test` run fail.
- The parity checker's own tests found that comparing after normalisation is not enough: a
  standby wired to the primary's provider looked identical. The rule "each side refers only to
  its own role" was added for that case.
- Neither check proves AWS will accept the plan (quotas, account settings); the M3 drill in a real
  account does.
