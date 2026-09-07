#!/usr/bin/env node
import { App } from 'aws-cdk-lib';

import { SiteStack } from '../lib/site-stack';

const app = new App();

new SiteStack(app, 'MylesShannonSite', {
  env: { account: process.env['CDK_DEFAULT_ACCOUNT'], region: 'us-east-1' },
  description: 'Static site for mylesshannon.com',
  apexDomain: 'mylesshannon.com',
  wwwDomain: 'www.mylesshannon.com',
  siteBucketName: 'www.mylesshannon.com',
  logBucketName: 'myles-com-logs',
  hostedZoneId: 'Z3NDC2K77LJES0',
  certificateId: 'a16468dc-7100-4b18-9605-2d2e082707a3',
});
