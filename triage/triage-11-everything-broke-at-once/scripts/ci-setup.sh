#!/bin/sh
# Shared CI setup, introduced by the "cleanup" MR.
# This runs as before_script for lint, test, and build.
set -e

echo "Configuring CI environment..."

# BUG: this line assumes the AWS CLI is present on the runner image.
# The node:20-alpine image does not ship the aws CLI, so every job that
# inherits this setup fails here with "aws: command not found" before
# its own script ever runs.
aws --version

echo "CI environment ready."
