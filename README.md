# SignalFx CollectD installer

The installer/configurator for collectd

curl -sSL https://dl.signalfx.com/collectd-install | bash -s YOUR_API_TOKEN

You can go non-interactive with

curl -sSL https://dl.signalfx.com/collectd-install | bash -s YOUR_API_TOKEN -y

You can provide your own collectd and just use the script to configure it with

curl -sSL https://dl.signalfx.com/collectd-install | bash -s YOUR_API_TOKEN --configure-only

Full usage options available:

Usage: collectd-install [ <api_token> ] [ --beta | --test ] [ -H <hostname> ] [ -U <Ingest URL>] [ -h ] [ --insecure ] [ -y ] [ --config-only ] [ -C /path/to/collectd ]
 -y makes the operation non-interactive. api_token is required and defaults to dns if no hostname is set
 -H <hostname> will set the collectd hostname to <hostname> instead of deferring to dns.
 -U <Ingest URL> will be used as the ingest url. Defaults to https://ingest.signalfx.com
 -C /path/to/collectd to use that collectd, this will still install the plugin if it is not already installed.
 --beta will use the beta repos instead of release.
 --test will use the test repos instead of release.
 --configure-only will use the installed collectd instead of attempting to install and will not install anything new.
 --insecure will use the insecure -k with any curl fetches.
 -h this page.
