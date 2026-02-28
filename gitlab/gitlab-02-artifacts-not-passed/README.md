## Problem

The deploy stage of your pipeline fails with "Build artifact not found!" even though the build stage completed successfully and created the output file.

### Context
- Two-stage pipeline: `build` and `deploy`
- The build job runs successfully and creates `dist/app.jar`
- The deploy job fails because `dist/app.jar` does not exist in its workspace

### Hint
Files created in one job don't automatically carry over to the next. Each job starts with a clean workspace (only the repository contents). Think about how GitLab CI persists files between stages — and how that differs from caching.

## Validation

```bash
gitlab-ci-local
# Both stages should pass
# The deploy stage should find dist/app.jar and print "Deploying..."
```

## [Solution](../solutions/gitlab-02-artifacts-not-passed.md)
