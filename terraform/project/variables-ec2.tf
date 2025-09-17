variable "ec2_instance" {
  description = "Details of ec2 instance"
  type = object({
    name                        = string
    instance_type               = string
    key_pair_name               = optional(string, null)
    subnet_name                 = string
    associate_public_ip_address = optional(bool, false)
    security_group_name_list    = optional(list(string), [])

    ami_conditions = optional(object({
      os           = string
      architecture = optional(string, "x86_64")
    }), null)

    user_data = optional(object({
      template_path   = string
      template_values = optional(map(any), null)
    }), null)

    tag_map = optional(map(string), {})
  })

  validation {
    condition     = contains(["amazon-linux-2023", "amazon-linux-2"], var.ec2_instance.ami_conditions.os)
    error_message = "Available value is one of -> amazon-linux-2023 | amazon-linux-2"
  }

  validation {
    condition     = contains(["x86_64", "arm64"], var.ec2_instance.ami_conditions.architecture)
    error_message = "Available value is one of -> x86_64 | arm64"
  }
}
