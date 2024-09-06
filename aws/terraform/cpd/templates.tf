locals {
  storage_type_key = var.storage_option == "portworx" ? "storageVendor: portworx" : "fileStorageClass: ${local.storage_class}\n  blockStorageClass: ${local.rwo_storage_class}"
  enable_manta     = var.enable_fips == false ? "True" : "False"
}
data "template_file" "wkc_iis_scc" {
  count    = (var.watson_knowledge_catalog == "yes" || var.watson_knowledge_catalog_core == "yes") ? 1 : 0
  template = <<EOF
allowHostDirVolumePlugin: false
allowHostIPC: false
allowHostNetwork: false
allowHostPID: false
allowHostPorts: false
allowPrivilegeEscalation: true
allowPrivilegedContainer: false
allowedCapabilities: null
apiVersion: security.openshift.io/v1
defaultAddCapabilities: null
fsGroup:
  type: RunAsAny
kind: SecurityContextConstraints
metadata:
  annotations:
    kubernetes.io/description: WKC/IIS provides all features of the restricted SCC
      but runs as user 10032.
  name: wkc-iis-scc
readOnlyRootFilesystem: false
requiredDropCapabilities:
- KILL
- MKNOD
- SETUID
- SETGID
runAsUser:
  type: MustRunAs
  uid: 10032
seLinuxContext:
  type: MustRunAs
supplementalGroups:
  type: RunAsAny
volumes:
- configMap
- downwardAPI
- emptyDir
- persistentVolumeClaim
- projected
- secret
users:
- system:serviceaccount:${var.cpd_instance_namespace}:wkc-iis-sa
EOF
}

data "template_file" "wkc_cr_spec" {
  count    = var.watson_knowledge_catalog == "yes" ? 1 : 0
  template = <<EOF
custom_spec:
  wkc:
    wkc_db2u_set_kernel_params: True
    enableKnowledgeGraph: True
    enableDataQuality: True
    enableMANTA: ${local.enable_manta}
EOF
}

data "template_file" "wkc_core_cr_spec" {
  count    = var.watson_knowledge_catalog_core == "yes" ? 1 : 0
  template = <<EOF
custom_spec:
  wkc:
    wkc_db2u_set_kernel_params: True
EOF
}


data "template_file" "replication_install_options" {
  template = <<EOF
replication_license_type: IDRC
EOF
}

locals {
  wkc_core_cr_spec_contents = length(data.template_file.wkc_core_cr_spec) > 0 ? data.template_file.wkc_core_cr_spec.*.rendered[0] : ""
  wkc_cr_spec_contents      = length(data.template_file.wkc_cr_spec) > 0 ? data.template_file.wkc_cr_spec.*.rendered[0] : ""
  rep_cr_contents           = length(data.template_file.replication_install_options) > 0 ? data.template_file.replication_install_options.*.rendered[0] : ""
  combined_template         = "${local.wkc_core_cr_spec_contents}${local.wkc_cr_spec_contents}${local.rep_cr_contents}"
}