# Triage 09: Pipeline Slow: Cache Miss Every Run

## Root Cause

The "cleanup" MR changed the cache key from `$CI_COMMIT_REF_SLUG` to `$CI_PIPELINE_ID`. Every pipeline run gets a unique ID, so the cache key is different every time. The cache is written but never read by a subsequent run. It is effectively disabled.

This is the same bug as [gitlab-01-cache-not-shared](../../gitlab/gitlab-01-cache-not-shared/), but presented as a regression after a "harmless" config change.

## Diagnostic Path

### 1. Run the pipeline twice

```bash
gitlab-ci-local
gitlab-ci-local
```

Both runs download all dependencies from scratch. The second run shows "Cache miss".

### 2. Read the cache configuration

Open `.gitlab-ci.yml`. The cache key is `$CI_PIPELINE_ID`.

### 3. Understand the problem

`$CI_PIPELINE_ID` is unique per pipeline run. Every run creates a new cache bucket and never reads from the previous one. The cache exists but is never reused.

### 4. Check what it was before

The cleanup MR changed it from `$CI_COMMIT_REF_SLUG` (branch name, stable across runs on the same branch) to `$CI_PIPELINE_ID` (unique per run). The person who made the change likely thought they were simplifying by using a "more specific" key.

## Solution

Change the cache key back to `$CI_COMMIT_REF_SLUG`:

```yaml
cache:
  key: $CI_COMMIT_REF_SLUG
  paths:
    - node_modules/
```

This means all runs on the same branch share the cache. The first run downloads dependencies; subsequent runs reuse them.

## Cache Key Reference

| Key | Value | Reuse |
|-----|-------|-------|
| `$CI_COMMIT_REF_SLUG` | Branch name (e.g., `main`) | All runs on same branch share cache |
| `$CI_COMMIT_SHA` | Full commit hash | Never reused (every commit is unique) |
| `$CI_PIPELINE_ID` | Pipeline run ID | Never reused (every run is unique) |
| `$CI_JOB_NAME` | Job name | Same job shares cache across all branches |
| `${CI_COMMIT_REF_SLUG}-${CI_JOB_NAME}` | Branch + job | Per-branch, per-job isolation |

## Triage Lessons

- **"Just a cleanup" can break performance.** Config changes that look cosmetic (renaming variables, reorganizing YAML) can have real effects when the values change.
- **Compare before and after.** When performance regresses, diff the config against the last known working version. The change is usually small and obvious in hindsight.
- **Understand what CI variables resolve to.** `$CI_PIPELINE_ID` sounds reasonable as a cache key until you realize it changes every run.

## Common Mistakes

1. **Adding more cache paths**: The cache works fine. The problem is the key, not the paths.
2. **Switching to artifacts**: Artifacts are for passing files between stages in the same pipeline. Cache is for persisting files across pipeline runs. Different tools for different problems.
3. **Blaming the runner**: The runner cache system is working correctly. It writes and reads by key. The key just never matches.
4. **Setting `cache:policy: pull-push` explicitly**: This is already the default. The policy is not the issue.

## Related Drill

See [gitlab-01-cache-not-shared](../../gitlab/gitlab-01-cache-not-shared/) for the foundational drill on cache key selection.
