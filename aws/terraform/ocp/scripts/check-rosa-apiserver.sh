INSTALLER_PATH_CLI=$1
CLUSTER_NAME_ROSA=$2
rosa_api_url=$($INSTALLER_PATH_CLI/rosa describe cluster --cluster $CLUSTER_NAME_ROSA  -o json | jq .api.url)
while [[ -z "$rosa_api_url" || $rosa_api_url == "null" ]];do
    echo -e "\nWaiting for the rosa api server url to be generated"
    echo -e "\nSleeping for a 1m"
    sleep 60
    rosa_api_url=$($INSTALLER_PATH_CLI/rosa describe cluster --cluster $CLUSTER_NAME_ROSA  -o json | jq .api.url)
done
echo -e "\nrosa api url is $rosa_api_url"