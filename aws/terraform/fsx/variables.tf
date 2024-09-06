
variable "fsx_admin_password" {
  default     = "Netapp1!"
  description = "default fsx filesystem fsxadmin user password"
}

variable "preferred_subnet_id" {
  default     = ""
  description = "Preferred Subnet Id for Fsx"
}

variable "fsx_storage_capacity" {
  type    = number
  default = 1024
}

variable "fsx_throughput_capacity" {
  type    = number
  default = 256
}

variable "vpc_id" {
  type        = string
  description = "AWS VPC"
}

variable "az" {
  description = "single_zone / multi_zone"
  default     = "multi_zone"
}

variable "fsx_endpoint_cidr" {
  description = "The IP address range in which the endpoints to access your fsx file system will be created , required only for Multi-AZ deployment"
  default     = "10.0.255.255/26"
}

variable "private_subnet_ids" {
  type = list(any)
}

variable "cluster_name" {
  type    = string
  default = "rosaws"
}

variable "trident_operator_version" {
  type    = string
  default = "23.4.0"
}

variable "login_cmd" {
  type    = string
  default = "na"
}

variable "trident_namespace" {
  type    = string
  default = "trident"
}

variable "installer_workspace" {
  type        = string
  description = "Folder find the installation files"
  default     = "./"
}

variable "region" {
  description = "The region to deploy the cluster in, e.g: us-east-1."
  default     = "us-east-1"
}