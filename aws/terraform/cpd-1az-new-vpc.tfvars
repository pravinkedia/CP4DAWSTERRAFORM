##### AWS Configuration #####
region = "us-east-1"

access_key_id     = "<required>"
secret_access_key = "<required>"

##############################

# Enter the number of availability zones the cluster is to be deployed, default is single zone deployment.
az = "single_zone"

##########
# ROSA
##########

cluster_name         = "<required>"
rosa_token           = "<required>"
worker_machine_type  = "m5.4xlarge"
worker_machine_count = 6 # set count depending on number of CPD services
private_cluster      = false
fsx                  = { "enable" : "false" }
efs                  = { "enable" : "true" } ##Install efs storage 

#Storage 
storage_option = "efs-ebs" #nfs,efs,efs-ebs,fsx This storage option is for cpd services to use


#############
# CPD Variables
###############

cpd_api_key        = "<required>"
accept_cpd_license = "accept"
cpd_version        = "4.7.0"

## CPD services
watson_knowledge_catalog      = "no"
watson_knowledge_catalog_core = "no"
data_virtualization           = "no"
analytics_engine              = "no"
watson_studio                 = "no"
watson_machine_learning       = "no"
watson_ai_openscale           = "no"
spss_modeler                  = "no"
cognos_dashboard_embedded     = "no"
datastage                     = "no"
db2_warehouse                 = "no"
db2_oltp                      = "no"
cognos_analytics              = "no"
master_data_management        = "no"
decision_optimization         = "no"
bigsql                        = "no"
planning_analytics            = "no"
watson_assistant              = "no"
watson_discovery              = "no"
openpages                     = "no"
data_management_console       = "no"
factsheets                    = "no"
rstudio                       = "no"
ws_pipelines                  = "no"
watson_speech                 = "no"
manta                         = "no"
