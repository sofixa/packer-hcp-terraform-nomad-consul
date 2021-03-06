variable "ami_name_prefix" {
  type    = string
  default = "nomad-consul"
}

variable "aws_region" {
  type    = string
  default = "eu-west-1"
}

variable "consul_module_version" {
  type    = string
  default = "v0.10.1"
}

variable "consul_version" {
  type    = string
  default = "1.10.3"
}

variable "nomad_version" {
  type    = string
  default = "1.2.0"
}

variable "subnet_id" {
  default = "subnet-f958429b"
}

# "timestamp" template function replacement
locals { timestamp = regex_replace(timestamp(), "[- TZ:]", "") }

source "amazon-ebs" "ubuntu-2004-arm64-ami" {
  ami_description = "Ubuntu 20.04 ARM64 AMI that has Nomad, Consul and Docker installed."
  ami_name        = "${var.ami_name_prefix}-docker-ubuntu-2004-arm64-${local.timestamp}"
  instance_type   = "t4g.nano"
  region          = "${var.aws_region}"
  subnet_id       = "${var.subnet_id}"
  source_ami_filter {
    filters = {
      name                = "ubuntu/images/hvm-ssd/ubuntu-focal-20.04-arm64-server-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners      = ["099720109477"]
  }

  ssh_username = "ubuntu"
}

# a build block invokes sources and runs provisionning steps on them. The
# documentation for build blocks can be found here:
# https://www.packer.io/docs/from-1.5/blocks/build
build {
  hcp_packer_registry {
    bucket_name = "nomad-consul-docker"
    description = <<EOT
AMIs based on Ubuntu 20.04 ARM64 with Nomad, Consul and Docker.
    EOT
    labels = {
      "nomad-version"  = "1.2.0",
      "consul-version" = "1.10.3",
    }
  }
  sources = ["source.amazon-ebs.ubuntu-2004-arm64-ami"]

  provisioner "shell" {
    inline = ["mkdir -p /tmp/terraform-aws-nomad/modules"]
  }

  provisioner "shell" {
    script = "${path.root}/setup_ubuntu.sh"
  }

  provisioner "file" {
    destination = "/tmp/terraform-aws-nomad/modules"
    source      = "${path.root}/modules/"
  }

  provisioner "shell" {
    environment_vars = ["NOMAD_VERSION=${var.nomad_version}", "CONSUL_VERSION=${var.consul_version}", "CONSUL_MODULE_VERSION=${var.consul_module_version}"]
    script           = "${path.root}/setup_nomad_consul.sh"
  }
}
