#############################################################################
# VARIABLES
#############################################################################

variable "resource_group_name" {
  type    = string
}

variable "location" {
  type    = string
  default = "eastus"
}

variable "sp_identifier" {
  type    = string
}

variable "opsman_image_url" {
  type    = string
}

variable "domain" {
  type    = string
}

variable "dns_zone" {
  type    = string
}

#############################################################################
# DATA
#############################################################################

data "azurerm_subscription" "current" {}

data "azurerm_public_ip" "opsman_ipaddress" {
  name                = azurerm_public_ip.opsman_ip.name
  resource_group_name = azurerm_public_ip.opsman_ip.resource_group_name
}

data "azurerm_public_ip" "tas_lb_ipaddress" {
  name                = azurerm_public_ip.tas_lb_ip.name
  resource_group_name = azurerm_public_ip.tas_lb_ip.resource_group_name
}

#############################################################################
# PROVIDERS
#############################################################################

terraform {
  required_providers {
    azure = {
      source  = "hashicorp/azurerm"
      version = "~> 2.52.0"
    }
    ad = {
      source  = "hashicorp/azuread"
      version = "~> 1.4.0" 
    }
  }
}

provider "azure" {
  features {}
}

#############################################################################
# RESOURCES
#############################################################################

## AZURE AD SP ##

resource "random_password" "sp_for_tas" {
  length  = 16
  special = true
  override_special = "_%@"
}

resource "azuread_application" "sp_for_tas" {
  display_name               = "Service Principal for BOSH"
  homepage           = "http://BOSHAzureCPI"
  identifier_uris    = [var.sp_identifier]
}

resource "time_sleep" "wait_2_mins" {
  depends_on = [azuread_application.sp_for_tas]

  create_duration = "2m"
}

resource "azuread_service_principal" "sp_for_tas" {
  application_id     = azuread_application.sp_for_tas.application_id
  depends_on = [time_sleep.wait_2_mins]
}

resource "azuread_service_principal_password" "sp_for_tas" {
  service_principal_id = azuread_service_principal.sp_for_tas.id
  value                = random_password.sp_for_tas.result
  end_date_relative    = "720h"
}

resource "azurerm_role_assignment" "sp_for_tas" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Owner"
  principal_id         = azuread_service_principal.sp_for_tas.id
}


## RESOURCE GROUPS ##

resource "azurerm_resource_group" "rg_tas" {
  name     = var.resource_group_name
  location = var.location
}


## NETWORKING ##

module "vnet" {
  source              = "Azure/vnet/azurerm"
  vnet_name           = "tas-virtual-network"
  version             = "2.3.0"
  resource_group_name = azurerm_resource_group.rg_tas.name
  address_space       = ["10.0.0.0/16"]
  subnet_prefixes     = ["10.0.4.0/26", "10.0.12.0/22", "10.0.8.0/22"]
  subnet_names        = ["tas-infrastructure", "tas-runtime", "tas-services"]

  nsg_ids = {
    tas-infrastructure = azurerm_network_security_group.tas_nsg.id
    tas-runtime = azurerm_network_security_group.tas_nsg.id
    tas-services = azurerm_network_security_group.tas_nsg.id
  }  

  depends_on = [azurerm_resource_group.rg_tas]
}

resource "azurerm_network_security_group" "tas_nsg" {
  name                = "tas_nsg"
  resource_group_name = azurerm_resource_group.rg_tas.name
  location            = azurerm_resource_group.rg_tas.location

  security_rule {
    name                       = "ssh"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "http"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
    
    security_rule {
    name                       = "https"
    priority                   = 300
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

    security_rule {
    name                       = "diego-ssh"
    priority                   = 400
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "2222"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_security_group" "opsman_nsg" {
  name                = "opsman_nsg"
  resource_group_name = azurerm_resource_group.rg_tas.name
  location            = azurerm_resource_group.rg_tas.location

  security_rule {
    name                       = "ssh"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "http"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
    
    security_rule {
    name                       = "https"
    priority                   = 300
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_public_ip" "opsman_ip" {
  name                = "opsman_ip"
  resource_group_name = azurerm_resource_group.rg_tas.name
  location            = azurerm_resource_group.rg_tas.location
  allocation_method   = "Static"
}

resource "azurerm_network_interface" "opsman_nic" {
  name                = "opsman_nic"
  location            = azurerm_resource_group.rg_tas.location
  resource_group_name = azurerm_resource_group.rg_tas.name

  ip_configuration {
    name                          = "opsmanipconf"
    subnet_id                     = module.vnet.vnet_subnets[0]
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.opsman_ip.id
  }
}

resource "azurerm_public_ip" "tas_lb_ip" {
  name                = "tas_lb_ip"
  location            = azurerm_resource_group.rg_tas.location
  resource_group_name = azurerm_resource_group.rg_tas.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_lb" "tas_lb" {
  name                = "tas_lb"
  location            = azurerm_resource_group.rg_tas.location
  resource_group_name = azurerm_resource_group.rg_tas.name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                 = "tas_frontend_ip"
    public_ip_address_id = azurerm_public_ip.tas_lb_ip.id
  }
}

resource "azurerm_lb_backend_address_pool" "tas_lb_backend_pool" {
  loadbalancer_id = azurerm_lb.tas_lb.id
  name            = "tas_lb_backend_pool"
}

resource "azurerm_lb_backend_address_pool_address" "tas_lb_backend_address1" {
  name                    = "tas_lb_backend_address1"
  backend_address_pool_id = azurerm_lb_backend_address_pool.tas_lb_backend_pool.id
  virtual_network_id      = module.vnet.vnet_id
  ip_address              = "10.0.12.19"
}

resource "azurerm_lb_backend_address_pool_address" "tas_lb_backend_address2" {
  name                    = "tas_lb_backend_address2"
  backend_address_pool_id = azurerm_lb_backend_address_pool.tas_lb_backend_pool.id
  virtual_network_id      = module.vnet.vnet_id
  ip_address              = "10.0.12.20"
}

resource "azurerm_lb_probe" "tas_lb_probe" {
  resource_group_name = azurerm_resource_group.rg_tas.name
  loadbalancer_id     = azurerm_lb.tas_lb.id
  name                = "http8080"
  port                = 8080
}

resource "azurerm_lb_rule" "tas_lb_http" {
  resource_group_name            = azurerm_resource_group.rg_tas.name
  loadbalancer_id                = azurerm_lb.tas_lb.id
  name                           = "HTTP_lb_rule"
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "tas_frontend_ip"
  probe_id                       = azurerm_lb_probe.tas_lb_probe.id
  backend_address_pool_id        = azurerm_lb_backend_address_pool.tas_lb_backend_pool.id
}

resource "azurerm_lb_rule" "tas_lb_https" {
  resource_group_name            = azurerm_resource_group.rg_tas.name
  loadbalancer_id                = azurerm_lb.tas_lb.id
  name                           = "HTTPS_lb_rule"
  protocol                       = "Tcp"
  frontend_port                  = 443
  backend_port                   = 443
  frontend_ip_configuration_name = "tas_frontend_ip"
  probe_id                       = azurerm_lb_probe.tas_lb_probe.id
  backend_address_pool_id        = azurerm_lb_backend_address_pool.tas_lb_backend_pool.id
}

## DNS ##

resource "azurerm_dns_a_record" "opsman_dns_record" {
  name                = "opsman.${var.resource_group_name}"
  zone_name           = var.domain
  resource_group_name = var.dns_zone
  ttl                 = 300
  records             = [data.azurerm_public_ip.opsman_ipaddress.ip_address]
}

resource "azurerm_dns_a_record" "sys_lb_dns_record" {
  name                = "*.sys.${var.resource_group_name}"
  zone_name           = var.domain
  resource_group_name = var.dns_zone
  ttl                 = 300
  records             = [data.azurerm_public_ip.tas_lb_ipaddress.ip_address]
}

resource "azurerm_dns_a_record" "apps_lb_dns_record" {
  name                = "*.apps.${var.resource_group_name}"
  zone_name           = var.domain
  resource_group_name = var.dns_zone
  ttl                 = 300
  records             = [data.azurerm_public_ip.tas_lb_ipaddress.ip_address]
}

## STORAGE ACCOUNTS ##

resource "azurerm_storage_account" "opsman_storage" {
  name                     = "${azurerm_resource_group.rg_tas.name}storage4tas"
  resource_group_name      = azurerm_resource_group.rg_tas.name
  location                 = azurerm_resource_group.rg_tas.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  allow_blob_public_access = true

}

resource "azurerm_storage_container" "opsman_container" {
  name                  = "opsmanager"
  storage_account_name  = azurerm_storage_account.opsman_storage.name
}

resource "azurerm_storage_container" "bosh_container" {
  name                  = "bosh"
  storage_account_name  = azurerm_storage_account.opsman_storage.name
}

resource "azurerm_storage_container" "stemcell_container" {
  name                  = "stemcell"
  storage_account_name  = azurerm_storage_account.opsman_storage.name
  container_access_type = "blob"
}

resource "azurerm_storage_table" "opsman_table" {
  name                 = "stemcells"
  storage_account_name = azurerm_storage_account.opsman_storage.name
}

resource "azurerm_storage_account" "storage_accounts" {
  for_each = toset( ["${azurerm_resource_group.rg_tas.name}storage4tas1", "${azurerm_resource_group.rg_tas.name}storage4tas2", "${azurerm_resource_group.rg_tas.name}storage4tas3" ] )
  name                     = each.key
  resource_group_name      = azurerm_resource_group.rg_tas.name
  location                 = azurerm_resource_group.rg_tas.location
  account_tier             = "Premium"
  account_replication_type = "LRS"
}

resource "azurerm_storage_container" "bosh_containers" {
  for_each = toset( ["${azurerm_resource_group.rg_tas.name}storage4tas1", "${azurerm_resource_group.rg_tas.name}storage4tas2", "${azurerm_resource_group.rg_tas.name}storage4tas3" ] )
  name                  = "bosh"
  storage_account_name  = each.key
  depends_on = [azurerm_storage_account.storage_accounts]
}

resource "azurerm_storage_container" "stemcell_containers" {
  for_each = toset( ["${azurerm_resource_group.rg_tas.name}storage4tas1", "${azurerm_resource_group.rg_tas.name}storage4tas2", "${azurerm_resource_group.rg_tas.name}storage4tas3" ] )
  name                  = "stemcell"
  storage_account_name  = each.key
  depends_on = [azurerm_storage_account.storage_accounts]
}

resource "azurerm_storage_blob" "opsman_blob" {
  name                   = "opsman.vhd"
  storage_account_name   = azurerm_storage_account.opsman_storage.name
  storage_container_name = azurerm_storage_container.opsman_container.name
  type                   = "Page"
  source_uri             = var.opsman_image_url
}

## VIRTUAL MACHINES ##

resource "azurerm_image" "opsman-image" {
  name                = "opsman-image"
  location            = azurerm_resource_group.rg_tas.location
  resource_group_name = azurerm_resource_group.rg_tas.name

  os_disk {
    os_type  = "Linux"
    os_state = "Generalized"
    blob_uri = azurerm_storage_blob.opsman_blob.url
  }
}

resource "azurerm_linux_virtual_machine" "opsman-vm" {
  name                = "opsman-vm"
  resource_group_name = azurerm_resource_group.rg_tas.name
  location            = azurerm_resource_group.rg_tas.location
  size                = "Standard_DS2_v2"
  admin_username      = "ubuntu"
  source_image_id     = azurerm_image.opsman-image.id
  network_interface_ids = [
    azurerm_network_interface.opsman_nic.id,
  ]

  admin_ssh_key {
    username   = "ubuntu"
    public_key = file("~/.ssh/azurekeys/opsman.pub")
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 128
  }
}

## FOR TAS CONFIGURATION ##

resource "random_password" "credhub_for_tas" {
  length  = 20
  special = true
  override_special = "_%@"
}

#############################################################################
# PROVISIONERS
#############################################################################

resource "null_resource" "opsman-config" {

  provisioner "local-exec" {
    command = <<EOT
echo "export SP_SECRET=${azuread_service_principal_password.sp_for_tas.value}" >> next-step.txt
echo "export OM_VAR_credhub_secret=${random_password.credhub_for_tas.result}" >> next-step.txt
echo "export OPSMAN_URL=${azurerm_dns_a_record.opsman_dns_record.name}.${azurerm_dns_a_record.opsman_dns_record.zone_name}" >> next-step.txt
echo "export SUBSCRIPTION_ID=${data.azurerm_subscription.current.subscription_id}" >> next-step.txt
echo "export TENANT_ID=${data.azurerm_subscription.current.tenant_id}" >> next-step.txt
echo "export STORAGE_NAME=${azurerm_storage_account.opsman_storage.name}" >> next-step.txt
EOT
  }
}

#############################################################################
# OUTPUTS
#############################################################################
