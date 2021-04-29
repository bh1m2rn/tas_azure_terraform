#!/bin/bash

read -p 'Please enter the name of the resource group you used to deploy TAS: ' RESOURCE_GROUP

# Adjust these values accordingly
DOMAIN="used4testing.xyz"
DNS_ZONE="dns_jlarrea"


az group delete -n $RESOURCE_GROUP -y
az ad sp delete --id http://BoshAzure$RESOURCE_GROUP
az network dns record-set a delete -n "*.apps.$RESOURCE_GROUP" -z $DOMAIN -g $DNS_ZONE -y
az network dns record-set a delete -n "*.sys.$RESOURCE_GROUP" -z $DOMAIN -g $DNS_ZONE -y
az network dns record-set a delete -n "opsman.$RESOURCE_GROUP" -z $DOMAIN -g $DNS_ZONE -y
