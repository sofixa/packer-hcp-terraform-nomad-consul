# ---------------------------------------------------------------------------------------------------------------------
# DEPLOY A NOMAD CLUSTER CO-LOCATED WITH A CONSUL CLUSTER IN AWS
# These templates show an example of how to use the nomad-cluster module to deploy a Nomad cluster in AWS. This cluster
# has Consul colocated on the same nodes.
#
# We deploy two Auto Scaling Groups (ASGs): one with a small number of Nomad and Consul server nodes and one with a
# larger number of Nomad and Consul client nodes. Note that these templates assume that the AMI you provide via the
# ami_id input variable is built from the examples/nomad-consul-ami/nomad-consul.json Packer template.
# ---------------------------------------------------------------------------------------------------------------------

# ----------------------------------------------------------------------------------------------------------------------
# REQUIRE A SPECIFIC TERRAFORM VERSION OR HIGHER
# ----------------------------------------------------------------------------------------------------------------------
terraform {
  required_version = ">= 0.12.26"
}

provider "hcp" {}

provider "aws" {
  region = "eu-west-1"
}


data "hcp_packer_iteration" "ubuntu_nomad_consul_docker" {
  bucket_name = "nomad-consul-docker"
  channel     = "production"
}

data "hcp_packer_image" "ubuntu_eu_west_1" {
  bucket_name    = "nomad-consul-docker"
  cloud_provider = "aws"
  iteration_id   = data.hcp_packer_iteration.ubuntu_nomad_consul_docker.ulid
  region         = "eu-west-1"
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPLOY THE SERVER NODES
# Note that we use the consul-cluster module to deploy both the Nomad and Consul nodes on the same servers
# ---------------------------------------------------------------------------------------------------------------------

module "servers" {
  source = "./modules/consul-cluster"

  cluster_name  = "${var.cluster_name}-server"
  cluster_size  = var.num_servers
  instance_type = var.server_instance_type

  # The EC2 Instances will use these tags to automatically discover each other and form a cluster
  cluster_tag_key   = var.cluster_tag_key
  cluster_tag_value = var.cluster_tag_value

  ami_id    = data.hcp_packer_image.ubuntu_eu_west_1.cloud_image_id
  user_data = data.template_file.user_data_server.rendered

  vpc_id     = data.aws_vpc.default.id
  subnet_ids = data.aws_subnet_ids.default.ids

  # To make testing easier, we allow requests from any IP address here but in a production deployment, we strongly
  # recommend you limit this to the IP address ranges of known, trusted servers inside your VPC.
  allowed_ssh_cidr_blocks = ["0.0.0.0/0"]

  allowed_inbound_cidr_blocks = ["0.0.0.0/0"]
  ssh_key_name                = var.ssh_key_name

  tags = [
    {
      key                 = "Environment"
      value               = "development"
      propagate_at_launch = true
    },
  ]
}

# ---------------------------------------------------------------------------------------------------------------------
# ATTACH SECURITY GROUP RULES FOR NOMAD
# Our Nomad servers are running on top of the consul-cluster module, so we need to configure that cluster to allow
# the inbound/outbound connections used by Nomad.
# ---------------------------------------------------------------------------------------------------------------------

module "nomad_security_group_rules" {
  source = "./modules/nomad-security-group-rules"

  # To make testing easier, we allow requests from any IP address here but in a production deployment, we strongly
  # recommend you limit this to the IP address ranges of known, trusted servers inside your VPC.
  security_group_id = module.servers.security_group_id

  allowed_inbound_cidr_blocks = ["0.0.0.0/0"]
}

# ---------------------------------------------------------------------------------------------------------------------
# THE USER DATA SCRIPT THAT WILL RUN ON EACH SERVER NODE WHEN IT'S BOOTING
# This script will configure and start Consul and Nomad
# ---------------------------------------------------------------------------------------------------------------------

data "template_file" "user_data_server" {
  template = file("${path.module}/user-data-server.sh")

  vars = {
    cluster_tag_key   = var.cluster_tag_key
    cluster_tag_value = var.cluster_tag_value
    num_servers       = var.num_servers
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPLOY THE CLIENT NODES
# ---------------------------------------------------------------------------------------------------------------------

module "clients" {
  source = "./modules/nomad-cluster"

  cluster_name  = "${var.cluster_name}-client"
  instance_type = var.instance_type

  # Give the clients a different tag so they don't try to join the server cluster
  cluster_tag_key   = "nomad-clients"
  cluster_tag_value = var.cluster_name

  # To keep the example simple, we are using a fixed-size cluster. In real-world usage, you could use auto scaling
  # policies to dynamically resize the cluster in response to load.
  min_size = var.num_clients

  max_size         = var.num_clients + 1
  desired_capacity = var.num_clients

  ami_id    = data.hcp_packer_image.ubuntu_eu_west_1.cloud_image_id  
  user_data = data.template_file.user_data_client.rendered

  vpc_id     = data.aws_vpc.default.id
  subnet_ids = data.aws_subnet_ids.default.ids

  # To make testing easier, we allow Consul and SSH requests from any IP address here but in a production
  # deployment, we strongly recommend you limit this to the IP address ranges of known, trusted servers inside your VPC.
  allowed_ssh_cidr_blocks = ["0.0.0.0/0"]

  allowed_inbound_cidr_blocks = ["0.0.0.0/0"]
  ssh_key_name                = var.ssh_key_name

  tags = [
    {
      key                 = "Environment"
      value               = "development"
      propagate_at_launch = true
    }
  ]
}

# ---------------------------------------------------------------------------------------------------------------------
# ATTACH IAM POLICIES FOR CONSUL
# To allow our client Nodes to automatically discover the Consul servers, we need to give them the IAM permissions from
# the Consul AWS Module's consul-iam-policies module.
# ---------------------------------------------------------------------------------------------------------------------

module "consul_iam_policies" {
  source = "github.com/hashicorp/terraform-aws-consul//modules/consul-iam-policies?ref=v0.8.0"

  iam_role_id = module.clients.iam_role_id
}

# ---------------------------------------------------------------------------------------------------------------------
# THE USER DATA SCRIPT THAT WILL RUN ON EACH CLIENT NODE WHEN IT'S BOOTING
# This script will configure and start Consul and Nomad
# ---------------------------------------------------------------------------------------------------------------------

data "template_file" "user_data_client" {
  template = file("${path.module}/user-data-client.sh")

  vars = {
    cluster_tag_key   = var.cluster_tag_key
    cluster_tag_value = var.cluster_tag_value
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPLOY THE CLUSTER IN THE DEFAULT VPC AND SUBNETS
# Using the default VPC and subnets makes this example easy to run and test, but it means Consul and Nomad are
# accessible from the public Internet. In a production deployment, we strongly recommend deploying into a custom VPC
# and private subnets.
# ---------------------------------------------------------------------------------------------------------------------

data "aws_vpc" "default" {
  default = var.vpc_id == "" ? true : false
  id      = var.vpc_id
}

data "aws_subnet_ids" "default" {
  vpc_id = data.aws_vpc.default.id
}

data "aws_region" "current" {}


data "aws_instances" "nomad_servers" {
  instance_tags = {
    (module.servers.cluster_tag_key) = module.servers.cluster_tag_value
  }

  instance_state_names = ["running"]

  depends_on = [module.servers]
}

data "aws_instances" "nomad_clients" {
  instance_tags = {
    (module.clients.cluster_tag_key) = module.clients.cluster_tag_value
  }

  instance_state_names = ["running"]

  depends_on = [module.clients]
}

