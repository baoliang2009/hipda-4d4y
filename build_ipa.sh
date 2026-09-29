#!/usr/bin/env bash
# 导出 IPA，供自签工具（Esign / Sideloadly / 巨魔 TrollStore 等）重签后安装。
#
# 关键点：archive 时用 CODE_SIGNING_ALLOWED=NO 出「未签名」IPA。
# 本机没有 Apple Distribution 证书，也没有任何描述文件，走 exportArchive
# 的 development/ad-hoc 方式都会因为缺 profile 失败；而最终安装时由自签工具
# 用自己的证书重新签名，所以构建期签名本来就不需要。
#
# 用法: ./build_ipa.sh    产物: build/FourD4Y.ipa
set -euo pipefail
cd "$(dirname "$0")"

# xcode-select 可能指向 CommandLineTools，xcodebuild 必须用完整 Xcode。
# 用 DEVELOPER_DIR 覆盖即可，无需 sudo 改 xcode-select。
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

ARCHIVE="build/FourD4Y.xcarchive"
APP="$ARCHIVE/Products/Applications/FourD4Y.app"
IPA="build/FourD4Y.ipa"

xcodegen generate

rm -rf "$ARCHIVE" build/Payload "$IPA"

xcodebuild archive \
  -project FourD4Y.xcodeproj \
  -scheme FourD4Y \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath "$ARCHIVE" \
  CODE_SIGNING_ALLOWED=NO

mkdir -p build/Payload
cp -R "$APP" build/Payload/
rm -f "$IPA"
(cd build && zip -qry "$(basename "$IPA")" Payload)
rm -rf build/Payload

echo "OK: $(pwd)/$IPA"
