variable "cluster_name" {
}

variable "vpc_id" {
  description = "VPC-naljal"
  default = "vpc-053cd69a368474226"
}

variable "subnets" {
    type = list(string)
}

variable "kubernetes_version" {
}

variable "master_nodes_security_grp_ids" {
    type = list(string)
}