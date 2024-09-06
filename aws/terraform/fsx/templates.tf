locals {
  svm_name = aws_fsx_ontap_storage_virtual_machine.cpdsvm.name
  svm_pwd  = aws_fsx_ontap_storage_virtual_machine.cpdsvm.svm_admin_password

}

data "template_file" "backend_fsx_ontap_secret" {
  template = <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: backend-tbc-ontap-nas-advanced-secret
  namespace: ${var.trident_namespace}
type: Opaque
stringData:
  username: fsxadmin
  password: ${local.svm_pwd}
EOF
}

data "template_file" "trident_backend_config" {
  template = <<EOF
apiVersion: trident.netapp.io/v1
kind: TridentBackendConfig
metadata:
  name: backend-fsx-ontap-nas
  namespace: ${var.trident_namespace}
spec:
  version: 1
  backendName: tbc-ontap-nas-advanced
  storageDriverName: ontap-nas
  managementLIF: ${local.fsx_mngmt_dnsname}
  svm: ${local.svm_name}
  credentials:
    name: backend-tbc-ontap-nas-advanced-secret
EOF
}


data "template_file" "ontap_nas_sc" {
  template = <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ontap-nas
provisioner: csi.trident.netapp.io
parameters:
  storagePools: "tbc-ontap-nas-advanced:.*"
  fsType: "nfs"
allowVolumeExpansion: True
EOF
}
