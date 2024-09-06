#!/bin/bash
function check_machine_status() {
   local machine_pool=$1
   MACHINE_STATUS=$( oc get machines -n openshift-machine-api  | grep $machine_pool | awk '{print $2}')
    while [[ $MACHINE_STATUS != "Running" ]];do
            echo -e "Sleeping for a 1m"
            sleep 60
            MACHINE_STATUS=$( oc get machines -n openshift-machine-api  | grep $machine_pool | awk '{print $2}')
            echo -e "Waiting for the machines to get into running state , current status is $MACHINE_STATUS"
   done
}

INSTALLER_PATH_CLI=$1
CLUSTER_NAME_ROSA=$2
CLUSTER_REGION=$3
INSTANCE_TYPE=$4
ADD_NODE_COUNT=$5
if [  $ADD_NODE_COUNT -ne 0 ]; then
    echo "$INSTALLER_PATH_CLI/rosa create machinepool -c $CLUSTER_NAME_ROSA  --availability-zone  ${CLUSTER_REGION}a  --replicas 1 --name machinepool1 --instance-type $INSTANCE_TYPE  --yes"
    $INSTALLER_PATH_CLI/rosa create machinepool -c $CLUSTER_NAME_ROSA  --availability-zone  ${CLUSTER_REGION}a  --replicas 1 --name machinepool1 --instance-type $INSTANCE_TYPE  --yes
    check_machine_status machinepool1
    ADD_NODE_COUNT=$((ADD_NODE_COUNT-1)) 
    if [  $ADD_NODE_COUNT -ne 0 ]; then
      echo "$INSTALLER_PATH_CLI/rosa create machinepool -c $CLUSTER_NAME_ROSA  --availability-zone  ${CLUSTER_REGION}b  --replicas 1 --name machinepool2 --instance-type $INSTANCE_TYPE  --yes"
      $INSTALLER_PATH_CLI/rosa create machinepool -c $CLUSTER_NAME_ROSA  --availability-zone  ${CLUSTER_REGION}b  --replicas 1 --name machinepool2 --instance-type $INSTANCE_TYPE  --yes
      check_machine_status machinepool2
    fi
fi       