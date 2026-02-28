# VPC Subnet No Internet Solution

## The Issue

The Internet Gateway exists but has two problems: it is not attached to the VPC, and the route table associated with the public subnet has no default route (`0.0.0.0/0`) pointing to the Internet Gateway. Without the IGW attachment and the default route, traffic from instances in the subnet has no path to the internet, even though the instances have public IPs assigned.

This is one of the most common VPC networking misconfigurations. A public subnet is only "public" if it has a route table with a default route to an attached Internet Gateway. Without both pieces in place, the subnet behaves like a private subnet.

## Solution

1. First, identify the VPC and Internet Gateway IDs:

```bash
awslocal ec2 describe-vpcs --filters "Name=tag:Name,Values=vpc-01-lab-vpc" --query "Vpcs[].VpcId" --output text
awslocal ec2 describe-internet-gateways --filters "Name=tag:Name,Values=vpc-01-igw" --query "InternetGateways[].InternetGatewayId" --output text
```

2. Check the current state of the Internet Gateway to confirm it is not attached:

```bash
awslocal ec2 describe-internet-gateways --filters "Name=tag:Name,Values=vpc-01-igw" --query "InternetGateways[].Attachments"
```

The `Attachments` array will be empty, confirming the IGW is detached.

3. Attach the Internet Gateway to the VPC:

```bash
VPC_ID=$(awslocal ec2 describe-vpcs --filters "Name=tag:Name,Values=vpc-01-lab-vpc" --query "Vpcs[0].VpcId" --output text)
IGW_ID=$(awslocal ec2 describe-internet-gateways --filters "Name=tag:Name,Values=vpc-01-igw" --query "InternetGateways[0].InternetGatewayId" --output text)

awslocal ec2 attach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID
```

4. Check the route table to confirm the default route is missing:

```bash
awslocal ec2 describe-route-tables --filters "Name=tag:Name,Values=vpc-01-public-rt" --query "RouteTables[].Routes"
```

You will see only the local route (`10.0.0.0/16 -> local`) and no `0.0.0.0/0` route.

5. Add the default route pointing to the Internet Gateway:

```bash
RT_ID=$(awslocal ec2 describe-route-tables --filters "Name=tag:Name,Values=vpc-01-public-rt" --query "RouteTables[0].RouteTableId" --output text)

awslocal ec2 create-route --route-table-id $RT_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID
```

6. Verify the route was added:

```bash
awslocal ec2 describe-route-tables --filters "Name=tag:Name,Values=vpc-01-public-rt" --query "RouteTables[].Routes"
```

You should now see the `0.0.0.0/0 -> igw-xxxxx` route alongside the local route.

## Understanding VPC Networking

### VPC, Subnets, and Route Tables

A VPC (Virtual Private Cloud) is an isolated network within AWS. Inside a VPC, subnets segment the IP address space. Each subnet is associated with a route table that determines where network traffic is directed.

- **VPC CIDR**: The overall IP range for the VPC (e.g., `10.0.0.0/16` provides 65,536 addresses)
- **Subnet CIDR**: A subset of the VPC CIDR (e.g., `10.0.1.0/24` provides 256 addresses within the VPC)
- **Route table**: A set of rules (routes) that determine where network traffic from your subnet is directed

Every route table automatically has a **local route** that enables communication within the VPC. For example, a VPC with CIDR `10.0.0.0/16` will have a route `10.0.0.0/16 -> local`, allowing all subnets in the VPC to communicate with each other.

### Internet Gateway (IGW)

An Internet Gateway is a horizontally scaled, redundant, and highly available VPC component that allows communication between your VPC and the internet. For an IGW to function, two things must be true:

1. **The IGW must be attached to the VPC** - An unattached IGW is just a resource that does nothing. Use `attach-internet-gateway` to connect it to a VPC.
2. **A route must point to the IGW** - The route table associated with the subnet must have a route with destination `0.0.0.0/0` (all traffic) targeting the IGW.

### What Makes a Subnet "Public"

A subnet is considered public when it meets all of the following criteria:

- Its route table has a route to an Internet Gateway (`0.0.0.0/0 -> igw-xxxxx`)
- The Internet Gateway is attached to the VPC
- Instances in the subnet have public IP addresses (either via `MapPublicIpOnLaunch` or Elastic IPs)

If any of these conditions is missing, instances in the subnet cannot communicate with the internet, even if they appear to have public IPs.

### NAT Gateway vs. Internet Gateway

- **Internet Gateway**: Enables two-way communication. Instances with public IPs can both send and receive traffic from the internet.
- **NAT Gateway**: Enables one-way outbound communication. Instances in private subnets can reach the internet, but the internet cannot initiate connections to them. NAT Gateways are placed in public subnets and referenced in private subnet route tables.

## Testing

1. Deploy the broken stack and confirm the issues:

```bash
awslocal cloudformation create-stack --stack-name vpc-subnet-no-internet --template-body file://template.yaml
```

2. Check the IGW is not attached:

```bash
awslocal ec2 describe-internet-gateways --filters "Name=tag:Name,Values=vpc-01-igw" --query "InternetGateways[].Attachments"
```

Should return an empty array `[]`.

3. Check the route table has no default route:

```bash
awslocal ec2 describe-route-tables --filters "Name=tag:Name,Values=vpc-01-public-rt" --query "RouteTables[].Routes"
```

Should show only the local route.

4. Apply the fixes (attach IGW and add route):

```bash
VPC_ID=$(awslocal ec2 describe-vpcs --filters "Name=tag:Name,Values=vpc-01-lab-vpc" --query "Vpcs[0].VpcId" --output text)
IGW_ID=$(awslocal ec2 describe-internet-gateways --filters "Name=tag:Name,Values=vpc-01-igw" --query "InternetGateways[0].InternetGatewayId" --output text)
RT_ID=$(awslocal ec2 describe-route-tables --filters "Name=tag:Name,Values=vpc-01-public-rt" --query "RouteTables[0].RouteTableId" --output text)

awslocal ec2 attach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID
awslocal ec2 create-route --route-table-id $RT_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID
```

5. Verify the IGW is now attached:

```bash
awslocal ec2 describe-internet-gateways --filters "Name=tag:Name,Values=vpc-01-igw" --query "InternetGateways[].Attachments"
```

Should show `State: attached` with the VPC ID.

6. Verify the route table now has the default route:

```bash
awslocal ec2 describe-route-tables --filters "Name=tag:Name,Values=vpc-01-public-rt" --query "RouteTables[].Routes"
```

Should now include both the local route and the `0.0.0.0/0 -> igw-xxxxx` route.

## Common Mistakes

1. **Adding the route without attaching the IGW first** - If you create a route pointing to an unattached Internet Gateway, the route may be created but will have a `blackhole` state. Always attach the IGW to the VPC before adding routes that reference it.
2. **Attaching the IGW but forgetting the route** - The IGW attachment alone does not enable internet access. The route table must explicitly direct `0.0.0.0/0` traffic to the IGW. Without this route, the subnet's traffic has no path to the internet.
3. **Associating the wrong route table with the subnet** - Each subnet can be associated with only one route table. If you add the IGW route to a different route table than the one associated with the subnet, traffic from the subnet still will not reach the internet. Verify the association with `describe-route-tables` and check the `Associations` field.
4. **Confusing public IP assignment with internet connectivity** - Having a public IP does not guarantee internet access. The public IP enables the internet to address the instance, but without an IGW and a route, the traffic has nowhere to go.
5. **Not fixing the CloudFormation template** - Fixing the issue via CLI is immediate but temporary. The next stack deployment will recreate the broken state. Uncomment the `AttachGateway` and `DefaultRoute` resources in `template.yaml` for a permanent fix.
6. **Forgetting the security group or network ACL** - Even with the route and IGW in place, if the security group does not allow outbound traffic or the network ACL blocks it, connectivity will still fail. In this drill the default security group and ACL allow all traffic, but in production always check these as well.

## Additional Resources

- [AWS VPC Internet Gateway Documentation](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_Internet_Gateway.html)
- [AWS VPC Route Tables](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_Route_Tables.html)
- [AWS VPC Subnets](https://docs.aws.amazon.com/vpc/latest/userguide/configure-subnets.html)
- [Troubleshooting VPC Connectivity](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_Troubleshooting.html)
- [AWS VPC NAT Gateways](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-nat-gateway.html)
- [LocalStack EC2 and VPC Support](https://docs.localstack.cloud/user-guide/aws/ec2/)
