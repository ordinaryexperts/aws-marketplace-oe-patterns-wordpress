import os
import logging

from datetime import datetime

import boto3
import botocore

logger = logging.getLogger()
logger.setLevel("INFO")

cloudfront_client = boto3.client("cloudfront")
codepipeline_client = boto3.client("codepipeline")

def lambda_handler(event, context):
    job_id = event["CodePipeline.job"]["id"]
    logger.info("CloudFront Invalidation Lambda starting with job id: {}...".format(job_id))

    now = datetime.now()
    now_formatted = now.strftime("%Y%m%dT%H%m%S")
    
    try:
        logger.info("Creating CloudFront Invalidation: {}...".format(now_formatted))
        cloudfront_client.create_invalidation(
            DistributionId=os.environ["CloudFrontDistributionId"],
            InvalidationBatch={
                "Paths": {
                    "Quantity": 1,
                    "Items": [
                        "/*"
                    ]
                },
                "CallerReference": now_formatted
            }
        )
        logger.info("Created")

        codepipeline_client.put_job_success_result(jobId=job_id)
    except Exception as e:
        logger.error("Failed")
        logger.error(e)
        codepipeline_client.put_job_failure_result(
            failureDetails={
                "type": "JobFailed",
                "message": str(e)
            },
            jobId=job_id
        )
    
