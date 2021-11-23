#!/bin/sh -e

JSONNETS_FILES=$(find -name '*.jsonnet' -o -name '*.libsonnet')
jsonnetfmt "$@" ${JSONNETS_FILES}
