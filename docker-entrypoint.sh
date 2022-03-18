#!/usr/bin/env bash

set -e -u

PROFILE="${PROFILE-"puerto-rico_profiles/puerto-rico_open/"}"
S3_DESTINATION="${S3_DESTINATION:?"S3_DESTINATION not set"}"
DISTRIBUTION_ID="${DISTRIBUTION_ID:?"DISTRIBUTION_ID not set"}"

snakemake --printshellcmds --profile "${PROFILE}"
aws s3 sync auspice/ "${S3_DESTINATION}"
aws cloudfront create-invalidation \
  --distribution-id "${DISTRIBUTION_ID}" \
  --paths '/auspice/*'
