# SQS Message Not Consumed Solution

## The Issue

The Lambda event source mapping is connected to the wrong queue. Instead of pointing to `main-queue`, it is configured to poll from `main-queue-dlq` (the dead-letter queue). This means messages sent to `main-queue` are never picked up by the Lambda function because the event source mapping is watching the DLQ, which has no messages in it. Meanwhile, messages accumulate in `main-queue` with nothing consuming them.

This is a common typo or copy-paste mistake when CloudFormation templates reference multiple queues: the event source mapping's `EventSourceArn` points to `DeadLetterQueue.Arn` instead of `MainQueue.Arn`.

## Solution

1. First, list the event source mappings to confirm the misconfiguration:

```bash
awslocal lambda list-event-source-mappings --function-name sqs-processor
```

In the output, note the `EventSourceArn` field. It will show the ARN of `main-queue-dlq` instead of `main-queue`.

2. Get the ARN of the main queue:

```bash
awslocal sqs get-queue-attributes \
    --queue-url http://sqs.us-east-1.localhost.localstack.cloud:4566/000000000000/main-queue \
    --attribute-names QueueArn
```

3. Delete the incorrect event source mapping (use the UUID from step 1):

```bash
awslocal lambda delete-event-source-mapping --uuid <UUID_FROM_STEP_1>
```

4. Create a new event source mapping pointing to the correct queue:

```bash
awslocal lambda create-event-source-mapping \
    --function-name sqs-processor \
    --event-source-arn arn:aws:sqs:us-east-1:000000000000:main-queue \
    --batch-size 10 \
    --enabled
```

5. Verify the new mapping is correct:

```bash
awslocal lambda list-event-source-mappings --function-name sqs-processor
```

The `EventSourceArn` should now show `arn:aws:sqs:us-east-1:000000000000:main-queue`.

## Understanding SQS Event Source Mappings

An SQS event source mapping is the mechanism that connects an SQS queue to a Lambda function. Lambda polls the queue on your behalf and invokes your function with a batch of messages.

### How Event Source Mappings Work

- Lambda uses **long polling** to check the SQS queue for messages
- When messages are available, Lambda retrieves them in batches (up to the configured `BatchSize`)
- Lambda invokes your function synchronously with the batch of messages as the event payload
- If the function processes the batch successfully, Lambda deletes the messages from the queue
- If the function returns an error, the messages become visible again after the `VisibilityTimeout` expires

### Dead-Letter Queues (DLQ) with SQS

A dead-letter queue is a separate SQS queue that receives messages which could not be processed successfully after a configured number of attempts (`maxReceiveCount`). The relationship works as follows:

- The **main queue** has a `RedrivePolicy` that specifies the DLQ ARN and the maximum receive count
- When a message is received more than `maxReceiveCount` times without being deleted, SQS automatically moves it to the DLQ
- The DLQ is meant for inspection and debugging, not for primary processing
- You can set up a separate Lambda function or alarm on the DLQ to handle failed messages

### Event Source Mapping vs. Queue Configuration

It is important to understand that the event source mapping and the redrive policy are independent configurations:

- **Event source mapping**: Tells Lambda which queue to poll for messages (configured on the Lambda side)
- **Redrive policy**: Tells SQS where to send failed messages (configured on the queue side)
- Mixing up these ARNs is a common source of bugs

## Testing

1. Confirm the event source mapping is misconfigured:

```bash
awslocal lambda list-event-source-mappings --function-name sqs-processor
```

Observe that `EventSourceArn` contains `main-queue-dlq`.

2. Send a message to the main queue:

```bash
awslocal sqs send-message \
    --queue-url http://sqs.us-east-1.localhost.localstack.cloud:4566/000000000000/main-queue \
    --message-body '{"order_id": "12345"}'
```

3. Wait a few seconds and check the queue depth:

```bash
awslocal sqs get-queue-attributes \
    --queue-url http://sqs.us-east-1.localhost.localstack.cloud:4566/000000000000/main-queue \
    --attribute-names ApproximateNumberOfMessages
```

The count should be 1 or more, confirming the message is not being consumed.

4. Apply the fix (delete old mapping, create new one pointing to `main-queue`), then send another message:

```bash
awslocal sqs send-message \
    --queue-url http://sqs.us-east-1.localhost.localstack.cloud:4566/000000000000/main-queue \
    --message-body '{"order_id": "99999"}'
```

5. Wait a few seconds and check the queue is empty:

```bash
sleep 5
awslocal sqs get-queue-attributes \
    --queue-url http://sqs.us-east-1.localhost.localstack.cloud:4566/000000000000/main-queue \
    --attribute-names ApproximateNumberOfMessages
```

6. Check Lambda logs to confirm the function was invoked:

```bash
awslocal logs filter-log-events --log-group-name /aws/lambda/sqs-processor
```

You should see log entries containing the message body with `order_id`.

## Common Mistakes

1. **Pointing the event source mapping to the DLQ instead of the main queue** - This is the exact bug in this exercise. Always verify the ARN in the event source mapping matches your intended source queue
2. **Trying to update the event source ARN in place** - AWS does not allow changing the `EventSourceArn` of an existing event source mapping. You must delete the old mapping and create a new one
3. **Forgetting to update the CloudFormation template** - Fixing the mapping via CLI resolves the immediate issue, but the template still has the bug. The next `create-stack` or `update-stack` will recreate the problem. Fix the template by changing `!GetAtt DeadLetterQueue.Arn` to `!GetAtt MainQueue.Arn` in the `SqsEventSourceMapping` resource
4. **Confusing the redrive policy DLQ with the event source** - The redrive policy on the main queue correctly points to the DLQ for failed messages, but that is a separate configuration from the event source mapping. Both can reference DLQ ARNs for different purposes
5. **Not checking the Lambda execution role permissions** - Even with the correct event source mapping, the Lambda role needs `sqs:ReceiveMessage`, `sqs:DeleteMessage`, and `sqs:GetQueueAttributes` permissions on the source queue
6. **Not waiting long enough for polling** - After creating a new event source mapping, Lambda may take a few seconds to start polling. Allow 5-10 seconds before concluding the fix did not work

## Additional Resources

- [AWS Lambda with Amazon SQS](https://docs.aws.amazon.com/lambda/latest/dg/with-sqs.html)
- [Amazon SQS Dead-Letter Queues](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-dead-letter-queues.html)
- [AWS Lambda Event Source Mapping](https://docs.aws.amazon.com/lambda/latest/dg/invocation-eventsourcemapping.html)
- [SQS Redrive Policy](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-configure-dead-letter-queue.html)
- [Troubleshooting Lambda with SQS](https://docs.aws.amazon.com/lambda/latest/dg/with-sqs.html#events-sqs-errors)
