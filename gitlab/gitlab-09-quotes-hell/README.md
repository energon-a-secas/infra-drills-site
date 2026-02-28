## Problem

Your GitLab CI pipeline is failing with cryptic YAML parsing errors. The variables and script blocks contain a mix of single quotes, double quotes, and special characters that are causing issues.

### Context
- GitLab CI/CD uses YAML for pipeline configuration
- YAML has specific rules about quoting strings, especially with special characters
- Variables containing `$`, `:`, `{`, `}`, or `#` need careful quoting

### Hint
Pay attention to how YAML interprets different quoting styles and when variable expansion happens.

## Validation

```bash
gitlab-ci-local
# The pipeline should parse and all jobs should complete successfully
```

## [Solution](../solutions/gitlab-09-quotes-hell.md)
