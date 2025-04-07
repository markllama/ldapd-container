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
    verbose "package fullname: ${pkg_fullname}" >&2
    local pkg_spec=($(parse_package_name ${pkg_fullname}))
    local pkg_name=${pkg_spec[0]}

    # download daemon package
    pull_package ${pkg_name} ${PACKAGE_DIR} ${ARCH}

    # unpack daemon package
    unpack_package ${pkg_name} ${PACKAGE_DIR} ${UNPACK_ROOT}

    # locate daemon binary within daemon package
    local binary_path=$(find_binaries ${pkg_name} ${UNPACK_ROOT} | grep ${BINARY})
    verbose "binary path: ${binary_path}" >&2

    # identify required shared libraries
    local libraries=($(find_libraries ${pkg_name} ${binary_path} ${UNPACK_ROOT}))
    debug "library files: ${libraries[@]}" >&2

    # Side effect - creates array library_records[]
    # unpack_libraries ${libraries[@]}
    local library_file
    declare -a library_packages
    declare -A library_records
    for library_file in ${libraries[@]} ; do
	verbose "processing library ${library_file}" >&2
	
	## identify library package
	local library_package=$(find_library_package ${library_file})
	local lib_pkg_spec=($(parse_package_name ${library_package}))
	local lib_pkg_name=${lib_pkg_spec[0]}
	library_packages+=(${lib_pkg_name})
	library_records[${library_file}]=${lib_pkg_name}
	
	debug "library package ${library_package}" >&2

	## download library package
	pull_package ${lib_pkg_name} ${PACKAGE_DIR} ${ARCH}

	## unpack library package
	unpack_package ${lib_pkg_name} ${PACKAGE_DIR} ${UNPACK_ROOT}
    done

    # Some packages provide more than one library: sort and remove duplicates
    IFS=$'\n' library_packages=($(sort -u <<<"${library_packages[@]}")) ; unset IFS

    debug "DEBUG library records: ${library_records[@]}" >&2
    
    # -------------------------------------------
    # create model root and create model symlinks
    # -------------------------------------------
    
    initialize_model_tree ${MODEL_ROOT}

    ## copy daemon binary
    copy_file ${pkg_name} ${binary_path} ${UNPACK_ROOT} ${MODEL_ROOT}

    ## copy symlinks to the binary
    #copy_symlinks ${pkg_name} ${binary_path} ${UNPACK_ROOT} ${MODEL_ROOT}
    mkdir -p ${MODEL_ROOT}/usr/lib
    mkdir -p ${MODEL_ROOT}/usr/lib64
    mkdir -p ${MODEL_ROOT}/usr/share

    cp -r ${UNPACK_ROOT}/${pkg_name}/etc ${MODEL_ROOT}
    cp -r ${UNPACK_ROOT}/${pkg_name}/usr/lib64/openldap ${MODEL_ROOT}/usr/lib64
    cp -r ${UNPACK_ROOT}/${pkg_name}/usr/libexec ${MODEL_ROOT}/usr
    cp -r ${UNPACK_ROOT}/${pkg_name}/var ${MODEL_ROOT}
    cp -r ${UNPACK_ROOT}/${pkg_name}/usr/share/openldap-servers ${MODEL_ROOT}/usr/share

    ## Copy DB files and helpers
    #copy_etc ${pkg_name} ${UNPACK_ROOT} ${MODEL_ROOT}

    ## for each library
    debug "library records: ${library_records[@]}" >&2
    for library_file in "${!library_records[@]}" ; do
     	library_name=${library_records[${library_file}]}
     	debug "${library_file} : ${library_name}"

	### copy library
     	copy_file ${library_name} $(basename ${library_file}) ${UNPACK_ROOT} ${MODEL_ROOT}	
    done    
}

function debug() {
    [ -z "${DEBUG}" ] || echo "DEBUG: $*"
}

function verbose() {
    [ -z "${VERBOSE}" ] || echo $*
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

    verbose "Getting package info: ${full_name} into ${pkg_dir}" >&2

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

    debug "unpacking package info: ${package_path} into ${unpack_dir}" >&2

    # Create the directory only if needed
    [ -d ${unpack_dir} ] || mkdir -p ${unpack_dir}
    
    # unpack only if the directory is empty
    if [ $(ls $unpack_dir | wc -l) -eq 0 ] ; then
	rpm2cpio ${package_path} | cpio -idmu --quiet --directory ${unpack_dir}
    else
	debug "already unpacked: ${package_name}"
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

    debug "discovering binaries in ${unpack_dir}" >&2

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

    debug "discovering shared libraries on ${exe_path}" >&2

    # Select Only lines with filenames and only one file path
    ldd ${exe_path} | grep / | sed 's|^[^/]*/|/|;s/ .*$//' | sort -u
}

#
# Almost like the function to find the provider of a binary, but look in two places
#
function find_library_package() {
    local library_file=$1

    debug "Finding package for library: ${library_file}" >&2

    # Some libraries are listed as /lib(64)? instead of /usr/lib(64)?
    dnf --quiet provides ${library_file} /usr${library_file} 2>/dev/null | head -1 | awk '{print $1}'
}

function unpack_libraries() {
    # -------------------------------------------------
    # For each shared library
    # - Find a package RPM the provides the file
    # - Then get the package name from the RPM filename
    # - Download and unpack the package
    # -------------------------------------------------
    local libraries=($*)
    
    local library_file
    declare -a library_packages
    declare -A library_records
    for library_file in ${libraries[@]} ; do
	verbose "processing library ${library_file}" >&2
	
	## identify library package
	local library_package=$(find_library_package ${library_file})
	local lib_pkg_spec=($(parse_package_name ${library_package}))
	local lib_pkg_name=${lib_pkg_spec[0]}
	library_packages+=(${lib_pkg_name})
	library_records[${library_file}]=${lib_pkg_name}
	
	debug "library package ${library_package}" >&2

	## download library package
	pull_package ${lib_pkg_name} ${PACKAGE_DIR} ${ARCH}

	## unpack library package
	unpack_package ${lib_pkg_name} ${PACKAGE_DIR} ${UNPACK_ROOT}
    done

    # Some packages provide more than one library: sort and remove duplicates
    IFS=$'\n' library_packages=($(sort -u <<<"${library_packages[@]}")) ; unset IFS

    echo ${library_packages[@]}
}
#
# The LDAP schema files are in LDIF format.
# They are all in the `schema` directory of the openldap-servers package
#
function copy_etc() {
    local package=$1
    local unpack_root=$2
    local model_root=$3

    local etc_src=${unpack_root}/${package}/etc

    debug "DEBUG: copy etc dir ${etc_src} to ${model_root}"
    mkdir -p ${model_root}
    cp -r ${etc_src} ${model_root}
}

function initialize_etc() {
    local model_root=$1

    mkdir -p ${model_root}/etc/openldap/slapd.d
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

    debug "pkg_name: ${pkg_name}"
    debug "file_name: ${file_name}"
    debug "src_root: ${src_root}"
    debug "dst_root: ${dst_root}"

    verbose "copying file from ${src_file} to ${dst_dir}"

    [ -d ${dst_dir} ] || mkdir -p ${dst_dir}
    
    # if it's a symlink, copy that
    if [ -L $src_file ] ; then
	debug "$file_name is a symlink"
	local link_target=$(symlink_target ${src_file})
	debug "$file_name -> $link_target"
	(cd ${dst_dir} ; ln -s ${link_target} ${file_name})
	src_file=$(dirname ${src_root}/${pkg_name}/${file_path})/${link_target}
	debug "copying file from ${src_file} to ${dst_dir}"
    fi

    # then copy the actual file
    cp $src_file $dst_dir
}

function copy_symlinks() {
    local pkg_name=$1
    local file_name=$2
    local src_root=$3
    local dst_root=$4
    
    #debug "pkg_name = ${pkg_name}"
    #debug "file_name = ${file_name}"
    #debug "src_root = ${src_root}"
    #debug "dst_root = ${dst_root}"

    # Find any symlinks in the same directory as the binary
    local search_dir=$(dirname ${file_name} | sed 's|^/||')
    local binary=$(basename ${file_name})
    debug "search_dir = ${search_dir}"
    debug "binary = ${binary}"

    local links=($(cd ${src_root}/${pkg_name} ; find ${search_dir} -type l | xargs ls -l | sed -E 's/.* (\S+) -> (\w+)/\1/'))
    debug "links = ${links[@]}"

    local link
    for link in ${links[@]} ; do
	ln -s ${binary} ${dst_root}/${link}
    done
}
# =======================================================================
# Call MAIN after all functions are defined
# =======================================================================
main $*
