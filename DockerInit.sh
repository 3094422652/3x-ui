#!/bin/sh
set -e

curl_retry() {
    curl --retry 5 --retry-all-errors --retry-delay 3 --connect-timeout 15 "$@"
}

case $1 in
    amd64)
        ARCH="64"
        FNAME="amd64"
        MTGARCH="amd64"
        MTGFNAME="amd64"
        ;;
    i386 | 386)
        ARCH="32"
        FNAME="386"
        MTGARCH="386"
        MTGFNAME="386"
        ;;
    armv8 | arm64 | aarch64)
        ARCH="arm64-v8a"
        FNAME="arm64"
        MTGARCH="arm64"
        MTGFNAME="arm64"
        ;;
    armv7 | arm | arm32)
        ARCH="arm32-v7a"
        FNAME="arm32"
        MTGARCH="armv7"
        MTGFNAME="arm"
        ;;
    armv6)
        ARCH="arm32-v6"
        FNAME="arm32"
        MTGARCH="armv6"
        MTGFNAME="arm"
        ;;
    *)
        ARCH="64"
        FNAME="amd64"
        MTGARCH="amd64"
        MTGFNAME="amd64"
        ;;
esac

MTG_MULTI_VER=$(curl_retry -sf -o /dev/null -w '%{redirect_url}' "https://github.com/mhsanaei/mtg-multi/releases/latest" | sed -n 's#.*/releases/tag/##p')
if [ -z "$MTG_MULTI_VER" ]; then
    MTG_MULTI_VER=$(curl_retry -sfL "https://api.github.com/repos/mhsanaei/mtg-multi/releases/latest" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n 1)
fi
if [ -z "$MTG_MULTI_VER" ]; then
    echo "DockerInit: could not resolve the latest mtg-multi release tag" >&2
    exit 1
fi

mkdir -p build/bin
cd build/bin
curl_retry -sfLRO "https://github.com/XTLS/Xray-core/releases/download/v26.10.21/Xray-linux-${ARCH}.zip"
unzip "Xray-linux-${ARCH}.zip"
rm -f "Xray-linux-${ARCH}.zip" geoip.dat geosite.dat
mv xray "xray-linux-${FNAME}"
chmod +x "xray-linux-${FNAME}"

# mtg-multi (MTProto sidecar) ships prebuilt release binaries for every target
# we package, so download and unpack the matching one instead of compiling.
MTG_PKG="mtg-multi-${MTG_MULTI_VER#v}-linux-${MTGARCH}"
curl_retry -sfLRO "https://github.com/mhsanaei/mtg-multi/releases/download/${MTG_MULTI_VER}/${MTG_PKG}.tar.gz"
tar -xzf "${MTG_PKG}.tar.gz"
mv "${MTG_PKG}/mtg-multi" "mtg-linux-${MTGFNAME}"
rm -rf "${MTG_PKG}" "${MTG_PKG}.tar.gz"
chmod +x "mtg-linux-${MTGFNAME}"

curl_retry -sfLRO https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat
curl_retry -sfLRO https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat
curl_retry -sfLRo geoip_IR.dat https://github.com/chocolate4u/Iran-v2ray-rules/releases/latest/download/geoip.dat
curl_retry -sfLRo geosite_IR.dat https://github.com/chocolate4u/Iran-v2ray-rules/releases/latest/download/geosite.dat
curl_retry -sfLRo geoip_RU.dat https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/geoip.dat
curl_retry -sfLRo geosite_RU.dat https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/geosite.dat
cd ../../
