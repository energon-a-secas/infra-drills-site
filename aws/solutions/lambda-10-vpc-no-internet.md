# Lambda VPC No Internet Solution

## The Issue

The Lambda function is placed in a private subnet that has no route to the internet. When a Lambda function is configured with a VPC, it creates an Elastic Network Interface (ENI) inside the specified subnet. All network traffic from the Lambda function goes through this ENI and follows the subnet's route table.

The private subnet's route table only has the default local route (`10.0.0.0/16 -> local`), which allows communication within the VPC (this is why RDS connectivity works). However, there is no route to `0.0.0.0/0`, so the Lambda function cannot reach anything outside the VPC -- including AWS service endpoints (S3, STS, SQS, DynamoDB, etc.) and external APIs.

## Solution

There are two approaches to fix this. You can use either or both depending on your requirements.

### Option A: Add a NAT Gateway (provides full internet access)

This approach gives the Lambda function access to both AWS services and any external API.

1. Create a public subnet with an Internet Gateway:

```bash
VPC_ID=$(awslocal ec2 describe-vpcs --filters "Name=tag:Name,Values=lambda-10-lab-vpc" --query "Vpcs[0].VpcId" --output text)

# Create a public subnet
PUBLIC_SUBNET_ID=$(awslocal ec2 create-subnet \
    --vpc-id $VPC_ID \
    --cidr-block 10.0.2.0/24 \
    --availability-zone us-east-1a \
    --query "Subnet.SubnetId" --output text)

# Create and attach an Internet Gateway
IGW_ID=$(awslocal ec2 create-internet-gateway --query "InternetGateway.InternetGatewayId" --output text)
awslocal ec2 attach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID

# Create a route table for the public subnet with a route to the IGW
PUBLIC_RT_ID=$(awslocal ec2 create-route-table --vpc-id $VPC_ID --query "RouteTable.RouteTableId" --output text)
awslocal ec2 create-route --route-table-id $PUBLIC_RT_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID
awslocal ec2 associate-route-table --route-table-id $PUBLIC_RT_ID --subnet-id $PUBLIC_SUBNET_ID
```

2. Create a NAT Gateway in the public subnet:

```bash
# Allocate an Elastic IP for the NAT Gateway
EIP_ALLOC=$(awslocal ec2 allocate-address --domain vpc --query "AllocationId" --output text)

# Create the NAT Gateway in the public subnet
NAT_GW_ID=$(awslocal ec2 create-nat-gateway \
    --subnet-id $PUBLIC_SUBNET_ID \
    --allocation-id $EIP_ALLOC \
    --query "NatGateway.NatGatewayId" --output text)
```

3. Add a route from the private subnet to the NAT Gateway:

```bash
PRIVATE_RT_ID=$(awslocal ec2 describe-route-tables --filters "Name=tag:Name,Values=lambda-10-private-rt" --query "RouteTables[0].RouteTableId" --output text)

awslocal ec2 create-route \
    --route-table-id $PRIVATE_RT_ID \
    --destination-cidr-block 0.0.0.0/0 \
    --nat-gateway-id $NAT_GW_ID
```

4. Verify the route was added:

```bash
awslocal ec2 describe-route-tables --route-table-ids $PRIVATE_RT_ID --query "RouteTables[].Routes"
```

### Option B: Add VPC Endpoints (for AWS services only, no internet needed)

If the Lambda function only needs to access specific AWS services (not external APIs), VPC Endpoints are more cost-effective and do not require a NAT Gateway.

```bash
VPC_ID=$(awslocal ec2 describe-vpcs --filters "Name=tag:Name,Values=lambda-10-lab-vpc" --query "Vpcs[0].VpcId" --output text)
PRIVATE_RT_ID=$(awslocal ec2 describe-route-tables --filters "Name=tag:Name,Values=lambda-10-private-rt" --query "RouteTables[0].RouteTableId" --output text)
PRIVATE_SUBNET_ID=$(awslocal ec2 describe-subnets --filters "Name=tag:Name,Values=lambda-10-private-subnet" --query "Subnets[0].SubnetId" --output text)
SG_ID=$(awslocal ec2 describe-security-groups --filters "Name=tag:Name,Values=lambda-10-sg" --query "SecurityGroups[0].GroupId" --output text)

# Gateway endpoint for S3 (free, attaches to route table)
awslocal ec2 create-vpc-endpoint \
    --vpc-id $VPC_ID \
    --service-name com.amazonaws.us-east-1.s3 \
    --route-table-ids $PRIVATE_RT_ID \
    --vpc-endpoint-type Gateway

# Interface endpoint for STS (has per-hour and per-GB cost)
awslocal ec2 create-vpc-endpoint \
    --vpc-id $VPC_ID \
    --service-name com.amazonaws.us-east-1.sts \
    --subnet-ids $PRIVATE_SUBNET_ID \
    --security-group-ids $SG_ID \
    --vpc-endpoint-type Interface
```

Note: VPC Endpoints only provide access to AWS services. If the Lambda also needs to call external third-party APIs, you still need a NAT Gateway (Option A).

### Verify the fix

Invoke the Lambda function to confirm it can now reach external services:

```bash
awslocal lambda invoke --function-name vpc-data-processor --payload '{}' /tmp/response.json && cat /tmp/response.json
```

## Understanding VPC Lambda Networking

### Why VPC Lambdas Lose Internet Access

By default (without VPC configuration), Lambda functions run in an AWS-managed VPC that has internet access. When you attach a Lambda function to your own VPC:

1. Lambda creates an ENI (Elastic Network Interface) in the specified subnet
2. All network traffic from the Lambda goes through this ENI
3. The ENI follows the subnet's route table
4. **Lambda ENIs never receive public IP addresses**, even in public subnets

This means that even if you put a Lambda in a public subnet with an Internet Gateway, the Lambda still cannot reach the internet because it has no public IP for the return traffic to reach.

### NAT Gateway

A NAT (Network Address Translation) Gateway sits in a **public subnet** and has an Elastic IP (public IP). It translates the private IP addresses of resources in private subnets to its own public IP for outbound traffic:

```
Lambda (private subnet, 10.0.1.x)
    --> Route table: 0.0.0.0/0 -> NAT Gateway
        --> NAT Gateway (public subnet, has Elastic IP)
            --> Route table: 0.0.0.0/0 -> Internet Gateway
                --> Internet
```

The NAT Gateway handles the address translation so return traffic can find its way back to the Lambda function, even though the Lambda has no public IP.

### VPC Endpoints

VPC Endpoints provide private connectivity to AWS services without going through the internet:

- **Gateway Endpoints** (S3 and DynamoDB only): Free. Added as a route in the route table. Traffic stays within the AWS network.
- **Interface Endpoints** (most other AWS services): Cost per hour + per GB of data processed. Creates an ENI in your subnet with a private IP that routes to the AWS service.

### Cost Considerations

| Approach | Cost | Use Case |
|----------|------|----------|
| NAT Gateway | ~$32/month + $0.045/GB data processed | Lambda needs to reach external APIs and multiple AWS services |
| VPC Endpoints (Gateway) | Free | Lambda only needs S3 and/or DynamoDB |
| VPC Endpoints (Interface) | ~$7.30/month per endpoint per AZ + $0.01/GB | Lambda only needs specific AWS services |
| No VPC | Free | Lambda does not need to access VPC resources (RDS, ElastiCache, etc.) |

### When to Use VPC Lambda vs. Not

**Put Lambda in a VPC when:**
- It needs to access RDS, ElastiCache, Redshift, or other VPC-only resources
- Compliance requires private network access
- You need to use private API endpoints

**Keep Lambda out of a VPC when:**
- It only needs to call public AWS APIs (S3, DynamoDB, SQS, etc.)
- It only calls external APIs
- It does not need access to VPC-internal resources

Keeping Lambda out of the VPC avoids the complexity and cost of NAT Gateways and VPC Endpoints, and historically reduced cold start times (though AWS has significantly improved VPC Lambda cold starts with Hyperplane ENI improvements).

## Testing

1. Deploy the broken stack:

```bash
awslocal cloudformation create-stack --stack-name lambda-vpc-no-internet --template-body file://template.yaml
```

2. Invoke the function to see the timeout errors:

```bash
awslocal lambda invoke --function-name vpc-data-processor --payload '{}' /tmp/response.json && cat /tmp/response.json
```

The `s3_reachable` and `external_api_reachable` fields should be `false` with timeout errors.

3. Check the current route table (only local route should be present):

```bash
RT_ID=$(awslocal ec2 describe-route-tables --filters "Name=tag:Name,Values=lambda-10-private-rt" --query "RouteTables[0].RouteTableId" --output text)
awslocal ec2 describe-route-tables --route-table-ids $RT_ID --query "RouteTables[].Routes"
```

4. Apply the fix (Option A or B from the Solution above).

5. Invoke the function again to confirm it works:

```bash
awslocal lambda invoke --function-name vpc-data-processor --payload '{}' /tmp/response.json && cat /tmp/response.json
```

Both `s3_reachable` and `external_api_reachable` should now be `true` (with Option A) or at least `s3_reachable` should be `true` (with Option B using only an S3 endpoint).

## Common Mistakes

1. **Putting the Lambda in a public subnet expecting it to have internet access** - This is the most common misconception. Lambda ENIs never get public IP addresses, regardless of whether the subnet has `MapPublicIpOnLaunch` enabled or the subnet has a route to an Internet Gateway. A Lambda in a public subnet behaves identically to a Lambda in a private subnet (no internet access). You always need a NAT Gateway for outbound internet access from a VPC Lambda.

2. **Forgetting to add the route from the private subnet to the NAT Gateway** - Creating the NAT Gateway in the public subnet is not enough. You must also add a route in the private subnet's route table: `0.0.0.0/0 -> nat-gw-xxxxx`. Without this route, the private subnet's traffic still has no path to the NAT Gateway.

3. **Placing the NAT Gateway in the private subnet instead of the public subnet** - The NAT Gateway must be in a public subnet (one with a route to an Internet Gateway) because it needs to reach the internet. Putting it in the private subnet creates a circular dependency.

4. **Not considering VPC Endpoints for AWS services** - If your Lambda only needs to call AWS APIs (S3, DynamoDB, STS, SQS, etc.), VPC Endpoints are cheaper and more secure than routing all traffic through a NAT Gateway. Gateway Endpoints for S3 and DynamoDB are free.

5. **Forgetting that security groups are stateful but NACLs are not** - If you have custom Network ACLs on your subnets, ensure both inbound and outbound rules allow the necessary traffic. Security groups are stateful (return traffic is automatically allowed), but NACLs are stateless (you must explicitly allow return traffic on ephemeral ports).

6. **Not placing the Lambda in a VPC at all** - If the Lambda does not need access to VPC resources like RDS or ElastiCache, the simplest fix is to remove the VPC configuration entirely. Lambda functions without VPC configuration automatically have internet access through the AWS-managed network.

## Additional Resources

- [AWS Lambda VPC Networking](https://docs.aws.amazon.com/lambda/latest/dg/configuration-vpc.html)
- [AWS VPC NAT Gateways](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-nat-gateway.html)
- [AWS VPC Endpoints](https://docs.aws.amazon.com/vpc/latest/privatelink/vpc-endpoints.html)
- [Understanding VPC Lambda Internet Access](https://repost.aws/knowledge-center/internet-access-lambda-function)
- [Improved VPC Networking for Lambda](https://aws.amazon.com/blogs/compute/announcing-improved-vpc-networking-for-aws-lambda-functions/)
- [AWS VPC Endpoint Pricing](https://aws.amazon.com/privatelink/pricing/)
- [LocalStack Lambda VPC Support](https://docs.localstack.cloud/user-guide/aws/lambda/)
