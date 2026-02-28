## Problem

Batch GetItem calls to DynamoDB keep returning `UnprocessedKeys` and throttling errors. The application retries but reads are extremely slow and unreliable. I'm using the following commands:

```
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

The response contains `UnprocessedKeys` with items that were not returned, and repeated calls produce inconsistent results.

### Context
- A DynamoDB table `product-catalog` exists with 20 items seeded into it
- The table was created via CloudFormation and has been working for writes
- The application performs batch reads of 10-20 items at a time for product listing pages
- Individual `get-item` calls work fine, but `batch-get-item` with multiple keys consistently returns partial results
- No recent changes were made to the application code

### Hint
Check the table's provisioned throughput settings and compare them to the read demand. How many Read Capacity Units does a batch of 10 items consume versus what is provisioned?

## Validation

Your solution should ensure that `batch-get-item` returns all requested items without any `UnprocessedKeys`:

```bash
# Batch read 10 items at once
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

# The response should have all 10 items in "Responses" and "UnprocessedKeys" should be empty ({})

# Verify the table's throughput is adequate
awslocal dynamodb describe-table --table-name product-catalog \
    --query 'Table.ProvisionedThroughput' --output table
```

## [Solution](../solutions/dynamodb-01-throttled-reads.md)
