#!/usr/bin/env bash
#
# Assertions about the published source. Guards the promises the design makes, which are
# otherwise invisible: exactly two outbound links, nothing loaded from a third party, no
# client-side JavaScript, and the accessibility affordances.
#
# Needs bash. The icon dimension check also needs macOS sips.

set -uo pipefail

HTML=src/index.html
CSS=src/styles.css

# Every host the design permits. Anything else is a third-party request, which is the one
# thing this page must never make.
ALLOWED_HOSTS='github\.com|www\.linkedin\.com|mylesshannon\.com'

fails=0

# Passes when the command succeeds.
check() {
	local desc=$1
	shift
	if "$@" >/dev/null 2>&1; then
		printf 'ok   %s\n' "$desc"
	else
		printf 'FAIL %s\n' "$desc"
		fails=$((fails + 1))
	fi
}

# Passes when the command fails, for asserting an absence.
refute() {
	local desc=$1
	shift
	if "$@" >/dev/null 2>&1; then
		printf 'FAIL %s\n' "$desc"
		fails=$((fails + 1))
	else
		printf 'ok   %s\n' "$desc"
	fi
}

# Counts occurrences, not matching lines. The `|| true` keeps a zero count from failing
# the pipeline under pipefail, so this stays correct if set -e is ever added.
count() {
	{ grep -oiE "$1" "$2" 2>/dev/null || true; } | wc -l | tr -d ' '
}

# Reads the two dimension lines by name rather than scraping digits, so a path
# containing a number cannot corrupt the result.
icon_alpha() {
	sips -g hasAlpha src/apple-touch-icon.png 2>/dev/null \
		| awk '/hasAlpha/ { print $2 }'
}

icon_dims() {
	sips -g pixelWidth -g pixelHeight src/apple-touch-icon.png 2>/dev/null \
		| awk '/pixelWidth|pixelHeight/ { print $2 }' \
		| tr '\n' 'x' | sed 's/x$//'
}

# Every host the source references, normalised the way a browser resolves one. Scans the
# stylesheet too, because @import and url() can pull in a remote font.
#
# Protocol-relative URLs (//host/path) are included. The browser supplies the page's own
# scheme and fetches them, so requiring "https?:" would wave a third party straight
# through the allowlist.
#
# xmlns declarations are removed first, in both quoting styles. An XML namespace is an
# identifier that resembles a URL but is never fetched, so treating www.w3.org as an
# origin would be a false positive that teaches people to ignore this check.
#
# Userinfo is discarded the way a browser discards it: in https://github.com@evil.com/ the
# host is evil.com, so a trusted name before the @ cannot smuggle an untrusted host past
# an allowlist that only looked at the first name it saw.
referenced_hosts() {
	{ cat "$HTML" "$CSS" 2>/dev/null || true; } \
		| sed -E 's/xmlns(:[a-zA-Z0-9]+)?="[^"]*"//g' \
		| sed -E "s/xmlns(:[a-zA-Z0-9]+)?='[^']*'//g" \
		| { grep -oiE "(https?:)?//[^\"'[:space:]>)]+" || true; } \
		| sed -E 's#^([Hh][Tt][Tt][Pp][Ss]?:)?//##' \
		| sed -E 's#[/?].*$##' \
		| sed -E 's#^.*@##' \
		| sed -E 's#:[0-9]+$##' \
		| tr '[:upper:]' '[:lower:]' \
		| { grep -v '^$' || true; } \
		| sort -u
}

# An allowlist, not a denylist: an unrecognised CDN fails even though no rule names it.
unexpected_hosts() {
	referenced_hosts | { grep -vxE "$ALLOWED_HOSTS" || true; }
}

# The stylesheet with comments removed, so a commented-out declaration cannot satisfy a
# check. Newlines are flattened first because sed is line-oriented and these comments
# span lines.
CSS_CODE=$(mktemp)
trap 'rm -f "$CSS_CODE"' EXIT
{ cat "$CSS" 2>/dev/null || true; } \
	| tr '\n' ' ' \
	| sed -E 's#/\*([^*]|\*+[^*/])*\*+/# #g' > "$CSS_CODE"

# Readability is asserted separately from existence: the scanning helpers redirect their
# own errors away, so an existing-but-unreadable file would otherwise be silently skipped.
check "index.html exists" test -f "$HTML"
check "index.html is readable" test -r "$HTML"
check "styles.css exists" test -f "$CSS"
check "favicon exists" test -f src/favicon.svg
check "touch icon exists" test -f src/apple-touch-icon.png
check "touch icon is 180px square" test "$(icon_dims)" = "180x180"
# The favicon is transparent so the mark floats on the browser tab strip, but iOS
# composites the home screen icon onto its own background and renders a transparent one
# badly. Only the PNG must be opaque, so that asymmetry is worth asserting.
check "touch icon is opaque" test "$(icon_alpha)" = "no"
check "styles.css is readable" test -r "$CSS"

check "declares english" grep -q '<html lang="en"' "$HTML"
check "declares utf-8" grep -qE 'charset="?utf-8' "$HTML"
check "has viewport meta" grep -q 'name="viewport"' "$HTML"
check "has exactly one h1" test "$(count '<h1' "$HTML")" = 1
# Matches <a>, <A, and a tag broken across lines, not only the literal "<a ".
check "has exactly two links" test "$(count '<a([[:space:]>]|$)' "$HTML")" = 2
check "links to github profile" grep -qE 'href="https://github\.com/MylesShannon"' "$HTML"
check "links to linkedin profile" grep -qE 'href="https://www\.linkedin\.com/in/myles-shannon-27304680/"' "$HTML"
# Anchored on the tags so a longer title cannot satisfy an "exact" requirement.
check "role line is exact" grep -qE '>Software Engineer at NVIDIA<' "$HTML"
check "declares canonical url" grep -q 'rel="canonical"' "$HTML"

# The leading guard stops this matching inside `prefers-color-scheme: dark`, which would
# otherwise let the page pass without ever declaring a scheme. The trailing guard rejects
# `color-scheme: dark light`, which would reintroduce the light variant the design drops.
check "declares dark scheme" grep -qE '(^|[^-[:alnum:]])color-scheme:[[:space:]]*dark[[:space:]]*([;}]|$)' "$CSS_CODE"
check "styles keyboard focus" grep -q ':focus-visible' "$CSS_CODE"
check "respects reduced motion" grep -q 'prefers-reduced-motion' "$CSS_CODE"

# The design's central promise, checked two complementary ways. The allowlist catches any
# remote origin, named or not. The refutes below catch libraries vendored as relative
# paths, which have no host for the allowlist to see -- exactly how the legacy page
# loaded jQuery and Font Awesome.
unexpected=$(unexpected_hosts)
check "no third-party origins" test -z "$unexpected"
if [ -n "$unexpected" ]; then
	printf '     unexpected hosts: %s\n' "$(echo "$unexpected" | tr '\n' ' ')"
fi

refute "no google fonts" grep -qE 'fonts\.(googleapis|gstatic)\.com' "$HTML" "$CSS"
refute "no font awesome" grep -qiE 'font-?awesome' "$HTML" "$CSS"
refute "no jquery" grep -qi 'jquery' "$HTML" "$CSS"
refute "no analytics" grep -qiE 'google-analytics|googletagmanager' "$HTML" "$CSS"
refute "no hotlinked s3 assets" grep -qE 's3\.amazonaws\.com' "$HTML" "$CSS"

# No client-side JavaScript, by any of the three routes it can enter a page.
refute "no script tags" grep -qi '<script' "$HTML"
refute "no javascript urls" grep -qi 'javascript:' "$HTML"
refute "no inline event handlers" grep -qiE '[[:space:]]on[a-z]+[[:space:]]*=' "$HTML"

# Removed content that must not come back.
refute "no twitter or facebook links" grep -qiE 'twitter\.com|facebook\.com' "$HTML"
refute "no mailto link" grep -q 'mailto:' "$HTML"
refute "no resume link" grep -qiE 'resume|résumé' "$HTML"

printf '\n'
if [ "$fails" -gt 0 ]; then
	printf '%d check(s) failed\n' "$fails"
	exit 1
fi
printf 'all checks passed\n'
