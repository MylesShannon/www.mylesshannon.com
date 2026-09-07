#!/usr/bin/env bash
#
# Publishes src/ to S3 and clears the CloudFront edge cache.
#
# Filenames are not content-hashed, so every object is uploaded must-revalidate. A long
# max-age would strand returning visitors on stale CSS that an invalidation cannot reach,
# because invalidation clears CloudFront's cache and not the browser's. For a handful of
# small files, revalidation costs one 304.

set -euo pipefail

STACK="${SITE_STACK:-MylesShannonSite}"
REGION="${AWS_REGION:-us-east-1}"

if [[ ! -f src/index.html ]]; then
	echo "src/index.html is missing; run this from the repository root" >&2
	exit 1
fi

output() {
	aws cloudformation describe-stacks \
		--stack-name "$STACK" --region "$REGION" \
		--query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text
}

BUCKET="${SITE_BUCKET:-$(output BucketName)}"
DISTRIBUTION="${SITE_DISTRIBUTION:-$(output DistributionId)}"

if [[ -z "$BUCKET" || "$BUCKET" == "None" || -z "$DISTRIBUTION" || "$DISTRIBUTION" == "None" ]]; then
	echo "Could not read BucketName and DistributionId from stack $STACK" >&2
	exit 1
fi

echo "==> Uploading src/ to s3://$BUCKET"
aws s3 sync src/ "s3://$BUCKET" \
	--no-progress \
	--delete \
	--cache-control "no-cache, must-revalidate"

echo
echo "==> Invalidating CloudFront $DISTRIBUTION"
# A wildcard counts as a single path against the monthly free allowance.
INVALIDATION=$(aws cloudfront create-invalidation \
	--distribution-id "$DISTRIBUTION" \
	--paths "/*" \
	--query "Invalidation.Id" \
	--output text)
echo "Invalidation $INVALIDATION created"

aws cloudfront wait invalidation-completed \
	--distribution-id "$DISTRIBUTION" \
	--id "$INVALIDATION"

echo
echo "Deployed. https://mylesshannon.com/"
