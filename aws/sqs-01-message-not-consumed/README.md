## Problem

I'm sending messages to my SQS queue `main-queue`, but the Lambda function `sqs-processor` never processes them. Messages keep piling up in the queue and the function never fires. I'm using the following commands:

```
awslocal sqs send-message --queue-url http://sqs.us-east-1.localhost.localstack.cloud:4566/000000000000/main-queue --message-body '{"order_id": "12345"}'
awslocal sqs get-queue-attributes --queue-url http://sqs.us-east-1.localhost.localstack.cloud:4566/000000000000/main-queue --attribute-names ApproximateNumberOfMessages
```

The message count keeps going up, but Lambda logs show zero invocations.

### Context
- Two SQS queues exist: `main-queue` (the primary queue) and `main-queue-dlq` (the dead-letter queue)
- A Lambda function `sqs-processor` was deployed via CloudFormation and exists in LocalStack
- An event source mapping was created to connect SQS to the Lambda function
- The Lambda function code is correct and works fine when invoked manually
- The dead-letter queue is intended to capture messages that fail processing after retries

### Hint
Check which queue ARN the event source mapping is actually connected to. Is it really pointing to `main-queue`?

## Validation

Your solution should:
- Ensure the event source mapping points to `main-queue` (not the DLQ)
- Messages sent to `main-queue` should trigger the Lambda function
- The Lambda function should successfully process the message and log the event

```bash
# Send a test message
awslocal sqs send-message --queue-url http://sqs.us-east-1.localhost.localstack.cloud:4566/000000000000/main-queue --message-body '{"order_id": "99999"}'

# Wait a moment for the event source mapping to poll
sleep 5

# Check that the queue is now empty (message was consumed)
awslocal sqs get-queue-attributes --queue-url http://sqs.us-east-1.localhost.localstack.cloud:4566/000000000000/main-queue --attribute-names ApproximateNumberOfMessages

# Check Lambda logs to confirm invocation
awslocal logs filter-log-events --log-group-name /aws/lambda/sqs-processor
```

## [Solution](../solutions/sqs-01-message-not-consumed.md)
