# SignalFx CollectD installer

The installer/configurator for collectd

curl -sSL https://dl.signalfx.com/collectd-install | bash -s YOUR_API_TOKEN

You can go non-interactive with

curl -sSL https://dl.signalfx.com/collectd-install | bash -s YOUR_API_TOKEN -y

You can provide your own collectd and just use the script to configure it with.  If it's not in a standard location for collectd you'll want to pass in -C /path/to/collectd in addition.

curl -sSL https://dl.signalfx.com/collectd-install | bash -s YOUR_API_TOKEN --configure-only -C /path/to/collectd

Full usage options available:

```
Usage: collectd-install [ <api_token> ] [ --beta | --test ] [ -H <hostname> ] [ -U <Ingest URL>] [ -h ] [ --insecure ] [ -y ] [ --configure-only ] [ -C /path/to/collectd ]
 -y makes the operation non-interactive. api_token is required and defaults to dns if no hostname is set
 -H <hostname> will set the collectd hostname to <hostname> instead of deferring to dns.
 -U <Ingest URL> will be used as the ingest url. Defaults to https://ingest.signalfx.com
 -C /path/to/collectd to use that collectd, this will still install the plugin if it is not already installed.
 --beta will use the beta repos instead of release.
 --test will use the test repos instead of release.
 --configure-only will use the installed collectd instead of attempting to install and will not install anything new.
 --insecure will use the insecure -k with any curl fetches.
 --skip-time-sync-check will skip check for whether the system time is synchronized.
 -h this page.
 ```

 ##### Note: Uninstalling from Mac OS X systems

 When the install script installs the SignalFx collectd agent on a Mac OS X system, an `uninstall.sh` script is laid down in the directory `/usr/local/share/collectd`. Run this script with administrative privileges to remove collectd and all related configuration from the host. Run the script with `–help` option for detailed instructions, including how to perform a dry run and keep configuration in place after uninstalling.
