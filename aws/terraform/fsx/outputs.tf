output "fsx-management-ip" {
  value = local.fsx_mngmt_ip
}

output "fsx-management-dns" {
  value = local.fsx_mngmt_dnsname
}

output "fsx-svm-name" {
  value = aws_fsx_ontap_storage_virtual_machine.cpdsvm.name
}
output "fsx-svm-id" {
  value = aws_fsx_ontap_storage_virtual_machine.cpdsvm.id
}

output "fsx-svmadmin-password" {
  value = aws_fsx_ontap_storage_virtual_machine.cpdsvm.svm_admin_password
}