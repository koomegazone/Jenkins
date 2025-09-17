vpc = {
  name       = "vpc-tfacademy"
  cidr_block = "10.0.0.0/16"
}

subnet_list = [
  { name = "sbn-tfacademy-public-az1", type = "public", az = "us-east-1a", cidr_block = "10.0.0.0/24" },
  { name = "sbn-tfacademy-public-az3", type = "public", az = "us-east-1c", cidr_block = "10.0.2.0/24" },
  { name = "sbn-tfacademy-private-az1", type = "private", az = "us-east-1a", cidr_block = "10.0.10.0/24" },
  { name = "sbn-tfacademy-private-az3", type = "private", az = "us-east-1c", cidr_block = "10.0.12.0/24" },
]

internet_gateway = {
  name = "igw-tfacademy"
}

nat_gateway_list = [
  { name = "ngw-tfacademy-az1", subnet_name = "sbn-tfacademy-public-az1" },
]

route_table_list = [
  {
    name             = "rt-tfacademy-public"
    subnet_name_list = ["sbn-tfacademy-public-az1", "sbn-tfacademy-public-az3"]
    route_list = [
      { destination_type = "cidr-block", destination_name = "0.0.0.0/0", target_type = "internet-gateway", target_name = "igw-tfacademy" },
    ]
  },
  {
    name             = "rt-tfacademy-private"
    subnet_name_list = ["sbn-tfacademy-private-az1", "sbn-tfacademy-private-az3"]
    route_list = [
      { destination_type = "cidr-block", destination_name = "0.0.0.0/0", target_type = "nat-gateway", target_name = "ngw-tfacademy-az1" },
    ]
  }
]
