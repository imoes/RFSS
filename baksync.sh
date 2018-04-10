#!/bin/bash
#
# baksync.sh: Script zur Datensicherung mittels Rsync
#
# Version 1.0
# 08.12.2006
#
#
#


[ "$#" == "0" ] && echo "Die Option -h gibt Hilfe zum Script aus !" && exit 1

# Sind wir interaktiv oder als cronjob unterwegs ?
case `tty` in /dev/* )
        interactive="1"
        logcommand="echo"
        ;;
 * )
        interactive="0"
        logcommand="logger"
        ;;
esac

check_srcHost="0"
check_localSrc="0"
check_localTrgt="0"
check_excludeFile="0"
check_logfile="0"
pretend="0"
logfile="/dev/null"
sshOpt=""
HDminFree="15"
localBakSync="0"

# Optionen pruefen
while getopts "hc:s:t:e:pf:l" option
do
  case $option in
    h)
cat << "EOF"
        Das Script erstellt ein Backup mittels RSYNC.

        1. Backup über das Netzwerk (SSH+RSYNC)
           Von '/' ausgehend wird ein gesamtes System gesichert.
           Wichtig: Es MUSS ein exclude File angegeben werden dass
                    mindestens die Pfade /proc/* und /SYS/* ausschliesst.
           Der SSH Zugang zum Quellhost sollte ohne Interaktion moeglich sein.
        2. Backup von localhost (RSYNC ohne SSH)
           Es wird lokal ein Verzeichnisbaum rekursiv gespiegelt, dies muss nicht / sein.
           Wichtig: Excludes sind hier relativ vom Quellpfad angegeben.
           z.B. verzeichnis1/*

        Parameter:
        -h                      Diese Hilfe anzeigen.
        -c FQDN                 FQDN eines entfernten Hosts oder 'localhost' oder '127.0.0.1'
                                 fuer ein lokales Backup. Erfordert -s und schliesst -o aus !
        -s /home/user           Nur bei lokalem Backup ! Lokaler Quellpfad.
        -t /home/backup         Pfad zum lokalen Zielverzeichnis.
                                 Darin wird ein Verzeichnis mit dem FQDN des Quellhosts angelegt.
                                 Darin ein Verzeichnis daily.0.
        -e /etc/bak/excludes    Pfad zur exclude Datei bei entferntem Backup.
                                 Inhalt mindestens: /proc/* und /sys/*
                                 Bei lokalem Backup relative Pfade ab Quellpfad.
        -o /etc/bak/sshopts     Optional ! Pfad zu den Dateien mit SSH Optionen. (to be implemented)
        -p                      pretend, tut nichts, zeigt nur an was passieren wuerde.
        -f 40                   Wieviel % Platz muss auf dem lokalen System frei sein
                                 damit das RSYNC starten darf. Default: 15 %.
        -l                      Logfile erzeugen.

        Beispiele:
        ./baksync.sh -c my.host.com -t -t /var/backup -e /home/excludes/excl_my.host.com
        ./baksync.sh -c localhost -s /home -t /var/backup -l /var/backup/localhost.log

EOF
        exit 0
        ;;
    c)  srcHost="$OPTARG"
        check_srcHost="1"
        ;;
    s)  localSrc="$OPTARG"
        check_localSrc="1"
        ;;
    t)  localTrgt="$OPTARG"
        check_localTrgt="1"
        ;;
    e)  excludeFile="$OPTARG"
        check_excludeFile="1"
        ;;
    o)  sshOptFile="$OPTARG"
        ;;
    p)  pretend="1"
        ;;
    w)  winConvert="1"
        ;;
    f)  HDminFree=$OPTARG
        ;;
    l)  check_logfile="1"
        ;;
#    w)  winConvert=1
#       which unix2dos 2>1 >/dev/null
#       [ "$?" != "0" ] && echo "Achtung: Das Tool unix2dos ist nicht installiert !"
#        ;;
    \?) echo falsche Argumente
        ;;
  esac
done


# Check, wurde ein Hostname angegeben ?
[ "$check_srcHost" != "1" ] && echo "Kritischer Abbruch: Parameter -c mit FQDN Hostname fehlt !" && exit 2
[ "$srcHost" == "localhost" -o "$srcHost" == "127.0.0.1" ] && srcHost="localhost" && localBakSync="1"

[ "$check_logfile" == "1" ] && logfile="${localTrgt}/${srcHost}/${srcHost}.log"

# Check, wurde ein Quellverzeichnis angegeben ?
[ "$srcHost" == "localhost" -a "$check_localSrc" != "1" ] && echo "Kritischer Abbruch: Parameter -s mit Quellverzeichnis fehlt !" && exit 2

# Check, wurde ein Zielverzeichnis angegeben ?
[ "$check_localTrgt" != "1" ] && echo "Kritischer Abbruch: Parameter -t mit Pfad zum Backupverzeichnis fehlt !" && exit 3
[ ! -d $localTrgt ] && echo "Kritischer Abbruch: Zielverzeichnis exisitiert nicht !" && exit 4

# Check, wurde ein Exclude Path angegeben ?
#
# Entfernter Sync erfordert zwingend $excludeFile
[ "$localBakSync" != "1" -a "$check_excludeFile" == "0" ] && \
        $logcommand "Kritischer Abbruch: Es wird eine Exclude Datei benoetigt !" && \
        exit 3
# Wurde ein Exclude File angegeben muss es existieren
[ "$localBakSync" != "1" -a "$check_excludeFile" != "1" ] && \
        $logcommand "Kritischer Abbruch: Es wurde keine Exclude Datei definiert !" && \
        exit 3
[ "$localBakSync" != "1" ] && [ ! -f $excludeFile ] && \
        $logcommand "Kritischer Abbruch: Exclude Datei existiert nicht !" && \
        exit 3
[ "$check_excludeFile" == "1" ] && excludeString="--delete-excluded --exclude-from=${excludeFile}"


# Check, wurde eine Datei mit SSH ExtraOptionen angegeben ?
sshOptFile="${sshOptFile}/${srcHost}"
[ -f "$sshOptFile" ] && sshOpt=`cat $sshOptFile`

# Check, wurde ein MinFree Wert angegeben ?
[ "check_HDminFree" == "0" ] && HDminFree=85

# Check, reicht freier Plattenplatz
getPercentage='s/.* \([0-9]\{1,3\}\)%.*/\1/'
KBused='df /$localTrgt | tail -n1 | sed -e "$getPercentage"'
inodesUsed='df -i /$localTrgt | tail -n1 | sed -e "$getPercentage"'
KBfree='expr 100 - $KBused'
inodesFree='expr 100 - $inodesUsed'
if [ $HDminFree -gt $KBfree -o $HDminFree -gt $inodesFree ] ; then
        $logcommand "Fehler: Nicht genug Platz fuer das RSYNC Backup !"
        exit 3
fi


# Ggf. Verzeichnis anlegen
[ "$localBakSync" == "0" -a -d ${localTrgt}/${srcHost}/daily.0 ] && mkdir -p ${localTrgt}/${srcHost}/daily.0

[ ! -d $localTrgt/$srcHost ] && mkdir -p $localTrgt/$srcHost

# Los geht`s: rsync zieht ein Vollbackup
echo "Starting rsync backup from $srcHost..." >> $logfile
logger "Starting rsync backup from $srcHost..."

if [ "${localSrc}" == "/" ]; then
localSrc="/"
else
localSrc="${localSrc}/"
fi

[ "$localBakSync" == "1" -a "$pretend" == "0" ] && rsync  -av --delete --delete-before $excludeString ${localSrc} ${localTrgt}/$srcHost/daily.0/ 2>&1 > $logfile
[ "$localBakSync" == "1" -a "$pretend" == "1" ] && echo -e "\nI would execute:\nrsync  -av --delete $excludeString ${localSrc} ${localTrgt}/$srcHost/daily.0/ 2>&1 > $logfile\n"
[ "$localBakSync" == "0" -a "$pretend" == "0" ] && rsync  -avz --numeric-ids -e ssh --delete-before --delete $excludeString $sshOpt $srcHost:/ $localTrgt/$srcHost/daily.0 2>&1 > $logfile
[ "$localBakSync" == "0" -a "$pretend" == "1" ] && echo -e "\nI would execute:\nrsync  -avz --numeric-ids -e ssh --delete $excludeString $sshOpt $srcHost:/ $localTrgt/$srcHost/daily.0 2>&1 > $logfile\n"

# Rueckgabewert pruefen.
# 0 = fehlerfrei,
# 24 ist harmlos; tritt auf, wenn waehrend der Laufzeit
# von rsync noch Dateien veraendert oder geloescht wurden.
# Alles andere ist fatal - siehe man (1) rsync
if ! [ $? != 0 ] ; then
        if [ "$interactive" == "1" ]; then
            $logcommand "Fatal: rsync finished $srcHost with errors!"
            $logcommand "ErrCode: ${?}"
            $logcommand "0 = OK   24 = harmless, file changed during rsync   other = fatal"
        fi
        echo "Fatal: rsync finished $srcHost with errors!" >> $logfile
        echo "ErrCode: ${?}" >> $logfile
        echo "0 = OK   24 = harmless, file changed during rsync   other = fatal" >> $logfile
        logger "Fatal: rsync finished $srcHost with errors! ErrCode: ${?}, 24 maybe harmless..."
        logger "ErrCode: ${?}"
        logger "0 = OK   24 = harmless, file changed during rsync   other = fatal"
fi


# Verzeichnis anfassen, um Backup-Datum zu verewigen.
  [ -d $localTrgt/$srcHost/daily.0 ] && touch $localTrgt/$srcHost/daily.0


# Fertig!
echo "Finished rsync backup from $srcHost..." >> $logfile
logger "Finished rsync backup from $srcHost..."

# Sicher ist sicher...
sync


# Falls kein Logfile gewuenscht wurde
[ "$check_logfile" == "0" -a "$logfile" != "/dev/null" ] && rm -f $logfile
[ "$check_logfile" == "1" ] && touch $logfile
exit 0
