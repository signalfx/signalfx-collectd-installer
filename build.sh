#!/bin/sh

set -ex

cd $(dirname $0)

rm -rf collectd.conf.tmpl *.conf install-files.tgz

for x in collectd-signalfx/10-signalfx.conf collectd-write_http/10-write_http-plugin.conf collectd-aggregation/10-aggregation-cpu.conf collectd/collectd.conf.tmpl collectd-match_regex/filtering.conf; do
	curl -sSL "https://raw.githubusercontent.com/signalfx/integrations/master/${x}" > `basename $x`
done

tar -cvzf install-files.tgz *.conf collectd.conf.tmpl get_aws_unique_id

if ! [ -z $BUILD_PUBLISH ] && [ $BUILD_PUBLISH = True ]; then
	aws s3 cp install.sh s3://public-downloads--signalfuse-com/collectd-install-test --cache-control="max-age=0, no-cache"
	aws s3 cp install-files.tgz s3://public-downloads--signalfuse-com/install-files-test.tgz --cache-control="max-age=0, no-cache"
fi
