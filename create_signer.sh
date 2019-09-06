#!/bin/bash
# uncomment to debug the script
# set -x
if [ -z "$DOCKER_CONTENT_TRUST_REPOSITORY_PASSPHRASE" ]; then
    export DOCKER_CONTENT_TRUST_REPOSITORY_PASSPHRASE=$(openssl rand -base64 16)
fi

echo "Create  $DEVOPS_SIGNER singer key"
export DOCKER_CONTENT_TRUST=1
docker trust key generate "$DEVOPS_SIGNER"
echo "Restoring keys from $VAULT_INSTANCE"
VAULT_DATA=$(buildVaultAccessDetailsJSON "$VAULT_INSTANCE" "$IBMCLOUD_TARGET_REGION" "$IBMCLOUD_TARGET_RESOURCE_GROUP")
#write repo pem file to trust/private. Only repo key required to add delegate
JSON_DATA="$(readData "$REGISTRY_NAMESPACE.$IMAGE_NAME.keys" "$VAULT_DATA")"
JSON_PUB_DATA="$(readData "$REGISTRY_NAMESPACE.$IMAGE_NAME.pub" "$VAULT_DATA")"

# save the new signer pem key to the Vault
deleteSecret "$REGISTRY_NAMESPACE.$IMAGE_NAME.keys" "$VAULT_DATA"
deleteSecret "$REGISTRY_NAMESPACE.$IMAGE_NAME.pub" "$VAULT_DATA"

JSON_DATA=$(addTrustFileToJSON "$DEVOPS_SIGNER" "$JSON_DATA" "$DOCKER_CONTENT_TRUST_REPOSITORY_PASSPHRASE")
publicPem=$(base64TextEncode "./$DEVOPS_SIGNER.pub")
data=$(addJSONEntry "$data" "name" "$DEVOPS_SIGNER.pub")
data=$(addJSONEntry "$data" "value" "$publicPem")
JSON_PUB_DATA=$(addJSONEntry "$JSON_PUB_DATA" "$DEVOPS_SIGNER" "$data")

saveData "$REGISTRY_NAMESPACE.$IMAGE_NAME.keys" "$VAULT_DATA" "$JSON_DATA"
saveData "$REGISTRY_NAMESPACE.$IMAGE_NAME.pub" "$VAULT_DATA" "$JSON_PUB_DATA"