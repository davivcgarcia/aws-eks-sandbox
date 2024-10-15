################################################################################
# Dynamic Data
################################################################################

data "aws_availability_zones" "available" {}



################################################################################
# Networking: VPC + Subnets + NATGW + RT
################################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.13.0"

  name = var.environment_name
  cidr = var.aws_vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(var.aws_vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(var.aws_vpc_cidr, 8, k + 48)]
  intra_subnets   = [for k, v in local.azs : cidrsubnet(var.aws_vpc_cidr, 8, k + 52)]

  enable_nat_gateway = true
  single_nat_gateway = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  # Tags subnets for Karpenter and LB Controller auto-discovery
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
    "karpenter.sh/discovery"          = var.environment_name
  }

  tags = var.aws_tags
}

################################################################################
# EKS: Cluster + Managed Add-ons + Infra Managed Nodegroup 
################################################################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.24.1"

  cluster_name    = var.environment_name
  cluster_version = var.k8s_version

  enable_cluster_creator_admin_permissions = true
  cluster_endpoint_public_access           = true

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.intra_subnets

  cluster_addons = {
    coredns = {
      addon_version = "v1.11.3-eksbuild.1"
      resolve_conflicts = "OVERWRITE"
    }
    kube-proxy = {
      addon_version = "v1.31.0-eksbuild.5"
      resolve_conflicts = "OVERWRITE"
    }
    vpc-cni = {
      addon_version = "v1.18.5-eksbuild.1"
      resolve_conflicts = "OVERWRITE"
    }
    aws-ebs-csi-driver = {
      addon_version = "v1.35.0-eksbuild.1"
      resolve_conflicts = "OVERWRITE"
    }
    snapshot-controller = {
      addon_version = "v8.1.0-eksbuild.1"
      resolve_conflicts = "OVERWRITE"
    }
    eks-pod-identity-agent = {
      addon_version = "v1.3.2-eksbuild.2"
      resolve_conflicts = "OVERWRITE"
    }
  }

  eks_managed_node_groups = {
    infra = {
      ami_type                       = "AL2023_x86_64_STANDARD"
      use_latest_ami_release_version = true

      instance_types = ["m5.large"]
      min_size       = 2
      max_size       = 3
      desired_size   = 2

      taints = {
        addons = {
          key    = "CriticalAddonsOnly"
          value  = "true"
          effect = "NO_SCHEDULE"
        },
      }

    }
  }

  node_security_group_tags = merge(var.aws_tags, {
    "karpenter.sh/discovery" = var.environment_name
  })

  tags = var.aws_tags
}

################################################################################
# EKS: Self-Managed Add-ons (using IRSA)
################################################################################

module "eks_blueprints_addons" {
  depends_on = [module.eks.eks_managed_node_groups]

  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.16.1"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  enable_aws_load_balancer_controller = true
  aws_load_balancer_controller = {
    values = [<<-EOT
      tolerations:
        - key: "CriticalAddonsOnly"
          operator: "Exists"
          effect: "NoSchedule"
      EOT
    ]
  }

  enable_metrics_server = true
  metrics_server = {
    values = [<<-EOT
      tolerations:
        - key: "CriticalAddonsOnly"
          operator: "Exists"
          effect: "NoSchedule"
      EOT
    ]
  }

  tags = var.aws_tags
}

################################################################################
# EKS: CloudWatch Container Insights (using IRSA)
################################################################################

module "eks_container_insights" {
  depends_on = [module.eks.eks_managed_node_groups]

  source = "github.com/aws-observability/terraform-aws-observability-accelerator//modules/eks-container-insights?ref=v2.12.2"

  eks_cluster_id                             = module.eks.cluster_name
  eks_oidc_provider_arn                      = module.eks.oidc_provider_arn
  enable_amazon_eks_cw_observability         = true
  create_cloudwatch_observability_irsa_role  = true
  create_cloudwatch_application_signals_role = true

  addon_config = {
    addon_version = "v2.1.2-eksbuild.1"
    resolve_conflicts = "OVERWRITE"
    configuration_values = jsonencode({
      tolerations = [
        {
          key      = "CriticalAddonsOnly"
          operator = "Exists"
          effect   = "NoSchedule"
        }
      ]
    })
  }

}

################################################################################
# EKS: Karpenter (using EKS Pod Identities)
################################################################################

module "karpenter" {
  depends_on = [module.eks.eks_managed_node_groups]

  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 20.11"

  cluster_name                    = module.eks.cluster_name
  node_iam_role_use_name_prefix   = false
  node_iam_role_name              = "KarpenterNodeRole-${var.environment_name}"
  create_pod_identity_association = true

  tags = var.aws_tags
}

resource "helm_release" "karpenter" {
  depends_on = [module.karpenter]

  namespace  = "kube-system"
  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = "1.0.5"
  wait       = true

  values = [
    <<-EOT
    tolerations:
      - key: CriticalAddonsOnly
        operator: Exists
    settings:
      clusterName: ${module.eks.cluster_name}
      clusterEndpoint: ${module.eks.cluster_endpoint}
      interruptionQueue: ${module.karpenter.queue_name}
    featureGates:
      spotToSpotConsolidation: true
    EOT
  ]

  lifecycle {
    ignore_changes = [
      repository_password
    ]
  }
}
