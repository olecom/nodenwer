#!/bin/sh
#нелья копировать и запускать с папками не на латинке!!!
# v000 2012-03-25 node+.sh # v001 2012-03-27 Masterpiece
# v002 2012-03-31 cygwin: msi PATH support; `tail -n 44` more output is needed
# v003 2012-04-03 `_err` must be >&8 in cmd loops, fix `_err` messages
# v004 2012-04-05 'devstart' -- development mode
# v005 2012-04-10 "export MONGODS" every `node` gets all db connections
# v006 2012-04-10 'devstart' with 'stop' && 'devstart' in on-line mode (Masterpiece)
# v006 2012-05-13 'devstart' reloads config file
#				  'uglify'
set -e

[ "$*" ] || { echo "
Usage: $0"' app_name.conf [&|] {start, stop, stat
					,devstart(loops reboots until CTRL+C)
					,devstartcon (output to console)
					,uglyfy }
(script, abs path app config file,   command)
Managing of `node`JS application server under cygwin or linux-gnu OSes
'
exit 2
}

trap 'echo "
Unexpected Script Error! Use /bin/sh -x $0 to trace it.
"
set +e

trap "" 0
exit 0
' 0

trap '' CHLD

_err() {
printf '[node+.sh error] '"$@" >&2
#exit
}

[ -e "$1" ] || {
_err "No Config file $1 is there."
exit 1
}

_exit() {
trap "" 0
exit "$1"
}

case "$OSTYPE" in
*cygwin*) # OSTYPE=cygwin
	LD_LIBRARY_PATH='/bin:/bin.w32'

	case "$PATH" in
	  *'nodejs'*) # nodejs is not installed via msi
		PATH="/bin:`/bin/sed 's|.*:\([^:]*/nodejs\).*|\1|p;d' <<!
$PATH
!`:/bin.w32";;
	  *) # nodejs is not installed, using local copy of node.exe
	    PATH='/bin:/bin.w32';;
	esac
;;
*linux_gnu*) # OSTYPE=linux-gnu ???
	LD_LIBRARY_PATH="/usr/local/bin:$LD_LIBRARY_PATH"
	case "$PATH" in
	  *'/usr/local/bin'*) ;;
	  *) PATH="/usr/local/bin:$PATH" ;;
	esac
;;
esac
# including config here; make \r\n -> \n trasformation

sed '' "$1" >"$1".lf
. "${1}.lf" && rm -f "${1}.lf"
APP_CFG=$1
shift 1
#
export PATH LD_LIBRARY_PATH
export -n JSAPPSTART

_date() { # ISO date
date -u '+%Y-%m-%dT%H:%M:%SZ'
}

_lftp_http() { # $1=timeout $2=cmd
{ # http head request with contentlength=0 reply
echo "[lftp->nodeJS:$JSAPPCTLPORT] sending '$2'"
lftp -c '
set net:timeout 2;
set cmd:long-running 2;
set net:max-retries 2;
set net:reconnect-interval-base '"$1"';
set net:reconnect-interval-multiplier 1;

cd http://127.0.0.1:'"$JSAPPCTLPORT"'/ && cat '"$2"' && exit 0 || exit 1
'
} 0</dev/null 1>&7 2>&8
return $?
}

_con(){
printf "$@" >&7
}

if [ 'console' = "$JSAPPSTART" ]
then
 _con "
Managing \"$NODEJS_APP_NAME\" under \"$OSTYPE\"...

" 7>&1
fi

[ -d "$JSAPPLOGS" ] || {
	mkdir -p "$JSAPPLOGS"
	[ 'console' = "$JSAPPSTART" ] && echo "Created logs dir: $JSAPPLOGS"
}

# start
# * check for running process,
# * if there is one, say it, do nothing, return status: 7 (except 'devstart')
# * else run new, check for running status

# OBSOLETE NOTE: that nodeJS program must manage its pid file itself;
#       this way this script can be sure, that app is running or there are some problems
# NOW: NodeJS has controlling channel via http server process.
# commands: { sts_running, cmd_exit, cmd_stat } 

while [ "$*" ]
do for app_chunk in $NODEJS_APP
do
# service js file:port.controlling port
# srv_dir/srv_name.js:3000.3001
LOGPREF=${app_chunk##*/} ; LOGPREF=${LOGPREF%%:*}.log
JSAPPJOBPORT=${app_chunk##*:}
# must not conflict on the system and be the only one per app
JSAPPCTLPORT=${JSAPPJOBPORT##*.} ; JSAPPJOBPORT=${JSAPPJOBPORT%%.*}
# JSAPPCTLPORT=3001 # JSAPPJOBPORT=3000 

#set -x
if [ 'console' = "$JSAPPSTART" ]
then exec   8>>"$JSAPPLOGS/${LOGPREF}" 7>&1
	_con 7>&8 "
@[`_date`] console cmd=$1 app=$app_chunk
"
else case "$1" in
 'stat') exec 7>/dev/null 8>&7 ;;
 *) exec 7>>"$JSAPPLOGS/${LOGPREF}" 8>&7 ;
 esac
fi
#set +x

# utility
case "$1" in
	'uglify')
		__var=${app_chunk%%:*}
		_con "uglify: $__var
"
		"$NODEJS" -e "(function(srcf,outf){
try {
var fs=require('fs')
	,ujs = require('uglify-js')
	,pro = ujs.uglify
	,ast = ujs.parser.parse(fs.readFileSync(srcf).toString())
	ast = pro.ast_lift_variables(ast)
	ast = pro.ast_mangle(ast)
	ast = pro.ast_squeeze(ast)
	fs.writeFileSync(outf, pro.gen_code(ast, { ascii_only: true }))
	process.exit(0)
} catch (e) { console.log(e) ; process.exit(1) }
})('$__var', '${__var%%.js}_min.js')"
;;
esac
	[ "$__var" ] && {
		unset __var
		break
	} || :

export JSAPPCTLPORT JSAPPJOBPORT
if [ "$MONGOD_SRVs" ]
then # every `node` gets all db connections
MONGODS=`sed 's_/.*__'<<!
$MONGOD_SRVs
!`
export MONGODS
fi

_con "
@[`_date`] cmd=$1 app=$app_chunk
"

if _lftp_http 0 'sts_running' 7>/dev/null 8>&7
then # == REstart: stop, start ==
	case "$1" in
'stop')
_lftp_http 1 'cmd_exit' && {
	_con 'stop sent
'
_lftp_http 2 'sts_running' 7>/dev/null 8>&7 && _exit 1 || _con "${app_chunk}"' stopped
'
} || _con "${app_chunk}"' already dead'
;;# =========
'stat')
_lftp_http 1 'cmd_stat' && _con "
(uptime), runnig status of ${app_chunk}: OK
" || _con "
deep shit happend (see nodeJS logs and handler for ctl's '/cmd_stat' == req.url)
"
# implement memory usage control && restart
# console.log(util.inspect(process.memoryUsage()));
;;# =========
'start')
	_con "${app_chunk}"' already started and is running (stop it first)
'
	_exit 7
;;
'devstart')
	_con "${app_chunk}"' already started, stopping for development
' 	# 'stop' node, and continue this 'devstart' in off-line mode (tweak `shift`)
	set -- "$1" 'stop' "$@"
;;# =========
'tailog')
	tail -f "$JSAPPLOGS/${LOGPREF}"
;;# =========
	esac
else ####### == start ==
	case "$1" in
'start')# =========
     _con "@[`_date`] nodeJS `$NODEJS --version | sed '1!d'` is starting...
"
"$NODEJS" "${app_chunk%%:*}" 0</dev/null 1>&8 2>&8 7>&- 8>&- &
	 _con "${app_chunk} running status: "
	_lftp_http 4 'sts_running' 7>/dev/null 8>&7 && _con "OK
" || {
_err "start failed
" 2>&8
if [ 'console' = "$JSAPPSTART" ]
then tail -n 44 "$JSAPPLOGS/${LOGPREF}"
fi
_exit 1
}
;;
'stat' | 'stop' | 'tailog')# =========
_con "$app_chunk is not running
"
_exit 8
;;# =========
'devstart')
	 while _con "@[`_date`] nodeJS `$NODEJS --version | sed '1!d'` is developing...
"
	 do
		sed '' "$APP_CFG" >"$APP_CFG".lf # reload config
		. "${APP_CFG}.lf" && rm -f "${APP_CFG}.lf"
	 
"$NODEJS" "${app_chunk%%:*}" 0</dev/null 1>&8 2>&8 7>&- 8>&- &
	 _con "${app_chunk} running status: "

	 
	_lftp_http 4 'sts_running' 7>/dev/null && _con "OK
" || {
_err "node is not running
" 2>&8
	tail -n 44 "$JSAPPLOGS/${LOGPREF}"
}
	_con '
to reboot node, press Enter' ; read A
	_lftp_http 4 'sts_running' 7>/dev/null && {
		_lftp_http 1 'cmd_exit'

		_lftp_http 4 'sts_running' 7>/dev/null && _con "hang or zombie
" || _con "reboot ok
"
	} || _con "already dead
"
	 done
;; # =========
'devstartcon')
_con "running nodeJS on console
"
$NODEJS "${app_chunk%%:*}" # 1>&8 2>&8
;;
	esac
fi
export -n JSAPPCTLPORT JSAPPJOBPORT

exec 7>&- 8>&-

done # for app_chunk

shift 1
done # while "$*"

_exit 0

# node+.sh ends here #
olecom
