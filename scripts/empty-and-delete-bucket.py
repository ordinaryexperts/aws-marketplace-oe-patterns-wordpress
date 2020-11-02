#!/usr/bin/env python3
import boto3
import sys

if len(sys.argv) != 2:
    print("Usage: python3 empty-and-delete-bucket.py bucket-name")
    exit()

bucket_name = sys.argv[1]

s3 = boto3.resource('s3')
bucket = s3.Bucket(bucket_name)
bucket.object_versions.all().delete()
bucket.delete()
