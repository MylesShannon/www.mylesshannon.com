# mylesshannon.com

A single static page: name, role, and links to GitHub and LinkedIn.

There is no build step. `src/` is the site — the files you edit are the files that get
uploaded. The page loads nothing from a third party: the brand marks are inline SVG and
the type is a system font stack.

## Layout

| Path | Purpose |
| --- | --- |
| `src/` | The site. Everything here is published verbatim. |
| `infra/` | CDK app owning the bucket, CloudFront distribution and DNS records. |
| `test.sh` | Checks the source keeps its promises. Needs bash and macOS `sips`. |
| `deploy.sh` | Uploads `src/` and invalidates the CloudFront cache. |

## Requirements

AWS CLI v2, authenticated against the account that owns the domain. Node.js 22 or newer
is needed only for `infra/`, and is not required to deploy the site.

`test.sh` needs bash and, for the icon dimension check, macOS `sips`. It does not run
unmodified on Linux.

## Checking the source

```sh
./test.sh
```

Asserts that the page has one `<h1>`, both profile links, the exact role line, a visible
keyboard focus style, and no `<script>` tag or third-party origin. Run it before deploying.

## Deploying

```sh
./deploy.sh
```

Syncs `src/` to S3, creates a `/*` CloudFront invalidation, and waits for it to complete.
The bucket name and distribution ID come from the `MylesShannonSite` stack outputs, so
there is nothing to keep in sync by hand. Override with `SITE_BUCKET`,
`SITE_DISTRIBUTION`, or `SITE_STACK` if you need to.

Every file is uploaded `no-cache, must-revalidate`. Filenames are not content-hashed, so a
long `max-age` would leave returning visitors on stale CSS that an invalidation cannot
clear.

## Changing infrastructure

```sh
cd infra
npm install
npm run type-check
npx cdk diff
npx cdk deploy
```

`www.mylesshannon.com` 301s to the apex via a CloudFront viewer-request function. Requests
for missing paths return a real 404 rather than a 200. Access logs land in
`myles-com-logs` and expire after a year; delivery lags by up to an hour.
