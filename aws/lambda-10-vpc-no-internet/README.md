## Problem

A Lambda function was placed in a VPC so it could connect to an RDS database in a private subnet. Database queries work fine, but now any call the Lambda makes to external APIs or AWS services (S3, STS, SQS, etc.) times out after the configured timeout period.

```
awslocal lambda invoke --function-name vpc-data-processor --payload '{}' /tmp/response.json && cat /tmp/response.json
```

The function successfully connects to the database but fails with a timeout when trying to reach anything outside the VPC.

### Context
- The Lambda function was recently moved into a VPC to access an RDS instance in a private subnet
- Database queries from the Lambda to RDS work correctly
- The Lambda function also needs to call the S3 API to store processed results
- Any call to external endpoints or AWS service APIs times out
- The Lambda is attached to a private subnet with a security group that allows all outbound traffic

### Hint
When a Lambda function is placed in a VPC, it runs inside the VPC network using an Elastic Network Interface (ENI). VPC Lambda functions do not get public IP addresses. Check the subnet's route table -- does the private subnet have any route to the internet?

## Validation

Your solution should:
- Ensure the Lambda function can reach both the internal RDS database and external AWS services
- The private subnet route table should have a route to a NAT Gateway or there should be VPC Endpoints for the required AWS services

```bash
# Verify the route table has a route to a NAT Gateway
RT_ID=$(awslocal ec2 describe-route-tables --filters "Name=tag:Name,Values=lambda-10-private-rt" --query "RouteTables[0].RouteTableId" --output text)
awslocal ec2 describe-route-tables --route-table-ids $RT_ID --query "RouteTables[].Routes"

# The route table should include a 0.0.0.0/0 route pointing to a NAT Gateway
```

## [Solution](../solutions/lambda-10-vpc-no-internet.md)
