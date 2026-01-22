variable "security_group_list" {
  default = []
  type = list(object({
    name                   = string
    description            = optional(string)
    vpc_name               = string
    default_security_group = optional(bool, false)
    revoke_rules_on_delete = optional(bool, false)
    ingress_rule_list = optional(list(object({
      protocol    = string
      from_port   = number
      to_port     = number
      target_list = list(string)
      description = optional(string)
    })), [])
    egress_rule_list = optional(list(object({
      protocol    = string
      from_port   = number
      to_port     = number
      target_list = list(string)
      description = optional(string)
    })), [])
  }))
}