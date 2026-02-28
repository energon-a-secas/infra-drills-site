# DynamoDB Throttled Reads Solution

## The Issue

The DynamoDB table `product-catalog` is provisioned with only **1 Read Capacity Unit (RCU)**. A single RCU supports one strongly consistent read per second for items up to 4 KB (or two eventually consistent reads per second). When a `batch-get-item` request asks for 10 or more items simultaneously, the read demand far exceeds the provisioned capacity, causing DynamoDB to throttle the request and return the excess items as `UnprocessedKeys`.

Looking at the CloudFormation template, the bug is clear:

```yaml
ProvisionedThroughput:
  ReadCapacityUnits: 1    # <-- absurdly low for batch reads
  WriteCapacityUnits: 5
```

With 1 RCU, the table can only serve 1 strongly consistent read per second (or 2 eventually consistent reads). A batch of 10 items requires at least 10 RCUs worth of capacity in a single burst, so most items are rejected as `UnprocessedKeys`.

## Solution

There are two approaches to fix this:

### Option A: Increase Provisioned Read Capacity Units

Update the table to have adequate RCUs for the expected read workload:

```bash
awslocal dynamodb update-table \
    --table-name product-catalog \
    --provisioned-throughput ReadCapacityUnits=25,WriteCapacityUnits=5
```

Verify the change:

```bash
awslocal dynamodb describe-table --table-name product-catalog \
    --query 'Table.ProvisionedThroughput' --output table
```

### Option B: Switch to On-Demand Capacity Mode

If the read traffic is unpredictable or spiky, switch the table to on-demand (pay-per-request) mode, which automatically scales to handle any level of traffic:

```bash
awslocal dynamodb update-table \
    --table-name product-catalog \
    --billing-mode PAY_PER_REQUEST
```

Verify the change:

```bash
awslocal dynamodb describe-table --table-name product-catalog \
    --query 'Table.BillingModeSummary' --output table
```

### Fix the CloudFormation Template

For Option A, update the template to set a reasonable RCU value:

```yaml
ProvisionedThroughput:
  ReadCapacityUnits: 25
  WriteCapacityUnits: 5
```

For Option B, replace the provisioned throughput with on-demand billing:

```yaml
ProductCatalogTable:
  Type: 'AWS::DynamoDB::Table'
  Properties:
    TableName: product-catalog
    AttributeDefinitions:
      - AttributeName: product_id
        AttributeType: S
    KeySchema:
      - AttributeName: product_id
        KeyType: HASH
    BillingMode: PAY_PER_REQUEST
```

## Understanding DynamoDB Capacity Modes

### Provisioned Capacity Mode

In provisioned mode, you specify the exact number of reads and writes per second your table can handle:

- **Read Capacity Unit (RCU)**: One strongly consistent read per second for an item up to 4 KB in size. Eventually consistent reads consume half an RCU. For items larger than 4 KB, additional RCUs are consumed proportionally (e.g., an 8 KB item consumes 2 RCUs per strongly consistent read).
- **Write Capacity Unit (WCU)**: One write per second for an item up to 1 KB in size. Items larger than 1 KB consume additional WCUs proportionally.

**RCU Calculation Example:**
- 10 items, each 2 KB, strongly consistent reads: 10 items x 1 RCU each = **10 RCUs**
- 10 items, each 2 KB, eventually consistent reads: 10 items x 0.5 RCU each = **5 RCUs**
- 10 items, each 6 KB, strongly consistent reads: 10 items x 2 RCU each (rounded up from 6/4) = **20 RCUs**

**WCU Calculation Example:**
- 10 items, each 0.5 KB: 10 items x 1 WCU each = **10 WCUs**
- 10 items, each 3 KB: 10 items x 3 WCU each (rounded up from 3/1) = **30 WCUs**

### On-Demand Capacity Mode

In on-demand mode (PAY_PER_REQUEST), DynamoDB automatically allocates capacity as needed:

- No capacity planning required
- Scales instantly to handle any level of traffic
- You pay per read/write request unit instead of provisioning upfront
- More expensive per-request than well-tuned provisioned capacity
- Best for unpredictable or spiky workloads, new tables with unknown traffic patterns, or applications where you prefer simplicity over cost optimization

### Burst Capacity

DynamoDB provides some burst capacity for provisioned tables:

- DynamoDB reserves a portion of unused capacity for bursts (up to 300 seconds worth of unused capacity)
- Burst capacity is consumed quickly and is not a substitute for adequate provisioning
- If your table consistently exceeds provisioned capacity, burst capacity will be depleted and throttling will occur
- With only 1 RCU, the burst budget is tiny (300 RCUs total), which a few batch requests can exhaust instantly

### BatchGetItem Behavior Under Throttling

When `BatchGetItem` encounters throttling:

- DynamoDB processes as many items as it can within the available capacity
- Items that could not be read are returned in the `UnprocessedKeys` field of the response
- The caller is responsible for retrying the `UnprocessedKeys` with exponential backoff
- AWS SDKs handle this retry automatically, but it results in increased latency
- The response will not contain an error status code; it simply returns partial results

## Testing

1. Confirm the table is under-provisioned:

```bash
awslocal dynamodb describe-table --table-name product-catalog \
    --query 'Table.ProvisionedThroughput' --output table
```

You should see `ReadCapacityUnits: 1`.

2. Attempt a batch read to observe throttling:

```bash
awslocal dynamodb batch-get-item --request-items '{
  "product-catalog": {
    "Keys": [
      {"product_id": {"S": "prod-001"}},
      {"product_id": {"S": "prod-002"}},
      {"product_id": {"S": "prod-003"}},
      {"product_id": {"S": "prod-004"}},
      {"product_id": {"S": "prod-005"}},
      {"product_id": {"S": "prod-006"}},
      {"product_id": {"S": "prod-007"}},
      {"product_id": {"S": "prod-008"}},
      {"product_id": {"S": "prod-009"}},
      {"product_id": {"S": "prod-010"}}
    ]
  }
}'
```

Check if `UnprocessedKeys` is non-empty in the response.

3. Apply the fix (either increase RCUs or switch to on-demand):

```bash
# Option A: Increase RCUs
awslocal dynamodb update-table \
    --table-name product-catalog \
    --provisioned-throughput ReadCapacityUnits=25,WriteCapacityUnits=5

# Option B: Switch to on-demand
awslocal dynamodb update-table \
    --table-name product-catalog \
    --billing-mode PAY_PER_REQUEST
```

4. Retry the batch read:

```bash
awslocal dynamodb batch-get-item --request-items '{
  "product-catalog": {
    "Keys": [
      {"product_id": {"S": "prod-001"}},
      {"product_id": {"S": "prod-002"}},
      {"product_id": {"S": "prod-003"}},
      {"product_id": {"S": "prod-004"}},
      {"product_id": {"S": "prod-005"}},
      {"product_id": {"S": "prod-006"}},
      {"product_id": {"S": "prod-007"}},
      {"product_id": {"S": "prod-008"}},
      {"product_id": {"S": "prod-009"}},
      {"product_id": {"S": "prod-010"}}
    ]
  }
}'
```

All 10 items should now appear in `Responses` and `UnprocessedKeys` should be empty (`{}`).

5. Test with a larger batch (all 20 items):

```bash
awslocal dynamodb batch-get-item --request-items '{
  "product-catalog": {
    "Keys": [
      {"product_id": {"S": "prod-001"}},
      {"product_id": {"S": "prod-002"}},
      {"product_id": {"S": "prod-003"}},
      {"product_id": {"S": "prod-004"}},
      {"product_id": {"S": "prod-005"}},
      {"product_id": {"S": "prod-006"}},
      {"product_id": {"S": "prod-007"}},
      {"product_id": {"S": "prod-008"}},
      {"product_id": {"S": "prod-009"}},
      {"product_id": {"S": "prod-010"}},
      {"product_id": {"S": "prod-011"}},
      {"product_id": {"S": "prod-012"}},
      {"product_id": {"S": "prod-013"}},
      {"product_id": {"S": "prod-014"}},
      {"product_id": {"S": "prod-015"}},
      {"product_id": {"S": "prod-016"}},
      {"product_id": {"S": "prod-017"}},
      {"product_id": {"S": "prod-018"}},
      {"product_id": {"S": "prod-019"}},
      {"product_id": {"S": "prod-020"}}
    ]
  }
}'
```

All 20 items should be returned successfully.

## Common Mistakes

1. **Setting absurdly low provisioned throughput** - This is the exact bug in this exercise. A table with 1 RCU cannot serve batch reads of 10+ items. Always calculate expected read/write patterns before setting capacity values
2. **Not understanding the difference between provisioned and on-demand** - Provisioned mode requires you to predict traffic; on-demand mode handles it automatically but costs more per request. Choose based on your workload pattern
3. **Forgetting that BatchGetItem does not fail on throttling** - Unlike other API calls that return `ProvisionedThroughputExceededException`, `BatchGetItem` simply returns partial results via `UnprocessedKeys`. This makes the problem harder to detect because there is no explicit error
4. **Not implementing retry logic for UnprocessedKeys** - Even with adequate capacity, transient throttling can occur. Applications should always check `UnprocessedKeys` and retry with exponential backoff
5. **Confusing RCU calculations for strongly vs. eventually consistent reads** - Eventually consistent reads consume half the RCUs. If your application can tolerate eventual consistency, using `ConsistentRead: false` in `BatchGetItem` effectively doubles your read throughput
6. **Relying on burst capacity instead of proper provisioning** - Burst capacity is meant for occasional spikes, not sustained traffic. A table with 1 RCU accumulates only 300 burst RCUs, which a few batch requests will exhaust
7. **Forgetting to update the CloudFormation template after a CLI fix** - If you increase RCUs via `update-table` but do not fix the template, the next stack update will revert the table to 1 RCU
8. **Not considering item size in RCU calculations** - Items larger than 4 KB consume additional RCUs. A 12 KB item requires 3 RCUs per strongly consistent read, not 1

## Additional Resources

- [Amazon DynamoDB Read/Write Capacity Mode](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/HowItWorks.ReadWriteCapacityMode.html)
- [DynamoDB Provisioned Capacity](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/ProvisionedThroughput.html)
- [DynamoDB On-Demand Capacity](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/on-demand-capacity-mode.html)
- [BatchGetItem API Reference](https://docs.aws.amazon.com/amazondynamodb/latest/APIReference/API_BatchGetItem.html)
- [DynamoDB Burst Capacity](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/bp-partition-key-design.html#bp-partition-key-throughput-bursting)
- [Handling Throttling in DynamoDB](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/Programming.Errors.html#Programming.Errors.RetryAndBackoff)
