#!/usr/bin/env ksh
#******************************************************************************
# @(#) check_hpux_file_age.sh
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
# @(#) MAIN: check_hpux_file_age
# DOES: see _show_usage()
# EXPECTS: see _show_usage()
# REQUIRES: data_space2comma(), init_hc(), log_hc()
#
# @(#) HISTORY:
# @(#) 2013-05-27: initial version [Patrick Van der Veken]
# @(#) 2013-05-29: added local trap for cleanup [Patrick Van der Veken]
# -----------------------------------------------------------------------------
# DO NOT CHANGE THIS FILE UNLESS YOU KNOW WHAT YOU ARE DOING!
#******************************************************************************

# -----------------------------------------------------------------------------
function check_hpux_file_age
{
# ------------------------- CONFIGURATION starts here -------------------------
typeset _CONFIG_FILE="${CONFIG_DIR}/$0.conf"
typeset _VERSION="2013-05-29"                           # YYYY-MM-DD
typeset _SUPPORTED_PLATFORMS="HP-UX"                    # uname -s match
# ------------------------- CONFIGURATION ends here ---------------------------

# set defaults
(( ARG_DEBUG != 0 && ARG_DEBUG_LEVEL > 0 )) && set ${DEBUG_OPTS}
init_hc "$0" "${_SUPPORTED_PLATFORMS}" "${_VERSION}"
typeset _ARGS=$(data_space2comma "$*")
typeset _ARG=""
typeset _MSG=""
typeset _STC=0
typeset _REF_FILE="${TMP_DIR}/.$0.ref.$$"
typeset _DO_REF=0
typeset _ENTRY=""
typeset _REF_TIME=""
typeset _AGE_CHECK==""
typeset _FILE_PATH=""
typeset _FILE_AGE=""
typeset _FILE_NAME=""
typeset _FILE_DIR=""

# set local trap for cleanup
trap "[[ -f ${_REF_FILE} ]] && rm -f ${_REF_FILE} >/dev/null 2>&1; return 1" 1 2 3 15

# handle arguments (originally comma-separated)
for _ARG in ${_ARGS}
do
    case "${_ARG}" in
        help)
            _show_usage $0 ${_VERSION} ${_CONFIG_FILE} && return 0
            ;;  
    esac
done

# handle configuration file
[[ -n "${ARG_CONFIG_FILE}" ]] && _CONFIG_FILE="${ARG_CONFIG_FILE}"
if [[ ! -r ${_CONFIG_FILE} ]] 
then
    warn "unable to read configuration file at ${_CONFIG_FILE}"
    return 1
fi
    
# perform check
cat ${_CONFIG_FILE} | grep -v -E -e '^$' -e '^#' | while read _ENTRY
do
    # field split
    _FILE_PATH=$(print "${_ENTRY%%;*}")
    _FILE_AGE=$(print "${_ENTRY##*;}")
    
    # split file/dir
    _FILE_NAME=$(print "${_FILE_PATH##*/}") 
    _FILE_DIR=$(print "${_FILE_PATH%/*}")  
    
    # check config
    if [ \( -z "${_FILE_PATH}" \) -a \( -z "${_FILE_AGE}" \) ]
    then
        warn "missing values in configuration file at ${_CONFIG_FILE}"
        return 1        
    fi
    case "${_FILE_AGE}" in
        +([0-9])*(.)*([0-9]))
            # numeric, OK
            ;;
        *) 
            # not numeric
            warn "invalid file age value '${_FILE_AGE}' in configuration file at ${_CONFIG_FILE}"
            return 1 
            ;;
    esac
 
    # calculate reference timestamp & set reference file (once only)
    if (( _DO_REF == 0 ))
    then
        REF_TIME=$(perl -e "use POSIX;\$t=time-(${_FILE_AGE}*60);print(strftime '%m%d%H%M',localtime(\$t))")
        if (( $? != 0 ))
        then
            warn "failed to query reference time (Perl)"
            return 1       
        fi
        touch -amt "${REF_TIME}" ${_REF_FILE} >>${HC_STDOUT_LOG} 2>>${HC_STDERR_LOG}
        if (( $? != 0 ))
        then
            warn "failed to create reference time ${TMP_DIR}"
            return 1       
        fi
        _DO_REF=1
    fi
sleep 60    
    # perform check
    if [[ ! -r "${_FILE_PATH}" ]]
    then
        _MSG="unable to read or access requested file at ${_FILE_PATH}"
        _STC=1        
    else
        # age check
        AGE_CHECK=$(find "${_FILE_DIR}" -type f -name "${_FILE_NAME}" -newer ${_REF_FILE})
        if (( $? != 0 ))
        then
            warn "unable to execute file age test for ${_FILE_PATH}"
            return 1        
        fi
        if [[ -z "${AGE_CHECK}" ]]
        then
            _MSG="file age of ${_FILE_AGE} has expired on ${_FILE_PATH}"
            _STC=1
        else
            _MSG="file age of ${_FILE_AGE} has not expired on ${_FILE_PATH}"
        fi
    fi
    
    # handle unit result
    log_hc "$0" ${_STC} "${_MSG}"
    _STC=0
done

# remove reference file
[[ -f ${_REF_FILE} ]] & rm -f ${_REF_FILE} >/dev/null 2>&1

return 0
}

# -----------------------------------------------------------------------------
function _show_usage
{
cat <<- EOT
NAME    : $1
VERSION : $2
CONFIG  : $3 with:
            <file_name>;<maximum_age_in_minutes>
PURPOSE : Checks whether given files have been changed in the last n minutes
          (requires perl!)

EOT

return 0
}

#******************************************************************************
# END of script
#******************************************************************************
