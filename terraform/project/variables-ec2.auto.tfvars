ec2_instance = {
  name                        = "i-tfacademy-bastion"
  instance_type               = "t3.large"
  subnet_name                 = "sbn-tfacademy-public-az1"
  associate_public_ip_address = true
  security_group_name_list    = ["sg-tfacademy-bastion"]

  ami_conditions = {
    os           = "amazon-linux-2023"
    architecture = "x86_64"
  }
}
