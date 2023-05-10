
terraform {
  required_providers {
    hcp = {
      source = "hashicorp/hcp"
      version = "0.56.0"
    }
  }
}

provider "hcp" {
  # Configuration options
 
}
provider "azurerm" {
  features {}
}

provider "azuread" {}

data "azurerm_subscription" "sub" {
  # subscription_id = "<subscription GUID>"
}

resource "azurerm_resource_group" "hcp-peering-rg" {
  name     = "resource-group-hcp-peering"
  location = "West US"
}

resource "azurerm_virtual_network" "vnet" {
  name                = "azure-hcp-peering"
  location            = azurerm_resource_group.hcp-peering-rg.location
  resource_group_name = azurerm_resource_group.hcp-peering-rg.name

  address_space = [
    "10.0.0.0/16"
  ]
}

resource "azuread_service_principal" "principal" {
  application_id = hcp_azure_peering_connection.peer.application_id
}

resource "azurerm_role_definition" "definition" {
  name  = "azure-peering-access"
  scope = azurerm_virtual_network.vnet.id

  assignable_scopes = [
    azurerm_virtual_network.vnet.id
  ]

permissions {
    actions = [
          "Microsoft.Network/virtualNetworks/read",
          "Microsoft.Network/virtualNetworks/virtualNetworkPeerings/read",
          "Microsoft.Network/virtualNetworks/virtualNetworkPeerings/write",
          "Microsoft.Network/virtualNetworks/peer/action"
    ]
  }
}



resource "azurerm_role_assignment" "assignment" {
  principal_id       = azuread_service_principal.principal.id
  scope              = azurerm_virtual_network.vnet.id
  role_definition_id = azurerm_role_definition.definition.role_definition_resource_id
}


resource "hcp_hvn" "hvn" {
  hvn_id         = var.hvn_id
  cloud_provider = var.cloud_provider
  region         = var.region
  cidr_block     = "172.25.16.0/20"
}

resource "hcp_vault_cluster" "azure_hcp_vault" {
  hvn_id     = hcp_hvn.hvn.hvn_id
  cluster_id = var.cluster_id
  tier       = var.tier
  # public_endpoint = true
}

// This resource initially returns in a Pending state, because its application_id is required to complete acceptance of the connection.
resource "hcp_azure_peering_connection" "peer" {
  hvn_link                 = hcp_hvn.hvn.self_link
  peering_id               = var.tier
  peer_vnet_name           = azurerm_virtual_network.vnet.name
  peer_subscription_id     = data.azurerm_subscription.sub.subscription_id
  peer_tenant_id           = data.azurerm_subscription.sub.tenant_id
  peer_resource_group_name = azurerm_resource_group.hcp-peering-rg.name
  peer_vnet_region         = azurerm_virtual_network.vnet.location
}

// This data source is the same as the resource above, but waits for the connection to be Active before returning.
data "hcp_azure_peering_connection" "peer" {
  hvn_link              = hcp_hvn.hvn.self_link
  peering_id            = hcp_azure_peering_connection.peer.peering_id
}

// The route depends on the data source, rather than the resource, to ensure the peering is in an Active state.
resource "hcp_hvn_route" "route" {
  hvn_link         = hcp_hvn.hvn.self_link
  hvn_route_id     = var.route_id
  destination_cidr = "172.31.0.0/16"
  target_link      = data.hcp_azure_peering_connection.peer.self_link
}



