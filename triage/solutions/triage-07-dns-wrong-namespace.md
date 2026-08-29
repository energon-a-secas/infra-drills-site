# Triage 07: DNS Resolution Fails After Namespace Migration

## Root Cause

Kubernetes DNS resolves short hostnames within the **same namespace**. When the app was in the "default" namespace and the database was also accessible there (or the default search domain matched), `postgres` resolved correctly.

After the app moved to the "payments" namespace, the DNS search path in `/etc/resolv.conf` changed. Now `postgres` resolves as `postgres.payments.svc.cluster.local`, which does not exist. The database Service lives in the "database" namespace.

The fix: use the fully qualified domain name (FQDN): `postgres.database.svc.cluster.local`.

## Diagnostic Path

### 1. Test DNS from the app's namespace

```bash
kubectl run dns-test --image=busybox:1.36 --rm -it --restart=Never -n payments -- nslookup postgres
```

Returns `** server can't find postgres`. The short name does not resolve.

### 2. Test DNS with the FQDN

```bash
kubectl run dns-test2 --image=busybox:1.36 --rm -it --restart=Never -n payments -- nslookup postgres.database.svc.cluster.local
```

Returns the Service IP. The database is reachable by FQDN.

### 3. Check where the Service lives

```bash
kubectl get svc -A | grep postgres
```

Shows `postgres` in the `database` namespace.

### 4. Check the app's connection string

```bash
kubectl get deployment payments-app -n payments -o jsonpath='{.spec.template.spec.containers[0].env[0].value}'
```

Shows `postgres://app:secret@postgres:5432/payments`: short hostname.

## Solution

Update the connection string to use the FQDN:

```bash
kubectl set env deployment/payments-app -n payments \
    DATABASE_URL="postgres://app:secret@postgres.database.svc.cluster.local:5432/payments"
```

Or use the shorter cross-namespace form: `postgres.database` (resolves via search domains).

## How Kubernetes DNS Works

Kubernetes DNS resolves service names using search domains configured in each pod's `/etc/resolv.conf`:

```
search payments.svc.cluster.local svc.cluster.local cluster.local
```

When you look up `postgres`, the resolver tries:
1. `postgres.payments.svc.cluster.local`: not found (no postgres Service in payments)
2. `postgres.svc.cluster.local`: not found
3. `postgres.cluster.local`: not found
4. `postgres`: not found

None match because the Service is `postgres.database.svc.cluster.local`.

| Hostname | Resolves From | Why |
|----------|--------------|-----|
| `postgres` | Same namespace only | Expands to `postgres.<current-ns>.svc.cluster.local` |
| `postgres.database` | Any namespace | Expands to `postgres.database.svc.cluster.local` |
| `postgres.database.svc.cluster.local` | Any namespace | Fully qualified: no search path needed |

## Triage Lessons

- **Short hostnames are namespace-scoped.** When you move a service to a different namespace, all cross-namespace references break unless they use FQDNs.
- **"The connection string hasn't changed" is the clue.** If the string didn't change but the app moved namespaces, the DNS context changed.
- **Test DNS from the right namespace.** `nslookup postgres` from the database namespace works; from the payments namespace it fails. Always test from the pod's perspective.

## Common Mistakes

1. **Testing DNS from the wrong namespace**, Running nslookup from the database namespace proves nothing about what the app sees.
2. **Creating a duplicate Service**: Adding a `postgres` Service in the payments namespace that forwards to the database namespace works but adds complexity. Use FQDNs instead.
3. **Blaming NetworkPolicies**: The problem is DNS resolution, not TCP connectivity. Check NetworkPolicies only if DNS resolves but connections time out.
4. **Using ExternalName Services as a workaround**, While `ExternalName` can alias cross-namespace services, it's unnecessary complexity. FQDNs are simpler and more explicit.
