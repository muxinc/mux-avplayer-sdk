#!/bin/bash

set -euo pipefail

if ! command -v saucectl &> /dev/null
then
    echo -e "\033[1;31m ERROR: saucectl could not be found please install it... \033[0m"
    exit 1
fi

if ! command -v jq &> /dev/null
then
    echo -e "\033[1;31m ERROR: jq could not be found please install it... \033[0m"
    exit 1
fi

readonly APPLICATION_NAME="MuxPlayerSwiftExample.ipa"
# TODO: make this an argument
readonly APPLICATION_PAYLOAD_PATH="Examples/MuxPlayerSwiftExample/${APPLICATION_NAME}"

if [ ! -f $APPLICATION_PAYLOAD_PATH ]; then
    echo -e "\033[1;31m ERROR: application archive not found \033[0m"
fi

# re-exported so saucectl CLI can use them
export SAUCE_USERNAME=$BUILDKITE_MAC_STADIUM_SAUCE_USERNAME
export SAUCE_ACCESS_KEY=$BUILDKITE_MAC_STADIUM_SAUCE_ACCESS_KEY

echo "▸ Uploading test application to Sauce Labs App Storage"

app_file_id=$(curl -s -u "$SAUCE_USERNAME:$SAUCE_ACCESS_KEY" --location --request POST 'https://api.us-west-1.saucelabs.com/v1/storage/upload' --form "payload=@\"${APPLICATION_PAYLOAD_PATH}\"" --form "name=\"${APPLICATION_NAME}\"" | jq -r '.item.id')

if [[ $? == 0 ]]; then
    echo "▸ Successfully uploaded to Sauce Labs application storage. File ID: $app_file_id"
else
    echo -e "\033[1;31m ERROR: Failed to upload to Sauce Labs application storage. Check for valid credentials. \033[0m"
    exit 1
fi

echo "▸ Deploying tests to Sauce Labs"

sed -i '' "s/${app_file_id}/INSERT-TEST-APP-FILE-ID-HERE/g" $PWD/.sauce/config.yml
sed -i '' "s/${app_file_id}/INSERT-APP-FILE-ID-HERE/g" $PWD/.sauce/config.yml

echo "▸ Sauce Labs config: $(cat $PWD/.sauce/config.yml)"

saucectl run -c "$PWD/.sauce/config.yml"

if [[ $? == 0 ]]; then
    echo "▸ Successfully deployed Sauce Labs tests"
else
    echo -e "\033[1;31m ERROR: Failed to deploy Sauce Labs tests \033[0m"
    exit 1
fi
