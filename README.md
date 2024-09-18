# Amazon EKS Sandbox

## About

This repository contains infrastructure code used to bootstrap an Amazon EKS environment with the most common components and integrations enabled using Terraform.

## Dependencies

- [aws-cli](https://aws.amazon.com/cli/)
- [terraform aws/vpc](https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws/latest)
- [terraform aws/eks](https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/latest)
- [terraform eks-blueprints-addons](https://aws-ia.github.io/terraform-aws-eks-blueprints-addons/main/amazon-eks-addons/)
- [terraform aws-observability-accelerator](https://aws-observability.github.io/terraform-aws-observability-accelerator/)

## Usage

1. Clone this repository:

```bash
git clone https://github.com/davivcgarcia/aws-eks-sandbox.git
cd aws-eks-sandbox/
```

2. Provision infrastructure with Terraform:

```bash
cd tf/
terraform init
terraform apply
```

3. Update Kubeconfig using the new cluster parameters:

```bash
EKS_CLUSTER_NAME=$(terraform output -raw EKSClusterName)
EKS_CLUSTER_REGION=$(terraform output -raw EKSClusterRegion)
aws eks update-kubeconfig --name $EKS_CLUSTER_NAME --region $EKS_CLUSTER_REGION
```

## Cleanup

1. Delete all Karpenter resources to remove EC2 Fleet instances:

```bash
kubectl delete NodePools,EC2NodeClass
```

2. Delete all network resources to LB Controller to remove ELBs:

```bash
kubectl get services --all-namespaces -o json | jq -r '.items[] | select(.spec.type == "LoadBalancer") | .metadata.name + " " + .metadata.namespace' | while read name namespace; do kubectl delete service $name -n $namespace; done
kubectl get ingress --all-namespaces -o json | jq -r '.items[] | select(.spec.ingressClassName == "alb") | .metadata.namespace + " " + .metadata.name' | while read name namespace; do kubectl delete ingress $name -n $namespace; done
```

3. Delete all storage resources to LB Controller to remove EBS/EFS:

```bash
kubectl delete pvc --all-namespaces --all
kubectl delete pv --all
```

4. Destroy AWS resources created by Terraform:

```bash
terraform destroy
```