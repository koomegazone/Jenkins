resource "aws_vpc" "this" {
  cidr_block           = var.vpc.cidr_block
  enable_dns_support   = var.vpc.enable_dns_support
  enable_dns_hostnames = var.vpc.enable_dns_hostnames

  tags = {
    Name = var.vpc.name
  }
}

locals {
  vpc_name_id_map = { (var.vpc.name) = aws_vpc.this.id }
}

### Subnet

locals {
  subnet_map = { for subnet in var.subnet_list : replace(subnet.name, "-", "_") => subnet }
}

resource "aws_subnet" "these" {
  for_each = local.subnet_map

  vpc_id                  = aws_vpc.this.id
  availability_zone       = each.value.az
  map_public_ip_on_launch = each.value.type == "public" ? true : false
  cidr_block              = each.value.cidr_block

  tags = {
    Name = each.value.name
  }
}

locals {
  subnet_name_id_map = { for key, subnet in local.subnet_map : subnet.name => aws_subnet.these[key].id }
}

### Internet Gateway

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = var.internet_gateway.name
  }
}

locals {
  internet_gateway_name_id_map = { (var.internet_gateway.name) = aws_internet_gateway.this.id }
}

### NAT Gateway

locals {
  nat_gateway_map = { for nat_gateway in var.nat_gateway_list : replace(nat_gateway.name, "-", "_") => nat_gateway }
}

resource "aws_eip" "these" {
  for_each = local.nat_gateway_map

  # domain = "vpc"
  tags = {
    Name = "eip-${each.value.name}"
  }
}

resource "aws_nat_gateway" "these" {
  for_each = local.nat_gateway_map

  connectivity_type = each.value.connectivity_type
  allocation_id     = aws_eip.these[each.key].id
  subnet_id         = local.subnet_name_id_map[each.value.subnet_name]

  tags = {
    Name = each.value.name
  }
}

locals {
  nat_gateway_name_id_map = { for key, nat_gateway in local.nat_gateway_map : nat_gateway.name => aws_nat_gateway.these[key].id }
}

### Route Table

locals {
  route_table_map = { for route_table in var.route_table_list : replace(route_table.name, "-", "_") => route_table }
}

resource "aws_route_table" "these" {
  for_each = local.route_table_map

  vpc_id = aws_vpc.this.id
  tags = {
    Name = each.value.name
  }
}

locals {
  route_table_name_id_map = { for key, route_table in local.route_table_map : route_table.name => aws_route_table.these[key].id }
}

locals {
  subnet_association_map = merge([for route_table_key, route_table in local.route_table_map :
    { for subnet_name in route_table.subnet_name_list :
      "${route_table_key}__${replace(subnet_name, "-", "_")}" => {
        route_table_id = local.route_table_name_id_map[route_table.name]
        subnet_id      = local.subnet_name_id_map[subnet_name]
      }
    }
  ]...)
}

### Route Table Subnet Association

resource "aws_route_table_association" "these" {
  for_each = local.subnet_association_map

  route_table_id = each.value.route_table_id
  subnet_id      = each.value.subnet_id
}


### Route Table Route

locals {
  route_map = merge([for route_table_key, route_table in local.route_table_map :
    { for route in route_table.route_list :
      "${route_table_key}__${md5(jsonencode(route))}" => merge(route, { route_table_name = route_table.name })
    }
  ]...)
}

resource "aws_route" "these" {
  for_each = local.route_map

  route_table_id             = local.route_table_name_id_map[each.value.route_table_name]
  destination_cidr_block     = each.value.destination_type == "cidr-block" ? each.value.destination_name : null
  destination_prefix_list_id = each.value.destination_type == "prefix-list" ? each.value.prefix_list_id : null
  gateway_id                 = each.value.target_type == "internet-gateway" ? local.internet_gateway_name_id_map[each.value.target_name] : null
  nat_gateway_id             = each.value.target_type == "nat-gateway" ? local.nat_gateway_name_id_map[each.value.target_name] : null
}

