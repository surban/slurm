#!/bin/sh
#
# chkconfig: 345 90 10
# description: SLURM is a simple resource management system which \
#              manages exclusive access o a set of compute \
#              resources and distributes work to those resources.
#
# processname: /usr/sbin/slurmd 
# pidfile: /var/run/slurm-llnl/slurmd.pid
#
# processname: /usr/sbin/slurmctld
# pidfile: /var/run/slurm-llnl/slurmctld.pid
#
# config: /etc/default/slurm-llnl
#
### BEGIN INIT INFO
# Provides:          slurm-llnl
# Required-Start:    $remote_fs $syslog $network munge
# Required-Stop:     $remote_fs $syslog $network munge
# Should-Start:      $named
# Should-Stop:       $named
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: slurm daemon management
# Description:       Start slurm to provide resource management
### END INIT INFO

BINDIR=/usr/bin
CONFDIR=/etc/slurm-llnl
LIBDIR=/usr/lib
SBINDIR=/usr/sbin

# Source slurm specific configuration
if [ -f /etc/default/slurm-llnl ] ; then
    . /etc/default/slurm-llnl
else
    SLURMCTLD_OPTIONS=""
    SLURMD_OPTIONS=""
fi

# Checking for slurm.conf presence
if [ ! -f $CONFDIR/slurm.conf ] ; then
    if [ -n "$(echo $1 | grep start)" ] ; then
      echo Not starting slurm-llnl
    fi
      echo slurm.conf was not found in $CONFDIR
      echo Please follow the instructions in \
            /usr/share/doc/slurm-llnl/README.Debian.gz
    exit 0
fi


test -f $BINDIR/scontrol || exit 0
DAEMONLIST=$($BINDIR/scontrol show daemons 2>/dev/null)
if [ $? = 0 ] ; then
  for prog in $DAEMONLIST ; do 
    test -f $SBINDIR/$prog || exit 0
  done
else
  if [ -n "$(echo $1 | grep start)" ] ; then
    echo "Not starting slurm-llnl for problems in the configuration file"
  else
    echo "Problems in the configuration file"
  fi
  echo "${CONFDIR}/slurm.conf"
  echo "If upgrading from version 1.2 it is recommended that you rebuild"
  echo "your configuration file. Please read instructions in"
  echo "     /usr/share/doc/slurm-llnl/README.Debian"
  echo "Otherwise use \"scontrol show daemons\" for more information"
  exit 0
fi

#Checking for lsb init function
if [ -f /lib/lsb/init-functions ] ; then
  . /lib/lsb/init-functions
else
  echo Can\'t find lsb init functions 
  exit 1
fi

# setup library paths for slurm and munge support
export LD_LIBRARY_PATH=$LIBDIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}

#Function to check for cert and key presence and key vulnerabilty
checkcertkey()
{
  MISSING=""
  keyfile=""
  certfile=""

  if [ "$1" = "slurmd" ] ; then 
    keyfile=$(grep JobCredentialPublicCertificate $CONFDIR/slurm.conf \
                  | grep -v "^ *#")
    keyfile=${keyfile##*=}
    keyfile=${keyfile%#*}
    [ -e $keyfile ] || MISSING="$keyfile"
  elif [ "$1" = "slurmctld" ] ; then 
    keyfile=$(grep JobCredentialPrivateKey $CONFDIR/slurm.conf | grep -v "^ *#")
    keyfile=${keyfile##*=}
    keyfile=${keyfile%#*}
    [ -e $keyfile ] || MISSING="$keyfile"
  fi

  if [ "${MISSING}" != "" ] ; then
    echo Not starting slurm-llnl
    echo $MISSING not found
    echo Please follow the instructions in \
  	  /usr/share/doc/slurm-llnl/README.cryptotype-openssl
    exit 0
  fi

  if [ -f "$keyfile" ] && [ "$1" = "slurmctld" ] ; then
    keycheck=$(openssl-vulnkey $keyfile | cut -d : -f 1)
    if [ "$keycheck" = "COMPROMISED" ] ; then 
      echo Your slurm key stored in the file $keyfile
      echo is vulnerable because has been created with a buggy openssl.
      echo Please rebuild it with openssl version \>= 0.9.8g-9
      echo More information in /usr/share/doc/slurm-llnl/README.Debian
      exit 0
    fi
  fi
}

get_daemon_description()
{
    case $1 in 
      slurmd)
        echo slurm compute node daemon
	;;
      slurmctld)
	echo slurm central management daemon
	;;
      *)
	echo slurm daemon
	;;
    esac
}

start() {
  CRYPTOTYPE=$(grep CryptoType $CONFDIR/slurm.conf | grep -v "^ *#")
  CRYPTOTYPE=${CRYPTOTYPE##*=}
  CRYPTOTYPE=${CRYPTOTYPE%#*}
  if [ "$CRYPTOTYPE" = "crypto/openssl" ] ; then
    checkcertkey $1
  fi

  # Create run-time variable data
  mkdir -p /var/run/slurm-llnl
  chown slurm:slurm /var/run/slurm-llnl

  # Checking if SlurmdSpoolDir is under run
  if [ "$1" = "slurmd" ] ; then
    SDIRLOCATION=$(grep SlurmdSpoolDir /etc/slurm-llnl/slurm.conf \
                       | grep -v "^ *#")
    SDIRLOCATION=${SDIRLOCATION##*=}
    SDIRLOCATION=${SDIRLOCATION%#*}
    if [ "${SDIRLOCATION}" = "/var/run/slurm-llnl/slurmd" ] ; then
      if ! [ -e /var/run/slurm-llnl/slurmd ] ; then
        ln -s /var/lib/slurm-llnl/slurmd /var/run/slurm-llnl/slurmd
      fi
    fi
  fi
    
  # Checking if StateSaveLocation is under run
  if [ "$1" = "slurmctld" ] ; then
    SDIRLOCATION=$(grep StateSaveLocation /etc/slurm-llnl/slurm.conf \
                       | grep -v "^ *#")
    SDIRLOCATION=${SDIRLOCATION##*=}
    SDIRLOCATION=${SDIRLOCATION%#*}
    if [ "${SDIRLOCATION}" = "/var/run/slurm-llnl/slurmctld" ] ; then
      if ! [ -e /var/run/slurm-llnl/slurmctld ] ; then
        ln -s /var/lib/slurm-llnl/slurmctld /var/run/slurm-llnl/slurmctld
      fi
    fi
  fi

  desc="$(get_daemon_description $1)"
  log_daemon_msg "Starting $desc" "$1"
  unset HOME MAIL USER USERNAME 
  #FIXME $STARTPROC $SBINDIR/$1 $2
  STARTERRORMSG="$(start-stop-daemon --start --oknodo \
    			--exec "$SBINDIR/$1" -- $2 2>&1)"
  STATUS=$?
  log_end_msg $STATUS
  if [ "$STARTERRORMSG" != "" ] ; then 
    echo $STARTERRORMSG
  fi
  touch /var/lock/slurm
}

stop() { 
    desc="$(get_daemon_description $1)"
    log_daemon_msg "Stopping $desc" "$1"
    STOPERRORMSG="$(start-stop-daemon --oknodo --stop -s TERM \
    			--exec "$SBINDIR/$1" 2>&1)"
    STATUS=$?
    log_end_msg $STATUS
    if [ "$STOPERRORMSG" != "" ] ; then 
      echo $STOPERRORMSG
    fi
    rm -f /var/lock/slurm
}

startall() {
    for PROG in $DAEMONLIST ; do
      case $PROG in 
        slurmd)
	  OPTVAR=$SLURMD_OPTIONS
	  ;;
        slurmctld)
	  OPTVAR=$SLURMCTLD_OPTIONS
	  ;;
        *)
	  ;;
      esac
      start $PROG $OPTVAR
    done
}

getpidfile() {
    dpidfile=`grep -i ${1}pid $CONFDIR/slurm.conf | grep -v '^ *#'`
    if [ $? = 0 ]; then
        dpidfile=${dpidfile##*=}
        dpidfile=${dpidfile%#*}
    else
        dpidfile=/var/run/${1}.pid
    fi

    echo $dpidfile
}

#
# status() with slight modifications to take into account
# instantiations of job manager slurmd's, which should not be
# counted as "running"
#
slurmstatus() {
    base=${1##*/}

    pidfile=$(getpidfile $base)

    pid=`pidof -o $$ -o $$PPID -o %PPID -x $1 || \
         pidof -o $$ -o $$PPID -o %PPID -x ${base}`

    if [ -f $pidfile ]; then
        read rpid < $pidfile
        if [ "$rpid" != "" -a "$pid" != "" ]; then
            for i in $pid ; do
                if [ "$i" = "$rpid" ]; then 
                    echo "${base} (pid $pid) is running..."
                    return 0
                fi     
            done
        elif [ "$rpid" != "" -a "$pid" = "" ]; then
#           Due to change in user id, pid file may persist 
#           after slurmctld terminates
            if [ "$base" != "slurmctld" ] ; then
               echo "${base} dead but pid file exists"
            fi
            return 1
        fi 

    fi

    if [ "$base" = "slurmctld" -a "$pid" != "" ] ; then
        echo "${base} (pid $pid) is running..."
        return 0
    fi
     
    echo "${base} is stopped"
    
    return 3
}

#
# stop slurm daemons, 
# wait for termination to complete (up to 10 seconds) before returning
#
slurmstop() {
    for prog in $DAEMONLIST ; do
       stop $prog
       for i in 1 2 3 4
       do
          sleep $i
          slurmstatus $prog
          if [ $? != 0 ]; then
             break
          fi
       done
    done
}

#
# The pathname substitution in daemon command assumes prefix and
# exec_prefix are same.  This is the default, unless the user requests
# otherwise.
#
# Any node can be a slurm controller and/or server.
#
case "$1" in
    start)
	startall
        ;;
    startclean)
        SLURMCTLD_OPTIONS="-c $SLURMCTLD_OPTIONS"
        SLURMD_OPTIONS="-c $SLURMD_OPTIONS"
        startall
        ;;
    stop)
	slurmstop
        ;;
    status)
	for prog in $DAEMONLIST ; do
	   slurmstatus $prog
	done
        ;;
    restart)
        $0 stop
        $0 start
        ;;
    force-reload)
        $0 stop
        $0 start
	;;
    condrestart)
        if [ -f /var/lock/subsys/slurm ]; then
            for prog in $DAEMONLIST ; do
                 stop $prog
                 start $prog
            done
        fi
        ;;
    reconfig)
	for prog in $DAEMONLIST ; do
	    PIDFILE=$(getpidfile $prog)
	    start-stop-daemon --stop --signal HUP --pidfile \
	    	"$PIDFILE" --quiet $prog
	done
	;;
    test)
	for prog in $DAEMONLIST ; do   
	    echo "$prog runs here"
	done
	;;
    *)
        echo "Usage: $0 {start|startclean|stop|status|restart|reconfig|condrestart|test}"
        exit 1
        ;;
esac
