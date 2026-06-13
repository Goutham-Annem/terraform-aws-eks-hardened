# terraform-aws-eks-hardened

> Production-grade, CIS-aligned EKS Terraform module with private endpoints, IRSA, envelope encryption, and Karpenter.

[![Terraform Registry](https://img.shields.io/badge/terraform-registry-blue)](https://registry.terraform.io/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

## Features

- **Private API endpoint** — control plane not exposed to public internet
- **Envelope encryption** — Kubernetes secrets encrypted via AWS KMS
- **IRSA** — IAM Roles for Service Accounts, no node-level credentials
- **Managed node groups** — Bottlerocket AMI, launch template, custom user-data
- **Karpenter** — event-driven node provisioning, replaces Cluster Autoscaler
- **CIS Benchmark aligned** — EKS CIS 1.4 controls where Terraform-configurable
- **VPC CNI / CoreDNS / kube-proxy** — managed add-ons with version pinning

## Usage

```hcl
module "eks" {
  source  = "goutham-annem/eks-hardened/aws"
  version = "~> 1.0"

  cluster_name    = "my-prod-cluster"
  cluster_version = "1.30"
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnets

  # Private endpoint only (CIS 5.4.1)
  cluster_endpoint_public_access  = false
  cluster_endpoint_private_access = true

  # KMS encryption for secrets (CIS 5.3.1)
  create_kms_key = true

  # Node groups
  node_groups = {
    system = {
      instance_types = ["m5.large"]
      min_size       = 2
      max_size       = 4
      desired_size   = 2
      ami_type       = "BOTTLEROCKET_x86_64"
      labels         = { role = "system" }
      taints         = [{ key = "CriticalAddonsOnly", value = "true", effect = "NO_SCHEDULE" }]
    }
    apps = {
      instance_types = ["m5.xlarge", "m5.2xlarge"]
      min_size       = 0
      max_size       = 50
      desired_size   = 2
      ami_type       = "BOTTLEROCKET_x86_64"
      capacity_type  = "SPOT"
    }
  }

  # Karpenter
  enable_karpenter = true

  # Add-ons
  cluster_addons = {
    coredns    = { most_recent = true }
    kube-proxy = { most_recent = true }
    vpc-cni    = { most_recent = true }
    aws-ebs-csi-driver = { most_recent = true }
  }

  tags = {
    Environment = "production"
    Team        = "platform"
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `cluster_name` | EKS cluster name | `string` | — | yes |
| `cluster_version` | Kubernetes version | `string` | `"1.30"` | no |
| `vpc_id` | VPC ID | `string` | — | yes |
| `subnet_ids` | Private subnet IDs | `list(string)` | — | yes |
| `cluster_endpoint_public_access` | Enable public API endpoint | `bool` | `false` | no |
| `create_kms_key` | Create KMS key for secrets encryption | `bool` | `true` | no |
| `enable_karpenter` | Deploy Karpenter | `bool` | `true` | no |
| `node_groups` | Managed node group configurations | `map(any)` | `{}` | no |
| `cluster_addons` | EKS managed add-ons | `map(any)` | see defaults | no |
| `tags` | Tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| `cluster_name` | EKS cluster name |
| `cluster_endpoint` | Kubernetes API endpoint |
| `cluster_certificate_authority_data` | CA certificate (base64) |
| `cluster_oidc_issuer_url` | OIDC provider URL (for IRSA) |
| `karpenter_irsa_role_arn` | Karpenter IRSA role ARN |
| `node_security_group_id` | Node security group ID |

## CIS Controls Covered

| CIS Control | Description | Implemented |
|-------------|-------------|-------------|
| 5.1.1 | RBAC enabled | ✅ Always on |
| 5.3.1 | Secrets encrypted at rest | ✅ KMS |
| 5.4.1 | API server not public | ✅ Configurable (default: private) |
| 5.4.2 | API server audit logging | ✅ CloudWatch Logs |
| 5.5.1 | Latest Kubernetes version | ✅ Version pinning |

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.5 |
| aws | >= 5.0 |
| kubernetes | >= 2.20 |
| helm | >= 2.12 |

## License

MIT — by [Goutham Annem](https://linkedin.com/in/goutham-annem)
