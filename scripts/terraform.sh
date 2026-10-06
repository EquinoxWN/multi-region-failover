#!/bin/sh
# Download the pinned Terraform release into .tmp/bin once, verify it against HashiCorp's
# published SHA-256 sums, and print the binary's path.
set -eu
VERSION=1.16.5
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
  curl -fsSLo "$dir/$zip" "https://releases.hashicorp.com/terraform/${VERSION}/${zip}"
  curl -fsSLo "$dir/SHA256SUMS" "https://releases.hashicorp.com/terraform/${VERSION}/terraform_${VERSION}_SHA256SUMS"
  (cd "$dir" && grep " ${zip}\$" SHA256SUMS | sha256sum -c - >&2)
  (cd "$dir" && unzip -o -q "$zip" "$exe" && rm -f "$zip")
fi
echo "$dir/$exe"
