"""S3/MinIO client utilities for receipt object storage.

Provides presigned URL generation, HEAD checks, object download,
and bucket initialisation via boto3 with MinIO-compatible config.
"""

import logging

import boto3
from botocore.config import Config as BotoConfig
from botocore.exceptions import ClientError

from app.core.config import s3_settings

logger = logging.getLogger(__name__)

_client = None
_presign_client = None


def get_s3_client():
    """Return a lazily-initialised boto3 S3 client for internal network access."""
    global _client
    if _client is None:
        _client = boto3.client(
            "s3",
            endpoint_url=s3_settings.ENDPOINT,
            aws_access_key_id=s3_settings.ACCESS_KEY,
            aws_secret_access_key=s3_settings.SECRET_KEY,
            region_name=s3_settings.REGION,
            config=BotoConfig(signature_version="s3v4"),
        )
    return _client


def get_s3_presign_client():
    """Return a lazily-initialised S3 client for generating external presigned URLs.
    
    If S3_EXTERNAL_ENDPOINT is set, it handles generating URLs that clients 
    outside the Docker network (like mobile devices) can reach.
    """
    global _presign_client
    if _presign_client is None:
        _presign_client = boto3.client(
            "s3",
            endpoint_url=s3_settings.EXTERNAL_ENDPOINT or s3_settings.ENDPOINT,
            aws_access_key_id=s3_settings.ACCESS_KEY,
            aws_secret_access_key=s3_settings.SECRET_KEY,
            region_name=s3_settings.REGION,
            config=BotoConfig(signature_version="s3v4"),
        )
    return _presign_client


def generate_presigned_put(
    key: str,
    content_type: str,
    bucket: str | None = None,
    expiry: int | None = None,
) -> dict:
    """Generate a presigned PUT URL for direct client upload.

    The Content-Type is signed into the URL so the client *must* send the
    same value, otherwise the signature will be rejected by MinIO.

    Returns ``{"url": "...", "required_headers": {"Content-Type": "..."}}``.
    """
    bucket = bucket or s3_settings.BUCKET_RECEIPTS
    expiry = expiry or s3_settings.PRESIGNED_PUT_EXPIRY_SECONDS
    client = get_s3_presign_client()
    url = client.generate_presigned_url(
        "put_object",
        Params={
            "Bucket": bucket,
            "Key": key,
            "ContentType": content_type,
        },
        ExpiresIn=expiry,
    )
    return {
        "url": url,
        "required_headers": {"Content-Type": content_type},
    }


def generate_presigned_get(
    key: str,
    bucket: str | None = None,
    expiry: int | None = None,
) -> str:
    """Generate a presigned GET URL for client-side object viewing."""

    bucket = bucket or s3_settings.BUCKET_RECEIPTS
    expiry = expiry or s3_settings.PRESIGNED_GET_EXPIRY_SECONDS
    client = get_s3_presign_client()
    return client.generate_presigned_url(
        "get_object",
        Params={
            "Bucket": bucket,
            "Key": key,
        },
        ExpiresIn=expiry,
    )


def head_object(key: str, bucket: str | None = None) -> dict:
    """HEAD an object and return size + content-type.

    Raises ``ClientError`` if the object does not exist.
    """
    bucket = bucket or s3_settings.BUCKET_RECEIPTS
    client = get_s3_client()
    resp = client.head_object(Bucket=bucket, Key=key)
    return {
        "size_bytes": resp["ContentLength"],
        "content_type": resp["ContentType"],
    }


def download_object(key: str, bucket: str | None = None) -> bytes:
    """Download an object's contents into memory."""
    bucket = bucket or s3_settings.BUCKET_RECEIPTS
    client = get_s3_client()
    resp = client.get_object(Bucket=bucket, Key=key)
    return resp["Body"].read()


def ensure_bucket(bucket: str | None = None) -> None:
    """Create the bucket if it does not already exist."""
    bucket = bucket or s3_settings.BUCKET_RECEIPTS
    client = get_s3_client()
    try:
        client.head_bucket(Bucket=bucket)
        logger.info("S3 bucket '%s' already exists.", bucket)
    except ClientError:
        try:
            client.create_bucket(Bucket=bucket)
            logger.info("Created S3 bucket '%s'.", bucket)
        except ClientError:
            logger.exception("Failed to create S3 bucket '%s'.", bucket)
            raise
