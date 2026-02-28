# gitlab-01-cache-not-shared

## The Issue

The pipeline cache key is set to `$CI_COMMIT_SHA`, which is the full 40-character commit hash. In `gitlab-ci-local`, this variable may not resolve consistently between stages, or it may change between pipeline runs even on the same branch. Because the cache key doesn't match between the build and test stages, the test stage starts with an empty cache and cannot find `node_modules/`.

## Solution

Change the cache key from `$CI_COMMIT_SHA` to `$CI_COMMIT_REF_SLUG`:

```yaml
cache:
  key: $CI_COMMIT_REF_SLUG
  paths:
    - node_modules/
```

`$CI_COMMIT_REF_SLUG` is a URL-safe version of the branch or tag name (e.g., `main`, `feature-login`). This means every job running on the same branch shares the same cache, which is the expected behavior for dependency caching.

### Step by step

1. Open `.gitlab-ci.yml`
2. Find the `cache:` block at the top level
3. Change `key: $CI_COMMIT_SHA` to `key: $CI_COMMIT_REF_SLUG`
4. Save the file

## Understanding

### Cache keys in GitLab CI

The cache key determines which cache bucket a job reads from and writes to. Jobs with the same cache key share the same cache. Choosing the right key is critical:

| Variable | Value | Use Case |
|---|---|---|
| `$CI_COMMIT_SHA` | Full commit hash (`a1b2c3d4...`) | Almost never appropriate for cache — each commit produces a unique key, so the cache is never reused |
| `$CI_COMMIT_REF_SLUG` | Branch/tag name, URL-safe (`main`, `feature-login`) | Best for dependency caches — all jobs on the same branch share the cache |
| `$CI_PIPELINE_ID` | Unique pipeline ID | Similar problem to SHA — each pipeline gets its own cache |
| `$CI_JOB_NAME` | Job name | Useful when different jobs need isolated caches |

### Cache vs Artifacts

These are commonly confused:

- **Cache**: Best-effort storage for dependencies (e.g., `node_modules/`, `.pip/`). Not guaranteed to be available. Used to speed up jobs.
- **Artifacts**: Guaranteed file passing between jobs/stages. Used for build outputs, test reports, binaries. Defined per-job with `artifacts:` and downloaded by dependent jobs.

If you need to guarantee that files are available in the next stage, use `artifacts`, not `cache`. Cache is an optimization, not a contract.

### How `gitlab-ci-local` handles cache

`gitlab-ci-local` simulates GitLab CI locally. It stores cache in `.gitlab-ci-local/cache/` by default. The cache key must resolve to the same string in both the producing and consuming jobs for the cache to be shared.

## Testing

```bash
# Run the pipeline — both stages should pass
gitlab-ci-local

# Expected output should show:
# install-dependencies  completed successfully
# run-tests             completed successfully (finding node_modules/.marker)
```

## Common Mistakes

1. **Using `$CI_COMMIT_SHA` as cache key** — Each commit has a unique SHA, so the cache is never reused across commits. This is the bug in this drill.
2. **Using `$CI_PIPELINE_ID` as cache key** — Same problem; each pipeline run gets a new ID.
3. **Confusing cache with artifacts** — Cache is best-effort and may not persist. If you need guaranteed file passing, use `artifacts`.
4. **Forgetting `paths:` in the cache definition** — Without specifying which paths to cache, nothing gets stored.
5. **Caching too much** — Caching large directories unnecessarily slows down cache upload/download. Only cache what is needed (e.g., `node_modules/` but not the entire project).

## Additional Resources

- [GitLab CI/CD Caching](https://docs.gitlab.com/ee/ci/caching/)
- [Cache key variables](https://docs.gitlab.com/ee/ci/variables/predefined_variables.html)
- [Cache vs Artifacts](https://docs.gitlab.com/ee/ci/caching/#cache-vs-artifacts)
- [gitlab-ci-local](https://github.com/firecow/gitlab-ci-local)
