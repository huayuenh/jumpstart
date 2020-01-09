#!/bin/bash
echo "TEST IMPORT SCRIPT"
# Get the notary binary
#curl -L https://github.com/theupdateframework/notary/releases/download/v0.6.1/notary-Linux-amd64 -o /usr/local/bin/notary
# Make it executable
chmod +x /usr/local/bin/notary

export IBMCLOUD_API_KEY=$IBM_CLOUD_API_KEY
export DOCKER_CONTENT_TRUST=1

# Setup Docker-In-Docker
source <(curl -s -S -L "https://raw.githubusercontent.com/jauninb/jumpstart/master/setup_dind.sh")

# configure the container registry
echo "REGISTRY REGION $REGISTRY_REGION"
export REGISTRY_REGION=$(echo "$REGISTRY_REGION" | awk -F ':' '{print $NF;}')
ibmcloud cr region-set $REGISTRY_REGION
echo "REGISTRY REGION $REGISTRY_REGION"

# login docker to ibm container registry
ibmcloud cr login

# check the existence of the container registry namespace
REGISTRY_URL=$(ibmcloud cr info | grep -m1 -i '^Container Registry' | awk '{print $3;}')
echo "Check for $REGISTRY_NAMESPACE existence"
if ibmcloud cr namespaces | tail --lines=+4 | head --lines=-2 | grep "^$REGISTRY_NAMESPACE"; then
echo "$REGISTRY_NAMESPACE exists in $REGISTRY_URL"
else
echo "Creating REGISTRY_NAMESPACE in $REGISTRY_URL"
ibmcloud cr namespace-add $REGISTRY_NAMESPACE
fi

export GUN="$REGISTRY_URL/$REGISTRY_NAMESPACE/$IMAGE_NAME"
source <(curl -s -S -L "https://raw.githubusercontent.com/huayuenh/jumpstart/master/check_signers.sh")
source <(curl -sSL "https://raw.githubusercontent.com/huayuenh/jumpstart/master/signatures.sh")
if [ $(findTrustData "$GUN") == "false" ]; then
echo "NO TRUST DATA FOUND"
# Initialize the repository for Docker Content Trust
# Generate passphrase for root and repository keys
# see https://docs.docker.com/engine/security/trust/trust_key_mng/#choose-a-passphrase
if [ -z "$DOCKER_CONTENT_TRUST_ROOT_PASSPHRASE" ]; then
    export DOCKER_CONTENT_TRUST_ROOT_PASSPHRASE=$(openssl rand -base64 16)
fi
if [ -z "$DOCKER_CONTENT_TRUST_REPOSITORY_PASSPHRASE" ]; then
    export DOCKER_CONTENT_TRUST_REPOSITORY_PASSPHRASE=$(openssl rand -base64 16)
fi
echo "Doing Docker Content Trust initialization for GUN $REGISTRY_URL/$REGISTRY_NAMESPACE/$IMAGE_NAME"
source <(curl -s -S -L "https://raw.githubusercontent.com/jauninb/jumpstart/master/notary_init_gun.sh")


echo "Backing-up keys in $VAULT_INSTANCE"
# jsonify the Vault access values
VAULT_DATA=$(buildVaultAccessDetailsJSON "$VAULT_INSTANCE" "$IBMCLOUD_TARGET_REGION" "$IBMCLOUD_TARGET_RESOURCE_GROUP")
JSON_DATA="$(readData "$REGISTRY_NAMESPACE.$IMAGE_NAME.keys" "$VAULT_DATA")"
#save the root, repo pem key files to the Vault
JSON_ROOT_DATA=$(addTrustFileToJSON "root" "$JSON_ROOT_DATA" "$DOCKER_CONTENT_TRUST_ROOT_PASSPHRASE")
JSON_ROOT_DATA=$(addTrustFileToJSON "target" "$JSON_ROOT_DATA" "$DOCKER_CONTENT_TRUST_REPOSITORY_PASSPHRASE")
deleteSecret "$REGISTRY_NAMESPACE.$IMAGE_NAME.repokeys" "$VAULT_DATA"
saveData "$REGISTRY_NAMESPACE.$IMAGE_NAME.repokeys" "$VAULT_DATA" "$JSON_ROOT_DATA"
else
#
echo "No op"

fi


echo "Create signer $DEVOPS_SIGNER for $REGISTRY_URL/$REGISTRY_NAMESPACE/$IMAGE_NAME"
echo "IMAGE TAG $IMAGE_TAG"
echo "Building signer list"
signerList=("$DEVOPS_BUILD_SIGNER" "$DEVOPS_VALIDATION_SIGNER")
for i in "${signerList[@]}"; do
echo "RUNNING ADD SCRIPT FOR $i";
DEVOPS_SIGNER=$i
# Restore root & repository keys
echo "Restoring keys from $VAULT_INSTANCE"
source <(curl -sSL "https://raw.githubusercontent.com/huayuenh/jumpstart/master/add_signer.sh")
done