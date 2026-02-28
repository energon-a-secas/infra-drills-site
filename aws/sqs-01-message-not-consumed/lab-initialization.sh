awslocal cloudformation create-stack \
        --stack-name sqs-message-not-consumed \
        --template-body file://template.yaml
