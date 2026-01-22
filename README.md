# Terraform EKS GPU Spot

EKS 集群 Terraform 配置，支持 Karpenter 自动扩缩容和 **GPU Spot 实例**。

## 架构

- **EKS 1.33** + **Karpenter** 自动扩缩容
- **GPU Spot 实例** - 默认 H100 (p5.48xlarge)，可配置其他类型
- **AWS Load Balancer Controller** - ALB/NLB 支持
- **SOCI Parallel Pull Mode** - 加速大型 AI/ML 镜像拉取
- **Bottlerocket OS** - 自带 NVIDIA Device Plugin

### 可用区策略

| 组件 | AZ 数量 | 说明 |
|------|---------|------|
| **Worker 节点** | 所有可用 AZ | 最大化 Spot 实例获取成功率 |
| **控制平面** | 2-3 个 | 排除不支持 EKS 的 AZ（如 us-east-1e） |

Worker 节点使用 Region 内所有可用区的 Private Subnets，提高 Spot 实例调度成功率。控制平面只需要 2-3 个 AZ 即可保证高可用，自动排除已知不支持 EKS 控制平面的 AZ。

## 目录结构

```
terraform-aws-eks/karpenter/        # 主要工作目录
├── main.tf                         # Provider、EKS、VPC
├── karpenter.tf                    # Karpenter 模块
├── nodepools.tf                    # NodePool 配置
├── alb-controller.tf               # ALB Controller
├── variables.tf                    # 可配置变量
├── outputs.tf
└── versions.tf
```

## 快速开始

### 前置条件

- Terraform >= 1.5.7
- AWS CLI 已配置 (`aws configure`)

### 部署

```bash
cd terraform-aws-eks/karpenter

# 1. 配置必要变量（二选一）
# 方式 A: 复制示例文件并修改
cp terraform.tfvars.example terraform.tfvars
# 编辑 terraform.tfvars 设置 region 和 gpu_instance_types

# 方式 B: 使用命令行参数（见下方）

# 2. 部署
terraform init
terraform plan
terraform apply --auto-approve
```

**配置示例**：

```bash
# 方式 1: 使用 tfvars 文件（推荐）
cat > terraform.tfvars <<EOF
region = "us-west-2"
gpu_instance_types = ["p5.48xlarge"]
EOF
terraform apply

# 方式 2: 命令行参数
terraform apply -var="region=ap-northeast-1" -var='gpu_instance_types=["p4d.24xlarge"]'
```

> **注意**：`region` 和 `gpu_instance_types` 是必填变量，部署前必须配置。

### 配置 kubectl

```bash
$(terraform output -raw configure_kubectl)
```

### 验证

```bash
kubectl get nodes
kubectl get nodepools,ec2nodeclasses
```

## 可配置变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `region` | **必填** | AWS Region |
| `gpu_instance_types` | **必填** | GPU 实例类型 |
| `gpu_capacity_type` | ["spot"] | spot 或 on-demand |
| `vpc_cidr` | 10.0.0.0/16 | VPC CIDR |
| `cluster_name_prefix` | eks-spot-gpu | 集群名称前缀 |

详细配置说明见 `terraform.tfvars.example` 文件。

## NodePool 说明

| NodePool | 实例类型 | 容量类型 | 用途 |
|----------|----------|----------|------|
| default | c/m/r 系列 | Spot + On-Demand | 通用工作负载 |
| gpu-spot | 可配置 GPU | Spot | GPU 推理/训练 |

GPU NodePool 带有 Taint `nvidia.com/gpu=true:NoSchedule`，需要在 Pod 中添加对应 Toleration。

## SOCI Parallel Pull Mode

已启用 [SOCI Parallel Pull](https://aws.amazon.com/cn/blogs/containers/introducing-seekable-oci-parallel-pull-mode-for-amazon-eks/) 加速镜像拉取，对 10GB+ 的大型 AI/ML 镜像可减少约 60% 拉取时间。

### 配置参数

| 节点类型 | 并发下载 | 块大小 | 并发解压 |
|----------|----------|--------|----------|
| 通用节点 | 10 | 16MB | 10 |
| GPU 节点 | 30 | 32MB | 30 |

GPU 节点额外配置了 NVMe 实例存储绑定，提升 IO 性能：

```toml
[settings.bootstrap-commands.k8s-ephemeral-storage]
commands = [
    ["apiclient", "ephemeral-storage", "init"],
    ["apiclient", "ephemeral-storage", "bind", "--dirs", "/var/lib/containerd", "/var/lib/kubelet"]
]
```

### 实测结果

| 镜像源 | 镜像大小 | 拉取时间 | 速度 |
|--------|----------|----------|------|
| Public ECR | 14.24 GB | 2m27s | ~99 MB/s |
| **Private ECR** | 14.24 GB | **35s** | **~408 MB/s** |

> 💡 **建议**：将大型镜像复制到 Private ECR，可获得 4x 性能提升。

### 参考文档

- [SOCI Parallel Pull Mode 官方博客](https://aws.amazon.com/cn/blogs/containers/introducing-seekable-oci-parallel-pull-mode-for-amazon-eks/)
- [Bottlerocket SOCI 配置](https://bottlerocket.dev/en/os/1.44.x/api/settings/container-runtime-plugins/)

## 测试

```bash
# 测试 Karpenter 扩缩容
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inflate
spec:
  replicas: 5
  selector:
    matchLabels:
      app: inflate
  template:
    metadata:
      labels:
        app: inflate
    spec:
      containers:
      - name: inflate
        image: public.ecr.aws/eks-distro/kubernetes/pause:3.7
        resources:
          requests:
            cpu: 1
EOF

kubectl get nodes -w

# 清理测试
kubectl delete deployment inflate
```

## 清理

```bash
terraform destroy --auto-approve
```

## License

Apache 2.0
