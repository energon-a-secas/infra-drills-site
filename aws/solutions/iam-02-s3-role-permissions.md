# IAM S3 Console Visibility Solution

## The Issue

The IAM policy `S3RestrictedAccess` attached to the user `project-user` grants bucket-level and object-level permissions (`s3:PutObject`, `s3:GetObject`, `s3:DeleteObject`, `s3:PutObjectAcl`, `s3:GetObjectAcl`, `s3:ListBucket`) scoped to a single bucket `project-assets-2024`. These permissions are sufficient for CLI operations against that specific bucket -- you can list its contents, upload files, and download files. However, the AWS S3 Console calls `s3:ListAllMyBuckets` when you first open the S3 service page. This action lists all buckets in the account and is not included in the current policy. Without it, the console shows an empty bucket list or an "Access Denied" error, even though the user has full access to the bucket itself.

The relevant section of the policy in `template.yaml`:

```yaml
RestrictedUserPolicy:
  Type: 'AWS::IAM::Policy'
  Properties:
    PolicyName: S3RestrictedAccess
    Users:
      - !Ref TestUser
    PolicyDocument:
      Version: '2012-10-17'
      Statement:
        - Effect: Allow
          Action:
            - s3:PutObject
            - s3:GetObject
            - s3:DeleteObject
            - s3:PutObjectAcl
            - s3:GetObjectAcl
            - s3:ListBucket
          Resource:
            - !Sub 'arn:aws:s3:::${ProjectAssetsBucket}'
            - !Sub 'arn:aws:s3:::${ProjectAssetsBucket}/*'
```

Notice that `s3:ListAllMyBuckets` is absent, and the resource scope is limited to the specific bucket. The `s3:ListAllMyBuckets` action requires a wildcard resource (`*`) because it operates at the account level, not at the bucket level.

## Solution

Add a second statement to the IAM policy that grants `s3:ListAllMyBuckets` on all resources. This is the minimum change needed to allow the S3 console to display the bucket list.

1. First, retrieve the current policy to confirm the issue:

```bash
awslocal iam list-user-policies --user-name project-user
awslocal iam get-user-policy --user-name project-user --policy-name S3RestrictedAccess
```

You will see the policy only has the bucket-scoped actions listed above.

2. Update the policy to add the `s3:ListAllMyBuckets` permission. Create a file called `updated-policy.json`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject",
        "s3:PutObjectAcl",
        "s3:GetObjectAcl",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::project-assets-2024",
        "arn:aws:s3:::project-assets-2024/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": "s3:ListAllMyBuckets",
      "Resource": "*"
    }
  ]
}
```

3. Apply the updated policy:

```bash
awslocal iam put-user-policy \
    --user-name project-user \
    --policy-name S3RestrictedAccess \
    --policy-document file://updated-policy.json
```

4. Verify the policy was updated:

```bash
awslocal iam get-user-policy --user-name project-user --policy-name S3RestrictedAccess
```

5. Confirm the user can now list all buckets:

```bash
awslocal s3 ls
```

This should now display `project-assets-2024` in the output. Existing bucket-level operations continue to work as before:

```bash
awslocal s3 ls s3://project-assets-2024
awslocal s3 cp test.txt s3://project-assets-2024/
```

## Understanding S3 Permission Levels

### Account-Level vs. Bucket-Level vs. Object-Level Actions

S3 permissions operate at three distinct levels, each requiring different resource scopes in the IAM policy:

**Account-level actions** -- These operate across all buckets in the account. They cannot be scoped to a single bucket.
- `s3:ListAllMyBuckets` -- Lists all buckets in the account (used by the S3 console landing page)
- `s3:CreateBucket` -- Creates a new bucket
- `s3:GetBucketLocation` -- Often needed alongside `ListAllMyBuckets` for the console to function properly

The resource for account-level actions must be `*` or `arn:aws:s3:::*`. Specifying a specific bucket ARN will not work because these actions do not target individual buckets.

**Bucket-level actions** -- These target a specific bucket. The resource is the bucket ARN without a trailing `/*`.
- `s3:ListBucket` -- Lists objects inside a specific bucket
- `s3:GetBucketPolicy` -- Reads the bucket policy
- `s3:GetBucketAcl` -- Reads the bucket ACL

Resource format: `arn:aws:s3:::bucket-name`

**Object-level actions** -- These target objects within a bucket. The resource is the bucket ARN with `/*` to match all objects (or a specific key prefix).
- `s3:GetObject` -- Downloads an object
- `s3:PutObject` -- Uploads an object
- `s3:DeleteObject` -- Deletes an object

Resource format: `arn:aws:s3:::bucket-name/*`

### Why the Console Needs ListAllMyBuckets

When you open the S3 service page in the AWS Console, the first API call it makes is `ListBuckets` (the API-level equivalent of `s3:ListAllMyBuckets`). This returns the list of all buckets in the account, which the console renders as the main bucket list. Without permission for this call, the console cannot render the page at all -- it does not know which buckets exist, so it cannot show any of them, even the ones you have full access to.

This is a common source of confusion: the user has complete read/write access to a specific bucket, but the console appears to show nothing. The CLI works fine because commands like `aws s3 ls s3://bucket-name` call `ListObjectsV2` (which requires `s3:ListBucket`), not `ListBuckets`.

### Principle of Least Privilege Considerations

Adding `s3:ListAllMyBuckets` with `Resource: "*"` does reveal the names of all buckets in the account to the user. This is a minor information disclosure -- the user can see bucket names but cannot access their contents without additional permissions. In most environments this is acceptable, but in highly sensitive multi-tenant accounts, some teams choose to accept the console limitation and require CLI-only access to avoid exposing bucket names.

An alternative approach for console access is to also add `s3:GetBucketLocation` so the console can determine the region of each bucket:

```json
{
  "Effect": "Allow",
  "Action": [
    "s3:ListAllMyBuckets",
    "s3:GetBucketLocation"
  ],
  "Resource": "*"
}
```

## Testing

1. Deploy the CloudFormation stack to set up the drill:

```bash
awslocal cloudformation create-stack \
    --stack-name iam-02-s3-role-permissions \
    --template-body file://template.yaml
```

2. Confirm the bucket exists and has content:

```bash
awslocal s3 ls s3://project-assets-2024
```

You should see `test.txt` in the output.

3. Verify that listing all buckets works at the account level (this uses the default LocalStack credentials, not the restricted user):

```bash
awslocal s3 ls
```

4. Check the current policy on the user:

```bash
awslocal iam get-user-policy --user-name project-user --policy-name S3RestrictedAccess
```

Confirm that `s3:ListAllMyBuckets` is not in the action list.

5. Apply the fix by putting the updated policy:

```bash
awslocal iam put-user-policy \
    --user-name project-user \
    --policy-name S3RestrictedAccess \
    --policy-document file://updated-policy.json
```

6. Verify the updated policy:

```bash
awslocal iam get-user-policy --user-name project-user --policy-name S3RestrictedAccess
```

Confirm that the policy now includes two statements, with the second granting `s3:ListAllMyBuckets` on `*`.

7. Confirm all original operations still work:

```bash
awslocal s3 ls s3://project-assets-2024
awslocal s3 cp test.txt s3://project-assets-2024/newfile.txt
awslocal s3 ls s3://project-assets-2024
```

Note: LocalStack Community tier uses simplified IAM and does not enforce IAM policies by default. The drill is designed to teach the concept; the policy analysis and fix are the same as in a real AWS environment.

## Common Mistakes

1. **Trying to scope `s3:ListAllMyBuckets` to a specific bucket** -- This action operates at the account level and requires `Resource: "*"`. Setting the resource to `arn:aws:s3:::project-assets-2024` will result in the permission having no effect because `ListAllMyBuckets` does not accept bucket-scoped resources
2. **Adding `s3:ListBucket` instead of `s3:ListAllMyBuckets`** -- These are different actions. `s3:ListBucket` lists objects inside a specific bucket (already in the policy). `s3:ListAllMyBuckets` lists the buckets themselves in the account. The names are confusingly similar but they serve different purposes
3. **Replacing the existing policy instead of adding to it** -- When using `put-user-policy`, you must include all existing permissions in the new document. If you only include the `s3:ListAllMyBuckets` statement, you will lose the bucket-level permissions. Always include both statements
4. **Using `s3:List*` wildcard to fix the issue** -- While `s3:List*` on `*` would work, it violates the principle of least privilege by granting `s3:ListBucket` on all buckets, `s3:ListBucketVersions`, `s3:ListBucketMultipartUploads`, and other list actions the user does not need
5. **Not understanding the difference between the CLI and console permission requirements** -- The CLI allows you to target a specific bucket directly (`aws s3 ls s3://bucket`), which only requires `s3:ListBucket`. The console always starts by listing all buckets, which requires `s3:ListAllMyBuckets`. This is why the CLI works but the console does not
6. **Forgetting `s3:GetBucketLocation`** -- In real AWS, the console also calls `GetBucketLocation` to determine which region each bucket is in. Without this permission, the console may show the bucket list but fail to navigate into a bucket. Adding it alongside `ListAllMyBuckets` provides the complete console experience

## Additional Resources

- [S3 Actions, Resources, and Condition Keys](https://docs.aws.amazon.com/AmazonS3/latest/userguide/list_amazons3.html)
- [Controlling Access to S3 with IAM Policies](https://docs.aws.amazon.com/AmazonS3/latest/userguide/access-control-overview.html)
- [Writing IAM Policies: Grant Access to User-Specific Folders](https://docs.aws.amazon.com/AmazonS3/latest/userguide/example-bucket-policies.html)
- [IAM Policy Simulator](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_testing-policies.html)
- [Troubleshooting S3 Access Denied Errors](https://docs.aws.amazon.com/AmazonS3/latest/userguide/troubleshoot-403-errors.html)
- [LocalStack S3 Documentation](https://docs.localstack.cloud/user-guide/aws/s3/)
