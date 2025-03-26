variable "global_settings" {
  type        = any
  description = "Global settings"
  default = {

    address_space = "10.0.0.0/16"
    hub_virtual_networks = {
      "hub" = {
        netnum = 0
      }
    }
    spoke_virtual_networks = {
      "spoke1" = {
        netnum = 1
      },
      "spoke2" = {
        netnum = 2
      },
      "spoke3" = {
        address_space = "176.16.0.0/16"
        netnum        = 0
      }
    }
  }
}

variable "location" {
  description = "Azure location"
  type        = string
  default     = "UK South"
}

variable "location-map" {
  description = "Azure location map used for naming abbreviations"
  type        = map(any)
  default = {
    "North Europe" = "eun",
    "northeurope"  = "eun",
    "UK South"     = "uks",
    "uksouth"      = "uks",
    "UK West"      = "ukw",
    "ukwest"       = "ukw",
    "West Europe"  = "euw",
    "westeurope"   = "euw"
  }
}
