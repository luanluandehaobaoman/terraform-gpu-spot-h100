# Terraform GPU Spot H100

EKS 集群 Terraform 配置，支持 Karpenter 自动扩缩容和 H100 GPU Spot 实例。

## 架构

- **EKS 1.34** - Kubernetes 集群
- **Karpenter** - 节点自动扩缩容
- **AWS Load Balancer Controller** - ALB/NLB 支持
- **NVIDIA Device Plugin** - GPU 资源管理

## 部署的 AWS 资源

执行 `terraform apply` 后将创建以下资源：

### 网络资源
| 资源 | 数量 | 说明 |
|------|------|------|
| VPC | 1 | CIDR: 10.0.0.0/16 |
| Public Subnet | 3 | 每个 AZ 一个 |
| Private Subnet | 3 | 每个 AZ 一个，用于 EKS 节点 |
| Intra Subnet | 3 | 每个 AZ 一个，用于 EKS Control Plane |
| NAT Gateway | 1 | 单 NAT 网关 |
| Internet Gateway | 1 | |
| Elastic IP | 1 | NAT Gateway 使用 |

### EKS 资源
| 资源 | 数量 | 说明 |
|------|------|------|
| EKS Cluster | 1 | Kubernetes 1.34 |
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
| DaemonSet | 1 | NVIDIA Device Plugin |

**总计约 100+ AWS 资源**

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
        └── vllm-h100.yaml      # vLLM H100 推理服务
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
| kubernetes_version | 1.34 | EKS 版本 |
| vpc_cidr | 10.0.0.0/16 | VPC CIDR |

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
