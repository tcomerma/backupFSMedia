#!/bin/bash
#

RSYNC_CMD="/usr/bin/rsync"
RSYNC_OPTS="-a --force --delete-excluded --delete --inplace --stats"
NSCA="/opt/backupFSMedia/send_nsca.pl"
MAIL="/usr/bin/mailx"

version="v0.1"
__DIR__="$(cd "$(dirname "${0}")"; echo $(pwd))"
__FILE__="${__DIR__}/$(basename "${0}")"

LOG_DIR=${__DIR__}/log
BEGIN=`date +"%Y%m%d_%H%M%S"`
NSCA_CFG=${__DIR__}/conf/send_nsca.cfg

###########
# Funcions
###########

out() {
  local message="$@"
  printf '%b\n' "$message";
}
die() { out "$@"; exit 1; } >&2
log() {
  now=`date +"%Y-%m-%d_%H:%M:%S"`
  printf '%b %-10b| %s\n' $now $1 "${@:2}">> $LOG
}


# Print usage
usage() {
  echo -n "
Script de backup de fitxers de FSMedia
Utilització: $(basename $0) -f FITXER_CONFIG

Script que copia els fitxers de FSMedia
 Options:
  -f      fitxer de configuracio
  -h      Display this help and exit
"
  exit
}

# Captura les excepcions, notifica i neteja
exception() {
    local EX=$1
    log ERR "Proces cancelat per interrupcio $EX"
    notifica ERROR
    rm -f $LOG_RSYNC_ERR
    rm -f $LOG_RSYNC_OUT
    exit 4
}

# Notificacio per correu
notificaCorreu() {
   local STATUS=$1
    cat $LOG | $MAIL -s "BACKUP $NAME $STATUS - ($SRC -> $DST) $BEGIN-$END" ${MAIL_TO}
}

# Notificacio a nagios
notificaNagios() {
   local STATUS=$1
   if [ "$STATUS" = "OK" ]
   then
      echo "$NAGIOS_HOST\t$NAGIOS_SERVICE\t0\t$STATUS Backup $NAME ($SRC -> $DST) correcte $BEGIN-$END\n" | $NSCA -H $NAGIOS_SERVER
   else
      echo "$NAGIOS_HOST\t$NAGIOS_SERVICE\t2\t$STATUS Backup $NAME ($SRC -> $DST) erroni $BEGIN-$END\n" | $NSCA -H $NAGIOS_SERVER
   fi
}


notifica() {
   local STATUS=$1
   if [ ! -z "$MAIL_TO" ]
   then
      notificaCorreu $STATUS
   fi
   if [ ! -z "$NAGIOS_SERVER" ]
   then
      notificaNagios $STATUS
   fi
}


###########
# Programa Principal
###########


# Processar parametres
  while getopts "f:o:d:bh" flag
  do
      case "$flag" in
      (h) echo "$__FILE__: versio $version$"; usage;;
      (f) FITXER="$OPTARG";;
      (*) usage;;
      esac
  done

# Comprovar parametres
[ -z "$FITXER" ] && die "No s'ha indicat -f"
[ -f "$FITXER" ] || die "No existeix el fitxer de parametres (-f)"

# Carregar fitxer de configuracio i validar
. $FITXER
[ -z "$NAME" ] && die "No s'ha indicat NAME en fitxer de configuracio $FITXER"
[ -z "$SRC" ] && die "No s'ha indicat SRC en fitxer de configuracio $FITXER"
[ -z "$DST" ] && die "No s'ha indicat DST en fitxer de configuracio $FITXER"
[ -z "$FILESYSTEM" ] && die "No s'ha indicat FILESYSTEM en fitxer de configuracio $FITXER"
[ -z "$SNAPSHOT_NUM" ] && die "No s'ha indicat SNAPSHOT_NUM en fitxer de configuracio $FITXER"

# Configurar entorn
LOG=$LOG_DIR/$NAME-$BEGIN.log
LOG_RSYNC_OUT=$LOG_DIR/$NAME-$BEGIN.rsync.log
LOG_RSYNC_ERR=$LOG_DIR/$NAME-$BEGIN.rsync.err


# Captura excepcions
trap exception SIGHUP SIGINT SIGTERM

log INFO ----------------------------------------------------------
log INFO Inici
log INFO "Config: $FITXER"
log INFO "Nom: $NAME"
log INFO "Comanda rsync: $RSYNC_CMD $RSYNC_OPTS $SRC/ $DST/"

# Executar rsync
$RSYNC_CMD $RSYNC_OPTS $SRC/ $DST/ > $LOG_RSYNC_OUT 2> $LOG_RSYNC_ERR
ERR=$?

# Comprovar estat de finalitzacio
if [ "$ERR" != "0" ]
then
   if [ "$ERR" != "24" ]
   then
      # ERROR 24 (vanished files) indica que s'han esborrat fitxers entre que s'ha fet la llista i s'han copiat
      # els fitxers. Normal
      log ERR "rsync ha acabat amb error $ERR"
      log ERR "Sortida de error de rsync"
      log ERR "----------------------------------------------"
      cat $LOG_RSYNC_ERR >> $LOG
      log INFO "Sortida de rsync"
      log INFO "----------------------------------------------"
      cat $LOG_RSYNC_OUT >> $LOG
      notifica ERROR
      exit 1
   fi
fi
log INFO "Rsync finalitzat amb exit"
log INFO "Sortida de rsync"
log INFO "----------------------------------------------"
cat $LOG_RSYNC_OUT >> $LOG
# Crear nou snapshot
log INFO "Creant Snapshot"
log INFO "Comanda snapshot: zfs snapshot ${DST}@${BEGIN}"

zfs snapshot ${FILESYSTEM}@${BEGIN} > $LOG_RSYNC_OUT 2> $LOG_RSYNC_ERR
ERR=$?

# Comprovar estat de finalitzacio
if [ "$ERR" != "0" ]
then
      log ERR "zfs snapshot ha acabat amb error $ERR"
      log ERR "Sortida de error de zfs snapshot"
      log ERR "----------------------------------------------"
      cat $LOG_RSYNC_ERR >> $LOG
      log INFO "Sortida de zfs snapshot"
      log INFO "----------------------------------------------"
      cat $LOG_RSYNC_OUT >> $LOG
      notifica ERROR
      exit 2
else
     log INFO "Snapshot creat"
fi

# Purgar snapshots antics
log INFO "Buscant Snapshots a eliminar"

rm -f $LOG_RSYNC_ERR
rm -f $LOG_RSYNC_OUT
COUNT=0
zfs list -H -t snapshot -o name,used,creation -r $FILESYSTEM | sort -r |
while read NAME SIZE DATE
do
   if [ $COUNT -ge $SNAPSHOT_NUM ]
   then
     log INFO "Eliminant snapshot $NAME"
     zfs destroy $NAME >> $LOG_RSYNC_OUT 2>> $LOG_RSYNC_ERR
   fi
   COUNT=$((COUNT+1))
done
# Comprovar si hi ha hagut algun problema amb la eliminacio dels snapshots
if [ -s $LOG_RSYNC_ERR ]
then
      log ERR "Error al eliminar snapshots"
      log ERR "Sortida de error de zfs destroy"
      log ERR "----------------------------------------------"
      cat $LOG_RSYNC_ERR >> $LOG
      log INFO "Sortida de zfs destroy"
      log INFO "----------------------------------------------"
      cat $LOG_RSYNC_OUT >> $LOG
      notifica ERROR
      exit 3
fi

log INFO "Final"
log INFO "----------------------------------------------------------"
END=`date +"%Y%m%d_%H%M%S"`
rm -f $LOG_RSYNC_ERR
rm -f $LOG_RSYNC_OUT
# Notificar
notifica OK
exit 0