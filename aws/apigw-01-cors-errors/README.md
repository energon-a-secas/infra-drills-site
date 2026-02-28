## Problem

My REST API works perfectly from `curl` and Postman, but when I call it from a web page using JavaScript (`fetch` or `XMLHttpRequest`), the browser console shows:

```
Access to XMLHttpRequest at 'https://xxxxxxxxxx.execute-api.us-east-1.amazonaws.com/prod/items'
from origin 'http://localhost:3000' has been blocked by CORS policy:
No 'Access-Control-Allow-Origin' header is present on the requested resource.
```

I can confirm the API returns valid data:

```
awslocal apigateway get-rest-apis --query "items[?name=='cors-api'].id" --output text
```

```bash
# Replace <api-id> with the ID from above
curl -s http://localhost:4566/restapis/<api-id>/prod/_user_request_/items | jq
```

The JSON response comes back fine from the CLI, but the browser refuses to use it.

### Context
- A REST API was deployed via API Gateway with a single GET method on `/items`
- The GET method uses Lambda proxy integration
- The Lambda function returns a valid JSON body with `statusCode: 200`
- Calling the endpoint from `curl` or Postman works and returns data
- Calling the endpoint from a browser-based JavaScript application fails with a CORS error

### Hint
CORS (Cross-Origin Resource Sharing) is enforced by the browser, not the server. The server must explicitly allow cross-origin requests by returning specific headers. Check what headers the Lambda function returns in its response. Also check whether the API Gateway handles preflight `OPTIONS` requests, which browsers send automatically before certain cross-origin requests.

## Validation

Your solution should:
- Return the `Access-Control-Allow-Origin` header in the GET response
- Handle preflight OPTIONS requests properly

```bash
API_ID=$(awslocal apigateway get-rest-apis --query "items[?name=='cors-api'].id" --output text)

# Verify CORS headers are present in the GET response
curl -s -I http://localhost:4566/restapis/$API_ID/prod/_user_request_/items | grep -i "access-control-allow-origin"

# Verify OPTIONS preflight returns CORS headers
curl -s -I -X OPTIONS http://localhost:4566/restapis/$API_ID/prod/_user_request_/items | grep -i "access-control-allow"
```

The GET response should include `Access-Control-Allow-Origin` and the OPTIONS response should include `Access-Control-Allow-Origin`, `Access-Control-Allow-Methods`, and `Access-Control-Allow-Headers`.

## [Solution](../solutions/apigw-01-cors-errors.md)
