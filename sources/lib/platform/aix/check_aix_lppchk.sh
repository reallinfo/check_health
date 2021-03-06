#!/usr/bin/env ksh
#******************************************************************************
# @(#) check_aix_lppchk.sh
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
# @(#) MAIN: check_aix_lppchk
# DOES: see _show_usage()
# EXPECTS: n/a
# REQUIRES: data_space2comma(), init_hc(), log_hc()
#
# @(#) HISTORY:
# @(#) 2013-05-17: initial version [Patrick Van der Veken]
# -----------------------------------------------------------------------------
# DO NOT CHANGE THIS FILE UNLESS YOU KNOW WHAT YOU ARE DOING!
#******************************************************************************

# -----------------------------------------------------------------------------
function check_aix_lppchk
{
# ------------------------- CONFIGURATION starts here -------------------------
typeset _VERSION="2013-05-17"                           # YYYY-MM-DD
typeset _SUPPORTED_PLATFORMS="AIX"                      # uname -s match
# ------------------------- CONFIGURATION ends here ---------------------------

# set defaults
(( ARG_DEBUG != 0 && ARG_DEBUG_LEVEL > 0 )) && set ${DEBUG_OPTS}
init_hc "$0" "${_SUPPORTED_PLATFORMS}" "${_VERSION}"
typeset _ARGS=$(data_space2comma "$*")
typeset _ARG=""
typeset _MSG=""
typeset _STC=0

# handle arguments (originally comma-separated)
for _ARG in ${_ARGS}
do
    case "${_ARG}" in
        help)
            _show_usage $0 ${_VERSION} ${_CONFIG_FILE} && return 0
            ;;  
    esac
done

# collect data
lppchk -v -m1 >>${HC_STDOUT_LOG} 2>>${HC_STDERR_LOG}
(( $? == 0)) || return $?

# perform check
if [[ -s ${HC_STDOUT_LOG} ]]
then
    _MSG="lppchk detected errors {lppchk -v -m1}"
    _STC=1
else
    _MSG="lppchk passed without errors"
fi

# handle results
log_hc "$0" ${_STC} "${_MSG}"

return 0
}

# -----------------------------------------------------------------------------
function _show_usage
{
cat <<- EOT
NAME    : $1
VERSION : $2
CONFIG  : $3
PURPOSE : Run {lppchk -v}

EOT

return 0
}

#******************************************************************************
# END of script
#******************************************************************************
