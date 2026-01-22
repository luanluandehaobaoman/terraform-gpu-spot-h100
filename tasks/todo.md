# 任务：强制用户配置 region 和 gpu_instance_types 变量

## 背景

当前 `variables.tf` 中的 `region` 和 `gpu_instance_types` 变量都有默认值：
- `region` 默认为 `"us-west-2"`
- `gpu_instance_types` 默认为 `["p5.48xlarge"]`

这样用户可以直接运行 `terraform apply` 而不配置这些关键变量，可能导致意外部署到错误的 Region 或使用不适合的 GPU 实例类型。

## 目标

强制用户在 `terraform apply` 前明确配置 `region` 和 `gpu_instance_types` 变量。

## 计划

- [x] 1. 修改 `variables.tf`：移除 `region` 和 `gpu_instance_types` 的默认值
- [x] 2. 创建 `terraform.tfvars.example` 示例文件，帮助用户快速配置
- [x] 3. 更新 `README.md`：明确说明部署前需要先配置变量

## 预期结果

用户运行 `terraform apply` 时，如果没有通过 `-var` 参数或 `terraform.tfvars` 文件提供 `region` 和 `gpu_instance_types`，Terraform 会报错并要求用户提供这些值。

---

## Review

### 变更文件

1. **`terraform-aws-eks/karpenter/variables.tf`**
   - 移除 `region` 变量的 `default = "us-west-2"`
   - 移除 `gpu_instance_types` 变量的 `default = ["p5.48xlarge"]`
   - 更新 description 标注为 required

2. **`terraform-aws-eks/karpenter/terraform.tfvars.example`** (新建)
   - 提供完整的配置示例
   - 包含所有 GPU 实例类型选项说明
   - 包含可选变量的注释说明

3. **`README.md`**
   - 更新部署步骤，先配置变量再部署
   - 更新变量表格，标明必填项
   - 添加指向 tfvars.example 的引用

### 用户体验

修改后，用户必须：
1. 复制 `terraform.tfvars.example` 为 `terraform.tfvars` 并配置
2. 或使用 `-var` 命令行参数指定变量

否则 Terraform 会报错提示缺少必要变量。
