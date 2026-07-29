# Triage 13: Find the Bad Entry by Bisection

## Root Cause

One service in `services.json` violates a registry rule: the `recommendations` entry declares `port: 70000`, which is outside the valid TCP range of 1 to 65535. The other 23 entries are valid.

The file is syntactically valid JSON, so `jq` and every parser accept it. The failure is a *semantic* rule check, and the validator reports it with a single vague message and no index or name. With 24 entries and no location hint, reading top to bottom is slow and error-prone. Bisection finds the offender in about `log2(24) ≈ 5` checks instead of up to 24.

## Diagnostic Path

### 1. Confirm the failure and rule out a parse error

```bash
node validate.js services.json
# ERROR: service registry failed validation

jq 'length' services.json
# 24
```

`jq` parses the file, so this is not a JSON syntax problem. Exactly one entry breaks a rule the validator enforces, and the tool refuses to say which. That combination, a whole-collection pass/fail with no location, is the classic cue to bisect.

### 2. Halve the collection and test each half

The validator accepts any array, so feed it slices. Split the 24 entries in two and validate each half:

```bash
# First half: entries 0..11
jq '.[0:12]' services.json > /tmp/half.json
node validate.js /tmp/half.json
# OK: 12 services valid

# Second half: entries 12..23
jq '.[12:24]' services.json > /tmp/half.json
node validate.js /tmp/half.json
# ERROR: service registry failed validation
```

The fault is in the second half. You just eliminated 12 entries with one comparison.

### 3. Keep halving the failing side

```bash
# 12..17
jq '.[12:18]' services.json > /tmp/half.json && node validate.js /tmp/half.json
# ERROR  → fault is in 12..17

# 12..14
jq '.[12:15]' services.json > /tmp/half.json && node validate.js /tmp/half.json
# OK     → fault is in 15..17

# 15..16
jq '.[15:17]' services.json > /tmp/half.json && node validate.js /tmp/half.json
# ERROR  → fault is index 15 or 16

# just index 16
jq '.[16:17]' services.json > /tmp/half.json && node validate.js /tmp/half.json
# ERROR  → index 16 is the bad entry
```

Five checks localize the offender. Inspect it:

```bash
jq '.[16]' services.json
# { "name": "recommendations", "port": 70000, "weight": 1.5 }
```

`port: 70000` is out of range.

## Solution

Fix the offending entry's port to a valid value:

```bash
jq '.[16].port = 8016' services.json > services.tmp && mv services.tmp services.json

node validate.js services.json
# OK: 24 services valid
```

Run the pipeline to confirm:

```bash
gitlab-ci-local
# validate job passes
```

Longer term, the real fix is the validator: it should name the failing index and rule (`service[16] "recommendations": port 70000 out of range 1-65535`). A validator that hides the location turns a one-line fix into a bisection hunt. Fixing the message means no one has to bisect this again.

## Triage Lessons

- **Bisection turns a linear search into a logarithmic one.** Halving 24 candidates costs about 5 checks, not 24. The bigger the collection, the more bisection wins: 1000 entries is ~10 checks.
- **Bisect anything you can split and re-test:** entries in a config file, commits in a range (`git bisect`), lines in a payload, feature flags, or half a request path. The only requirement is a reliable pass/fail test.
- **A valid parse does not mean valid content.** `jq` accepting the file rules out syntax and points you at semantic rules. Do not stop at "the JSON is fine."
- **A vague error is a signal about the tooling, not just the data.** When the fix is done, improve the validator to report location. The next incident should not require detective work the tool could have done.

## Common Mistakes

1. **Reading all 24 entries by hand.** Slow, and easy to skim past `70000`. Bisection is faster and does not rely on spotting the anomaly visually.
2. **Blaming JSON syntax.** `jq` parses the file. The rule violation is semantic; a linter for syntax will never flag it.
3. **Guessing at the newest entries first.** "Someone added a batch last MR" is a reasonable prior, but bisection confirms the location deterministically instead of hoping the newest entry is the bad one.
4. **Fixing the symptom, ignoring the tool.** Patching the port unblocks today. Leaving the validator silent guarantees the same manual hunt next time a bad entry lands.
