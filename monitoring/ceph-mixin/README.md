## Ceph mixin

The ceph-mixin generates both grafana dashboards and alerts with Jsonnet.
You can find all the generated files in the `output` directory and you can
run `tox -egrafonnet-fix` to re-generate them.

The ceph-mixin depends on some Jsonnet third party libraries located in the
`vendor` directory. To update those libraries you will have to install
[jsonnet-bundler](https://github.com/jsonnet-bundler/jsonnet-bundler) and run
the command `jb update`.

### Grafana dashboards for Ceph

Here you can find a collection of [Grafana](https://grafana.com/grafana)
dashboards for Ceph Monitoring. These dashboards are based on metrics collected
from [prometheus](https://prometheus.io/) scraping the [prometheus mgr
plugin](http://docs.ceph.com/en/latest/mgr/prometheus/) and the
[node_exporter](https://github.com/prometheus/node_exporter).

#### Other requirements

- Luminous 12.2.5 or newer
- [Status Panel](https://grafana.com/plugins/vonage-status-panel) installed
- node_exporter 0.15.x and 0.16.x are supported (host details and hosts
overview dashboards)

### Prometheus related bits

#### Alerts
In `monitoring/ceph-mixin/output/alerts.yaml` you'll find a set of Prometheus
alert rules that should provide a decent set of default alerts for a
Ceph cluster. Just put this file in a place according to your Prometheus
configuration (wherever the `rules` configuration stanza points).

#### SNMP
Ceph provides a MIB (CEPH-PROMETHEUS-ALERT-MIB.txt) to support sending Prometheus
alerts through to an SNMP management platform. The translation from Prometheus
alert to SNMP trap requires the Prometheus alert to contain an OID that maps to
a definition within the MIB. When making changes to the Prometheus alert rules
file, developers should include any necessary changes to the MIB.
