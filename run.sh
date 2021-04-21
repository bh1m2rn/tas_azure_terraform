#!/bin/bash

az cloud set --name AzureCloud

echo "Log in with your VMware AD account on your browser"
az login

read -p 'Please enter the Opsman exact version and build. 
You can find that info here https://network.pivotal.io/products/ops-manager/#/releases (Example: 2.9.11-build.186). : ' OPSMAN_VERSION
read -p 'Please enter the TAS version you would like to install: ' TAS_VERSION
read -p 'Please enter your Pivnet API refresh token. If you do NOT have one: Log into pivnet > edit profile > request new refresh token). ' REFRESH_TOKEN
read -p 'Which is your preferred location? (eastus or westus): ' TF_VAR_location
read -p 'Please enter a unique name for your resource group - all lowercase (Example: jsmith): ' RESOURCE_GROUP
read -sp 'Please enter a new password for Opsman: ' OPSMAN_PASSWORD
echo ''

# I am hardcoding these values but feel free to create your own dns zone.
export TF_VAR_domain="used4testing.xyz"
export TF_VAR_dns_zone="dns_jlarrea"

# Other variables that need to be exported for Terraform to consume
export TF_VAR_resource_group_name=$RESOURCE_GROUP 
export TF_VAR_location
export TF_VAR_opsman_image_url="https://opsmanager$TF_VAR_location.blob.core.windows.net/images/ops-manager-$OPSMAN_VERSION.vhd"
export TF_VAR_sp_identifier="http://BoshAzure$RESOURCE_GROUP"


# Create a keypair
if [ -d "$HOME/.ssh/azurekeys" ]; then
    echo "Key pair already exists"
else
    echo "Creating a key pair in ~/.ssh/azurekeys"
    mkdir -p ~/.ssh/azurekeys
    ssh-keygen -t rsa -f ~/.ssh/azurekeys/opsman -C ubuntu -N ""
fi

terraform init
terraform plan -out tas.tfplan
terraform apply "tas.tfplan"

source next-step.txt 
rm next-step.txt 

sleep 60

opsman_authentication_setup()
{
  cat <<EOF
{
    "setup": {
    "decryption_passphrase": "$OPSMAN_PASSWORD",
    "decryption_passphrase_confirmation": "$OPSMAN_PASSWORD",
    "eula_accepted": "true",
    "identity_provider": "internal",
    "admin_user_name": "admin",
    "admin_password": "$OPSMAN_PASSWORD",
    "admin_password_confirmation": "$OPSMAN_PASSWORD"
    }
}
EOF
}

echo "Setting up Opsman authentication..."
curl -k -X POST -H "Content-Type: application/json" -d "$(opsman_authentication_setup)" "https://$OPSMAN_URL/api/v0/setup"

sleep 60

uaa target https://$OPSMAN_URL/uaa --skip-ssl-validation
uaa get-password-token opsman -u admin -s "" -p $OPSMAN_PASSWORD
OPSMAN_TOKEN=$(uaa context | jq -r ".Token.access_token")

director_newconfig()
{
  cat <<EOF
{
  "director_configuration": {
    "ntp_servers_string": "ntp.ubuntu.com",
    "resurrector_enabled": false,
    "director_hostname": null,
    "max_threads": null,
    "custom_ssh_banner": null,
    "metrics_server_enabled": true,
    "system_metrics_runtime_enabled": true,
    "opentsdb_ip": null,
    "director_worker_count": 5,
    "post_deploy_enabled": false,
    "bosh_recreate_on_next_deploy": false,
    "bosh_director_recreate_on_next_deploy": false,
    "bosh_recreate_persistent_disks_on_next_deploy": false,
    "retry_bosh_deploys": false,
    "keep_unreachable_vms": false,
    "identification_tags": {},
    "skip_director_drain": false,
    "job_configuration_on_tmpfs": false,
    "nats_max_payload_mb": null,
    "database_type": "internal",
    "blobstore_type": "local",
    "local_blobstore_options": {
      "enable_signed_urls": true
    },
    "hm_pager_duty_options": {
      "enabled": false
    },
    "hm_emailer_options": {
      "enabled": false
    },
    "encryption": {
      "keys": [],
      "providers": []
    }
  },
  "dns_configuration": {
    "excluded_recursors": [],
    "recursor_selection": null,
    "recursor_timeout": null,
    "handlers": []
  },
  "security_configuration": {
    "trusted_certificates": null,
    "generate_vm_passwords": true,
    "opsmanager_root_ca_trusted_certs": false
  },
  "syslog_configuration": {
    "enabled": false
  },
  "iaas_configuration": {
    "name": "default",
    "additional_cloud_properties": {},
    "subscription_id": "$SUBSCRIPTION_ID",
    "tenant_id": "$TENANT_ID",
    "client_id": "$TF_VAR_sp_identifier",
    "client_secret": "$SP_SECRET",
    "resource_group_name": "$RESOURCE_GROUP",
    "bosh_storage_account_name": "$STORAGE_NAME",
    "cloud_storage_type": "managed_disks",
    "storage_account_type": "Premium_LRS",
    "default_security_group": null,
    "deployed_cloud_storage_type": null,
    "deployments_storage_account_name": null,
    "ssh_public_key": "$(cat ~/.ssh/azurekeys/opsman.pub)",
    "ssh_private_key": "$(cat ~/.ssh/azurekeys/opsman | tr -d '\n')",
    "environment": "AzureCloud",
    "availability_mode": "availability_zones"
  }
}
EOF
}

echo "Configuring bosh director..."
curl -k -X PUT -H "Content-Type: application/json" -H "Authorization: Bearer $OPSMAN_TOKEN" -d "$(director_newconfig)" "https://$OPSMAN_URL/api/v0/staged/director/properties"

networks_config()
{
  cat <<EOF
{
    "icmp_checks_enabled": false,
    "networks": [
      {
        "guid": null,
        "name": "infrastructure",
        "subnets": [
          {
            "guid": null,
            "iaas_identifier": "tas-virtual-network/tas-infrastructure",
            "cidr": "10.0.4.0/26",
            "dns": "168.63.129.16",
            "gateway": "10.0.4.1",
            "reserved_ip_ranges": "10.0.4.1-10.0.4.9"
          }
        ]
      },
      {
        "guid": null,
        "name": "tas",
        "subnets": [
          {
            "guid": null,
            "iaas_identifier": "tas-virtual-network/tas-runtime",
            "cidr": "10.0.12.0/22",
            "dns": "168.63.129.16",
            "gateway": "10.0.12.1",
            "reserved_ip_ranges": "10.0.12.1-10.0.12.9"
          }
        ]
      }, 
      {
        "guid": null,
        "name": "services",
        "subnets": [
          {
            "guid": null,
            "iaas_identifier": "tas-virtual-network/tas-services",
            "cidr": "10.0.8.0/22",
            "dns": "168.63.129.16",
            "gateway": "10.0.8.1",
            "reserved_ip_ranges": "10.0.8.1-10.0.8.9"
          }
        ]
      } 
    ]
  }
EOF
}

curl -k -X PUT -H "Content-Type: application/json" -H "Authorization: Bearer $OPSMAN_TOKEN" -d "$(networks_config)" "https://$OPSMAN_URL/api/v0/staged/director/networks"

az_singleton()
{
  cat <<EOF
{
  "network_and_az": {
    "network": {
      "name": "infrastructure"
    },
    "singleton_availability_zone": {
      "name": "zone-1"
    }
  }
}
EOF
}

curl -k -X PUT -H "Content-Type: application/json" -H "Authorization: Bearer $OPSMAN_TOKEN" -d "$(az_singleton)" "https://$OPSMAN_URL/api/v0/staged/director/network_and_az"

echo "Retrieving Tanzu Network access token..."
generate_pivnet_token()
{
cat <<EOF
{"refresh_token":"$REFRESH_TOKEN"}
EOF
}

PIVNET_TOKEN=$(curl -sX POST https://network.pivotal.io/api/v2/authentication/access_tokens -d "$(generate_pivnet_token)" | jq -r '.access_token')

echo "Creating a product download link..."
RELEASE_ID=$(curl -sX GET https://network.pivotal.io/api/v2/products/elastic-runtime/releases -H "Authorization: Bearer $PIVNET_TOKEN" |jq -r --arg TAS_VERSION "$TAS_VERSION" '.[] | .[] | select(.version==$TAS_VERSION) | .id')

PRODUCT_FILE_URL=$(curl -sX GET "https://network.pivotal.io/api/v2/products/elastic-runtime/releases/$RELEASE_ID/product_files" -H "Authorization: Bearer $PIVNET_TOKEN" | jq -r '.[] | .[] | select(.name=="Pivotal Application Service") | ._links.download.href')

echo "Downloading TAS..."
DOWNLOAD_LINK=$(curl -sX GET $PRODUCT_FILE_URL -H "Authorization: Bearer $PIVNET_TOKEN" | awk '{ print substr ($0, 36, length($0) - 66 ) }' | sed 's/amp;//g')

ssh -q -o StrictHostKeyChecking=no -i ~/.ssh/azurekeys/opsman ubuntu@$OPSMAN_URL "cat << EOF > /home/ubuntu/download_tas.sh 
curl -X GET '$DOWNLOAD_LINK' -o tas-tile.pivotal
EOF"

ssh -q -o StrictHostKeyChecking=no -i ~/.ssh/azurekeys/opsman ubuntu@$OPSMAN_URL 'bash /home/ubuntu/download_tas.sh'

echo "Uploading TAS to Opsman...this could take a while..."
ssh -q -o StrictHostKeyChecking=no -i ~/.ssh/azurekeys/opsman ubuntu@$OPSMAN_URL "curl -k "https://$OPSMAN_URL/api/v0/available_products" -X POST -H 'Authorization: Bearer $OPSMAN_TOKEN' -F 'product[file]=@/home/ubuntu/tas-tile.pivotal'"

echo "TAS upload completed..."


stage_product()
{
  cat <<EOF
{"name": "cf",
"product_version": "$TAS_VERSION"}
EOF
}

echo "Staging TAS..."
curl -k -X POST -H "Content-Type: application/json" -H "Authorization: Bearer $OPSMAN_TOKEN" -d "$(stage_product)" "https://$OPSMAN_URL/api/v0/staged/products"

echo "Downloading Stemcell..."
STEMCELL_ID=$(curl -sX GET "https://network.pivotal.io/api/v2/products/elastic-runtime/releases/$RELEASE_ID/dependencies" -H "Authorization: Bearer $PIVNET_TOKEN" | jq -r '.[] | .[] | .[] | select(.product.slug=="stemcells-ubuntu-xenial") | .id' 2>/dev/null | sed 1q)

STEMCELL_VERSION=$(curl -sX GET "https://network.pivotal.io/api/v2/products/elastic-runtime/releases/$RELEASE_ID/dependencies" -H "Authorization: Bearer $PIVNET_TOKEN" | jq -r '.[] | .[] | .[] | select(.product.slug=="stemcells-ubuntu-xenial") | .version' 2>/dev/null | sed 1q)

STEMCELL_PRODUCT_URL=$(curl -sX GET "https://network.pivotal.io/api/v2/products/stemcells-ubuntu-xenial/releases/$STEMCELL_ID/product_files" -H "Authorization: Bearer $PIVNET_TOKEN" | jq -r '.[] | .[] | select(.name | contains("Azure") ) | ._links.download.href' 2>/dev/null)

STEMCELL_DOWNLOAD_LINK=$(curl -sX GET $STEMCELL_PRODUCT_URL -H "Authorization: Bearer $PIVNET_TOKEN" | awk '{ print substr ($0, 36, length($0) - 66 ) }' | sed 's/amp;//g')

ssh -q -o StrictHostKeyChecking=no -i ~/.ssh/azurekeys/opsman ubuntu@$OPSMAN_URL "cat << EOF > /home/ubuntu/download_stemcell.sh 
curl -O -J -X GET '$STEMCELL_DOWNLOAD_LINK'
EOF"

ssh -q -o StrictHostKeyChecking=no -i ~/.ssh/azurekeys/opsman ubuntu@$OPSMAN_URL 'bash /home/ubuntu/download_stemcell.sh'

echo "Uploading Stemcell to Opsman..."

ssh -q -o StrictHostKeyChecking=no -i ~/.ssh/azurekeys/opsman ubuntu@$OPSMAN_URL "curl -k "https://$OPSMAN_URL/api/v0/stemcells" -X POST -H 'Authorization: Bearer $OPSMAN_TOKEN' -F 'stemcell[file]=@/home/ubuntu/bosh-stemcell-$STEMCELL_VERSION-azure-hyperv-ubuntu-xenial-go_agent.tgz' -F 'stemcell[floating]=false'"

echo "Stemcell upload completed..."

CF_GUID=$(curl -k -X GET https://$OPSMAN_URL/api/v0/staged/products -H "Authorization: Bearer $OPSMAN_TOKEN" | jq -r '.[] | select(.type=="cf") | .guid')

associate_stemcell()
{
  cat <<EOF
{
  "products": [
    {
      "guid": "$CF_GUID",
      "staged_stemcells": [
        {
          "os": "ubuntu-xenial",
          "version": "$STEMCELL_VERSION"
        }
      ]
    }
  ]
}
EOF
}

curl -k -X PATCH -H "Content-Type: application/json" -H "Authorization: Bearer $OPSMAN_TOKEN" -d "$(associate_stemcell)" "https://$OPSMAN_URL/api/v0/stemcell_associations"

echo "Stemcell associated with TAS..."

echo "Configuring TAS..."

export OM_VAR_apps_domain="apps.$RESOURCE_GROUP.$TF_VAR_domain"
export OM_VAR_sys_domain="sys.$RESOURCE_GROUP.$TF_VAR_domain"

export OM_VAR_opsman_ca_cert=$(curl -sk -X GET -H "Content-Type: application/json" -H "Authorization: Bearer $OPSMAN_TOKEN" "https://$OPSMAN_URL/api/v0/certificate_authorities" | jq -r '.[] | .[].cert_pem')

CERT_DOMAINS="*.$RESOURCE_GROUP.$TF_VAR_domain,*.apps.$RESOURCE_GROUP.$TF_VAR_domain,*.sys.$RESOURCE_GROUP.$TF_VAR_domain,*.login.sys.$RESOURCE_GROUP.$TF_VAR_domain,*.uaa.sys.$RESOURCE_GROUP.$TF_VAR_domain"
CERTIFICATE=$(om -u admin -p $OPSMAN_PASSWORD -t $OPSMAN_URL -k generate-certificate -d $CERT_DOMAINS)
export OM_VAR_properties_networking_poe_ssl_certs_0_certificate_cert_pem=$(echo $CERTIFICATE | jq -r ".certificate")
export OM_VAR_properties_networking_poe_ssl_certs_0_certificate_private_key_pem=$(echo $CERTIFICATE | jq -r ".key")

CERT_DOMAINS_UAA="*.login.sys.$RESOURCE_GROUP.$TF_VAR_domain,*.uaa.sys.$RESOURCE_GROUP.$TF_VAR_domain"
CERTIFICATE_UAA=$(om -u admin -p $OPSMAN_PASSWORD -t $OPSMAN_URL -k generate-certificate -d $CERT_DOMAINS_UAA)
export OM_VAR_uaa_service_provider_key_credentials_cert_pem=$(echo $CERTIFICATE_UAA | jq -r ".certificate")
export OM_VAR_uaa_service_provider_key_credentials_private_key_pem=$(echo $CERTIFICATE_UAA | jq -r ".key")

om -u admin -p $OPSMAN_PASSWORD -t $OPSMAN_URL -k configure-product -c cf_config.yml --vars-env OM_VAR

echo "Running apply changes..."
apply_changes()
{
  cat <<EOF
{
"deploy_products": "all",
"ignore_warnings": true
}
EOF
}

curl -k -X POST -H "Content-Type: application/json" -H "Authorization: Bearer $OPSMAN_TOKEN" -d "$(apply_changes)" "https://$OPSMAN_URL/api/v0/installations"


echo "

Apply changes is currently running. 
You Opsman URL is $OPSMAN_URL
Your username is admin
ssh to Opsman vm:
ssh -o StrictHostKeyChecking=no -i ~/.ssh/azurekeys/opsman ubuntu@$OPSMAN_URL"

