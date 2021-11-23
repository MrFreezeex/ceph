if(WITH_GRAFANA)
  include(AddCephTest)
  set(CEPH_GRAFANA_DASHBOARDS_DIR "${CMAKE_INSTALL_SYSCONFDIR}/grafana/dashboards/ceph-dashboard"
    CACHE PATH "Location for grafana dashboards")
  file(GLOB CEPH_GRAFANA_DASHBOARDS "output/dashboards/*.json")
  install(FILES
    ${CEPH_GRAFANA_DASHBOARDS}
    DESTINATION ${CEPH_GRAFANA_DASHBOARDS_DIR})

  set(CEPH_BUILD_VIRTUALENV $ENV{TMPDIR})
  if(NOT CEPH_BUILD_VIRTUALENV)
    set(CEPH_BUILD_VIRTUALENV ${CMAKE_BINARY_DIR})
    add_tox_test(grafana-check TOX_ENVS grafonnet-check)
    add_tox_test(grafana-query-test TOX_ENVS promql-query-test)
    add_tox_test(grafana-lint TOX_ENVS lint)
    add_tox_test(jsonnet-lint TOX_ENVS jsonnet-lint)
  endif()
endif()

