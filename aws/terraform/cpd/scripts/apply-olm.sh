INSTALLER_PATH=$1
CPD_RELEASE=$2
COMPONENTS=$3
OPERATOR_NS=$4
$INSTALLER_PATH/cpd-cli manage apply-olm --release=$CPD_RELEASE --components=$COMPONENTS --cpd_operator_ns=$OPERATOR_NS
if [ $? -ne 0 ]
then
    echo "**********************************"
    echo "Deploying catalog Sources & subscription failed for one of the $COMPONENTS"
    echo "**********************************"
    exit 1
fi 
