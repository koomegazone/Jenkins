variable "vpc" {
  type = object({
    name                 = string
    cidr_block           = string
    enable_dns_support   = optional(bool, true)
    enable_dns_hostnames = optional(bool, true)
  })
}

variable "subnet_list" {
  default = []
  type = list(object({
    name       = string
    type       = string
    az         = string
    cidr_block = string
  }))
  
  validation {
    condition     = alltrue([for subnet in var.subnet_list : contains(["public", "private"], subnet.type)])
    error_message = "Available value is one of -> public | private"
  }
}

variable "internet_gateway" {
  default = null
  type = object({
    name = string
  })
}

variable "nat_gateway_list" {
  default = []
  type = list(object({
    name              = string
    connectivity_type = optional(string, "public")
    subnet_name       = string
  }))
}

variable "route_table_list" {
  default = []
  type = list(object({
    name             = string
    subnet_name_list = optional(list(string), [])
    route_list = optional(list(object({
      destination_type = string # cidr-block | prefix-list
      destination_name = string
      target_type      = string # internet-gateway | nat-gateway
      target_name      = string
    })), [])
  }))

  validation {
    condition = alltrue(flatten([for route_table in var.route_table_list :
      [for route in route_table.route_list : contains(["cidr-block", "prefix-list"], route.destination_type)]]
    ))
    error_message = "Available value is one of -> cidr-block | prefix-list"
  }

  validation {
    condition = alltrue(flatten([for route_table in var.route_table_list :
      [for route in route_table.route_list : contains(["internet-gateway", "nat-gateway"], route.target_type)]]
    ))
    error_message = "Available value is one of -> internet-gateway | nat-gateway"
  }
}

