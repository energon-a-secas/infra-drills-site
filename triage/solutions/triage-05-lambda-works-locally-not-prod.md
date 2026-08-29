# Triage 05: Lambda Works Locally, Times Out in VPC

## Root Cause

A Lambda function in a VPC is placed in a private subnet. The subnet's route table has no route to the internet. No NAT Gateway, no VPC endpoint. When the function tries to call `api.github.com`, the TCP connection hangs until the Lambda timeout kills it.

Outside a VPC, Lambda has direct internet access through AWS's managed networking. Inside a VPC, Lambda gets an ENI (Elastic Network Interface) in the specified subnet and follows that subnet's routing rules. A private subnet without a NAT Gateway has no path to the public internet.

## Diagnostic Path

### 1. Confirm the function works outside a VPC

```bash
awslocal lambda invoke --function-name github-checker --payload '{}' /tmp/response.json && cat /tmp/response.json
```

Returns 200 with GitHub data. The code is fine.

### 2. Check VPC configuration

```bash
awslocal lambda get-function-configuration --function-name github-checker
```

If the function were VPC-attached, you'd see a `VpcConfig` block with `SubnetIds` and `SecurityGroupIds`.

### 3. Check the subnet's route table

```bash
awslocal ec2 describe-route-tables
```

The private subnet's route table only has a local route (`10.0.0.0/16 -> local`). There is no `0.0.0.0/0` route pointing to a NAT Gateway or Internet Gateway.

### 4. Confirm no NAT Gateway exists

```bash
awslocal ec2 describe-nat-gateways
```

Returns empty. No NAT Gateway is provisioned.

## Solution

For a VPC Lambda to reach the internet, you need:

1. **A public subnet** with an Internet Gateway attached
2. **A NAT Gateway** in the public subnet
3. **A route** in the private subnet's route table: `0.0.0.0/0 -> NAT Gateway`

```bash
# Create Internet Gateway
IGW_ID=$(awslocal ec2 create-internet-gateway --query 'InternetGateway.InternetGatewayId' --output text)
awslocal ec2 attach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID

# Create public subnet
PUBLIC_SUBNET=$(awslocal ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.2.0/24 --query 'Subnet.SubnetId' --output text)

# Create NAT Gateway (needs an Elastic IP)
EIP=$(awslocal ec2 allocate-address --query 'AllocationId' --output text)
NAT_ID=$(awslocal ec2 create-nat-gateway --subnet-id $PUBLIC_SUBNET --allocation-id $EIP --query 'NatGateway.NatGatewayId' --output text)

# Add route to private subnet's route table
RT_ID=$(awslocal ec2 describe-route-tables --filters Name=association.subnet-id,Values=$PRIVATE_SUBNET --query 'RouteTables[0].RouteTableId' --output text)
awslocal ec2 create-route --route-table-id $RT_ID --destination-cidr-block 0.0.0.0/0 --nat-gateway-id $NAT_ID
```

Alternative: Use a **VPC Endpoint** for specific AWS services (S3, DynamoDB, SQS) to avoid NAT Gateway costs. But for external APIs like GitHub, you need a NAT Gateway.

## Why This Is Confusing

The mental model that trips people up:

| Environment | Internet Access | Why |
|-------------|----------------|-----|
| Lambda **without** VPC | Yes | AWS manages networking, direct internet path |
| Lambda **in VPC**, public subnet | **No** | Lambda ENIs never get public IPs, even in public subnets |
| Lambda **in VPC**, private subnet + NAT | Yes | Traffic routes through NAT Gateway in the public subnet |

Putting a Lambda in a **public** subnet does NOT give it internet access, Lambda ENIs never receive public IPs. You must route through a NAT Gateway regardless.

## Triage Lessons

- **"It works locally" usually means different network paths.** Local testing bypasses VPC networking. Always consider what network path the function uses in production.
- **Timeouts on external calls point to network routing.** If the function code works and the timeout is generous, the connection is not reaching the destination. Check routing next.
- **Timeout increases mask network problems.** If there is no route, the connection hangs regardless of timeout. A longer timeout just delays the error.

## Common Mistakes

1. **Putting Lambda in a public subnet**: Lambda ENIs never get public IPs. A public subnet alone does not help.
2. **Increasing the timeout**: The team already tried this. The connection is not slow; it's blocked.
3. **Blaming DNS**: DNS resolution may actually work (VPC has default DNS). The TCP connection to the resolved IP is what fails.
4. **Removing VPC configuration**: This fixes the symptom but loses access to VPC resources (RDS, ElastiCache, etc.) that required VPC placement in the first place.

## Related Drill

See [lambda-10-vpc-no-internet](../../aws/lambda-10-vpc-no-internet/) for the full hands-on lab with NAT Gateway setup.
