output "security_groups" {
  value = aws_security_group.these
}

output "security_group_name_id_map" {
  value = local.security_group_name_id_map
}

output "security_group_rules" {
  value = aws_security_group_rule.these
}