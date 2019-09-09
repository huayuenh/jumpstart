#!/bin/bash
# uncomment to debug the script
# set -x
if [ -z "$DOCKER_CONTENT_TRUST_REPOSITORY_PASSPHRASE" ]; then
    export DOCKER_CONTENT_TRUST_REPOSITORY_PASSPHRASE=$(openssl rand -base64 16)
fi

export DOCKER_CONTENT_TRUST=1

#set Vault access
VAULT_DATA=$(buildVaultAccessDetailsJSON "$VAULT_INSTANCE" "$IBMCLOUD_TARGET_REGION" "$IBMCLOUD_TARGET_RESOURCE_GROUP")

#retrieve existing keys from Vault
echo "Checking Key Protect Vault for keys"
echo "reading data"
JSON_PRIV_DATA="$(readData "$REGISTRY_NAMESPACE.keys" "$VAULT_DATA")"
JSON_PUB_DATA="$(readData "$REGISTRY_NAMESPACE.pub" "$VAULT_DATA")"

echo "extract data"
EXISTING_KEY="$(getJSONValue "$DEVOPS_SIGNER" "$JSON_PRIV_DATA")"

if [[ "$EXISTING_KEY" == "null" || -z "$EXISTING_KEY" ]]; then
    echo "Key for $DEVOPS_SIGNER not found."
    echo "Create  $DEVOPS_SIGNER singer key"
    docker trust key generate "$DEVOPS_SIGNER"
    # add new keys to json
    echo "start check"
    JSON_PRIV_DATA=$(addTrustFileToJSON "$DEVOPS_SIGNER" "$JSON_PRIV_DATA" "$DOCKER_CONTENT_TRUST_REPOSITORY_PASSPHRASE")
    base64PublicPem=$(base64TextEncode "./$DEVOPS_SIGNER.pub")
    publicKeyEntry=$(addJSONEntry "$publicKeyEntry" "name" "$DEVOPS_SIGNER.pub")
    publicKeyEntry=$(addJSONEntry "$publicKeyEntry" "value" "$base64PublicPem")
    JSON_PUB_DATA=$(addJSONEntry "$JSON_PUB_DATA" "$DEVOPS_SIGNER" "$publicKeyEntry")
    echo "end check"
    # delete old keys to allow for update
    if [ "$JSON_PRIV_DATA" ]; then
        echo "start delete"
        deleteSecret "$REGISTRY_NAMESPACE.keys" "$VAULT_DATA"
        deleteSecret "$REGISTRY_NAMESPACE.pub" "$VAULT_DATA"
        echo "end delete"
    fi

    #save public/private key pairs to the vault
    echo "start save"
    saveData "$REGISTRY_NAMESPACE.keys" "$VAULT_DATA" "$JSON_PRIV_DATA"
    saveData "$REGISTRY_NAMESPACE.pub" "$VAULT_DATA" "$JSON_PUB_DATA"
else
    echo "key for $DEVOPS_SIGNER already exists"
    echo "No op"
fi



