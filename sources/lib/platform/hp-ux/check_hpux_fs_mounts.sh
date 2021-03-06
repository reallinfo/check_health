#!/usr/bin/env ksh
#******************************************************************************
# @(#) check_hpux_fs_mounts.sh
#******************************************************************************
# @(#) Copyright (C) 2014 by KUDOS BVBA (info@kudos.be).  All rights reserved.
#
# This program is a free software; you can redistribute it and/or modify
# it under the same terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details
#******************************************************************************
#
# DOCUMENTATION (MAIN)
# -----------------------------------------------------------------------------
# @(#) MAIN: check_hpux_fs_mounts
# DOES: see _show_usage()
# EXPECTS: n/a
# REQUIRES: data_space2comma(), init_hc(), log_hc()
#
# @(#) HISTORY:
# @(#) 2013-05-27: initial version [Patrick Van der Veken]
# @(#) 2016-04-04: exclude dump/swap spaces (...) [Patrick Van der Veken]
# @(#) 2016-07-04: fix for nfs exclusion [Patrick Van der Veken]
# -----------------------------------------------------------------------------
# DO NOT CHANGE THIS FILE UNLESS YOU KNOW WHAT YOU ARE DOING!
#******************************************************************************

# -----------------------------------------------------------------------------
function check_hpux_fs_mounts
{
# ------------------------- CONFIGURATION starts here -------------------------
typeset _VERSION="2016-07-04"                           # YYYY-MM-DD
typeset _SUPPORTED_PLATFORMS="HP-UX"                    # uname -s match
# ------------------------- CONFIGURATION ends here ---------------------------

# set defaults
(( ARG_DEBUG != 0 && ARG_DEBUG_LEVEL > 0 )) && set ${DEBUG_OPTS}
init_hc "$0" "${_SUPPORTED_PLATFORMS}" "${_VERSION}"
typeset _ARGS=$(data_space2comma "$*")
typeset _ARG=""
typeset _MSG=""
typeset _STC=0
typeset _FS=""
typeset _FS_COUNT=0

# handle arguments (originally comma-separated)
for _ARG in ${_ARGS}
do
    case "${_ARG}" in
        help)
            _show_usage $0 ${_VERSION} ${_CONFIG_FILE} && return 0
            ;;  
    esac
done

# collect data (mount only)
mount >>${HC_STDOUT_LOG} 2>>${HC_STDERR_LOG}
(( $? == 0)) || return $?

# check for each auto-mount configured file system (except / and dump/swap)
grep -v -E -e '^#' -e '^$' \
    -e '[[:space:]]*\/[[:space:]]+' -e '\.\.\.' /etc/fstab 2>/dev/null |\
    awk '{print $2}' |\
while read _FS
do
    _FS_COUNT=$(grep -c -E -e "^${_FS}[ \t]+on.*[ \t]+" ${HC_STDOUT_LOG} 2>/dev/null)
    case ${_FS_COUNT} in
        0)
            _MSG="${_FS} is not mounted"
            _STC=1
            ;;
        1)
            _MSG="${_FS} is mounted"
            ;;
        *)
            _MSG="${_FS} is multiple times mounted?"
            ;;              
    esac
    
    # handle unit result
    log_hc "$0" ${_STC} "${_MSG}"
    _STC=0
done

# add /etc/fstab to STDOUT log
cat /etc/fstab >>${HC_STDOUT_LOG} 

return 0
}

# -----------------------------------------------------------------------------
function _show_usage
{
cat <<- EOT
NAME    : $1
VERSION : $2
CONFIG  : $3
PURPOSE : Checks whether file systems are mounted or not

EOT

return 0
}

#******************************************************************************
# END of script
#******************************************************************************
