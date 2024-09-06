data "aws_vpc" "cpd_vpc" {
  id = var.vpc_id
}

resource "aws_efs_file_system" "cpd_efs" {
  creation_token   = "${var.cluster_name}_cpd_efs"
  performance_mode = "generalPurpose"
  throughput_mode  = "elastic"
  encrypted        = "true"
  #lifecycle_policy {
  #   transition_to_ia = "AFTER_30_DAYS"
  #}
  tags = {
    Name = var.cluster_name
  }
}

data "aws_security_group" "aws_worker_sg" {
  tags = {
    Name = "${var.cluster_name}-*-worker-sg"
  }
}

resource "aws_efs_mount_target" "cpd-efs-mt" {
  count           = var.az == "multi_zone" ? 3 : 1
  file_system_id  = aws_efs_file_system.cpd_efs.id
  subnet_id       = var.subnet_ids[count.index]
  security_groups = [data.aws_security_group.aws_worker_sg.id]

  depends_on = [
    aws_efs_file_system.cpd_efs,
  ]
}

resource "aws_security_group_rule" "efs_sg-rule" {
  type        = "ingress"
  from_port   = 2049
  to_port     = 2049
  protocol    = "tcp"
  cidr_blocks = [data.aws_vpc.cpd_vpc.cidr_block]
  # ipv6_cidr_blocks  = [aws_vpc.example.ipv6_cidr_block]
  security_group_id = data.aws_security_group.aws_worker_sg.id
}


resource "null_resource" "efs_ocp_login" {
  triggers = {
    login_cmd          = var.login_cmd
    openshift_username = regex("username (.*) --password", "${var.login_cmd}")[0]
    openshift_api      = regex("login (.*) --username", "${var.login_cmd}")[0]
    openshift_password = sensitive(regex("--password (.*)", "${var.login_cmd}")[0])
  }
  provisioner "local-exec" {
    command = <<EOF
    bash efs/oc_login.sh  "${self.triggers.openshift_api}" "${self.triggers.openshift_username}" "${self.triggers.openshift_password}"
    EOF
  }
  depends_on = [
    resource.aws_efs_mount_target.cpd-efs-mt,
  ]
}

resource "null_resource" "nfs_subdir_provisioner_setup" {
  triggers = {
    login_cmd          = var.login_cmd
    openshift_username = regex("username (.*) --password", "${var.login_cmd}")[0]
    openshift_api      = regex("login (.*) --username", "${var.login_cmd}")[0]
    openshift_password = regex("--password (.*)", "${var.login_cmd}")[0]
    cluster_type       = "managed"
    file_system_id     = aws_efs_file_system.cpd_efs.id
  }
  provisioner "local-exec" {
    command = <<EOF
    bash efs/setup-nfs.sh ${self.triggers.openshift_api}  '${self.triggers.file_system_id}' '${var.vpc_id}' '${data.aws_vpc.cpd_vpc.cidr_block}' '${var.region}' '${data.aws_security_group.aws_worker_sg.id}'
EOF
  }
  depends_on = [
    resource.aws_efs_mount_target.cpd-efs-mt,
    null_resource.efs_ocp_login,
  ]
}

locals {
  installer_workspace = var.installer_workspace
}
