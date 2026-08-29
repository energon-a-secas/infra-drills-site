# Triage 04: S3 Access Denied After Policy Change

## Root Cause

The security team added a bucket policy with an explicit **Deny** on `s3:PutObject` when the request lacks the `s3:x-amz-server-side-encryption: AES256` header. This is a valid compliance pattern. It forces all uploads to use server-side encryption.

The IAM user has `s3:PutObject` permission, but explicit Deny in a bucket policy always overrides Allow in IAM policies. Every upload without the `--server-side-encryption AES256` flag hits the Deny rule and returns Access Denied.

The policy is correct. The uploads need to include the encryption header.

## Diagnostic Path

### 1. Reproduce the failure

```bash
awslocal s3api put-object --bucket secure-uploads --key test.txt --body test.txt
```

Returns Access Denied.

### 2. Read the bucket policy

```bash
awslocal s3api get-bucket-policy --bucket secure-uploads --output text | python3 -m json.tool
```

The policy shows a Deny statement with condition `StringNotEquals` on `s3:x-amz-server-side-encryption`. This means: deny any PutObject that does NOT include the AES256 encryption header.

### 3. Test with the encryption header

```bash
awslocal s3api put-object --bucket secure-uploads --key test.txt --body test.txt --server-side-encryption AES256
```

This succeeds. The policy is working as designed.

## Solution

Add `--server-side-encryption AES256` to all upload commands:

```bash
awslocal s3api put-object \
    --bucket secure-uploads \
    --key test.txt \
    --body test.txt \
    --server-side-encryption AES256
```

For applications, set the `x-amz-server-side-encryption: AES256` header on every PUT request to S3.

## Understanding Explicit Deny

AWS evaluates policies in this order:

1. **Explicit Deny**: if any policy says Deny, the request is denied. Full stop.
2. **Explicit Allow**: if no Deny exists and any policy says Allow, the request is allowed.
3. **Implicit Deny**: if nothing says Allow, the request is denied by default.

The IAM user has Allow for `s3:PutObject`. But the bucket policy has Deny for PutObject without encryption. Deny wins over Allow regardless of where the Allow comes from.

## Triage Lessons

- **"Minor tightening" can break everything.** A bucket policy with Deny overrides all IAM permissions. The security team's change was correct but its impact was not communicated.
- **Check bucket policies early.** When S3 returns Access Denied, check both IAM and bucket policies, IAM alone misses Deny conditions.
- **Read the Deny conditions carefully.** `StringNotEquals` means "deny when the header is NOT present or NOT equal to AES256". This denies both missing headers and wrong encryption types.

## Common Mistakes

1. **Blaming IAM permissions**: The IAM user has the right permissions. The bucket policy overrides them.
2. **Removing the bucket policy**: The policy enforces a compliance requirement. Removing it fixes uploads but creates a security gap.
3. **Adding more IAM permissions**: Explicit Deny always overrides Allow, regardless of source.
4. **Not reading the Condition block**: The Deny is conditional. Understanding the condition reveals exactly what the upload command needs.
