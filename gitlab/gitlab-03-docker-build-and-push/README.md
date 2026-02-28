## Problem

You need to understand and debug a multi-stage Docker CI/CD pipeline that builds, tags, and pushes images to a registry.

### Context
- The pipeline uses Docker-in-Docker (dind) for building images
- It has three stages: build, push, and release
- Different branch and tag rules control which jobs run
- YAML anchors are used for shared Docker login logic

### Hint
Look at how the variables, anchors, and job rules interact. Pay attention to the `needs` and `only/except` configurations.

## Validation

```bash
gitlab-ci-local
# The pipeline should parse and execute without errors
```

## [Solution](../solutions/gitlab-03-docker-build-and-push.md)
