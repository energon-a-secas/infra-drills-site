# API Gateway CORS Errors Solution

## The Issue

The API has two problems that together cause CORS failures in the browser:

1. **The Lambda function does not return CORS headers.** With Lambda proxy integration, API Gateway passes the Lambda response directly to the client. If the Lambda response does not include headers like `Access-Control-Allow-Origin`, the browser will block the response because it violates the same-origin policy.

2. **No OPTIONS method is configured on the API resource.** Before making certain cross-origin requests (those with custom headers, non-simple methods, etc.), browsers send a preflight `OPTIONS` request to check whether the server allows the actual request. Without an OPTIONS method, the preflight request returns an error, and the browser never sends the actual GET request.

Both issues must be fixed for cross-origin requests to work from a browser.

## Solution

### Step 1: Fix the Lambda function to return CORS headers

Update the Lambda function code to include CORS headers in the response:

```bash
awslocal lambda update-function-code \
    --function-name cors-items-function \
    --zip-file fileb://<(cat <<'PYEOF' | python3 -c "
import zipfile, io, sys
buf = io.BytesIO()
with zipfile.ZipFile(buf, 'w') as zf:
    zf.writestr('index.py', sys.stdin.read())
sys.stdout.buffer.write(buf.getvalue())
" > /tmp/cors-fix.zip && echo /tmp/cors-fix.zip)
PYEOF
```

Alternatively, use the simpler approach of updating the function code inline. Create a file called `index.py`:

```python
import json

def handler(event, context):
    items = [
        {"id": 1, "name": "Widget A", "price": 9.99},
        {"id": 2, "name": "Widget B", "price": 14.99},
        {"id": 3, "name": "Widget C", "price": 19.99}
    ]

    return {
        "statusCode": 200,
        "headers": {
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "GET,OPTIONS",
            "Access-Control-Allow-Headers": "Content-Type,Authorization"
        },
        "body": json.dumps({"items": items})
    }
```

Then zip and update:

```bash
cd /tmp && cat > index.py << 'EOF'
import json

def handler(event, context):
    items = [
        {"id": 1, "name": "Widget A", "price": 9.99},
        {"id": 2, "name": "Widget B", "price": 14.99},
        {"id": 3, "name": "Widget C", "price": 19.99}
    ]

    return {
        "statusCode": 200,
        "headers": {
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "GET,OPTIONS",
            "Access-Control-Allow-Headers": "Content-Type,Authorization"
        },
        "body": json.dumps({"items": items})
    }
EOF

zip -j /tmp/cors-fix.zip /tmp/index.py

awslocal lambda update-function-code \
    --function-name cors-items-function \
    --zip-file fileb:///tmp/cors-fix.zip
```

### Step 2: Add an OPTIONS method to the API Gateway resource

Get the API and resource IDs:

```bash
API_ID=$(awslocal apigateway get-rest-apis --query "items[?name=='cors-api'].id" --output text)
RESOURCE_ID=$(awslocal apigateway get-resources --rest-api-id $API_ID --query "items[?pathPart=='items'].id" --output text)
```

Create the OPTIONS method with a MOCK integration:

```bash
# Create the OPTIONS method
awslocal apigateway put-method \
    --rest-api-id $API_ID \
    --resource-id $RESOURCE_ID \
    --http-method OPTIONS \
    --authorization-type NONE

# Set up MOCK integration
awslocal apigateway put-integration \
    --rest-api-id $API_ID \
    --resource-id $RESOURCE_ID \
    --http-method OPTIONS \
    --type MOCK \
    --request-templates '{"application/json": "{\"statusCode\": 200}"}'

# Configure the method response with CORS headers
awslocal apigateway put-method-response \
    --rest-api-id $API_ID \
    --resource-id $RESOURCE_ID \
    --http-method OPTIONS \
    --status-code 200 \
    --response-parameters '{"method.response.header.Access-Control-Allow-Headers":true,"method.response.header.Access-Control-Allow-Methods":true,"method.response.header.Access-Control-Allow-Origin":true}'

# Configure the integration response to return CORS header values
awslocal apigateway put-integration-response \
    --rest-api-id $API_ID \
    --resource-id $RESOURCE_ID \
    --http-method OPTIONS \
    --status-code 200 \
    --response-parameters '{"method.response.header.Access-Control-Allow-Headers":"'"'"'Content-Type,Authorization'"'"'","method.response.header.Access-Control-Allow-Methods":"'"'"'GET,OPTIONS'"'"'","method.response.header.Access-Control-Allow-Origin":"'"'"'*'"'"'"}'
```

### Step 3: Redeploy the API

```bash
awslocal apigateway create-deployment \
    --rest-api-id $API_ID \
    --stage-name prod
```

### Step 4: Verify the fix

```bash
# Test the GET endpoint for CORS headers
curl -s -I http://localhost:4566/restapis/$API_ID/prod/_user_request_/items | grep -i "access-control"

# Test the OPTIONS preflight
curl -s -I -X OPTIONS http://localhost:4566/restapis/$API_ID/prod/_user_request_/items | grep -i "access-control"
```

## Understanding CORS

### What is CORS?

CORS (Cross-Origin Resource Sharing) is a browser security mechanism that restricts web pages from making requests to a different domain (origin) than the one that served the page. An origin is defined by the combination of protocol, domain, and port (e.g., `http://localhost:3000`).

Key points:

- **CORS is enforced by the browser, not the server.** The server simply returns headers; the browser decides whether to allow or block the response. This is why `curl` and Postman work fine -- they do not enforce CORS.
- **The server must opt in to cross-origin requests** by returning the `Access-Control-Allow-Origin` header with a value that matches the requesting origin (or `*` to allow any origin).

### Simple Requests vs. Preflighted Requests

Browsers classify cross-origin requests into two categories:

**Simple requests** are sent directly without a preflight. A request is "simple" if it meets all of these conditions:
- Method is GET, HEAD, or POST
- Only uses headers: Accept, Accept-Language, Content-Language, Content-Type (with values `application/x-www-form-urlencoded`, `multipart/form-data`, or `text/plain`)

**Preflighted requests** require the browser to first send an OPTIONS request to the server to check whether the actual request is allowed. The preflight happens when:
- The request uses methods like PUT, DELETE, or PATCH
- The request includes custom headers (e.g., `Authorization`, `X-Custom-Header`)
- The Content-Type is `application/json`

### The CORS Headers

| Header | Purpose |
|--------|---------|
| `Access-Control-Allow-Origin` | Specifies which origins can access the resource (`*` for any) |
| `Access-Control-Allow-Methods` | Specifies which HTTP methods are allowed |
| `Access-Control-Allow-Headers` | Specifies which request headers are allowed |
| `Access-Control-Max-Age` | How long (in seconds) the preflight result can be cached |
| `Access-Control-Allow-Credentials` | Whether the request can include credentials (cookies, auth headers) |

### Lambda Proxy Integration and CORS

With Lambda proxy integration, API Gateway passes the entire request to Lambda and returns the Lambda response directly to the client. This means:

- **Lambda is responsible for returning CORS headers** in the `headers` field of its response object
- API Gateway does NOT automatically add CORS headers in proxy mode
- Both the actual response (GET, POST, etc.) AND the OPTIONS preflight must return CORS headers

This differs from non-proxy integration, where API Gateway can be configured to add response headers via method responses and integration responses.

## Testing

1. Deploy the broken stack:

```bash
awslocal cloudformation create-stack --stack-name apigw-cors-errors --template-body file://template.yaml
```

2. Get the API ID and test the endpoint:

```bash
API_ID=$(awslocal apigateway get-rest-apis --query "items[?name=='cors-api'].id" --output text)

# This works (no CORS enforcement from curl)
curl -s http://localhost:4566/restapis/$API_ID/prod/_user_request_/items | jq

# Check for CORS headers (they will be missing)
curl -s -I http://localhost:4566/restapis/$API_ID/prod/_user_request_/items | grep -i "access-control"
```

3. Apply the Lambda fix and OPTIONS method fix (see Solution steps above).

4. Redeploy and verify:

```bash
awslocal apigateway create-deployment --rest-api-id $API_ID --stage-name prod

# CORS headers should now appear
curl -s -I http://localhost:4566/restapis/$API_ID/prod/_user_request_/items | grep -i "access-control"
curl -s -I -X OPTIONS http://localhost:4566/restapis/$API_ID/prod/_user_request_/items | grep -i "access-control"
```

## Common Mistakes

1. **Thinking CORS is a server-side security block** - CORS is enforced entirely by the browser. The server returns headers that tell the browser what to allow. Tools like `curl` ignore CORS entirely, which is why the API "works" from the CLI but not from a web page.

2. **Only fixing the Lambda function OR the API Gateway, but not both** - With Lambda proxy integration, the Lambda function must return CORS headers in its response for the actual request (GET, POST, etc.). But the API Gateway also needs an OPTIONS method to handle the preflight request. Fixing only one side leaves the other broken.

3. **Using wildcard `*` for `Access-Control-Allow-Origin` in production** - While `*` is convenient for development, it allows any website to call your API. In production, set this to the specific origin(s) that should have access (e.g., `https://myapp.example.com`). This is especially important when `Access-Control-Allow-Credentials` is set to `true`, as `*` is not allowed in that case.

4. **Forgetting to redeploy the API** - API Gateway changes (like adding an OPTIONS method) do not take effect until the API is deployed to a stage. After making changes, always create a new deployment.

5. **Confusing proxy integration with non-proxy integration** - In non-proxy (custom) integration, you can configure CORS headers at the API Gateway level via method responses and integration responses. In proxy integration, the Lambda function must return the headers itself. Many CORS tutorials assume non-proxy integration, which leads to confusion.

6. **Not handling CORS for error responses** - If the Lambda function throws an error or returns a 4xx/5xx status code without CORS headers, the browser will block the error response too. Ensure CORS headers are included in all responses, including error responses.

## Additional Resources

- [AWS API Gateway CORS Documentation](https://docs.aws.amazon.com/apigateway/latest/developerguide/how-to-cors.html)
- [MDN Web Docs: CORS](https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS)
- [MDN Web Docs: Preflight Request](https://developer.mozilla.org/en-US/docs/Glossary/Preflight_request)
- [AWS Lambda Proxy Integration](https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-lambda-proxy-integrations.html)
- [Enabling CORS for a REST API Resource](https://docs.aws.amazon.com/apigateway/latest/developerguide/how-to-cors-console.html)
- [LocalStack API Gateway Support](https://docs.localstack.cloud/user-guide/aws/apigateway/)
