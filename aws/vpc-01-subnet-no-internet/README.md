## Problem

An EC2 instance in a public subnet can't reach the internet. Running `curl` to any external URL times out. The instance has a public IP assigned, so connectivity should work, but all outbound traffic fails.

```
awslocal ec2 describe-instances --filters "Name=tag:Name,Values=web-server" --query "Reservations[].Instances[].{InstanceId:InstanceId,PublicIp:PublicIpAddress,SubnetId:SubnetId,State:State.Name}"
```

The instance shows a public IP and is in a running state, yet nothing external is reachable.

### Context
- A VPC (`10.0.0.0/16`) was created with a public subnet (`10.0.1.0/24`)
- The subnet has `MapPublicIpOnLaunch` set to `true`
- An Internet Gateway was created via CloudFormation
- A route table is associated with the subnet
- The instance was launched in the public subnet and received a public IP

### Hint
Check the route table associated with the subnet. Does it have a default route (`0.0.0.0/0`) pointing to the Internet Gateway? Also check whether the Internet Gateway is actually attached to the VPC.

## Validation

Your solution should:
- Ensure the Internet Gateway is attached to the VPC
- Ensure the route table has a `0.0.0.0/0` route pointing to the Internet Gateway

```bash
# Verify the Internet Gateway is attached to the VPC
awslocal ec2 describe-internet-gateways --filters "Name=tag:Name,Values=vpc-01-igw" --query "InternetGateways[].Attachments"

# Verify the route table has the default route to the IGW
awslocal ec2 describe-route-tables --filters "Name=tag:Name,Values=vpc-01-public-rt" --query "RouteTables[].Routes"
```

The IGW attachment should show `State: attached` and the route table should include a route with `DestinationCidrBlock: 0.0.0.0/0` targeting the Internet Gateway.

## [Solution](../solutions/vpc-01-subnet-no-internet.md)
