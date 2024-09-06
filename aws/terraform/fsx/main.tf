terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.67.0"
    }
  }
}

locals {
  route_table_list  = (var.az == "multi_zone" ? [data.aws_route_table.worker_subnet1_rt.id, data.aws_route_table.worker_subnet2_rt[0].id, data.aws_route_table.worker_subnet3_rt[0].id] : [data.aws_route_table.worker_subnet1_rt.id])
  fsx_mngmt_ip      = var.az == "multi_zone" ? format("%s=%s", "FSX_MANAGEMENT_IP", join("", aws_fsx_ontap_file_system.cpdfs_multizone[0].endpoints[0].management[0].ip_addresses)) : format("%s=%s", "FSX_MANAGEMENT_IP", join("", aws_fsx_ontap_file_system.cpdfs_singlezone[0].endpoints[0].management[0].ip_addresses))
  fsx_mngmt_dnsname = var.az == "multi_zone" ? aws_fsx_ontap_file_system.cpdfs_multizone[0].endpoints[0].management[0].dns_name : aws_fsx_ontap_file_system.cpdfs_singlezone[0].endpoints[0].management[0].dns_name
  fsx_filesystem_id = var.az == "multi_zone" ? aws_fsx_ontap_file_system.cpdfs_multizone[0].id : aws_fsx_ontap_file_system.cpdfs_singlezone[0].id
}

data "aws_vpc" "cpd_vpc" {
  id = var.vpc_id
}

data "aws_route_table" "worker_subnet1_rt" {
  subnet_id = var.private_subnet_ids[0]
}

data "aws_route_table" "worker_subnet2_rt" {
  count     = var.az == "multi_zone" ? 1 : 0
  subnet_id = var.private_subnet_ids[1]
}

data "aws_route_table" "worker_subnet3_rt" {
  count     = var.az == "multi_zone" ? 1 : 0
  subnet_id = var.private_subnet_ids[2]
}

resource "aws_security_group" "fsx_sg" {
  name_prefix = "security group for fsx access"
  vpc_id      = var.vpc_id
  tags = {
    Name = "${var.cluster_name}_fsx_sg"
  }
}

resource "aws_security_group_rule" "fsx_sg_inbound" {
  description       = "allow inbound traffic within vpc"
  from_port         = 0
  protocol          = "-1"
  to_port           = 0
  security_group_id = aws_security_group.fsx_sg.id
  type              = "ingress"
  cidr_blocks       = [data.aws_vpc.cpd_vpc.cidr_block]
}

resource "aws_security_group_rule" "fsx_sg_outbound" {
  description       = "allow outbound traffic to anywhere"
  from_port         = 0
  protocol          = "-1"
  security_group_id = aws_security_group.fsx_sg.id
  to_port           = 0
  type              = "egress"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_fsx_ontap_file_system" "cpdfs_multizone" {
  count                           = var.az == "multi_zone" ? 1 : 0
  storage_capacity                = var.fsx_storage_capacity
  throughput_capacity             = var.fsx_throughput_capacity
  subnet_ids                      = [var.private_subnet_ids[0], var.private_subnet_ids[1]]
  deployment_type                 = "MULTI_AZ_1"
  endpoint_ip_address_range       = var.fsx_endpoint_cidr
  preferred_subnet_id             = var.private_subnet_ids[0]
  security_group_ids              = [aws_security_group.fsx_sg.id]
  fsx_admin_password              = var.fsx_admin_password
  route_table_ids                 = local.route_table_list
  automatic_backup_retention_days = 0
  tags = {
    Name = var.cluster_name
  }
}

resource "aws_fsx_ontap_file_system" "cpdfs_singlezone" {
  count                           = var.az == "multi_zone" ? 0 : 1
  storage_capacity                = var.fsx_storage_capacity
  throughput_capacity             = var.fsx_throughput_capacity
  subnet_ids                      = [var.private_subnet_ids[0]]
  preferred_subnet_id             = var.private_subnet_ids[0]
  deployment_type                 = "SINGLE_AZ_1"
  security_group_ids              = [aws_security_group.fsx_sg.id]
  fsx_admin_password              = var.fsx_admin_password
  automatic_backup_retention_days = 0
  tags = {
    Name = var.cluster_name
  }
}
resource "aws_fsx_ontap_storage_virtual_machine" "cpdsvm" {
  file_system_id     = var.az == "multi_zone" ? aws_fsx_ontap_file_system.cpdfs_multizone[0].id : aws_fsx_ontap_file_system.cpdfs_singlezone[0].id
  name               = var.cluster_name
  svm_admin_password = var.fsx_admin_password
  tags = {
    Name = var.cluster_name
  }
}

resource "null_resource" "destroy_fsx_volumes" {
  depends_on = [aws_fsx_ontap_storage_virtual_machine.cpdsvm]
  triggers = {
    region            = var.region
    fsx_filesystem_id = local.fsx_filesystem_id
    svm_name          = var.cluster_name
  }
  provisioner "local-exec" {
    when    = destroy
    command = <<EOF
    bash fsx/scripts/delete_volumes.sh  "${self.triggers.region}" "${self.triggers.fsx_filesystem_id}" "${self.triggers.svm_name}" 
    EOF
  }
}


resource "null_resource" "fsx_ocp_login" {
  triggers = {
    login_cmd          = var.login_cmd
    openshift_username = regex("username (.*) --password", "${var.login_cmd}")[0]
    openshift_api      = regex("login (.*) --username", "${var.login_cmd}")[0]
    openshift_password = sensitive(regex("--password (.*)", "${var.login_cmd}")[0])
  }
  provisioner "local-exec" {
    command = <<EOF
    bash fsx/scripts/oc_login.sh  "${self.triggers.openshift_api}" "${self.triggers.openshift_username}" "${self.triggers.openshift_password}"
    EOF
  }
  depends_on = [
    aws_fsx_ontap_storage_virtual_machine.cpdsvm,
  ]
}

resource "null_resource" "setup_trident_operator" {

  triggers = {
    login_cmd          = var.login_cmd
    openshift_username = regex("username (.*) --password", "${var.login_cmd}")[0]
    openshift_api      = regex("login (.*) --username", "${var.login_cmd}")[0]
    openshift_password = sensitive(regex("--password (.*)", "${var.login_cmd}")[0])
    cluster_name       = var.cluster_name
  }
  provisioner "local-exec" {
    command = <<EOF
    helm repo add netapp-trident https://netapp.github.io/trident-helm-chart --force-update && 
    {
        helm list -n trident -o json | grep trident-driver \
        || helm install trident-driver netapp-trident/trident-operator \
            --version "${var.trident_operator_version}" \
            --create-namespace \
            --namespace "${var.trident_namespace}"
    } \
    && echo "INFO: Waiting for Trident driver installation to start." \
    && sleep 20 \
    && oc wait TridentOrchestrator.trident.netapp.io trident --for=jsonpath='{.status.status}'="Installed" --timeout 300s
    EOF
  }
  depends_on = [
    null_resource.fsx_ocp_login,
  ]

}


resource "local_file" "fsx_ontap_secret_yaml" {
  content  = data.template_file.backend_fsx_ontap_secret.rendered
  filename = "${var.installer_workspace}/ontap_secret.yaml"
}

resource "local_file" "trident_backend_yaml" {
  content  = data.template_file.trident_backend_config.rendered
  filename = "${var.installer_workspace}/trident_backend.yaml"
}

resource "local_file" "ontap_nas_sc_yaml" {
  content  = data.template_file.ontap_nas_sc.rendered
  filename = "${var.installer_workspace}/ontap_nas_sc.yaml"
}


resource "null_resource" "configure_fsx_storage" {
  triggers = {
    installer_workspace = var.installer_workspace
  }
  provisioner "local-exec" {
    command = <<EOF
oc apply -f ${self.triggers.installer_workspace}/ontap_secret.yaml && 
oc apply -f ${self.triggers.installer_workspace}/trident_backend.yaml &&
sleep 30 &&
oc wait TridentBackendConfig.trident.netapp.io backend-fsx-ontap-nas \
        -n "${var.trident_namespace}" \
        --for=jsonpath='{.status.phase}'="Bound" &&
oc wait TridentBackendConfig.trident.netapp.io backend-fsx-ontap-nas \
        -n "${var.trident_namespace}" \
        --for=jsonpath='{.status.lastOperationStatus}'="Success"    && 
oc apply -f ${self.triggers.installer_workspace}/ontap_nas_sc.yaml
EOF
  }
  depends_on = [
    null_resource.setup_trident_operator,
    local_file.fsx_ontap_secret_yaml,
    local_file.trident_backend_yaml,
    local_file.ontap_nas_sc_yaml,
  ]
}