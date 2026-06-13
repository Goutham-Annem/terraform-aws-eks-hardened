##############################################################################
# terraform-aws-eks-hardened
# Production-grade EKS with private endpoint, KMS encryption, IRSA, Karpenter
##############################################################################

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.20"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.12"
    }
  }
}

##############################################################################
# KMS Key for envelope encryption of Kubernetes secrets
##############################################################################
resource "aws_kms_key" "eks" {
  count                   = var.create_kms_key ? 1 : 0
  description             = "KMS key for EKS cluster ${var.cluster_name} secrets encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = merge(var.tags, { Name = "${var.cluster_name}-eks-secrets" })
}

resource "aws_kms_alias" "eks" {
  count         = var.create_kms_key ? 1 : 0
  name          = "alias/${var.cluster_name}-eks-secrets"
  target_key_id = aws_kms_key.eks[0].key_id
}

##############################################################################
# IAM role for the EKS cluster
##############################################################################
data "aws_iam_policy_document" "eks_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${var.cluster_name}-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.eks_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

##############################################################################
# CloudWatch log group for control plane audit logs (CIS 5.4.2)
##############################################################################
resource "aws_cloudwatch_log_group" "eks" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.create_kms_key ? aws_kms_key.eks[0].arn : var.kms_key_arn

  tags = var.tags
}

##############################################################################
# EKS Cluster
##############################################################################
resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  version  = var.cluster_version
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_private_access = var.cluster_endpoint_private_access
    endpoint_public_access  = var.cluster_endpoint_public_access
    public_access_cidrs     = var.cluster_endpoint_public_access ? var.public_access_cidrs : []
    security_group_ids      = [aws_security_group.cluster.id]
  }

  # Envelope encryption for secrets (CIS 5.3.1)
  dynamic "encryption_config" {
    for_each = var.create_kms_key || var.kms_key_arn != "" ? [1] : []
    content {
      resources = ["secrets"]
      provider {
        key_arn = var.create_kms_key ? aws_kms_key.eks[0].arn : var.kms_key_arn
      }
    }
  }

  # Control plane audit logging (CIS 5.4.2)
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy,
    aws_cloudwatch_log_group.eks,
  ]

  tags = var.tags
}

##############################################################################
# OIDC Provider for IRSA
##############################################################################
data "tls_certificate" "eks" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer

  tags = var.tags
}

##############################################################################
# Managed Node Groups
##############################################################################
module "node_groups" {
  source   = "./modules/node-groups"
  for_each = var.node_groups

  cluster_name    = aws_eks_cluster.this.name
  node_group_name = each.key
  config          = each.value
  subnet_ids      = var.subnet_ids
  tags            = var.tags

  depends_on = [aws_eks_cluster.this]
}

##############################################################################
# EKS Managed Add-ons
##############################################################################
resource "aws_eks_addon" "this" {
  for_each = var.cluster_addons

  cluster_name             = aws_eks_cluster.this.name
  addon_name               = each.key
  addon_version            = lookup(each.value, "addon_version", null)
  resolve_conflicts_on_update = "OVERWRITE"

  # Use latest if no specific version specified
  dynamic "configuration_values" {
    for_each = lookup(each.value, "configuration_values", null) != null ? [1] : []
    content {
      # pass through stringified JSON config
    }
  }

  tags = var.tags

  depends_on = [module.node_groups]
}

##############################################################################
# Karpenter (optional)
##############################################################################
module "karpenter" {
  count  = var.enable_karpenter ? 1 : 0
  source = "./modules/karpenter"

  cluster_name            = aws_eks_cluster.this.name
  cluster_endpoint        = aws_eks_cluster.this.endpoint
  oidc_provider_arn       = aws_iam_openid_connect_provider.eks.arn
  node_iam_role_name      = module.node_groups["system"].node_iam_role_name

  tags = var.tags
}

##############################################################################
# Cluster Security Group
##############################################################################
resource "aws_security_group" "cluster" {
  name        = "${var.cluster_name}-cluster-sg"
  description = "EKS cluster control plane security group"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = merge(var.tags, { Name = "${var.cluster_name}-cluster-sg" })
}
