#!/usr/bin/env ksh
#******************************************************************************
# @(#) check_health.sh
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
# @(#) MAIN: check_health.sh
# DOES: performs simple health checks on UNIX hosts. Individual checks are
#       contained in separate KSH functions (aka plug-ins)
# EXPECTS: (see --help for more options)
# REQUIRES: ksh88/93 (mksh/pdksh will probably work too but YMMV)
#           build_fpath(), check_config(), check_core(), check_lock_dir(),
#           check_params(), check_platform(), check_user(), check_shell(),
#           display_usage(), do_cleanup, fix_symlinks(), read_config()
#           + include functions
#           For other pre-requisites see the documentation in display_usage()
# REQUIRES (OPTIONAL): display_csv(), display_terse(), display_init(),
#                      notify_eif(), notify_mail(), notify_sms()
# -----------------------------------------------------------------------------
# DO NOT CHANGE THIS FILE UNLESS YOU KNOW WHAT YOU ARE DOING!
#******************************************************************************

#******************************************************************************
# DATA structures
#******************************************************************************

# ------------------------- CONFIGURATION starts here -------------------------
# define the version (YYYY-MM-DD)
typeset -r SCRIPT_VERSION="2017-08-24"
# location of parent directory containing KSH functions/HC plugins
typeset -r FPATH_PARENT="/opt/hc/lib"
# location of custom HC configuration files
typeset -r CONFIG_DIR="/etc/opt/hc"
# location of main configuration file
typeset -r CONFIG_FILE="${CONFIG_DIR}/core/check_health.conf"
# location of the host check configuration file (optional)
typeset -r HOST_CONFIG_FILE="${CONFIG_DIR}/check_host.conf"
# location of temporary working storage
typeset -r TMP_DIR="/var/tmp"
# health check log separator
typeset -r SEP="|"
# specify the UNIX user that needs to be used for executing the script
typeset -r EXEC_USER="root"
# ------------------------- CONFIGURATION ends here ---------------------------
# miscellaneous
typeset PATH=${PATH}:/usr/bin:/usr/sbin:/usr/local/bin
typeset -r SCRIPT_NAME="$(basename $0)"
typeset -r SCRIPT_DIR="$(dirname $0)"
typeset -r HOST_NAME="$(hostname)"
typeset -r OS_NAME="$(uname -s)"
typeset -r LOCK_DIR="${TMP_DIR}/.${SCRIPT_NAME}.lock"
typeset -r HC_MSG_FILE="${TMP_DIR}/.${SCRIPT_NAME}.hc.msg.$$"   # plugin messages files
typeset CHILD_ERROR=0
typeset DIR_PREFIX="$(date '+%Y-%m')"
typeset EXIT_CODE=0
typeset FDIR=""
typeset FFILE=""
typeset FPATH=""
typeset HC_FAIL_ID=""
typeset HC_FILE_LINE=""
typeset HC_NOW=""
typeset HC_STDOUT_LOG=""
typeset HC_STDERR_LOG=""
typeset LINUX_DISTRO=""
typeset LINUX_RELEASE=""
typeset RUN_RC=0
typeset SORT_CMD=""
typeset DEBUG_OPTS=""
# command-line parameters
typeset ARG_ACTION=0            # HC action flag
typeset ARG_CHECK_HOST=0        # host check is off by default
typeset ARG_CONFIG_FILE=""      # custom configuration file for a HC, none by default
typeset ARG_DEBUG=0             # debug is off by default
typeset ARG_DEBUG_LEVEL=0       # debug() only by default
typeset ARG_DETAIL=0            # for --report
typeset ARG_DISPLAY=""          # display is STDOUT by default
typeset ARG_FAIL_ID=""
typeset ARG_HC=""
typeset ARG_HC_ARGS=""          # no extra arguments to HC plug-in by default
typeset ARG_LAST=0              # report last events
typeset ARG_LIST=""             # list all by default
typeset ARG_LOG_DIR=""          # location of the log directory (~root, oracle etc)
typeset ARG_LOG=1               # logging is on by default
typeset ARG_MONITOR=1           # killing long running HC processes is on by default
typeset ARG_NOTIFY=""           # notification of problems is off by default
typeset ARG_REVERSE=0           # show report in reverse date order is off by default
typeset ARG_TERSE=0             # show terse help is off by default
typeset ARG_TODAY=0             # report today's events
typeset ARG_VERBOSE=1           # STDOUT is on by default
set +o bgnice


#******************************************************************************
# FUNCTION routines
#******************************************************************************

# -----------------------------------------------------------------------------
# COMMON
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# @(#) FUNCTION: build_fpath()
# DOES: build the FPATH environment variable from FPATH_PARENT
# EXPECTS: n/a
# RETURNS: 0
# REQUIRES: n/a
function build_fpath
{
(( ARG_DEBUG != 0 && ARG_DEBUG_LEVEL > 0 )) && set "${DEBUG_OPTS}"
typeset FPATH_DIR=""

# do not use a while-do loop here because mksh/pdksh does not pass updated
# variables back from the sub shell (only works for true ksh88/ksh93)
for FPATH_DIR in $(find ${FPATH_PARENT} -type d | grep -v -E -e "^${FPATH_PARENT}$" | tr '\n' ' ' 2>/dev/null)
do
    if [[ -z "${FPATH}" ]]
    then
        FPATH="${FPATH_DIR}"
    else
        FPATH="${FPATH}:${FPATH_DIR}"
    fi
done

return 0
}
# -----------------------------------------------------------------------------
# @(#) FUNCTION: check_config()
# DOES: check script configuration settings, abort upon failure
# EXPECTS: n/a
# RETURNS: 0
# REQUIRES: n/a
function check_config
{
(( ARG_DEBUG != 0 && ARG_DEBUG_LEVEL > 0 )) && set "${DEBUG_OPTS}"

# EXEC_USER
if [[ -z "${EXEC_USER}" ]]
then
    print -u2 "ERROR: you must define a value for the EXEC_USER setting in $0"
    exit 1
fi
# FPATH_PARENT
if [[ -z "${FPATH_PARENT}" ]]
then
    print -u2 "ERROR: you must define a value for the FPATH_PARENT setting in $0"
    exit 1
fi
if [[ ! -d "${FPATH_PARENT}" ]]
then
    print -u2 "ERROR: directory in setting FPATH_PARENT does not exist"
    exit 1
fi
# SEP
if [[ -z "${SEP}" ]]
then
    print -u2 "ERROR: you must define a value for the SEP setting in $0"
    exit 1
fi
# HC_TIME_OUT
if [[ -z "${HC_TIME_OUT}" ]]
then
    print -u2 "ERROR: you must define a value for the HC_TIME_OUT setting in $0"
    exit 1
fi
# EVENTS_DIR (auto-created dir)
if [[ -z "${EVENTS_DIR}" ]]
then
    print -u2 "ERROR: you must define a value for the EVENTS_DIR setting in $0"
    exit 1
fi
# STATE_DIR (auto-created dir)
if [[ -z "${STATE_DIR}" ]]
then
    print -u2 "ERROR: you must define a value for the STATE_DIR setting in $0"
    exit 1
fi

return 0
}

# -----------------------------------------------------------------------------
# @(#) FUNCTION: check_core()
# DOES: check core plugins & files/directories
# EXPECTS: n/a
# RETURNS: 0
# REQUIRES: n/a
function check_core
{
(( ARG_DEBUG != 0 && ARG_DEBUG_LEVEL > 0 )) && set "${DEBUG_OPTS}"

# check and include core helper libs
if [[ -r ${FPATH_PARENT}/core/include_core.sh && -h ${FPATH_PARENT}/core/include_core ]]
then
    # source /opt/hc/lib/core/include_core.sh
    . ${FPATH_PARENT}/core/include_core.sh
else
    print -u2 "ERROR: library file ${FPATH_PARENT}/core/include_core.sh is not present (tip: run --fix-symlinks)"
    exit 1
fi
if [[ -r ${FPATH_PARENT}/core/include_data.sh && -h ${FPATH_PARENT}/core/include_data ]]
then
    # source /opt/hc/lib/core/include_data.sh
    . ${FPATH_PARENT}/core/include_data.sh
else
    print -u2 "ERROR: library file ${FPATH_PARENT}/core/include_data.sh is not present (tip: run --fix-symlinks)"
    exit 1
fi
if [[ -r ${FPATH_PARENT}/core/include_os.sh && -h ${FPATH_PARENT}/core/include_os ]]
then
    # source /opt/hc/lib/core/include_os.sh
    . ${FPATH_PARENT}/core/include_os.sh
else
    print -u2 "ERROR: library file ${FPATH_PARENT}/core/include_os.sh is not present (tip: run --fix-symlinks)"
    exit 1
fi

# check for core directories
[[ -d ${EVENTS_DIR} ]] || mkdir -p "${EVENTS_DIR}" >/dev/null 2>&1
if [[ ! -d "${EVENTS_DIR}" ]] || [[ ! -w "${EVENTS_DIR}" ]]
then
    print -u2 "ERROR: unable to access the state directory at ${EVENTS_DIR}"
fi
[[ -d ${STATE_DIR} ]] || mkdir -p "${STATE_DIR}" >/dev/null 2>&1
if [[ ! -d "${STATE_DIR}" ]] || [[ ! -w "${STATE_DIR}" ]]
then
    print -u2 "ERROR: unable to access the state directory at ${STATE_DIR}"
fi
[[ -d ${STATE_PERM_DIR} ]] || mkdir -p "${STATE_PERM_DIR}" >/dev/null 2>&1
if [[ ! -d "${STATE_PERM_DIR}" ]] || [[ ! -w "${STATE_PERM_DIR}" ]]
then
    print -u2 "ERROR: unable to access the persistent state directory at ${STATE_PERM_DIR}"
fi
[[ -d ${STATE_TEMP_DIR} ]] || mkdir -p "${STATE_TEMP_DIR}" >/dev/null 2>&1
if [[ ! -d "${STATE_TEMP_DIR}" ]] || [[ ! -w "${STATE_TEMP_DIR}" ]]
then
    print -u2 "ERROR: unable to access the temporary state directory at ${STATE_TEMP_DIR}"
fi

return 0
}

# -----------------------------------------------------------------------------
# @(#) FUNCTION: check_lock_dir()
# DOES: check if script lock directory exists, abort upon duplicate run
# EXPECTS: n/a
# RETURNS: 0
# REQUIRES: n/a
function check_lock_dir
{
(( ARG_DEBUG != 0 && ARG_DEBUG_LEVEL > 0 )) && set "${DEBUG_OPTS}"
mkdir ${LOCK_DIR} >/dev/null || {
    print -u2 "ERROR: unable to acquire lock ${LOCK_DIR}"
    ARG_VERBOSE=0 warn "unable to acquire lock ${LOCK_DIR}"
    if [[ -f ${LOCK_DIR}/.pid ]]
    then
        typeset LOCK_PID="$(cat ${LOCK_DIR}/.pid)"
        print -u2 "ERROR: active health checker running on PID: ${LOCK_PID}"
        ARG_VERBOSE=0 warn "active health checker running on PID: ${LOCK_PID}. Exiting!"
    fi
    exit 1
}
print $$ >${LOCK_DIR}/.pid

return 0
}

# -----------------------------------------------------------------------------
# @(#) FUNCTION: check_params()
# DOES: check if arguments/options are valid, abort script upon error
# EXPECTS: n/a
# RETURNS: 0
# REQUIRES: n/a
function check_params
{
(( ARG_DEBUG != 0 && ARG_DEBUG_LEVEL > 0 )) && set "${DEBUG_OPTS}"

# --debug-level
if (( ARG_DEBUG_LEVEL > 2 ))
then
    print -u2 "ERROR: you must specify a debug level between 0-2"
    exit 1
fi
# --config-file
if [[ -n "${ARG_CONFIG_FILE}" ]]
then
    # do not allow a custom configuration file for multiple checks
    if [[ "${ARG_HC}" = *,* ]]      # use =, ksh88
    then
        print -u2 "ERROR: custom configuration file is not allowed when executing multiple HC's"
        exit 1
    fi
    # check if config file exists
    if [[ ! -r "${ARG_CONFIG_FILE}" ]]
    then
        print -u2 "ERROR: unable to read configuration file at ${ARG_CONFIG_FILE}"
        exit 1
    fi
fi
# --report/--detail/--id/--reverse/--last/--today
if (( ARG_ACTION == 8 ))
then
    if (( ARG_DETAIL != 0 )) && [[ -z "${ARG_FAIL_ID}" ]]
    then
        print -u2 "ERROR: you must specify an unique value for '--id' when using '--detail'"
        exit 1
    fi
    if (( ARG_LAST != 0 )) && (( ARG_TODAY != 0 ))
    then
        print -u2 "ERROR: you cannot specify '--last' with '--today'"
        exit 1
    fi
    if (( ARG_LAST != 0 )) && (( ARG_DETAIL != 0 ))
    then
        print -u2 "ERROR: you cannot specify '--last' with '--detail'"
        exit 1
    fi
    if (( ARG_LAST != 0 )) && (( ARG_REVERSE != 0 ))
    then
        print -u2 "ERROR: you cannot specify '--last' with '--detail'"
        exit 1
    fi
    if (( ARG_LAST != 0 )) && [[ -n "${ARG_FAIL_ID}" ]]
    then
        print -u2 "ERROR: you cannot specify '--last' with '--id'"
        exit 1
    fi
    if (( ARG_TODAY != 0 )) && (( ARG_DETAIL != 0 ))
    then
        print -u2 "ERROR: you cannot specify '--today' with '--detail'"
        exit 1
    fi
    if (( ARG_TODAY != 0 )) && (( ARG_REVERSE != 0 ))
    then
        print -u2 "ERROR: you cannot specify '--today' with '--detail'"
        exit 1
    fi
    if (( ARG_TODAY != 0 )) && [[ -n "${ARG_FAIL_ID}" ]]
    then
        print -u2 "ERROR: you cannot specify '--today' with '--id'"
        exit 1
    fi
fi
if (( ARG_ACTION != 8 )) && (( ARG_LAST != 0 ))
then
    print -u2 "ERROR: you cannot specify '--last' without '--report'"
    exit 1
fi
if (( ARG_ACTION != 8 )) && (( ARG_REVERSE != 0 ))
then
    print -u2 "ERROR: you cannot specify '--reverse' without '--report'"
    exit 1
fi
if (( ARG_ACTION != 8 )) && (( ARG_DETAIL != 0 ))
then
    print -u2 "ERROR: you cannot specify '--detail' without '--report'"
    exit 1
fi
if (( ARG_ACTION != 8 )) && [[ -n "${ARG_FAIL_ID}" ]]
then
    print -u2 "ERROR: you cannot specify '--id' without '--report'"
    exit 1
fi
# --check-host,--check/--disable/--enable/--run/--show,--hc
if [[ -n "${ARG_HC}" ]] && (( ARG_ACTION == 0 ))
then
    print -u2 "ERROR: you must specify an action for the HC (--check/--disable/--enable/--run/--show)"
    exit 1
fi
if (( ARG_CHECK_HOST == 0 ))
then
    if (( ARG_ACTION < 6 )) && [[ -z "${ARG_HC}" ]]
    then
        print -u2 "ERROR: you specify a value for parameter '--hc'"
        exit 1
    fi
    if (( ARG_ACTION == 5 )) || [[ -n "${ARG_HC_ARGS}" ]]
    then
        case "${ARG_HC}" in
            *,*)
                print -u2 "ERROR: you can only specify one value for '--hc' in combination with '--show'"
                exit 1
                ;;
        esac
    fi
else
    # host checking has no other messages to display
    ARG_VERBOSE=0
fi
# --list
if (( ARG_ACTION == 9 ))
then
    ARG_VERBOSE=0
    ARG_LOG=0
fi
# --log-dir
[[ -z "${ARG_LOG_DIR}" ]] || LOG_DIR="${ARG_LOG_DIR}"
LOG_FILE="${LOG_DIR}/${SCRIPT_NAME}.log"
if (( ARG_LOG != 0 ))
then
    if [[ ! -d "${LOG_DIR}" ]] || [[ ! -w "${LOG_DIR}" ]]
    then
        print -u2 "ERROR: unable to write to the log directory at ${LOG_DIR}"
        exit 1
    fi
fi

return 0
}

# -----------------------------------------------------------------------------
# @(#) FUNCTION: check_platform()
# DOES: check running platform
# EXPECTS: platform name [string]
# RETURNS: 0=platform matches, 1=platform does not match
# REQUIRES: $OS_NAME
function check_platform
{
(( ARG_DEBUG != 0 && ARG_DEBUG_LEVEL > 0 )) && set "${DEBUG_OPTS}"
typeset HC_PLATFORM="${1}"
typeset RC=0

if [[ "${OS_NAME}" != @(${HC_PLATFORM}) ]]
then
    (( ARG_DEBUG != 0 )) && warn "platform ${HC_PLATFORM} does not match ${OS_NAME}"
    RC=1
fi

return ${RC}
}

# -----------------------------------------------------------------------------
# @(#) FUNCTION: check_user()
# DOES: check user that is executing the script, abort script if user 'root'
# EXPECTS: n/a
# RETURNS: 0
# REQUIRES: n/a
function check_user
{
(( ARG_DEBUG != 0 && ARG_DEBUG_LEVEL > 0 )) && set "${DEBUG_OPTS}"
typeset WHOAMI=""

# avoid sub-shell for mksh/pdksh
WHOAMI=$(IFS='()'; set -- $(id); print $2)
if [[ "${WHOAMI}" != "${EXEC_USER}" ]]
then
    print -u2 "ERROR: must be run as user '${EXEC_USER}'"
    exit 1
fi

return 0
}

# -----------------------------------------------------------------------------
# @(#) FUNCTION: check_shell()
# DOES: check for ksh version
# EXPECTS: n/a
# RETURNS: 0
# REQUIRES: n/a
function check_shell
{
case "${KSH_VERSION}" in
    *MIRBSD*|*PD*|*LEGACY*)
        (( ARG_DEBUG != 0 )) && debug "running ksh: ${KSH_VERSION}"
        ;;
    *)
        if [[ -z "${ERRNO}" ]]
        then
            (( ARG_DEBUG != 0 )) && print "running ksh: ${.sh.version}"
        else
            (( ARG_DEBUG != 0 )) && print "running ksh: ksh88 or older"
        fi
        ;;
esac

return 0
}

# -----------------------------------------------------------------------------
# @(#) FUNCTION: display_usage()
# DOES: display usage and exit with error code 0
# EXPECTS: n/a
# RETURNS: 0
# REQUIRES: n/a
function display_usage
{
cat << EOT

**** ${SCRIPT_NAME} ****
**** (c) KUDOS BVBA - Patrick Van der Veken ****

Execute/report simple health checks (HC) on UNIX hosts.

Syntax: ${SCRIPT_DIR}/${SCRIPT_NAME} [--help] | [--help-terse] | [--version] |
    [--list=<needle>] | [--list-core] | [--fix-symlinks] | (--disable-all | enable-all) |
        (--check-host | ((--check | --enable | --disable | --run | --show) --hc=<list_of_checks> [--config-file=<configuration_file>] [hc-args="<arg1,arg2=val,arg3">]))
            [--display=<method>] ([--debug] [--debug-level=<level>]) [--no-monitor] [--no-log] [--log-dir=<log_directory>]
                [--notify=<method_list>] [--mail-to=<address_list>] [--sms-to=<sms_rcpt> --sms-provider=<name>]
                    --report ( ([--last] | [--today]) | ([--reverse] [--id=<fail_id> [--detail]]) )

EOT

if (( ARG_TERSE == 0 ))
then
    cat << EOT
Parameters:

--check         : display HC state.
--check-host    : execute all configured HC(s) (see check_host.conf)
--config-file   : custom configuration file for a HC, may only be specified when executing a single HC plugin.
--debug         : run script in debug mode
--debug-level   : level of debugging information to show (0,1,2)
--detail        : show detailed info on failed HC event (will show STDOUT+STDERR logs)
--disable       : disable HC(s).
--disable-all   : disable all HC.
--display       : display HC results in a formatted way. Default is STDOUT (see --list-core for available formats)
--enable        : enable HC(s).
--enable-all    : enable all HCs.
--fix-symlinks  : update symbolic links for the KSH autoloader.
--hc            : list of health checks to be executed (comma-separated) (see also --list-hc)
--hc-args       : extra arguments to be passed to an individual HC. Arguments must be comma-separated and enclosed
                  in double quotes (example: --hc_args="arg1,arg2=value,arg3").
--id            : value of a FAIL ID (must be specified as uninterrupted sequence of numbers)
--last          : show the last events for each HC and their combined STC value
--list          : show the available health checks. Use <needle> to search with wildcards. Following details are shown:
                  - health check (plugin) name
                  - state of the HC plugin (disabled/enabled)
                  - version of the HC plugin
                  - whether the HC plugin requires a configuration file in ${HC_ETC_DIR}
                  - whether the HC plugin is scheduled by cron
--list-core     : show the available core plugins (mail,SMS,...)
--log-dir       : specify a log directory location (for both script & health checks log).
--mail-to       : list of e-mail address(es) to which an e-mail alert will be send to [requires mail core plugin]
--no-log        : do not log any messages to the script log file or health check results.
--no-monitor    : do not stop the execution of a HC after \$HC_TIME_OUT seconds
--notify        : notify upon HC failure(s). Multiple options may be specified if comma-separated (see --list-core for availble formats)
--report        : report on failed HC events
--reverse       : show the report in reverse date order (newest events first)
--run           : execute HC(s).
--show          : show information/documentation on a HC
--sms-provider  : name of a supported SMS provider (see \$SMS_PROVIDERS) [requires SMS core plugin]
--sms-to        : name of person or group to which a sms alert will be send to [requires SMS core plugin]
--today         : show today's events (HC and their combined STC value)
--version       : show the script version (major/minor/fix).

EOT
fi

return 0
}

# -----------------------------------------------------------------------------
# @(#) FUNCTION: do_cleanup()
# DOES: remove temporary file(s)/director(y|ies)
# EXPECTS: n/a
# RETURNS: 0
# REQUIRES: log()
function do_cleanup
{
(( ARG_DEBUG != 0 && ARG_DEBUG_LEVEL > 0 )) && set "${DEBUG_OPTS}"
log "performing cleanup ..."

# remove temporary files
[[ -f "${HC_MSG_FILE}" ]] && rm -f ${HC_MSG_FILE} >/dev/null 2>&1

# remove trailing log files
[[ -f "${HC_STDOUT_LOG}" ]] && rm -f ${HC_STDOUT_LOG} >/dev/null 2>&1
[[ -f "${HC_STDERR_LOG}" ]] && rm -f ${HC_STDERR_LOG} >/dev/null 2>&1

# remove lock directory
if [[ -d ${LOCK_DIR} ]]
then
    rm -rf ${LOCK_DIR} >/dev/null 2>&1
    log "${LOCK_DIR} lock directory removed"
fi

log "*** finish of ${SCRIPT_NAME} [${CMD_LINE}] ***"

return 0
}

# -----------------------------------------------------------------------------
# @(#) FUNCTION: fix_symlinks()
# DOES: create symbolic links to HC scripts to satisfy KSH autoloader
# EXPECTS: n/a
# RETURNS: 0
# REQUIRES: n/a
function fix_symlinks
{
(( ARG_DEBUG != 0 && ARG_DEBUG_LEVEL > 0 )) && set "${DEBUG_OPTS}"
typeset FDIR=""
typeset FFILE=""
typeset FSYML=""

# find missing symlinks (do not skip core plug-ins here)
print "${FPATH}" | tr ':' '\n' | while read -r FDIR
do
    find ${FDIR} -type f -print 2>/dev/null | while read -r FFILE
    do
        FSYML="${FFILE%.sh}"
        # check if symlink already exists
        if [[ ! -h "${FSYML}" ]]
        then
            ln -s "${FFILE##*/}" "${FSYML}" >/dev/null
            (( $? == 0 )) && \
                print -u2 "INFO: created symbolic link ${FFILE} -> ${FSYML}"
        fi
    done
done

# find & remove broken symbolic links (do not skip core plug-ins here)
print "${FPATH}" | tr ':' '\n' | while read -r FDIR
do
    # do not use 'find -type l' here!
    ls ${FDIR} 2>/dev/null | grep -v "\." | while read -r FSYML
    do
        # check if file is a dead symlink
        if [[ -h "${FDIR}/${FSYML}" ]] && [[ ! -f "${FDIR}/${FSYML}" ]]
        then
            rm -f "${FDIR}/${FSYML}" >/dev/null
            (( $? == 0 )) && \
                print -u2 "INFO: remove dead symbolic link ${FSYML}"
        fi
    done
done

return 0
}

# -----------------------------------------------------------------------------
# @(#) FUNCTION: read_config()
# DOES: read & parse the main configuration file(s)
# EXPECTS: n/a
# RETURNS: 0
# REQUIRES: die()
function read_config
{
(( ARG_DEBUG != 0 && ARG_DEBUG_LEVEL > 0 )) && set "${DEBUG_OPTS}"
typeset SMS_CONFIG_FILE=""

if [[ -z "${CONFIG_FILE}" ]] || [[ -z "${CONFIG_FILE}" ]]
then
    die "you must define a value for the CONFIG_DIR and CONFIG_FILE setting in $0"
fi
if [[ ! -r "${CONFIG_FILE}" ]]
then
    die "unable to read configuration file at ${CONFIG_FILE}"
else
    . "${CONFIG_FILE}"
fi

return 0
}


#******************************************************************************
# MAIN routine
#******************************************************************************

# parse arguments/parameters
CMD_LINE="$*"
[[ -z "${CMD_LINE}" ]] && display_usage && exit 0
for PARAMETER in ${CMD_LINE}
do
    case ${PARAMETER} in
        -check|--check)
            ARG_ACTION=1
            ;;
        -c|-check-host|--check-host)
            ARG_CHECK_HOST=1
            ARG_ACTION=4
            ;;
        -config-file=*)
            ARG_CONFIG_FILE="${PARAMETER#-config-file=}"
            ;;
        --config-file=*)
            ARG_CONFIG_FILE="${PARAMETER#--config-file=}"
            ;;
        -debug|--debug)
            ARG_DEBUG=1
            PS4='DEBUG: $0: line $LINENO: '
            set "${DEBUG_OPTS}"
            ;;
        -debug-level=*)
            ARG_DEBUG_LEVEL="${PARAMETER#-debug-level=}"
            ;;
        --debug-level=*)
            ARG_DEBUG_LEVEL="${PARAMETER#--debug-level=}"
            ;;
        -detail|--detail)
            ARG_DETAIL=1
            ;;
        -d|-disable|--disable)
            ARG_ACTION=2
            ;;
        -disable-all|--disable-all)
            ARG_ACTION=6
            ;;
        -display|--display)
            # STDOUT as default
            ARG_DISPLAY=""
            ;;
        -display=*)
            ARG_DISPLAY="${PARAMETER#-display=}"
            ;;
        --display=*)
            ARG_DISPLAY="${PARAMETER#--display=}"
            ;;
        -e|-enable|--enable)
            ARG_ACTION=3
            ;;
        -enable-all|--enable-all)
            ARG_ACTION=7
            ;;
        -hc=*)
            ARG_HC="${PARAMETER#-hc=}"
            ;;
        --hc=*)
            ARG_HC="${PARAMETER#--hc=}"
            ;;
        -hc-args=*)
            ARG_HC_ARGS="${PARAMETER#-hc-args=}"
            ;;
        --hc-args=*)
            ARG_HC_ARGS="${PARAMETER#--hc-args=}"
            ;;
        -f|-fix-symlinks|--fix-symlinks)
            read_config
            check_config
            build_fpath
            check_shell
            check_user
            fix_symlinks
            exit 0
            ;;
        -id=*)
            ARG_FAIL_ID="${PARAMETER#-id=}"
            ;;
        --id=*)
            ARG_FAIL_ID="${PARAMETER#--id=}"
            ;;
        -last|--last)
            ARG_LAST=1
            ;;
        -list|--list)
            ARG_ACTION=9
            ;;
        -list=*)
            ARG_LIST="${PARAMETER#-list=}"
            ARG_ACTION=9
            ;;
        --list=*)
            ARG_LIST="${PARAMETER#--list=}"
            ARG_ACTION=9
            ;;
        -list-hc|--list-hc|-list-all|--list-all)
            print -u2 "WARN: deprecated option. Use --list | --list=<needle>"
            exit 0
            ;;
        -list-core|--list-core)
            read_config
            check_config
            build_fpath
            check_core
            check_shell
            check_user
            list_core
            exit 0
            ;;
        -log-dir=*)
            ARG_LOG_DIR="${PARAMETER#-log-dir=}"
            ;;
        --log-dir=*)
            ARG_LOG_DIR="${PARAMETER#--log-dir=}"
            ;;
        -mail-to=*)
            ARG_MAIL_TO="${PARAMETER#-mail-to=}"
            ;;
        --mail-to=*)
            ARG_MAIL_TO="${PARAMETER#--mail-to=}"
            ;;
        -notify=*)
            ARG_NOTIFY="${PARAMETER#-notify=}"
            ;;
        --notify=*)
            ARG_NOTIFY="${PARAMETER#--notify=}"
            ;;
        -no-log|--no-log)
            ARG_LOG=0
            ;;
        -no-monitor|--no-monitor)
            ARG_MONITOR=0
            ;;
        -report|--report)
            ARG_LOG=0; ARG_VERBOSE=0
            ARG_ACTION=8
            ;;
        -reverse|--reverse)
            ARG_REVERSE=1
            ;;
        -r|-run|--run)
            ARG_ACTION=4
            ;;
        -s|-show|--show)
            ARG_ACTION=5
            ARG_LOG=0
            ARG_VERBOSE=0
            ;;
        -sms-provider=*)
            ARG_SMS_PROVIDER="${PARAMETER#-sms-provider=}"
            ;;
        --sms-provider=*)
            ARG_SMS_PROVIDER="${PARAMETER#--sms-provider=}"
            ;;
        -sms-to=*)
            ARG_SMS_TO="${PARAMETER#-sms-to=}"
            ;;
        --sms-to=*)
            ARG_SMS_TO="${PARAMETER#--sms-to=}"
            ;;
        -today|--today)
            ARG_TODAY=1
            ;;
        -v|-version|--version)
            print "INFO: $0: ${SCRIPT_VERSION}"
            exit 0
            ;;
        \?|-h|-help|--help)
            display_usage
            exit 0
            ;;
        -help-terse|--help-terse)
            ARG_TERSE=1
            display_usage
            exit 0
            ;;
        *)
            display_usage
            exit 0
            ;;
    esac
done

# startup checks & processing (no build_fpath() here to avoid dupes in FPATH!)
read_config
check_config
build_fpath
check_core
check_shell
check_params        # parse cmd-line
discover_core       # parse cmd-line (for core plugins)
check_user

# catch shell signals
trap 'do_cleanup; exit' HUP INT QUIT TERM

# set debugging options
if (( ARG_DEBUG != 0 ))
then
    case ${ARG_DEBUG_LEVEL} in
        0)
            # display only messages via debug() (default)
            :
            ;;
        1)
            # set -x
            DEBUG_OPTS='-x'
            ;;
        2)
            # set -vx
            DEBUG_OPTS='-vx'
            ;;
    esac
fi

log "*** start of ${SCRIPT_NAME} [${CMD_LINE}] ***"
(( ARG_LOG != 0 )) && log "logging takes places in ${LOG_FILE}"

# check/create lock file & write PID file (only for --run)
(( ARG_ACTION == 4 )) && check_lock_dir

# general HC log
HC_LOG="${LOG_DIR}/hc.log"

# get linux stuff
[[ "${OS_NAME}" = "Linux" ]] && linux_get_distro        # use =, ksh88

# act on HC check(s)
case ${ARG_ACTION} in
    1)  # check (status) HC(s)
        print "${ARG_HC}" | tr ',' '\n' | grep -v '^$' | while read -r HC_CHECK
        do
            # check for HC (function)
            exists_hc "${HC_CHECK}" && die "cannot find HC: ${HC_CHECK}"
            stat_hc "${HC_CHECK}"
            if (( $? == 0 ))
            then
                log "HC ${HC_CHECK} is currently disabled"
            else
                log "HC ${HC_CHECK} is currently enabled"
            fi
            is_scheduled "${HC_CHECK}"
            if (( $? == 0 ))
            then
                log "HC ${HC_CHECK} is currently not scheduled (cron)"
            else
                log "HC ${HC_CHECK} is currently scheduled (cron)"
            fi
        done
        ;;
    2)  # disable HC(s)
        print "${ARG_HC}" | tr ',' '\n' | grep -v '^$' | while read -r HC_DISABLE
        do
            # check for HC (function)
            exists_hc "${HC_DISABLE}" && die "cannot find HC: ${HC_DISABLE}"
            log "disabling HC: ${HC_DISABLE}"
            touch "${STATE_PERM_DIR}/${HC_DISABLE}.disabled" >/dev/null 2>&1
            if (( $? == 0 ))
            then
                log "successfully disabled HC: ${HC_DISABLE}"
            else
                log "failed to disable HC: ${HC_DISABLE} [RC=${DISABLE_RC}]"
                EXIT_CODE=1
            fi
        done
        ;;
    3)  # enable HC(s)
        print "${ARG_HC}" | tr ',' '\n' | grep -v '^$' | while read -r HC_ENABLE
        do
            # check for HC (function)
            exists_hc "${HC_ENABLE}" && die "cannot find HC: ${HC_ENABLE}"
            log "enabling HC: ${HC_ENABLE}"
            [[ -d ${STATE_PERM_DIR} ]] || \
                die "state directory does not exist, all HC(s) are enabled"
            stat_hc "${HC_ENABLE}" || die "HC is already enabled"
            rm -f "${STATE_PERM_DIR}/${HC_ENABLE}.disabled" >/dev/null 2>&1
            if (( $? == 0 ))
            then
                log "successfully enabled HC: ${HC_ENABLE}"
            else
                log "failed to enable HC: ${HC_ENABLE} [RC=${ENABLE_RC}]"
                EXIT_CODE=1
            fi
        done
        ;;
    4)  # run HC(s)
        # pre-allocate FAIL_ID
        HC_NOW="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)"
        if [[ -z "${HC_FAIL_ID}" ]]
        then
            HC_FAIL_ID="$(print ${HC_NOW} | tr -d '\-:[:space:]')"
        fi
        # --check-host handling
        (( ARG_CHECK_HOST == 1 )) && init_check_host
        # execute plug-in(s)
        print "${ARG_HC}" | tr ',' '\n' | grep -v '^$' | while read -r HC_RUN
        do
            # check for HC (function)
            exists_hc "${HC_RUN}"
            if (( $? == 0 ))
            then
                # callback for display_init with extra code 'MISSING'
                if (( DO_DISPLAY_INIT == 1 ))
                then
                    display_init "${HC_RUN}" "" "MISSING"
                else
                    warn "cannot find HC: ${HC_RUN}"
                    EXIT_CODE=${RUN_RC}
                fi
                continue
            fi
            stat_hc "${HC_RUN}"
            if (( $? == 0 ))
            then
                # callback for display_init with extra code 'DISABLED'
                if (( DO_DISPLAY_INIT == 1 ))
                then
                    display_init "${HC_RUN}" "" "DISABLED"
                else
                    warn "may not run disabled HC: ${HC_RUN}"
                    EXIT_CODE=${RUN_RC}
                fi
                continue
            fi
            # set & initialize STDOUT/STDERR locations (not in init_hc()!)
            HC_STDOUT_LOG="${TMP_DIR}/${HC_RUN}.stdout.log.$$"
            HC_STDERR_LOG="${TMP_DIR}/${HC_RUN}.stderr.log.$$"
            >${HC_STDOUT_LOG} 2>/dev/null
            >${HC_STDERR_LOG} 2>/dev/null

            # --check-host handling: alternative configuration file, mangle ARG_CONFIG_FILE
            if (( ARG_CHECK_HOST == 1 ))
            then
                ARG_CONFIG_FILE=""      # reset from previous call
                RUN_CONFIG_FILE=$(grep -i -E -e "^hc:${HC_RUN}:" ${HOST_CONFIG_FILE} 2>/dev/null | cut -f3 -d':')
                [[ -n "${RUN_CONFIG_FILE}" ]] && ARG_CONFIG_FILE="${CONFIG_DIR}/${RUN_CONFIG_FILE}"
            fi

            # run HC with or without monitor
            if (( ARG_MONITOR == 0 ))
            then
                ${HC_RUN} ${ARG_HC_ARGS}
                RUN_RC=$?
                EXIT_CODE=${RUN_RC}
                if (( RUN_RC == 0 ))
                then
                    log "executed HC: ${HC_RUN} [RC=${RUN_RC}]"
                else
                    # callback for display_init with extra code 'ERROR'
                    if (( DO_DISPLAY_INIT == 1 ))
                    then
                        display_init "${HC_RUN}" "" "ERROR"
                    else
                        warn "failed to execute HC: ${HC_RUN} [RC=${RUN_RC}]"
                    fi
                fi
            else
                # set trap on SIGUSR1
                trap "handle_timeout" USR1

                # $PID is PID of the owner shell
                OWNER_PID=$$
                (
                    # sleep for $TIME_OUT seconds. If the sleep subshell is then still alive, send a SIGUSR1 to the owner
                    sleep ${HC_TIME_OUT}
                    kill -s USR1 ${OWNER_PID} >/dev/null 2>&1
                ) &
                # SLEEP_PID is the PID of the sleep subshell itself
                SLEEP_PID=$!

                ${HC_RUN} ${ARG_HC_ARGS} &
                CHILD_PID=$!
                log "spawning child process with time-out of ${HC_TIME_OUT} secs for HC call [PID=${CHILD_PID}]"
                # wait for the command to complete
                wait ${CHILD_PID}
                # when the child completes, we can get rid of the sleep trigger
                RUN_RC=$?
                EXIT_CODE=${RUN_RC}
                kill -s TERM ${SLEEP_PID} >/dev/null 2>&1
                # process return codes
                if (( RUN_RC != 0 ))
                then
                    # callback for display_init with extra code 'ERROR'
                    if (( DO_DISPLAY_INIT == 1 ))
                    then
                        display_init "${HC_RUN}" "" "ERROR"
                    else
                        warn "failed to execute HC: ${HC_RUN} [RC=${RUN_RC}]"
                    fi
                else
                    if (( CHILD_ERROR == 0 ))
                    then
                        log "executed HC: ${HC_RUN} [RC=${RUN_RC}]"
                    else
                        # callback for display_init with extra code 'ERROR'
                        if (( DO_DISPLAY_INIT == 1 ))
                        then
                            display_init "${HC_RUN}" "" "ERROR"
                        else
                            warn "failed to execute HC as background process"
                        fi
                    fi
                fi
            fi

            # reset FAIL_ID & HC failure storage (also for failed HCs)
            handle_hc "${HC_RUN}"
            rm -f ${HC_MSG_FILE} >/dev/null 2>&1
        done
        ;;
    5)  # show info on HC (single)
        exists_hc "${ARG_HC}"
        if (( $? == 0 ))
        then
            die "cannot find HC: ${ARG_HC}"
        else
            ${ARG_HC} "help"
        fi
        ;;
    6)  # disable all HCs
        list_hc "list" | while read -r HC_DISABLE
        do
            # check for HC (function)
            exists_hc "${HC_DISABLE}" && die "cannot find HC: ${HC_DISABLE}"
            log "disabling HC: ${HC_DISABLE}"
            touch "${STATE_PERM_DIR}/${HC_DISABLE}.disabled" >/dev/null 2>&1
            if (( $? == 0 ))
            then
                log "successfully disabled HC: ${HC_DISABLE}"
            else
                log "failed to disable HC: ${HC_DISABLE} [RC=${DISABLE_RC}]"
                EXIT_CODE=1
            fi
        done
        ;;
    7)  # enable all HCs
        list_hc "list" | while read -r HC_ENABLE
        do
            # check for HC (function)
            exists_hc "${HC_ENABLE}" && die "cannot find HC: ${HC_ENABLE}"
            log "enabling HC: ${HC_ENABLE}"
            [[ -d ${STATE_PERM_DIR} ]] || \
                die "state directory does not exist, all HC(s) are enabled"
            rm -f "${STATE_PERM_DIR}/${HC_ENABLE}.disabled" >/dev/null 2>&1
            if (( $? == 0 ))
            then
                log "successfully enabled HC: ${HC_ENABLE}"
            else
                log "failed to enable HC: ${HC_ENABLE} [RC=${ENABLE_RC}]"
                EXIT_CODE=1
            fi
        done
        ;;
    8)  # report on last events or FAIL_IDs
        if (( ARG_LAST != 0 ))
        then
            printf "\n| %-30s | %-20s | %-14s | %-4s\n" "HC" "Timestamp" "FAIL ID" "STC (combined value)"
            printf "%100s\n" | tr ' ' -
            # loop over all HCs
            list_hc "list" | while read -r HC_LAST
            do
                HC_LAST_TIME=""
                HC_LAST_STC=0
                HC_LAST_FAIL_ID="-"
                # find last event or block of events (same timestamp)
                # (but unfortunately this is only accurate to events within the SAME second!)
                HC_LAST_TIME="$(grep ${HC_LAST} ${HC_LOG} 2>/dev/null | sort -n | cut -f1 -d${SEP} | uniq | tail -1)"
                if [[ -z "${HC_LAST_TIME}" ]]
                then
                    HC_LAST_TIME="-"
                    HC_LAST_STC="-"
                else
                    # find all STC codes for the last event and add them up
                    grep "${HC_LAST_TIME}${SEP}${HC_LAST}" ${HC_LOG} 2>/dev/null |\
                        while read -r REPORT_LINE
                    do
                        HC_LAST_EVENT_STC=$(print "${REPORT_LINE}" | cut -f3 -d"${SEP}")
                        HC_LAST_EVENT_FAIL_ID=$(print "${REPORT_LINE}" | cut -f5 -d"${SEP}")
                        HC_LAST_STC=$(( HC_LAST_STC + HC_LAST_EVENT_STC ))
                        [[ -n "${HC_LAST_EVENT_FAIL_ID}" ]] && HC_LAST_FAIL_ID="${HC_LAST_EVENT_FAIL_ID}"
                    done
                fi
                # report on findings
                printf "| %-30s | %-20s | %-14s | %-4s\n" \
                    "${HC_LAST}" "${HC_LAST_TIME}" "${HC_LAST_FAIL_ID}" "${HC_LAST_STC}"
            done
            # disclaimer
            print "Note: this report only shows the overall combined status of all events of each HC within exactly"
            print "      the *same* time stamp (seconds precise). It may therefore fail to report certain FAIL IDs."
            print "      Use $0 --report to get the exact list of failure events."
        else
            ID_NEEDLE="[0-9][0-9]*"
            [[ -n "${ARG_FAIL_ID}" ]] && ID_NEEDLE="${ARG_FAIL_ID}"
            (( ARG_TODAY != 0 )) && ID_NEEDLE="$(date '+%Y%m%d')"    # refers to timestamp of HC FAIL_ID

            # check fail count (look for unique IDs in the 5th field of the HC log)
            FAIL_COUNT=$(cut -f5 -d"${SEP}" ${HC_LOG} 2>/dev/null | grep -E -e "${ID_NEEDLE}" | uniq | wc -l)
            if (( FAIL_COUNT != 0 ))
            then
                # check for detail or not?
                if (( ARG_DETAIL != 0 )) && (( FAIL_COUNT != 1 ))
                then
                    ARG_LOG=1 die "you must specify a unique FAIL_ID value"
                fi
                # reverse?
                if (( ARG_REVERSE == 0 ))
                then
                    SORT_CMD="sort -n"
                else
                    SORT_CMD="sort -rn"
                fi
                # global or detailed?
                if (( ARG_DETAIL == 0 ))
                then
                    printf "\n| %-20s | %-14s | %-30s | %-s\n" \
                        "Timestamp" "FAIL ID" "HC" "Message"
                    printf "%120s\n" | tr ' ' -

                    # print failed events
                    # no extended grep here and no end $SEP!
                    grep ".*${SEP}.*${SEP}.*${SEP}.*${SEP}${ID_NEEDLE}" ${HC_LOG} 2>/dev/null |\
                        ${SORT_CMD} | while read -r REPORT_LINE
                    do
                        FAIL_F1=$(print "${REPORT_LINE}" | cut -f1 -d"${SEP}")
                        FAIL_F2=$(print "${REPORT_LINE}" | cut -f2 -d"${SEP}")
                        FAIL_F3=$(print "${REPORT_LINE}" | cut -f4 -d"${SEP}")
                        FAIL_F4=$(print "${REPORT_LINE}" | cut -f5 -d"${SEP}")

                        printf "| %-20s | %-14s | %-30s | %-s\n" \
                            "${FAIL_F1}" "${FAIL_F4}" "${FAIL_F2}" "${FAIL_F3}"
                    done

                    printf "\n%-s\n" "SUMMARY: ${FAIL_COUNT} failed HC event(s) found."
                else
                    # print failed events (we may have multiple events for 1 FAIL ID)
                    EVENT_COUNT=1
                    DIR_PREFIX="$(expr substr ${ARG_FAIL_ID} 1 4)-$(expr substr ${ARG_FAIL_ID} 5 2)"
                    # no extended grep here!
                    grep ".*${SEP}.*${SEP}.*${SEP}.*${SEP}${ID_NEEDLE}${SEP}" ${HC_LOG} 2>/dev/null |\
                        ${SORT_CMD} | while read -r REPORT_LINE
                    do
                        FAIL_F1=$(print "${REPORT_LINE}" | cut -f1 -d"${SEP}")
                        FAIL_F2=$(print "${REPORT_LINE}" | cut -f2 -d"${SEP}")
                        FAIL_F3=$(print "${REPORT_LINE}" | cut -f4 -d"${SEP}")

                        printf "%36sMSG #%03d%36s" "" ${EVENT_COUNT} "" | tr ' ' -
                        printf "\nTime    : %-s\nHC      : %-s\nDetail  : %-s\n" \
                            "${FAIL_F1}" "${FAIL_F2}" "${FAIL_F3}"
                        EVENT_COUNT=$(( EVENT_COUNT + 1 ))
                    done

                    printf "%37sSTDOUT%37s\n" | tr ' ' -;
                    # display non-empty STDOUT file(s)
                    if [[ -n "$(du -a ${EVENTS_DIR}/${DIR_PREFIX}/${ARG_FAIL_ID}/*.stdout.log 2>/dev/null | awk '$1*512 > 0 {print $2}')"  ]]
                    then
                        cat ${EVENTS_DIR}/${DIR_PREFIX}/${ARG_FAIL_ID}/*.stdout.log
                    else
                        printf "%-s\n" "No STDOUT found"
                    fi

                    printf "%37sSTDERR%37s\n" | tr ' ' -;
                    # display non-empty STDERR file(s)
                    if [[ -n "$(du -a ${EVENTS_DIR}/${DIR_PREFIX}/${ARG_FAIL_ID}/*.stderr.log 2>/dev/null | awk '$1*512 > 0 {print $2}')" ]]
                    then
                        cat ${EVENTS_DIR}/${DIR_PREFIX}/${ARG_FAIL_ID}/*.stderr.log
                    else
                        printf "%-s\n" "No STDERR found"
                    fi

                    printf "%80s\n" | tr ' ' -
                fi
            else
                printf "\n%-s\n" "SUMMARY: 0 failed HC events found."
            fi
        fi
        ;;
    9)  # list HC plugins
        list_hc "" "${ARG_LIST}"
        ;;
esac

# finish up work
do_cleanup

exit ${EXIT_CODE}

#******************************************************************************
# END of script
#******************************************************************************
