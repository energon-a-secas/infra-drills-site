# Lambda Timeout Configuration Solution

## The Issue

The Lambda function `http-checker` is configured with a timeout of only 3 seconds. The function makes an HTTP GET request to an external URL, which can easily take longer than 3 seconds to complete (DNS resolution, TLS handshake, connection establishment, and response transfer). When the function exceeds its timeout, Lambda forcefully terminates it and returns a `Task timed out` error.

## Solution

Increase the Lambda function's timeout to allow enough time for the HTTP request to complete:

```bash
awslocal lambda update-function-configuration \
    --function-name http-checker \
    --timeout 30
```

Then invoke the function again to verify it works:

```bash
awslocal lambda invoke --function-name http-checker --payload '{}' /tmp/response.json && cat /tmp/response.json
```

## Understanding Lambda Timeouts

AWS Lambda allows you to configure the maximum execution time for a function. Key points:

- **Minimum timeout**: 1 second
- **Maximum timeout**: 900 seconds (15 minutes)
- **Default timeout**: 3 seconds (when not explicitly set)
- The timeout includes all initialization time (cold start), execution, and cleanup
- If a function exceeds its timeout, Lambda terminates the execution immediately and returns a timeout error
- You are billed for the actual execution time, not the configured timeout

When a function makes external HTTP calls, network latency can vary significantly. A 3-second timeout is often too tight for:
- DNS resolution (especially first call)
- TLS handshake negotiation
- Slow or distant endpoints
- Cold start overhead in the Lambda runtime itself

A good rule of thumb is to set the Lambda timeout to at least 2-3x the expected execution time, with some buffer for cold starts and network variability.

## Testing

1. First, check the current timeout configuration:

```bash
awslocal lambda get-function-configuration --function-name http-checker
```

Look for the `"Timeout": 3` field in the output.

2. Invoke the function to confirm the timeout error:

```bash
awslocal lambda invoke --function-name http-checker --payload '{}' /tmp/response.json && cat /tmp/response.json
```

3. Increase the timeout:

```bash
awslocal lambda update-function-configuration \
    --function-name http-checker \
    --timeout 30
```

4. Verify the configuration was updated:

```bash
awslocal lambda get-function-configuration --function-name http-checker
```

Confirm `"Timeout": 30` is now shown.

5. Invoke the function again to confirm it succeeds:

```bash
awslocal lambda invoke --function-name http-checker --payload '{}' /tmp/response.json && cat /tmp/response.json
```

You should see a successful response with an HTTP status code:

```json
{
    "statusCode": 200,
    "body": "{\"message\": \"HTTP request successful\", \"url\": \"https://aws.amazon.com\", \"status\": 200}"
}
```

## Common Mistakes

1. **Setting the timeout too low** - The default 3 seconds is rarely enough for functions that make external API calls or database queries
2. **Setting the timeout too high unnecessarily** - While it does not increase cost (you pay for actual execution time), an excessively high timeout can mask performance issues and delay error detection
3. **Not accounting for cold starts** - A Lambda function's first invocation takes longer due to runtime initialization; the timeout must cover this additional time
4. **Confusing Lambda timeout with HTTP client timeout** - The function code sets `urllib.request.urlopen(req, timeout=10)`, meaning the HTTP client waits up to 10 seconds, but if the Lambda timeout is only 3 seconds, it gets killed before the HTTP timeout can even take effect
5. **Forgetting to update the CloudFormation template** - Fixing the timeout via CLI works for immediate resolution, but the template should also be updated to prevent the issue from recurring on the next stack deployment

## Additional Resources

- [AWS Lambda Function Configuration](https://docs.aws.amazon.com/lambda/latest/dg/configuration-function-common.html)
- [AWS Lambda Execution Environment](https://docs.aws.amazon.com/lambda/latest/dg/lambda-runtime-environment.html)
- [Best Practices for Lambda Timeouts](https://docs.aws.amazon.com/lambda/latest/dg/best-practices.html)
- [AWS Lambda Quotas](https://docs.aws.amazon.com/lambda/latest/dg/gettingstarted-limits.html)
