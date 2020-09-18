# IAM ROLES

resource "aws_iam_role" "eks_cluster" {
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
  name               = "${var.identifier}-eks-cluster"
  tags = {
    Infrastructure = var.identifier
  }
}

resource "aws_iam_role" "node_instance" {
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
  name               = "${var.identifier}-node-instance"
  tags = {
    Infrastructure = var.identifier
  }
}

resource "aws_iam_role_policy_attachment" "eks_cluster" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.id
}

resource "aws_iam_role_policy_attachment" "node_instance_cni" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node_instance.id
}

resource "aws_iam_role_policy_attachment" "node_instance_registry" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.node_instance.id
}

resource "aws_iam_role_policy_attachment" "node_instance_worker" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node_instance.id
}

# SECURITY GROUPS

resource "aws_security_group" "this" {
  name   = "${var.identifier}-control-plane"
  vpc_id = var.vpc_id
  tags = {
    Infrastructure = var.identifier
    Name           = "${var.identifier}-control-plane"
  }
}

resource "aws_security_group_rule" "this" {
  cidr_blocks       = ["0.0.0.0/0"]
  from_port         = 0
  protocol          = "-1"
  security_group_id = aws_security_group.this.id
  to_port           = 0
  type              = "egress"
}

# CLUSTER

resource "aws_eks_cluster" "this" {
  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster
  ]
  name       = var.identifier
  role_arn   = aws_iam_role.eks_cluster.arn
  tags = {
    Infrastructure = var.identifier
  }
  vpc_config {
    security_group_ids = [
      aws_security_group.this.id
    ]
    subnet_ids         = var.subnet_ids
  }
}

resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  depends_on      = [
    aws_iam_role_policy_attachment.node_instance_cni,
    aws_iam_role_policy_attachment.node_instance_registry,
    aws_iam_role_policy_attachment.node_instance_worker
  ]
  node_group_name = var.identifier
  node_role_arn   = aws_iam_role.node_instance.arn
  scaling_config {
    desired_size = 2
    max_size     = 2
    min_size     = 2
  }
  subnet_ids      = var.private_subnet_ids
  tags = {
    Infrastructure = var.identifier
  }
}

# IAM ROLES FOR SERVICE ACCOUNTS

data "tls_certificate" "this" {
  url = "${aws_eks_cluster.this.identity.0.oidc.0.issuer}"
}

resource "aws_iam_openid_connect_provider" "this" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["${data.tls_certificate.this.certificates.0.sha1_fingerprint}"]
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
}