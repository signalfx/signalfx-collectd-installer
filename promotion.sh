#!/bin/sh

aws s3 cp s3://public-downloads--signalfuse-com/collectd-install-test s3://public-downloads--signalfuse-com/collectd-install --cache-control="max-age=0, no-cache"
aws s3 cp s3://public-downloads--signalfuse-com/install-files-test.tgz s3://public-downloads--signalfuse-com/install-files.tgz --cache-control="max-age=0, no-cache"
