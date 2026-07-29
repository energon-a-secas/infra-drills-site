# Ticket Triage

You receive a support ticket describing a failure. Read it, form a hypothesis, run diagnostic commands, find the root cause.

These drills train a different skill than break-fix labs. Instead of a known broken config file, you start with vague or misleading symptoms — the way real incidents arrive.

Drills 10 through 13 each rehearse one strategy from the [Troubleshooting Framework](https://infradrills.neorgon.com/troubleshooting/): **comparison** (diff two environments), **rule out** (isolate a shared change), **verify assumptions** (test what you "know"), and **bisect** (halve the search space). The ticket is written so the wrong strategy leads you in circles and the right one solves it quickly.

## How It Works

Each drill presents:

1. **The Ticket** — what the user reported. May include red herrings or missing context.
2. **Your Environment** — a lab-initialization script sets up the broken state.
3. **Diagnostic Checklist** — suggested commands to investigate (hidden by default in the solution).
4. **Root Cause + Fix** — what actually went wrong and how to resolve it.

## Approach

When you read a ticket, ask yourself:

- **What exactly is the symptom?** (502 error, pod crashing, pipeline failing)
- **What changed recently?** (deploy, config update, dependency bump — or "nothing")
- **What would I check first?** (logs, events, recent changes, resource status)
- **What's the simplest explanation?** (typo, misconfiguration, wrong environment)

## Setup

Each triage drill uses the same infrastructure as its parent section:

- **AWS drills**: LocalStack must be running (`cd ../aws && make run`)
- **Kubernetes drills**: Minikube must be running (`cd ../kubernetes && make start`)
- **GitLab drills**: gitlab-ci-local via docker-compose (`cd ../gitlab && make start`)

## Drills

| Drill | Section | Difficulty | Symptom |
|-------|---------|------------|---------|
| [triage-01-api-502-gateway](./triage-01-api-502-gateway/) | AWS | intermediate | API returns 502 Bad Gateway |
| [triage-02-app-crash-after-rollback](./triage-02-app-crash-after-rollback/) | Kubernetes | intermediate | App crashes after "successful" rollback |
| [triage-03-pipeline-broke-overnight](./triage-03-pipeline-broke-overnight/) | GitLab | intermediate | Pipeline fails with no code changes |
| [triage-04-s3-access-denied-policy](./triage-04-s3-access-denied-policy/) | AWS | intermediate | S3 Access Denied after security update |
| [triage-05-lambda-works-locally-not-prod](./triage-05-lambda-works-locally-not-prod/) | AWS | intermediate | Lambda works locally, times out in VPC |
| [triage-06-service-intermittent-503](./triage-06-service-intermittent-503/) | Kubernetes | intermediate | Service returns 503 randomly (~50%) |
| [triage-07-dns-wrong-namespace](./triage-07-dns-wrong-namespace/) | Kubernetes | intermediate | DNS fails after namespace migration |
| [triage-08-deploy-works-locally-fails-ci](./triage-08-deploy-works-locally-fails-ci/) | GitLab | beginner | Script works locally, Permission Denied in CI |
| [triage-09-pipeline-slow-cache-miss](./triage-09-pipeline-slow-cache-miss/) | GitLab | beginner | Pipeline 6x slower after config cleanup |
| [triage-10-crashloop-one-environment](./triage-10-crashloop-one-environment/) | Kubernetes | intermediate | Works in staging, CrashLoopBackOff in production |
| [triage-11-everything-broke-at-once](./triage-11-everything-broke-at-once/) | GitLab | intermediate | Every job fails at once after a shared-setup MR |
| [triage-12-config-assumed-updated](./triage-12-config-assumed-updated/) | AWS | intermediate | Still hits old endpoint after "config was updated" |
| [triage-13-find-the-bad-entry](./triage-13-find-the-bad-entry/) | GitLab | intermediate | 24-entry registry fails validation, no location given |
