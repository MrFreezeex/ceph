#!/bin/sh -e

TEMPDIR=$(mktemp -d)
BASEDIR=$(dirname "$0")
OUTPUT_PATH="${BASEDIR}/output"

jsonnet -J vendor -m ${TEMPDIR} $BASEDIR/dashboards.jsonnet
jsonnet -J vendor -S $BASEDIR/alerts.jsonnet > ${TEMPDIR}/ceph_default_alerts.yml

truncate -s 0 ${TEMPDIR}/json_difference.log
truncate -s 0 ${TEMPDIR}/yaml_difference.log
for file in ${OUTPUT_PATH}/dashboards/*.json
do
    file_name="$(basename $file)"
    for generated_file in ${TEMPDIR}/*.json
    do
        generated_file_name="$(basename $generated_file)"
        if [ "$file_name" == "$generated_file_name" ]; then
            jsondiff --indent 2 "${generated_file}" "${file}" \
                | tee -a ${TEMPDIR}/json_difference.log
        fi
    done
done

diff -C 1 ${OUTPUT_PATH}/alerts/ceph_default_alerts.yml \
    ${TEMPDIR}/ceph_default_alerts.yml | tee -a ${TEMPDIR}/yaml_difference.log

err=0
if [ $(wc -l < ${TEMPDIR}/json_difference.log) -eq 0 ] && \
   [ $(wc -l < ${TEMPDIR}/yaml_difference.log) -eq 0 ]
then
    rm -rf ${TEMPDIR}
    echo "Congratulations! Grafonnet Check Passed"
else
    rm -rf ${TEMPDIR}
    echo "Grafonnet Check Failed, failed comparing generated file with existing"
    exit 1
fi
