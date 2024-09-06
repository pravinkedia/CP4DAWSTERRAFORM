INSTALLER_PATH=$1
CPD_RELEASE=$2
COMPONENTS=$3
OPERATOR_NS=$4
NAMESPACE=$5
SC_VENDOR=$6
FILE_SC=$7
BLOCK_SC=$8
PARAM_FILE=$9
if [[ "$SC_VENDOR" != "portworx" ]]
then
  $INSTALLER_PATH/cpd-cli manage apply-cr --release=$CPD_RELEASE --components=$COMPONENTS  --license_acceptance=true  --cpd_operator_ns=$OPERATOR_NS  --cpd_instance_ns=$NAMESPACE --file_storage_class=$FILE_SC --block_storage_class=$BLOCK_SC --param-file=$PARAM_FILE --parallel_num=6
else
  $INSTALLER_PATH/cpd-cli manage apply-cr --release=$CPD_RELEASE --components=$COMPONENTS  --license_acceptance=true  --cpd_operator_ns=$OPERATOR_NS  --cpd_instance_ns=$NAMESPACE --storage_vendor=portworx --param-file=$PARAM_FILE --parallel_num=6
fi
if [ $? -ne 0 ]
then
    echo "**********************************"
    echo "Applying CR for one of the $COMPONENTS failed"
    echo "**********************************"
    exit 1
fi 

