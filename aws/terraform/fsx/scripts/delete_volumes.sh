#!/bin/bash
region=$1
file_system_id=$2
svm_name=$3

echo "aws fsx describe-volumes \
        --region "${region}" \
        --filters "Name=file-system-id,Values=${file_system_id}" \
        --max-items 5000 \
        --page-size 100 \
        --no-cli-pager \
        --query "Volumes[?Name != \`${svm_name}_root\`].VolumeId" \
        --output text \
        | tr -s "\\t" "\\n" \
        | xargs -I{} aws fsx delete-volume \
                    --region "${region}" \
                    --volume-id {} \
                    --ontap-configuration SkipFinalBackup=true"

aws fsx describe-volumes \
        --region "${region}" \
        --filters "Name=file-system-id,Values=${file_system_id}" \
        --max-items 5000 \
        --page-size 100 \
        --no-cli-pager \
        --query "Volumes[?Name != \`${svm_name}_root\`].VolumeId" \
        --output text \
        | tr -s "\\t" "\\n" \
        | xargs -I{} aws fsx delete-volume \
                    --region "${region}" \
                    --volume-id {} \
                    --ontap-configuration SkipFinalBackup=true

while true; do
fsx_volumes=$(aws fsx describe-volumes \
            --region "${region}" \
            --filters "Name=file-system-id,Values=${file_system_id}" \
            --max-items 5000 \
            --page-size 100 \
            --no-cli-pager \
            --query "Volumes[?Name != \`${svm_name}_root\`].VolumeId" \
            --output text)
        if [ -n "${fsx_volumes}" ]; then
            echo "INFO: Still waiting on deletion of volumes ${fsx_volumes} for ${file_system_id}"
            sleep 10
        else
            break;
        fi
    done

