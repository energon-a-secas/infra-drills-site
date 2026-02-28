## Problem

The test stage of your pipeline fails because the `node_modules` directory is missing, even though `npm install` ran successfully in the build stage.

### Context
- Two-stage pipeline: `build` and `test`
- Cache is configured to share `node_modules/` between stages
- The build stage passes and installs dependencies
- The test stage fails with "Cannot find module" errors because `node_modules/` is empty

### Hint
Compare how the cache key is defined and what value it produces in each stage. Think about whether the key resolves to the same value across different stages and pipeline runs.

## Validation

```bash
gitlab-ci-local
# Both stages should pass
# The test stage should find node_modules with the .marker file present
```

## [Solution](../solutions/gitlab-01-cache-not-shared.md)
