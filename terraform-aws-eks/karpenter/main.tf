################################################################################
# Providers
################################################################################

provider "aws" {
  region  = var.region
  profile = "default"
}

provider "helm" {
  kubernetes = {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--profile", "default"]
    }
  }

  # Isolate Helm cache from local Helm CLI to avoid cache conflicts
  # This prevents errors like "no cached repo found" when local Helm repos are corrupted
  repository_cache       = "${path.module}/.helm/cache"
  repository_config_path = "${path.module}/.helm/repositories.yaml"
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--profile", "default"]
  }
}

provider "kubectl" {
  apply_retry_count      = 5
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  load_config_file       = false

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--profile", "default"]
  }
}

################################################################################
# Data Sources
################################################################################

data "aws_availability_zones" "available" {
  # Exclude local zones
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

provider "aws" {
  alias   = "virginia"
  region  = "us-east-1"
  profile = "default"
}

data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.virginia
}

resource "random_string" "suffix" {
  length  = 4
  special = false
  upper   = false
}

################################################################################
# Local Variables
################################################################################

locals {
  name                = "${var.cluster_name_prefix}-${random_string.suffix.result}"
  karpenter_discovery = local.name # 动态值，每个集群唯一，避免多集群 tag 冲突

  # 自动探测并使用当前 region 的全部 AZ，提高 Spot 实例获取成功率
  azs = data.aws_availability_zones.available.names

  tags = {
    Example    = local.name
    GithubRepo = "terraform-aws-eks"
    GithubOrg  = "terraform-aws-modules"
  }
}

################################################################################
# EKS Module
################################################################################

module "eks" {
  source = "./.."

  name               = local.name
  kubernetes_version = "1.33"

  # Gives Terraform identity admin access to cluster which will
  # allow deploying resources (Karpenter) into the cluster
  enable_cluster_creator_admin_permissions = true
  endpoint_public_access                   = true

  # EKS Provisioned Control Plane configuration
  control_plane_scaling_config = {
    tier = "standard"
  }

  addons = {
    coredns = {}
    eks-pod-identity-agent = {
      before_compute = true
    }
    kube-proxy = {}
    vpc-cni = {
      before_compute = true
    }
  }

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.intra_subnets

  eks_managed_node_groups = {
    karpenter = {
      ami_type       = "BOTTLEROCKET_x86_64"
      instance_types = var.karpenter_node_instance_types

      min_size     = var.karpenter_node_min_size
      max_size     = var.karpenter_node_max_size
      desired_size = var.karpenter_node_desired_size

      labels = {
        # Used to ensure Karpenter runs on nodes that it does not manage
        "karpenter.sh/controller" = "true"
      }

      # Taint to prevent regular workloads from scheduling on this node group
      # Only Karpenter and system components (with tolerations) can run here
      taints = {
        karpenter = {
          key    = "CriticalAddonsOnly"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      }
    }
  }

  node_security_group_tags = merge(local.tags, {
    # NOTE - if creating multiple security groups with this module, only tag the
    # security group that Karpenter should utilize with the following tag
    # (i.e. - at most, only one security group should have this tag in your account)
    "karpenter.sh/discovery" = local.karpenter_discovery
  })

  tags = local.tags
}

################################################################################
# VPC Module
################################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = local.name
  cidr = var.vpc_cidr

  azs = local.azs

  # Subnet CIDR 分配策略（支持最多 8 个 AZ）:
  # - Private /20: 10.0.0.0 - 10.0.127.255  (4,091 可用 IP/AZ，运行工作节点和 Pod)
  # - Public  /24: 10.0.128.0 - 10.0.191.255 (251 可用 IP/AZ，运行 NAT Gateway 和 ELB)
  # - Intra   /24: 10.0.192.0 - 10.0.255.255 (251 可用 IP/AZ，EKS Control Plane ENI)
  private_subnets = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 8, k + 128)]
  intra_subnets   = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 8, k + 192)]

  enable_nat_gateway = true
  single_nat_gateway = true # 保持单一 NAT Gateway，节省成本（~$32/月 vs 多 AZ 的 ~$128/月）

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
    # Tags subnets for Karpenter auto-discovery
    "karpenter.sh/discovery" = local.karpenter_discovery
  }

  tags = local.tags
}
