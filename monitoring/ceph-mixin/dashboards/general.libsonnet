local g = import 'grafonnet/grafana.libsonnet';
local u = import 'utils.libsonnet';

{
  grafanaDashboards+:: {
    'hosts-overview.json':
      local HostsOverviewSingleStatPanel(format,
                                         title,
                                         description,
                                         valueName,
                                         expr,
                                         targetFormat,
                                         x,
                                         y,
                                         w,
                                         h) =
        u.addSingleStatSchema('$datasource',
                              format,
                              title,
                              description,
                              valueName,
                              false,
                              100,
                              false,
                              false,
                              '')
        .addTarget(
          u.addTargetSchema(expr, 1, targetFormat, '')
        ) + { gridPos: { x: x, y: y, w: w, h: h } };

      local HostsOverviewGraphPanel(title, description, formatY1, expr, legendFormat, x, y, w, h) =
        u.graphPanelSchema(
          {}, title, description, 'null', false, formatY1, 'short', null, null, 0, 1, '$datasource'
        )
        .addTargets(
          [u.addTargetSchema(
            expr, 1, 'time_series', legendFormat
          )]
        ) + { gridPos: { x: x, y: y, w: w, h: h } };

      u.dashboardSchema(
        'Host Overview',
        '',
        'y0KGL0iZz',
        'now-1h',
        '10s',
        16,
        [],
        '',
        {
          refresh_intervals: ['5s', '10s', '30s', '1m', '5m', '15m', '30m', '1h', '2h', '1d'],
          time_options: ['5m', '15m', '1h', '6h', '12h', '24h', '2d', '7d', '30d'],
        }
      )
      .addRequired(
        type='grafana', id='grafana', name='Grafana', version='5.3.2'
      )
      .addRequired(
        type='panel', id='graph', name='Graph', version='5.0.0'
      )
      .addRequired(
        type='panel', id='singlestat', name='Singlestat', version='5.0.0'
      )
      .addAnnotation(
        u.addAnnotationSchema(
          1,
          '-- Grafana --',
          true,
          true,
          'rgba(0, 211, 255, 1)',
          'Annotations & Alerts',
          'dashboard'
        )
      )
      .addTemplate(
        g.template.datasource('datasource',
                              'prometheus',
                              'default',
                              label='Data Source')
      )
      .addTemplate(
        u.addTemplateSchema('osd_hosts',
                            '$datasource',
                            'label_values(ceph_disk_occupation, exported_instance)',
                            1,
                            true,
                            1,
                            null,
                            '([^.]*).*')
      )
      .addTemplate(
        u.addTemplateSchema('mon_hosts',
                            '$datasource',
                            'label_values(ceph_mon_metadata, ceph_daemon)',
                            1,
                            true,
                            1,
                            null,
                            'mon.(.*)')
      )
      .addTemplate(
        u.addTemplateSchema('mds_hosts',
                            '$datasource',
                            'label_values(ceph_mds_inodes, ceph_daemon)',
                            1,
                            true,
                            1,
                            null,
                            'mds.(.*)')
      )
      .addTemplate(
        u.addTemplateSchema('rgw_hosts',
                            '$datasource',
                            'label_values(ceph_rgw_qlen, ceph_daemon)',
                            1,
                            true,
                            1,
                            null,
                            'rgw.(.*)')
      )
      .addPanels([
        HostsOverviewSingleStatPanel(
          'none',
          'OSD Hosts',
          '',
          'current',
          'count(sum by (hostname) (ceph_osd_metadata))',
          'time_series',
          0,
          0,
          4,
          5
        ),
        HostsOverviewSingleStatPanel(
          'percentunit',
          'AVG CPU Busy',
          'Average CPU busy across all hosts (OSD, RGW, MON etc) within the cluster',
          'current',
          'avg(\n  1 - (\n    avg by(instance) \n      (irate(node_cpu_seconds_total{mode=\'idle\',instance=~\"($osd_hosts|$mon_hosts|$mds_hosts|$rgw_hosts).*\"}[1m]) or\n       irate(node_cpu{mode=\'idle\',instance=~\"($osd_hosts|$mon_hosts|$mds_hosts|$rgw_hosts).*\"}[1m]))\n    )\n  )',
          'time_series',
          4,
          0,
          4,
          5
        ),
        HostsOverviewSingleStatPanel(
          'percentunit',
          'AVG RAM Utilization',
          'Average Memory Usage across all hosts in the cluster (excludes buffer/cache usage)',
          'current',
          'avg (((node_memory_MemTotal{instance=~"($osd_hosts|$mon_hosts|$mds_hosts|$rgw_hosts).*"} or node_memory_MemTotal_bytes{instance=~"($osd_hosts|$mon_hosts|$mds_hosts|$rgw_hosts).*"})- (\n  (node_memory_MemFree{instance=~"($osd_hosts|$mon_hosts|$mds_hosts|$rgw_hosts).*"} or node_memory_MemFree_bytes{instance=~"($osd_hosts|$mon_hosts|$mds_hosts|$rgw_hosts).*"})  + \n  (node_memory_Cached{instance=~"($osd_hosts|$mon_hosts|$mds_hosts|$rgw_hosts).*"} or node_memory_Cached_bytes{instance=~"($osd_hosts|$mon_hosts|$mds_hosts|$rgw_hosts).*"}) + \n  (node_memory_Buffers{instance=~"($osd_hosts|$mon_hosts|$mds_hosts|$rgw_hosts).*"} or node_memory_Buffers_bytes{instance=~"($osd_hosts|$mon_hosts|$mds_hosts|$rgw_hosts).*"}) +\n  (node_memory_Slab{instance=~"($osd_hosts|$mon_hosts|$mds_hosts|$rgw_hosts).*"} or node_memory_Slab_bytes{instance=~"($osd_hosts|$mon_hosts|$mds_hosts|$rgw_hosts).*"})\n  )) /\n (node_memory_MemTotal{instance=~"($osd_hosts|$mon_hosts|$mds_hosts|$rgw_hosts).*"} or node_memory_MemTotal_bytes{instance=~"($osd_hosts|$rgw_hosts|$mon_hosts|$mds_hosts).*"} ))',
          'time_series',
          8,
          0,
          4,
          5
        ),
        HostsOverviewSingleStatPanel(
          'none',
          'Physical IOPS',
          'IOPS Load at the device as reported by the OS on all OSD hosts',
          'current',
          'sum ((irate(node_disk_reads_completed{instance=~"($osd_hosts).*"}[5m]) or irate(node_disk_reads_completed_total{instance=~"($osd_hosts).*"}[5m]) )  + \n(irate(node_disk_writes_completed{instance=~"($osd_hosts).*"}[5m]) or irate(node_disk_writes_completed_total{instance=~"($osd_hosts).*"}[5m])))',
          'time_series',
          12,
          0,
          4,
          5
        ),
        HostsOverviewSingleStatPanel(
          'percent',
          'AVG Disk Utilization',
          'Average Disk utilization for all OSD data devices (i.e. excludes journal/WAL)',
          'current',
          'avg (\n  label_replace((irate(node_disk_io_time_ms[5m]) / 10 ) or\n   (irate(node_disk_io_time_seconds_total[5m]) * 100), "instance", "$1", "instance", "([^.:]*).*"\n  ) *\n  on(instance, device, ceph_daemon) label_replace(label_replace(ceph_disk_occupation{instance=~"($osd_hosts).*"}, "device", "$1", "device", "/dev/(.*)"), "instance", "$1", "instance", "([^.:]*).*")\n)',
          'time_series',
          16,
          0,
          4,
          5
        ),
        HostsOverviewSingleStatPanel(
          'bytes',
          'Network Load',
          'Total send/receive network load across all hosts in the ceph cluster',
          'current',
          |||
            sum (
                    (
                            irate(node_network_receive_bytes{instance=~"($osd_hosts|mon_hosts|mds_hosts|rgw_hosts).*",device!="lo"}[1m]) or
                            irate(node_network_receive_bytes_total{instance=~"($osd_hosts|mon_hosts|mds_hosts|rgw_hosts).*",device!="lo"}[1m])
                    ) unless on (device, instance)
                    label_replace((bonding_slaves > 0), "device", "$1", "master", "(.+)")
            ) +
            sum (
                    (
                            irate(node_network_transmit_bytes{instance=~"($osd_hosts|mon_hosts|mds_hosts|rgw_hosts).*",device!="lo"}[1m]) or
                            irate(node_network_transmit_bytes_total{instance=~"($osd_hosts|mon_hosts|mds_hosts|rgw_hosts).*",device!="lo"}[1m])
                    ) unless on (device, instance)
                    label_replace((bonding_slaves > 0), "device", "$1", "master", "(.+)")
                    )
          |||
          ,
          'time_series',
          20,
          0,
          4,
          5
        ),
        HostsOverviewGraphPanel(
          'CPU Busy - Top 10 Hosts',
          'Show the top 10 busiest hosts by cpu',
          'percent',
          'topk(10,100 * ( 1 - (\n    avg by(instance) \n      (irate(node_cpu_seconds_total{mode=\'idle\',instance=~\"($osd_hosts|$mon_hosts|$mds_hosts|$rgw_hosts).*\"}[1m]) or\n       irate(node_cpu{mode=\'idle\',instance=~\"($osd_hosts|$mon_hosts|$mds_hosts|$rgw_hosts).*\"}[1m]))\n    )\n  )\n)',
          '{{instance}}',
          0,
          5,
          12,
          9
        ),
        HostsOverviewGraphPanel(
          'Network Load - Top 10 Hosts', 'Top 10 hosts by network load', 'Bps', |||
            topk(10, (sum by(instance) (
            (
                    irate(node_network_receive_bytes{instance=~"($osd_hosts|$mon_hosts|$mds_hosts|$rgw_hosts).*",device!="lo"}[1m]) or
                    irate(node_network_receive_bytes_total{instance=~"($osd_hosts|$mon_hosts|$mds_hosts|$rgw_hosts).*",device!="lo"}[1m])
            ) +
            (
                    irate(node_network_transmit_bytes{instance=~"($osd_hosts|$mon_hosts|$mds_hosts|$rgw_hosts).*",device!="lo"}[1m]) or
                    irate(node_network_transmit_bytes_total{instance=~"($osd_hosts|$mon_hosts|$mds_hosts|$rgw_hosts).*",device!="lo"}[1m])
            ) unless on (device, instance)
                    label_replace((bonding_slaves > 0), "device", "$1", "master", "(.+)"))
            ))
          |||
          , '{{instance}}', 12, 5, 12, 9
        ),
      ]),
    'host-details.json':
      local HostDetailsSingleStatPanel(format,
                                       title,
                                       description,
                                       valueName,
                                       expr,
                                       targetFormat,
                                       x,
                                       y,
                                       w,
                                       h) =
        u.addSingleStatSchema('$datasource',
                              format,
                              title,
                              description,
                              valueName,
                              false,
                              100,
                              false,
                              false,
                              '')
        .addTarget(u.addTargetSchema(expr,
                                     1,
                                     targetFormat,
                                     '')) + { gridPos: { x: x, y: y, w: w, h: h } };

      local HostDetailsGraphPanel(alias,
                                  title,
                                  description,
                                  nullPointMode,
                                  formatY1,
                                  labelY1,
                                  expr,
                                  legendFormat,
                                  x,
                                  y,
                                  w,
                                  h) =
        u.graphPanelSchema(alias,
                           title,
                           description,
                           nullPointMode,
                           false,
                           formatY1,
                           'short',
                           labelY1,
                           null,
                           null,
                           1,
                           '$datasource')
        .addTargets(
          [u.addTargetSchema(expr,
                             1,
                             'time_series',
                             legendFormat)]
        ) + { gridPos: { x: x, y: y, w: w, h: h } };

      u.dashboardSchema(
        'Host Details',
        '',
        'rtOg0AiWz',
        'now-1h',
        '10s',
        16,
        ['overview'],
        '',
        {
          refresh_intervals: ['5s', '10s', '30s', '1m', '5m', '15m', '30m', '1h', '2h', '1d'],
          time_options: ['5m', '15m', '1h', '6h', '12h', '24h', '2d', '7d', '30d'],
        }
      )
      .addRequired(
        type='grafana', id='grafana', name='Grafana', version='5.3.2'
      )
      .addRequired(
        type='panel', id='graph', name='Graph', version='5.0.0'
      )
      .addRequired(
        type='panel', id='singlestat', name='Singlestat', version='5.0.0'
      )
      .addAnnotation(
        u.addAnnotationSchema(
          1, '-- Grafana --', true, true, 'rgba(0, 211, 255, 1)', 'Annotations & Alerts', 'dashboard'
        )
      )
      .addTemplate(
        g.template.datasource('datasource', 'prometheus', 'default', label='Data Source')
      )
      .addTemplate(
        u.addTemplateSchema('ceph_hosts', '$datasource', 'label_values(node_scrape_collector_success, instance) ', 1, false, 3, 'Hostname', '([^.:]*).*')
      )
      .addPanels([
        u.addRowSchema(false, true, '$ceph_hosts System Overview') + { gridPos: { x: 0, y: 0, w: 24, h: 1 } },
        HostDetailsSingleStatPanel(
          'none',
          'OSDs',
          '',
          'current',
          "count(sum by (ceph_daemon) (ceph_osd_metadata{hostname='$ceph_hosts'}))",
          'time_series',
          0,
          1,
          3,
          5
        ),
        HostDetailsGraphPanel(
          {
            interrupt: '#447EBC',
            steal: '#6D1F62',
            system: '#890F02',
            user: '#3F6833',
            wait: '#C15C17',
          }, 'CPU Utilization', "Shows the CPU breakdown. When multiple servers are selected, only the first host's cpu data is shown", 'null', 'percent', '% Utilization', 'sum by (mode) (\n  irate(node_cpu{instance=~"($ceph_hosts)([\\\\.:].*)?", mode=~"(irq|nice|softirq|steal|system|user|iowait)"}[1m]) or\n  irate(node_cpu_seconds_total{instance=~"($ceph_hosts)([\\\\.:].*)?", mode=~"(irq|nice|softirq|steal|system|user|iowait)"}[1m])\n) / scalar(\n  sum(irate(node_cpu{instance=~"($ceph_hosts)([\\\\.:].*)?"}[1m]) or\n      irate(node_cpu_seconds_total{instance=~"($ceph_hosts)([\\\\.:].*)?"}[1m]))\n) * 100', '{{mode}}', 3, 1, 6, 10
        ),
        HostDetailsGraphPanel(
          {
            Available: '#508642',
            Free: '#508642',
            Total: '#bf1b00',
            Used: '#bf1b00',
            total: '#bf1b00',
            used: '#0a50a1',
          },
          'RAM Usage',
          '',
          'null',
          'bytes',
          'RAM used',
          'node_memory_MemFree{instance=~"$ceph_hosts([\\\\.:].*)?"} or node_memory_MemFree_bytes{instance=~"$ceph_hosts([\\\\.:].*)?"} ',
          'Free',
          9,
          1,
          6,
          10
        )
        .addTargets(
          [
            u.addTargetSchema('node_memory_MemTotal{instance=~"$ceph_hosts([\\\\.:].*)?"} or node_memory_MemTotal_bytes{instance=~"$ceph_hosts([\\\\.:].*)?"} ', 1, 'time_series', 'total'),
            u.addTargetSchema('(node_memory_Cached{instance=~"$ceph_hosts([\\\\.:].*)?"} or node_memory_Cached_bytes{instance=~"$ceph_hosts([\\\\.:].*)?"}) + \n(node_memory_Buffers{instance=~"$ceph_hosts([\\\\.:].*)?"} or node_memory_Buffers_bytes{instance=~"$ceph_hosts([\\\\.:].*)?"}) +\n(node_memory_Slab{instance=~"$ceph_hosts([\\\\.:].*)?"} or node_memory_Slab_bytes{instance=~"$ceph_hosts([\\\\.:].*)?"}) \n', 1, 'time_series', 'buffers/cache'),
            u.addTargetSchema('(node_memory_MemTotal{instance=~"$ceph_hosts([\\\\.:].*)?"} or node_memory_MemTotal_bytes{instance=~"$ceph_hosts([\\\\.:].*)?"})- (\n  (node_memory_MemFree{instance=~"$ceph_hosts([\\\\.:].*)?"} or node_memory_MemFree_bytes{instance=~"$ceph_hosts([\\\\.:].*)?"})  + \n  (node_memory_Cached{instance=~"$ceph_hosts([\\\\.:].*)?"} or node_memory_Cached_bytes{instance=~"$ceph_hosts([\\\\.:].*)?"}) + \n  (node_memory_Buffers{instance=~"$ceph_hosts([\\\\.:].*)?"} or node_memory_Buffers_bytes{instance=~"$ceph_hosts([\\\\.:].*)?"}) +\n  (node_memory_Slab{instance=~"$ceph_hosts([\\\\.:].*)?"} or node_memory_Slab_bytes{instance=~"$ceph_hosts([\\\\.:].*)?"})\n  )\n  \n', 1, 'time_series', 'used'),
          ]
        )
        .addSeriesOverride(
          {
            alias: 'total',
            color: '#bf1b00',
            fill: 0,
            linewidth: 2,
            stack: false,
          }
        ),
        HostDetailsGraphPanel(
          {},
          'Network Load',
          "Show the network load (rx,tx) across all interfaces (excluding loopback 'lo')",
          'null',
          'decbytes',
          'Send (-) / Receive (+)',
          'sum by (device) (\n  irate(node_network_receive_bytes{instance=~"($ceph_hosts)([\\\\.:].*)?",device!="lo"}[1m]) or \n  irate(node_network_receive_bytes_total{instance=~"($ceph_hosts)([\\\\.:].*)?",device!="lo"}[1m])\n)',
          '{{device}}.rx',
          15,
          1,
          6,
          10
        )
        .addTargets(
          [
            u.addTargetSchema('sum by (device) (\n  irate(node_network_transmit_bytes{instance=~"($ceph_hosts)([\\\\.:].*)?",device!="lo"}[1m]) or\n  irate(node_network_transmit_bytes_total{instance=~"($ceph_hosts)([\\\\.:].*)?",device!="lo"}[1m])\n)', 1, 'time_series', '{{device}}.tx'),
          ]
        )
        .addSeriesOverride(
          { alias: '/.*tx/', transform: 'negative-Y' }
        ),
        HostDetailsGraphPanel(
          {},
          'Network drop rate',
          '',
          'null',
          'pps',
          'Send (-) / Receive (+)',
          'irate(node_network_receive_drop{instance=~"$ceph_hosts([\\\\.:].*)?"}[1m]) or irate(node_network_receive_drop_total{instance=~"$ceph_hosts([\\\\.:].*)?"}[1m])',
          '{{device}}.rx',
          21,
          1,
          3,
          5
        )
        .addTargets(
          [
            u.addTargetSchema(
              'irate(node_network_transmit_drop{instance=~"$ceph_hosts([\\\\.:].*)?"}[1m]) or irate(node_network_transmit_drop_total{instance=~"$ceph_hosts([\\\\.:].*)?"}[1m])', 1, 'time_series', '{{device}}.tx'
            ),
          ]
        )
        .addSeriesOverride(
          {
            alias: '/.*tx/',
            transform: 'negative-Y',
          }
        ),
        HostDetailsSingleStatPanel(
          'bytes',
          'Raw Capacity',
          'Each OSD consists of a Journal/WAL partition and a data partition. The RAW Capacity shown is the sum of the data partitions across all OSDs on the selected OSD hosts.',
          'current',
          'sum(ceph_osd_stat_bytes and on (ceph_daemon) ceph_disk_occupation{instance=~"($ceph_hosts)([\\\\.:].*)?"})',
          'time_series',
          0,
          6,
          3,
          5
        ),
        HostDetailsGraphPanel(
          {},
          'Network error rate',
          '',
          'null',
          'pps',
          'Send (-) / Receive (+)',
          'irate(node_network_receive_errs{instance=~"$ceph_hosts([\\\\.:].*)?"}[1m]) or irate(node_network_receive_errs_total{instance=~"$ceph_hosts([\\\\.:].*)?"}[1m])',
          '{{device}}.rx',
          21,
          6,
          3,
          5
        )
        .addTargets(
          [u.addTargetSchema(
            'irate(node_network_transmit_errs{instance=~"$ceph_hosts([\\\\.:].*)?"}[1m]) or irate(node_network_transmit_errs_total{instance=~"$ceph_hosts([\\\\.:].*)?"}[1m])', 1, 'time_series', '{{device}}.tx'
          )]
        )
        .addSeriesOverride(
          {
            alias: '/.*tx/',
            transform: 'negative-Y',
          }
        ),
        u.addRowSchema(false,
                       true,
                       'OSD Disk Performance Statistics') + { gridPos: { x: 0, y: 11, w: 24, h: 1 } },
        HostDetailsGraphPanel(
          {},
          '$ceph_hosts Disk IOPS',
          "For any OSD devices on the host, this chart shows the iops per physical device. Each device is shown by it's name and corresponding OSD id value",
          'connected',
          'ops',
          'Read (-) / Write (+)',
          'label_replace(\n  (\n    irate(node_disk_writes_completed{instance=~"($ceph_hosts)([\\\\.:].*)?"}[5m]) or\n    irate(node_disk_writes_completed_total{instance=~"($ceph_hosts)([\\\\.:].*)?"}[5m])\n  ),\n  "instance",\n  "$1",\n  "instance",\n  "([^:.]*).*"\n)\n* on(instance, device, ceph_daemon) group_left\n  label_replace(\n    label_replace(\n      ceph_disk_occupation,\n      "device",\n      "$1",\n      "device",\n      "/dev/(.*)"\n    ),\n    "instance",\n    "$1",\n    "instance",\n    "([^:.]*).*"\n  )',
          '{{device}}({{ceph_daemon}}) writes',
          0,
          12,
          11,
          9
        )
        .addTargets(
          [
            u.addTargetSchema(
              'label_replace(\n    (irate(node_disk_reads_completed{instance=~"($ceph_hosts)([\\\\.:].*)?"}[5m]) or irate(node_disk_reads_completed_total{instance=~"($ceph_hosts)([\\\\.:].*)?"}[5m])),\n    "instance",\n    "$1",\n    "instance",\n    "([^:.]*).*"\n)\n* on(instance, device, ceph_daemon) group_left\n  label_replace(\n    label_replace(\n      ceph_disk_occupation,\n      "device",\n      "$1",\n      "device",\n      "/dev/(.*)"\n    ),\n    "instance",\n    "$1",\n    "instance",\n    "([^:.]*).*"\n  )',
              1,
              'time_series',
              '{{device}}({{ceph_daemon}}) reads'
            ),
          ]
        )
        .addSeriesOverride(
          { alias: '/.*reads/', transform: 'negative-Y' }
        ),
        HostDetailsGraphPanel(
          {},
          '$ceph_hosts Throughput by Disk',
          'For OSD hosts, this chart shows the disk bandwidth (read bytes/sec + write bytes/sec) of the physical OSD device. Each device is shown by device name, and corresponding OSD id',
          'connected',
          'Bps',
          'Read (-) / Write (+)',
          'label_replace((irate(node_disk_bytes_written{instance=~"($ceph_hosts)([\\\\.:].*)?"}[5m]) or irate(node_disk_written_bytes_total{instance=~"($ceph_hosts)([\\\\.:].*)?"}[5m])), "instance", "$1", "instance", "([^:.]*).*") * on(instance, device, ceph_daemon) group_left label_replace(label_replace(ceph_disk_occupation, "device", "$1", "device", "/dev/(.*)"), "instance", "$1", "instance", "([^:.]*).*")',
          '{{device}}({{ceph_daemon}}) write',
          12,
          12,
          11,
          9
        )
        .addTargets(
          [u.addTargetSchema(
            'label_replace((irate(node_disk_bytes_read{instance=~"($ceph_hosts)([\\\\.:].*)?"}[5m]) or irate(node_disk_read_bytes_total{instance=~"($ceph_hosts)([\\\\.:].*)?"}[5m])), "instance", "$1", "instance", "([^:.]*).*") * on(instance, device, ceph_daemon) group_left label_replace(label_replace(ceph_disk_occupation, "device", "$1", "device", "/dev/(.*)"), "instance", "$1", "instance", "([^:.]*).*")',
            1,
            'time_series',
            '{{device}}({{ceph_daemon}}) read'
          )]
        )
        .addSeriesOverride(
          { alias: '/.*read/', transform: 'negative-Y' }
        ),
        HostDetailsGraphPanel(
          {},
          '$ceph_hosts Disk Latency',
          "For OSD hosts, this chart shows the latency at the physical drive. Each drive is shown by device name, with it's corresponding OSD id",
          'null as zero',
          's',
          '',
          'max by(instance,device) (label_replace((irate(node_disk_write_time_seconds_total{ instance=~"($ceph_hosts)([\\\\.:].*)?"}[5m]) )  / clamp_min(irate(node_disk_writes_completed_total{ instance=~"($ceph_hosts)([\\\\.:].*)?"}[5m]), 0.001) or   (irate(node_disk_read_time_seconds_total{ instance=~"($ceph_hosts)([\\\\.:].*)?"}[5m]) )  / clamp_min(irate(node_disk_reads_completed_total{ instance=~"($ceph_hosts)([\\\\.:].*)?"}[5m]), 0.001), "instance", "$1", "instance", "([^:.]*).*")) *  on(instance, device, ceph_daemon) group_left label_replace(label_replace(ceph_disk_occupation{instance=~"($ceph_hosts)([\\\\.:].*)?"}, "device", "$1", "device", "/dev/(.*)"), "instance", "$1", "instance", "([^:.]*).*")',
          '{{device}}({{ceph_daemon}})',
          0,
          21,
          11,
          9
        ),
        HostDetailsGraphPanel(
          {},
          '$ceph_hosts Disk utilization',
          'Show disk utilization % (util) of any OSD devices on the host by the physical device name and associated OSD id.',
          'connected',
          'percent',
          '%Util',
          'label_replace(((irate(node_disk_io_time_ms{instance=~"($ceph_hosts)([\\\\.:].*)?"}[5m]) / 10 ) or  irate(node_disk_io_time_seconds_total{instance=~"($ceph_hosts)([\\\\.:].*)?"}[5m]) * 100), "instance", "$1", "instance", "([^:.]*).*") * on(instance, device, ceph_daemon) group_left label_replace(label_replace(ceph_disk_occupation{instance=~"($ceph_hosts)([\\\\.:].*)?"}, "device", "$1", "device", "/dev/(.*)"), "instance", "$1", "instance", "([^:.]*).*")',
          '{{device}}({{ceph_daemon}})',
          12,
          21,
          11,
          9
        ),
      ]),
    'pool-overview.json':
      local PoolOverviewSingleStatPanel(format,
                                        title,
                                        description,
                                        valueName,
                                        expr,
                                        targetFormat,
                                        x,
                                        y,
                                        w,
                                        h) =
        u.addSingleStatSchema('$datasource',
                              format,
                              title,
                              description,
                              valueName,
                              false,
                              100,
                              false,
                              false,
                              '')
        .addTarget(u.addTargetSchema(expr, 1, targetFormat, '')) + { gridPos: { x: x, y: y, w: w, h: h } };

      local PoolOverviewStyle(alias,
                              pattern,
                              type,
                              unit,
                              colorMode,
                              thresholds,
                              valueMaps) =
        u.addStyle(alias,
                   colorMode,
                   [
                     'rgba(245, 54, 54, 0.9)',
                     'rgba(237, 129, 40, 0.89)',
                     'rgba(50, 172, 45, 0.97)',
                   ],
                   'YYYY-MM-DD HH:mm:ss',
                   2,
                   1,
                   pattern,
                   thresholds,
                   type,
                   unit,
                   valueMaps);

      local PoolOverviewGraphPanel(title,
                                   description,
                                   formatY1,
                                   labelY1,
                                   expr,
                                   targetFormat,
                                   legendFormat,
                                   x,
                                   y,
                                   w,
                                   h) =
        u.graphPanelSchema({},
                           title,
                           description,
                           'null as zero',
                           false,
                           formatY1,
                           'short',
                           labelY1,
                           null,
                           0,
                           1,
                           '$datasource')
        .addTargets(
          [u.addTargetSchema(expr,
                             1,
                             'time_series',
                             legendFormat)]
        ) + { gridPos: { x: x, y: y, w: w, h: h } };

      u.dashboardSchema(
        'Ceph Pools Overview',
        '',
        'z99hzWtmk',
        'now-1h',
        '15s',
        22,
        [],
        '',
        { refresh_intervals: ['5s', '10s', '15s', '30s', '1m', '5m', '15m', '30m', '1h', '2h', '1d'], time_options: ['5m', '15m', '1h', '6h', '12h', '24h', '2d', '7d', '30d'] }
      )
      .addAnnotation(
        u.addAnnotationSchema(
          1,
          '-- Grafana --',
          true,
          true,
          'rgba(0, 211, 255, 1)',
          'Annotations & Alerts',
          'dashboard'
        )
      )
      .addTemplate(
        g.template.datasource('datasource',
                              'prometheus',
                              'Dashboard1',
                              label='Data Source')
      )
      .addTemplate(
        g.template.custom(label='TopK',
                          name='topk',
                          current='15',
                          query='15')
      )
      .addPanels([
        PoolOverviewSingleStatPanel(
          'none',
          'Pools',
          '',
          'avg',
          'count(ceph_pool_metadata)',
          'table',
          0,
          0,
          3,
          3
        ),
        PoolOverviewSingleStatPanel(
          'none',
          'Pools with Compression',
          'Count of the pools that have compression enabled',
          'current',
          'count(ceph_pool_metadata{compression_mode!="none"})',
          '',
          3,
          0,
          3,
          3
        ),
        PoolOverviewSingleStatPanel(
          'bytes',
          'Total Raw Capacity',
          'Total raw capacity available to the cluster',
          'current',
          'sum(ceph_osd_stat_bytes)',
          '',
          6,
          0,
          3,
          3
        ),
        PoolOverviewSingleStatPanel(
          'bytes',
          'Raw Capacity Consumed',
          'Total raw capacity consumed by user data and associated overheads (metadata + redundancy)',
          'current',
          'sum(ceph_pool_bytes_used)',
          '',
          9,
          0,
          3,
          3
        ),
        PoolOverviewSingleStatPanel(
          'bytes',
          'Logical Stored ',
          'Total of client data stored in the cluster',
          'current',
          'sum(ceph_pool_stored)',
          '',
          12,
          0,
          3,
          3
        ),
        PoolOverviewSingleStatPanel(
          'bytes',
          'Compression Savings',
          'A compression saving is determined as the data eligible to be compressed minus the capacity used to store the data after compression',
          'current',
          'sum(ceph_pool_compress_under_bytes - ceph_pool_compress_bytes_used)',
          '',
          15,
          0,
          3,
          3
        ),
        PoolOverviewSingleStatPanel(
          'percent',
          'Compression Eligibility',
          'Indicates how suitable the data is within the pools that are/have been enabled for compression - averaged across all pools holding compressed data\n',
          'current',
          '(sum(ceph_pool_compress_under_bytes > 0) / sum(ceph_pool_stored_raw and ceph_pool_compress_under_bytes > 0)) * 100',
          'table',
          18,
          0,
          3,
          3
        ),
        PoolOverviewSingleStatPanel(
          'none',
          'Compression Factor',
          'This factor describes the average ratio of data eligible to be compressed divided by the data actually stored. It does not account for data written that was ineligible for compression (too small, or compression yield too low)',
          'current',
          'sum(ceph_pool_compress_under_bytes > 0) / sum(ceph_pool_compress_bytes_used > 0)',
          '',
          21,
          0,
          3,
          3
        ),
        u.addTableSchema(
          '$datasource',
          '',
          { col: 5, desc: true },
          [
            PoolOverviewStyle('', 'Time', 'hidden', 'short', null, [], []),
            PoolOverviewStyle('', 'instance', 'hidden', 'short', null, [], []),
            PoolOverviewStyle('', 'job', 'hidden', 'short', null, [], []),
            PoolOverviewStyle('Pool Name', 'name', 'string', 'short', null, [], []),
            PoolOverviewStyle('Pool ID', 'pool_id', 'hidden', 'none', null, [], []),
            PoolOverviewStyle('Compression Factor', 'Value #A', 'number', 'none', null, [], []),
            PoolOverviewStyle('% Used', 'Value #D', 'number', 'percentunit', 'value', ['70', '85'], []),
            PoolOverviewStyle('Usable Free', 'Value #B', 'number', 'bytes', null, [], []),
            PoolOverviewStyle('Compression Eligibility', 'Value #C', 'number', 'percent', null, [], []),
            PoolOverviewStyle('Compression Savings', 'Value #E', 'number', 'bytes', null, [], []),
            PoolOverviewStyle('Growth (5d)', 'Value #F', 'number', 'bytes', 'value', ['0', '0'], []),
            PoolOverviewStyle('IOPS', 'Value #G', 'number', 'none', null, [], []),
            PoolOverviewStyle('Bandwidth', 'Value #H', 'number', 'Bps', null, [], []),
            PoolOverviewStyle('', '__name__', 'hidden', 'short', null, [], []),
            PoolOverviewStyle('', 'type', 'hidden', 'short', null, [], []),
            PoolOverviewStyle('', 'compression_mode', 'hidden', 'short', null, [], []),
            PoolOverviewStyle('Type', 'description', 'string', 'short', null, [], []),
            PoolOverviewStyle('Stored', 'Value #J', 'number', 'bytes', null, [], []),
            PoolOverviewStyle('', 'Value #I', 'hidden', 'short', null, [], []),
            PoolOverviewStyle('Compression', 'Value #K', 'string', 'short', null, [], [{ text: 'ON', value: '1' }]),
          ],
          'Pool Overview',
          'table'
        )
        .addTargets(
          [
            u.addTargetSchema(
              '(ceph_pool_compress_under_bytes / ceph_pool_compress_bytes_used > 0) and on(pool_id) (((ceph_pool_compress_under_bytes > 0) / ceph_pool_stored_raw) * 100 > 0.5)',
              1,
              'table',
              ''
            ),
            u.addTargetSchema(
              'ceph_pool_max_avail * on(pool_id) group_left(name) ceph_pool_metadata',
              1,
              'table',
              ''
            ),
            u.addTargetSchema(
              '((ceph_pool_compress_under_bytes > 0) / ceph_pool_stored_raw) * 100',
              1,
              'table',
              ''
            ),
            u.addTargetSchema(
              '(ceph_pool_percent_used * on(pool_id) group_left(name) ceph_pool_metadata)',
              1,
              'table',
              ''
            ),
            u.addTargetSchema(
              '(ceph_pool_compress_under_bytes - ceph_pool_compress_bytes_used > 0)',
              1,
              'table',
              ''
            ),
            u.addTargetSchema(
              'delta(ceph_pool_stored[5d])', 1, 'table', ''
            ),
            u.addTargetSchema(
              'rate(ceph_pool_rd[30s]) + rate(ceph_pool_wr[30s])', 1, 'table', ''
            ),
            u.addTargetSchema(
              'rate(ceph_pool_rd_bytes[30s]) + rate(ceph_pool_wr_bytes[30s])', 1, 'table', ''
            ),
            u.addTargetSchema(
              'ceph_pool_metadata', 1, 'table', ''
            ),
            u.addTargetSchema(
              'ceph_pool_stored * on(pool_id) group_left ceph_pool_metadata', 1, 'table', ''
            ),
            u.addTargetSchema(
              'ceph_pool_metadata{compression_mode!="none"}', 1, 'table', ''
            ),
            u.addTargetSchema('', '', '', ''),
          ]
        ) + { gridPos: { x: 0, y: 3, w: 24, h: 6 } },
        PoolOverviewGraphPanel(
          'Top $topk Client IOPS by Pool',
          'This chart shows the sum of read and write IOPS from all clients by pool',
          'short',
          'IOPS',
          'topk($topk,round((rate(ceph_pool_rd[30s]) + rate(ceph_pool_wr[30s])),1) * on(pool_id) group_left(instance,name) ceph_pool_metadata) ',
          'time_series',
          '{{name}} ',
          0,
          9,
          12,
          8
        )
        .addTarget(
          u.addTargetSchema(
            'topk($topk,rate(ceph_pool_wr[30s]) + on(pool_id) group_left(instance,name) ceph_pool_metadata) ',
            1,
            'time_series',
            '{{name}} - write'
          )
        ),
        PoolOverviewGraphPanel(
          'Top $topk Client Bandwidth by Pool',
          'The chart shows the sum of read and write bytes from all clients, by pool',
          'Bps',
          'Throughput',
          'topk($topk,(rate(ceph_pool_rd_bytes[30s]) + rate(ceph_pool_wr_bytes[30s])) * on(pool_id) group_left(instance,name) ceph_pool_metadata)',
          'time_series',
          '{{name}}',
          12,
          9,
          12,
          8
        ),
        PoolOverviewGraphPanel(
          'Pool Capacity Usage (RAW)',
          'Historical view of capacity usage, to help identify growth and trends in pool consumption',
          'bytes',
          'Capacity Used',
          'ceph_pool_bytes_used * on(pool_id) group_right ceph_pool_metadata',
          '',
          '{{name}}',
          0,
          17,
          24,
          7
        ),
      ]),
    'pool-detail.json':
      local PoolDetailSingleStatPanel(format,
                                      title,
                                      description,
                                      valueName,
                                      colorValue,
                                      gaugeMaxValue,
                                      gaugeShow,
                                      sparkLineShow,
                                      thresholds,
                                      expr,
                                      targetFormat,
                                      x,
                                      y,
                                      w,
                                      h) =
        u.addSingleStatSchema('$datasource',
                              format,
                              title,
                              description,
                              valueName,
                              colorValue,
                              gaugeMaxValue,
                              gaugeShow,
                              sparkLineShow,
                              thresholds)
        .addTarget(u.addTargetSchema(expr, 1, targetFormat, '')) + { gridPos: { x: x, y: y, w: w, h: h } };

      local PoolDetailGraphPanel(alias,
                                 title,
                                 description,
                                 formatY1,
                                 labelY1,
                                 expr,
                                 targetFormat,
                                 legendFormat,
                                 x,
                                 y,
                                 w,
                                 h) =
        u.graphPanelSchema(alias,
                           title,
                           description,
                           'null as zero',
                           false,
                           formatY1,
                           'short',
                           labelY1,
                           null,
                           null,
                           1,
                           '$datasource')
        .addTargets(
          [u.addTargetSchema(expr, 1, 'time_series', legendFormat)]
        ) + { gridPos: { x: x, y: y, w: w, h: h } };

      u.dashboardSchema(
        'Ceph Pool Details',
        '',
        '-xyV8KCiz',
        'now-1h',
        '15s',
        22,
        [],
        '',
        {
          refresh_intervals: ['5s', '10s', '15s', '30s', '1m', '5m', '15m', '30m', '1h', '2h', '1d'],
          time_options: ['5m', '15m', '1h', '6h', '12h', '24h', '2d', '7d', '30d'],
        }
      )
      .addRequired(
        type='grafana', id='grafana', name='Grafana', version='5.3.2'
      )
      .addRequired(
        type='panel', id='graph', name='Graph', version='5.0.0'
      )
      .addRequired(
        type='panel', id='singlestat', name='Singlestat', version='5.0.0'
      )
      .addAnnotation(
        u.addAnnotationSchema(
          1,
          '-- Grafana --',
          true,
          true,
          'rgba(0, 211, 255, 1)',
          'Annotations & Alerts',
          'dashboard'
        )
      )
      .addTemplate(
        g.template.datasource('datasource',
                              'prometheus',
                              'Prometheus admin.virt1.home.fajerski.name:9090',
                              label='Data Source')
      )
      .addTemplate(
        u.addTemplateSchema('pool_name',
                            '$datasource',
                            'label_values(ceph_pool_metadata,name)',
                            1,
                            false,
                            1,
                            'Pool Name',
                            '')
      )
      .addPanels([
        PoolDetailSingleStatPanel(
          'percentunit',
          'Capacity used',
          '',
          'current',
          true,
          1,
          true,
          true,
          '.7,.8',
          '(ceph_pool_stored / (ceph_pool_stored + ceph_pool_max_avail)) * on(pool_id) group_left(instance,name) ceph_pool_metadata{name=~"$pool_name"}',
          'time_series',
          0,
          0,
          7,
          7
        ),
        PoolDetailSingleStatPanel(
          's',
          'Time till full',
          'Time till pool is full assuming the average fill rate of the last 6 hours',
          false,
          100,
          false,
          false,
          '',
          'current',
          '(ceph_pool_max_avail / deriv(ceph_pool_stored[6h])) * on(pool_id) group_left(instance,name) ceph_pool_metadata{name=~"$pool_name"} > 0',
          'time_series',
          7,
          0,
          5,
          7
        ),
        PoolDetailGraphPanel(
          {
            read_op_per_sec:
              '#3F6833',
            write_op_per_sec: '#E5AC0E',
          },
          '$pool_name Object Ingress/Egress',
          '',
          'ops',
          'Objects out(-) / in(+) ',
          'deriv(ceph_pool_objects[1m]) * on(pool_id) group_left(instance,name) ceph_pool_metadata{name=~"$pool_name"}',
          'time_series',
          'Objects per second',
          12,
          0,
          12,
          7
        ),
        PoolDetailGraphPanel(
          {
            read_op_per_sec: '#3F6833',
            write_op_per_sec: '#E5AC0E',
          }, '$pool_name Client IOPS', '', 'iops', 'Read (-) / Write (+)', 'irate(ceph_pool_rd[1m]) * on(pool_id) group_left(instance,name) ceph_pool_metadata{name=~"$pool_name"}', 'time_series', 'reads', 0, 7, 12, 7
        )
        .addSeriesOverride({ alias: 'reads', transform: 'negative-Y' })
        .addTarget(
          u.addTargetSchema(
            'irate(ceph_pool_wr[1m]) * on(pool_id) group_left(instance,name) ceph_pool_metadata{name=~"$pool_name"}', 1, 'time_series', 'writes'
          )
        ),
        PoolDetailGraphPanel(
          {
            read_op_per_sec: '#3F6833',
            write_op_per_sec: '#E5AC0E',
          },
          '$pool_name Client Throughput',
          '',
          'Bps',
          'Read (-) / Write (+)',
          'irate(ceph_pool_rd_bytes[1m]) + on(pool_id) group_left(instance,name) ceph_pool_metadata{name=~"$pool_name"}',
          'time_series',
          'reads',
          12,
          7,
          12,
          7
        )
        .addSeriesOverride({ alias: 'reads', transform: 'negative-Y' })
        .addTarget(
          u.addTargetSchema(
            'irate(ceph_pool_wr_bytes[1m]) + on(pool_id) group_left(instance,name) ceph_pool_metadata{name=~"$pool_name"}',
            1,
            'time_series',
            'writes'
          )
        ),
        PoolDetailGraphPanel(
          {
            read_op_per_sec: '#3F6833',
            write_op_per_sec: '#E5AC0E',
          },
          '$pool_name Objects',
          '',
          'short',
          'Objects',
          'ceph_pool_objects * on(pool_id) group_left(instance,name) ceph_pool_metadata{name=~"$pool_name"}',
          'time_series',
          'Number of Objects',
          0,
          14,
          12,
          7
        ),
      ]),
    'osds-overview.json':
      local OsdOverviewStyle(alias, pattern, type, unit) =
        u.addStyle(alias, null, [
          'rgba(245, 54, 54, 0.9)',
          'rgba(237, 129, 40, 0.89)',
          'rgba(50, 172, 45, 0.97)',
        ], 'YYYY-MM-DD HH:mm:ss', 2, 1, pattern, [], type, unit, []);
      local OsdOverviewGraphPanel(alias,
                                  title,
                                  description,
                                  formatY1,
                                  labelY1,
                                  min,
                                  expr,
                                  legendFormat1,
                                  x,
                                  y,
                                  w,
                                  h) =
        u.graphPanelSchema(alias,
                           title,
                           description,
                           'null',
                           false,
                           formatY1,
                           'short',
                           labelY1,
                           null,
                           min,
                           1,
                           '$datasource')
        .addTargets(
          [u.addTargetSchema(expr, 1, 'time_series', legendFormat1)]
        ) + { gridPos: { x: x, y: y, w: w, h: h } };
      local OsdOverviewPieChartPanel(alias, description, title) =
        u.addPieChartSchema(alias,
                            '$datasource',
                            description,
                            'Under graph',
                            'pie',
                            title,
                            'current');

      u.dashboardSchema(
        'OSD Overview',
        '',
        'lo02I1Aiz',
        'now-1h',
        '10s',
        16,
        [],
        '',
        {
          refresh_intervals: ['5s', '10s', '30s', '1m', '5m', '15m', '30m', '1h', '2h', '1d'],
          time_options: ['5m', '15m', '1h', '6h', '12h', '24h', '2d', '7d', '30d'],
        }
      )
      .addAnnotation(
        u.addAnnotationSchema(
          1,
          '-- Grafana --',
          true,
          true,
          'rgba(0, 211, 255, 1)',
          'Annotations & Alerts',
          'dashboard'
        )
      )
      .addRequired(
        type='grafana', id='grafana', name='Grafana', version='5.0.0'
      )
      .addRequired(
        type='panel', id='grafana-piechart-panel', name='Pie Chart', version='1.3.3'
      )
      .addRequired(
        type='panel', id='graph', name='Graph', version='5.0.0'
      )
      .addRequired(
        type='panel', id='table', name='Table', version='5.0.0'
      )
      .addTemplate(
        g.template.datasource('datasource', 'prometheus', 'default', label='Data Source')
      )
      .addPanels([
        OsdOverviewGraphPanel(
          { '@95%ile': '#e0752d' },
          'OSD Read Latencies',
          '',
          'ms',
          null,
          '0',
          'avg (irate(ceph_osd_op_r_latency_sum[1m]) / on (ceph_daemon) irate(ceph_osd_op_r_latency_count[1m]) * 1000)',
          'AVG read',
          0,
          0,
          8,
          8
        )
        .addTargets(
          [
            u.addTargetSchema(
              'max (irate(ceph_osd_op_r_latency_sum[1m]) / on (ceph_daemon) irate(ceph_osd_op_r_latency_count[1m]) * 1000)',
              1,
              'time_series',
              'MAX read'
            ),
            u.addTargetSchema(
              'quantile(0.95,\n  (irate(ceph_osd_op_r_latency_sum[1m]) / on (ceph_daemon) irate(ceph_osd_op_r_latency_count[1m]) * 1000)\n)', 1, 'time_series', '@95%ile'
            ),
          ],
        ),
        u.addTableSchema(
          '$datasource',
          "This table shows the osd's that are delivering the 10 highest read latencies within the cluster",
          { col: 2, desc: true },
          [
            OsdOverviewStyle('OSD ID', 'ceph_daemon', 'string', 'short'),
            OsdOverviewStyle('Latency (ms)', 'Value', 'number', 'none'),
            OsdOverviewStyle('', '/.*/', 'hidden', 'short'),
          ],
          'Highest READ Latencies',
          'table'
        )
        .addTarget(
          u.addTargetSchema(
            'topk(10,\n  (sort(\n    (irate(ceph_osd_op_r_latency_sum[1m]) / on (ceph_daemon) irate(ceph_osd_op_r_latency_count[1m]) * 1000)\n  ))\n)\n\n', 1, 'table', ''
          )
        ) + { gridPos: { x: 8, y: 0, w: 4, h: 8 } },
        OsdOverviewGraphPanel(
          {
            '@95%ile write': '#e0752d',
          },
          'OSD Write Latencies',
          '',
          'ms',
          null,
          '0',
          'avg (irate(ceph_osd_op_w_latency_sum[1m]) / on (ceph_daemon) irate(ceph_osd_op_w_latency_count[1m]) * 1000)',
          'AVG write',
          12,
          0,
          8,
          8
        )
        .addTargets(
          [
            u.addTargetSchema(
              'max (irate(ceph_osd_op_w_latency_sum[1m]) / on (ceph_daemon) irate(ceph_osd_op_w_latency_count[1m]) * 1000)',
              1,
              'time_series',
              'MAX write'
            ),
            u.addTargetSchema(
              'quantile(0.95,\n (irate(ceph_osd_op_w_latency_sum[1m]) / on (ceph_daemon) irate(ceph_osd_op_w_latency_count[1m]) * 1000)\n)', 1, 'time_series', '@95%ile write'
            ),
          ],
        ),
        u.addTableSchema(
          '$datasource',
          "This table shows the osd's that are delivering the 10 highest write latencies within the cluster",
          { col: 2, desc: true },
          [
            OsdOverviewStyle(
              'OSD ID', 'ceph_daemon', 'string', 'short'
            ),
            OsdOverviewStyle('Latency (ms)', 'Value', 'number', 'none'),
            OsdOverviewStyle('', '/.*/', 'hidden', 'short'),
          ],
          'Highest WRITE Latencies',
          'table'
        )
        .addTarget(
          u.addTargetSchema(
            'topk(10,\n  (sort(\n    (irate(ceph_osd_op_w_latency_sum[1m]) / on (ceph_daemon) irate(ceph_osd_op_w_latency_count[1m]) * 1000)\n  ))\n)\n\n',
            1,
            'table',
            ''
          )
        ) + { gridPos: { x: 20, y: 0, w: 4, h: 8 } },
        OsdOverviewPieChartPanel(
          {}, '', 'OSD Types Summary'
        )
        .addTarget(
          u.addTargetSchema('count by (device_class) (ceph_osd_metadata)', 1, 'time_series', '{{device_class}}')
        ) + { gridPos: { x: 0, y: 8, w: 4, h: 8 } },
        OsdOverviewPieChartPanel(
          { 'Non-Encrypted': '#E5AC0E' }, '', 'OSD Objectstore Types'
        )
        .addTarget(
          u.addTargetSchema(
            'count(ceph_bluefs_wal_total_bytes)', 1, 'time_series', 'bluestore'
          )
        )
        .addTarget(
          u.addTargetSchema(
            'count(ceph_osd_metadata) - count(ceph_bluefs_wal_total_bytes)', 1, 'time_series', 'filestore'
          )
        )
        .addTarget(
          u.addTargetSchema(
            'absent(ceph_bluefs_wal_total_bytes)*count(ceph_osd_metadata)', 1, 'time_series', 'filestore'
          )
        ) + { gridPos: { x: 4, y: 8, w: 4, h: 8 } },
        OsdOverviewPieChartPanel(
          {}, 'The pie chart shows the various OSD sizes used within the cluster', 'OSD Size Summary'
        )
        .addTarget(u.addTargetSchema(
          'count(ceph_osd_stat_bytes < 1099511627776)', 1, 'time_series', '<1TB'
        ))
        .addTarget(u.addTargetSchema(
          'count(ceph_osd_stat_bytes >= 1099511627776 < 2199023255552)', 1, 'time_series', '<2TB'
        ))
        .addTarget(u.addTargetSchema(
          'count(ceph_osd_stat_bytes >= 2199023255552 < 3298534883328)', 1, 'time_series', '<3TB'
        ))
        .addTarget(u.addTargetSchema(
          'count(ceph_osd_stat_bytes >= 3298534883328 < 4398046511104)', 1, 'time_series', '<4TB'
        ))
        .addTarget(u.addTargetSchema(
          'count(ceph_osd_stat_bytes >= 4398046511104 < 6597069766656)', 1, 'time_series', '<6TB'
        ))
        .addTarget(u.addTargetSchema(
          'count(ceph_osd_stat_bytes >= 6597069766656 < 8796093022208)', 1, 'time_series', '<8TB'
        ))
        .addTarget(u.addTargetSchema(
          'count(ceph_osd_stat_bytes >= 8796093022208 < 10995116277760)', 1, 'time_series', '<10TB'
        ))
        .addTarget(u.addTargetSchema(
          'count(ceph_osd_stat_bytes >= 10995116277760 < 13194139533312)', 1, 'time_series', '<12TB'
        ))
        .addTarget(u.addTargetSchema(
          'count(ceph_osd_stat_bytes >= 13194139533312)', 1, 'time_series', '<12TB+'
        )) + { gridPos: { x: 8, y: 8, w: 4, h: 8 } },
        g.graphPanel.new(bars=true,
                         datasource='$datasource',
                         title='Distribution of PGs per OSD',
                         x_axis_buckets=20,
                         x_axis_mode='histogram',
                         x_axis_values=['total'],
                         formatY1='short',
                         formatY2='short',
                         labelY1='# of OSDs',
                         min='0',
                         nullPointMode='null')
        .addTarget(u.addTargetSchema(
          'ceph_osd_numpg\n', 1, 'time_series', 'PGs per OSD'
        )) + { gridPos: { x: 12, y: 8, w: 12, h: 8 } },
        u.addRowSchema(false,
                       true,
                       'R/W Profile') + { gridPos: { x: 0, y: 16, w: 24, h: 1 } },
        OsdOverviewGraphPanel(
          {},
          'Read/Write Profile',
          'Show the read/write workload profile overtime',
          'short',
          null,
          null,
          'round(sum(irate(ceph_pool_rd[30s])))',
          'Reads',
          0,
          17,
          24,
          8
        )
        .addTargets([u.addTargetSchema(
          'round(sum(irate(ceph_pool_wr[30s])))', 1, 'time_series', 'Writes'
        )]),
      ]),
    'osd-device-details.json':
      local OsdDeviceDetailsPanel(title,
                                  description,
                                  formatY1,
                                  labelY1,
                                  expr1,
                                  expr2,
                                  legendFormat1,
                                  legendFormat2,
                                  x,
                                  y,
                                  w,
                                  h) =
        u.graphPanelSchema({},
                           title,
                           description,
                           'null',
                           false,
                           formatY1,
                           'short',
                           labelY1,
                           null,
                           null,
                           1,
                           '$datasource')
        .addTargets(
          [
            u.addTargetSchema(expr1,
                              1,
                              'time_series',
                              legendFormat1),
            u.addTargetSchema(expr2, 1, 'time_series', legendFormat2),
          ]
        ) + { gridPos: { x: x, y: y, w: w, h: h } };

      u.dashboardSchema(
        'OSD device details',
        '',
        'CrAHE0iZz',
        'now-3h',
        '',
        16,
        [],
        '',
        {
          refresh_intervals: ['5s', '10s', '30s', '1m', '5m', '15m', '30m', '1h', '2h', '1d'],
          time_options: ['5m', '15m', '1h', '6h', '12h', '24h', '2d', '7d', '30d'],
        }
      )
      .addAnnotation(
        u.addAnnotationSchema(
          1,
          '-- Grafana --',
          true,
          true,
          'rgba(0, 211, 255, 1)',
          'Annotations & Alerts',
          'dashboard'
        )
      )
      .addRequired(
        type='grafana', id='grafana', name='Grafana', version='5.3.2'
      )
      .addRequired(
        type='panel', id='graph', name='Graph', version='5.0.0'
      )
      .addTemplate(
        g.template.datasource('datasource',
                              'prometheus',
                              'default',
                              label='Data Source')
      )
      .addTemplate(
        u.addTemplateSchema('osd',
                            '$datasource',
                            'label_values(ceph_osd_metadata,ceph_daemon)',
                            1,
                            false,
                            1,
                            'OSD',
                            '(.*)')
      )
      .addPanels([
        u.addRowSchema(
          false, true, 'OSD Performance'
        ) + { gridPos: { x: 0, y: 0, w: 24, h: 1 } },
        OsdDeviceDetailsPanel(
          '$osd Latency',
          '',
          's',
          'Read (-) / Write (+)',
          'irate(ceph_osd_op_r_latency_sum{ceph_daemon=~"$osd"}[1m]) / on (ceph_daemon) irate(ceph_osd_op_r_latency_count[1m])',
          'irate(ceph_osd_op_w_latency_sum{ceph_daemon=~"$osd"}[1m]) / on (ceph_daemon) irate(ceph_osd_op_w_latency_count[1m])',
          'read',
          'write',
          0,
          1,
          6,
          9
        )
        .addSeriesOverride(
          {
            alias: 'read',
            transform: 'negative-Y',
          }
        ),
        OsdDeviceDetailsPanel(
          '$osd R/W IOPS',
          '',
          'short',
          'Read (-) / Write (+)',
          'irate(ceph_osd_op_r{ceph_daemon=~"$osd"}[1m])',
          'irate(ceph_osd_op_w{ceph_daemon=~"$osd"}[1m])',
          'Reads',
          'Writes',
          6,
          1,
          6,
          9
        )
        .addSeriesOverride(
          { alias: 'Reads', transform: 'negative-Y' }
        ),
        OsdDeviceDetailsPanel(
          '$osd R/W Bytes',
          '',
          'bytes',
          'Read (-) / Write (+)',
          'irate(ceph_osd_op_r_out_bytes{ceph_daemon=~"$osd"}[1m])',
          'irate(ceph_osd_op_w_in_bytes{ceph_daemon=~"$osd"}[1m])',
          'Read Bytes',
          'Write Bytes',
          12,
          1,
          6,
          9
        )
        .addSeriesOverride({ alias: 'Read Bytes', transform: 'negative-Y' }),
        u.addRowSchema(
          false, true, 'Physical Device Performance'
        ) + { gridPos: { x: 0, y: 10, w: 24, h: 1 } },
        OsdDeviceDetailsPanel(
          'Physical Device Latency for $osd',
          '',
          's',
          'Read (-) / Write (+)',
          '(label_replace(irate(node_disk_read_time_seconds_total[1m]) / irate(node_disk_reads_completed_total[1m]), "instance", "$1", "instance", "([^:.]*).*") and on (instance, device) label_replace(label_replace(ceph_disk_occupation{ceph_daemon=~"$osd"}, "device", "$1", "device", "/dev/(.*)"), "instance", "$1", "instance", "([^:.]*).*"))',
          '(label_replace(irate(node_disk_write_time_seconds_total[1m]) / irate(node_disk_writes_completed_total[1m]), "instance", "$1", "instance", "([^:.]*).*") and on (instance, device) label_replace(label_replace(ceph_disk_occupation{ceph_daemon=~"$osd"}, "device", "$1", "device", "/dev/(.*)"), "instance", "$1", "instance", "([^:.]*).*"))',
          '{{instance}}/{{device}} Reads',
          '{{instance}}/{{device}} Writes',
          0,
          11,
          6,
          9
        )
        .addSeriesOverride(
          { alias: '/.*Reads/', transform: 'negative-Y' }
        ),
        OsdDeviceDetailsPanel(
          'Physical Device R/W IOPS for $osd',
          '',
          'short',
          'Read (-) / Write (+)',
          'label_replace(irate(node_disk_writes_completed_total[1m]), "instance", "$1", "instance", "([^:.]*).*") and on (instance, device) label_replace(label_replace(ceph_disk_occupation{ceph_daemon=~"$osd"}, "device", "$1", "device", "/dev/(.*)"), "instance", "$1", "instance", "([^:.]*).*")',
          'label_replace(irate(node_disk_reads_completed_total[1m]), "instance", "$1", "instance", "([^:.]*).*") and on (instance, device) label_replace(label_replace(ceph_disk_occupation{ceph_daemon=~"$osd"}, "device", "$1", "device", "/dev/(.*)"), "instance", "$1", "instance", "([^:.]*).*")',
          '{{device}} on {{instance}} Writes',
          '{{device}} on {{instance}} Reads',
          6,
          11,
          6,
          9
        )
        .addSeriesOverride(
          { alias: '/.*Reads/', transform: 'negative-Y' }
        ),
        OsdDeviceDetailsPanel(
          'Physical Device R/W Bytes for $osd',
          '',
          'Bps',
          'Read (-) / Write (+)',
          'label_replace(irate(node_disk_read_bytes_total[1m]), "instance", "$1", "instance", "([^:.]*).*") and on (instance, device) label_replace(label_replace(ceph_disk_occupation{ceph_daemon=~"$osd"}, "device", "$1", "device", "/dev/(.*)"), "instance", "$1", "instance", "([^:.]*).*")',
          'label_replace(irate(node_disk_written_bytes_total[1m]), "instance", "$1", "instance", "([^:.]*).*") and on (instance, device) label_replace(label_replace(ceph_disk_occupation{ceph_daemon=~"$osd"}, "device", "$1", "device", "/dev/(.*)"), "instance", "$1", "instance", "([^:.]*).*")',
          '{{instance}} {{device}} Reads',
          '{{instance}} {{device}} Writes',
          12,
          11,
          6,
          9
        )
        .addSeriesOverride(
          { alias: '/.*Reads/', transform: 'negative-Y' }
        ),
        u.graphPanelSchema(
          {},
          'Physical Device Util% for $osd',
          '',
          'null',
          false,
          'percentunit',
          'short',
          null,
          null,
          null,
          1,
          '$datasource'
        )
        .addTarget(u.addTargetSchema(
          'label_replace(irate(node_disk_io_time_seconds_total[1m]), "instance", "$1", "instance", "([^:.]*).*") and on (instance, device) label_replace(label_replace(ceph_disk_occupation{ceph_daemon=~"$osd"}, "device", "$1", "device", "/dev/(.*)"), "instance", "$1", "instance", "([^:.]*).*")', 1, 'time_series', '{{device}} on {{instance}}'
        )) + { gridPos: { x: 18, y: 11, w: 6, h: 9 } },
      ]),
  },
}
