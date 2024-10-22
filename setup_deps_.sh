#!/bin/bash

# Run the Kurtosis command and capture its output
echo "Running Kurtosis command..."
KURTOSIS_OUTPUT=$(kurtosis run . --args-file network_params.yaml)

# Extract the Blockscout port
BLOCKSCOUT_PORT=$(echo "$KURTOSIS_OUTPUT" | grep -A 5 "^[a-f0-9]\+ *blockscout " | grep "http:" | sed -E 's/.*-> http:\/\/127\.0\.0\.1:([0-9]+).*/\1/' | head -n 1)

if [ -z "$BLOCKSCOUT_PORT" ]; then
    echo "Failed to extract Blockscout port."
    exit 1
fi

echo "Extracted Blockscout port: $BLOCKSCOUT_PORT"
echo "$BLOCKSCOUT_PORT" > /tmp/kurtosis_blockscout_port
echo "blockscout port: $BLOCKSCOUT_PORT"

# # Print the entire Kurtosis output for debugging
# echo "Kurtosis Output:"
# echo "$KURTOSIS_OUTPUT"

# Extract the "User Services" section
USER_SERVICES_SECTION=$(echo "$KURTOSIS_OUTPUT" | awk '/^========================================== User Services ==========================================/{flag=1;next}/^$/{flag=0}flag')
# Print the "User Services" section for debugging
# echo "User Services Section:"
# echo "$USER_SERVICES_SECTION"
# Extract the dynamic port assigned to the rpc service for "el-1-reth-lighthouse"
RPC_PORT=$(echo "$USER_SERVICES_SECTION" | grep -A 5 "el-1-reth-lighthouse" | grep "rpc: 8545/tcp" | sed -E 's/.* -> 127.0.0.1:([0-9]+).*/\1/')
if [ -z "$RPC_PORT" ]; then
    echo "Failed to extract RPC port from User Services section."
    exit 1
else
    echo "Extracted RPC port: $RPC_PORT"
    echo "$RPC_PORT" > /tmp/kurtosis_rpc_port
    echo "rpc port: $RPC_PORT" 
fi

# Extract the Starlark output section
STARLARK_OUTPUT=$(echo "$KURTOSIS_OUTPUT" | awk '/^Starlark code successfully run. Output was:/{flag=1; next} /^$/{flag=0} flag')

# Extract the beacon_http_url for cl-1-lighthouse-reth
BEACON_HTTP_URL=$(echo "$STARLARK_OUTPUT" | jq -r '.all_participants[] | select(.cl_context.beacon_service_name == "cl-1-lighthouse-reth") | .cl_context.beacon_http_url')

if [ -z "$BEACON_HTTP_URL" ]; then
    echo "Failed to extract beacon_http_url for cl-1-lighthouse-reth."
    exit 1
else
    echo "Extracted beacon_http_url: $BEACON_HTTP_URL"
    echo "$BEACON_HTTP_URL" > /tmp/kurtosis_beacon_http_url
    echo "beacon http url: $BEACON_HTTP_URL"
fi

# Find the correct Docker container
CONTAINER_ID=$(docker ps --format '{{.ID}} {{.Names}}' | grep 'el-1-reth-lighthouse--' | awk '{print $1}')

if [ -z "$CONTAINER_ID" ]; then
    echo "Failed to find the el-1-reth-lighthouse container."
    exit 1
else
    echo "Found container ID: $CONTAINER_ID"
fi

# Check if the file exists in the container
FILE_PATH="/app/rbuilder/config-gwyneth-reth.toml"
if ! docker exec "$CONTAINER_ID" test -f "$FILE_PATH"; then
    echo "File $FILE_PATH does not exist in the container."
    exit 1
fi

# Update the cl_node_url in the file, regardless of its current content
ESCAPED_URL=$(echo "$BEACON_HTTP_URL" | sed 's/[\/&]/\\&/g')
UPDATE_COMMAND="sed -i '/^cl_node_url[[:space:]]*=/c\cl_node_url = [\"$ESCAPED_URL\"]' $FILE_PATH"
if docker exec "$CONTAINER_ID" sh -c "$UPDATE_COMMAND"; then
    echo "Successfully updated $FILE_PATH in the container."
else
    echo "Failed to update $FILE_PATH in the container."
    exit 1
fi

# Verify the change
VERIFY_COMMAND="grep 'cl_node_url' $FILE_PATH"
VERIFICATION=$(docker exec "$CONTAINER_ID" sh -c "$VERIFY_COMMAND")
echo "Updated line in $FILE_PATH: $VERIFICATION"

# Load the .env file and extract the PRIVATE_KEY
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
    PRIVATE_KEY=${PRIVATE_KEY}
else
    echo ".env file not found. Please create a .env file with your PRIVATE_KEY."
    exit 1
fi
if [ -z "$PRIVATE_KEY" ]; then
    echo "PRIVATE_KEY not found in the .env file. $PRIVATE_KEY"
    exit 1
fi

echo 
