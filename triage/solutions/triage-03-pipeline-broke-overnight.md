# Triage 03: Pipeline Broke Overnight

## Root Cause

The pipeline uses `image: node:latest`. The `latest` tag points to whichever Node.js version Docker published most recently. Overnight, the Node.js Docker image updated from Node 20.x to Node 22.x (or a similar major bump).

The project's `package.json` specifies `"engines": {"node": ">=18.0.0 <21.0.0"}`. When npm runs with `node:latest` now resolving to Node 22, `npm install` fails with "Unsupported engine" because 22 falls outside the allowed range.

No code changed. The Docker image tag resolved to a new version overnight.

## Diagnostic Path

### 1. Run the pipeline and read the error

```bash
gitlab-ci-local
```

The install stage fails. The error message says:
```
npm ERR! engine Unsupported engine
npm ERR! notsup Not compatible with your version of node/npm
npm ERR! notsup Required: {"node":">=18.0.0 <21.0.0"}
npm ERR! notsup Actual:   {"node":"v22.x.x","npm":"10.x.x"}
```

### 2. Check what image the pipeline uses

Open `.gitlab-ci.yml`. Both jobs use `image: node:latest`.

### 3. Check the engine constraint

Open `package.json`. The `engines` field requires Node `>=18.0.0 <21.0.0`.

### 4. Connect the dots

`node:latest` resolved to Node 22 (outside the allowed range). Yesterday it resolved to Node 20 (inside the range). The tag moved but the code stayed the same.

## Solution

Pin the Node.js image to a specific major version:

```yaml
stages:
  - install
  - test

install_deps:
  stage: install
  image: node:20
  script:
    - node --version
    - npm install
  cache:
    key: $CI_COMMIT_REF_SLUG
    paths:
      - node_modules/

run_tests:
  stage: test
  image: node:20
  script:
    - npm test
  cache:
    key: $CI_COMMIT_REF_SLUG
    paths:
      - node_modules/
```

Change `image: node:latest` to `image: node:20` (or `node:20-alpine` for a smaller image). This pins to the Node 20 major version while still receiving patch updates.

Alternatively, update the `engines` field in `package.json` to accept Node 22 if the application supports it:

```json
"engines": {
  "node": ">=18.0.0 <23.0.0"
}
```

The first option (pinning the image) is safer because it keeps the runtime predictable.

## What to Suspect When "Nothing Changed"

When pipelines break without code changes, check the environment:

1. **Docker image tags moved**: `latest`, `lts`, `stable` resolve to new versions overnight
2. **Dependencies updated**: unpinned packages (`^1.0.0`) pulled a breaking minor/patch release
3. **Runner infrastructure changed**: shared runners updated their base image or Docker version
4. **Certificates or tokens expired**: TLS certs, API keys, or CI variables have expiration dates
5. **External services changed**: an API endpoint the build depends on changed its response format

## Triage Lessons

- **Never use `:latest` in CI pipelines.** Pin to a specific major version (`node:20`, `python:3.12`, `ruby:3.3`). The `latest` tag is convenient for local development but dangerous in CI.
- **Read the full error message.** "Unsupported engine" + the required vs actual versions tells you everything. The fix is clear once you compare the two version numbers.
- **Check the `engines` field.** Many Node.js projects set engine constraints. When the runtime version changes, npm enforces the constraint and fails fast.

## Common Mistakes

1. **Rerunning the pipeline**: If the image tag still points to the new version, rerunning produces the same failure. This is why the team tried twice and got the same error.
2. **Removing the `engines` field**: This masks the problem. The app may have real incompatibilities with the newer Node version. The engine constraint exists for a reason.
3. **Pinning to an exact patch version**: `node:20.11.1` is too specific and misses security patches. Pin to the major version (`node:20`) for the right balance.
4. **Only fixing one job**: Both `install_deps` and `run_tests` use `node:latest`. Fix both, or extract the image into a default or variable.
