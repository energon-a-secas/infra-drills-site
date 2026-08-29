# Triage 08: Script Works Locally, Fails in CI

## Root Cause

The deploy script writes to `/opt/app/config/`, a system directory that requires root permissions. On the developer's laptop, they run with sudo or as a user with write access to /opt. In CI, the container runs as a non-root user (or the filesystem is read-only for system paths), so `mkdir -p /opt/app/config` fails with "Permission denied".

The CI runner works correctly. The script assumes elevated privileges that CI containers lack.

## Diagnostic Path

### 1. Run the pipeline

```bash
gitlab-ci-local
```

The build stage passes. The deploy stage fails with:
```
mkdir: can't create directory '/opt/app/config': Permission denied
```

### 2. Check the script

The deploy job runs `mkdir -p /opt/app/config`. In `node:20-alpine`, the default user may not have write access to `/opt/`.

### 3. Identify the fix

The script should write to a directory the CI user controls. The project workspace, a temp directory, or `$CI_PROJECT_DIR`.

## Solution

Write to the CI workspace instead of a system directory:

```yaml
deploy_config:
  stage: deploy
  image: node:20-alpine
  script:
    - mkdir -p ./deploy/config
    - cp settings.json ./deploy/config/settings.json
    - echo "Config deployed to ./deploy/config/"
    - cat ./deploy/config/settings.json
```

Or use a variable for the config path so it can be overridden per environment:

```yaml
deploy_config:
  stage: deploy
  image: node:20-alpine
  variables:
    CONFIG_DIR: "./deploy/config"
  script:
    - mkdir -p $CONFIG_DIR
    - cp settings.json $CONFIG_DIR/settings.json
    - echo "Config deployed to $CONFIG_DIR/"
    - cat $CONFIG_DIR/settings.json
```

## "Works on My Machine" Checklist

When a script works locally but fails in CI, check these differences:

| Factor | Local | CI |
|--------|-------|----|
| **User** | Your user (often with sudo) | Container user (often non-root) |
| **Filesystem** | Full access, persistent | Ephemeral, restricted paths |
| **Environment variables** | Your shell profile | Only CI-defined variables |
| **Network** | Direct internet, VPN | Runner network, proxy, restricted egress |
| **Tools installed** | Everything you've ever installed | Only what the image provides |
| **Working directory** | Wherever you run from | $CI_PROJECT_DIR (the repo root) |

## Triage Lessons

- **"The CI runner must be broken" usually means the script assumes local privileges.** The runner is working correctly. It runs the script in a controlled environment that is different from a developer laptop.
- **Write to relative paths or $CI_PROJECT_DIR.** Avoid hardcoded system paths (/opt, /usr/local, /etc) in CI scripts unless the image explicitly supports it.
- **Test scripts inside the same container image locally.** Run `docker run --rm -it node:20-alpine sh` and try the commands there. This reproduces the CI environment.

## Common Mistakes

1. **Adding `sudo` to CI scripts**: Most CI images do not have sudo installed. Even if they do, running as root in CI is a security risk.
2. **Switching to a root-based image**: This masks the problem. The script should not require root for deploying config files.
3. **Blaming the artifact passing**: The settings.json file is passed correctly via artifacts. The failure is in the destination path, not the source.
4. **Not reading the error message**: "Permission denied" on a mkdir tells you exactly what happened. The path is not writable.
