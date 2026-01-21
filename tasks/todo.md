# 任务：项目通用化重构

## 目标
将项目从专门针对 H100 改为支持所有 GPU Spot 实例的通用方案，H100 作为默认示例。

## 重构方案

### 1. 项目定位变更

| 项目 | 修改前 | 修改后 |
|------|--------|--------|
| 项目名称 | terraform-gpu-spot-h100 | terraform-eks-gpu-spot |
| 定位 | 专门针对 H100 | 通用 GPU Spot 方案 |
| H100 地位 | 核心功能 | 默认示例（可替换） |

### 2. 资源命名变更

| 资源 | 修改前 | 修改后 |
|------|--------|--------|
| EC2NodeClass | `h100-gpu` | `gpu` |
| NodePool | `p5-gpu-h100` | `gpu-spot` |
| Terraform 资源名 | `ec2nodeclass_h100` | `ec2nodeclass_gpu` |
| Terraform 资源名 | `nodepool_h100` | `nodepool_gpu` |
| Tag | `gpu-type = "h100"` | `gpu-type = "nvidia"` |

### 3. 文件变更

| 文件 | 改动 |
|------|------|
| `README.md` | 通用化描述 |
| `main.tf` | 重命名资源，添加注释说明如何替换 GPU 类型 |
| `test/vllm-h100.yaml` | 重命名为 `vllm-gpu.yaml` |
| `test/wan2.1-h100.yaml` | 已删除 |

---

## 实现计划

### [x] 1. 规划重构方案
### [x] 2. 修改 README.md
### [x] 3. 修改 main.tf
### [x] 4. 重命名测试文件
### [x] 5. 提交并推送到 dev 分支

---

## Review

### 2025-01-21 重构完成

**修改的文件:**

1. `README.md`
   - 标题从 "Terraform GPU Spot H100" 改为 "Terraform EKS GPU Spot"
   - 添加说明：默认使用 H100 作为示例，可轻松替换
   - 更新 Karpenter 资源表格（h100-gpu → gpu, p5-gpu-h100 → gpu-spot）
   - 目录结构中文件名更新
   - 新增 "修改 GPU 实例类型" 章节，提供多个示例
   - 通用化 SOCI 配置说明（从 H100 特定改为通用 GPU）

2. `terraform-aws-eks/karpenter/main.tf`
   - `ec2nodeclass_h100` → `ec2nodeclass_gpu`
   - `h100-gpu` → `gpu`
   - `nodepool_h100` → `nodepool_gpu`
   - `p5-gpu-h100` → `gpu-spot`
   - `gpu-type = "h100"` → `gpu-type = "nvidia"`
   - 添加详细注释说明如何切换 GPU 实例类型

3. `terraform-aws-eks/test/vllm-h100.yaml` → `vllm-gpu.yaml`
   - 更新 nodeSelector 使用新的 nodepool 名称 `gpu-spot`
   - 更新资源命名为通用名称
   - 添加注释说明如何修改 GPU 实例类型

4. `terraform-aws-eks/test/wan2.1-h100.yaml`
   - 已删除（不再需要）

**Git 操作:**

- Commit: `refactor: generalize project from H100-specific to universal GPU Spot support`
- 推送到 dev 分支 (287b12d)

**注意事项:**

- GitHub 仓库名称需要手动在 GitHub Settings 中修改
- 已有部署需要重新 `terraform apply` 以更新资源名称

---

# Dev 分支代码审查报告

审查时间: 2026-01-21
审查范围: 整个 dev 分支

---

## 审查总结

项目整体结构清晰，Terraform 配置完整，但存在一些需要关注的问题。

### ✅ 优点

1. **功能完整**: EKS + Karpenter + GPU Spot 集成方案完整
2. **文档详尽**: README.md 详细说明了部署步骤和配置选项
3. **成本优化**: 单 NAT Gateway、Spot 优先、自动扩缩容
4. **性能优化**: SOCI Parallel Pull Mode 加速镜像拉取
5. **安全增强**: KMS 加密、Pod Identity、IRSA

---

## ⚠️ 发现的问题

### 1. 代码行数超标（严重）

根据项目规范，静态语言文件不应超过 **400 行**。以下文件超标：

| 文件 | 行数 | 超标 |
|------|------|------|
| `terraform-aws-eks/variables.tf` | 1508 | +1108 |
| `terraform-aws-eks/modules/self-managed-node-group/main.tf` | 1104 | +704 |
| `terraform-aws-eks/modules/self-managed-node-group/variables.tf` | 1029 | +629 |
| `terraform-aws-eks/main.tf` | 939 | +539 |
| `terraform-aws-eks/modules/eks-managed-node-group/variables.tf` | 789 | +389 |
| `terraform-aws-eks/karpenter/main.tf` | 730 | +330 |
| `terraform-aws-eks/node_groups.tf` | 545 | +145 |

**建议**: 这些是 terraform-aws-modules 官方模块的标准结构，为保持与上游的兼容性，暂不建议拆分。但 `karpenter/main.tf` 是自定义配置，建议拆分为：
- `main.tf` - EKS 和 VPC 基础设施
- `karpenter.tf` - Karpenter 配置
- `alb-controller.tf` - AWS Load Balancer Controller
- `nodepools.tf` - NodePool 和 EC2NodeClass 定义

### 2. 安全配置需审视

#### 2.1 EKS API Endpoint 公开访问

**文件**: `karpenter/main.tf:101`
```hcl
endpoint_public_access = true
```

**风险等级**: 中
**说明**: EKS API endpoint 对公网开放，虽然有 IAM 认证保护，但增加了攻击面
**建议**: 生产环境考虑设置为 `false` 并通过 VPN/堡垒机访问

#### 2.2 IAM 策略过于宽松

**文件**: `karpenter/main.tf:390-626`

AWS Load Balancer Controller IAM 策略多处使用 `"Resource": "*"`：
```hcl
{
  Effect = "Allow"
  Action = [
    "ec2:DescribeAccountAttributes",
    # ... 大量 Action
  ]
  Resource = "*"  # 过于宽松
}
```

**风险等级**: 低
**说明**: 这是 AWS 官方推荐的策略，但在严格安全环境下可进一步收紧
**建议**: 评估是否需要收紧 Resource 范围

### 3. 空文件

**文件**: `karpenter/variables.tf`

该文件只有 1 行空内容，应该要么删除，要么添加有意义的变量定义。

### 4. 硬编码配置

#### 4.1 Region 硬编码

**文件**: `karpenter/main.tf:74`
```hcl
region = "us-west-2"
```

**建议**: 考虑提取为变量或环境变量，便于多 region 部署

#### 4.2 实例类型硬编码

**文件**: `karpenter/main.tf:376`
```hcl
{ key = "node.kubernetes.io/instance-type", operator = "In", values = ["p5.48xlarge"] }
```

**建议**: 考虑提取为变量，方便用户自定义

### 5. 代码架构问题

#### 5.1 职责混合

**文件**: `karpenter/main.tf`

单个文件包含了多个不同职责：
- VPC 配置
- EKS 集群配置
- Karpenter 配置
- AWS Load Balancer Controller 配置
- NodePool/EC2NodeClass 配置

**建议**: 按职责拆分为多个文件

#### 5.2 内联策略过长

**文件**: `karpenter/main.tf:390-626`

AWS Load Balancer Controller IAM 策略定义约 **236 行**，直接内联在 main.tf 中。

**建议**:
- 使用外部 JSON 文件 + `file()` 函数
- 或使用官方提供的策略 ARN

### 6. 特殊变量

**文件**: `terraform-aws-eks/variables.tf:1504-1508`
```hcl
variable "putin_khuylo" {
  description = "Do you agree that Putin doesn't respect Ukrainian sovereignty..."
  type        = bool
  default     = true
}
```

**说明**: 这是 terraform-aws-modules 官方模块的一个政治声明变量，保持原样即可。

---

## 📋 建议优化清单

- [ ] **P1**: 拆分 `karpenter/main.tf` 为多个文件
- [ ] **P2**: 将 region 和 GPU 实例类型提取为变量
- [ ] **P2**: 评估 `endpoint_public_access` 的安全需求
- [ ] **P3**: 处理空的 `variables.tf` 文件
- [ ] **P3**: 将 ALB Controller IAM 策略提取为外部文件

---

## 总结

dev 分支代码整体质量良好，功能完整，文档详细。主要问题集中在：

1. **代码组织**: 部分文件行数超标，但大多数是上游模块，`karpenter/main.tf` 建议拆分
2. **配置灵活性**: 部分配置硬编码，建议参数化
3. **安全配置**: EKS endpoint 公开访问需要根据实际场景评估

**审查结论**: 可以合并到 main，建议后续迭代中处理上述 P1/P2 优先级的问题

---

# 代码重构：拆分 karpenter/main.tf

重构时间: 2026-01-21

## 目标

将 730 行的 `karpenter/main.tf` 拆分为 4 个文件，并将硬编码配置提取为变量。

## 重构内容

### 1. 文件拆分

| 新文件 | 行数 | 内容 |
|--------|------|------|
| `main.tf` | ~205 | Provider、EKS、VPC 基础设施 |
| `karpenter.tf` | ~57 | Karpenter 模块和 Helm |
| `nodepools.tf` | ~175 | EC2NodeClass 和 NodePool 定义 |
| `alb-controller.tf` | ~261 | AWS Load Balancer Controller |
| `variables.tf` | ~68 | 可配置变量定义 |

### 2. 变量化配置

新增变量：

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `region` | us-west-2 | AWS Region |
| `cluster_name_prefix` | eks-spot-gpu | 集群名称前缀 |
| `gpu_instance_types` | ["p5.48xlarge"] | GPU 实例类型 |
| `gpu_capacity_type` | ["spot"] | 容量类型 |
| `vpc_cidr` | 10.0.0.0/16 | VPC CIDR |
| `karpenter_node_instance_types` | ["m5.large"] | Karpenter 节点实例类型 |
| `karpenter_node_min/max/desired_size` | 2/3/2 | 节点数量配置 |

### 3. README.md 更新

- 更新目录结构说明
- 新增变量配置说明
- 更新部署到不同 Region 的方式

## 修改的文件

1. `terraform-aws-eks/karpenter/main.tf` - 精简为基础设施配置
2. `terraform-aws-eks/karpenter/karpenter.tf` - 新建
3. `terraform-aws-eks/karpenter/nodepools.tf` - 新建
4. `terraform-aws-eks/karpenter/alb-controller.tf` - 新建
5. `terraform-aws-eks/karpenter/variables.tf` - 新建变量定义
6. `terraform-aws-eks/karpenter/outputs.tf` - 更新 region 引用
7. `README.md` - 更新文档
