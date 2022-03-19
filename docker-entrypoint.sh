#!/usr/bin/env bash

set -e -u -x -o pipefail

RUN_TIME="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
S3_AUSPICE_DESTINATION="${S3_AUSPICE_DESTINATION:?"S3_AUSPICE_DESTINATION not set"}"
S3_JOBS_DESTINATION="${S3_JOBS_DESTINATION:?"S3_JOBS_DESTINATION not set"}"
CLOUDFRONT_DISTRIBUTION_ID="${CLOUDFRONT_DISTRIBUTION_ID:?"CLOUDFRONT_DISTRIBUTION_ID not set"}"

# Remove final slashes
shopt -s extglob # Needed for the globs just below to work
S3_AUSPICE_DESTINATION="${S3_AUSPICE_DESTINATION%%+(/)}"
S3_JOBS_DESTINATION="${S3_JOBS_DESTINATION%%+(/)}"

# This is to check that we have the permission to do at least this
# before we spend 4-6 hours running the build for nothing:
echo "$(date): Checking access to destination and jobs buckets"
aws s3 ls "${S3_AUSPICE_DESTINATION}"/
aws s3 ls "${S3_JOBS_DESTINATION}"/


echo "$(date): Running the Nexstrain build"
snakemake --printshellcmds "$@"


echo "$(date): Syncing auspice files to destination bucket"
aws s3 sync --no-progress auspice/ "${S3_AUSPICE_DESTINATION}"/


echo "$(date): Invalidating CloudFront distribution"
aws cloudfront create-invalidation \
  --distribution-id "${CLOUDFRONT_DISTRIBUTION_ID}" \
  --paths '/auspice/*'


echo "$(date): Syncing other result files to jobs bucket"
if [[ -z "${AWS_BATCH_JOB_ID}" ]]
then
  JOB_ID="${RUN_TIME}"
else
  JOB_ID="${RUN_TIME}_${AWS_BATCH_JOB_ID}"
fi
S3_JOB_DESTINATION="${S3_JOBS_DESTINATION}/${JOB_ID}"
for directory in .snakemake auspice benchmarks data.nextstrain.org logs results
do
  if [ -d "${directory}" ]
  then
    aws s3 sync --no-progress "${directory}"/ "${S3_JOB_DESTINATION}"/"${directory}"/
  fi
done

echo "$(date): All done"
