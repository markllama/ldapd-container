#!/bin/sh
DEFAULT_SLAPD_IMAGE=quay.io/markllama/slapd
DEFAULT_HOST_CONF_DIR=./test/slapd.d
DEFAULT_HOST_DB_DIR=./test/ldap
DEFAULT_AUTH_LDIF=/var/lib/ldap/admin-auth.ldif

: SLAPD_IMAGE=${SLAPD_IMAGE:=${DEFAULT_SLAPD_IMAGE}}
: HOST_CONF_DIR=${HOST_CONF_DIR:=${DEFAULT_HOST_CONF_DIR}}
: HOST_DB_DIR=${HOST_DB_DIR:=${DEFAULT_HOST_DB_DIR}}
: AUTH_LDIF=${AUTH_LDIF:=${DEFAULT_AUTH_LDIF}}

mkdir -p ${HOST_CONF_DIR}
mkdir -p ${HOST_DB_DIR}

podman run --name slapd-init --rm \
       -v ${HOST_CONF_DIR}:/etc/openldap/slapd.d:rw,Z \
       -v ${HOST_DB_DIR}:/var/lib/ldap:rw,Z \
       ${SLAPD_IMAGE} \
       /usr/sbin/slapd -T modify \
       -l ${AUTH_LDIF} \
       -F /etc/openldap/slapd.d/
