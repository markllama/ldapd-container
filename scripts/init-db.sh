#!/bin/sh
DEFAULT_SLAPD_IMAGE=quay.io/markllama/slapd
DEFAULT_HOST_CONF_DIR=./test/slapd.d
DEFAULT_HOST_DB_DIR=./test/ldap
DEFAULT_INIT_LDIF=/usr/share/openldap-servers/slapd.ldif

: SLAPD_IMAGE=${SLAPD_IMAGE:=${DEFAULT_SLAPD_IMAGE}}
: HOST_CONF_DIR=${HOST_CONF_DIR:=${DEFAULT_HOST_CONF_DIR}}
: HOST_DB_DIR=${HOST_DB_DIR:=${DEFAULT_HOST_DB_DIR}}
: INIT_LDIF=${INIT_LDIF:=${DEFAULT_INIT_LDIF}}

mkdir -p ${HOST_CONF_DIR}
mkdir -p ${HOST_DB_DIR}

podman run --name slapd-init --rm \
       -v ${HOST_CONF_DIR}:/etc/openldap/slapd.d:rw,Z \
       -v ${HOST_DB_DIR}:/var/lib/ldap:rw,Z \
       localhost/slapd \
       /usr/sbin/slapd -T add -n0 \
       -l ${INIT_LDIF} \
       -F /etc/openldap/slapd.d/
