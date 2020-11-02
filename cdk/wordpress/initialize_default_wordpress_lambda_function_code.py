import os
import logging
import shutil
import urllib3
import uuid

import boto3
import botocore
from botocore.exceptions import ClientError
import cfnresponse

logger = logging.getLogger()
logger.setLevel("INFO")

cloudformation_client = boto3.client("cloudformation")
s3_client = boto3.client("s3")

def lambda_handler(event, context):
    logger.info("Initialize Default WordPress Lambda starting...")

    try:
        if (event["RequestType"] == "Create"):
            source_already_exists = False
            try:
                s3_client.head_object(
                    Bucket=os.environ["SourceArtifactBucket"],
                    Key=os.environ["SourceArtifactObjectKey"]
                )
                source_already_exists = True
            except ClientError as e:
                # perform the copy only if the object is not found
                # in this case that means a 404 ClientError from the HeadObject request
                if e.response["Error"]["Code"] == "404":
                    copy_source = os.environ["DefaultWordPressSourceUrl"]
                    local_file = "/tmp/drupal.zip"
                    logger.info("Copying {} to {}/{}".format(
                        copy_source,
                        os.environ["SourceArtifactBucket"],
                        os.environ["SourceArtifactObjectKey"]
                    ))

                    c = urllib3.PoolManager()
                    with c.request('GET', copy_source, preload_content=False) as resp, open(local_file, 'wb') as out_file:
                        shutil.copyfileobj(resp, out_file)
                    resp.release_conn()

                    s3_client.upload_file(
                        local_file,
                        os.environ["SourceArtifactBucket"],
                        os.environ["SourceArtifactObjectKey"]
                    )
                    logger.info("WordPress codebase copy complete.")

            if source_already_exists:
                logger.info("The artifact object already exists. Copy aborted.")
                # an error cfnresponse could be returned here if we wanted to fail the stack

        cfnresponse.send(event, context, cfnresponse.SUCCESS, {})
        logger.info("CloudFormation success response sent.")

    except Exception as e:
        logger.error(e)
        cfnresponse.send(event, context, cfnresponse.FAILED, {})
        raise e
