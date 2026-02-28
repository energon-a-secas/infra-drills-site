## Tutorial

This is a basic tutorial to get started with GitLab CI/CD locally using `gitlab-ci-local`.

### Setup

1. Ensure Docker is running
2. From the `gitlab/` directory, run `make start` to launch the gitlab-ci container
3. Or run `gitlab-ci-local` directly from this directory

### The Pipeline

The `.gitlab-ci.yml` contains a single job that prints "hello world". This is the simplest possible pipeline.

### Running

```bash
gitlab-ci-local
```

### Expected Output

You should see the job execute and print "hello world" in the output.

### Next Steps

Once you're comfortable with the basics, try the other GitLab drills that introduce more complex pipeline configurations.
