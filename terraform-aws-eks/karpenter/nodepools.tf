################################################################################
# Karpenter NodeClass & NodePool (auto-deployed via Terraform)
# Using kubectl_manifest to avoid plan-time cluster connection requirement
################################################################################

################################################################################
# Default EC2NodeClass - 通用节点
################################################################################

resource "kubectl_manifest" "ec2nodeclass_default" {
  yaml_body = yamlencode({
    apiVersion = "karpenter.k8s.aws/v1"
    kind       = "EC2NodeClass"
    metadata = {
      name = "default"
    }
    spec = {
      amiSelectorTerms = [{ alias = "bottlerocket@latest" }]
      role             = local.karpenter_discovery
      subnetSelectorTerms = [{
        tags = { "karpenter.sh/discovery" = local.karpenter_discovery }
      }]
      securityGroupSelectorTerms = [{
        tags = { "karpenter.sh/discovery" = local.karpenter_discovery }
      }]
      tags = { "karpenter.sh/discovery" = local.karpenter_discovery }
      # SOCI Parallel Pull Mode - 加速容器镜像拉取
      # https://aws.amazon.com/cn/blogs/containers/introducing-seekable-oci-parallel-pull-mode-for-amazon-eks/
      userData = <<-EOT
        [settings.container-runtime]
        snapshotter = "soci"

        [settings.container-runtime-plugins.soci-snapshotter]
        pull-mode = "parallel-pull-unpack"

        [settings.container-runtime-plugins.soci-snapshotter.parallel-pull-unpack]
        max-concurrent-downloads-per-image = 10
        concurrent-download-chunk-size = "16mb"
        max-concurrent-unpacks-per-image = 10
        discard-unpacked-layers = true
      EOT
    }
  })
  depends_on = [helm_release.karpenter]
}

################################################################################
# Default NodePool - 通用工作负载
################################################################################

resource "kubectl_manifest" "nodepool_default" {
  yaml_body = yamlencode({
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata = {
      name = "default"
    }
    spec = {
      template = {
        spec = {
          nodeClassRef = {
            group = "karpenter.k8s.aws"
            kind  = "EC2NodeClass"
            name  = "default"
          }
          requirements = [
            { key = "kubernetes.io/arch", operator = "In", values = ["amd64"] },
            { key = "karpenter.k8s.aws/instance-category", operator = "In", values = ["c", "m", "r"] },
            { key = "karpenter.k8s.aws/instance-cpu", operator = "In", values = ["4", "8", "16", "32"] },
            { key = "karpenter.k8s.aws/instance-hypervisor", operator = "In", values = ["nitro"] },
            { key = "karpenter.k8s.aws/instance-generation", operator = "Gt", values = ["2"] }
          ]
        }
      }
      limits     = { cpu = 1000 }
      disruption = { consolidationPolicy = "WhenEmpty", consolidateAfter = "30s" }
    }
  })
  depends_on = [kubectl_manifest.ec2nodeclass_default]
}

################################################################################
# GPU EC2NodeClass - GPU Spot 实例
# 默认配置针对高配置 GPU 实例优化（如 p5.48xlarge）
# 可根据实际使用的 GPU 实例类型调整 SOCI 参数
################################################################################

resource "kubectl_manifest" "ec2nodeclass_gpu" {
  yaml_body = yamlencode({
    apiVersion = "karpenter.k8s.aws/v1"
    kind       = "EC2NodeClass"
    metadata = {
      name = "gpu"
    }
    spec = {
      amiSelectorTerms    = [{ alias = "bottlerocket@latest" }]
      role                = local.karpenter_discovery
      instanceStorePolicy = "RAID0"
      securityGroupSelectorTerms = [{
        tags = { "karpenter.sh/discovery" = local.karpenter_discovery }
      }]
      subnetSelectorTerms = [{
        tags = { "karpenter.sh/discovery" = local.karpenter_discovery }
      }]
      tags = {
        "karpenter.sh/discovery" = local.karpenter_discovery
        "gpu-type"               = "nvidia"
      }
      # SOCI Parallel Pull Mode - 加速大型 AI/ML 镜像拉取
      # https://aws.amazon.com/cn/blogs/containers/introducing-seekable-oci-parallel-pull-mode-for-amazon-eks/
      # 针对高配置 GPU 实例优化（高带宽网络、多核 CPU、NVMe SSD）
      userData = <<-EOT
        [settings.container-runtime]
        snapshotter = "soci"

        [settings.container-runtime-plugins.soci-snapshotter]
        pull-mode = "parallel-pull-unpack"

        [settings.container-runtime-plugins.soci-snapshotter.parallel-pull-unpack]
        max-concurrent-downloads-per-image = 30
        concurrent-download-chunk-size = "32mb"
        max-concurrent-unpacks-per-image = 30
        discard-unpacked-layers = true

        # 将容器存储绑定到 instance store NVMe 盘以提升 IO 性能
        [settings.bootstrap-commands.k8s-ephemeral-storage]
        commands = [
            ["apiclient", "ephemeral-storage", "init"],
            ["apiclient", "ephemeral-storage", "bind", "--dirs", "/var/lib/containerd", "/var/lib/kubelet", "/var/log/pods", "/var/lib/soci-snapshotter"]
        ]
        essential = true
        mode = "always"
      EOT
    }
  })
  depends_on = [helm_release.karpenter]
}

################################################################################
# GPU NodePool - Spot 实例
# 使用 var.gpu_instance_types 配置 GPU 实例类型
# 默认: p5.48xlarge (H100)
# 可选: p4d.24xlarge (A100), g5.48xlarge (A10G) 等
################################################################################

resource "kubectl_manifest" "nodepool_gpu" {
  yaml_body = yamlencode({
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata = {
      name = "gpu-spot"
    }
    spec = {
      disruption = { consolidateAfter = "1h", consolidationPolicy = "WhenEmpty" }
      template = {
        metadata = {
          labels = { "gpu-type" = "nvidia", "nodepool" = "gpu-spot" }
        }
        spec = {
          nodeClassRef = {
            group = "karpenter.k8s.aws"
            kind  = "EC2NodeClass"
            name  = "gpu"
          }
          requirements = [
            { key = "karpenter.sh/capacity-type", operator = "In", values = var.gpu_capacity_type },
            { key = "kubernetes.io/arch", operator = "In", values = ["amd64"] },
            { key = "node.kubernetes.io/instance-type", operator = "In", values = var.gpu_instance_types }
          ]
          taints = [{ key = "nvidia.com/gpu", value = "true", effect = "NoSchedule" }]
        }
      }
    }
  })
  depends_on = [kubectl_manifest.ec2nodeclass_gpu]
}
