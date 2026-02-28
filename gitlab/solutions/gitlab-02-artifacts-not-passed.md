# gitlab-02-artifacts-not-passed

## The Issue

The `build-app` job creates `dist/app.jar` successfully, but it never defines an `artifacts:` block. Without artifacts, the file only exists for the duration of the build job. When the `deploy-app` job starts, it gets a fresh workspace containing only the repository contents — `dist/app.jar` is gone.

In GitLab CI, each job runs in an isolated environment. Files created during a job are discarded when the job finishes unless they are explicitly preserved using the `artifacts:` keyword.

## Solution

Add an `artifacts:` block to the `build-app` job so that `dist/` is uploaded and made available to subsequent stages:

```yaml
build-app:
  stage: build
  image: alpine:latest
  script:
    - echo "Compiling application..."
    - mkdir -p dist
    - echo "compiled" > dist/app.jar
    - echo "Build complete. Output written to dist/app.jar"
    - ls -la dist/
  artifacts:
    paths:
      - dist/
```

### Step by step

1. Open `.gitlab-ci.yml`
2. Find the `build-app` job
3. Add an `artifacts:` block after the `script:` section
4. Under `artifacts:`, add `paths:` with `- dist/`
5. Save the file and run `gitlab-ci-local`

## Understanding

### What are artifacts?

Artifacts are files created by a job that are uploaded to GitLab when the job finishes. They are then automatically downloaded by jobs in subsequent stages. This is the mechanism GitLab provides to pass build outputs between stages.

### Artifacts vs Cache

These two features are often confused, but they serve different purposes:

| Feature | Artifacts | Cache |
|---|---|---|
| **Purpose** | Pass build outputs between stages | Speed up jobs by reusing downloaded dependencies |
| **Guarantee** | Guaranteed delivery to downstream jobs | Best-effort; may not be available |
| **Scope** | Within a single pipeline (by default) | Across pipelines on the same branch |
| **Typical contents** | Compiled binaries, JARs, test reports, build outputs | `node_modules/`, `.pip/`, `.m2/`, vendor directories |
| **Defined by** | `artifacts:` keyword in the producing job | `cache:` keyword (global or per-job) |
| **Direction** | Uploaded after job, downloaded by next stage | Saved after job, restored before job |

**Rule of thumb**: If the next stage needs a file to do its work, use `artifacts`. If you want to avoid re-downloading dependencies, use `cache`.

### Artifacts lifecycle

Artifacts have a configurable expiration. By default, they are kept for 30 days on GitLab.com. You can control this with `expire_in`:

```yaml
artifacts:
  paths:
    - dist/
  expire_in: 1 week
```

Common values: `30 min`, `1 hour`, `1 day`, `1 week`, `never`. Setting an appropriate `expire_in` prevents disk usage from growing unboundedly on your GitLab instance.

### How artifacts flow between stages

1. The `build-app` job runs its `script` and creates files
2. GitLab checks the `artifacts:paths` patterns and uploads matching files
3. When `deploy-app` starts, GitLab automatically downloads all artifacts from previous stages into the job's workspace
4. The `deploy-app` job can now access `dist/app.jar` as if it had created it

### The `dependencies` keyword

By default, a job downloads artifacts from all jobs in previous stages. You can limit this with the `dependencies` keyword:

```yaml
deploy-app:
  stage: deploy
  dependencies:
    - build-app
  script:
    - cat dist/app.jar
```

This tells `deploy-app` to only download artifacts from `build-app`, ignoring artifacts from other jobs. This is useful when you have many jobs producing artifacts and want to limit what gets downloaded.

Setting `dependencies: []` (empty list) means the job downloads no artifacts at all.

### How `gitlab-ci-local` handles artifacts

`gitlab-ci-local` simulates artifact passing locally. When a job defines `artifacts:`, the specified files are preserved and made available to subsequent stage jobs. This closely mirrors the behavior of real GitLab runners.

## Testing

```bash
# Run the pipeline after adding the artifacts block
gitlab-ci-local

# Expected output should show:
# build-app    completed successfully (creates dist/app.jar)
# deploy-app   completed successfully (finds dist/app.jar, prints "Deploying...")
```

Verify that:
- The `build-app` job shows "Build complete. Output written to dist/app.jar"
- The `deploy-app` job shows "Deploying dist/app.jar..." and "Deployment successful."
- Neither job exits with an error

## Common Mistakes

1. **Forgetting the `artifacts:` block entirely** — This is the bug in this drill. Without it, files are discarded after the job ends.
2. **Confusing artifacts with cache** — Cache is best-effort and meant for dependencies. Build outputs that the next stage depends on must use `artifacts`.
3. **Using cache for build outputs** — Cache is not guaranteed to be available. If your deploy stage depends on a compiled binary, it must be an artifact, not a cached file.
4. **Wrong artifact paths** — The path in `artifacts:paths` must match the actual location of the files. A typo like `build/` instead of `dist/` means nothing gets uploaded.
5. **Artifacts too large** — Large artifacts slow down upload and download. Use `.gitignore`-style patterns or `artifacts:exclude` to avoid uploading unnecessary files (e.g., intermediate build objects).
6. **Forgetting `expire_in`** — Without it, artifacts use the instance default (30 days on GitLab.com). For CI-only artifacts that aren't needed long-term, set a short expiration to save storage.
7. **Using `dependencies: []` accidentally** — An empty dependencies list means the job downloads no artifacts at all, which can cause the same "file not found" error.

## Additional Resources

- [GitLab CI/CD Job Artifacts](https://docs.gitlab.com/ee/ci/jobs/job_artifacts.html)
- [Artifacts keyword reference](https://docs.gitlab.com/ee/ci/yaml/#artifacts)
- [Dependencies keyword](https://docs.gitlab.com/ee/ci/yaml/#dependencies)
- [Cache vs Artifacts](https://docs.gitlab.com/ee/ci/caching/#cache-vs-artifacts)
- [gitlab-ci-local](https://github.com/firecow/gitlab-ci-local)
