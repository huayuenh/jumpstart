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
    if [ "$JSON" ]; then
        echo $JSON| jq -r '.["'$KEY'"]'
    fi
}

#add or update key/value pair to json
function addJSONEntry {
    local JSON=$1
    #init json if null
    if [ -z "$JSON" ]
    then
        JSON="{}"
    fi
    local KEY=$2
    local VALUE=$3
    if [[ "$KEY" && "$VALUE" ]]; then
        echo $(jq --arg key "$KEY" --arg value "$VALUE" '.[$KEY] = $VALUE' <<<$JSON)
    else
        echo "$JSON"
    fi
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
    if [[ "$VAULT_NAME" && "$VAULT_REGION" && "$VAULT_RESOURCE_GROUP" && "$KEY" && "$JSON_DATA" ]]; then
        SECRET_GUID=$(
            save_secret \
            "$VAULT_NAME" \
            "$VAULT_REGION" \
            "$VAULT_RESOURCE_GROUP" \
            "$KEY" \
            "$JSON_DATA" \
        )
        echo "SAVE SUCCESSFUL SECRET_GUID=${SECRET_GUID}"
    fi
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
    if [[ "$VAULT_NAME" && "$VAULT_REGION" && "$VAULT_RESOURCE_GROUP" && "$KEY" ]]; then
        PASSWORD_SECRET=$(
            retrieve_secret \
            "$VAULT_NAME" \
            "$VAULT_NAME" \
            "$VAULT_RESOURCE_GROUP"  \
            "$KEY" \
        )
        echo "$PASSWORD_SECRET"
    fi
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
        mkdir ~/.docker/trust
        mkdir ~/.docker/trust/private
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