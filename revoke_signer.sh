#!/bin/bash
# uncomment to debug the script
# set -x

VAULT_DATA=$(buildVaultAccessDetailsJSON "$VAULT_INSTANCE" "$IBMCLOUD_TARGET_REGION" "$IBMCLOUD_TARGET_RESOURCE_GROUP")
#write repo pem file to trust/private. Only repo key required to add delegate
export CURRENT_PATH=$(pwd)
JSON_REPO_DATA="$(readData "$REGISTRY_NAMESPACE.$IMAGE_NAME.repokeys" "$VAULT_DATA")"
repokey=$(getJSONValue "target" "$JSON_REPO_DATA")
writeFile "$repokey"

#retrieve public keys
PUBLIC_DATA="$(readData "$REGISTRY_NAMESPACE.pub" "$VAULT_DATA")"
publickey=$(getJSONValue "$DEVOPS_SIGNER" "$PUBLIC_DATA")
#write out/create the public key file to the system
writeFile "$publickey" "$CURRENT_PATH"
export DOCKER_CONTENT_TRUST_REPOSITORY_PASSPHRASE=$(getJSONValue "passphrase" "$repokey")
#docker trust signer remove prompts for confirmation
echo y | docker trust signer remove "$DEVOPS_SIGNER" "$GUN"
docker trust inspect --pretty $GUN