### Security Gruop

locals {
  security_group_map = { for security_group in var.security_group_list : replace(security_group.name, "-", "_") => security_group }
}

resource "aws_security_group" "these" {
  for_each = local.security_group_map

  name                   = trimprefix(each.value.name, "sg-")
  description            = each.value.description
  vpc_id                 = local.vpc_name_id_map[each.value.vpc_name]
  revoke_rules_on_delete = each.value.revoke_rules_on_delete

  tags = {
    Name = each.value.name
  }
}

locals {
  security_group_name_id_map = { for key, security_group in local.security_group_map : security_group.name => aws_security_group.these[key].id }
}


### Security Group Rule

locals {
  ingress_security_group_rule_map = merge([for key, security_group in local.security_group_map :
    { for rule in security_group.ingress_rule_list :
      "${key}__${md5(jsonencode(rule))}" => merge(rule, {
        rule_type           = "ingress"
        security_group_name = security_group.name
      })
    }
  ]...)

  egress_security_group_rule_map = merge([for key, security_group in local.security_group_map :
    { for rule in security_group.egress_rule_list :
      "${key}__${md5(jsonencode(rule))}" => merge(rule, {
        rule_type           = "egress"
        security_group_name = security_group.name
      })
    }
  ]...)

  security_group_rule_map = merge([for key, rule in merge(local.ingress_security_group_rule_map, local.egress_security_group_rule_map) :
    { for target in rule.target_list :
      "${split("__", key)[0]}__${md5(join("_", [split("__", key)[0], target]))}" => merge(
        { for prop_key, prop_val in rule : prop_key => prop_val if prop_key != "target_list" },
        {
          cidr_block                 = try(regex("^(?:[0-9]{1,3}\\.){3}[0-9]{1,3}/[0-9]{1,2}$", target), null)
          source_security_group_name = try(regex("^[0-9a-z]{1,}(?:\\-[0-9a-z]{1,}){1,}$", target), null)
          self                       = target == "self" ? true : false
        }
      )
    }
  ]...)
}

resource "aws_security_group_rule" "these" {
  for_each = local.security_group_rule_map

  type                     = each.value.rule_type
  security_group_id        = local.security_group_name_id_map[each.value.security_group_name]
  description              = each.value.description
  protocol                 = each.value.protocol
  from_port                = each.value.from_port
  to_port                  = each.value.to_port
  cidr_blocks              = each.value.cidr_block != null ? [each.value.cidr_block] : null
  source_security_group_id = each.value.source_security_group_name != null ? local.security_group_name_id_map[each.value.source_security_group_name] : null
  self                     = each.value.self ? true : null
}
