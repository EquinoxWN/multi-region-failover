#!/bin/sh
# Download the pinned Terraform release into .tmp/bin once, verify it against HashiCorp's
# published SHA-256 sums, and print the binary's path.
set -eu
VERSION=1.17.1
os=$(uname -s | tr '[:upper:]' '[:lower:]')
arch=$(uname -m)
case "$arch" in
  x86_64 | amd64) arch=amd64 ;;
  aarch64 | arm64) arch=arm64 ;;
esac
exe=terraform
case "$os" in
  mingw* | msys* | cygwin*) os=windows exe=terraform.exe ;;
esac
dir=.tmp/bin
mkdir -p "$dir"
if [ ! -x "$dir/$exe" ]; then
  zip="terraform_${VERSION}_${os}_${arch}.zip"
  # Bounded: 3 retries with curl's growing back-off, 15 s to connect, 5 minutes per file.
  get="curl -fsSL --retry 3 --connect-timeout 15 --max-time 300"
  $get -o "$dir/$zip" "https://releases.hashicorp.com/terraform/${VERSION}/${zip}"
  $get -o "$dir/SHA256SUMS" "https://releases.hashicorp.com/terraform/${VERSION}/terraform_${VERSION}_SHA256SUMS"
  (cd "$dir" && grep " ${zip}\$" SHA256SUMS | sha256sum -c - >&2)
  # Extract next to the target and rename, so an interrupted run never leaves a half-written binary.
  (cd "$dir" && rm -rf unpack && unzip -q "$zip" "$exe" -d unpack && mv -f "unpack/$exe" "$exe" && rm -rf unpack "$zip")
fi
echo "$dir/$exe"
