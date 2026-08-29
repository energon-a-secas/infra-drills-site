## Ticket

**From:** Frontend Developer
**Priority:** Medium
**Subject:** CI pipeline broke overnight. We didn't change anything

> Our pipeline was green yesterday at 5 PM. This morning every build fails
> in the install stage with "npm ERR! engine Unsupported engine". Nobody
> pushed any commits overnight.
>
> We tried re-running the pipeline twice: same error both times.
>
> Pipeline: .gitlab-ci.yml in this directory
> Error stage: install

### What You Know

- The project uses Node.js with a specific engine requirement in package.json.
- The CI pipeline ran successfully yesterday.
- No commits were pushed overnight.
- The pipeline uses an image tag that may resolve to different versions over time.

### Your Task

1. Reproduce the failure by running the pipeline locally.
2. Find why it broke without code changes.
3. Fix the pipeline so it passes.

## Lab Setup

No infrastructure needed: run directly with gitlab-ci-local.

```bash
cd triage-03-pipeline-broke-overnight
gitlab-ci-local
```

## Validation

```bash
gitlab-ci-local
# Both install and test stages should pass
```

## [Solution](../solutions/triage-03-pipeline-broke-overnight.md)
