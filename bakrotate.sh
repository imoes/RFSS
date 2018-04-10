#!/bin/bash
#
# bakrotate.sh: Script rotiert Backup-Verzeichnisse mittels Hardlinks
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

check_daily="0"
check_weekly="0"
check_monthly="0"
check_yearly="0"
HDminFree="10"

# Optionen pruefen
while getopts "hp:f:d:w:m:y:" option
do
  case $option in
    h)
cat << "EOF"
        Das Script erwartet ein Zielverzeichnis mit Pfadangabe
        als Parameter. z.B.  bakrotate.sh -p /home/server.domain.com
        Darin muss sich ein Verzeichnis daily.0 befinden.
        Das Verzeichnis wird dann rotiert wie angegeben.
        daily.0 -> daily.1 -> daily.2 ...
        daily.0 -> weekly.0 -> weekly.1 ...
        daily.0 -> monthly.0 -> monthly.1 ...
        daily.0 -> yearly.0 -> yearly.1 ...

        Parameter:
        -h                      Diese Hilfe anzeigen.
        -p                      Pfadangabe exklusive des daily.0 Verzeichnisses.
        -f 40                   Wieviel % Platz muss auf dem lokalen System frei sein
                                 damit das rotate starten darf. Default: 10 %.
        -d 7                    Optional, wie viele Tagessicherungen sollen rotiert werden
        -w 4                    Optional, wie viele Wochensicherungen sollen rotiert werden
        -m 12                   Optional, wie viele Monatssicherungen sollen rotiert werden
        -y 3                    Optional, wie viele Jahressicherungen sollen rotiert werden

        Mindestens ein Parameter -d -w -m -y muss gesetzt sein, sonst passiert nichts.

EOF
        exit 0
        ;;
    p)  rotateDir=$OPTARG
        ;;
    f)  HDminFree=$OPTARG
        ;;
    d)  daily=$OPTARG
        check_daily="1"
        ;;
    w)  weekly=$OPTARG
        check_weekly="1"
        ;;
    m)  monthly=$OPTARG
        check_monthly="1"
        ;;
    y)  yearly=$OPTARG
        check_yearly="1"
        ;;
    \?) echo falsche Argumente
        ;;
  esac
done


# Check, wurde ein zu rotierendes Verzeichnis angegeben ?
[ ! -d $rotateDir/daily.0 ] && echo "Abbruch: Parameter -d fehlt oder daily.0 Verzeichnis existiert nicht !" && exit 2


# Soll ueberhaupt irgendetwas rotiert werden ?
[ "$check_daily" == "0" -a "$check_weekly" == "0" -a "$check_monthly" == "0" -a "$check_yearly" == "0" ] && \
        echo "Abbruch: es gibt nichts zu rotaten !" && exit 2


# Pruefe auf freien Plattenplatz
getPercentage='s/.* \([0-9]\{1,3\}\)%.*/\1/'
KBused=$(df /$rotateDir | tail -n1 | sed -e "$getPercentage")
KBfree=$(expr 100 - $KBused)
inodesUsed=$(df -i /$rotateDir | tail -n1 | sed -e "$getPercentage")
inodesFree=$(expr 100 - $inodesUsed)
if [ $KBfree -lt $HDminFree -o $inodesFree -lt $HDminFree ] ; then
    $logcommand "Fatal: Not enough space left for rotating backups!"
    exit 2
fi


# Pruefe Werte auf Gueltigkeit und mache den rotate

if [ "$check_daily" == "1" ]; then
  if expr "$daily" : '[0-9]\+' >/dev/null ; then
        # Das hoechste Backup abloeschen
        [ -d ${rotateDir}/daily.${daily} ] && rm -rf ${rotateDir}/daily.${daily}
        # Alle anderen Snapshots eine Nummer nach oben verschieben
        count=$(expr $daily - 1)
        while [ $count -gt 0 ]
        do
          if [ -d $rotateDir/daily.$count ] ; then
                new=$[ $count + 1 ]
                # Datum sichern
                touch $rotateDir/.timestamp -r $rotateDir/daily.$count
                mv -f $rotateDir/daily.$count $rotateDir/daily.$new
                # Datum zurueckspielen
                touch $rotateDir/daily.$new -r $rotateDir/.timestamp
          fi
        count=$(expr $count - 1)
        done
        # Snapshot von Level-0 per hardlink-Kopie nach Level-1 kopieren
         [ -d $rotateDir/daily.0 ] && cp -al $rotateDir/daily.0/ $rotateDir/daily.1
  else
        $logcommand "$daily ist ein ungueltiger Wert fuer den Parameter -d"
  fi
fi


if [ "$check_weekly" == "1" ]; then
  if expr "$weekly" : '[0-9]\+' >/dev/null ; then
        # Das hoechste Backup abloeschen
        [ -d ${rotateDir}/weekly.${weekly} ] && rm -rf ${rotateDir}/weekly.${weekly}
        # Alle anderen Snapshots eine Nummer nach oben verschieben
        count=$(expr $weekly - 1)
        while [ $count -gt 0 ]
        do
          if [ -d $rotateDir/weekly.$count ] ; then
                new=$[ $count + 1 ]
                # Datum sichern
                touch $rotateDir/.timestamp -r $rotateDir/weekly.$count
                mv -f $rotateDir/weekly.$count $rotateDir/weekly.$new
                # Datum zurueckspielen
                touch $rotateDir/weekly.$new -r $rotateDir/.timestamp
          fi
        count=$(expr $count - 1)
        done
        # Snapshot von Level-0 per hardlink-Kopie nach Level-1 kopieren
        [ -d $rotateDir/daily.0 ] && cp -al $rotateDir/daily.0 $rotateDir/weekly.0
  else
        $logcommand "$weekly ist ein ungueltiger Wert fuer den Parameter -w"
  fi
fi


if [ "$check_monthly" == "1" ]; then
  if expr "$monthly" : '[0-9]\+' >/dev/null ; then
        # Das hoechste Backup abloeschen
        [ -d ${rotateDir}/monthly.${monthly} ] && rm -rf ${rotateDir}/monthly.${monthly}
        # Alle anderen Snapshots eine Nummer nach oben verschieben
        count=$(expr $monthly - 1)
        while [ $count -gt 0 ]
        do
          if [ -d $rotateDir/monthly.$count ] ; then
                new=$[ $count + 1 ]
                # Datum sichern
                touch $rotateDir/.timestamp -r $rotateDir/monthly.$count
                mv -f $rotateDir/monthly.$count $rotateDir/monthly.$new
                # Datum zurueckspielen
                touch $rotateDir/monthly.$new -r $rotateDir/.timestamp
          fi
        count=$(expr $count - 1)
        done
        # Snapshot von Level-0 per hardlink-Kopie nach Level-1 kopieren
        [ -d $rotateDir/daily.0 ] && cp -al $rotateDir/daily.0 $rotateDir/monthly.0
  else
        $logcommand "$monthly ist ein ungueltiger Wert fuer den Parameter -m"
  fi
fi


if [ "$check_yearly" == "1" ]; then
  if expr "$yearly" : '[0-9]\+' >/dev/null ; then
        # Das hoechste Backup abloeschen
        [ -d ${rotateDir}/yearly.${yearly} ] && rm -rf ${rotateDir}/yearly.${yearly}
        # Alle anderen Snapshots eine Nummer nach oben verschieben
        count=$(expr $yearly - 1)
        while [ $count -gt 0 ]
        do
          if [ -d $rotateDir/yearly.$count ] ; then
                new=$[ $count + 1 ]
                # Datum sichern
                touch $rotateDir/.timestamp -r $rotateDir/yearly.$count
                mv -f $rotateDir/yearly.$count $rotateDir/yearly.$new
                # Datum zurueckspielen
                touch $rotateDir/yearly.$new -r $rotateDir/.timestamp
          fi
        count=$(expr $count - 1)
        done
        # Snapshot von Level-0 per hardlink-Kopie nach Level-1 kopieren
        [ -d $rotateDir/daily.0 ] && cp -al $rotateDir/daily.0 $rotateDir/yearly.0
  else
        $logcommand "$yearly ist ein ungueltiger Wert fuer den Parameter -y"
  fi
fi

exit 0
