#!/usr/bin/env bash

set -e -u -x

PROFILE="${PROFILE-"puerto-rico_profiles/puerto-rico_open/"}"
snakemake --printshellcmds --profile "${PROFILE}"

if [[ -z "${S3_DESTINATION}" ]]
then
  aws s3 sync auspice/ "${S3_DESTINATION}"
else
  echo "$(date): No S3_DESTINATION set. Skipping aws s3 sync."
fi

if [[ -z "${DISTRIBUTION_ID}" ]]
then
  aws cloudfront create-invalidation \
    --distribution-id "${DISTRIBUTION_ID}" \
    --paths '/*'
else
  echo "$(date): No DISTRIBUTION_ID set. Skipping CloudFront invalidation."
fi
