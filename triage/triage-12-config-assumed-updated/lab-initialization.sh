#!/bin/bash
# Triage 12: Config assumed updated, but the app reads a stale value.
#
# The application reads its endpoint from SSM parameter:
#     /payments/charge/endpoint   (singular)
#
# During the migration, Ops "updated the endpoint" — but they ran the update
# against a typo'd path:
#     /payments/charge/endpoints  (plural)
#
# So an update DID happen and DID succeed ("the change went through"), just on
# the wrong parameter. The parameter the app actually reads still points at the
# decommissioned v1 host. The team's assumption ("the config is updated") is
# true for the wrong key and false for the one that matters.

AWS_COMMAND=awslocal

# The parameter the application actually reads — still holds the OLD host.
$AWS_COMMAND ssm put-parameter \
  --name /payments/charge/endpoint \
  --type String \
  --value "https://api.payments-v1.internal/charge" \
  --overwrite >/dev/null

# The parameter Ops updated by mistake (typo: plural "endpoints") — has the NEW host.
$AWS_COMMAND ssm put-parameter \
  --name /payments/charge/endpoints \
  --type String \
  --value "https://api.payments-v2.internal/charge" \
  --overwrite >/dev/null

echo ""
echo "Lab initialized."
echo "  App reads parameter: /payments/charge/endpoint"
echo ""
echo "Ticket says: 'Ops updated the endpoint, so this must be a network issue.'"
echo "The parameter update is an assumption. Verify what the app actually reads."
echo ""
echo "Try:"
echo "  awslocal ssm get-parameter --name /payments/charge/endpoint --query 'Parameter.Value' --output text"
