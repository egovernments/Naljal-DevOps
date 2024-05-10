#
# Outputs
#

locals {

  kubeconfig = <<KUBECONFIG


apiVersion: v1
clusters:
- cluster:
    server: ${aws_eks_cluster.cluster.endpoint}
    certificate-authority-data: ${aws_eks_cluster.cluster.certificate_authority.0.data}
  name: kubernetes
contexts:
- context:
    cluster: kubernetes
    user: aws
  name: aws
current-context: aws
kind: Config
preferences: {}
users:
- name: aws
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1beta1
      command: aws-iam-authenticator
      args:
        - "token"
        - "-i"
        - "${var.cluster_name}"
KUBECONFIG
}

output "kubeconfig" {
  value = "${local.kubeconfig}"
}

output "eks_cluster" {
  value = "${aws_eks_cluster.cluster}"
}

output "cluster_security_group_id" {
    value   = "${aws_eks_cluster.cluster.vpc_config[0].worker_security_group_id}"
}

output "vpc_id" {
  value = var.vpc_id
}