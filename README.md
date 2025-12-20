# Terraform GPU Spot H100

EKS 集群 Terraform 配置，支持 Karpenter 自动扩缩容和 H100 GPU Spot 实例。

## 架构

- **EKS 1.34** - Kubernetes 集群
- **Karpenter** - 节点自动扩缩容
- **AWS Load Balancer Controller** - ALB/NLB 支持
- **NVIDIA Device Plugin** - GPU 资源管理

## 目录结构

```
terraform-gpu-spot-h100/
├── README.md
└── terraform-aws-eks/
    ├── karpenter/              # Terraform 入口
    │   ├── main.tf             # 主配置
    │   ├── versions.tf         # Provider 版本
    │   ├── variables.tf
    │   ├── outputs.tf
    │   └── karpenter.yaml      # NodeClass + NodePool
    ├── modules/                # EKS 子模块
    ├── templates/              # User data 模板
    └── test/                   # 测试 YAML
        ├── inflate.yaml        # Karpenter 扩缩容测试
        └── vllm-h100.yaml      # vLLM H100 推理服务
```

## 快速开始

### 前置条件

- Terraform >= 1.5.7
- AWS CLI 已配置 (`aws configure`)
- kubectl

### 部署

```bash
cd terraform-aws-eks/karpenter

# 初始化
terraform init

# 预览
terraform plan

# 部署
terraform apply
```

### 配置 kubectl

```bash
aws eks update-kubeconfig --name <cluster-name> --region us-west-2 --profile default
```

### 部署 Karpenter NodeClass/NodePool

```bash
kubectl apply -f karpenter.yaml
```

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

## 清理

```bash
cd terraform-aws-eks/karpenter
terraform destroy
```

## License

Apache 2.0
