terraform {
  required_providers {
    http = {
      source  = "hashicorp/http"
      version = "3.2.1"
    }
  }
}

data "http" "cpd_cli" {
  url = var.cpdcli_config_giturl
}
locals {
  classic_lb_timeout  = 600
  cpd_workspace       = "${var.installer_workspace}/cpd"
  operator_namespace  = "ibm-common-services"
  cpd_case_url        = "https://raw.githubusercontent.com/IBM/cloud-pak/master/repo/case"
  storage_class       = lookup(var.cpd_storageclass, var.storage_option)
  rwo_storage_class   = lookup(var.rwo_cpd_storageclass, var.storage_option)
  cpd_cli_config_json = data.http.cpd_cli.response_body
  cpd_cli_config      = jsondecode(local.cpd_cli_config_json)
  cpd_version         = local.cpd_cli_config.cpd-version
  release_version     = local.cpd_cli_config.cpd-cli-version
  release_build       = local.cpd_cli_config.cpd-cli-build
}

module "machineconfig" {
  source                       = "./machineconfig"
  cpd_api_key                  = var.cpd_api_key
  installer_workspace          = var.installer_workspace
  cluster_type                 = var.cluster_type
  openshift_api                = var.openshift_api
  openshift_username           = var.openshift_username
  openshift_password           = var.openshift_password
  openshift_token              = var.openshift_token
  login_string                 = var.login_string
  configure_global_pull_secret = var.configure_global_pull_secret
  configure_openshift_nodes    = var.configure_openshift_nodes
}

resource "null_resource" "download_cpd_cli" {
  triggers = {
    cpd_workspace = local.cpd_workspace
  }
  provisioner "local-exec" {
    command = <<-EOF
  echo "Download cpd-cli installer."
case $(uname -s) in
  Darwin)
    wget https://github.com/IBM/cpd-cli/releases/download/v${local.release_version}/cpd-cli-darwin-EE-${local.release_version}.tgz -P ${self.triggers.cpd_workspace} -A 'cpd-cli-darwin-EE-${local.release_version}.tgz'
    tar -xvf ${self.triggers.cpd_workspace}/cpd-cli-darwin-EE-${local.release_version}.tgz -C ${self.triggers.cpd_workspace}
    rm -rf ${self.triggers.cpd_workspace}/plugins
    rm -rf ${self.triggers.cpd_workspace}/LICENSES
    mv ${self.triggers.cpd_workspace}/cpd-cli-darwin-EE-${local.release_version}-${local.release_build}/*  ${self.triggers.cpd_workspace}
    ;;
  Linux)
    wget https://github.com/IBM/cpd-cli/releases/download/v${local.release_version}/cpd-cli-linux-EE-${local.release_version}.tgz -P ${self.triggers.cpd_workspace} -A 'cpd-cli-linux-EE-${local.release_version}.tgz'
    tar -xvf ${self.triggers.cpd_workspace}/cpd-cli-linux-EE-${local.release_version}.tgz -C ${self.triggers.cpd_workspace}
    rm -rf ${self.triggers.cpd_workspace}/plugins
    rm -rf ${self.triggers.cpd_workspace}/LICENSES
    mv ${self.triggers.cpd_workspace}/cpd-cli-linux-EE-${local.release_version}-${local.release_build}/* ${self.triggers.cpd_workspace}
    ;;
  *)
    echo 'Supports only Linux and Mac OS at this time'
    exit 1;;
esac
EOF
  }
  depends_on = [
    module.machineconfig,
  ]
}

resource "null_resource" "login_cluster" {
  triggers = {
    openshift_api      = var.openshift_api
    openshift_username = var.openshift_username
    openshift_password = sensitive(var.openshift_password)
    openshift_token    = var.openshift_token
    login_string       = var.login_string
    cpd_workspace      = local.cpd_workspace
    build_number       = "${timestamp()}"
  }
  provisioner "local-exec" {
    command = <<EOF
echo 'Remove any existing olm-utils-play container' 
podman rm --force olm-utils-play-v2
podman rmi $OLM_UTILS_IMAGE
echo 'Run login-to-ocp command'
${self.triggers.cpd_workspace}/cpd-cli manage login-to-ocp --server ${self.triggers.openshift_api} -u '${self.triggers.openshift_username}' -p '${self.triggers.openshift_password}' || ${self.triggers.cpd_workspace}/cpd-cli manage login-to-ocp --server ${self.triggers.openshift_api} --token='${self.triggers.openshift_token}'
${self.triggers.cpd_workspace}/cpd-cli manage login-to-ocp --server ${self.triggers.openshift_api} -u '${self.triggers.openshift_username}' -p '${self.triggers.openshift_password}' || ${self.triggers.cpd_workspace}/cpd-cli manage login-to-ocp --server ${self.triggers.openshift_api} --token='${self.triggers.openshift_token}'
oc login ${self.triggers.openshift_api} -u '${self.triggers.openshift_username}' -p '${self.triggers.openshift_password}' --insecure-skip-tls-verify=true || oc login --server='${self.triggers.openshift_api}' --token='${self.triggers.openshift_token}'
sleep 60
EOF
  }
  depends_on = [
    module.machineconfig,
    null_resource.download_cpd_cli,
  ]
}

resource "null_resource" "configure_global_pull_secret" {
  triggers = {
    cpd_workspace         = local.cpd_workspace
    cpd_external_registry = var.cpd_external_registry
    cpd_external_username = var.cpd_external_username
    cpd_api_key           = sensitive(var.cpd_api_key)
  }

  count = var.configure_global_pull_secret ? 1 : 0
  provisioner "local-exec" {
    command = <<EOF
echo "Configuring global pull secret"
${self.triggers.cpd_workspace}/cpd-cli manage add-cred-to-global-pull-secret  --registry='${self.triggers.cpd_external_registry}'  --registry_pull_user='${self.triggers.cpd_external_username}'  --registry_pull_password='${self.triggers.cpd_api_key}'

echo 'Sleeping for 5mins while global pull secret apply and the nodes restarts' 
sleep 300
EOF
  }
  depends_on = [
    module.machineconfig,
    null_resource.login_cluster,
    null_resource.download_cpd_cli,
  ]
}


resource "null_resource" "node_check" {
  triggers = {
    namespace     = var.cpd_instance_namespace
    cpd_workspace = local.cpd_workspace
  }
  #adding a negative check for managed-ibm as it doesn't support machine config 
  #so that this block runs for all other stack except ibmcloud
  count = var.cluster_type != "managed-ibm" ? 1 : 0
  provisioner "local-exec" {
    command = <<-EOF
echo "Ensure the nodes are running"
bash cpd/scripts/nodes_running.sh

EOF
  }
  depends_on = [
    module.machineconfig,
    null_resource.login_cluster,
    null_resource.download_cpd_cli,
    null_resource.configure_global_pull_secret,
  ]
}



