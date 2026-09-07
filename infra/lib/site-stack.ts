import { CfnOutput, Duration, RemovalPolicy, Stack, type StackProps } from 'aws-cdk-lib';
import * as acm from 'aws-cdk-lib/aws-certificatemanager';
import * as cloudfront from 'aws-cdk-lib/aws-cloudfront';
import * as origins from 'aws-cdk-lib/aws-cloudfront-origins';
import * as route53 from 'aws-cdk-lib/aws-route53';
import * as targets from 'aws-cdk-lib/aws-route53-targets';
import * as s3 from 'aws-cdk-lib/aws-s3';
import type { Construct } from 'constructs';

export interface SiteStackProps extends StackProps {
  /** Canonical host. Everything redirects here. */
  readonly apexDomain: string;
  /** Redirected to the apex with a 301. */
  readonly wwwDomain: string;
  readonly siteBucketName: string;
  readonly logBucketName: string;
  readonly hostedZoneId: string;
  /**
   * UUID of an existing certificate covering both domains, in us-east-1. The account
   * half of the ARN is filled in from the deploying credentials, so this repository can
   * stay public without publishing the account number.
   */
  readonly certificateId: string;
}

export class SiteStack extends Stack {
  constructor(scope: Construct, id: string, props: SiteStackProps) {
    super(scope, id, props);

    const site = new s3.Bucket(this, 'SiteBucket', {
      bucketName: props.siteBucketName,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      enforceSSL: true,
      // Retained on stack deletion. The contents are reproducible from git, but an
      // accidental destroy should not silently take the live site with it.
      removalPolicy: RemovalPolicy.RETAIN,
    });

    // CloudFront standard logging writes objects using an ACL grant. Buckets created
    // since April 2023 default to BucketOwnerEnforced, which disables ACLs and makes
    // log delivery fail silently, with no error and a permanently empty bucket.
    const logs = new s3.Bucket(this, 'LogBucket', {
      bucketName: props.logBucketName,
      objectOwnership: s3.ObjectOwnership.BUCKET_OWNER_PREFERRED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      enforceSSL: true,
      lifecycleRules: [{ expiration: Duration.days(365) }],
      removalPolicy: RemovalPolicy.RETAIN,
    });

    // Multi-value query parameters collapse to their first value, which is acceptable
    // for a site whose only inbound links carry at most tracking parameters.
    const redirect = new cloudfront.Function(this, 'WwwRedirect', {
      runtime: cloudfront.FunctionRuntime.JS_2_0,
      comment: `301 ${props.wwwDomain} to ${props.apexDomain}`,
      code: cloudfront.FunctionCode.fromInline(`
function handler(event) {
	var request = event.request;
	if (request.headers.host.value !== '${props.wwwDomain}') {
		return request;
	}
	var pairs = [];
	for (var key in request.querystring) {
		pairs.push(key + '=' + request.querystring[key].value);
	}
	var query = pairs.length ? '?' + pairs.join('&') : '';
	return {
		statusCode: 301,
		statusDescription: 'Moved Permanently',
		headers: { location: { value: 'https://${props.apexDomain}' + request.uri + query } },
	};
}
`),
    });

    const distribution = new cloudfront.Distribution(this, 'Distribution', {
      comment: props.apexDomain,
      domainNames: [props.apexDomain, props.wwwDomain],
      certificate: acm.Certificate.fromCertificateArn(
        this,
        'Certificate',
        this.formatArn({
          service: 'acm',
          resource: 'certificate',
          resourceName: props.certificateId,
        }),
      ),
      defaultRootObject: 'index.html',
      priceClass: cloudfront.PriceClass.PRICE_CLASS_100,
      httpVersion: cloudfront.HttpVersion.HTTP2_AND_3,
      minimumProtocolVersion: cloudfront.SecurityPolicyProtocol.TLS_V1_2_2021,
      enableLogging: true,
      logBucket: logs,
      defaultBehavior: {
        origin: origins.S3BucketOrigin.withOriginAccessControl(site),
        viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
        allowedMethods: cloudfront.AllowedMethods.ALLOW_GET_HEAD,
        cachePolicy: cloudfront.CachePolicy.CACHING_OPTIMIZED,
        compress: true,
        functionAssociations: [
          { function: redirect, eventType: cloudfront.FunctionEventType.VIEWER_REQUEST },
        ],
      },
      // One page, so a missing key is a real 404, not a client-side route. Returning 200
      // would tell search engines every mistyped URL is genuine content.
      errorResponses: [
        {
          httpStatus: 403,
          responseHttpStatus: 404,
          responsePagePath: '/index.html',
          ttl: Duration.minutes(5),
        },
        {
          httpStatus: 404,
          responseHttpStatus: 404,
          responsePagePath: '/index.html',
          ttl: Duration.minutes(5),
        },
      ],
    });

    const zone = route53.HostedZone.fromHostedZoneAttributes(this, 'Zone', {
      hostedZoneId: props.hostedZoneId,
      zoneName: props.apexDomain,
    });

    const target = route53.RecordTarget.fromAlias(new targets.CloudFrontTarget(distribution));

    // No deleteExisting here: it is deprecated as dangerous — a failed deployment can
    // leave the record deleted — and this zone also carries live mail.
    new route53.ARecord(this, 'ApexA', { zone, target });
    new route53.AaaaRecord(this, 'ApexAaaa', { zone, target });
    new route53.ARecord(this, 'WwwA', { zone, recordName: 'www', target });
    new route53.AaaaRecord(this, 'WwwAaaa', { zone, recordName: 'www', target });

    new CfnOutput(this, 'BucketName', { value: site.bucketName });
    new CfnOutput(this, 'DistributionId', { value: distribution.distributionId });
    new CfnOutput(this, 'DistributionDomain', { value: distribution.distributionDomainName });
  }
}
