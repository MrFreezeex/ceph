{
  prometheusAlerts+:: {
    groups+: [
      {
        name: 'cluster health',
        rules: [
          {
            alert: 'CephHealthError',
            expr: 'ceph_health_status == 2',
            'for': '5m',
            labels: {
              severity: 'critical',
              type: 'ceph_default',
              oid: '1.3.6.1.4.1.50495.1.2.1.2.1',
            },
            annotations: {
              summary: 'Cluster is in an ERROR state',
              description: 'Ceph in HEALTH_ERROR state for more than 5 minutes. Please check "ceph health detail" for more information.\n',
            },
          },
          {
            alert: 'CephHealthWarning',
            expr: 'ceph_health_status == 1',
            'for': '15m',
            labels: {
              severity: 'warning',
              type: 'ceph_default',
            },
            annotations: {
              summary: 'Cluster is in a WARNING state',
              description: 'Ceph has been in HEALTH_WARN for more than 15 minutes. Please check "ceph health detail" for more information.\n',
            },
          },
        ],
      },
      {
        name: 'mon',
        rules: [
          {
            alert: 'CephMonDownQuorumAtRisk',
            expr: '((ceph_health_detail{name="MON_DOWN"} == 1) * on() (count(ceph_mon_quorum_status == 1) == bool (floor(count(ceph_mon_metadata) / 2) + 1))) == 1',
            'for': '30s',
            labels: {
              severity: 'critical',
              type: 'ceph_default',
              oid: '1.3.6.1.4.1.50495.1.2.1.3.1',
            },
            annotations: {
              documentation: 'https://docs.ceph.com/en/latest/rados/operations/health-checks#mon-down',
              summary: 'Monitor quorum is at risk',
              description: '{{ $min := query "floor(count(ceph_mon_metadata) / 2) +1" | first | value }}Quorum requires a majority of monitors (x {{ $min }}) to be active\nWithout quorum the cluster will become inoperable, affecting all connected clients and services.\n\nThe following monitors are down:\n{{- range query "(ceph_mon_quorum_status == 0) + on(ceph_daemon) group_left(hostname) (ceph_mon_metadata * 0)" }}\n  - {{ .Labels.ceph_daemon }} on {{ .Labels.hostname }}\n{{- end }}\n',
            },
          },
          {
            alert: 'CephMonDown',
            expr: '(count(ceph_mon_quorum_status == 0) <= (count(ceph_mon_metadata) - floor(count(ceph_mon_metadata) / 2) + 1))',
            'for': '30s',
            labels: {
              severity: 'warning',
              type: 'ceph_default',
            },
            annotations: {
              documentation: 'https://docs.ceph.com/en/latest/rados/operations/health-checks#mon-down',
              summary: 'One of more ceph monitors are down',
              description: '{{ $down := query "count(ceph_mon_quorum_status == 0)" | first | value }}{{ $s := "" }}{{ if gt $down 1.0 }}{{ $s = "s" }}{{ end }}You have {{ $down }} monitor{{ $s }} down.\nQuorum is still intact, but the loss of further monitors will make your cluster inoperable.\n\nThe following monitors are down:\n{{- range query "(ceph_mon_quorum_status == 0) + on(ceph_daemon) group_left(hostname) (ceph_mon_metadata * 0)" }}\n  - {{ .Labels.ceph_daemon }} on {{ .Labels.hostname }}\n{{- end }}\n',
            },
          },
          {
            alert: 'CephMonDiskspaceCritical',
            expr: 'ceph_health_detail{name="MON_DISK_CRIT"} == 1',
            'for': '1m',
            labels: {
              severity: 'critical',
              type: 'ceph_default',
              oid: '1.3.6.1.4.1.50495.1.2.1.3.2',
            },
            annotations: {
              documentation: 'https://docs.ceph.com/en/latest/rados/operations/health-checks#mon-disk-crit',
              summary: 'Disk space on at least one monitor is critically low',
              description: "The free space available to a monitor's store is critically low (<5% by default).\nYou should increase the space available to the monitor(s). The\ndefault location for the store sits under /var/lib/ceph. Your monitor hosts are;\n{{- range query \"ceph_mon_metadata\"}}\n  - {{ .Labels.hostname }}\n{{- end }}\n",
            },
          },
          {
            alert: 'CephMonDiskspaceLow',
            expr: 'ceph_health_detail{name="MON_DISK_LOW"} == 1',
            'for': '5m',
            labels: {
              severity: 'warning',
              type: 'ceph_default',
            },
            annotations: {
              documentation: 'https://docs.ceph.com/en/latest/rados/operations/health-checks#mon-disk-low',
              summary: 'Disk space on at least one monitor is approaching full',
              description: "The space available to a monitor's store is approaching full (>70% is the default).\nYou should increase the space available to the monitor store. The\ndefault location for the store sits under /var/lib/ceph. Your monitor hosts are;\n{{- range query \"ceph_mon_metadata\"}}\n  - {{ .Labels.hostname }}\n{{- end }}\n",
            },
          },
          {
            alert: 'CephMonClockSkew',
            expr: 'ceph_health_detail{name="MON_CLOCK_SKEW"} == 1',
            'for': '1m',
            labels: {
              severity: 'warning',
              type: 'ceph_default',
            },
            annotations: {
              documentation: 'https://docs.ceph.com/en/latest/rados/operations/health-checks#mon-clock-skew',
              summary: 'Clock skew across the Monitor hosts detected',
              description: "The ceph monitors rely on a consistent time reference to maintain\nquorum and cluster consistency. This event indicates that at least\none of your mons is not sync'd correctly.\n\nReview the cluster status with ceph -s. This will show which monitors\nare affected. Check the time sync status on each monitor host.\n",
            },
          },
        ],
      },
      {
        name: 'osd',
        rules: [
          {
            alert: 'CephOSDDownHigh',
            expr: 'count(ceph_osd_up == 0) / count(ceph_osd_up) * 100 >= 10',
            labels: {
              severity: 'critical',
              type: 'ceph_default',
              oid: '1.3.6.1.4.1.50495.1.2.1.4.1',
            },
            annotations: {
              summary: 'More than 10% of OSDs are down',
              description: '{{ $value | humanize }}% or {{ with query "count(ceph_osd_up == 0)" }}{{ . | first | value }}{{ end }} of {{ with query "count(ceph_osd_up)" }}{{ . | first | value }}{{ end }} OSDs are down (>= 10%).\n\nThe following OSDs are down:\n{{- range query "(ceph_osd_up * on(ceph_daemon) group_left(hostname) ceph_osd_metadata) == 0" }}\n  - {{ .Labels.ceph_daemon }} on {{ .Labels.hostname }}\n{{- end }}\n',
            },
          },
          {
            alert: 'CephOSDHostDown',
            expr: 'ceph_health_detail{name="OSD_HOST_DOWN"} == 1',
            'for': '5m',
            labels: {
              severity: 'warning',
              type: 'ceph_default',
              oid: '1.3.6.1.4.1.50495.1.2.1.4.8',
            },
            annotations: {
              summary: 'An OSD host is offline',
              description: 'The following OSDs are down:\n{{- range query "(ceph_osd_up * on(ceph_daemon) group_left(hostname) ceph_osd_metadata) == 0" }}\n- {{ .Labels.hostname }} : {{ .Labels.ceph_daemon }}\n{{- end }}\n',
            },
          },
          {
            alert: 'CephOSDDown',
            expr: 'ceph_health_detail{name="OSD_DOWN"} == 1',
            'for': '5m',
            labels: {
              severity: 'warning',
              type: 'ceph_default',
              oid: '1.3.6.1.4.1.50495.1.2.1.4.2',
            },
            annotations: {
              documentation: 'https://docs.ceph.com/en/latest/rados/operations/health-checks#osd-down',
              summary: 'An OSD has been marked down/unavailable',
              description: '{{ $num := query "count(ceph_osd_up == 0)" | first | value }}{{ $s := "" }}{{ if gt $num 1.0 }}{{ $s = "s" }}{{ end }}{{ $num }} OSD{{ $s }} down for over 5mins.\n\nThe following OSD{{ $s }} {{ if eq $s "" }}is{{ else }}are{{ end }} down:\n  {{- range query "(ceph_osd_up * on(ceph_daemon) group_left(hostname) ceph_osd_metadata) == 0"}}\n  - {{ .Labels.ceph_daemon }} on {{ .Labels.hostname }}\n  {{- end }}\n',
            },
          },
          {
            alert: 'CephOSDNearFull',
            expr: 'ceph_health_detail{name="OSD_NEARFULL"} == 1',
            'for': '5m',
            labels: {
              severity: 'warning',
              type: 'ceph_default',
              oid: '1.3.6.1.4.1.50495.1.2.1.4.3',
            },
            annotations: {
              documentation: 'https://docs.ceph.com/en/latest/rados/operations/health-checks#osd-nearfull',
              summary: 'OSD(s) running low on free space (NEARFULL)',
              description: "One or more OSDs have reached their NEARFULL threshold\n\nUse 'ceph health detail' to identify which OSDs have reached this threshold.\nTo resolve, either add capacity to the cluster, or delete unwanted data\n",
            },
          },
          {
            alert: 'CephOSDFull',
            expr: 'ceph_health_detail{name="OSD_FULL"} > 0',
            'for': '1m',
            labels: {
              severity: 'critical',
              type: 'ceph_default',
              oid: '1.3.6.1.4.1.50495.1.2.1.4.6',
            },
            annotations: {
              documentation: 'https://docs.ceph.com/en/latest/rados/operations/health-checks#osd-full',
              summary: 'OSD(s) is full, writes blocked',
              description: "An OSD has reached it's full threshold. Writes from all pools that share the\naffected OSD will be blocked.\n\nTo resolve, either add capacity to the cluster, or delete unwanted data\n",
            },
          },
          {
            alert: 'CephOSDBackfillFull',
            expr: 'ceph_health_detail{name="OSD_BACKFILLFULL"} > 0',
            'for': '1m',
            labels: {
              severity: 'warning',
              type: 'ceph_default',
            },
            annotations: {
              documentation: 'https://docs.ceph.com/en/latest/rados/operations/health-checks#osd-backfillfull',
              summary: 'OSD(s) too full for backfill operations',
              description: "An OSD has reached it's BACKFILL FULL threshold. This will prevent rebalance operations\ncompleting for some pools. Check the current capacity utilisation with 'ceph df'\n\nTo resolve, either add capacity to the cluster, or delete unwanted data\n",
            },
          },
          {
            alert: 'CephOSDTooManyRepairs',
            expr: 'ceph_health_detail{name="OSD_TOO_MANY_REPAIRS"} == 1',
            'for': '30s',
            labels: {
              severity: 'warning',
              type: 'ceph_default',
            },
            annotations: {
              documentation: 'https://docs.ceph.com/en/latest/rados/operations/health-checks#osd-too-many-repairs',
              summary: 'OSD has hit a high number of read errors',
              description: 'Reads from an OSD have used a secondary PG to return data to the client, indicating\na potential failing disk.\n',
            },
          },
          {
            alert: 'CephOSDTimeoutsPublicNetwork',
            expr: 'ceph_health_detail{name="OSD_SLOW_PING_TIME_FRONT"} == 1',
            'for': '1m',
            labels: {
              severity: 'warning',
              type: 'ceph_default',
            },
            annotations: {
              summary: 'Network issues delaying OSD heartbeats (public network)',
              description: "OSD heartbeats on the cluster's 'public' network (frontend) are running slow. Investigate the network\nfor any latency issues on this subnet. Use 'ceph health detail' to show the affected OSDs.\n",
            },
          },
          {
            alert: 'CephOSDTimeoutsClusterNetwork',
            expr: 'ceph_health_detail{name="OSD_SLOW_PING_TIME_BACK"} == 1',
            'for': '1m',
            labels: {
              severity: 'warning',
              type: 'ceph_default',
            },
            annotations: {
              summary: 'Network issues delaying OSD heartbeats (cluster network)',
              description: "OSD heartbeats on the cluster's 'cluster' network (backend) are running slow. Investigate the network\nfor any latency issues on this subnet. Use 'ceph health detail' to show the affected OSDs.\n",
            },
          },
          {
            alert: 'CephOSDInternalDiskSizeMismatch',
            expr: 'ceph_health_detail{name="BLUESTORE_DISK_SIZE_MISMATCH"} == 1',
            'for': '1m',
            labels: {
              severity: 'warning',
              type: 'ceph_default',
            },
            annotations: {
              documentation: 'https://docs.ceph.com/en/latest/rados/operations/health-checks#bluestore-disk-size-mismatch',
              summary: 'OSD size inconsistency error',
              description: "One or more OSDs have an internal inconsistency between the size of the physical device and it's metadata.\nThis could lead to the OSD(s) crashing in future. You should redeploy the effected OSDs.\n",
            },
          },
          {
            alert: 'CephDeviceFailurePredicted',
            expr: 'ceph_health_detail{name="DEVICE_HEALTH"} == 1',
            'for': '1m',
            labels: {
              severity: 'warning',
              type: 'ceph_default',
            },
            annotations: {
              documentation: 'https://docs.ceph.com/en/latest/rados/operations/health-checks#id2',
              summary: 'Device(s) have been predicted to fail soon',
              description: "The device health module has determined that one or more devices will fail\nsoon. To review the device states use 'ceph device ls'. To show a specific\ndevice use 'ceph device info <dev id>'.\n\nMark the OSD as out (so data may migrate to other OSDs in the cluster). Once\nthe osd is empty remove and replace the OSD.\n",
            },
          },
          {
            alert: 'CephDeviceFailurePredictionTooHigh',
            expr: 'ceph_health_detail{name="DEVICE_HEALTH_TOOMANY"} == 1',
            'for': '1m',
            labels: {
              severity: 'critical',
              type: 'ceph_default',
              oid: '1.3.6.1.4.1.50495.1.2.1.4.7',
            },
            annotations: {
              documentation: 'https://docs.ceph.com/en/latest/rados/operations/health-checks#device-health-toomany',
              summary: 'Too many devices have been predicted to fail, unable to resolve',
              description: "The device health module has determined that the number of devices predicted to\nfail can not be remediated automatically, since it would take too many osd's out of\nthe cluster, impacting performance and potentially availabililty. You should add new\nOSDs to the cluster to allow data to be relocated to avoid the data integrity issues.\n",
            },
          },
          {
            alert: 'CephDeviceFailureRelocationIncomplete',
            expr: 'ceph_health_detail{name="DEVICE_HEALTH_IN_USE"} == 1',
            'for': '1m',
            labels: {
              severity: 'warning',
              type: 'ceph_default',
            },
            annotations: {
              documentation: 'https://docs.ceph.com/en/latest/rados/operations/health-checks#device-health-in-use',
              summary: 'A device failure is predicted, but unable to relocate data',
              description: 'The device health module has determined that one or more devices will fail\nsoon, but the normal process of relocating the data on the device to other\nOSDs in the cluster is blocked.\n\nCheck the the cluster has available freespace. It may be necessary to add\nmore disks to the cluster to allow the data from the failing device to\nsuccessfully migrate.\n',
            },
          },
          {
            alert: 'CephOSDFlapping',
            expr: '(\n  rate(ceph_osd_up[5m])\n  * on(ceph_daemon) group_left(hostname) ceph_osd_metadata\n) * 60 > 1\n',
            labels: {
              severity: 'warning',
              type: 'ceph_default',
              oid: '1.3.6.1.4.1.50495.1.2.1.4.4',
            },
            annotations: {
              documentation: 'https://docs.ceph.com/en/latest/rados/troubleshooting/troubleshooting-osd#flapping-osds',
              summary: "Network issues are causing OSD's to flap (mark each other out)",
              description: 'OSD {{ $labels.ceph_daemon }} on {{ $labels.hostname }} was marked down and back up at {{ $value | humanize }} times once a minute for 5 minutes. This could indicate a network issue (latency, packet drop, disruption) on the clusters "cluster network". Check the network environment on the listed host(s).\n',
            },
          },
          {
            alert: 'CephOSDReadErrors',
            expr: 'ceph_health_detail{name="BLUESTORE_SPURIOUS_READ_ERRORS"} == 1',
            'for': '30s',
            labels: {
              severity: 'warning',
              type: 'ceph_default',
            },
            annotations: {
              documentation: 'https://docs.ceph.com/en/latest/rados/operations/health-checks#bluestore-spurious-read-errors',
              summary: 'Device read errors detected',
              description: 'An OSD has encountered read errors, but the OSD has recovered by retrying the reads. This may indicate an issue with the Hardware or Kernel.\n',
            },
          },
          {
            alert: 'CephPGImbalance',
            expr: 'abs(\n  (\n    (ceph_osd_numpg > 0) - on (job) group_left avg(ceph_osd_numpg > 0) by (job)\n  ) / on (job) group_left avg(ceph_osd_numpg > 0) by (job)\n) * on(ceph_daemon) group_left(hostname) ceph_osd_metadata > 0.30\n',
            'for': '5m',
            labels: {
              severity: 'warning',
              type: 'ceph_default',
              oid: '1.3.6.1.4.1.50495.1.2.1.4.5',
            },
            annotations: {
              summary: 'PG allocations are not balanced across devices',
              description: 'OSD {{ $labels.ceph_daemon }} on {{ $labels.hostname }} deviates by more than 30% from average PG count.\n',
            },
          },
        ],
      },
      {
        name: 'mds',
        rules: [
          {
            alert: 'CephFilesystemDamaged',
            expr: 'ceph_health_detail{name="MDS_DAMAGE"} > 0',
            'for': '1m',
            labels: {
              severity: 'critical',
              type: 'ceph_default',
              oid: '1.3.6.1.4.1.50495.1.2.1.5.1',
            },
            annotations: {
              documentation: 'https://docs.ceph.com/en/latest/cephfs/health-messages#cephfs-health-messages',
              summary: 'Ceph filesystem is damaged.',
              description: 'The filesystems metadata has been corrupted. Data access may be blocked.\nEither analyse the output from the mds daemon admin socket, or escalate to support\n',
            },
          },
          {
            alert: 'CephFilesystemOffline',
            expr: 'ceph_health_detail{name="MDS_ALL_DOWN"} > 0',
            'for': '1m',
            labels: {
              severity: 'critical',
              type: 'ceph_default',
              oid: '1.3.6.1.4.1.50495.1.2.1.5.3',
            },
            annotations: {
              documentation: 'https://docs.ceph.com/en/latest/cephfs/health-messages/#mds-all-down',
              summary: 'Ceph filesystem is offline',
              description: 'All MDS ranks are unavailable. The ceph daemons providing the metadata for the Ceph filesystem are all down, rendering the filesystem offline.\n',
            },
          },
          {
            alert: 'CephFilesystemDegraded',
            expr: 'ceph_health_detail{name="FS_DEGRADED"} > 0',
            'for': '1m',
            labels: {
              severity: 'critical',
              type: 'ceph_default',
              oid: '1.3.6.1.4.1.50495.1.2.1.5.4',
            },
            annotations: {
              documentation: 'https://docs.ceph.com/en/latest/cephfs/health-messages/#fs-degraded',
              summary: 'Ceph filesystem is degraded',
              description: 'One or more metdata daemons (MDS ranks) are failed or in a damaged state. At best the filesystem is partially available, worst case is the filesystem is completely unusable.\n',
            },
          },
          {
            alert: 'CephFilesystemMDSRanksLow',
            expr: 'ceph_health_detail{name="MDS_UP_LESS_THAN_MAX"} > 0',
            'for': '1m',
            labels: {
              severity: 'warning',
              type: 'ceph_default',
            },
            annotations: {
              documentation: 'https://docs.ceph.com/en/latest/cephfs/health-messages/#mds-up-less-than-max',
              summary: 'Ceph MDS daemon count is lower than configured',
              description: "The filesystem's \"max_mds\" setting defined the number of MDS ranks in the filesystem. The current number of active MDS daemons is less than this setting.\n",
            },
          },
          {
            alert: 'CephFilesystemInsufficientStandby',
            expr: 'ceph_health_detail{name="MDS_INSUFFICIENT_STANDBY"} > 0',
            'for': '1m',
            labels: {
              severity: 'warning',
              type: 'ceph_default',
            },
            annotations: {
              documentation: 'https://docs.ceph.com/en/latest/cephfs/health-messages/#mds-insufficient-standby',
              summary: 'Ceph filesystem standby daemons too low',
              description: 'The minimum number of standby daemons determined by standby_count_wanted is less than the actual number of standby daemons. Adjust the standby count or increase the number of mds daemons within the filesystem.\n',
            },
          },
          {
            alert: 'CephFilesystemFailureNoStandby',
            expr: 'ceph_health_detail{name="FS_WITH_FAILED_MDS"} > 0',
            'for': '1m',
            labels: {
              severity: 'critical',
              type: 'ceph_default',
              oid: '1.3.6.1.4.1.50495.1.2.1.5.5',
            },
            annotations: {
              documentation: 'https://docs.ceph.com/en/latest/cephfs/health-messages/#fs-with-failed-mds',
              summary: 'Ceph MDS daemon failed, no further standby available',
              description: 'An MDS daemon has failed, leaving only one active rank without further standby. Investigate the cause of the failure or add a standby daemon\n',
            },
          },
          {
            alert: 'CephFilesystemReadOnly',
            expr: 'ceph_health_detail{name="MDS_HEALTH_READ_ONLY"} > 0',
            'for': '1m',
            labels: {
              severity: 'critical',
              type: 'ceph_default',
              oid: '1.3.6.1.4.1.50495.1.2.1.5.2',
            },
            annotations: {
              documentation: 'https://docs.ceph.com/en/latest/cephfs/health-messages#cephfs-health-messages',
              summary: 'Ceph filesystem in read only mode, due to write error(s)',
              description: 'The filesystem has switched to READ ONLY due to an unexpected write error, when writing to the metadata pool\nEither analyse the output from the mds daemon admin socket, or escalate to support\n',
            },
          },
        ],
      },
      {
        name: 'mgr',
        rules: [
          {
            alert: 'CephMgrModuleCrash',
            expr: 'ceph_health_detail{name="RECENT_MGR_MODULE_CRASH"} == 1',
            'for': '5m',
            labels: {
              severity: 'critical',
              type: 'ceph_default',
              oid: '1.3.6.1.4.1.50495.1.2.1.6.1',
            },
            annotations: {
              documentation: 'https://docs.ceph.com/en/latest/rados/operations/health-checks#recent-mgr-module-crash',
              summary: 'A mgr module has recently crashed',
              description: "One or more mgr modules have crashed and are yet to be acknowledged by the administrator. A crashed module may impact functionality within the cluster. Use the 'ceph crash' commands to investigate which module has failed, and archive it to acknowledge the failure.\n",
            },
          },
          {
            alert: 'CephMgrPrometheusModuleInactive',
            expr: 'up{job="ceph"} == 0',
            'for': '1m',
            labels: {
              severity: 'critical',
              type: 'ceph_default',
              oid: '1.3.6.1.4.1.50495.1.2.1.6.2',
            },
            annotations: {
              summary: "Ceph's mgr/prometheus module is not available",
              description: "The mgr/prometheus module at {{ $labels.instance }} is unreachable. This could mean that the module has been disabled or the mgr itself is down.\nWithout the mgr/prometheus module metrics and alerts will no longer function. Open a shell to ceph and use 'ceph -s' to to determine whether the mgr is active. If the mgr is not active, restart it, otherwise you can check the mgr/prometheus module is loaded with 'ceph mgr module ls'  and if it's not listed as enabled, enable it with 'ceph mgr module enable prometheus'\n",
            },
          },
        ],
      },
      {
        name: 'pgs',
        rules: [
          {
            alert: 'CephPGsInactive',
            expr: 'ceph_pool_metadata * on(pool_id,instance) group_left() (ceph_pg_total - ceph_pg_active) > 0',
            'for': '5m',
            labels: {
              severity: 'critical',
              type: 'ceph_default',
              oid: '1.3.6.1.4.1.50495.1.2.1.7.1',
            },
            annotations: {
              summary: 'One or more Placement Groups are inactive',
              description: "{{ $value }} PGs have been inactive for more than 5 minutes in pool {{ $labels.name }}. Inactive placement groups aren't able to serve read/write requests.\n",
            },
          },
          {
            alert: 'CephPGsUnclean',
            expr: 'ceph_pool_metadata * on(pool_id,instance) group_left() (ceph_pg_total - ceph_pg_clean) > 0',
            'for': '15m',
            labels: {
              severity: 'warning',
              type: 'ceph_default',
              oid: '1.3.6.1.4.1.50495.1.2.1.7.2',
            },
            annotations: {
              summary: 'One or more platcment groups are marked unclean',
              description: "{{ $value }} PGs haven't been clean for more than 15 minutes in pool {{ $labels.name }}. Unclean PGs haven't been able to completely recover from a previous failure.\n",
            },
          },
          {
            alert: 'CephPGsDamaged',
            expr: 'ceph_health_detail{name=~"PG_DAMAGED|OSD_SCRUB_ERRORS"} == 1',
            'for': '5m',
            labels: {
              severity: 'critical',
              type: 'ceph_default',
              oid: '1.3.6.1.4.1.50495.1.2.1.7.4',
            },
            annotations: {
              documentation: 'https://docs.ceph.com/en/latest/rados/operations/health-checks#pg-damaged',
              summary: 'Placement group damaged, manual intervention needed',
              description: "During data consistency checks (scrub), at least one PG has been flagged as being damaged or inconsistent.\nCheck to see which PG is affected, and attempt a manual repair if neccessary. To list problematic placement groups, use 'rados list-inconsistent-pg <pool>'. To repair PGs use the 'ceph pg repair <pg_num>' command.\n",
            },
          },
          {
            alert: 'CephPGRecoveryAtRisk',
            expr: 'ceph_health_detail{name="PG_RECOVERY_FULL"} == 1',
            'for': '1m',
            labels: {
              severity: 'critical',
              type: 'ceph_default',
              oid: '1.3.6.1.4.1.50495.1.2.1.7.5',
            },
            annotations: {
              documentation: 'https://docs.ceph.com/en/latest/rados/operations/health-checks#pg-recovery-full',
              summary: 'OSDs are too full for automatic recovery',
              description: "Data redundancy may be reduced, or is at risk, since one or more OSDs are at or above their 'full' threshold. Add more capacity to the cluster, or delete unwanted data.\n",
            },
          },
          {
            alert: 'CephPGUnavilableBlockingIO',
            expr: '((ceph_health_detail{name="PG_AVAILABILITY"} == 1) - scalar(ceph_health_detail{name="OSD_DOWN"})) == 1',
            'for': '1m',
            labels: {
              severity: 'critical',
              type: 'ceph_default',
              oid: '1.3.6.1.4.1.50495.1.2.1.7.3',
            },
            annotations: {
              documentation: 'https://docs.ceph.com/en/latest/rados/operations/health-checks#pg-availability',
              summary: 'Placement group is unavailable, blocking some I/O',
              description: 'Data availability is reduced impacting the clusters abilty to service I/O to some data. One or more placement groups (PGs) are in a state that blocks IO.\n',
            },
          },
          {
            alert: 'CephPGBackfillAtRisk',
            expr: 'ceph_health_detail{name="PG_BACKFILL_FULL"} == 1',
            'for': '1m',
            labels: {
              severity: 'critical',
              type: 'ceph_default',
              oid: '1.3.6.1.4.1.50495.1.2.1.7.6',
            },
            annotations: {
              documentation: 'https://docs.ceph.com/en/latest/rados/operations/health-checks#pg-backfill-full',
              summary: 'Backfill operations are blocked, due to lack of freespace',
              description: "Data redundancy may be at risk due to lack of free space within the cluster. One or more OSDs have breached their 'backfillfull' threshold. Add more capacity, or delete unwanted data.\n",
            },
          },
          {
            alert: 'CephPGNotScrubbed',
            expr: 'ceph_health_detail{name="PG_NOT_SCRUBBED"} == 1',
            'for': '5m',
            labels: {
              severity: 'warning',
              type: 'ceph_default',
            },
            annotations: {
              documentation: 'https://docs.ceph.com/en/latest/rados/operations/health-checks#pg-not-scrubbed',
              summary: 'Placement group(s) have not been scrubbed',
              description: "One or more PGs have not been scrubbed recently. The scrub process is a data integrity\nfeature, protectng against bit-rot. It checks that objects and their metadata (size and\nattributes) match across object replicas. When PGs miss their scrub window, it may\nindicate the scrub window is too small, or PGs were not in a 'clean' state during the\nscrub window.\n\nYou can manually initiate a scrub with: ceph pg scrub <pgid>\n",
            },
          },
          {
            alert: 'CephPGsHighPerOSD',
            expr: 'ceph_health_detail{name="TOO_MANY_PGS"} == 1',
            'for': '1m',
            labels: {
              severity: 'warning',
              type: 'ceph_default',
            },
            annotations: {
              documentation: 'https://docs.ceph.com/en/latest/rados/operations/health-checks/#too-many-pgs',
              summary: 'Placement groups per OSD is too high',
              description: "The number of placement groups per OSD is too high (exceeds the mon_max_pg_per_osd setting).\n\nCheck that the pg_autoscaler hasn't been disabled for any of the pools, with 'ceph osd pool autoscale-status'\nand that the profile selected is appropriate. You may also adjust the target_size_ratio of a pool to guide\nthe autoscaler based on the expected relative size of the pool\n(i.e. 'ceph osd pool set cephfs.cephfs.meta target_size_ratio .1')\n",
            },
          },
          {
            alert: 'CephPGNotDeepScrubbed',
            expr: 'ceph_health_detail{name="PG_NOT_DEEP_SCRUBBED"} == 1',
            'for': '5m',
            labels: {
              severity: 'warning',
              type: 'ceph_default',
            },
            annotations: {
              documentation: 'https://docs.ceph.com/en/latest/rados/operations/health-checks#pg-not-deep-scrubbed',
              summary: 'Placement group(s) have not been deep scrubbed',
              description: "One or more PGs have not been deep scrubbed recently. Deep scrub is a data integrity\nfeature, protectng against bit-rot. It compares the contents of objects and their\nreplicas for inconsistency. When PGs miss their deep scrub window, it may indicate\nthat the window is too small or PGs were not in a 'clean' state during the deep-scrub\nwindow.\n\nYou can manually initiate a deep scrub with: ceph pg deep-scrub <pgid>\n",
            },
          },
        ],
      },
      {
        name: 'nodes',
        rules: [
          {
            alert: 'CephNodeRootFilesystemFull',
            expr: 'node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"} * 100 < 5',
            'for': '5m',
            labels: {
              severity: 'critical',
              type: 'ceph_default',
              oid: '1.3.6.1.4.1.50495.1.2.1.8.1',
            },
            annotations: {
              summary: 'Root filesystem is dangerously full',
              description: 'Root volume (OSD and MON store) is dangerously full: {{ $value | humanize }}% free.\n',
            },
          },
          {
            alert: 'CephNodeNetworkPacketDrops',
            expr: '(\n  increase(node_network_receive_drop_total{device!="lo"}[1m]) +\n  increase(node_network_transmit_drop_total{device!="lo"}[1m])\n) / (\n  increase(node_network_receive_packets_total{device!="lo"}[1m]) +\n  increase(node_network_transmit_packets_total{device!="lo"}[1m])\n) >= 0.0001 or (\n  increase(node_network_receive_drop_total{device!="lo"}[1m]) +\n  increase(node_network_transmit_drop_total{device!="lo"}[1m])\n) >= 10\n',
            labels: {
              severity: 'warning',
              type: 'ceph_default',
              oid: '1.3.6.1.4.1.50495.1.2.1.8.2',
            },
            annotations: {
              summary: 'One or more Nics is seeing packet drops',
              description: 'Node {{ $labels.instance }} experiences packet drop > 0.01% or > 10 packets/s on interface {{ $labels.device }}.\n',
            },
          },
          {
            alert: 'CephNodeNetworkPacketErrors',
            expr: '(\n  increase(node_network_receive_errs_total{device!="lo"}[1m]) +\n  increase(node_network_transmit_errs_total{device!="lo"}[1m])\n) / (\n  increase(node_network_receive_packets_total{device!="lo"}[1m]) +\n  increase(node_network_transmit_packets_total{device!="lo"}[1m])\n) >= 0.0001 or (\n  increase(node_network_receive_errs_total{device!="lo"}[1m]) +\n  increase(node_network_transmit_errs_total{device!="lo"}[1m])\n) >= 10\n',
            labels: {
              severity: 'warning',
              type: 'ceph_default',
              oid: '1.3.6.1.4.1.50495.1.2.1.8.3',
            },
            annotations: {
              summary: 'One or more Nics is seeing packet errors',
              description: 'Node {{ $labels.instance }} experiences packet errors > 0.01% or > 10 packets/s on interface {{ $labels.device }}.\n',
            },
          },
          {
            alert: 'CephNodeDiskspaceWarning',
            expr: 'predict_linear(node_filesystem_free_bytes{device=~"/.*"}[2d], 3600 * 24 * 5) *\non(instance) group_left(nodename) node_uname_info < 0\n',
            labels: {
              severity: 'warning',
              type: 'ceph_default',
              oid: '1.3.6.1.4.1.50495.1.2.1.8.4',
            },
            annotations: {
              summary: 'Host filesystem freespace is getting low',
              description: 'Mountpoint {{ $labels.mountpoint }} on {{ $labels.nodename }} will be full in less than 5 days assuming the average fill-up rate of the past 48 hours.\n',
            },
          },
          {
            alert: 'CephNodeInconsistentMTU',
            expr: 'node_network_mtu_bytes{device!="lo"} * (node_network_up{device!="lo"} > 0) != on() group_left() (quantile(0.5, node_network_mtu_bytes{device!="lo"}))',
            labels: {
              severity: 'warning',
              type: 'ceph_default',
            },
            annotations: {
              summary: 'MTU settings across Ceph hosts are inconsistent',
              description: 'Node {{ $labels.instance }} has a different MTU size ({{ $value }}) than the median value on device {{ $labels.device }}.\n',
            },
          },
        ],
      },
      {
        name: 'pools',
        rules: [
          {
            alert: 'CephPoolGrowthWarning',
            expr: '(predict_linear(ceph_pool_percent_used[2d], 3600 * 24 * 5) * on(pool_id)\n    group_right ceph_pool_metadata) >= 95\n',
            labels: {
              severity: 'warning',
              type: 'ceph_default',
              oid: '1.3.6.1.4.1.50495.1.2.1.9.2',
            },
            annotations: {
              summary: "Pool growth rate may soon exceed it's capacity",
              description: "Pool '{{ $labels.name }}' will be full in less than 5 days assuming the average fill-up rate of the past 48 hours.\n",
            },
          },
          {
            alert: 'CephPoolBackfillFull',
            expr: 'ceph_health_detail{name="POOL_BACKFILLFULL"} > 0',
            labels: {
              severity: 'warning',
              type: 'ceph_default',
            },
            annotations: {
              summary: 'Freespace in a pool is too low for recovery/rebalance',
              description: "A pool is approaching it's near full threshold, which will prevent rebalance operations from completing. You should consider adding more capacity to the pool.\n",
            },
          },
          {
            alert: 'CephPoolFull',
            expr: 'ceph_health_detail{name="POOL_FULL"} > 0',
            'for': '1m',
            labels: {
              severity: 'critical',
              type: 'ceph_default',
              oid: '1.3.6.1.4.1.50495.1.2.1.9.1',
            },
            annotations: {
              documentation: 'https://docs.ceph.com/en/latest/rados/operations/health-checks#pool-full',
              summary: 'Pool is full - writes are blocked',
              description: "A pool has reached it's MAX quota, or the OSDs supporting the pool\nhave reached their FULL threshold. Until this is resolved, writes to\nthe pool will be blocked.\nPool Breakdown (top 5)\n{{- range query \"topk(5, sort_desc(ceph_pool_percent_used * on(pool_id) group_right ceph_pool_metadata))\" }}\n  - {{ .Labels.name }} at {{ .Value }}%\n{{- end }}\nEither increase the pools quota, or add capacity to the cluster first\nthen increase it's quota (e.g. ceph osd pool set quota <pool_name> max_bytes <bytes>)\n",
            },
          },
          {
            alert: 'CephPoolNearFull',
            expr: 'ceph_health_detail{name="POOL_NEAR_FULL"} > 0',
            'for': '5m',
            labels: {
              severity: 'warning',
              type: 'ceph_default',
            },
            annotations: {
              summary: 'One or more Ceph pools are getting full',
              description: "A pool has exceeeded it warning (percent full) threshold, or the OSDs\nsupporting the pool have reached their NEARFULL thresholds. Writes may\ncontinue, but you are at risk of the pool going read only if more capacity\nisn't made available.\n\nDetermine the affected pool with 'ceph df detail', for example looking\nat QUOTA BYTES and STORED. Either increase the pools quota, or add\ncapacity to the cluster first then increase it's quota\n(e.g. ceph osd pool set quota <pool_name> max_bytes <bytes>)\n",
            },
          },
        ],
      },
      {
        name: 'healthchecks',
        rules: [
          {
            alert: 'CephSlowOps',
            expr: 'ceph_healthcheck_slow_ops > 0',
            'for': '30s',
            labels: {
              severity: 'warning',
              type: 'ceph_default',
            },
            annotations: {
              documentation: 'https://docs.ceph.com/en/latest/rados/operations/health-checks#slow-ops',
              summary: 'MON/OSD operations are slow to complete',
              description: '{{ $value }} OSD requests are taking too long to process (osd_op_complaint_time exceeded)\n',
            },
          },
        ],
      },
      {
        name: 'cephadm',
        rules: [
          {
            alert: 'CephadmUpgradeFailed',
            expr: 'ceph_health_detail{name="UPGRADE_EXCEPTION"} > 0',
            'for': '30s',
            labels: {
              severity: 'critical',
              type: 'ceph_default',
              oid: '1.3.6.1.4.1.50495.1.2.1.11.2',
            },
            annotations: {
              summary: 'Ceph version upgrade has failed',
              description: 'The cephadm cluster upgrade process has failed. The cluster remains in an undetermined state.\nPlease review the cephadm logs, to understand the nature of the issue\n',
            },
          },
          {
            alert: 'CephadmDaemonFailed',
            expr: 'ceph_health_detail{name="CEPHADM_FAILED_DAEMON"} > 0',
            'for': '30s',
            labels: {
              severity: 'critical',
              type: 'ceph_default',
              oid: '1.3.6.1.4.1.50495.1.2.1.11.1',
            },
            annotations: {
              summary: 'A ceph daemon manged by cephadm is down',
              description: "A daemon managed by cephadm is no longer active. Determine, which daemon is down with 'ceph health detail'. you may start daemons with the 'ceph orch daemon start <daemon_id>'\n",
            },
          },
          {
            alert: 'CephadmPaused',
            expr: 'ceph_health_detail{name="CEPHADM_PAUSED"} > 0',
            'for': '1m',
            labels: {
              severity: 'warning',
              type: 'ceph_default',
            },
            annotations: {
              documentation: 'https://docs.ceph.com/en/latest/cephadm/operations#cephadm-paused',
              summary: 'Orchestration tasks via cephadm are PAUSED',
              description: "Cluster management has been paused manually. This will prevent the orchestrator from service management and reconciliation. If this is not intentional, resume cephadm operations with 'ceph orch resume'\n",
            },
          },
        ],
      },
      {
        name: 'PrometheusServer',
        rules: [
          {
            alert: 'PrometheusJobMissing',
            expr: 'absent(up{job="ceph"})',
            'for': '30s',
            labels: {
              severity: 'critical',
              type: 'ceph_default',
              oid: '1.3.6.1.4.1.50495.1.2.1.12.1',
            },
            annotations: {
              summary: 'The scrape job for Ceph is missing from Prometheus',
              description: "The prometheus job that scrapes from Ceph is no longer defined, this\nwill effectively mean you'll have no metrics or alerts for the cluster.\n\nPlease review the job definitions in the prometheus.yml file of the prometheus\ninstance.\n",
            },
          },
        ],
      },
      {
        name: 'rados',
        rules: [
          {
            alert: 'CephObjectMissing',
            expr: '(ceph_health_detail{name="OBJECT_UNFOUND"} == 1) * on() (count(ceph_osd_up == 1) == bool count(ceph_osd_metadata)) == 1',
            'for': '30s',
            labels: {
              severity: 'critical',
              type: 'ceph_default',
              oid: '1.3.6.1.4.1.50495.1.2.1.10.1',
            },
            annotations: {
              documentation: 'https://docs.ceph.com/en/latest/rados/operations/health-checks#object-unfound',
              summary: 'Object(s) has been marked UNFOUND',
              description: 'A version of a RADOS object can not be found, even though all OSDs are up. I/O\nrequests for this object from clients will block (hang). Resolving this issue may\nrequire the object to be rolled back to a prior version manually, and manually verified.\n',
            },
          },
        ],
      },
      {
        name: 'generic',
        rules: [
          {
            alert: 'CephDaemonCrash',
            expr: 'ceph_health_detail{name="RECENT_CRASH"} == 1',
            'for': '1m',
            labels: {
              severity: 'critical',
              type: 'ceph_default',
              oid: '1.3.6.1.4.1.50495.1.2.1.1.2',
            },
            annotations: {
              documentation: 'https://docs.ceph.com/en/latest/rados/operations/health-checks/#recent-crash',
              summary: 'One or more Ceph daemons have crashed, and are pending acknowledgement',
              description: "One or more daemons have crashed recently, and need to be acknowledged. This notification\nensures that software crashes don't go unseen. To acknowledge a crash, use the\n'ceph crash archive <id>' command.\n",
            },
          },
        ],
      },
    ],
  },
}
