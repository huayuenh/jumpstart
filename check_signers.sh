#!/bin/bash
# uncomment to debug the script
# set -x
if [ -z "$REGISTRY_URL" ]; then
  # Use the ibmcloud cr info to find the target registry url 
  export REGISTRY_URL=$(ibmcloud cr info | grep -m1 -i '^Container Registry' | awk '{print $3;}')
fi
export REGISTRY_NAMESPACE=${REGISTRY_NAMESPACE:-'jumpstart'}
export IMAGE_NAME=${IMAGE_NAME:-'signed-hello-app'}

export GUN="$REGISTRY_URL/$REGISTRY_NAMESPACE/$IMAGE_NAME"
export DOCKER_CONTENT_TRUST_SERVER=${DOCKER_CONTENT_TRUST_SERVER:-"https://$REGISTRY_URL:4443"}
echo "DOCKER_CONTENT_TRUST_SERVER=$DOCKER_CONTENT_TRUST_SERVER"

# Notary Setup usage avec DCT
# https://github.com/theupdateframework/notary/blob/master/docs/command_reference.md#set-up-notary-cli

export DOCKER_CONTENT_TRUST_ROOT_PASSPHRASE=${DOCKER_CONTENT_TRUST_ROOT_PASSPHRASE:-"dctrootpassphrase"}
export DOCKER_CONTENT_TRUST_REPOSITORY_PASSPHRASE=${DOCKER_CONTENT_TRUST_REPOSITORY_PASSPHRASE:-"dctrepositorypassphrase"}

export NOTARY_ROOT_PASSPHRASE="$DOCKER_CONTENT_TRUST_ROOT_PASSPHRASE"
export NOTARY_TARGETS_PASSPHRASE="$DOCKER_CONTENT_TRUST_REPOSITORY_PASSPHRASE"
export NOTARY_SNAPSHOT_PASSPHRASE="$DOCKER_CONTENT_TRUST_REPOSITORY_PASSPHRASE"
export NOTARY_AUTH=$(echo -e "iamapikey:$IBM_CLOUD_API_KEY" | base64)
#remove the key from json
function findSigner {
    local SIGNER=$1
    local IMAGE_TAG=$2
    local GUN=$3
    trustData=$(docker trust inspect "$GUN")
    # Check if the Builder signature is present
    if jq -e ".[] | .SignedTags[] | select(.SignedTag=\"$IMAGE_TAG\") | select (.Signers[] | contains(\"$SIGNER\"))" <<<"$trustData"; then
        echo "$BUILD_SIGNER found"
        echo "true"
    else
        echo "$BUILD_SIGNER not found"
        echo "false"
    fi
}

function findTrustData {
    local GUN=$1
    trustData=$(docker trust inspect "$GUN")
    result=$(jq -e ".[]" <<<"$trustData")
    if [ "$result" ]; then
        echo "true"
    else
        echo "false"
    fi
}