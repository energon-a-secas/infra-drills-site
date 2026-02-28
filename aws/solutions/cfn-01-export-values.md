# CloudFormation Export Values Solution

## The Issue

The CloudFormation template defines `Outputs` for environment, instance type, and key name parameters, but it does not **export** any of these values. Without the `Export` block on each output, the values remain scoped to the stack and cannot be referenced by other stacks using `Fn::ImportValue`. The drill asks you to export VPC and subnet IDs so that other stacks (such as an application stack or a database stack) can deploy resources into the correct network configuration without hardcoding IDs.

Additionally, the original template has a broken `BucketName` property that uses `!Sub` inside a plain string instead of as a proper intrinsic function, but the core issue is the missing exports.

## Solution

Replace the template with one that accepts VPC and subnet parameters and exports them with named exports:

```yaml
AWSTemplateFormatVersion: '2010-09-09'
Description: 'Exports VPC and Subnet IDs for use in other stacks'

Parameters:
  VpcId:
    Type: String
    Description: ID of the existing VPC
    Default: vpc-123456

  PublicSubnet1:
    Type: String
    Description: ID of the first public subnet
    Default: subnet-public1

  PublicSubnet2:
    Type: String
    Description: ID of the second public subnet
    Default: subnet-public2

  PrivateSubnet1:
    Type: String
    Description: ID of the first private subnet
    Default: subnet-private1

  PrivateSubnet2:
    Type: String
    Description: ID of the second private subnet
    Default: subnet-private2

Resources:
  PlaceholderBucket:
    Type: AWS::S3::Bucket
    Properties:
      BucketName: !Sub "placeholder-bucket-${AWS::StackName}"

Outputs:
  VpcId:
    Description: VPC ID
    Value: !Ref VpcId
    Export:
      Name: !Sub "${AWS::StackName}-VpcId"

  PublicSubnets:
    Description: List of Public Subnets
    Value: !Join [',', [!Ref PublicSubnet1, !Ref PublicSubnet2]]
    Export:
      Name: !Sub "${AWS::StackName}-PublicSubnets"

  PrivateSubnets:
    Description: List of Private Subnets
    Value: !Join [',', [!Ref PrivateSubnet1, !Ref PrivateSubnet2]]
    Export:
      Name: !Sub "${AWS::StackName}-PrivateSubnets"
```

Deploy the stack:

```bash
awslocal cloudformation create-stack \
    --stack-name network-exports \
    --template-body file://template.yaml
```

Verify the exports exist:

```bash
awslocal cloudformation list-exports
```

You should see three exports: `network-exports-VpcId`, `network-exports-PublicSubnets`, and `network-exports-PrivateSubnets`.

## Understanding CloudFormation Exports and Cross-Stack References

### What Are Exports?

CloudFormation **Outputs** let you see values from a stack (in the console, CLI, or API). Adding an `Export` block to an output makes the value available for **cross-stack references** -- other stacks in the same region and account can import it using `Fn::ImportValue`.

### How Cross-Stack References Work

In a consuming stack, you reference an exported value like this:

```yaml
Resources:
  AppSecurityGroup:
    Type: AWS::EC2::SecurityGroup
    Properties:
      VpcId: !ImportValue network-exports-VpcId
```

`Fn::ImportValue` resolves the export name at deploy time and injects the value. This creates a dependency between the two stacks: CloudFormation will not allow you to delete the exporting stack while any other stack is importing its values.

### The Export Block Structure

Each export requires exactly one property -- `Name`:

```yaml
Outputs:
  MyOutput:
    Description: Some value
    Value: !Ref SomeResource
    Export:
      Name: !Sub "${AWS::StackName}-MyOutput"   # Must be unique in the region
```

Using `${AWS::StackName}` as a prefix is a best practice to avoid naming collisions across stacks.

### Key Rules and Limits

- **Export names must be unique** within a region and account. Two stacks cannot export the same name.
- **200 exports per region** -- AWS imposes this soft limit. Plan export names carefully and avoid exporting values that only one stack needs.
- **Exports cannot be deleted while referenced** -- If stack B imports a value from stack A, you cannot delete stack A or remove that export until stack B is updated to stop using it.
- **Exports are region-scoped** -- A stack in `us-east-1` cannot import a value exported by a stack in `eu-west-1`.
- **Values are strings** -- Even when you export a list (like comma-separated subnets), it is stored as a single string. The consuming stack must split it with `Fn::Split` if needed.

## Testing

1. Start LocalStack and deploy the corrected template:

```bash
awslocal cloudformation create-stack \
    --stack-name network-exports \
    --template-body file://template.yaml
```

2. Wait for the stack to reach `CREATE_COMPLETE`:

```bash
awslocal cloudformation describe-stacks --stack-name network-exports \
    --query "Stacks[0].StackStatus"
```

3. List all exports and confirm the three expected names appear:

```bash
awslocal cloudformation list-exports
```

Expected output should include:

```json
{
    "Exports": [
        {
            "ExportingStackId": "...",
            "Name": "network-exports-VpcId",
            "Value": "vpc-123456"
        },
        {
            "ExportingStackId": "...",
            "Name": "network-exports-PublicSubnets",
            "Value": "subnet-public1,subnet-public2"
        },
        {
            "ExportingStackId": "...",
            "Name": "network-exports-PrivateSubnets",
            "Value": "subnet-private1,subnet-private2"
        }
    ]
}
```

4. (Optional) Create a second stack that imports one of the values to confirm the cross-stack reference works:

```bash
cat <<'EOF' > /tmp/consumer.yaml
AWSTemplateFormatVersion: '2010-09-09'
Resources:
  DummyBucket:
    Type: AWS::S3::Bucket
Outputs:
  ImportedVpc:
    Value: !ImportValue network-exports-VpcId
EOF

awslocal cloudformation create-stack \
    --stack-name consumer-stack \
    --template-body file:///tmp/consumer.yaml

awslocal cloudformation describe-stacks --stack-name consumer-stack \
    --query "Stacks[0].Outputs"
```

## Common Mistakes

1. **Defining Outputs without the Export block** -- This is the core issue. An Output without `Export` is only visible via `describe-stacks`; it cannot be consumed by other stacks with `Fn::ImportValue`
2. **Using duplicate export names** -- If two stacks try to export the same name, the second deployment fails. Always prefix export names with the stack name or a namespace
3. **Not using `!Sub` for dynamic export names** -- Hardcoding export names like `Name: MyVpcId` works but makes it impossible to deploy two copies of the same template. Using `!Sub "${AWS::StackName}-VpcId"` ensures uniqueness
4. **Circular dependencies between stacks** -- Stack A exports a value that stack B imports, and stack B exports a value that stack A imports. CloudFormation cannot resolve this and the deployment will fail
5. **Exceeding the 200-export limit** -- Large organizations with many stacks can hit this limit. Consider using SSM Parameter Store as an alternative for sharing values between stacks when you have many exports
6. **Trying to delete a stack with active imports** -- CloudFormation will refuse to delete a stack whose exports are referenced by other stacks. You must update or delete the consuming stacks first
7. **Forgetting that exports are strings** -- Exporting a comma-separated list of subnets is fine, but the consuming stack receives a single string. Use `Fn::Split` to break it back into a list when needed

## Additional Resources

- [AWS CloudFormation Outputs](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/outputs-section-structure.html)
- [Exporting Stack Output Values](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/using-cfn-stack-exports.html)
- [Fn::ImportValue](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/intrinsic-function-reference-importvalue.html)
- [CloudFormation Quotas (200 Exports)](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/cloudformation-limits.html)
- [Cross-Stack References Best Practices](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/best-practices.html#cross-stack)
