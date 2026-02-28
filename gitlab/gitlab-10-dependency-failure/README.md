## Problem

The pipeline fails immediately with an error: `deploy-prod: needs 'run-test' job`. The pipeline never executes any jobs.

### Context
- Three-stage pipeline: `build`, `test`, and `deploy`
- The pipeline uses `needs` to define job dependencies (DAG mode)
- The YAML syntax is valid, but the pipeline fails at configuration validation
- No jobs run at all; the error appears before execution

### Hint
Check the `needs` section of the deploy job against the actual job names defined in the pipeline. Job names are case-sensitive and must match exactly.

## Validation

```bash
gitlab-ci-local
# All three stages should parse and execute successfully
# build-app, run-tests, and deploy-prod should all complete
```

## [Solution](../solutions/gitlab-10-dependency-failure.md)
