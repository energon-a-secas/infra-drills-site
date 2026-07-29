## Ticket

**From:** Platform Engineer
**Priority:** High
**Subject:** Entire pipeline is red — every single job fails now

> Every job in our pipeline started failing at the same time: lint, test,
> and build all fail immediately. Nobody touched those jobs. The only thing
> that merged was a "CI cleanup" MR that added a shared setup block so we
> stop repeating ourselves across jobs.
>
> Each job fails with something like:
> `./scripts/ci-setup.sh: line 3: aws: command not found`
>
> Three unrelated jobs breaking together makes no sense. Are the runners
> misconfigured?
>
> Pipeline: .gitlab-ci.yml in this directory

### What You Know

- lint, test, and build all fail at the same time.
- The jobs themselves were not edited — a shared setup block was introduced.
- When many unrelated things break together, look for the one thing they share.
- Each job fails in setup, before its real work ever runs.

### Your Task

1. Run the pipeline and confirm all three jobs fail the same way.
2. Find the single shared change that every job now inherits.
3. Fix it so all three jobs pass, without duplicating setup back into each job.

## Lab Setup

No infrastructure needed.

```bash
cd triage-11-everything-broke-at-once
gitlab-ci-local
```

## Validation

```bash
gitlab-ci-local
# All three jobs (lint, test, build) should succeed.
```

Every job should reach and complete its own script.

## [Solution](../solutions/triage-11-everything-broke-at-once.md)
