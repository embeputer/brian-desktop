#!/bin/bash
# Publish Brian.dmg and a one-item appcast.json for the tag that triggered this run.
# One tag is one version. Pull requests and branch pushes must not run this script.

set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

event="${GITHUB_EVENT_NAME:-}"
ref="${GITHUB_REF:-}"
tag="${GITHUB_REF_NAME:-}"
repo="${GITHUB_REPOSITORY:-}"

if [[ "$event" != "push" ]]; then
	echo "A GitHub release is created only for a tag push, not for ${event:-an unset event}." >&2
	exit 1
fi
if [[ "$ref" != refs/tags/v* ]]; then
	echo "Ref ${ref:-unset} is not a v* tag. Branch pushes upload the disk image and do not publish a release." >&2
	exit 1
fi
if [[ -z "$tag" || "$ref" != "refs/tags/${tag}" ]]; then
	echo "GITHUB_REF does not match GITHUB_REF_NAME." >&2
	exit 1
fi
if [[ -z "$repo" ]]; then
	echo "GITHUB_REPOSITORY is required." >&2
	exit 1
fi

plist="$root/Brian.app/Contents/Info.plist"
dmg="$root/Brian.dmg"
if [[ ! -f "$plist" ]]; then
	echo "Brian.app/Contents/Info.plist is missing. Run ./Scripts/package-dmg.sh first." >&2
	exit 1
fi
if [[ ! -f "$dmg" ]]; then
	echo "Brian.dmg is missing. Run ./Scripts/package-dmg.sh first." >&2
	exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
	echo "python3 is required to write appcast.json." >&2
	exit 1
fi
if [[ -z "${BRIAN_UPDATE_SIGNING_KEY:-}" ]]; then
	echo "BRIAN_UPDATE_SIGNING_KEY is required. The app installs only updates signed with the release key." >&2
	exit 1
fi

work="$(mktemp -d)"
notes_file="$work/release-notes.txt"
response_file="$work/generate-notes.json"
appcast="$work/appcast.json"
signing_key="$work/update-signing-key.pem"
app_key_source="$root/Sources/BrianClient/UpdateSigning.swift"
cleanup() {
	rm -rf "$work"
}
trap cleanup EXIT
(umask 077 && printf '%s\n' "$BRIAN_UPDATE_SIGNING_KEY" >"$signing_key")

# Validate the tag against the built app before talking to GitHub.
python3 "$root/Scripts/write-appcast.py" \
	--plist "$plist" \
	--dmg "$dmg" \
	--tag "$tag" \
	--repo "$repo" \
	--signing-key "$signing_key" \
	--app-key-source "$app_key_source" \
	--output "$appcast"

if [[ -z "${GH_TOKEN:-}" ]]; then
	echo "GH_TOKEN is required to publish the release." >&2
	exit 1
fi
if ! command -v gh >/dev/null 2>&1; then
	echo "gh is required to publish the release." >&2
	exit 1
fi

notes_ready=0
if gh api \
	--method POST \
	-H "Accept: application/vnd.github+json" \
	"/repos/${repo}/releases/generate-notes" \
	-f "tag_name=${tag}" >"$response_file" \
	&& python3 "$root/Scripts/write-appcast.py" --print-notes-from-github-json "$response_file" >"$notes_file"
then
	notes_ready=1
fi
if [[ "$notes_ready" -eq 1 ]]; then
	python3 "$root/Scripts/write-appcast.py" \
		--plist "$plist" \
		--dmg "$dmg" \
		--tag "$tag" \
		--repo "$repo" \
		--notes-file "$notes_file" \
		--signing-key "$signing_key" \
		--app-key-source "$app_key_source" \
		--output "$appcast"
else
	printf 'Brian %s\n' "${tag#v}" >"$notes_file"
fi

if gh release view "$tag" --repo "$repo" >/dev/null 2>&1; then
	gh release upload "$tag" "$dmg" "$appcast" --repo "$repo" --clobber
	gh release edit "$tag" --repo "$repo" --latest --draft=false --notes-file "$notes_file"
else
	gh release create "$tag" \
		"$dmg" \
		"$appcast" \
		--repo "$repo" \
		--title "$tag" \
		--notes-file "$notes_file" \
		--latest \
		--verify-tag
fi

echo "Published $tag with Brian.dmg and appcast.json"
