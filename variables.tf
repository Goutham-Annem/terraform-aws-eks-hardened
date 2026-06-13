variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.30"
}

variable "vpc_id" {
  description = "VPC ID where the cluster will be deployed"
  type        = string
}

variable "subnet_ids" {
  description = "Private subnet IDs for the cluster and node groups"
  type        = list(string)
}

variable "cluster_endpoint_public_access" {
  description = "Enable public access to the Kubernetes API server. Set to false for CIS compliance."
  type        = bool
  default     = false
}

variable "cluster_endpoint_private_access" {
  description = "Enable private access to the Kubernetes API server"
  type        = bool
  default     = true
}

variable "public_access_cidrs" {
  description = "CIDR blocks allowed to access the public API endpoint"
  type        = list(string)
  default     = []
}

variable "create_kms_key" {
  description = "Create a KMS key for envelope encryption of Kubernetes secrets"
  type        = bool
  default     = true
}

variable "kms_key_arn" {
  description = "ARN of an existing KMS key. Used only if create_kms_key is false."
  type        = string
  default     = ""
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days for control plane logs"
  type        = number
  default     = 90
}

variable "node_groups" {
  description = "Map of managed node group configurations"
  type        = map(any)
  default     = {}
}

variable "cluster_addons" {
  description = "Map of EKS managed add-ons to install"
  type        = map(any)
  default = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
  }
}

variable "enable_karpenter" {
  description = "Deploy Karpenter for event-driven node provisioning"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
