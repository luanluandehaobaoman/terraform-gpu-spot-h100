# Terraform EKS GPU Spot

EKS 集群 Terraform 配置，支持 Karpenter 自动扩缩容和 **GPU Spot 实例**。

## 架构

- **EKS 1.33** + **Karpenter** 自动扩缩容
- **GPU Spot 实例** - 默认 H100 (p5.48xlarge)，可配置其他类型
- **AWS Load Balancer Controller** - ALB/NLB 支持
- **SOCI Parallel Pull Mode** - 加速大型 AI/ML 镜像拉取
- **Bottlerocket OS** - 自带 NVIDIA Device Plugin

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

terraform init
terraform plan
terraform apply --auto-approve    # 约 15-20 分钟
```

**部署到其他 Region 或修改 GPU 类型**：

```bash
# 方式 1: 命令行参数
terraform apply -var="region=ap-northeast-1" -var='gpu_instance_types=["p4d.24xlarge"]'

# 方式 2: 创建 terraform.tfvars 文件
cat > terraform.tfvars <<EOF
region = "ap-northeast-1"
gpu_instance_types = ["p4d.24xlarge", "g5.48xlarge"]
EOF
terraform apply
```

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
| `region` | us-west-2 | AWS Region |
| `gpu_instance_types` | ["p5.48xlarge"] | GPU 实例类型 |
| `gpu_capacity_type` | ["spot"] | spot 或 on-demand |
| `vpc_cidr` | 10.0.0.0/16 | VPC CIDR |
| `cluster_name_prefix` | eks-spot-gpu | 集群名称前缀 |

## NodePool 说明

| NodePool | 实例类型 | 容量类型 | 用途 |
|----------|----------|----------|------|
| default | c/m/r 系列 | Spot + On-Demand | 通用工作负载 |
| gpu-spot | 可配置 GPU | Spot | GPU 推理/训练 |

GPU NodePool 带有 Taint `nvidia.com/gpu=true:NoSchedule`，需要在 Pod 中添加对应 Toleration。

## SOCI Parallel Pull Mode

已启用 [SOCI Parallel Pull](https://aws.amazon.com/cn/blogs/containers/introducing-seekable-oci-parallel-pull-mode-for-amazon-eks/) 加速镜像拉取：

| 节点类型 | 并发下载 | 块大小 | 适用场景 |
|----------|----------|--------|----------|
| 通用节点 | 10 | 16MB | 常规镜像 |
| GPU 节点 | 30 | 32MB | 大型 AI/ML 镜像 |

实测：14GB 镜像在 Private ECR 上 **35 秒**完成拉取（~408 MB/s）。

## 测试

```bash
# 测试 Karpenter 扩缩容
kubectl apply -f test/inflate.yaml
kubectl get nodes -w

# 测试 GPU 节点
kubectl apply -f test/vllm-gpu.yaml
```

## 清理

```bash
terraform destroy --auto-approve
```

## License

Apache 2.0
