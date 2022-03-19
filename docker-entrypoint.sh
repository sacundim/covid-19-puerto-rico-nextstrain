#!/usr/bin/env bash

set -e -u -x
shopt -s extglob

PROFILE="${PROFILE-"puerto-rico_profiles/puerto-rico_open/"}"
S3_DESTINATION="${S3_DESTINATION:?"S3_DESTINATION not set"}"
DISTRIBUTION_ID="${DISTRIBUTION_ID:?"DISTRIBUTION_ID not set"}"

# Remove final slashes
S3_DESTINATION="${S3_DESTINATION%%+(/)}"

# This is to check that we have the permission to do at least this
# before we spend 4-6 hours running the build:
aws s3 ls "${S3_DESTINATION}"/

snakemake --printshellcmds --profile "${PROFILE}"
aws s3 sync --no-progress auspice/ "${S3_DESTINATION}"/
aws cloudfront create-invalidation \
  --distribution-id "${DISTRIBUTION_ID}" \
  --paths '/auspice/*'

echo "$(date): All done"
