output "vpc" {
  value = aws_vpc.this
}

output "vpc_name_id_map" {
  value = local.vpc_name_id_map
}

output "subnets" {
  value = aws_subnet.these
}

output "subnet_name_id_map" {
  value = local.subnet_name_id_map
}

output "internet_gateway" {
  value = aws_internet_gateway.this
}

output "internet_gateway_name_id_map" {
  value = local.internet_gateway_name_id_map
}

output "nat_gateways" {
  value = aws_nat_gateway.these
}

output "nat_gateway_name_id_map" {
  value = local.nat_gateway_name_id_map
}

output "route_tables" {
  value = aws_route_table.these
}

output "route_table_name_id_map" {
  value = local.route_table_name_id_map
}

