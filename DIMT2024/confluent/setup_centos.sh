#!/bin/bash

# Source the .env file
sleep_time=2
current_dir=$(pwd)
parent_dir=$(dirname "$current_dir")

env_file="${parent_dir}/.env"
resources_file="${parent_dir}/resources.json"

# Use confluent environment
sleep $sleep_time # Add sleep after installing jq
confluent login --save
export CCLOUD_ENV_ID=$(confluent environment list -o json \
    | jq -r '.[] | select(.name | contains("'"${CCLOUD_ENV_NAME:-Data_In_Motion_Tour}"'")) | .id')

confluent env use $CCLOUD_ENV_ID

# Use kafka cluster
export CCLOUD_CLUSTER_ID=$(confluent kafka cluster list -o json \
    | jq -r '.[] | select(.name | contains("'"${CCLOUD_CLUSTER_NAME:-dimt_kafka_cluster}"'")) | .id')

confluent kafka cluster use $CCLOUD_CLUSTER_ID

# Get cluster bootstrap endpoint
export CCLOUD_BOOTSTRAP_ENDPOINT=$(confluent kafka cluster describe -o json | jq -r .endpoint)
STRIPPED_CCLOUD_BOOTSTRAP_ENDPOINT=$(echo $CCLOUD_BOOTSTRAP_ENDPOINT | sed 's/SASL_SSL:\/\///')

# use awk to replace kafka-cluster-endpoint with the replacement string
awk -v var="$STRIPPED_CCLOUD_BOOTSTRAP_ENDPOINT" '{gsub("kafka-cluster-endpoint", var)}1' "$env_file" > temp && mv temp "$env_file"
sleep $sleep_time

# Create an API key pair to use for connectors
echo "Creating Kafka cluster API key"
CREDENTIALS=$(confluent api-key create --resource $CCLOUD_CLUSTER_ID --description "Data In Motion Tour 2024" -o json)
kafka_api_key=$(echo $CREDENTIALS | jq -r '.api_key')
kafka_api_secret=$(echo $CREDENTIALS | jq -r '.api_secret')
sleep $sleep_time

# use awk to replace all instances of $kafka_api_key with the replacement string
awk -v var="$kafka_api_key" '{gsub("api-key", "\"" var "\"")}1' "$env_file" > temp && mv temp "$env_file"
awk -v var="$kafka_api_secret" '{gsub("api-secret", "\"" var "\"")}1' "$env_file" > temp && mv temp "$env_file"

sleep $sleep_time

# Get schema registry info
export CCLOUD_SCHEMA_REGISTRY_ID=$(confluent sr cluster describe -o json | jq -r .cluster_id)
export CCLOUD_SCHEMA_REGISTRY_URL=$(confluent sr cluster describe -o json | jq -r .endpoint_url)

echo "Creating schema registry API key"
SR_CREDENTIALS=$(confluent api-key create --resource $CCLOUD_SCHEMA_REGISTRY_ID --description "Data In Motion Tour 2024" -o json)
sr_api_key=$(echo $SR_CREDENTIALS | jq -r '.api_key')
sr_api_secret=$(echo $SR_CREDENTIALS | jq -r '.api_secret')
sr_info="'$sr_api_key:$sr_api_secret'"
sleep $sleep_time

# use awk to replace all instances of $sr_api_key and $sr_api_secret with the replacement string
awk -v var="$CCLOUD_SCHEMA_REGISTRY_URL" '{gsub("schema-registry-url", var)}1' "$env_file" > temp && mv temp "$env_file"
awk -v var="$sr_info" '{gsub("sr-info", var)}1' "$env_file" > temp && mv temp "$env_file"
sleep $sleep_time

# Read values from resources.json and update the "$env_file" file.
# These resources are created by Terraform
json=$(cat "$resources_file")

mongodbatlas_connection_string=$(echo "$json" | jq -r '.mongodbatlas_connection_string.value'| sed 's/mongodb+srv:\/\///')

# Updating the "$env_file" file with awk command
awk -v var="$mongodbatlas_connection_string" '{gsub("mongodb-endpoint", var)}1' "$env_file" > temp && mv temp "$env_file"
