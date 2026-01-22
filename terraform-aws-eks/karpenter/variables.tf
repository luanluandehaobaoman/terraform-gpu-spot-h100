################################################################################
# General Configuration
################################################################################

variable "region" {
  description = "AWS region for deployment (required)"
  type        = string
}

variable "cluster_name_prefix" {
  description = "Prefix for EKS cluster name (will append random suffix)"
  type        = string
  default     = "eks-spot-gpu"
}

################################################################################
# GPU NodePool Configuration
################################################################################

variable "gpu_instance_types" {
  description = "GPU instance types for Karpenter NodePool (required). Examples: p5.48xlarge (H100), p4d.24xlarge (A100), g5.48xlarge (A10G)"
  type        = list(string)
}

variable "gpu_capacity_type" {
  description = "Capacity type for GPU instances: spot or on-demand"
  type        = list(string)
  default     = ["spot"]
}

################################################################################
# Network Configuration
################################################################################

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

################################################################################
# Karpenter Node Group Configuration
################################################################################

variable "karpenter_node_instance_types" {
  description = "Instance types for Karpenter controller node group"
  type        = list(string)
  default     = ["m5.large"]
}

variable "karpenter_node_min_size" {
  description = "Minimum number of nodes in Karpenter node group"
  type        = number
  default     = 2
}

variable "karpenter_node_max_size" {
  description = "Maximum number of nodes in Karpenter node group"
  type        = number
  default     = 3
}

variable "karpenter_node_desired_size" {
  description = "Desired number of nodes in Karpenter node group"
  type        = number
  default     = 2
}
