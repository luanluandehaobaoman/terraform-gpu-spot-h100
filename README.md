# Terraform GPU Spot H100

EKS 集群 Terraform 配置，支持 Karpenter 自动扩缩容和 H100 GPU Spot 实例。

## 架构

- **EKS 1.33** - Kubernetes 集群
- **Karpenter** - 节点自动扩缩容
- **AWS Load Balancer Controller** - ALB/NLB 支持
- **NVIDIA GPU 支持** - Bottlerocket 自带 device plugin，无需额外安装
- **SOCI Parallel Pull Mode** - 加速容器镜像拉取

## 部署的 AWS 资源

执行 `terraform apply` 后将创建以下资源：

### 网络资源
| 资源 | 数量 | 说明 |
|------|------|------|
| VPC | 1 | CIDR: 10.0.0.0/16 |
| Public Subnet | N | 每个 AZ 一个（自动探测 region 的全部 AZ） |
| Private Subnet | N | 每个 AZ 一个，用于 EKS 节点 |
| Intra Subnet | N | 每个 AZ 一个，用于 EKS Control Plane |
| NAT Gateway | 1 | 单 NAT 网关（成本优化） |
| Internet Gateway | 1 | |
| Elastic IP | 1 | NAT Gateway 使用 |

> **注意**: Subnet 数量 N 取决于部署 region 的 AZ 数量。例如 us-west-2 有 4 个 AZ，则创建 4 个 Private/Public/Intra Subnet。

### EKS 资源
| 资源 | 数量 | 说明 |
|------|------|------|
| EKS Cluster | 1 | Kubernetes 1.33 |
| EKS Managed Node Group | 1 | 2x m5.large (Karpenter 控制节点) |
| EKS Addons | 4 | coredns, kube-proxy, vpc-cni, eks-pod-identity-agent |

### Karpenter 资源
| 资源 | 数量 | 说明 |
|------|------|------|
| EC2NodeClass | 2 | default, h100-gpu |
| NodePool | 2 | default (c/m/r 系列), p5-gpu-h100 (H100 GPU) |
| SQS Queue | 1 | Spot 中断处理 |
| CloudWatch Event Rules | 4 | Spot 中断、实例状态变更等 |

### IAM 资源
| 资源 | 数量 | 说明 |
|------|------|------|
| IAM Role | 4 | EKS Cluster, Node Group, Karpenter, LB Controller |
| IAM Policy | 3 | Karpenter, LB Controller, Cluster Encryption |
| Pod Identity Association | 2 | Karpenter, LB Controller |

### 其他资源
| 资源 | 数量 | 说明 |
|------|------|------|
| KMS Key | 1 | EKS 加密 |
| CloudWatch Log Group | 1 | EKS 日志 |
| Security Group | 2 | Cluster SG, Node SG |
| Helm Release | 2 | Karpenter, AWS LB Controller |

**总计约 100+ AWS 资源**

> **注意**: NVIDIA Device Plugin 由 Bottlerocket AMI 自带，无需通过 Terraform 部署。

## 目录结构

```
terraform-gpu-spot-h100/
├── README.md
└── terraform-aws-eks/
    ├── karpenter/              # Terraform 入口
    │   ├── main.tf             # 主配置
    │   ├── versions.tf         # Provider 版本
    │   ├── variables.tf
    │   └── outputs.tf
    ├── modules/                # EKS 子模块
    └── test/                   # 测试 YAML
        ├── inflate.yaml        # Karpenter 扩缩容测试
        ├── vllm-h100.yaml      # vLLM H100 推理服务
        └── wan2.1-h100.yaml    # 私有 ECR 镜像测试
```

## 快速开始

### 前置条件

- Terraform >= 1.5.7
- AWS CLI 已配置 (`aws configure`)
- kubectl (可选，用于验证和管理集群)

### 部署

```bash
cd terraform-aws-eks/karpenter

# 初始化
terraform init

# 预览
terraform plan

# 部署 (约 15-20 分钟)
terraform apply --auto-approve
```

### 配置 kubectl

部署完成后，使用以下命令配置 kubectl：

```bash
# 方式 1: 使用 terraform output 自动获取命令
$(terraform output -raw configure_kubectl)

# 方式 2: 手动执行 (cluster_name 从 output 获取)
aws eks update-kubeconfig --name $(terraform output -raw cluster_name) --region us-west-2 --profile default
```

### 验证部署

```bash
# 检查节点
kubectl get nodes

# 检查 Karpenter
kubectl get nodepools,ec2nodeclasses

# 检查系统 Pod
kubectl get pods -n kube-system
```

> **注意**: Karpenter NodeClass/NodePool 会在 `terraform apply` 时自动部署，无需手动操作。

## NodePool 配置

### Default NodePool
- 实例类型: c/m/r 系列 (4-32 vCPU)
- 容量类型: Spot + On-Demand
- 用途: 通用工作负载

### H100 GPU NodePool (p5-gpu-h100)
- 实例类型: p5.48xlarge (8x H100 GPU)
- 容量类型: Spot
- Taint: `nvidia.com/gpu=true:NoSchedule`
- 用途: GPU 推理/训练

## SOCI Parallel Pull Mode

项目已启用 [SOCI (Seekable OCI) Parallel Pull Mode](https://aws.amazon.com/cn/blogs/containers/introducing-seekable-oci-parallel-pull-mode-for-amazon-eks/)，可显著加速容器镜像拉取。

### 优势

- **并行下载**: 同时下载多个镜像层，提升下载效率
- **并行解压**: 同时解压多个镜像层，减少等待时间
- **性能提升**: 对于 10GB+ 的大型 AI/ML 镜像，可减少约 60% 的拉取时间

### 配置详情

在 EC2NodeClass 的 `userData` 中配置 Bottlerocket SOCI 设置。

**Default NodeClass (通用节点)**：

```toml
[settings.container-runtime]
snapshotter = "soci"

[settings.container-runtime-plugins.soci-snapshotter]
pull-mode = "parallel-pull-unpack"

[settings.container-runtime-plugins.soci-snapshotter.parallel-pull-unpack]
max-concurrent-downloads-per-image = 10   # 每个镜像最大并行下载数
concurrent-download-chunk-size = "16mb"    # 下载块大小
max-concurrent-unpacks-per-image = 10      # 每个镜像最大并行解压数
discard-unpacked-layers = true             # 解压后丢弃原始层
```

### H100 GPU 节点优化配置

p5.48xlarge 是超高配置实例，针对其硬件特性进行了激进优化：

| 资源 | 配置 |
|------|------|
| vCPU | 192 核 |
| 内存 | 2TB |
| 网络 | 3200 Gbps EFA |
| Instance Store | 8x 3.84TB NVMe (RAID0) |

**优化后的 SOCI 配置**：

```toml
[settings.container-runtime]
snapshotter = "soci"

[settings.container-runtime-plugins.soci-snapshotter]
pull-mode = "parallel-pull-unpack"

[settings.container-runtime-plugins.soci-snapshotter.parallel-pull-unpack]
max-concurrent-downloads-per-image = 30   # 3200 Gbps 网络，大幅提升并发
concurrent-download-chunk-size = "32mb"    # 更大块减少 HTTP 请求
max-concurrent-unpacks-per-image = 30      # 192 核 CPU 充分并行解压
discard-unpacked-layers = true

# 将容器存储绑定到 instance store NVMe 盘以提升 IO 性能
[settings.bootstrap-commands.k8s-ephemeral-storage]
commands = [
    ["apiclient", "ephemeral-storage", "init"],
    ["apiclient", "ephemeral-storage", "bind", "--dirs", "/var/lib/containerd", "/var/lib/kubelet", "/var/log/pods", "/var/lib/soci-snapshotter"]
]
essential = true
mode = "always"
```

**参数调优说明**：

| 参数 | 默认值 | 通用节点 | H100 节点 | 说明 |
|------|--------|----------|-----------|------|
| max-concurrent-downloads-per-image | 3 | 10 | 30 | ECR 建议 10-20，高带宽可更高 |
| concurrent-download-chunk-size | 层大小 | 16mb | 32mb | 更大块减少请求开销 |
| max-concurrent-unpacks-per-image | 1 | 10 | 30 | 根据 CPU 核心数调整 |

### 实测结果

在 p5.48xlarge + SOCI Parallel Pull 优化配置下的实际测试：

| 测试镜像 | 镜像大小 | 拉取时间 | 平均速度 |
|----------|----------|----------|----------|
| `public.ecr.aws/.../vllm` (Public ECR) | 14.24 GB | 2m27s (147s) | ~99 MB/s |
| `<AWS_ACCOUNT_ID>.dkr.ecr.../vllm` (Private ECR) | 14.24 GB | **34.9s** | **~408 MB/s** |
| `<AWS_ACCOUNT_ID>.dkr.ecr.../wan2.1` (Private ECR) | 10.97 GB | **29.7s** | **~370 MB/s** |

**测试环境**：
- 实例类型: p5.48xlarge (192 vCPU, 2TB RAM)
- 存储: Instance Store NVMe (RAID0, 8x 3.84TB)
- 测试日期: 2025-12-20
- Region: us-west-2

> **关键发现**：
> - **Private ECR vs Public ECR**: 同一镜像 (vLLM 14.24GB)，私有 ECR 快 **4.2 倍**！
> - **对比 AWS 官方基准** (m6i.8xlarge + SOCI 拉取 10GB 镜像: 45s)
> - 本项目 p5.48xlarge 拉取 14.24GB 镜像仅需 **34.9s**，性能卓越！

### 参考文档

- [Introducing Seekable OCI Parallel Pull Mode for Amazon EKS](https://aws.amazon.com/cn/blogs/containers/introducing-seekable-oci-parallel-pull-mode-for-amazon-eks/)
- [SOCI Snapshotter Karpenter Blueprint](https://github.com/aws-samples/karpenter-blueprints/tree/main/blueprints/soci-snapshotter)
- [Bottlerocket SOCI Configuration](https://bottlerocket.dev/en/os/1.44.x/api/settings/container-runtime-plugins/#tag-soci-parallel-pull-configuration)

## 测试

### 测试 Karpenter 扩缩容

```bash
kubectl apply -f test/inflate.yaml
kubectl get nodes -w
kubectl delete -f test/inflate.yaml
```

### 测试 H100 GPU 节点

```bash
kubectl apply -f test/vllm-h100.yaml
kubectl get pods -w
```

## 配置说明

| 参数 | 默认值 | 说明 |
|------|--------|------|
| region | us-west-2 | AWS Region |
| kubernetes_version | 1.33 | EKS 版本 |
| vpc_cidr | 10.0.0.0/16 | VPC CIDR |

### AZ 自动探测

部署时会自动探测当前 region 的全部可用区（AZ），并在每个 AZ 创建 subnet。这样做的好处：

1. **提高 Spot 获取成功率**: 更多 AZ = 更多 Spot 容量池，H100 等稀缺资源获取概率更高
2. **更好的高可用性**: 工作负载可分散到更多 AZ
3. **零额外成本**: 保持单一 NAT Gateway，不因 AZ 增加而增加成本

**Subnet CIDR 分配策略** (VPC: 10.0.0.0/16):

| Subnet 类型 | CIDR 范围 | 每个 Subnet | 可用 IP/AZ | 用途 |
|-------------|-----------|-------------|------------|------|
| Private | 10.0.0.0 - 10.0.127.255 | /20 | 4,091 | 工作节点和 Pod |
| Public | 10.0.128.0 - 10.0.191.255 | /24 | 251 | NAT Gateway, ELB |
| Intra | 10.0.192.0 - 10.0.255.255 | /24 | 251 | EKS Control Plane ENI |

> 此配置最多支持 8 个 AZ，覆盖所有 AWS region。

## 部署到不同 Region

默认部署到 `us-west-2`。如需部署到其他 Region，修改 `terraform-aws-eks/karpenter/main.tf` 中的 `locals` 块：

```hcl
locals {
  name               = "eks-spot-gpu-${random_string.suffix.result}"
  region             = "ap-northeast-1"  # 修改为目标 Region
  # ...
}
```

### 修改 GPU 实例类型

如需使用其他 GPU 实例，修改 `main.tf` 中的 `nodepool_h100` 配置：

```hcl
# 例如改用 p4d.24xlarge (A100 GPU)
requirements = [
  { key = "karpenter.sh/capacity-type", operator = "In", values = ["spot", "on-demand"] },
  { key = "kubernetes.io/arch", operator = "In", values = ["amd64"] },
  { key = "node.kubernetes.io/instance-type", operator = "In", values = ["p4d.24xlarge"] }
]
```

## Terraform Outputs

| Output | 说明 |
|--------|------|
| cluster_name | EKS 集群名称 |
| cluster_endpoint | EKS API Server 地址 |
| cluster_version | Kubernetes 版本 |
| region | AWS Region |
| configure_kubectl | 配置 kubectl 的完整命令 |

## 清理

```bash
cd terraform-aws-eks/karpenter
terraform destroy --auto-approve
```

## License

Apache 2.0
