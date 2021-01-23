#!/usr/bin/env bash

# https://stackoverflow.com/a/246128
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

TYPE="${1:-all}"
PREFIX="${2:-user}"
TEST_REGIONS="${3:-main}"

if [[ $TEST_REGIONS == "all" ]]; then
    readarray -t REGIONS < /code/supported_regions.txt
else
    REGIONS=('us-east-1')
fi

if [[ $PREFIX == "tcat" ]]; then
    PREFIX_TO_DELETE="tcat"
else
    PREFIX_TO_DELETE="oe-patterns-drupal-${USER}"
fi

if [[ $TYPE == "all" || $TYPE == "buckets" ]]; then
    echo "Removing $PREFIX_TO_DELETE buckets..."
    BUCKETS=`aws s3 ls | awk '{print $3}'`
    for bucket in $BUCKETS; do
        if [[ $bucket == $PREFIX_TO_DELETE* ]]; then
            echo $bucket
            python3 $DIR/empty-and-delete-bucket.py $bucket
        fi
    done
    echo "done."
fi

if [[ $TYPE == "all" || $TYPE == "snapshots" ]]; then
    for region in ${REGIONS[@]}; do
        echo "Removing $PREFIX_TO_DELETE snapshots in $region..."
        SNAPSHOTS=`aws rds describe-db-cluster-snapshots --region $region | jq -r '.DBClusterSnapshots[].DBClusterSnapshotIdentifier'`
        for snapshot in $SNAPSHOTS; do
            if [[ $snapshot == $PREFIX_TO_DELETE* ]]; then
                echo $snapshot
                aws rds delete-db-cluster-snapshot --region $region --db-cluster-snapshot-identifier $snapshot
            fi
        done
    done
    echo "done."
fi

if [[ $TYPE == "all" || $TYPE == "stacks" ]]; then
    for region in ${REGIONS[@]}; do
        echo "Removing $PREFIX_TO_DELETE stacks in $region..."
        STACKS=`aws cloudformation describe-stacks --region $region | jq -r '.Stacks[].StackName'`
        for stack in $STACKS; do
            if [[ $PREFIX_TO_DELETE == "tcat" ]]; then
                if [[ $stack == tCaT* ]]; then
                    echo $stack
                    aws cloudformation delete-stack --region $region --stack-name $stack
                fi
            else
                if [[ $stack == $PREFIX_TO_DELETE* ]]; then
                    echo $stack
                    aws cloudformation delete-stack --region $region --stack-name $stack
                fi
            fi
        done
    done
    echo "done."
fi

if [[ $TYPE == "all" || $TYPE == "logs" ]]; then
    for region in ${REGIONS[@]}; do
        echo "Removing $PREFIX_TO_DELETE log groups in $region..."
        LOG_GROUPS=`aws logs describe-log-groups --region $region | jq -r '.logGroups[].logGroupName'`
        for log_group in $LOG_GROUPS; do
            if [[ $log_group == $PREFIX_TO_DELETE* || $log_group == /aws/codebuild/$PREFIX_TO_DELETE* ]]; then
                echo $log_group
                aws logs delete-log-group --region $region --log-group-name $log_group
            fi
            if [[ $PREFIX_TO_DELETE == "tcat" ]]; then
                if [[ $log_group == tCaT* || $log_group == /aws/codebuild/tCaT* ]]; then
                    echo $log_group
                    aws logs delete-log-group --region $region --log-group-name $log_group
                fi
            fi
            if [[ $log_group == /aws/rds/cluster/$PREFIX_TO_DELETE* ]]; then
                echo $log_group
                aws logs delete-log-group --region $region --log-group-name $log_group
            fi
        done
    done
    echo "done."
fi
