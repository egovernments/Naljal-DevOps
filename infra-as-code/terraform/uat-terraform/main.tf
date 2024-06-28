terraform {
  backend "s3" {
    bucket = "uat-s3"
    key    = "digit-bootcamp-setup/terraform.tfstate"
    region = "ap-south-1"
    # The below line is optional depending on whether you are using DynamoDB for state locking and consistency
    dynamodb_table = "uat-s3"
    # The below line is optional if your S3 bucket is encrypted
    encrypt = true
  }
}




data "aws_eks_cluster" "cluster" {
  name = "${module.eks.cluster_id}"
}

data "aws_eks_cluster_auth" "cluster" {
  name = "${module.eks.cluster_id}"
}

data "aws_caller_identity" "current" {}

data "tls_certificate" "thumb" {
  url = "${data.aws_eks_cluster.cluster.identity.0.oidc.0.issuer}"
}

provider "kubernetes" {
  host                   = "${data.aws_eks_cluster.cluster.endpoint}"
  cluster_ca_certificate = "${base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)}"
  token                  = "${data.aws_eks_cluster_auth.cluster.token}"
}

module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  version         = "17.24.0"
  cluster_name    = "${var.cluster_name}"
  vpc_id          = "${var.vpc_id}"
  cluster_version = "${var.kubernetes_version}"
  subnets         = "${concat(var.existing_private_subnet_ids, var.existing_public_subnet_ids)}"

##By default worker groups is Configured with SPOT, As per your requirement you can below values.

  worker_groups = [
    {
      name                          = "spot"
      ami_id                        = "ami-0a82b544ef71a207d"   
      subnets                       = "${concat(slice(var.existing_private_subnet_ids, 0, length(var.availability_zones)))}"
      instance_type                 = "${var.instance_type}"
      override_instance_types       = "${var.override_instance_types}"
      kubelet_extra_args            = "--node-labels=node.kubernetes.io/lifecycle=spot"
      asg_max_size                  = "${var.number_of_worker_nodes}"
      asg_desired_capacity          = "${var.number_of_worker_nodes}"
      spot_allocation_strategy      = "capacity-optimized"
      spot_instance_pools           = null
    }
  ]
  tags = "${
    tomap({
      "kubernetes.io/cluster/${var.cluster_name}" = "owned",
      "KubernetesCluster" = "${var.cluster_name}"
    })
  }"
}

resource "aws_iam_role" "eks_iam" {
  name = "${var.cluster_name}-eks"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid = "EKSWorkerAssumeRole"
        Effect = "Allow",
        Principal = {
          Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${replace(data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer, "https://", "")}"
        },
        Action = "sts:AssumeRoleWithWebIdentity",
        Condition = {
          StringEquals = {
            "${replace(data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:kube-system:ebs-csi-controller-sa"
          }
        }
      }
    ]
  })
}

resource "kubernetes_annotations" "example" {
  api_version = "v1"
  kind        = "ServiceAccount"
  metadata {
    name = "ebs-csi-controller-sa"
    namespace = "kube-system"
  }
  annotations = {
    "eks.amazonaws.com/role-arn" = "${aws_iam_role.eks_iam.arn}"
  }
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEBSCSIDriverPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  role       = "${aws_iam_role.eks_iam.name}"
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEC2FullAccess" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
  role       = "${aws_iam_role.eks_iam.name}"
}

resource "aws_iam_openid_connect_provider" "eks_oidc_provider" {
  client_id_list = ["sts.amazonaws.com"]
  thumbprint_list = ["${data.tls_certificate.thumb.certificates.0.sha1_fingerprint}"] # This should be empty or provide certificate thumbprints if needed
  url            = "${data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer}" # Replace with the OIDC URL from your EKS cluster details
}

resource "aws_security_group_rule" "rds_db_ingress_workers" {
  description              = "Allow worker nodes to communicate with RDS database" 
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = "${var.existing_rds_security_group_id}"
  source_security_group_id = "${module.eks.worker_security_group_id}"
  type                     = "ingress"
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name      = data.aws_eks_cluster.cluster.name
  addon_name        = "kube-proxy"
  addon_version     = "v1.29.0-eksbuild.1"
  resolve_conflicts = "OVERWRITE"
}
resource "aws_eks_addon" "core_dns" {
  cluster_name      = data.aws_eks_cluster.cluster.name
  addon_name        = "coredns"
  addon_version     = "v1.11.1-eksbuild.4"
  resolve_conflicts = "OVERWRITE"
}
resource "aws_eks_addon" "aws_ebs_csi_driver" {
  cluster_name      = data.aws_eks_cluster.cluster.name
  addon_name        = "aws-ebs-csi-driver"
  addon_version     = "v1.30.0-eksbuild.1"
  resolve_conflicts = "OVERWRITE"
}
resource "aws_eks_addon" "aws_vpc_cni" {
  cluster_name      = data.aws_eks_cluster.cluster.name
  addon_name        = "vpc-cni"
  addon_version     = "v1.12.6-eksbuild.2"
  resolve_conflicts = "OVERWRITE"
}
