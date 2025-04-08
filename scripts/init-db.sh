#!/bin/sh
DEFAULT_HOST_CONF_DIR=./test/slapd.d
DEFAULT_DB_DIR=./test/ldap

: HOST_CONF_DIR=${HOST_CONF_DIR:=${DEFAULT_HOST_CONF_DIR}}
: HOST_DB_DIR=${HOST_DB_DIR:=${DEFAULT_HOST_DB_DIR}}

mkdir -p ${HOST_CONF_DIR}
mkdir -p ${HOST_DB_DIR}

podman run --name slapd-init --rm \
       -v ${HOST_CONF_DIR}:/etc/openldap/slapd.d:rw,Z \
       -v ${HOST_DB_DIR}:/var/lib/ldap:rw,Z \
       localhost/slapd \
       /usr/sbin/slapd -T add -n0 \
       -l /usr/share/openldap-servers/slapd.ldif \
       -F /etc/openldap/slapd.d/ 

