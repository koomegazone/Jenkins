locals {
  image_name_map = {
    "amazon-linux-2023" = "al2023-ami-2023*"
    "amazon-linux-2"    = "amzn2-ami-hvm-2.0.*-x86_64-ebs"
  }
}

data "aws_ami" "this" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = [local.image_name_map[var.ec2_instance.ami_conditions.os]]
  }
  filter {
    name   = "architecture"
    values = [var.ec2_instance.ami_conditions.architecture]
  }
}

resource "aws_instance" "this" {
  instance_type               = var.ec2_instance.instance_type
  key_name                    = var.ec2_instance.key_pair_name
  associate_public_ip_address = var.ec2_instance.associate_public_ip_address
  subnet_id                   = local.subnet_name_id_map[var.ec2_instance.subnet_name]
  vpc_security_group_ids      = [for security_group_name in var.ec2_instance.security_group_name_list : local.security_group_name_id_map[security_group_name]]
  ami                         = data.aws_ami.this.id
  user_data                   = try(templatefile(var.ec2_instance.user_data.template_path, var.ec2_instance.user_data.template_values), null)

  tags = merge({
    Name = var.ec2_instance.name
  }, var.ec2_instance.tag_map)

  lifecycle {
    ignore_changes = [ami]
  }
}
