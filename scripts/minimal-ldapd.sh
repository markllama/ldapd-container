#!/bin/bash
# ----------------------------------------
# Build a container for dhcpd from scratch
# ----------------------------------------

# To tag and publish the image
# buildah tag localhost/dhcpd quay.io/markllama/dhcpd
# buildah push quay.io/markllama/dhcpd

# Stop on any error 
set -o errexit

SCRIPT=$0

OPT_SPEC='a:b:c:s:r:'

DEFAULT_SERVICE="slapd"
DEFAULT_SOURCE_ROOT="workdir/model"
DEFAULT_AUTHOR="Mark Lamourine <markllama@gmail.com>"
DEFAULT_BUILDER="Mark Lamourine <markllama@gmail.com>"

: SERVICE="${SERVICE:=${DEFAULT_SERVICE}}"
: SOURCE_ROOT="${SOURCE_ROOT:=${DEFAULT_SOURCE_ROOT}/${SERVICE}}"
: AUTHOR="${AUTHOR:=${DEFAULT_AUTHOR}}"
: BUILDER="${BUILDER:=${DEFAULT_BUILDER}}"

function main() {

    parse_args $*

    if [ -z "${BUILDAH_ISOLATION}" -o -z "${CONTAINER_ID}" ] ; then
	# Create a container
	local container=$(buildah from --name $SERVICE scratch)

	if [ -z "${BUILDAH_ISOLATION}" ] ; then
	    # Run the file copy in an unshare environement
	    buildah unshare bash $0 -c ${container} -s ${SOURCE_ROOT}
	else
	    # Aldready in an unshare environment
	    copy_model_tree ${SOURCE_ROOT} ${container}
	fi
	
	# add a volume to include the configuration file
	# Leave the files in the default locations 
	# - buildah config --volume /etc/dhcp/dhcpd.conf $container
	# - buildah config --volume /var/lib/dhcpd $container

	# # open ports for listening
	buildah config --port 389/tcp ${container}

	# # Define the startup command
	buildah config --cmd "/usr/sbin/slapd -d" $container

	buildah config --author "${AUTHOR}" $container
	buildah config --created-by "${BUILDER}" $container
	buildah config --annotation description="OpenLDAP Server" $container
	buildah config --annotation license="MPL-2.0" $container

	# # Save the container to an image
	buildah commit --squash $container $SERVICE

	buildah tag localhost/slapd quay.io/markllama/slapd

	podman rm ${SERVICE}

    else
	# Only the copy needs to happen in an unshare environment
	copy_model_tree ${SOURCE_ROOT} ${CONTAINERb=_ID}
    fi
}

function copy_model_tree() {
    local source_root=$1
    local container_id=$2
    
    # Access the container file space
    local mountpoint=$(buildah mount $container_id)

    # Create the model directory tree
    (cd ${source_root} ; find * -type d) | xargs -I{} mkdir -p ${mountpoint}/{}
    [ -z "${DEBUG}" ] || ls -R ${mountpoint}
    cp -r ${source_root}/* ${mountpoint}
    
    # Create volume mount points
    mkdir -p ${mountpoint}/etc/openldap/schema
    mkdir -p ${mountpoint}/etc/openldap/slapd.d
    mkdir -p ${mountpoint}/var/lib/ldap
    mkdir -p ${mountpoint}/var/run/openldap

    [ -z ${DEBUG} ] || ls -R ${mountpoint}

    # Release the container file space
    buildah unmount ${container_id}
}

function parse_args() {
    local opt
    
    while getopts "${OPT_SPEC}" opt; do
	case "${opt}" in
	    a)
		AUTHOR=${OPTARG}
		;;
	    b)
		BUILDER=${OPTARG}
		;;
	    c)
		CONTAINER_ID=${OPTARG}
		;;
	    s)
		SERVICE=${OPTARG}
		;;
	    r)
		ROOT=${OPTARG}
		;;
	esac
    done
}

# == Call main after all functions are defined
main $*
