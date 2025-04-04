#!/bin/bash
#
# Create a model tree for a single binary.
#
# USAGE: bash create-model-tree.sh <binary>
# Example: bash create-model-tree.sh dhcpd
#

BINARY=$1
ARCH=$(uname -m)

# Allow overrides from environment variables
: WORKDIR_ROOT=${WORKDIR_ROOT:=./workdir}
: PACKAGE_DIR=${PACKAGE_DIR:=${WORKDIR_ROOT}/rpms}
: UNPACK_ROOT=${UNPACK_ROOT:=${WORKDIR_ROOT}/unpack}
: MODEL_ROOT=${MODEL_ROOT:=${WORKDIR_ROOT}/model/${BINARY}}

OPT_SPEC="b:dfm:p:u:w:v"

#function parse_args() {
#    echo parsing args
#    while getopts ${OPT_SPEC} as opt ; do
#	case opt in
#	    b)
#	    ;;
#	esac
#    done
#}

function main() {
    # parse_args

    # -------------------------------------------
    # Find retrieve and examine the binary
    # -------------------------------------------

    # identify daemon package
    local pkg_fullname=$(find_provider_package $BINARY ${ARCH})
    [ -z "${VERBOSE}" ] || echo "package fullname: ${pkg_fullname}" >&2
    local pkg_spec=($(parse_package_name ${pkg_fullname}))
    local pkg_name=${pkg_spec[0]}

    # download daemon package
    pull_package ${pkg_name} ${PACKAGE_DIR} ${ARCH}

    # unpack daemon package
    unpack_package ${pkg_name} ${PACKAGE_DIR} ${UNPACK_ROOT}

    # locate daemon binary within daemon package
    local binary_path=$(find_binaries ${pkg_name} ${UNPACK_ROOT} | grep ${BINARY})
    [ -z "${VERBOSE}" ] || echo "binary path: ${binary_path}" >&2

    # identify required shared libraries
    local libraries=($(find_libraries ${pkg_name} ${binary_path} ${UNPACK_ROOT}))
    [ -z "${DEBUG}" ] || echo "library files: ${libraries[@]}" >&2

    # -------------------------------------------------
    # For each shared library
    # - Find a package RPM the provides the file
    # - Then get the package name from the RPM filename
    # - Download and unpack the package
    # -------------------------------------------------

    local library_file
    declare -a library_packages
    declare -A library_records
    for library_file in ${libraries[@]} ; do
	[ -z "${VERBOSE}" ] || echo "processing library ${library_file}" >&2
	
	## identify library package
	local library_package=$(find_library_package ${library_file})
	local lib_pkg_spec=($(parse_package_name ${library_package}))
	local lib_pkg_name=${lib_pkg_spec[0]}
	library_packages+=(${lib_pkg_name})
	library_records[${library_file}]=${lib_pkg_name}
	
	[ -z "${DEBUG}" ] || echo "library package ${library_package}" >&2

	## download library package
	pull_package ${lib_pkg_name} ${PACKAGE_DIR} ${ARCH}

	## unpack library package
	unpack_package ${BINARY} ${PACKAGE_DIR} ${UNPACK_ROOT}
    done

    # Some packages provide more than one library: sort and remove duplicates
    IFS=$'\n' library_packages=($(sort -u <<<"${library_packages[@]}")) ; unset IFS

    # -------------------------------------------
    # create model root and create model symlinks
    # -------------------------------------------
    
    initialize_model_tree ${MODEL_ROOT}

    ## copy daemon binary
    copy_file ${pkg_name} ${binary_path} ${UNPACK_ROOT} ${MODEL_ROOT}

    ## Copy DB files and helpers
    copy_etc ${BINARY} ${pkg_name} ${UNPACK_ROOT} ${MODEL_ROOT}

    ## for each library
    [ -z "${DEBUG}" ] || echo "library records: ${library_records[@]}" >&2
    for library_file in "${!library_records[@]}" ; do
     	library_name=${library_records[${library_file}]}
     	[ -z "${DEBUG}" ] || echo "${library_file} : ${library_name}"

	### copy library
     	copy_file ${library_name} $(basename ${library_file}) ${UNPACK_ROOT} ${MODEL_ROOT}	
    done

}

# =====================================================================
# Functions to get and examine packages for libraries
# =====================================================================

function parse_package_name() {
    local full_name=$1

    # matches package-name-1:1.2.3-4-dist-arch
    #         package-name-1.2.3-4-dist-arch
    [[ $full_name =~ (.+)[-:]([^-]+)-(.+)\.[^.]+\.${ARCH}$ ]]

    # TODO test for failed match - ML 20250304
    local name=${BASH_REMATCH[1]}
    local version=${BASH_REMATCH[2]}
    local release=${BASH_REMATCH[3]}

    # If the name includes a tag number [-0] remove it.
    [[ ${name} =~ ^(.+)(-([[:digit:]]+))$ ]]
    if [ ${#BASH_REMATCH[@]} -ne 0 ] ; then
	name=${BASH_REMATCH[1]}
    fi
    
    echo ${name} ${version} ${release}
}

#
# Get information about a package
#
function find_provider_package() {
    local file_name=$1

    dnf --quiet provides ${file_name} 2>/dev/null | head -1 | awk '{print $1}'
}

#
# Download a package into the package directory
#
function pull_package() {
    local full_name=$1
    local pkg_dir=$2
    local arch=$3

    [ -z "${VERBOSE}" ] || echo "Getting package info: ${full_name} into ${pkg_dir}" >&2

    # create the package directory if needed
    [ -d ${pkg_dir} ] || mkdir -p ${pkg_dir}
    dnf --quiet download --arch ${arch} --destdir ${pkg_dir} ${full_name} 2>/dev/null
}

#
# Unpack a package into a working directory
#
function unpack_package() {
    local package_name=$1
    local package_root=$2
    local unpack_root=$3

    local package_path=$(ls ${package_root}/${package_name}*.rpm)
    local unpack_dir=${unpack_root}/${package_name}

    [ -z "${DEBUG}" ] || echo "unpacking package info: ${package_path} into ${unpack_dir}" >&2

    # Create the directory only if needed
    [ -d ${unpack_dir} ] || mkdir -p ${unpack_dir}
    
    # unpack only if the directory is empty
    if [ $(ls $unpack_dir | wc -l) -eq 0 ] ; then
	rpm2cpio ${package_path} | cpio -idmu --quiet --directory ${unpack_dir}
    else
	[ -z "${DEBUG}" ] || echo "already unpacked: ${package_name}"
    fi
}

# ============================================================================
# Functions for examining binaries and identifying shared library dependencies
# ============================================================================

#
# Locate executables in a file tree
# TODO: either make it actually find binaries or change the name: MAL 20250304
function find_binaries() {
    local pkg_name=$1
    local unpack_root=$2

    local unpack_dir=${unpack_root}/${pkg_name}

    [ -z "${DEBUG}" ] || echo "discovering binaries in ${unpack_dir}" >&2

    find ${unpack_dir} -type f -perm 755 | sed "s|${unpack_dir}||"
}

#
# find shared libraries linked to the specified binary
#
function find_libraries() {
    local package=$1
    local exe_name=$2
    local unpack_root=$3

    local unpack_dir=${unpack_root}/${package}
    local exe_path=${unpack_dir}${exe_name}

    [ -z "${DEBUG}" ] || echo "discovering shared libraries on ${exe_path}" >&2

    # Select Only lines with filenames and only one file path
    ldd ${exe_path} | grep / | sed 's|^[^/]*/|/|;s/ .*$//' | sort -u
}

#
# Almost like the function to find the provider of a binary, but look in two places
#
function find_library_package() {
    local library_file=$1

    [ -z "${DEBUG}" ] || echo "Finding package for library: ${library_file}" >&2

    # Some libraries are listed as /lib(64)? instead of /usr/lib(64)?
    dnf --quiet provides ${library_file} /usr${library_file} 2>/dev/null | head -1 | awk '{print $1}'
}

#
# The LDAP schema files are in LDIF format.
# They are all in the `schema` directory of the openldap-servers package
#
function copy_etc() {
    local program=$1
    local package=$2
    local unpack_root=$3
    local model_root=$4

    local etc_from=${unpack_root}/${package}/etc
    local etc_to=${model_root}/${program}

    [ -z "${DEBUG}" ] || echo "Copying ${etc_from} to ${etc_to}"
    mkdir -p ${etc_to}
    cp -r ${etc_from} ${etc_to}
}

# ==========================================================================
# Functions to build the model tree
# ==========================================================================

function initialize_model_tree() {
    local model_root=$1

    # create the root directory if needed
    [ -d ${model_root} ] || mkdir -p ${model_root}

    # Create two required symlinks
    for link_dir in lib lib64 ; do
	[ -L ${model_root}/${link_dir} ] || ln -s usr/${link_dir} ${model_root}/${link_dir}
    done
}

function symlink_target() {
    local file_path=$1
    ls -l ${file_path} | sed 's/.*-> //'
}

#
# This only works if there's only one file with this filename
#
function copy_file() {
    local pkg_name=$1
    local file_name=$2
    local src_root=$3
    local dst_root=$4

    local file_path
    case $file_name in
	/*)
	    file_path=$file_name
	    ;;
	*)
	    file_path=$(cd ${src_root}/${pkg_name} ; find * -name ${file_name})
    esac
    # If it's a relative path
    local src_file=${src_root}/${pkg_name}/${file_path}
    local dst_file=${dst_root}/${file_path}
    local dst_dir=$(dirname $dst_file)

    [ -z "${DEBUG}" ] || echo "pkg_name: ${pkg_name}"
    [ -z "${DEBUG}" ] || echo "file_name: ${file_name}"
    [ -z "${DEBUG}" ] || echo "src_root: ${src_root}"
    [ -z "${DEBUG}" ] || echo "dst_root: ${dst_root}"

    [ -z "${VERBOSE}" ] || echo "copying file from ${src_file} to ${dst_dir}"

    [ -d ${dst_dir} ] || mkdir -p ${dst_dir}
    
    # if it's a symlink, copy that
    if [ -L $src_file ] ; then
	[ -z "${DEBUG}" ] || echo "$file_name is a symlink"
	local link_target=$(symlink_target ${src_file})
	[ -z "${DEBUG}" ] || echo "$file_name -> $link_target"
	(cd ${dst_dir} ; ln -s ${link_target} ${file_name})
	src_file=$(dirname ${src_root}/${pkg_name}/${file_path})/${link_target}
	[ -z "${DEBUG}" ] || echo "copying file from ${src_file} to ${dst_dir}"
    fi

    # then copy the actual file
    cp $src_file $dst_dir
}

# =======================================================================
# Call MAIN after all functions are defined
# =======================================================================
main $*
