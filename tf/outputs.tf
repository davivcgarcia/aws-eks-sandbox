################################################################################
# Relevant Outputs
################################################################################

output "EKSClusterName" {
  value = module.eks.cluster_name
}

output "EKSClusterRegion" {
  value = var.aws_region
}

output "KarpenterNodeRoleName" {
  value = module.karpenter.node_iam_role_name
}