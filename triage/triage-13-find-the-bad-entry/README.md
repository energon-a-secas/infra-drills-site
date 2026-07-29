## Ticket

**From:** DevOps Engineer
**Priority:** Medium
**Subject:** Config validation fails but won't tell us which service is wrong

> Our service registry validation step started failing. The pipeline runs
> `node validate.js services.json` and it just prints:
>
> `ERROR: service registry failed validation`
>
> That's it. No line number, no service name. The file has 24 services in
> it and it's valid JSON (jq parses it fine), so we can't tell which entry
> is broken. Someone added a batch of services in the last MR.
>
> We don't want to eyeball 24 entries by hand. How do we find the bad one
> quickly?
>
> Files: services.json + validate.js in this directory

### What You Know

- The file is syntactically valid JSON — the failure is a semantic rule, not a parse error.
- The validator gives a single vague message with no location.
- There are 24 entries; exactly one violates a rule.
- Reading all 24 by hand is slow. There is a faster way to localize the fault.

### Your Task

1. Run the validation and confirm the vague failure.
2. Use bisection to narrow 24 entries down to the one bad entry, without reading them all.
3. Fix the bad entry so validation passes.

## Lab Setup

No infrastructure needed.

```bash
cd triage-13-find-the-bad-entry
gitlab-ci-local
```

## Validation

```bash
node validate.js services.json
# Should print: "OK: 24 services valid"
```

Or run the full pipeline with `gitlab-ci-local` — the `validate` job should pass.

## [Solution](../solutions/triage-13-find-the-bad-entry.md)
