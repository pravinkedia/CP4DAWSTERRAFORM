locals {
  classic_lb_timeout = 600
  
  installer_workspace = "${path.root}/installer-files"
  rosa_installer_url  = "https://github.com/openshift/rosa/releases/download/v1.2.22"
  subnet_ids          = join(",", var.subnet_ids)
  private_link        = var.private_cluster ? "--private-link" : ""
  worker_number = var.multi_zone && var.worker_machine_count %3 != 0 ? var.worker_machine_count - var.worker_machine_count %3 : var.worker_machine_count
  additional_node_count =  var.worker_machine_count - local.worker_number
  major_version = split(".",var.openshift_version)[0]
  minor_version = split(".",var.openshift_version)[1]
  rosa_major_minor_version = "${local.major_version}.${local.minor_version}"

}

resource "null_resource" "download_binaries" {
  triggers = {
    installer_workspace = var.installer_workspace
  }
  provisioner "local-exec" {
    when    = create
    command = <<EOF
test -e ${self.triggers.installer_workspace} || mkdir ${self.triggers.installer_workspace}
case $(uname -s) in
  Darwin)
    wget -r -l1 -np -nd -q ${local.rosa_installer_url}/rosa-darwin-amd64 -P ${self.triggers.installer_workspace} -A 'rosa-darwin-amd64'
    chmod u+x ${self.triggers.installer_workspace}/rosa-darwin-amd64
    mv ${self.triggers.installer_workspace}/rosa-darwin-amd64 ${self.triggers.installer_workspace}/rosa
    ;;
  Linux)
    wget -r -l1 -np -nd -q ${local.rosa_installer_url}/rosa-linux-amd64 -P ${self.triggers.installer_workspace} -A 'rosa-linux-amd64'
    chmod u+x ${self.triggers.installer_workspace}/rosa-linux-amd64
    mv ${self.triggers.installer_workspace}/rosa-linux-amd64 ${self.triggers.installer_workspace}/rosa
    ;;
  *)
    echo 'Supports only Linux and Mac OS at this time'
    exit 1;;
esac
EOF
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<EOF
#rm -rf ${self.triggers.installer_workspace}
EOF
  }
}

resource "null_resource" "create_AWSServiceRoleForElasticLoadBalancing" {

  provisioner "local-exec" {
    when    = create
    command = <<EOF
aws iam get-role --role-name "AWSServiceRoleForElasticLoadBalancing" || aws iam create-service-linked-role --aws-service-name "elasticloadbalancing.amazonaws.com"
sleep 10
EOF
  }
  depends_on = [
    null_resource.download_binaries
  ]
}
resource "null_resource" "login_rosa" {
  triggers = {
    installer_workspace = var.installer_workspace
    cluster_name        = var.cluster_name
  }
  provisioner "local-exec" {
    when    = create
    command = <<EOF
    ${self.triggers.installer_workspace}/rosa login --token='${var.rosa_token}'
    EOF
  }
  depends_on = [
    null_resource.download_binaries,
    null_resource.create_AWSServiceRoleForElasticLoadBalancing,
  ]
}


resource "null_resource" "install_rosa" {
  triggers = {
    installer_workspace = var.installer_workspace
    cluster_name        = var.cluster_name
    rosa_token          = var.rosa_token
  }
  provisioner "local-exec" {
    when    = create
    command = <<EOF
${self.triggers.installer_workspace}/rosa verify quota &&
${self.triggers.installer_workspace}/rosa create account-roles --mode auto --yes --version  ${local.rosa_major_minor_version} &&
${self.triggers.installer_workspace}/rosa create cluster ${local.private_link} --cluster-name='${self.triggers.cluster_name}' --compute-machine-type='${var.worker_machine_type}' --replicas ${local.worker_number} --region ${var.region} \
    --machine-cidr='${var.machine_network_cidr}' --service-cidr='${var.service_network_cidr}' --pod-cidr='${var.cluster_network_cidr}' --host-prefix='${var.cluster_network_host_prefix}' --private=${var.private_cluster} \
    --multi-az=${var.multi_zone} --version='${var.openshift_version}' --subnet-ids='${local.subnet_ids}'  --fips='${var.enable_fips}' --watch --yes --sts --mode auto &&
${self.triggers.installer_workspace}/rosa logs install --cluster=${self.triggers.cluster_name} --watch &&
${self.triggers.installer_workspace}/rosa describe cluster --cluster='${self.triggers.cluster_name}' &&
#Check for rosa api server is created
bash ocp/scripts/check-rosa-apiserver.sh "${self.triggers.installer_workspace}" "${self.triggers.cluster_name}"
EOF
  }
  provisioner "local-exec" {
    when    = destroy
    command = <<EOF
${self.triggers.installer_workspace}/rosa login --token='${self.triggers.rosa_token}' &&
CLUSTER_ID=$(${self.triggers.installer_workspace}/rosa describe cluster --cluster='${self.triggers.cluster_name}' -o json | jq --raw-output .id)
${self.triggers.installer_workspace}/rosa delete cluster --cluster='${self.triggers.cluster_name}' --yes &&
${self.triggers.installer_workspace}/rosa logs uninstall -c '${self.triggers.cluster_name}' --watch &&
${self.triggers.installer_workspace}/rosa delete operator-roles -c=$CLUSTER_ID --mode auto --yes &&
${self.triggers.installer_workspace}/rosa delete oidc-provider -c=$CLUSTER_ID --mode auto --yes
sleep 10
EOF
  }
  depends_on = [
    null_resource.download_binaries,
    null_resource.login_rosa,
  ]
}

resource "null_resource" "create_rosa_user" {
  triggers = {
    installer_workspace = var.installer_workspace
  }
  provisioner "local-exec" {
    when    = create
    command = <<EOF
${self.triggers.installer_workspace}/rosa create admin --cluster='${var.cluster_name}' > ${self.triggers.installer_workspace}/.creds
echo "Sleeping for 5mins"
sleep 300
EOF
  }
  depends_on = [
    null_resource.install_rosa,
  ]
}

data "local_file" "creds" {
  filename = "${var.installer_workspace}/.creds"
  depends_on = [
    null_resource.create_rosa_user
  ]
}
locals {
  login_cmd     = regex("oc\\s.*", data.local_file.creds.content)
  openshift_username      = regex("username (.*) --password", "${local.login_cmd}")[0]
  openshift_api        =  regex("login (.*) --username","${local.login_cmd}")[0]
  openshift_password      = sensitive(regex("--password (.*)","${local.login_cmd}")[0])
}

resource "null_resource" "login_rosa_cluster" {
  provisioner "local-exec" {
    command =<<EOF
bash ocp/scripts/oc_login.sh  "${local.openshift_api}" "${local.openshift_username}" "${local.openshift_password}"
EOF
}
  depends_on = [
    null_resource.create_rosa_user
  ]
}

resource "null_resource" "create_machinepool_multiaz_cluster" {
  count                = local.additional_node_count > 0 ? 1 : 0
   triggers = {
    installer_workspace = var.installer_workspace
    cluster_name        = var.cluster_name
  }
provisioner "local-exec" {
    command =<<EOF
  bash ocp/scripts/create-machinesets.sh "${self.triggers.installer_workspace}" "${self.triggers.cluster_name}" "${var.region}" "${var.worker_machine_type}" ${local.additional_node_count}
EOF
}
  depends_on = [
    null_resource.login_rosa_cluster
  ]
}

resource "null_resource" "configure_image_registry" {
  provisioner "local-exec" {
    command =<<EOF
bash ocp/scripts/nodes_running.sh
oc patch configs.imageregistry.operator.openshift.io/cluster --type merge -p '{"spec":{"defaultRoute":true,"replicas":3}}' -n openshift-image-registry
oc patch svc/image-registry -p '{"spec":{"sessionAffinity": "ClientIP"}}' -n openshift-image-registry
echo 'Sleeping for 3m'
sleep 180
oc annotate route default-route haproxy.router.openshift.io/timeout=600s -n openshift-image-registry
oc set env deployment/image-registry -n openshift-image-registry REGISTRY_STORAGE_S3_CHUNKSIZE=1048576000

sleep 2m
bash ocp/scripts/update-elb-timeout.sh ${var.vpc_id} ${local.classic_lb_timeout}
EOF
  }
  depends_on = [
   // null_resource.create_rosa_user
   null_resource.login_rosa_cluster,
   null_resource.create_machinepool_multiaz_cluster,
  ]
}

resource "null_resource" "configure_cluster_rosa" {
  provisioner "local-exec" {
    command =<<EOF
bash ocp/scripts/nodes_running.sh
EOF
  }
  depends_on = [
    null_resource.configure_image_registry
  ]
}

