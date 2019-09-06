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
#retrieve existing keys from Vault
JSON_PRIV_DATA="$(readData "$REGISTRY_NAMESPACE.keys" "$VAULT_DATA")"
JSON_PUB_DATA="$(readData "$REGISTRY_NAMESPACE.pub" "$VAULT_DATA")"

# delete old keys to allow for update
if [ "$JSON_PRIV_DATA" ]; then
    deleteSecret "$REGISTRY_NAMESPACE.keys" "$VAULT_DATA"
fi
if [ "$JSON_PUB_DATA" ]; then
    deleteSecret "$REGISTRY_NAMESPACE.pub" "$VAULT_DATA"
fi

# add new keys to json
JSON_PRIV_DATA=$(addTrustFileToJSON "$DEVOPS_SIGNER" "$JSON_PRIV_DATA" "$DOCKER_CONTENT_TRUST_REPOSITORY_PASSPHRASE")
base64PublicPem=$(base64TextEncode "./$DEVOPS_SIGNER.pub")
publicKeyEntry=$(addJSONEntry "$publicKeyEntry" "name" "$DEVOPS_SIGNER.pub")
publicKeyEntry=$(addJSONEntry "$publicKeyEntry" "value" "$base64PublicPem")
JSON_PUB_DATA=$(addJSONEntry "$JSON_PUB_DATA" "$DEVOPS_SIGNER" "$publicKeyEntry")

#save public/private key pairs to the vault
saveData "$REGISTRY_NAMESPACE.keys" "$VAULT_DATA" "$JSON_PRIV_DATA"
saveData "$REGISTRY_NAMESPACE.pub" "$VAULT_DATA" "$JSON_PUB_DATA"