#!/bin/sh
# v000 2012-03-26 mongodb+.sh # v001 2012-03-27 Masterpiece
# v003 2012-04-10 `_start` to run multiple clients under w32 
#      "mongo": start mongo shell for all db chuncks (uses `_start`)
set -e

[ "$*" ] || { echo "
Usage: $0"' app_name.conf [&|] {start, stop, stat, mongo}
(script, abs path app config file,   command)
Managing of `mongodb` memory server under cygwin or linux-gnu OSes
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
printf '[error] '"$@" >&2
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
	PATH="/bin:/bin.w32:$PATH"
	_start(){
	cmd /C start "$@"
	}
;;
*linux_gnu*) # OSTYPE=linux-gnu ???
	LD_LIBRARY_PATH="/usr/local/bin:$LD_LIBRARY_PATH"
	case "$PATH" in
	  *"/usr/local/bin"*) ;;
	  *) PATH="/usr/local/bin:$PATH" ;;
	esac
	_start(){
	"$@"
	}
;;
esac
# including config here; make \r\n -> \n trasformation
sed '' "$1" >"$1".lf
. "${1}.lf" && rm -f "${1}.lf"
shift 1
#
export PATH LD_LIBRARY_PATH
export -n JSAPPSTART

_date() { # ISO date
date -u '+%Y-%m-%dT%H:%M:%SZ'
}

_lftp_http() { # $1=timeout $2=cmd $3=real_url
{ # http head request with contentlength=0 reply
echo "[lftp->mongodb:${admin_web_console=$((1000 + ${DBADDR##*:}))}] sending '$2'"
lftp -c '
set net:timeout 2;
set cmd:long-running 2;
set net:max-retries 2;
set net:reconnect-interval-base '"$1"';
set net:reconnect-interval-multiplier 1;

cd http://127.0.0.1:'"${admin_web_console}"'/ && cat '"$3"' && exit 0 || exit 1
'
} 0</dev/null 2>&8
return $?
}

_mongo() { # $1=cmd
{
case "$1" in
#'cmd_stat') -- OLD PLAN --  cmd='print(tojson(getMemInfo()))';;
'sts_running' | 'cmd_stat') #cmd='quit()'
a=`_lftp_http 1 "$1" '/serverStatus' 7>&1` ; b=$?
echo "$a" | sed 's/.*\("uptime"[^,]*\),.*/\1/p;1!d'
return $b
;;
'cmd_exit') cmd='db.shutdownServer(1);quit()';;
* ) cmd=$1;;
esac

echo "[mongo->mongodb] sending '$1'"
"$MONGO" --eval "$cmd" "$DBADDR/admin"
} 0</dev/null 1>&7 2>&8
return $?
}

_con(){
printf "$@" >&7
}

#set -x#set +x
if [ 'console' = "$JSAPPSTART" ]
then _con "
Managing mongodb under \"$OSTYPE\"...

"
[ "$MONGOD_SRVs" ] || { _con '
development: $MONGOD_SRVs config is empty, nothing to start.

'
exit 0
}
fi 7>&1

[ -d "$JSAPPLOGS" ] || {
	mkdir -p "$JSAPPLOGS"
	[ 'console' = "$JSAPPSTART" ] && echo "Created logs dir: $JSAPPLOGS"
}

while [ "$*" ]
do for db_chunk in $MONGOD_SRVs
do

# "url:port/fs/path2/db" like this "127.0.0.1:27017/_data/db"
DBADDR=${db_chunk%%/*} # 127.0.0.1:27017
LOGPREF=`sed 's"/"_"' <<!
${db_chunk#*/}
!`.log # _data_db.log

if [ 'console' = "$JSAPPSTART" ]
then exec 8>>"$JSAPPLOGS/${LOGPREF}" 7>&1
else case "$1" in
 'stat') exec 7>/dev/null 8>&7 ;;
 *) exec 7>>"$JSAPPLOGS/${LOGPREF}" 8>&7 ;
 esac
fi

if _mongo 'sts_running' 7>/dev/null 8>&7
then # == REstart: stop, start ==
	case "$1" in
	'stop')
_mongo 'cmd_exit' 7>/dev/null 8>&7 && {
	_con 'stop sent
'
_mongo 'sts_running' 7>/dev/null 8>&7 && _exit 1 || _con "mongodb for '${db_chunk}'"' stopped
'
} || _con "${db_chunk}"' already dead'
;;
	'stat')
_mongo 'cmd_stat' && _con "
runnig status of mongodb '${db_chunk}': OK
" || _con "
deep shit happend
"
;;
	'start')
	_con "mongodb for '${db_chunk}'"' already started and is running
'
	_exit 7
;;
	'mongo')
	_con "starting mongodb shell for '$db_chunk'"'
'
	_start mongo "${db_chunk%%/*}"

	_exit $?
;;
	esac
else # == start ==
	case "$1" in
	'start')
	{ [ -d "${db_path=${db_chunk#*/}}" ] || {
	   _con "creating '$db_path': "
	   mkdir -p "$db_path" && _con "OK 
"   ; }
    } && {
     _con "@[`_date`] `$MONGOD --version | sed '1!d'` is starting...
"
$MONGOD  --repair --upgrade --dbpath "$db_path" 0</dev/null 1>&8 2>&8 7>&- 8>&-
$MONGOD  --bind_ip "${DBADDR%%:*}" --port "${DBADDR##*:}" \
	     --dbpath "$db_path" 0</dev/null 1>&8 2>&8 7>&- 8>&- &
	 _con "'${db_chunk}' running status: "
	 _mongo 'sts_running' 7>/dev/null 8>&7 && _con "OK
" ; } || {
_err "Error
"
if [ 'console' = "$JSAPPSTART" ]
then tail "$JSAPPLOGS/${LOGPREF}"
fi
_exit 1
}
;;
	'stat' | 'stop' | 'mongo')
_con "mongodb for '$db_chunk' is not running
"
_exit 8
;;
	esac
fi
exec 7>&- 8>&-

done # for db_chunks

shift 1
done # while "$*" script commands

_exit 0

# mongodb+.sh ends here #
olecom
