#!/bin/bash
DEFAULT_HOST_CONF_DIR=./test/slapd.d
DEFAULT_HOST_DB_DIR=./test/ldap

: HOST_CONF_DIR=${HOST_CONF_DIR:=${DEFAULT_HOST_CONF_DIR}}
: HOST_DB_DIR=${HOST_DB_DIR:=${DEFAULT_HOST_DB_DIR}}

podman run --name slapd -d  \
       --privileged --network=host --ipc=host \
       --expose=389/tcp \
       -v ${HOST_CONF_DIR}:/etc/openldap/slapd.d:rw,Z \
       -v ${HOST_DB_DIR}:/var/lib/ldap:rw,Z \
       quay.io/markllama/slapd
