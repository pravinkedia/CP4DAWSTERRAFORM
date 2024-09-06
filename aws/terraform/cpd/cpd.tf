locals {
  cpd_services = join(",", compact([
    for var_name, var_value in {
      cpd_platform       = var.cpd_platform,
      dv                 = var.data_virtualization,
      analyticsengine    = var.analytics_engine,
      bigsql             = var.bigsql,
      dashboard          = var.cognos_dashboard_embedded,
      cognos_analytics   = var.cognos_analytics,
      datagate           = var.datagate,
      db2oltp            = var.db2_oltp,
      db2wh              = var.db2_warehouse,
      dmc                = var.data_management_console,
      dods               = var.decision_optimization,
      datastage_ent_plus = var.datastage,
      factsheet          = var.factsheets,
      match360           = var.master_data_management,
      openpages          = var.openpages,
      planning_analytics = var.planning_analytics,
      replication        = var.data_replication,
      rstudio            = var.rstudio,
      spss               = var.spss_modeler,
      watson_assistant   = var.watson_assistant,
      watson_speech      = var.watson_speech,
      watson_discovery   = var.watson_discovery,
      wkc                = var.watson_knowledge_catalog,
      wkc                = var.watson_knowledge_catalog_core,
      wml                = var.watson_machine_learning,
      openscale          = var.watson_ai_openscale,
      ws_pipelines       = var.ws_pipelines,
      ws                 = var.watson_studio
    } : var_name == "wkc" && (var_value == "yes"  || var.watson_knowledge_catalog == "yes") ? var_name : var_value == "yes" ? var_name : null
  ]))
}

resource "null_resource" "cpd_certmanager_licensing_services" {
  triggers = {
    cpd_workspace = local.cpd_workspace
    cpd_version   = local.cpd_version
  }
  provisioner "local-exec" {
    command = <<-EOF
echo "Apply Cluster components to install cert manager & Licensing service"  &&
${self.triggers.cpd_workspace}/cpd-cli manage apply-cluster-components --release=${local.cpd_version} --license_acceptance=true
EOF
  }
  depends_on = [
    module.machineconfig,
    null_resource.login_cluster,
    null_resource.download_cpd_cli,
    null_resource.node_check,
    null_resource.configure_global_pull_secret,
  ]
}

resource "null_resource" "authorize_instance_toplogy" {
  triggers = {
    operator_namespace = var.cpd_operator_namespace
    instance_namespace = var.cpd_instance_namespace
    cpd_workspace      = local.cpd_workspace
  }
  provisioner "local-exec" {
    command = <<-EOF
echo "Authorize Instance topology to authorize cpd instance namespaces to be manageable from operator namespace"  &&
${self.triggers.cpd_workspace}/cpd-cli manage authorize-instance-topology --cpd_operator_ns=${var.cpd_operator_namespace} --cpd_instance_ns=${var.cpd_instance_namespace}
EOF
  }
  depends_on = [
    module.machineconfig,
    null_resource.login_cluster,
    null_resource.download_cpd_cli,
    null_resource.node_check,
    null_resource.configure_global_pull_secret,
    null_resource.cpd_certmanager_licensing_services,
  ]
}

resource "null_resource" "setup_instance_toplogy" {
  triggers = {
    operator_namespace = var.cpd_operator_namespace
    instance_namespace = var.cpd_instance_namespace
    cpd_workspace      = local.cpd_workspace
    cpd_version        = local.cpd_version
  }
  provisioner "local-exec" {
    command = <<-EOF
echo "Setup Instance Topolgy to install cpfs and setup configmap for the Namespacescope operator"  &&
${self.triggers.cpd_workspace}/cpd-cli manage setup-instance-topology --release=${local.cpd_version} --cpd_operator_ns=${var.cpd_operator_namespace} --cpd_instance_ns=${var.cpd_instance_namespace}  --license_acceptance=true
EOF
  }
  depends_on = [
    module.machineconfig,
    null_resource.login_cluster,
    null_resource.download_cpd_cli,
    null_resource.node_check,
    null_resource.configure_global_pull_secret,
    null_resource.cpd_certmanager_licensing_services,
    null_resource.authorize_instance_toplogy,
  ]
}
data "template_file" "mcg_namespace" {
  count    = (var.watson_discovery == "yes" || var.watson_assistant == "yes" || var.watson_speech == "yes") ? 1 : 0
  template = <<EOF
apiVersion: v1
kind: Namespace
metadata:
  labels:
    openshift.io/cluster-monitoring: "true"
  name: openshift-storage
spec: {}
EOF
}


data "template_file" "mcg_operatorgroup" {
  count    = (var.watson_discovery == "yes" || var.watson_assistant == "yes" || var.watson_speech == "yes") ? 1 : 0
  template = <<EOF
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: openshift-storage-og
  namespace: openshift-storage
spec:
  targetNamespaces:
  - openshift-storage
EOF
}

data "template_file" "mcg_odf_operator" {
  count    = (var.watson_discovery == "yes" || var.watson_assistant == "yes" || var.watson_speech == "yes") ? 1 : 0
  template = <<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  labels:
    operators.coreos.com/odf-operator.openshift-storage: ""
  name: ocs-operator
  namespace: openshift-storage
spec:
  channel: stable-4.12
  installPlanApproval: Automatic
  name: odf-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF
}

data "template_file" "mcg_ocs_storagecluster" {
  count    = (var.watson_discovery == "yes" || var.watson_assistant == "yes" || var.watson_speech == "yes") ? 1 : 0
  template = <<EOF
apiVersion: ocs.openshift.io/v1
kind: StorageCluster
metadata:
  annotations:
    cluster.ocs.openshift.io/local-devices: 'true'
    uninstall.ocs.openshift.io/cleanup-policy: delete
    uninstall.ocs.openshift.io/mode: graceful
  name: ocs-storagecluster
  namespace: openshift-storage
  finalizers:
    - storagecluster.ocs.openshift.io
spec:
    arbiter: {}
    encryption:
      kms: {}
    externalStorage: {}
    managedResources:
      cephBlockPools: {}
      cephCluster: {}
      cephConfig: {}
      cephDashboard: {}
      cephFilesystems: {}
      cephNonResilientPools: {}
      cephObjectStoreUsers: {}
      cephObjectStores: {}
      cephToolbox: {}
    mirroring: {}
    multiCloudGateway:
      dbStorageClassName: ${local.storage_class}
      reconcileStrategy: standalone
EOF
}

resource "local_file" "mcg_namespace_yaml" {
  count    = (var.watson_discovery == "yes" || var.watson_assistant == "yes" || var.watson_speech == "yes") ? 1 : 0
  content  = data.template_file.mcg_namespace.*.rendered[0]
  filename = "${local.cpd_workspace}/mcg_namespace.yaml"
  provisioner "local-exec" {
    command = <<-EOF
echo "Setting up Openshift-storage namespace"  &&
oc apply -f ${local.cpd_workspace}/mcg_namespace.yaml
EOF
  }
  depends_on = [
    module.machineconfig,
    null_resource.login_cluster,
    null_resource.download_cpd_cli,
    null_resource.node_check,
    null_resource.configure_global_pull_secret,
    null_resource.cpd_certmanager_licensing_services,
    null_resource.authorize_instance_toplogy,
    null_resource.setup_instance_toplogy
  ]
}

resource "local_file" "mcg_operatorgroup_yaml" {
  count    = (var.watson_discovery == "yes" || var.watson_assistant == "yes" || var.watson_speech == "yes") ? 1 : 0
  content  = data.template_file.mcg_operatorgroup.*.rendered[0]
  filename = "${local.cpd_workspace}/mcg_operatorgroup.yaml"
  provisioner "local-exec" {
    command = <<-EOF
echo "Setup ODF Operator group"  &&
oc apply -f ${local.cpd_workspace}/mcg_operatorgroup.yaml
EOF
  }
  depends_on = [
    module.machineconfig,
    null_resource.login_cluster,
    null_resource.download_cpd_cli,
    null_resource.node_check,
    null_resource.configure_global_pull_secret,
    null_resource.cpd_certmanager_licensing_services,
    null_resource.authorize_instance_toplogy,
    null_resource.setup_instance_toplogy,
    local_file.mcg_namespace_yaml
  ]
}

resource "local_file" "mcg_odf_operator_yaml" {
  count    = (var.watson_discovery == "yes" || var.watson_assistant == "yes" || var.watson_speech == "yes") ? 1 : 0
  content  = data.template_file.mcg_odf_operator.*.rendered[0]
  filename = "${local.cpd_workspace}/mcg_odf_operator.yaml"
  provisioner "local-exec" {
    command = <<-EOF
echo "Setup ODF Operator"  &&
oc apply -f ${local.cpd_workspace}/mcg_odf_operator.yaml
status="unknown"
while [ "$status" != "Running" ]
do
  POD_NAME=$(oc get pods -n openshift-storage | grep noobaa-operator | awk '{print $1}' )
  ready_status=$(oc get pods -n openshift-storage $POD_NAME  --no-headers | awk '{print $2}')
  pod_status=$(oc get pods -n openshift-storage $POD_NAME --no-headers | awk '{print $3}')
  echo $POD_NAME State - $ready_status, podstatus - $pod_status
  if [ "$ready_status" == "1/1" ] && [ "$pod_status" == "Running" ]
  then
  status="Running"
  elif [ "$ready_status" == "2/2" ] && [ "$pod_status" == "Running" ]
  then
  status="Running"
  else
  status="starting"
  sleep 10
  fi
  echo "$POD_NAME is $status"
done
EOF
  }
  depends_on = [
    module.machineconfig,
    null_resource.login_cluster,
    null_resource.download_cpd_cli,
    null_resource.node_check,
    null_resource.configure_global_pull_secret,
    null_resource.cpd_certmanager_licensing_services,
    null_resource.authorize_instance_toplogy,
    null_resource.setup_instance_toplogy,
    local_file.mcg_namespace_yaml,
    local_file.mcg_operatorgroup_yaml
  ]
}

resource "local_file" "mcg_ocs_storagecluster_yaml" {
  count    = (var.watson_discovery == "yes" || var.watson_assistant == "yes" || var.watson_speech == "yes") ? 1 : 0
  content  = data.template_file.mcg_ocs_storagecluster.*.rendered[0]
  filename = "${local.cpd_workspace}/mcg_ocs_storagecluster.yaml"
  provisioner "local-exec" {
    command = <<-EOF
echo "Setup OCS storage cluster"  &&
oc apply -f ${local.cpd_workspace}/mcg_ocs_storagecluster.yaml
sleep 600
oc project openshift-storage
EOF
  }
  depends_on = [
    module.machineconfig,
    null_resource.login_cluster,
    null_resource.download_cpd_cli,
    null_resource.node_check,
    null_resource.configure_global_pull_secret,
    null_resource.cpd_certmanager_licensing_services,
    null_resource.authorize_instance_toplogy,
    null_resource.setup_instance_toplogy,
    local_file.mcg_namespace_yaml,
    local_file.mcg_operatorgroup_yaml,
    local_file.mcg_odf_operator_yaml
  ]
}

resource "null_resource" "mcg_ocs_storagecluster_exec" {
  count    = (var.watson_discovery == "yes" || var.watson_assistant == "yes" || var.watson_speech == "yes") ? 1 : 0

  provisioner "local-exec" {
    command = <<-EOF
oc project openshift-storage
echo "Setup OCS Storage cluster"  &&
oc get storagecluster -n openshift-storage
sleep 300
status=$(oc get storagecluster -n openshift-storage --no-headers | awk '{print $3}')

while [ "$status" != "Ready" ]
do
  ready_status=$(oc get storagecluster -n openshift-storage | grep ocs-storagecluster | awk '{print $3}')
  echo Storage cluster state - $ready_status
  if [ "$ready_status" == "Ready" ]
  then
  status="Ready"
  else
  oc exec -it deploy/noobaa-operator -- noobaa-operator -n openshift-storage backingstore create pv-pool noobaa-default-backing-store --num-volumes 1 --pv-size-gb 50
  sleep 10
  fi
  echo "Storage cluster status is $status"
done

oc get storagecluster -n openshift-storage
sleep 60
EOF
  }
  depends_on = [
    module.machineconfig,
    null_resource.login_cluster,
    null_resource.download_cpd_cli,
    null_resource.node_check,
    null_resource.configure_global_pull_secret,
    null_resource.cpd_certmanager_licensing_services,
    null_resource.authorize_instance_toplogy,
    null_resource.setup_instance_toplogy,
    local_file.mcg_namespace_yaml,
    local_file.mcg_operatorgroup_yaml,
    local_file.mcg_odf_operator_yaml,
    local_file.mcg_ocs_storagecluster_yaml
  ]
}

resource "null_resource" "mcg_wd_secrets" {
  triggers = {
    operator_namespace = var.cpd_operator_namespace
    instance_namespace = var.cpd_instance_namespace
    cpd_workspace      = local.cpd_workspace
    cpd_version        = local.cpd_version
    openshift_api      = var.openshift_api
    openshift_username = var.openshift_username
    openshift_password = sensitive(var.openshift_password)
    openshift_token    = var.openshift_token
    login_string       = var.login_string
  }
  count    = var.watson_discovery == "yes" ? 1 : 0
  provisioner "local-exec" {
    command = <<-EOF
echo "Setup WD mcg secrets"  &&
echo "Setting up Watson Discovery multi cloud gateway secrets"  &&
${self.triggers.cpd_workspace}/cpd-cli manage login-to-ocp --server ${self.triggers.openshift_api} -u '${self.triggers.openshift_username}' -p '${self.triggers.openshift_password}' || ${self.triggers.cpd_workspace}/cpd-cli manage login-to-ocp --server ${self.triggers.openshift_api} --token='${self.triggers.openshift_token}'
${self.triggers.cpd_workspace}/cpd-cli manage login-to-ocp --server ${self.triggers.openshift_api} -u '${self.triggers.openshift_username}' -p '${self.triggers.openshift_password}' || ${self.triggers.cpd_workspace}/cpd-cli manage login-to-ocp --server ${self.triggers.openshift_api} --token='${self.triggers.openshift_token}'

oc login ${self.triggers.openshift_api} -u '${self.triggers.openshift_username}' -p '${self.triggers.openshift_password}' --insecure-skip-tls-verify=true || oc login --server='${self.triggers.openshift_api}' --token='${self.triggers.openshift_token}'

oc get secrets --namespace=openshift-storage
export NOOBAA_ACCOUNT_CREDENTIALS_SECRET=noobaa-admin
export NOOBAA_ACCOUNT_CERTIFICATE_SECRET=noobaa-s3-serving-cert

${self.triggers.cpd_workspace}/cpd-cli manage setup-mcg \
--components=watson_discovery \
--cpd_instance_ns=${self.triggers.instance_namespace} \
--noobaa_account_secret=noobaa-admin \
--noobaa_cert_secret=noobaa-s3-serving-cert


oc get secrets --namespace=${self.triggers.instance_namespace} \
noobaa-account-watson-discovery \

sleep 20


EOF
  }
  depends_on = [
    module.machineconfig,
    null_resource.login_cluster,
    null_resource.download_cpd_cli,
    null_resource.node_check,
    null_resource.configure_global_pull_secret,
    null_resource.cpd_certmanager_licensing_services,
    null_resource.authorize_instance_toplogy,
    null_resource.setup_instance_toplogy,
    local_file.mcg_namespace_yaml,
    local_file.mcg_operatorgroup_yaml,
    local_file.mcg_odf_operator_yaml,
    local_file.mcg_ocs_storagecluster_yaml,
    null_resource.mcg_ocs_storagecluster_exec
  ]
}

resource "null_resource" "mcg_watson_speech_secrets" {
  triggers = {
    operator_namespace = var.cpd_operator_namespace
    instance_namespace = var.cpd_instance_namespace
    cpd_workspace      = local.cpd_workspace
    cpd_version        = local.cpd_version
    openshift_api      = var.openshift_api
    openshift_username = var.openshift_username
    openshift_password = sensitive(var.openshift_password)
    openshift_token    = var.openshift_token
    login_string       = var.login_string
  }
  count    = var.watson_speech == "yes" ? 1 : 0
  provisioner "local-exec" {
    command = <<-EOF
echo "Setup Watson Speech mcg secrets"  &&
echo "Setting up Watson Speech multi cloud gateway secrets"  &&
${self.triggers.cpd_workspace}/cpd-cli manage login-to-ocp --server ${self.triggers.openshift_api} -u '${self.triggers.openshift_username}' -p '${self.triggers.openshift_password}' || ${self.triggers.cpd_workspace}/cpd-cli manage login-to-ocp --server ${self.triggers.openshift_api} --token='${self.triggers.openshift_token}'
${self.triggers.cpd_workspace}/cpd-cli manage login-to-ocp --server ${self.triggers.openshift_api} -u '${self.triggers.openshift_username}' -p '${self.triggers.openshift_password}' || ${self.triggers.cpd_workspace}/cpd-cli manage login-to-ocp --server ${self.triggers.openshift_api} --token='${self.triggers.openshift_token}'

oc login ${self.triggers.openshift_api} -u '${self.triggers.openshift_username}' -p '${self.triggers.openshift_password}' --insecure-skip-tls-verify=true || oc login --server='${self.triggers.openshift_api}' --token='${self.triggers.openshift_token}'

oc get secrets --namespace=openshift-storage
export NOOBAA_ACCOUNT_CREDENTIALS_SECRET=noobaa-admin
export NOOBAA_ACCOUNT_CERTIFICATE_SECRET=noobaa-s3-serving-cert

${self.triggers.cpd_workspace}/cpd-cli manage setup-mcg \
--components=watson_speech \
--cpd_instance_ns=${self.triggers.instance_namespace} \
--noobaa_account_secret=noobaa-admin \
--noobaa_cert_secret=noobaa-s3-serving-cert

oc get secrets --namespace=${self.triggers.instance_namespace} \
noobaa-account-watson-speech

sleep 120
EOF
  }
  depends_on = [
    module.machineconfig,
    null_resource.login_cluster,
    null_resource.download_cpd_cli,
    null_resource.node_check,
    null_resource.configure_global_pull_secret,
    null_resource.cpd_certmanager_licensing_services,
    null_resource.authorize_instance_toplogy,
    null_resource.setup_instance_toplogy,
    local_file.mcg_namespace_yaml,
    local_file.mcg_operatorgroup_yaml,
    local_file.mcg_odf_operator_yaml,
    local_file.mcg_ocs_storagecluster_yaml,
    null_resource.mcg_ocs_storagecluster_exec,
    null_resource.mcg_wd_secrets
  ]
}

resource "null_resource" "mcg_wa_secrets" {
  triggers = {
    operator_namespace = var.cpd_operator_namespace
    instance_namespace = var.cpd_instance_namespace
    cpd_workspace      = local.cpd_workspace
    cpd_version        = local.cpd_version
    openshift_api      = var.openshift_api
    openshift_username = var.openshift_username
    openshift_password = var.openshift_password
    openshift_token    = var.openshift_token
    login_string       = var.login_string
  }
  count    = var.watson_assistant == "yes" ? 1 : 0
  provisioner "local-exec" {
    command = <<-EOF
echo "Setting up Watson Assistant multi cloud gateway secrets"  &&
${self.triggers.cpd_workspace}/cpd-cli manage login-to-ocp --server ${self.triggers.openshift_api} -u '${self.triggers.openshift_username}' -p '${self.triggers.openshift_password}' || ${self.triggers.cpd_workspace}/cpd-cli manage login-to-ocp --server ${self.triggers.openshift_api} --token='${self.triggers.openshift_token}'
${self.triggers.cpd_workspace}/cpd-cli manage login-to-ocp --server ${self.triggers.openshift_api} -u '${self.triggers.openshift_username}' -p '${self.triggers.openshift_password}' || ${self.triggers.cpd_workspace}/cpd-cli manage login-to-ocp --server ${self.triggers.openshift_api} --token='${self.triggers.openshift_token}'

oc login ${self.triggers.openshift_api} -u '${self.triggers.openshift_username}' -p '${self.triggers.openshift_password}' --insecure-skip-tls-verify=true || oc login --server='${self.triggers.openshift_api}' --token='${self.triggers.openshift_token}'

oc get secrets --namespace=openshift-storage
export NOOBAA_ACCOUNT_CREDENTIALS_SECRET=noobaa-admin
export NOOBAA_ACCOUNT_CERTIFICATE_SECRET=noobaa-s3-serving-cert

${self.triggers.cpd_workspace}/cpd-cli manage setup-mcg \
--components=watson_assistant \
--cpd_instance_ns=${self.triggers.instance_namespace} \
--noobaa_account_secret=noobaa-admin \
--noobaa_cert_secret=noobaa-s3-serving-cert

oc get secrets --namespace=${self.triggers.instance_namespace} \
noobaa-account-watson-assistant

sleep 20

echo "Deploy Knative Eventing for Watson Assistant"

${self.triggers.cpd_workspace}/cpd-cli manage deploy-knative-eventing --release=${self.triggers.cpd_version} --block_storage_class=${local.rwo_storage_class}

sleep 20

EOF
  }
  depends_on = [
    module.machineconfig,
    null_resource.login_cluster,
    null_resource.download_cpd_cli,
    null_resource.node_check,
    null_resource.configure_global_pull_secret,
    null_resource.cpd_certmanager_licensing_services,
    null_resource.authorize_instance_toplogy,
    null_resource.setup_instance_toplogy,
    local_file.mcg_namespace_yaml,
    local_file.mcg_operatorgroup_yaml,
    local_file.mcg_odf_operator_yaml,
    local_file.mcg_ocs_storagecluster_yaml,
    null_resource.mcg_ocs_storagecluster_exec,
    null_resource.mcg_wd_secrets,
    null_resource.mcg_watson_speech_secrets
  ]
}

resource "local_file" "wkc_iis_scc_yaml" {
  count    = (var.watson_knowledge_catalog == "yes" || var.watson_knowledge_catalog_core == "yes") ? 1 : 0
  content  = data.template_file.wkc_iis_scc.*.rendered[0]
  filename = "${local.cpd_workspace}/wkc_iis_scc.yaml"
  provisioner "local-exec" {
    command = <<-EOF
echo "Create SCC for WKC-IIS"  &&
oc apply -f ${local.cpd_workspace}/wkc_iis_scc.yaml
EOF
  }
}

resource "local_file" "install_options" {
  content  = local.combined_template
  filename = "${local.cpd_workspace}/install-options.yml"
}

resource "null_resource" "cpd_services" {
  triggers = {
    cpd_workspace = local.cpd_workspace
    cpd_operator_namespace = var.cpd_operator_namespace
    cpd_instance_namespace = var.cpd_instance_namespace
    cpd_version = local.cpd_version
  }

  provisioner "local-exec" {
    command = <<-EOF
echo "Deploy all catalogsources and operator subscriptions for ${local.cpd_services}"  &&
bash cpd/scripts/apply-olm.sh ${self.triggers.cpd_workspace} ${local.cpd_version}  ${local.cpd_services} ${var.cpd_operator_namespace}  &&
echo "Install options param file" &&
echo "Applying CR for ${local.cpd_services}" &&
bash cpd/scripts/apply-cr.sh ${self.triggers.cpd_workspace} ${local.cpd_version} ${local.cpd_services} ${var.cpd_operator_namespace} ${var.cpd_instance_namespace} ${var.storage_option}  ${local.storage_class} ${local.rwo_storage_class} /tmp/work/install-options.yml
EOF
  }
  depends_on = [
    module.machineconfig,
    null_resource.login_cluster,
    null_resource.download_cpd_cli,
    null_resource.node_check,
    null_resource.configure_global_pull_secret,
    null_resource.cpd_certmanager_licensing_services,
    null_resource.authorize_instance_toplogy,
    null_resource.setup_instance_toplogy,
    local_file.mcg_namespace_yaml,
    local_file.mcg_operatorgroup_yaml,
    local_file.mcg_odf_operator_yaml,
    local_file.mcg_ocs_storagecluster_yaml,
    null_resource.mcg_ocs_storagecluster_exec,
    null_resource.mcg_wd_secrets,
    null_resource.mcg_watson_speech_secrets,
    null_resource.mcg_wa_secrets
  ]
}

resource "null_resource" "manta_install" {
  triggers = {
    cpd_workspace = local.cpd_workspace
    cpd_operator_namespace = var.cpd_operator_namespace
    cpd_instance_namespace = var.cpd_instance_namespace
    cpd_version = local.cpd_version
  }

  count    = var.manta == "yes" ? 1 : 0
  provisioner "local-exec" {
    command = <<-EOF
echo "Deploy catalogsource and operator subscription for Manta"  &&
bash cpd/scripts/apply-olm.sh ${self.triggers.cpd_workspace} ${local.cpd_version}  mantaflow ${var.cpd_operator_namespace}  &&
echo "Install options param file" &&
cp ${self.triggers.cpd_workspace}/install-options.yml cpd-cli-workspace/olm-utils-workspace/work/install-options.yml &&
echo "Applying CR for Manta" &&
bash cpd/scripts/apply-cr.sh ${self.triggers.cpd_workspace} ${local.cpd_version} mantaflow ${var.cpd_operator_namespace} ${var.cpd_instance_namespace} ${var.storage_option}  ${local.storage_class} ${local.rwo_storage_class} /tmp/work/install-options.yml
EOF
  }
  depends_on = [
    module.machineconfig,
    null_resource.login_cluster,
    null_resource.download_cpd_cli,
    null_resource.node_check,
    null_resource.configure_global_pull_secret,
    null_resource.cpd_certmanager_licensing_services,
    null_resource.authorize_instance_toplogy,
    null_resource.setup_instance_toplogy,
    local_file.mcg_namespace_yaml,
    local_file.mcg_operatorgroup_yaml,
    local_file.mcg_odf_operator_yaml,
    local_file.mcg_ocs_storagecluster_yaml,
    null_resource.mcg_ocs_storagecluster_exec,
    null_resource.mcg_wd_secrets,
    null_resource.mcg_watson_speech_secrets,
    null_resource.mcg_wa_secrets,
    null_resource.cpd_services
  ]
}
