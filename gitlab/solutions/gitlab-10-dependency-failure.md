# gitlab-10-dependency-failure

## The Issue

The `deploy-prod` job references `run-test` in its `needs` array, but the actual job name is `run-tests` (with an 's'). GitLab CI validates all `needs` references before starting the pipeline, and since `run-test` doesn't match any defined job, the entire pipeline fails at configuration validation without executing any jobs.

## Solution

Fix the typo in the `deploy-prod` job's `needs` array. Change `run-test` to `run-tests`:

```yaml
deploy-prod:
  stage: deploy
  image: alpine:latest
  needs:
    - build-app
    - run-tests
  script:
    - echo "Deploying to production..."
    - echo "Deployment complete."
```

### Step by step

1. Open `.gitlab-ci.yml`
2. Find the `deploy-prod` job
3. In the `needs:` list, change `- run-test` to `- run-tests`
4. Save the file

## Understanding

### `needs` keyword and DAG pipelines

The `needs` keyword creates a Directed Acyclic Graph (DAG) pipeline. Instead of jobs waiting for all jobs in the previous stage to finish, a job with `needs` only waits for the specific jobs listed:

```yaml
# Without needs (stage-based):
# build-app -> [wait for ALL build jobs] -> run-tests -> [wait for ALL test jobs] -> deploy-prod

# With needs (DAG):
# build-app -> run-tests -> deploy-prod (runs as soon as its dependencies finish)
```

DAG pipelines can be significantly faster because jobs start as soon as their specific dependencies complete, not when the entire previous stage finishes.

### `needs` vs `dependencies`

| Feature | `needs` | `dependencies` |
|---|---|---|
| Controls execution order | Yes — job waits for listed jobs | No — only controls artifact download |
| Enables DAG mode | Yes | No |
| Validates job names | Yes — fails pipeline if name doesn't match | Yes — fails pipeline if name doesn't match |
| Downloads artifacts | Yes (by default) | Yes |
| Can skip artifact download | Yes, with `artifacts: false` | No |

### Why the pipeline fails immediately

GitLab validates the entire pipeline configuration before executing any jobs. When it encounters `needs: ["run-test"]` and cannot find a job named `run-test`, it rejects the pipeline configuration. This is a safety feature: it prevents pipelines from reaching a deploy stage only to discover that a required dependency was never defined.

### Job name matching

Job names in `needs` must match exactly:
- They are **case-sensitive**: `Build-App` is not the same as `build-app`
- They must match the **full name**: `run-test` is not the same as `run-tests`
- They cannot use patterns or wildcards

## Testing

```bash
# Run the pipeline after fixing the typo
gitlab-ci-local

# Expected output should show all three jobs completing:
# build-app     completed successfully
# run-tests     completed successfully
# deploy-prod   completed successfully
```

## Common Mistakes

1. **Typos in job names** — This is the most common cause of `needs` failures. Job names must match exactly, including pluralization, hyphens, and casing. This is the bug in this drill.
2. **Referencing jobs from child pipelines** — `needs` can only reference jobs in the same pipeline by default. Cross-pipeline `needs` requires `needs:pipeline` syntax.
3. **Creating circular dependencies** — If job A needs job B and job B needs job A, the pipeline fails. GitLab validates that the dependency graph is acyclic.
4. **Exceeding the `needs` limit** — By default, a job can list a maximum of 50 jobs in `needs`. This limit can be changed by administrators.
5. **Confusing `needs` with `dependencies`** — Using `dependencies` when you want execution ordering won't work. `dependencies` only controls artifact downloading; it doesn't change when jobs run.
6. **Forgetting that `needs` bypasses stage ordering** — A job with `needs` can run before jobs in earlier stages if its dependencies are met. This can cause surprising behavior if not well understood.

## Additional Resources

- [GitLab CI `needs` keyword](https://docs.gitlab.com/ee/ci/yaml/#needs)
- [Directed Acyclic Graph (DAG) pipelines](https://docs.gitlab.com/ee/ci/directed_acyclic_graph/)
- [GitLab CI `dependencies` keyword](https://docs.gitlab.com/ee/ci/yaml/#dependencies)
- [GitLab CI pipeline architecture](https://docs.gitlab.com/ee/ci/pipelines/pipeline_architectures.html)
- [gitlab-ci-local](https://github.com/firecow/gitlab-ci-local)
