#!/bin/bash
source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/secrets_management.sh")

#Assumes default Docker Trust location
#USE KEY PROTECT VAULT set value to 1
#USE HASHICORP set value to 0 -> not implemented
USE_KEY_PROTECT_VAULT=1
DOCKER_TRUST_DIRECTORY=~/.docker/trust/private
DOCKER_HOME_DIRECTORY=~/.docker
DOCKER_TRUST_HOME=~/.docker/trust

#Helper function to generate a JSON for storing
#the required data to construct a docker pem file
#Params
#name -> the name of the pem file
#value -> base64 encoding of the pem file data
function generateKeyValueJSON {
    local NAME=$1
    local VALUE=$2
    echo '{ "name" : "'$NAME'", "value": "'$VALUE'" }'
}

#Helper function to extract JSON values
function getJSONValue {
    local KEY=$1
    local JSON=$2
    echo $JSON| jq -r '.["'$KEY'"]'
}

#add or update key/value pair to json
function addJSONEntry {
    local json=$1
    #init json if null
    if [ -z "$json" ]
    then
        json="{}"
    fi
    local key=$2
    local value=$3
    echo $(jq --arg key "$key" --arg value "$value" '.[$key] = $value' <<<$json)
}

#remove the key from json
function removeJSONEntry {
    local json=$1
    local key=$2
    echo "$(jq --arg key $key 'del(.[$key])' <<<$json)"
}

#Params
#Role - the role to find in the pem file
#return json containing pem fail name and pem data in base64
function addTrustFileToJSON {
    local ROLE=$1
    local json=$2
    local passphrase=$3
    
    if [ -z "$json" ]
    then
        json="{}"
    fi

    #check all files in the dokcer trust
    for file in $DOCKER_TRUST_DIRECTORY/*
    do
        #Only need the pem file containing the specified role
        if grep -q "$ROLE" "$file"; then
        local filename=$(basename $file)
        local base64EncodedPem=$(base64TextEncode "$file")
        local data=$(addJSONEntry "$data" "name" "$filename")
        data=$(addJSONEntry "$data" "value" "$base64EncodedPem")
        if [ "$passphrase" ]; then
            data=$(addJSONEntry "$data" "passphrase" "$passphrase")
        fi
        json=$(addJSONEntry "$json" "$ROLE" "$data")
        echo "$json"
        #end loop once target role hase been found
        break
        fi
    done
}

#Store the required identifiers for the Key Protect Vault

function buildVaultAccessDetailsJSON {
    local NAME=$1
    local REGION=$2
    local RESOURCE_GROUP=$3
    echo '{"name" : "'$NAME'", "region" : "'$REGION'", "resourcegroup": "'$RESOURCE_GROUP'"}'
}

#Function to save the docker pem file to the Key protect
#KEY -> the key used in the Key Protect/Vault or other lookup
#JSON_DATA payload for the Vault store or other containing the pem file name and data
#VAULT_DATA data wrapper for values required for Vault access
function saveData {
    #name of the entry root, repokey, delegate etc. This represents the vault/store entry key
    local KEY=$1
    #Docker Trust keys are named with GUIDs. Name needs to be correctly associated with the pem data
    local JSON_DATA=$3
    #See buildVaultJSONDetails
    local VAULT_DATA=$2
   # if [$USE_KEY_PROTECT_VAULT -eq 1]; then
    local VAULT_NAME=$(getJSONValue "name" "$VAULT_DATA")
    local VAULT_REGION=$(getJSONValue "region" "$VAULT_DATA")
    local VAULT_RESOURCE_GROUP=$(getJSONValue "resourcegroup" "$VAULT_DATA")
    
    for (( i=0 ; i<5 ; i++ )); do
        if [[ "$VAULT_NAME" && "$VAULT_REGION" && "$VAULT_RESOURCE_GROUP" && "$KEY" && "$JSON_DATA" ]]; then
            local SECRET_GUID=$(
                save_secret \
                "$VAULT_NAME" \
                "$VAULT_REGION" \
                "$VAULT_RESOURCE_GROUP" \
                "$KEY" \
                "$JSON_DATA" \
            )
            if [ "$SECRET_GUID" ]; then
                break
            else
                sleep 0.5
            fi
        fi
    done
  #  else
    #TODO use hashicorp
   # echo "Hashicorp"
  #  fi
}

#
function savePemFileByRoleToVault {
    local role=$1
    local vault_key=$2
    local vault_data=$3
    local json_data=$(convertTrustFileToJSON "$role")
    echo $(saveData "$vault_key" "$vault_data" "$json_data" )
}

function savePemFileToVault {
    local filename=$1
    local vault_key=$2
    local vault_data=$3
    local base64EncodedPem=$(base64TextEncode "$filename")
    local payload=$(generateKeyValueJSON "$filename" "$base64EncodedPem")
    echo $(saveData "$vault_key" "$vault_data" "$payload" )
}

#Function to read the docker pem file data from secure storage
#KEY -> the look up key for teh storage
#VAULT_DATA the variable/json storing the required Vault details
function readData {
    local KEY=$1
    local VAULT_DATA=$2
    #if [$USE_KEY_PROTECT_VAULT -eq 1]; then
    local VAULT_NAME=$(getJSONValue "name" "$VAULT_DATA")
    local VAULT_REGION=$(getJSONValue "region" "$VAULT_DATA")
    local VAULT_RESOURCE_GROUP=$(getJSONValue "resourcegroup" "$VAULT_DATA")
     PASSWORD_SECRET=$(
        retrieve_secret \
          "$VAULT_NAME" \
          "$VAULT_REGION" \
          "$VAULT_RESOURCE_GROUP"  \
          "$KEY" \
      )
      echo "$PASSWORD_SECRET"
   # else
   #     echo "Hashicorp"
   # fi
}

function writeFile {
    local json_data=$1
    local file_name=$(getJSONValue "name" "$json_data")
    local file_data_base64=$(getJSONValue "value" "$json_data")
    local SAVEPATH=$2

    if [  -z "$SAVEPATH" ] 
    then
        SAVEPATH="$DOCKER_TRUST_DIRECTORY"
        echo "creating trust directory" 
        mkdir -p ~/.docker/trust
        mkdir -p ~/.docker/trust/private
    fi

    echo "$(base64TextDecode $file_data_base64)" >> "$SAVEPATH"/"$file_name"
    #pem files only valid in rw mode
    chmod -R 600 "$SAVEPATH"/"$file_name"
}

#this will store a map of the pem file name with the associated roles
#delegate public keys are not auto generated
function generateMap {
    # {
    #   "root": "id1.pem"
    #   "repository": "id2.pem"
    #    "dev-signer": "id3.pem"
    #}
    echo "PLACE HOLDER"
}

#Params
#Role - the role to find in the pem file
#return json containing pem fail name and pem data in base64
function convertTrustFileToJSON {
    local ROLE=$1
    #check all files in the dokcer trust
    for file in $DOCKER_TRUST_DIRECTORY/*
    do
        #Only need the pem file containing the specified role
        if grep -q "$ROLE" "$file"; then
        local filename=$(basename $file)
       local base64EncodedPem=$(base64TextEncode "$file")
       local payload=$(generateKeyValueJSON "$filename" "$base64EncodedPem")
        echo "$payload"
        #end loop once target role hase been found
        break
        fi
    done
}

#Params
#filepath - path to the file to encode
#returns encoded string
function base64TextEncode {
    local filepath=$1
    echo $(cat $filepath | base64 -w 0)
}

#Params
#base64TextData - raw base64 string to decode
#returns decoded string
function base64TextDecode {
    local base64TextData=$1
    echo $base64TextData | base64 -d #>> /Users/huayuenhui/.docker/trust/private/test.key
}

function deleteSecret {
    local KEY=$1
    local VAULT_DATA=$2
    local VAULT_NAME=$(getJSONValue "name" "$VAULT_DATA")
    local VAULT_REGION=$(getJSONValue "region" "$VAULT_DATA")
    local VAULT_RESOURCE_GROUP=$(getJSONValue "resourcegroup" "$VAULT_DATA")

    if [[ "$VAULT_NAME" && "$VAULT_REGION" && "$VAULT_RESOURCE_GROUP" && "$KEY" ]]; then
        DELETE_SECRET_RESPONSE=$(
            delete_secret \
            "$VAULT_NAME" \
            "$VAULT_REGION" \
            "$VAULT_RESOURCE_GROUP" \
            "$KEY"
        )
        echo "DELETE_SECRET_RESPONSE=${DELETE_SECRET_RESPONSE}"
    fi
}

function deleteVault {
    local VAULT_DATA=$1
    local VAULT_NAME=$(getJSONValue "name" "$VAULT_DATA")
    local VAULT_REGION=$(getJSONValue "region" "$VAULT_DATA")
    local VAULT_RESOURCE_GROUP=$(getJSONValue "resourcegroup" "$VAULT_DATA")
    DELETE_VAULT_RESPONSE=$(
        delete_vault_instance \
          "$VAULT_NAME" \
          "$VAULT_REGION" \
          "$VAULT_RESOURCE_GROUP"
      )
      echo "DELETE_VAULT_RESPONSE=${DELETE_VAULT_RESPONSE}"
}

function createSigner {

    if [ -z "$DOCKER_CONTENT_TRUST_REPOSITORY_PASSPHRASE" ]; then
        export DOCKER_CONTENT_TRUST_REPOSITORY_PASSPHRASE=$(openssl rand -base64 16)
    fi

    export DOCKER_CONTENT_TRUST=1

    #set Vault access
    VAULT_DATA=$(buildVaultAccessDetailsJSON "$VAULT_INSTANCE" "$IBMCLOUD_TARGET_REGION" "$IBMCLOUD_TARGET_RESOURCE_GROUP")

    #retrieve existing keys from Vault
    echo "Checking Key Protect Vault for keys"
    JSON_PRIV_DATA="$(readData "$REGISTRY_NAMESPACE.keys" "$VAULT_DATA")"
    JSON_PUB_DATA="$(readData "$REGISTRY_NAMESPACE.pub" "$VAULT_DATA")"
    EXISTING_KEY="$(getJSONValue "$DEVOPS_SIGNER" "$JSON_PRIV_DATA")"
    if [[ "$EXISTING_KEY" == "null" || -z "$EXISTING_KEY" ]]; then
        echo "Key for $DEVOPS_SIGNER not found."
        echo "Create  $DEVOPS_SIGNER singer key"
        docker trust key generate "$DEVOPS_SIGNER"
        # add new keys to json
        JSON_PRIV_DATA=$(addTrustFileToJSON "$DEVOPS_SIGNER" "$JSON_PRIV_DATA" "$DOCKER_CONTENT_TRUST_REPOSITORY_PASSPHRASE")
        base64PublicPem=$(base64TextEncode "./$DEVOPS_SIGNER.pub")
        publicKeyEntry=$(addJSONEntry "$publicKeyEntry" "name" "$DEVOPS_SIGNER.pub")
        publicKeyEntry=$(addJSONEntry "$publicKeyEntry" "value" "$base64PublicPem")
        JSON_PUB_DATA=$(addJSONEntry "$JSON_PUB_DATA" "$DEVOPS_SIGNER" "$publicKeyEntry")
    
    
        # delete old keys to allow for update
        if [ "$JSON_PRIV_DATA" ]; then
            deleteSecret "$REGISTRY_NAMESPACE.keys" "$VAULT_DATA"
            deleteSecret "$REGISTRY_NAMESPACE.pub" "$VAULT_DATA"
        fi

        #save public/private key pairs to the vault
        saveData "$REGISTRY_NAMESPACE.keys" "$VAULT_DATA" "$JSON_PRIV_DATA"
        saveData "$REGISTRY_NAMESPACE.pub" "$VAULT_DATA" "$JSON_PUB_DATA"
    else
        echo "key for $DEVOPS_SIGNER already exists"
        echo "No op"
    fi
}

function deleteSigner {
    export DOCKER_CONTENT_TRUST=1

    #set Vault access
    VAULT_DATA=$(buildVaultAccessDetailsJSON "$VAULT_INSTANCE" "$IBMCLOUD_TARGET_REGION" "$IBMCLOUD_TARGET_RESOURCE_GROUP")

    #retrieve existing keys from Vault
    echo "Checking Key Protect Vault for keys"
    JSON_PRIV_DATA="$(readData "$REGISTRY_NAMESPACE.keys" "$VAULT_DATA")"
    JSON_PUB_DATA="$(readData "$REGISTRY_NAMESPACE.pub" "$VAULT_DATA")"
    EXISTING_KEY="$(getJSONValue "$DEVOPS_SIGNER" "$JSON_PRIV_DATA")"

    if [ "$EXISTING_KEY" ]; then
        echo "Key for $DEVOPS_SIGNER  found."
        echo "Removing  $DEVOPS_SIGNER singer key"
        # add new keys to json
        JSON_PRIV_DATA=$(removeJSONEntry "$JSON_PRIV_DATA" "$DEVOPS_SIGNER")
        JSON_PUB_DATA=$(removeJSONEntry "$JSON_PUB_DATA" "$DEVOPS_SIGNER")
        # delete old keys to allow for update
        if [ "$JSON_PRIV_DATA" ]; then
            deleteSecret "$REGISTRY_NAMESPACE.keys" "$VAULT_DATA"
            deleteSecret "$REGISTRY_NAMESPACE.pub" "$VAULT_DATA"
        fi

        #save public/private key pairs to the vault
        saveData "$REGISTRY_NAMESPACE.keys" "$VAULT_DATA" "$JSON_PRIV_DATA"
        saveData "$REGISTRY_NAMESPACE.pub" "$VAULT_DATA" "$JSON_PUB_DATA"
    else
        echo "key for $DEVOPS_SIGNER already exists"
        echo "No op"
    fi
}

#remove the key from json
function findSigner {
    local SIGNER=$1
    local IMAGE_TAG=$2
    local GUN=$3
    if [ -z "$REGISTRY_URL" ]; then
    # Use the ibmcloud cr info to find the target registry url 
    export REGISTRY_URL=$(ibmcloud cr info | grep -m1 -i '^Container Registry' | awk '{print $3;}')
    fi

    export GUN="$REGISTRY_URL/$REGISTRY_NAMESPACE/$IMAGE_NAME"
    export DOCKER_CONTENT_TRUST_SERVER=${DOCKER_CONTENT_TRUST_SERVER:-"https://$REGISTRY_URL:4443"}
    echo "DOCKER_CONTENT_TRUST_SERVER=$DOCKER_CONTENT_TRUST_SERVER"
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
    if [ -z "$REGISTRY_URL" ]; then
    # Use the ibmcloud cr info to find the target registry url 
    export REGISTRY_URL=$(ibmcloud cr info | grep -m1 -i '^Container Registry' | awk '{print $3;}')
    fi

    export GUN="$REGISTRY_URL/$REGISTRY_NAMESPACE/$IMAGE_NAME"
    export DOCKER_CONTENT_TRUST_SERVER=${DOCKER_CONTENT_TRUST_SERVER:-"https://$REGISTRY_URL:4443"}
    echo "DOCKER_CONTENT_TRUST_SERVER=$DOCKER_CONTENT_TRUST_SERVER"
    trustData=$(docker trust inspect "$GUN")
    result=$(jq -e ".[]" <<<"$trustData")
    if [ "$result" ]; then
        echo "true"
    else
        echo "false"
    fi
}

function revokeSigner {
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
}

function signImage {
    #Requires
    #VAULT_INSTANCE -name of vault
    # $IBMCLOUD_TARGET_REGION -region hosting Key Protect Vault instance
    # $IBMCLOUD_TARGET_RESOURCE_GROUP of the Key Protect Vault Instance
    # REGISTRY_NAMESPACE namespace of registry
    # $IMAGE_NAME
    # $IMAGE_TAG
    # $DEVOPS_SIGNER
    export DOCKER_CONTENT_TRUST=1
    echo "Vault instance $VAULT_INSTANCE used to retrieve signing keys"
    source <(curl -sSL "https://raw.githubusercontent.com/jauninb/jumpstart/master/signatures.sh")
    # Restore signer pem key
    VAULT_DATA=$(buildVaultAccessDetailsJSON "$VAULT_INSTANCE" "$IBMCLOUD_TARGET_REGION" "$IBMCLOUD_TARGET_RESOURCE_GROUP")
    JSON_DATA="$(readData "$REGISTRY_NAMESPACE.keys" "$VAULT_DATA")"
    signerkey=$(getJSONValue "$DEVOPS_SIGNER" "$JSON_DATA")
    writeFile "$signerkey"
    # Retrieve the signer passphrase
    export DOCKER_CONTENT_TRUST_REPOSITORY_PASSPHRASE=$(getJSONValue "passphrase" "$signerkey")

    export DCT_DISABLED=false
    # Pull the image
    docker pull "$REGISTRY_URL/$REGISTRY_NAMESPACE/$IMAGE_NAME:$IMAGE_TAG"
    # Sign the image
    docker trust sign "$REGISTRY_URL/$REGISTRY_NAMESPACE/$IMAGE_NAME:$IMAGE_TAG"
    docker trust inspect --pretty "$REGISTRY_URL/$REGISTRY_NAMESPACE/$IMAGE_NAME"
}

function addSigner {
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
    docker trust signer add --key "${DEVOPS_SIGNER}.pub" "$DEVOPS_SIGNER" "$GUN"
    docker trust inspect --pretty $GUN

    export DEVOPS_SIGNER=${DEVOPS_SIGNER:-"devops"}
    export DEVOPS_SIGNER_PRIVATE_KEY=$(docker trust inspect $GUN | jq -r --arg GUN "$GUN" --arg DEVOPS_SIGNER "$DEVOPS_SIGNER" '.[] | select(.name=$GUN) | .Signers[] | select(.Name=$DEVOPS_SIGNER) | .Keys[0].ID')

    # If $ARCHIVE_DIR then create the tar file containing certificates/keys created during initialization
    # https://docs.docker.com/engine/security/trust/trust_key_mng/#back-up-your-keys , add public key
    # and specific information for DCT initialization
    if [[ "$ARCHIVE_DIR" ]]; then
        mkdir -p $ARCHIVE_DIR
        # keep the signer ids
        docker trust inspect $GUN | jq -r --arg GUN "$GUN" --arg DEVOPS_SIGNER "$DEVOPS_SIGNER" '.[] | select(.name=$GUN) | .Signers' > $ARCHIVE_DIR/dct_signers.json
        # keep the signed registry context
        echo "GUN=$GUN" > $ARCHIVE_DIR/dct.properties
        echo "REGISTRY_URL=${REGISTRY_URL}" >> $ARCHIVE_DIR/dct.properties
        echo "REGISTRY_REGION=${REGISTRY_REGION}" >> $ARCHIVE_DIR/dct.properties
        echo "REGISTRY_NAMESPACE=${REGISTRY_NAMESPACE}" >> $ARCHIVE_DIR/dct.properties
        echo "IMAGE_NAME=${IMAGE_NAME}" >> $ARCHIVE_DIR/dct.properties
        echo "DOCKER_CONTENT_TRUST_SERVER=$DOCKER_CONTENT_TRUST_SERVER" >> $ARCHIVE_DIR/dct.properties
        # public key of signer are kept in archive as needed for CISE configuration for instance
        cp *.pub $ARCHIVE_DIR

        # if no vault is configured, keep the passphrase and backup the keys in the archive
        # https://docs.docker.com/engine/security/trust/trust_key_mng/#back-up-your-keys
        if [ -z "$VAULT_INSTANCE" ]; then
        echo "No Vault instance defined - backing-up the keys in $ARCHIVE_DIR directory"
        echo "DOCKER_CONTENT_TRUST_ROOT_PASSPHRASE=$DOCKER_CONTENT_TRUST_ROOT_PASSPHRASE" >> $ARCHIVE_DIR/dct.properties
        echo "DOCKER_CONTENT_TRUST_REPOSITORY_PASSPHRASE=$DOCKER_CONTENT_TRUST_REPOSITORY_PASSPHRASE" >> $ARCHIVE_DIR/dct.properties
        umask 077; tar -zcvf $ARCHIVE_DIR/private_keys_backup.tar.gz --directory ~ .docker/trust/private; umask 022
        else
        echo "Vault instance $VAULT_INSTANCE defined - it would be used for the key backup"
        fi
    fi
}