################################################################################
# Kubernetes Manifests: EBS GP3 StorageClass
################################################################################

resource "kubectl_manifest" "EBSStorageClass" {
  depends_on = [module.eks]

  yaml_body = <<-EOT
  apiVersion: storage.k8s.io/v1
  kind: StorageClass
  metadata:
    name: gp3
  provisioner: ebs.csi.aws.com
  parameters:
    fsType: xfs
    type: gp3
  reclaimPolicy: Delete
  volumeBindingMode: WaitForFirstConsumer
  allowVolumeExpansion: true
  EOT
}

################################################################################
# Kubernetes Manifests: Karpenter Defaults EC2NodeClass and NodePool
################################################################################

resource "kubectl_manifest" "KarpenterEC2NodeClass" {
  depends_on = [module.karpenter]

  yaml_body = <<-EOT
  apiVersion: karpenter.k8s.aws/v1
  kind: EC2NodeClass
  metadata:
    name: default
  spec:
    amiFamily: AL2023
    role: ${module.karpenter.node_iam_role_name}
    subnetSelectorTerms:
      - tags:
          karpenter.sh/discovery: "${var.environment_name}"
    securityGroupSelectorTerms:
      - tags:
          karpenter.sh/discovery: "${var.environment_name}"
    amiSelectorTerms:
      - name: "amazon-eks-node-al2023-*-${var.k8s_version}-*"
  EOT
}

resource "kubectl_manifest" "KarpenterNodePool" {
  depends_on = [module.karpenter]

  yaml_body = <<-EOT
  apiVersion: karpenter.sh/v1
  kind: NodePool
  metadata:
    name: default
  spec:
    template:
      spec:
        requirements:
          - key: kubernetes.io/arch
            operator: In
            values: ["amd64", "arm64"]
          - key: kubernetes.io/os
            operator: In
            values: ["linux"]
          - key: karpenter.sh/capacity-type
            operator: In
            values: ["on-demand", "spot"]
          - key: karpenter.k8s.aws/instance-category
            operator: In
            values: ["c", "m", "r"]
        nodeClassRef:
          group: karpenter.k8s.aws
          kind: EC2NodeClass
          name: default
        expireAfter: 720h # 30 * 24h = 720h
    limits:
      cpu: 16
      memory: 256Gi
    disruption:
      consolidationPolicy: WhenEmptyOrUnderutilized
      consolidateAfter: 1m
      budgets:
      - nodes: "10%"
  EOT
}
