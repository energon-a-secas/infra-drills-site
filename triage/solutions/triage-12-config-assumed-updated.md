# Triage 12: The Config You Assumed Was Updated

## Root Cause

The application reads its endpoint from the SSM parameter `/payments/charge/endpoint` (singular). During the migration, Ops updated a parameter named `/payments/charge/endpoints` (plural, a typo). That update genuinely succeeded, so everyone reports "the config was updated" and "the change went through" in good faith.

But the parameter the application actually reads was never touched. It still holds the decommissioned v1 host, so the app dutifully targets a host that no longer exists and times out. This looks exactly like a network problem, which is why the ticket jumps to DNS and firewalls.

The bug lives in an unchecked assumption: *the config the app reads holds the new value*. Nobody verified it. They verified that *an* update happened, not that the *right parameter* now holds the *right value*.

## Diagnostic Path

### 1. Refuse the conclusion, test the assumption

The ticket asserts "the config is definitely updated, so it's the network." That is a hypothesis stated as fact. Before touching DNS or firewalls, read the exact value the application reads:

```bash
awslocal ssm get-parameter \
  --name /payments/charge/endpoint \
  --query 'Parameter.Value' --output text
```

```
https://api.payments-v1.internal/charge
```

The assumption is false. The parameter still points at v1. There is no network mystery: the app is correctly reaching the address it was told to use, and that address is wrong. This single command collapses the entire "it's the network" theory.

### 2. Find where the "successful update" actually went

Ops are not lying; an update did happen. List the parameters under the prefix to see what exists:

```bash
awslocal ssm get-parameters-by-path --path /payments/charge --recursive \
  --query 'Parameters[].[Name,Value]' --output text
```

```
/payments/charge/endpoint    https://api.payments-v1.internal/charge
/payments/charge/endpoints   https://api.payments-v2.internal/charge
```

The new host landed in `/payments/charge/endpoints` (plural). The update was real but aimed at the wrong key. Assumption verified *and* the true cause located in one step.

### 3. Confirm the network was never the problem

Optional, but it closes the "runner is caching DNS" theory: the app resolves and connects fine to whatever host it is given. Point it at v2 and it works. There was nothing to fix in the network path.

## Solution

Write the correct value to the parameter the application actually reads:

```bash
awslocal ssm put-parameter \
  --name /payments/charge/endpoint \
  --type String \
  --value "https://api.payments-v2.internal/charge" \
  --overwrite

# Remove the typo'd parameter so it can't mislead the next person:
awslocal ssm delete-parameter --name /payments/charge/endpoints
```

Verify:

```bash
awslocal ssm get-parameter --name /payments/charge/endpoint \
  --query 'Parameter.Value' --output text
# https://api.payments-v2.internal/charge
```

The app now reads the new host and the timeouts stop.

## Triage Lessons

- **Verify the assumption before you inherit the conclusion.** "The config is updated, so it must be the network" chains a fact you have not checked to a diagnosis you have not earned. Test the first link and the whole chain often collapses.
- **"An update succeeded" is not "the right thing was updated."** A green confirmation tells you a write happened, not that it happened to the key your app reads with the value it needs. Confirm the specific parameter, name and value.
- **Read what the app reads, at the point it reads it.** Do not audit what *should* be configured; audit the exact source the running code consumes. The gap between the two is where these incidents live.
- **A wrong config masquerades as a network fault.** Timeouts against a dead host look like DNS or firewall issues. Rule out the config the app targets before you send infra chasing packets.

## Common Mistakes

1. **Chasing DNS and firewalls first.** The ticket's suggested cause is the assumption, not the evidence. Investigating it wastes an infra team on a config typo.
2. **Trusting "the change went through."** It did, on the wrong parameter. Accepting the report at face value keeps the real key invisible.
3. **Updating the wrong parameter again.** Writing the new value to `/payments/charge/endpoints` (plural) repeats the original mistake. Fix the key the app actually reads.
4. **Restarting the service and hoping.** A restart re-reads the same stale parameter and times out identically. The value, not the process, is wrong.
