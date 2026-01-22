security_group_list = [
  {
    name        = "sg-tfacademy-bastion"
    description = "Security Group for bastion instance"
    vpc_name    = "vpc-tfacademy"

    ingress_rule_list = []
    egress_rule_list = [
      { protocol = "all", from_port = "1", to_port = "65535", target_list = ["0.0.0.0/0"], description = "all outbound" },
    ]
  }
]
