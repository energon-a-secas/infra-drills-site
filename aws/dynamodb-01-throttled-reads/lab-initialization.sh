#!/bin/bash
set -e

echo "Creating CloudFormation stack..."
awslocal cloudformation create-stack \
    --stack-name dynamodb-throttled-reads \
    --template-body file://template.yaml

echo "Waiting for stack creation to complete..."
awslocal cloudformation wait stack-create-complete \
    --stack-name dynamodb-throttled-reads

echo "Seeding 20 items into product-catalog table..."
for i in $(seq -w 1 20); do
    awslocal dynamodb put-item \
        --table-name product-catalog \
        --item "{
            \"product_id\": {\"S\": \"prod-0${i}\"},
            \"name\": {\"S\": \"Product ${i}\"},
            \"category\": {\"S\": \"category-$(( (10#$i % 5) + 1 ))\"},
            \"price\": {\"N\": \"$(( (RANDOM % 9900) + 100 ))\"},
            \"in_stock\": {\"BOOL\": true},
            \"description\": {\"S\": \"This is the description for product number ${i} in the catalog.\"}
        }"
    echo "  Inserted prod-0${i}"
done

echo ""
echo "Lab initialization complete."
echo "Table 'product-catalog' has 20 items and is provisioned with 1 RCU / 5 WCU."
echo ""
echo "Try running a batch-get-item to observe the throttling issue."
