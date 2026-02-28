# Route 53 Missing Zone Delegation Solution

## The Issue

The CloudFormation template creates two Route 53 hosted zones -- a parent zone for `ehq.cloud` and a child zone for `eph.ehq.cloud` -- along with a test A record (`test.eph.ehq.cloud` pointing to `192.0.2.44`) in the child zone. However, the template does **not** create NS (Name Server) delegation records in the parent zone that point to the child zone's nameservers. Without these delegation records, the DNS hierarchy is broken: when a DNS resolver queries for `eph.ehq.cloud` or any record under it, the parent zone has no way to direct the resolver to the child zone's nameservers. The query returns no results.

In DNS, every subdomain delegation requires the parent zone to contain an NS record set that tells resolvers "for queries about this subdomain, go ask these nameservers." The child zone exists and has the correct records, but no one can find it because the parent never tells resolvers where to look.

The relevant template creates the zones but is missing the delegation:

```yaml
ParentHostedZone:
  Type: 'AWS::Route53::HostedZone'
  Properties:
    Name: ehq.cloud

ChildHostedZone:
  Type: 'AWS::Route53::HostedZone'
  Properties:
    Name: eph.ehq.cloud

# Missing: NS record in ParentHostedZone pointing to ChildHostedZone's nameservers
```

## Solution

1. First, identify the hosted zone IDs:

```bash
PARENT_ZONE_ID=$(awslocal route53 list-hosted-zones \
    --query "HostedZones[?Name=='ehq.cloud.'].Id" --output text | sed 's|/hostedzone/||')

CHILD_ZONE_ID=$(awslocal route53 list-hosted-zones \
    --query "HostedZones[?Name=='eph.ehq.cloud.'].Id" --output text | sed 's|/hostedzone/||')

echo "Parent Zone: $PARENT_ZONE_ID"
echo "Child Zone: $CHILD_ZONE_ID"
```

2. Retrieve the child zone's nameservers:

```bash
CHILD_NS=$(awslocal route53 get-hosted-zone \
    --id $CHILD_ZONE_ID \
    --query "DelegationSet.NameServers" --output json)

echo "Child nameservers: $CHILD_NS"
```

3. Check the parent zone's current records to confirm the delegation is missing:

```bash
awslocal route53 list-resource-record-sets --hosted-zone-id $PARENT_ZONE_ID
```

You will see SOA and NS records for `ehq.cloud.` itself, but no NS record for `eph.ehq.cloud.`.

4. Create the NS delegation record in the parent zone. Build the change batch with the child zone's nameservers:

```bash
# Extract individual nameservers
NS1=$(echo $CHILD_NS | jq -r '.[0]')
NS2=$(echo $CHILD_NS | jq -r '.[1]')
NS3=$(echo $CHILD_NS | jq -r '.[2]')
NS4=$(echo $CHILD_NS | jq -r '.[3]')

awslocal route53 change-resource-record-sets \
    --hosted-zone-id $PARENT_ZONE_ID \
    --change-batch '{
        "Changes": [{
            "Action": "CREATE",
            "ResourceRecordSet": {
                "Name": "eph.ehq.cloud",
                "Type": "NS",
                "TTL": 300,
                "ResourceRecords": [
                    {"Value": "'"$NS1"'"},
                    {"Value": "'"$NS2"'"},
                    {"Value": "'"$NS3"'"},
                    {"Value": "'"$NS4"'"}
                ]
            }
        }]
    }'
```

If the child zone has fewer than four nameservers (common in LocalStack), adjust the `ResourceRecords` array accordingly. You can use this approach for any number of nameservers:

```bash
# Dynamic approach for any number of nameservers
NS_RECORDS=$(awslocal route53 get-hosted-zone --id $CHILD_ZONE_ID \
    --query "DelegationSet.NameServers" --output json | \
    jq '[.[] | {"Value": .}]')

awslocal route53 change-resource-record-sets \
    --hosted-zone-id $PARENT_ZONE_ID \
    --change-batch '{
        "Changes": [{
            "Action": "CREATE",
            "ResourceRecordSet": {
                "Name": "eph.ehq.cloud",
                "Type": "NS",
                "TTL": 300,
                "ResourceRecords": '"$NS_RECORDS"'
            }
        }]
    }'
```

5. Verify the delegation records were created:

```bash
awslocal route53 list-resource-record-sets --hosted-zone-id $PARENT_ZONE_ID
```

You should now see an NS record for `eph.ehq.cloud.` pointing to the child zone's nameservers.

6. Test DNS resolution:

```bash
dig @127.0.0.1 eph.ehq.cloud NS
dig @127.0.0.1 test.eph.ehq.cloud A
```

The first query should return the child zone's nameservers. The second should return `192.0.2.44`.

## Understanding DNS Delegation

### How DNS Resolution Works

DNS is a hierarchical system. When a resolver needs to find `test.eph.ehq.cloud`, it follows a chain of delegations:

1. The **root servers** (`.`) know which nameservers are authoritative for `.cloud`
2. The `.cloud` **TLD servers** know which nameservers are authoritative for `ehq.cloud`
3. The `ehq.cloud` **nameservers** should know which nameservers are authoritative for `eph.ehq.cloud` -- this is the delegation that was missing
4. The `eph.ehq.cloud` **nameservers** have the actual A record for `test.eph.ehq.cloud`

If step 3 is broken (no NS records in the parent zone for the child subdomain), the resolver has no way to discover the child zone's nameservers. The query fails with `NXDOMAIN` or `SERVFAIL`, even though the child zone exists and has the correct records.

### NS Records and Delegation

An NS (Name Server) record delegates authority for a DNS zone to specific nameservers. There are two types of NS records to understand:

**Zone apex NS records** -- Every hosted zone automatically has NS records at its apex (e.g., `ehq.cloud NS ns-1.example.com`). These tell the world which nameservers are authoritative for that zone.

**Delegation NS records** -- These are NS records created in a parent zone that point to a child zone's nameservers (e.g., an NS record for `eph.ehq.cloud` in the `ehq.cloud` zone). These records create the link in the DNS hierarchy.

The key insight is that creating a hosted zone in Route 53 only creates the zone itself with its own apex NS records. It does **not** automatically create the delegation NS records in the parent zone. You must create those manually.

### Glue Records

In real DNS (less relevant for LocalStack), when the nameservers for a child zone are within the child zone itself (e.g., `ns1.eph.ehq.cloud` serving `eph.ehq.cloud`), the parent zone must also contain **glue records** -- A records that provide the IP addresses of those nameservers. Without glue records, there would be a circular dependency: to find `ns1.eph.ehq.cloud`, you would need to query the nameserver for `eph.ehq.cloud`, which is `ns1.eph.ehq.cloud`. Route 53 nameservers live outside customer zones (e.g., `ns-123.awsdns-45.com`), so glue records are typically not needed.

### Route 53 Hosted Zone Types

- **Public hosted zone** -- Answers DNS queries from the internet. Used for publicly accessible domain names.
- **Private hosted zone** -- Answers DNS queries only from within associated VPCs. Used for internal domain names.

Both types require proper delegation from the parent zone, but private zones only need to be resolvable from within the VPC.

## Testing

1. Deploy the CloudFormation stack:

```bash
awslocal cloudformation create-stack \
    --stack-name r53-missing-delegation \
    --template-body file://template.yaml
```

2. Confirm both zones exist:

```bash
awslocal route53 list-hosted-zones
```

You should see both `ehq.cloud.` and `eph.ehq.cloud.`.

3. Verify the test record exists in the child zone:

```bash
CHILD_ZONE_ID=$(awslocal route53 list-hosted-zones \
    --query "HostedZones[?Name=='eph.ehq.cloud.'].Id" --output text | sed 's|/hostedzone/||')

awslocal route53 list-resource-record-sets --hosted-zone-id $CHILD_ZONE_ID
```

You should see the A record for `test.eph.ehq.cloud` pointing to `192.0.2.44`.

4. Confirm the parent zone is missing the delegation:

```bash
PARENT_ZONE_ID=$(awslocal route53 list-hosted-zones \
    --query "HostedZones[?Name=='ehq.cloud.'].Id" --output text | sed 's|/hostedzone/||')

awslocal route53 list-resource-record-sets --hosted-zone-id $PARENT_ZONE_ID
```

You should see only the SOA and NS records for `ehq.cloud.` -- no NS record for `eph.ehq.cloud.`.

5. Attempt DNS resolution before the fix (this should fail or return no answer):

```bash
dig @127.0.0.1 test.eph.ehq.cloud A
```

6. Apply the fix by adding the delegation NS records (using the commands from the Solution section above).

7. Verify DNS resolution after the fix:

```bash
dig @127.0.0.1 eph.ehq.cloud NS
dig @127.0.0.1 test.eph.ehq.cloud A
```

The NS query should return the child zone's nameservers, and the A query should return `192.0.2.44`.

## Common Mistakes

1. **Creating the NS records in the child zone instead of the parent zone** -- The delegation NS records must be in the **parent** zone (`ehq.cloud`), not in the child zone (`eph.ehq.cloud`). The child zone already has its own apex NS records. Adding duplicate NS records in the child zone does nothing for delegation
2. **Using the parent zone's nameservers instead of the child zone's** -- The delegation must point to the child zone's nameservers, not the parent's. Each Route 53 hosted zone has its own set of four nameservers. Retrieve them with `get-hosted-zone --id <child-zone-id>`
3. **Forgetting the trailing dot on domain names** -- Route 53 uses fully qualified domain names with a trailing dot (e.g., `eph.ehq.cloud.`). While the API often handles this automatically, some tools and configurations require the trailing dot. Omitting it can cause unexpected behavior
4. **Creating an A record or CNAME instead of NS records** -- Delegation requires NS records specifically. An A record in the parent zone would create a direct answer rather than a delegation, and a CNAME at a delegation point is not allowed by the DNS specification (RFC 1034)
5. **Not waiting for propagation** -- In real AWS, Route 53 changes can take up to 60 seconds to propagate to all nameservers. In LocalStack the change is typically immediate, but in production always account for propagation delay before concluding the fix did not work
6. **Hardcoding nameserver values** -- Route 53 assigns nameservers dynamically when a hosted zone is created. If you delete and recreate the child zone, it will get different nameservers. Always retrieve the current nameservers programmatically rather than hardcoding them
7. **Confusing hosted zones with domain registration** -- Creating a hosted zone in Route 53 does not register or transfer a domain. For the delegation to work end-to-end in production, the domain registrar must also have NS records pointing to the Route 53 nameservers for the parent zone

## Additional Resources

- [Creating a Subdomain That Uses Route 53 as the DNS Service](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/CreatingNewSubdomain.html)
- [Routing Traffic for Subdomains](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/dns-routing-traffic-for-subdomains.html)
- [Working with Hosted Zones](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/hosted-zones-working-with.html)
- [NS and SOA Records That Route 53 Creates](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/SOA-NSrecords.html)
- [DNS Delegation Explained (RFC 1034)](https://www.rfc-editor.org/rfc/rfc1034)
- [LocalStack Route 53 Documentation](https://docs.localstack.cloud/user-guide/aws/route53/)
