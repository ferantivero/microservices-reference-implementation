#!/bin/bash


echo "Gather environment variables from the infrastructure..."


export SSH_PUBLIC_KEY_FILE=$1
#echo "displaying the env vars....."
#env


az login --service-principal --username $SP_APP_ID --password $SP_CLIENT_SECRET --tenant $TENANT_ID >> /dev/null

echo "Logging in and setting the proper subscription..."
az account set --subscription $SUBSCRIPTION_ID

echo "Acquiring deployment values to continue the installation...."
export IDENTITIES_DEPLOYMENT_NAME=$(az deployment show -n azuredeploy-prereqs-dev --query properties.outputs.identitiesDeploymentName.value -o tsv) && \
export DELIVERY_ID_NAME=$(az group deployment show -g $RESOURCE_GROUP -n $IDENTITIES_DEPLOYMENT_NAME --query properties.outputs.deliveryIdName.value -o tsv) && \
export DELIVERY_ID_PRINCIPAL_ID=$(az identity show -g $RESOURCE_GROUP -n $DELIVERY_ID_NAME --query principalId -o tsv) && \
export DRONESCHEDULER_ID_NAME=$(az group deployment show -g $RESOURCE_GROUP -n $IDENTITIES_DEPLOYMENT_NAME --query properties.outputs.droneSchedulerIdName.value -o tsv) && \
export DRONESCHEDULER_ID_PRINCIPAL_ID=$(az identity show -g $RESOURCE_GROUP -n $DRONESCHEDULER_ID_NAME --query principalId -o tsv) && \
export WORKFLOW_ID_NAME=$(az group deployment show -g $RESOURCE_GROUP -n $IDENTITIES_DEPLOYMENT_NAME --query properties.outputs.workflowIdName.value -o tsv) && \
export WORKFLOW_ID_PRINCIPAL_ID=$(az identity show -g $RESOURCE_GROUP -n $WORKFLOW_ID_NAME --query principalId -o tsv) && \
export GATEWAY_CONTROLLER_ID_NAME=$(az group deployment show -g $RESOURCE_GROUP -n $IDENTITIES_DEPLOYMENT_NAME --query properties.outputs.appGatewayControllerIdName.value -o tsv) && \
export GATEWAY_CONTROLLER_ID_PRINCIPAL_ID=$(az identity show -g $RESOURCE_GROUP -n $GATEWAY_CONTROLLER_ID_NAME --query principalId -o tsv) && \
export RESOURCE_GROUP_ACR=$(az group deployment show -g $RESOURCE_GROUP -n $IDENTITIES_DEPLOYMENT_NAME --query properties.outputs.acrResourceGroupName.value -o tsv)



export KUBERNETES_VERSION=$(az aks get-versions -l $LOCATION --query "orchestrators[?default!=null].orchestratorVersion" -o tsv)
export SERVICETAGS_LOCATION=$(az account list-locations --query "[?name=='${LOCATION}'].displayName" -o tsv | sed 's/[[:space:]]//g')

echo "Understanding the networking environment..."
export VNET_NAME=$(az group deployment show -g $RESOURCE_GROUP -n azuredeploy-dev --query properties.outputs.aksVNetName.value -o tsv) && \
export CLUSTER_SUBNET_NAME=$(az group deployment show -g $RESOURCE_GROUP -n azuredeploy-dev --query properties.outputs.aksClusterSubnetName.value -o tsv) && \
export CLUSTER_SUBNET_PREFIX=$(az group deployment show -g $RESOURCE_GROUP -n azuredeploy-dev --query properties.outputs.aksClusterSubnetPrefix.value -o tsv) && \
export CLUSTER_NAME=$(az group deployment show -g $RESOURCE_GROUP -n azuredeploy-dev --query properties.outputs.aksClusterName.value -o tsv) && \
export CLUSTER_SERVER=$(az aks show -n $CLUSTER_NAME -g $RESOURCE_GROUP --query fqdn -o tsv) && \
export FIREWALL_PIP_NAME=$(az group deployment show -g $RESOURCE_GROUP -n azuredeploy-dev --query properties.outputs.firewallPublicIpName.value -o tsv) && \
export ACR_NAME=$(az group deployment show -g $RESOURCE_GROUP -n azuredeploy-dev --query properties.outputs.acrName.value -o tsv) && \
export ACR_SERVER=$(az acr show -n $ACR_NAME --query loginServer -o tsv) && \
export DELIVERY_REDIS_HOSTNAME=$(az group deployment show -g $RESOURCE_GROUP -n azuredeploy-dev --query properties.outputs.deliveryRedisHostName.value -o tsv)



export GATEWAY_SUBNET_PREFIX=$(az group deployment show -g $RESOURCE_GROUP -n azuredeploy-dev --query properties.outputs.appGatewaySubnetPrefix.value -o tsv)

#  Install kubectl no sudo in a container
#az aks install-cli

# Get the Kubernetes cluster credentials
az aks get-credentials --resource-group=$RESOURCE_GROUP --name=$CLUSTER_NAME

helm init --service-account tiller --client-only

# Acquire Instrumentation Key
export AI_NAME=$(az group deployment show -g $RESOURCE_GROUP -n azuredeploy-dev --query properties.outputs.appInsightsName.value -o tsv)
export AI_IKEY=$(az resource show \
                    -g $RESOURCE_GROUP \
                    -n $AI_NAME \
                    --resource-type "Microsoft.Insights/components" \
                    --query properties.InstrumentationKey \
                    -o tsv)

export GATEWAY_CONTROLLER_PRINCIPAL_RESOURCE_ID=$(az group deployment show -g $RESOURCE_GROUP -n $IDENTITIES_DEPLOYMENT_NAME --query properties.outputs.appGatewayControllerPrincipalResourceId.value -o tsv) && \
export GATEWAY_CONTROLLER_PRINCIPAL_CLIENT_ID=$(az identity show -g $RESOURCE_GROUP -n $GATEWAY_CONTROLLER_ID_NAME --query clientId -o tsv)
export APP_GATEWAY_NAME=$(az group deployment show -g $RESOURCE_GROUP -n azuredeploy-dev --query properties.outputs.appGatewayName.value -o tsv)
export APP_GATEWAY_PUBLIC_IP_FQDN=$(az group deployment show -g $RESOURCE_GROUP -n azuredeploy-dev --query properties.outputs.appGatewayPublicIpFqdn.value -o tsv)


export EXTERNAL_INGEST_FQDN=$APP_GATEWAY_PUBLIC_IP_FQDN

# Create a self-signed certificate for TLS
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -out ingestion-ingress-tls.crt \
    -keyout ingestion-ingress-tls.key \
    -subj "/CN=${APP_GATEWAY_PUBLIC_IP_FQDN}/O=fabrikam"

#================================ App building ====================================
echo "Delivery service....."
export DELIVERY_PATH=$PROJECT_ROOT/src/shipping/delivery

export COSMOSDB_NAME=$(az group deployment show -g $RESOURCE_GROUP -n azuredeploy-dev --query properties.outputs.deliveryCosmosDbName.value -o tsv) && \
export DATABASE_NAME="${COSMOSDB_NAME}-db" && \
export COLLECTION_NAME="${DATABASE_NAME}-col" && \
export DELIVERY_KEYVAULT_URI=$(az group deployment show -g $RESOURCE_GROUP -n azuredeploy-dev --query properties.outputs.deliveryKeyVaultUri.value -o tsv)

# depending on perms, you may need to log in first
echo "tag=$ACR_SERVER/delivery:0.1.0"
result=$(az acr repository show -n byem2kjldx646 --repository delivery --query '[registry, imageName]' -o tsv)
if [[ "$result" = "" ]]; then
    az acr build -t $ACR_SERVER/delivery:0.1.0 -r $ACR_NAME $DELIVERY_PATH/.
else
    echo "Found the image, moving to deployment...."
fi



# Deploying the delivery service
# Extract pod identity outputs from deployment
export DELIVERY_PRINCIPAL_RESOURCE_ID=$(az group deployment show -g $RESOURCE_GROUP -n $IDENTITIES_DEPLOYMENT_NAME --query properties.outputs.deliveryPrincipalResourceId.value -o tsv) && \
export DELIVERY_PRINCIPAL_CLIENT_ID=$(az identity show -g $RESOURCE_GROUP -n $DELIVERY_ID_NAME --query clientId -o tsv)
export DELIVERY_INGRESS_TLS_SECRET_NAME=delivery-ingress-tls

helm install $HELM_CHARTS/delivery/ \
     --set image.tag=0.1.0 \
     --set image.repository=delivery \
     --set dockerregistry=$ACR_SERVER \
     --set ingress.hosts[0].name=$EXTERNAL_INGEST_FQDN \
     --set ingress.hosts[0].serviceName=delivery \
     --set ingress.hosts[0].tls=true \
     --set ingress.hosts[0].tlsSecretName=$DELIVERY_INGRESS_TLS_SECRET_NAME \
     --set ingress.tls.secrets[0].name=$DELIVERY_INGRESS_TLS_SECRET_NAME \
     --set ingress.tls.secrets[0].key="$(cat ingestion-ingress-tls.key)" \
     --set ingress.tls.secrets[0].certificate="$(cat ingestion-ingress-tls.crt)" \
     --set networkPolicy.ingress.customSelectors.argSelector={ipBlock} \
     --set networkPolicy.ingress.customSelectors.argSelector[0].ipBlock.cidr=$GATEWAY_SUBNET_PREFIX \
     --set identity.clientid=$DELIVERY_PRINCIPAL_CLIENT_ID \
     --set identity.resourceid=$DELIVERY_PRINCIPAL_RESOURCE_ID \
     --set cosmosdb.id=$DATABASE_NAME \
     --set cosmosdb.collectionid=$COLLECTION_NAME \
     --set keyvault.uri=$DELIVERY_KEYVAULT_URI \
     --set reason="Initial deployment" \
     --set tags.dev=true \
     --namespace backend-dev \
     --name delivery-v0.1.0-dev \
     --dep-up


# Verify the pod is created
#helm status delivery-v0.1.0-dev


## Deploy the Package service

# Extract resource details from deployment
echo "Moving to deploy the "

export COSMOSDB_NAME=$(az group deployment show -g $RESOURCE_GROUP -n azuredeploy-dev --query properties.outputs.packageMongoDbName.value -o tsv)

export PACKAGE_PATH=$PROJECT_ROOT/src/shipping/package

echo "tag=$ACR_SERVER/package:0.1.0"

result=$(az acr repository show -n byem2kjldx646 --repository package --query '[registry, imageName]' -o tsv)
if [[ "$result" = "" ]]; then
    az acr build -t $ACR_SERVER/package:0.1.0 -r $ACR_NAME $PACKAGE_PATH/.
else
    echo "Found the image for package, moving to deploy...."
fi



# Create secret
# Note: Connection strings cannot be exported as outputs in ARM deployments
export COSMOSDB_CONNECTION=$(az cosmosdb list-connection-strings --name $COSMOSDB_NAME --resource-group $RESOURCE_GROUP --query "connectionStrings[0].connectionString" -o tsv | sed 's/==/%3D%3D/g') && \
export COSMOSDB_COL_NAME=packages

# Deploy service
helm install $HELM_CHARTS/package/ \
     --set image.tag=0.1.0 \
     --set image.repository=package \
     --set ingress.hosts[0].name=$EXTERNAL_INGEST_FQDN \
     --set ingress.hosts[0].serviceName=package \
     --set ingress.hosts[0].tls=false \
     --set secrets.appinsights.ikey=$AI_IKEY \
     --set secrets.mongo.pwd=$COSMOSDB_CONNECTION \
     --set cosmosDb.collectionName=$COSMOSDB_COL_NAME \
     --set dockerregistry=$ACR_SERVER \
     --set reason="Initial deployment" \
     --set tags.dev=true \
     --namespace backend-dev \
     --name package-v0.1.0-dev \
     --dep-up

# Deploy the workflow service

export WORKFLOW_KEYVAULT_NAME=$(az group deployment show -g $RESOURCE_GROUP -n azuredeploy-dev --query properties.outputs.workflowKeyVaultName.value -o tsv)

export WORKFLOW_PATH=$PROJECT_ROOT/src/shipping/workflow

# Build the Docker image

echo "tag=$ACR_SERVER/workflow:0.1.0"
result=$(az acr repository show -n byem2kjldx646 --repository workflow --query '[registry, imageName]' -o tsv)
if [[ "$result" = "" ]]; then
    az acr build -t $ACR_SERVER/workflow:0.1.0 -r $ACR_NAME $WORKFLOW_PATH/.
else
    echo "Found the image for workflow, moving to deploy...."
fi



echo "Create and set up pod identity for workflow...."


# Extract outputs from deployment
export WORKFLOW_PRINCIPAL_RESOURCE_ID=$(az group deployment show -g $RESOURCE_GROUP -n $IDENTITIES_DEPLOYMENT_NAME --query properties.outputs.workflowPrincipalResourceId.value -o tsv) && \
export WORKFLOW_PRINCIPAL_CLIENT_ID=$(az identity show -g $RESOURCE_GROUP -n $WORKFLOW_ID_NAME --query clientId -o tsv)

echo "Deploying the workflow service...."
# Deploy the service
helm install $HELM_CHARTS/workflow/ \
     --set image.tag=0.1.0 \
     --set image.repository=workflow \
     --set dockerregistry=$ACR_SERVER \
     --set identity.clientid=$WORKFLOW_PRINCIPAL_CLIENT_ID \
     --set identity.resourceid=$WORKFLOW_PRINCIPAL_RESOURCE_ID \
     --set keyvault.name=$WORKFLOW_KEYVAULT_NAME \
     --set keyvault.resourcegroup=$RESOURCE_GROUP \
     --set keyvault.subscriptionid=$SUBSCRIPTION_ID \
     --set keyvault.tenantid=$TENANT_ID \
     --set reason="Initial deployment" \
     --set tags.dev=true \
     --namespace backend-dev \
     --name workflow-v0.1.0-dev \
     --dep-up

echo "Deploy the Ingestion service..."


export INGESTION_QUEUE_NAMESPACE=$(az group deployment show -g $RESOURCE_GROUP -n azuredeploy-dev --query properties.outputs.ingestionQueueNamespace.value -o tsv) && \
export INGESTION_QUEUE_NAME=$(az group deployment show -g $RESOURCE_GROUP -n azuredeploy-dev --query properties.outputs.ingestionQueueName.value -o tsv)
export INGESTION_ACCESS_KEY_NAME=$(az group deployment show -g $RESOURCE_GROUP -n azuredeploy-dev --query properties.outputs.ingestionServiceAccessKeyName.value -o tsv)
export INGESTION_ACCESS_KEY_VALUE=$(az servicebus namespace authorization-rule keys list --resource-group $RESOURCE_GROUP --namespace-name $INGESTION_QUEUE_NAMESPACE --name $INGESTION_ACCESS_KEY_NAME --query primaryKey -o tsv)

echo "Build the Ingestion service..."

export INGESTION_PATH=$PROJECT_ROOT/src/shipping/ingestion

# Build the docker image
echo "tag=$ACR_SERVER/ingestion:0.1.0"
result=$(az acr repository show -n byem2kjldx646 --repository ingestion --query '[registry, imageName]' -o tsv)
if [[ "$result" = "" ]]; then
    az acr build -t $ACR_SERVER/ingestion:0.1.0 -r $ACR_NAME $INGESTION_PATH/.
else
    echo "Found the image for ingestion, moving to deploy...."
fi


echo "Deploy the Ingestion service...."


#Set secret name
export INGRESS_TLS_SECRET_NAME=ingestion-ingress-tls

# Deploy service
helm install $HELM_CHARTS/ingestion/ \
     --set image.tag=0.1.0 \
     --set image.repository=ingestion \
     --set dockerregistry=$ACR_SERVER \
     --set ingress.hosts[0].name=$EXTERNAL_INGEST_FQDN \
     --set ingress.hosts[0].serviceName=ingestion \
     --set ingress.hosts[0].tls=true \
     --set ingress.hosts[0].tlsSecretName=$INGRESS_TLS_SECRET_NAME \
     --set ingress.tls.secrets[0].name=$INGRESS_TLS_SECRET_NAME \
     --set ingress.tls.secrets[0].key="$(cat ingestion-ingress-tls.key)" \
     --set ingress.tls.secrets[0].certificate="$(cat ingestion-ingress-tls.crt)" \
     --set networkPolicy.ingress.customSelectors.argSelector={ipBlock} \
     --set networkPolicy.ingress.customSelectors.argSelector[0].ipBlock.cidr=$GATEWAY_SUBNET_PREFIX \
     --set secrets.appinsights.ikey=${AI_IKEY} \
     --set secrets.queue.keyname=IngestionServiceAccessKey \
     --set secrets.queue.keyvalue=${INGESTION_ACCESS_KEY_VALUE} \
     --set secrets.queue.name=${INGESTION_QUEUE_NAME} \
     --set secrets.queue.namespace=${INGESTION_QUEUE_NAMESPACE} \
     --set reason="Initial deployment" \
     --set tags.dev=true \
     --namespace backend-dev \
     --name ingestion-v0.1.0-dev \
     --dep-up

echo "Deploy DroneScheduler service...."

#Extract resource details from deployment

export DRONESCHEDULER_KEYVAULT_URI=$(az group deployment show -g $RESOURCE_GROUP -n azuredeploy-dev --query properties.outputs.droneSchedulerKeyVaultUri.value -o tsv)
export DRONESCHEDULER_COSMOSDB_NAME=$(az group deployment show -g $RESOURCE_GROUP -n azuredeploy-dev --query properties.outputs.droneSchedulerCosmosDbName.value -o tsv) && \
export ENDPOINT_URL=$(az cosmosdb show -n $DRONESCHEDULER_COSMOSDB_NAME -g $RESOURCE_GROUP --query documentEndpoint -o tsv) && \
export AUTH_KEY=$(az cosmosdb list-keys -n $DRONESCHEDULER_COSMOSDB_NAME -g $RESOURCE_GROUP --query primaryMasterKey -o tsv) && \
export DATABASE_NAME="invoicing" && \
export COLLECTION_NAME="utilization"

echo "Build the dronescheduler services...."


export DRONE_PATH=$PROJECT_ROOT/src/shipping/dronescheduler

# Build the docker image
echo "tag=$ACR_SERVER/dronescheduler:0.1.0"
result=$(az acr repository show -n byem2kjldx646 --repository dronescheduler --query '[registry, imageName]' -o tsv)
if [[ "$result" = "" ]]; then
    #az acr build -t byem2kjldx646.azurecr.io/dronescheduler:0.1.0 -r byem2kjldx646 .. -f ./Dockerfile
    az acr build -t $ACR_SERVER/dronescheduler:0.1.0 -r $ACR_NAME $DRONE_PATH/../ -f ./Dockerfile
else
    echo "Found the image for droneschedule, moving to deploy...."
fi


echo "Create and set up pod identity...."

# Extract outputs from deployment
export DRONESCHEDULER_PRINCIPAL_RESOURCE_ID=$(az group deployment show -g $RESOURCE_GROUP -n $IDENTITIES_DEPLOYMENT_NAME --query properties.outputs.droneSchedulerPrincipalResourceId.value -o tsv) && \
export DRONESCHEDULER_PRINCIPAL_CLIENT_ID=$(az identity show -g $RESOURCE_GROUP -n $DRONESCHEDULER_ID_NAME --query clientId -o tsv)

echo "Deploy the dronescheduler service..."

# Deploy the service
helm install $HELM_CHARTS/dronescheduler/ \
     --set image.tag=0.1.0 \
     --set image.repository=dronescheduler \
     --set dockerregistry=$ACR_SERVER \
     --set ingress.hosts[0].name=$EXTERNAL_INGEST_FQDN \
     --set ingress.hosts[0].serviceName=dronescheduler \
     --set ingress.hosts[0].tls=false \
     --set identity.clientid=$DRONESCHEDULER_PRINCIPAL_CLIENT_ID \
     --set identity.resourceid=$DRONESCHEDULER_PRINCIPAL_RESOURCE_ID \
     --set keyvault.uri=$DRONESCHEDULER_KEYVAULT_URI \
     --set cosmosdb.id=$DATABASE_NAME \
     --set cosmosdb.collectionid=$COLLECTION_NAME \
     --set reason="Initial deployment" \
     --set tags.dev=true \
     --namespace backend-dev \
     --name dronescheduler-v0.1.0-dev \
     --dep-up

### Send a request

echo "Validating the application is running...."

#Since the certificate used for TLS is self-signed, the request disables TLS validation using the '-k' option.

curl -X POST "https://$EXTERNAL_INGEST_FQDN/api/deliveryrequests" --header 'Content-Type: application/json' --header 'Accept: application/json' -k -i -d '{
   "confirmationRequired": "None",
   "deadline": "",
   "deliveryId": "mydelivery",
   "dropOffLocation": "drop off",
   "expedited": true,
   "ownerId": "myowner",
   "packageInfo": {
     "packageId": "mypackage",
     "size": "Small",
     "tag": "mytag",
     "weight": 10
   },
   "pickupLocation": "my pickup",
   "pickupTime": "2019-05-08T20:00:00.000Z"
 }'

echo  "Check the request status...."

curl "https://$EXTERNAL_INGEST_FQDN/api/deliveries/mydelivery" --header 'Accept: application/json' -k -i
