# gitlab-03-docker-build-and-push

## The Issue

This drill is not about fixing a broken pipeline -- it is about understanding how a multi-stage Docker CI/CD pipeline works. The `.gitlab-ci.yml` implements a complete Docker build, tag, and push workflow with Docker-in-Docker, YAML anchors for shared logic, and branch/tag-based job controls. However, it mixes modern `rules:` syntax (in the Build job) with deprecated `only/except` syntax (in the Push jobs), which creates confusion and is a common source of bugs in real pipelines.

The pipeline has three stages:

1. **build** -- Build the Docker image and push it tagged with the pipeline IID
2. **push** -- Re-tag and push the image for the branch (feature branches) or as `latest` (main branch)
3. **release** -- Re-tag and push the image with the Git tag (on tag pushes)

## Solution

### Full Pipeline Walkthrough

#### Global Configuration

```yaml
image: docker:latest

variables:
  CI_REGISTRY_IMAGE: index.docker.io/energonhq/$CI_PROJECT_NAME
  IMAGE_BRANCH: $CI_REGISTRY_IMAGE:$CI_COMMIT_BRANCH
  IMAGE_REF: $CI_REGISTRY_IMAGE:$CI_PIPELINE_IID
  IMAGE_TAG: $CI_REGISTRY_IMAGE:$CI_COMMIT_TAG

services:
  - docker:dind
```

- **`image: docker:latest`** -- Every job runs inside a Docker container that has the Docker CLI installed. This is the client side.
- **`services: docker:dind`** -- Docker-in-Docker. A sidecar container runs a full Docker daemon. The Docker CLI in the job container connects to this daemon to build and push images. This is necessary because GitLab CI runners typically do not have Docker installed on the host.
- **Variables** -- Four image tag variants are defined globally:
  - `CI_REGISTRY_IMAGE` -- Base image path on Docker Hub (e.g., `index.docker.io/energonhq/my-project`)
  - `IMAGE_BRANCH` -- Tagged with the branch name (e.g., `:feature-login`)
  - `IMAGE_REF` -- Tagged with the pipeline IID (e.g., `:42`). The pipeline IID is an auto-incrementing integer per project, more readable than a commit SHA
  - `IMAGE_TAG` -- Tagged with the Git tag (e.g., `:v1.2.3`)

#### The YAML Anchor

```yaml
.docker_login: &docker_login |
  echo -n $CI_REGISTRY_PASSWORD | docker login -u $CI_REGISTRY_USER --password-stdin $CI_REGISTRY
```

This defines a **YAML anchor** named `docker_login`. The `&docker_login` creates the anchor, and the `|` makes it a literal block scalar (preserving the command as a single string). Key points:

- **`echo -n $CI_REGISTRY_PASSWORD | docker login --password-stdin`** -- Pipes the password to stdin instead of using `-p` on the command line. This avoids the password appearing in process listings or shell history.
- **`.docker_login`** -- The leading dot makes this a hidden job (GitLab ignores jobs starting with `.`). It is only used as an anchor, never run as a job.
- **`*docker_login`** -- Used in `script:` blocks to insert the anchor content. This is YAML's alias syntax.

#### Build Job

```yaml
Build:
  stage: build
  script:
    - *docker_login
    - docker build --pull -t "$CI_REGISTRY_IMAGE" . --tag $IMAGE_REF
    - docker push $IMAGE_REF
  rules:
    - changes:
      - Dockerfile
```

- **Stage**: `build` (runs first)
- **Script**:
  1. Logs into the Docker registry using the shared anchor
  2. Builds the image with `--pull` (always pulls the latest base image instead of using a cached one) and tags it with both the base image name and `IMAGE_REF` (pipeline IID)
  3. Pushes only the `IMAGE_REF` tag -- this is the "build artifact" that later jobs will pull and re-tag
- **Rules**: Only runs when the `Dockerfile` has changed. This uses the modern `rules:` syntax. If the Dockerfile has not changed, the entire pipeline effectively stops here because no image is built.

#### Push Branch Job

```yaml
Push branch:
  stage: push
  script:
    - *docker_login
    - docker pull $IMAGE_REF
    - docker tag $IMAGE_REF $IMAGE_BRANCH
    - docker push $IMAGE_BRANCH
  only:
    refs:
      - branches
    changes:
      - Dockerfile
  except:
    - main
  needs:
    - ["Build"]
```

- **Stage**: `push` (runs after build)
- **Script**: Pulls the image built in the Build stage (by its pipeline IID tag), re-tags it with the branch name, and pushes the branch-tagged image
- **only/except**: Runs on all branches EXCEPT `main`, and only when the Dockerfile changed. This means feature branches get an image tagged with their branch name (e.g., `:feature-login`)
- **needs**: Explicitly depends on the Build job. This enables DAG (Directed Acyclic Graph) mode -- the job starts as soon as Build finishes, without waiting for all jobs in the `build` stage to complete

#### Push Latest Job

```yaml
Push latest:
  stage: push
  script:
    - *docker_login
    - docker pull $IMAGE_REF
    - docker tag $IMAGE_REF $CI_REGISTRY_IMAGE:latest
    - docker push $CI_REGISTRY_IMAGE:latest
  only:
    refs:
      - main
    changes:
      - Dockerfile
  needs:
    - ["Build"]
```

- **Stage**: `push`
- **Script**: Same pull-retag-push pattern, but tags the image as `:latest`
- **only**: Runs only on the `main` branch when the Dockerfile changed. This ensures `:latest` always points to the most recent main branch build
- **needs**: Depends on Build

#### Push Tag Job

```yaml
Push tag:
  stage: release
  script:
    - *docker_login
    - docker pull $IMAGE_REF
    - docker tag $IMAGE_REF $IMAGE_TAG
    - docker push $IMAGE_TAG
  only:
    refs:
      - tags
  needs:
    - ["Build"]
```

- **Stage**: `release` (third stage, runs after push)
- **Script**: Pulls the pipeline IID-tagged image, re-tags it with the Git tag (e.g., `:v1.2.3`), and pushes it
- **only**: Runs only on tag pushes. Note this job does NOT check for Dockerfile changes -- when you tag a release, you want the image pushed regardless
- **needs**: Depends on Build

### Pipeline Flow by Scenario

| Trigger | Build | Push branch | Push latest | Push tag |
|---|---|---|---|---|
| Feature branch + Dockerfile changed | Runs | Runs | Skipped | Skipped |
| Feature branch + no Dockerfile change | Skipped | Skipped | Skipped | Skipped |
| Main branch + Dockerfile changed | Runs | Skipped | Runs | Skipped |
| Git tag pushed | Runs | Skipped | Skipped | Runs |

### The `only/except` vs `rules` Problem

The pipeline mixes two syntaxes:

- **Build** uses `rules:` (modern)
- **Push branch**, **Push latest**, **Push tag** use `only/except` (deprecated)

This is problematic for several reasons:

1. **`only/except` is deprecated** -- GitLab recommends `rules:` for all new pipelines. `only/except` will eventually be removed.
2. **You cannot mix `rules:` and `only/except` in the same job** -- GitLab will reject a job that has both keywords. The current pipeline avoids this by using different syntax in different jobs, which is technically valid but confusing.
3. **`rules:` is more powerful** -- It supports `if`, `changes`, `exists`, `variables`, `when`, and `allow_failure` in a single, composable syntax. `only/except` is limited to `refs`, `variables`, `changes`, and `kubernetes`.
4. **Behavior differences** -- With `only/except`, a job defaults to running on all branches if no `only` is specified. With `rules:`, a job defaults to NOT running if no rule matches. This subtle difference causes bugs when migrating pipelines.

### Modernized Version with `rules:`

Here is how the pipeline would look using only `rules:`:

```yaml
image: docker:latest

variables:
  CI_REGISTRY_IMAGE: index.docker.io/energonhq/$CI_PROJECT_NAME
  IMAGE_BRANCH: $CI_REGISTRY_IMAGE:$CI_COMMIT_BRANCH
  IMAGE_REF: $CI_REGISTRY_IMAGE:$CI_PIPELINE_IID
  IMAGE_TAG: $CI_REGISTRY_IMAGE:$CI_COMMIT_TAG

services:
  - docker:dind

.docker_login: &docker_login |
  echo -n $CI_REGISTRY_PASSWORD | docker login -u $CI_REGISTRY_USER --password-stdin $CI_REGISTRY

Build:
  stage: build
  script:
    - *docker_login
    - docker build --pull -t "$CI_REGISTRY_IMAGE" . --tag $IMAGE_REF
    - docker push $IMAGE_REF
  rules:
    - changes:
        - Dockerfile

Push branch:
  stage: push
  script:
    - *docker_login
    - docker pull $IMAGE_REF
    - docker tag $IMAGE_REF $IMAGE_BRANCH
    - docker push $IMAGE_BRANCH
  rules:
    - if: '$CI_COMMIT_BRANCH && $CI_COMMIT_BRANCH != "main"'
      changes:
        - Dockerfile
  needs:
    - Build

Push latest:
  stage: push
  script:
    - *docker_login
    - docker pull $IMAGE_REF
    - docker tag $IMAGE_REF $CI_REGISTRY_IMAGE:latest
    - docker push $CI_REGISTRY_IMAGE:latest
  rules:
    - if: '$CI_COMMIT_BRANCH == "main"'
      changes:
        - Dockerfile
  needs:
    - Build

Push tag:
  stage: release
  script:
    - *docker_login
    - docker pull $IMAGE_REF
    - docker tag $IMAGE_REF $IMAGE_TAG
    - docker push $IMAGE_TAG
  rules:
    - if: '$CI_COMMIT_TAG'
  needs:
    - Build
```

Key changes in the modernized version:

- All jobs use `rules:` instead of `only/except`
- `only: refs: branches` + `except: main` becomes `if: '$CI_COMMIT_BRANCH && $CI_COMMIT_BRANCH != "main"'`
- `only: refs: main` becomes `if: '$CI_COMMIT_BRANCH == "main"'`
- `only: refs: tags` becomes `if: '$CI_COMMIT_TAG'`
- `needs` values no longer use array-in-array syntax (`["Build"]` becomes `Build`)

## Understanding

### Docker-in-Docker (dind)

Docker-in-Docker runs a full Docker daemon inside a container. In GitLab CI:

1. The **job container** (`image: docker:latest`) has the Docker CLI
2. The **service container** (`docker:dind`) runs the Docker daemon
3. The CLI connects to the daemon via the `DOCKER_HOST` variable (usually `tcp://docker:2376` or `tcp://docker:2375`)

This allows building Docker images inside CI without needing Docker installed on the runner host. The alternative is **Docker socket binding** (mounting `/var/run/docker.sock`), which is simpler but has security implications because the CI job gets access to the host's Docker daemon.

### YAML Anchors and Aliases

YAML anchors (`&name`) and aliases (`*name`) are a standard YAML feature (not GitLab-specific) for reusing content:

```yaml
# Define anchor
.template: &my_anchor
  key: value

# Use alias
job:
  <<: *my_anchor    # Merge the anchor's key-value pairs into this mapping
```

For scalar values (strings), the anchor creates a reusable string:

```yaml
.login: &login |
  echo "logging in"

job:
  script:
    - *login        # Inserts the string "echo \"logging in\""
    - echo "done"
```

GitLab also provides `extends:` as a higher-level alternative to YAML anchors for job inheritance, and `!reference` tags for referencing specific keys from other jobs.

### The `needs` Keyword (DAG Pipelines)

By default, GitLab CI runs stages sequentially -- all jobs in stage 1 must finish before any job in stage 2 starts. The `needs` keyword creates a Directed Acyclic Graph (DAG) that allows jobs to start as soon as their specific dependencies finish, regardless of stage ordering.

In this pipeline, all Push jobs have `needs: [Build]`, meaning they start immediately when Build finishes. Without `needs`, they would wait for all `build` stage jobs to complete (even though there is only one).

### Image Tagging Strategy

The pipeline implements a common Docker image tagging strategy:

- **Pipeline IID tag** (`IMAGE_REF`) -- Every build gets a unique, traceable tag. This is the "source of truth" tag that other jobs pull from and re-tag.
- **Branch tag** (`IMAGE_BRANCH`) -- Developers on a feature branch can pull the latest image for that branch. Useful for testing and review environments.
- **Latest tag** -- Always points to the most recent build from `main`. Used by default in `docker pull`.
- **Git tag** (`IMAGE_TAG`) -- Immutable release versions (e.g., `v1.2.3`). Used for production deployments.

## Testing

```bash
# Run the pipeline locally
cd gitlab/gitlab-03-docker-build-and-push
gitlab-ci-local

# The pipeline should parse without errors
# Note: The docker commands will fail locally without a real Docker daemon and registry,
# but the pipeline structure and YAML parsing should be valid
```

To validate just the YAML syntax and structure:

```bash
# Check if gitlab-ci-local can parse the file
gitlab-ci-local --list
```

Expected output should show all four jobs: Build, Push branch, Push latest, Push tag.

## Common Mistakes

1. **Mixing `rules:` and `only/except` in the same job** -- GitLab rejects this with a validation error. They cannot coexist within a single job definition. The pipeline works because each job uses only one syntax, but the inconsistency is confusing and should be fixed.
2. **Forgetting `--password-stdin` for docker login** -- Using `-p $PASSWORD` on the command line exposes the password in process listings and CI logs. Always pipe the password through stdin.
3. **Not using `--pull` in docker build** -- Without `--pull`, Docker uses cached base image layers which may be outdated. In CI, you generally want the latest base image to pick up security patches.
4. **Confusing `CI_PIPELINE_IID` with `CI_PIPELINE_ID`** -- `CI_PIPELINE_IID` is project-scoped and auto-incrementing (1, 2, 3...). `CI_PIPELINE_ID` is instance-scoped and globally unique. The IID is more readable for image tags.
5. **Not setting `needs` correctly** -- The Push jobs pull the image that Build pushed. Without `needs: [Build]`, if another job in the `build` stage fails, the Push jobs would never run even though Build succeeded. `needs` makes the dependency explicit.
6. **Assuming `only: changes` works on the first pipeline** -- On the very first pipeline for a branch (no previous pipeline to compare against), `changes` evaluates to `true` by default. This can cause unexpected behavior.
7. **Using `only/except` in new pipelines** -- This syntax is deprecated. New pipelines should use `rules:` exclusively for consistency and access to the full feature set.
8. **Array-in-array syntax for `needs`** -- The original pipeline uses `needs: - ["Build"]` (array containing a single-element array). While GitLab tolerates this, the correct syntax is `needs: - Build` or `needs: ["Build"]`.

## Additional Resources

- [GitLab CI/CD `rules` keyword](https://docs.gitlab.com/ee/ci/yaml/#rules)
- [Migrating from `only/except` to `rules`](https://docs.gitlab.com/ee/ci/yaml/#switch-between-branch-pipelines-and-merge-request-pipelines)
- [Docker-in-Docker for CI/CD](https://docs.gitlab.com/ee/ci/docker/using_docker_build.html)
- [YAML Anchors and Aliases](https://yaml.org/spec/1.2/spec.html#id2765878)
- [GitLab CI `needs` keyword (DAG)](https://docs.gitlab.com/ee/ci/yaml/#needs)
- [Predefined CI/CD Variables](https://docs.gitlab.com/ee/ci/variables/predefined_variables.html)
- [Docker Image Tagging Best Practices](https://docs.docker.com/develop/dev-best-practices/)
