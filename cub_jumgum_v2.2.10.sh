#!/bin/bash
#
# Jumgum Script v3.0
# Copyright (c) 2020-2025 CUBRID Corporation
#
# Version history:
# 1.0 : 2019.04.30 - Initial creation
# 2.0 : 2020.03.26 - Modifications and bug fixes
# 2.1 : 2020.06.02 - Feature modifications
# 2.2 : 2025.02.10 - Modifications and bug fixes
# 3.0 : 2025.03.26 - Added features and fixed bugs


exec 3> debug.log
BASH_XTRACEFD=3
set -x

# version check-------------------------------------------------------------------------
RD_INPUT=$1
function fn_shell_version(){
   if [ "$RD_INPUT" -z ] 2>/dev/null; then
      continue
   elif [ $RD_INPUT = "-v" ] 2>/dev/null; then
      echo
      echo "CUBRID Jumgum Script v3.0 (64bit release build for linux_gnu) (Feb 10 2025)"
      echo
      exit
   elif [ $RD_INPUT = "start" ] 2>/dev/null; then
      START_SIGN="y"
   elif [ $RD_INPUT != "-v" -o $RD_INPUT = "--help" ] 2>/dev/null ||  [ $RD_INPUT -z ] 2>/dev/null; then
      echo "CUBRID Auto Jumgum Script"
      echo "usage: sh cub_jumgum.sh [option]"
      echo "        ./cub_jumgum.sh [option]"
      echo
      echo "valid options:"
      echo "   start : Script Start"
      echo "      -v : Version"
      echo
      echo "This is a Script for CUBRID DBMS."
      exit
   fi
}

fn_shell_version

# Variable------------------------------------------------------------------------------
IMSI_CNT=1

TODAY=`date +'%Y%m%d'`
TODAY_TIME=`date +'%H'`

RESULT_TOTAL="Abnormal"
RESULT_SYSTEM="Normal"
RESULT_SERVICE="Normal"
RESULT_HA="Normal"
RESULT_SPACE="Normal"
RESULT_BACKUP="Normal"
RESULT_BROKER="Normal"
RESULT_SERVER_ERROR="Normal"
RESULT_RESTART="Normal"
RESULT_HA_FAILCOUNT_STATUS="Normal"
RESULT_ARCHIVELOG="Normal"

RESULT_DISK_STATUS="Normal"
RESULT_CPU_STATUS="Normal"
RESULT_MEMORY_STATUS="Normal"
RESULT_SWAP_STATUS="Normal"

RESULT_SERVICE_STATUS="Normal"
RESULT_DB_STATUS="Normal"
RESULT_BROKER_STATUS="Normal"
RESULT_MANAGER_STATUS="Normal"

RESULT_HA_DB_STATUS="Normal"
RESULT_HA_APPLY_STATUS="Normal"
RESULT_HA_COPY_STATUS="Normal"
RESULT_HA_COPYLOG_STATUS="Normal"

RESULT_HA_FAILCOUNT_STATUS="Normal"
RESULT_HA_DELAY_STATUS="Normal"
RESULT_HA_FAILOVER_STATUS="Normal"
RESULT_HA_HOSTS_STATUS="Normal"
RESULT_HA_CONST_STATUS="Normal"

RESULT_DATASPACE_STATUS="Normal"
RESULT_INDEXSPACE_STATUS="Normal"
RESULT_TEMPSPACE_STATUS="Normal"
RESULT_GENERICSPACE_STATUS="Normal"
RESULT_FULLBACKUP_STATUS="Normal"
RESULT_INCREBACKUP_STATUS="Normal"

RESULT_BROKER_DELAY_STATUS="Normal"
RESULT_BROKER_LONGQUERY_STATUS="Normal"

RESULT_SERVERERROR_STATUS="Normal"
RESULT_ARCHIVE_STATUS="Normal"

CUB_VERSION=`cubrid_rel |awk '{print $2}' | grep -v '^$' | awk -F '.' '{print $1}'`

JUMGUM_RESULT=`echo ~`
JUMGUM_LOG="$JUMGUM_RESULT/cubrid_jumgum"

# BACKUP Setting
# Fullbackup = 0, Increbackup = 1
# backup schedule ex)1day=1, 1month=31
BACKUP_MODE="0" 
FULL_BACKUP_SCHEDULE="1"
INCRE_BACKUP_SCHEDULE="1"

# SERVER ERROR CHECK DAY
# last check ex) 2025-02-26
SERVER_ERROR_CONFIRM_DAY=""


mkdir -p $JUMGUM_LOG
mkdir -p $JUMGUM_RESULT

# Sub function--------------------------------------------------------------------------

function fn_system_status(){
echo "     1. DISK	                                                   "
                df -h 2>/dev/null | awk '{print "       ", $n}'
echo
df_output=$(df -h --output=pcent,target 2>/dev/null | tail -n +2 | sed 's/%//')
while read -r line
do
	USAGE=$(echo "$line" | awk '{print $1}')
	PARTITION=$(echo "$line" | awk '{print $2}')
	if [[ ! "$PARTITION" =~ ^/(dev|proc|sys|tmpfs|var|run|boot) ]]
	then
		if [ -n "$USAGE" ] && [ -n "$PARTITION" ]
		then
			if [ "$USAGE" -ge 90 ]
			then
				if [ "$RESULT_DISK_STATUS" == "Normal" ]
				then
					RESULT_DISK_STATUS="Warning"
				fi
				if [ "$RESULT_SYSTEM" == "Normal" ]
				then
					RESULT_SYSTEM="Warning"
				fi
				if [ "$USAGE" -ge 95 ]
				then
					RESULT_DISK_STATUS="Critical"
					RESULT_SYSTEM="Critical"
				fi
				if [ -z "$RESULT_DISK_MSG" ]
				then
					RESULT_DISK_MSG="${PARTITION} ${USAGE}%"
				else
					RESULT_DISK_MSG="${RESULT_DISK_MSG}, $PARTITION ${USAGE}%"
				fi
			fi
		fi
	fi
done <<< "$df_output"
echo "--------------------------------------------------------------------"
echo "     2. CPU	                                                  "
CPU_IDLE=$(vmstat 1 2 | awk 'NR==4 {print $15}')
CPU_USED=$((100 - CPU_IDLE))
		echo "CPU Usage: ${CPU_USED}%" | awk '{print "       ", $n}'
		echo 
		echo "CPU Top 5 Process List" | awk '{print "       ", $n}'
		echo "----------------------" | awk '{print "       ", $n}'
                ps -eo user,pid,ppid,rss,size,vsize,pmem,pcpu,time,cmd --sort -pcpu | head -n 6 | awk '{print "       ", $n}'
echo
if [ "$CPU_USED" -ge 80 ]
then
	RESULT_CPU_STATUS="Warning"
        if [ "$RESULT_SYSTEM" == "Normal" ]
        then
       		 RESULT_SYSTEM="Warning"
        fi
	if [ "$CPU_USED" -ge 90 ]
	then
		RESULT_CPU_STATUS="Critical"
		RESULT_SYSTEM="Critical"
	fi
RESULT_CPU_MSG="${CPU_USED}%"
fi
echo "--------------------------------------------------------------------"
echo "     3. MEMORY                                               "
                free -m | awk '{print "      ", $n}'
echo
TOTAL_MEM=$(free -m | awk 'NR==2 {print $2}')    # 총 메모리 (MB)

if free | grep -q "available"
then
	# CentOS 7 이상
	AVAILABLE_MEM=$(free -m | awk 'NR==2 {print $(NF-2)}')
else
	# CentOS 6 (buffers/cache 활용)
	AVAILABLE_MEM=$(free -m | awk 'NR==3{print $NF}')
fi

MEMORY_USED=$(( (TOTAL_MEM - AVAILABLE_MEM) * 100 / TOTAL_MEM ))
if [ "$MEMORY_USED" -ge 80 ]
then
	if [ "$RESULT_SYSTEM" == "Normal" ]
	then
        	RESULT_SYSTEM="Warning"
	fi
	RESULT_MEMORY_STATUS="Warning"
	if [ "$MEMORY_USED" -ge 90 ]
	then
        	RESULT_SYSTEM="Critical"
        	RESULT_MEMORY_STATUS="Critical"
	fi
	RESULT_MEMORY_MSG="${MEMORY_USED}%"
fi

TOTAL_SWAP_MEM=`free -m | grep Swap |awk '{print $2}'`
FREE_SWAP_MEM=`free -m | grep Swap |awk '{print $4}'`
SWAP_USED=$(( (TOTAL_SWAP_MEM - FREE_SWAP_MEM) * 100 / TOTAL_SWAP_MEM ))
if [ "$SWAP_USED" -ge 50 ]
then
        if [ "$RESULT_SYSTEM" == "Normal" ]
	then
        	RESULT_SYSTEM="Warning"
        fi
        RESULT_SWAP_STATUS="Warning"
        if [ "$SWAP_USED" -ge 90 ]
	then
        	RESULT_SYSTEM="Critical"
        	RESULT_SWAP_STATUS="Critical"
        fi
	RESULT_SWAP_MSG="${SWAP_USED}%"
fi
}

function fn_service_info(){
MASTER=`cubrid service status | grep "master is" | sed -n '1p' | awk '{print $5}'| sed -e 's/[.]//g'`
if [ $MASTER = 'not' ]
        then
                MASTER_STATUS="Not Running"
		RESULT_SERVICE="Critical"
		RESULT_SERVICE_STATUS="Critical"
		echo "     CUBRID service is not running"
        else
                MASTER_STATUS="Running"
	echo "     1. Master                                                      "
	echo "           Master status : $MASTER_STATUS                                "
	echo
	echo "--------------------------------------------------------------------"
	echo "     2. Database                                                    "
	DB_list=`cat $CUBRID/databases/databases.txt | awk '{print $1}' | sed '/#/d'`
	ha_list=`cat $CUBRID/conf/cubrid_ha.conf | grep -v '#' | grep -w ha_db_list | cut -d '=' -f2 | sed -e 's/,/ /g'`
	DB_mode="Single"
	for DB_NAME in `cat $CUBRID/databases/databases.txt | awk '{print $1}' | sed '/#/d'`
	do
		echo "        2-$IMSI_CNT. $DB_NAME                                       "
	        DB_stat=`cubrid server status 2>/dev/null |grep -v @ | grep -v +| grep -w "$DB_NAME" | awk '{print $1}'`
	        if [ -z $DB_stat ]
	        then
	                DB_STATUS="Not Running"
			DB_USE_CHECK=`awk -v dbname="$DB_NAME" '$1 == dbname {print $4 "/" $1"_lgat"}' "$CUBRID/databases/databases.txt"`
			if [ -n "$DB_USE_CHECK" ]
			then
				DB_LAST_ACCESS_CHECK=`find "$DB_USER_CHECK" -mtime -60`
				if [ -n "$DB_LAST_ACCESS_CHECK" ]
				then
					RESULT_SERVICE="Critical"
					RESULT_DB_STATUS="Critical"
					if [ -z "$RESULT_DB_MSG" ]
					then
						RESULT_DB_MSG="$DB_NAME"
					else
						RESULT_DB_MSG="$RESULT_DB_MSG, $DB_NAME"
					fi
				fi
			fi
	        else
	                DB_STATUS="Running"
		        for HA_NAME in `cat $CUBRID/conf/cubrid_ha.conf | grep -v '#' | grep -w ha_db_list | cut -d '=' -f2 | sed -e 's/,/ /g'`
	        	do
	                	if [ "$HA_NAME" == "$DB_NAME" ]
	                	then
	                        	DB_mode="HA"
	                        	break
	                	else
	                        	DB_mode="Single"
	                	fi
	        	done
		fi
		echo "           DB mode       : $DB_mode                                 "
		echo "           DB Status     : $DB_STATUS                               "
		echo
		IMSI_CNT=`expr $IMSI_CNT + 1`
	done
	echo "--------------------------------------------------------------------"
	echo "     3. Broker                                                      "
	BRO_LIST=`cat $CUBRID/conf/cubrid_broker.conf | grep -v '#'| grep % | sed -e 's/[[]//g' | sed -e 's/[]]//g' | sed -e 's/%//g'`
	for BRO_NAME in $BRO_LIST
	do
		echo "        3-$IMSI_CNT. $BRO_NAME                                      "
	        BRO_STAT=`cubrid broker status -b  | grep -i "$BRO_NAME" | awk '{print $2}'`
	        if [ -z $BRO_STAT ]
	        then
	                BRO_STATUS="Not Running"
	                RESULT_SERVICE="Critical"
			RESULT_BROKER_STATUS="Critical"
			if [ -z "$RESULT_BROKER_MSG" ]
			then
				RESULT_BROKER_MSG="$BRO_NAME"
			else
				RESULT_BROKER_MSG="$RESULT_BROKER_MSG, $BRO_NAME"
			fi
	        else
	                BRO_STATUS="Running"
	        fi
		echo "           Broker Status : $BRO_STATUS                              "
		echo
		IMSI_CNT=`expr $IMSI_CNT + 1`
	done
	echo "--------------------------------------------------------------------"
	echo "     4. Manager                                                     "
	Manager=`cubrid manager status | grep running | awk '{print $6}'`
	if [ $Manager = 'not' ]
	then
		Mng_status="Not Running"
	        if [ "$RESULT_SERVICE" == "Normal" ]
	        then
	                RESULT_SERVICE="Warning"
	        fi
		RESULT_MANAGER_STATUS="Warning"
		if [ -z "$RESULT_MANAGER_MSG" ]
		then
			RESULT_MANAGER_MSG=""
		fi
	else
	        Mng_status="Running"
	fi
	echo "           Manager Status : $Mng_status                             "
	echo
fi
}


function fn_ha_status(){
IMSI_CNT=1
HOST_NAME_CURR=`hostname`
HA_STATUS_CURR=`cubrid hb status 2>/dev/null | grep current | awk '{print $6}' | sed -e 's/)//g'`
if [ -z "$HA_STATUS_CURR" ]
then
        HA_STATUS_CURR="Not Running"
	echo "--------------------------------------------------------------------"
	echo "     1. Current node HA Status                                      "
	echo "--------------------------------------------------------------------"
	echo "        The server was not configured for HA.                         "
	echo
else
	echo "--------------------------------------------------------------------"
        echo "     1. Current node HA Status                                      "
        echo "--------------------------------------------------------------------"
	echo "        Current node($HOST_NAME_CURR) : $HA_STATUS_CURR             "
	for HOST_NAME_OTH in `cubrid hb status  | grep priority | awk '{print $2}' | sort`
	do
        	if [ $HOST_NAME_OTH != $HOST_NAME_CURR ]
	        then
		        HA_STATUS_OTH=`cubrid hb status | grep priority | grep $HOST_NAME_OTH | awk '{print $6}' | sed -e 's/)//g'`
		        echo "        Other   node($HOST_NAME_OTH) : $HA_STATUS_OTH               "
		fi
	done
        echo "--------------------------------------------------------------------"
	echo
        echo "--------------------------------------------------------------------"
        echo "     2. HA-Server List                                              "
        echo "--------------------------------------------------------------------"
	for DB_NAME in `cat $CUBRID/conf/cubrid_ha.conf | grep -v '#' | grep -w ha_db_list | cut -d '=' -f2 | sed -e 's/,/ /g'`
	do
		DB_STATUS_CURR=`cubrid changemode $DB_NAME@localhost 2>/dev/null| awk '{print $9}' | sed -e 's/[.]//g'`
		HA_STATUS_APPLY=`cubrid hb status | grep -w $DB_NAME | grep -w Applylogdb | awk '{print $1}'`
		HA_STATUS_COPY=`cubrid hb status | grep -w $DB_NAME | grep -w Copylogdb | awk '{print $1}'`
		if [ -z "$DB_STATUS_CURR" ]
		then
		        DB_STATUS_CURR="Not Running"
                	RESULT_HA="Critical"
			RESULT_HA_DB_STATUS="Critical"
			if [ -z "$RESULT_HA_DB_MSG" ]
			then
				RESULT_HA_DB_MSG="$DB_NAME"
			else
				RESULT_HA_DB_MSG="$RESULT_HA_DB_MSG, $DB_NAME"
			fi
		elif [ "$DB_STATUS_CURR" == "to-be-active" ]
		then
			DB_STATUS_CURR="to-be-active"
			RESULT_HA="Critical"  
			RESULT_HA_DB_STATUS="Critical"
			if [ -z "$RESULT_HA_DB_MSG" ]
                        then
                                RESULT_HA_DB_MSG="$DB_NAME(to-be-active)"
                        else
                                RESULT_HA_DB_MSG="$RESULT_HA_DB_MSG, $DB_NAME(to-be-active)"
			fi
		fi
		if [ -z "$HA_STATUS_APPLY" ]
		then
		        HA_STATUS_APPLY_RES="Not Running"
                        RESULT_HA="Critical"
			RESULT_HA_APPLY_STATUS="Critical"
                        if [ -z "$RESULT_HA_APPLY_MSG" ]
                        then
                                RESULT_HA_APPLY_MSG="$DB_NAME"
                        else
                                RESULT_HA_APPLY_MSG="$RESULT_HA_APPLY_MSG, $DB_NAME"
                        fi
		else
		        HA_STATUS_APPLY_RES="Running"
		fi
		if [ -z "$HA_STATUS_COPY" ]
		then
		        HA_STATUS_COPY_RES="Not Running"
                        RESULT_HA="Critical"
                        RESULT_HA_COPY_STATUS="Critical"
                        if [ -z "$RESULT_HA_COPY_MSG" ]
                        then
                                RESULT_HA_COPY_MSG="$DB_NAME"
                        else
                                RESULT_HA_COPY_MSG="$RESULT_HA_COPY_MSG, $DB_NAME"
                        fi

		else
			HA_STATUS_COPY_RES="Running"
		fi
		echo "        2-$IMSI_CNT. $DB_NAME"
		echo
		echo "          DB Status     : $DB_STATUS_CURR"
		echo "          Applylogdb    : $HA_STATUS_APPLY_RES"
		echo "          Copylogdb     : $HA_STATUS_COPY_RES"
		echo
		IMSI_CNT=`expr $IMSI_CNT + 1`
	done
	echo "--------------------------------------------------------------------"
	echo "     3. HA-Apply Info                                               "
	echo "--------------------------------------------------------------------"
	IMSI_CNT=1
	HOST_NAME_CURR=`hostname`
	HOST_NAME_OTH=`cubrid hb status | grep priority | grep -v $HOST_NAME_CURR | awk '{print $2}' | sort`
	for DB_NAME in `cat $CUBRID/conf/cubrid_ha.conf | grep -v '#' | grep -w ha_db_list | cut -d '=' -f2 | sed -e 's/,/ /g'`
	do
	        HA_COPY_DEST=`cubrid hb status | grep Applylogdb | grep $DB_NAME |sed "s/${DB_NAME}@localhost://g" | awk '{print $2}'`
	        for HOST_NAME_RES in $HOST_NAME_OTH
	        do
	                HA_STATUS=`cubrid hb status | grep priority | grep -w "$HOST_NAME_RES" | awk '{print $6}' | sed 's/.$//'`
	                if [ $HA_STATUS != 'replica)' ]
	                then
	                        if [ $HA_STATUS != 'unknown)' ]
	                        then
			                echo "        3-$IMSI_CNT. $DB_NAME"
	              			cubrid applyinfo -a -r "$HOST_NAME_RES" -L $HA_COPY_DEST ${DB_NAME} | awk '{print "         ", $n}'
					echo
					FAIL_COUNT=`cubrid applyinfo -a -r "$HOST_NAME_RES" -L $HA_COPY_DEST ${DB_NAME} | grep "Fail" | awk '{print $4}'`
					if [ "0$FAIL_COUNT" -ge 1 ]
					then
						if [ "$RESULT_HA_FAILCOUNT_STATUS" == "Normal" ]
						then
							RESULT_HA_FAILCOUNT_STATUS="Warning"
						fi
						if [ "$RESULT_HA" == "Normal" ]
						then
				               		RESULT_HA="Warning"
						fi
						if [ "0$FAIL_COUNT" -ge 100 ]
	                            		then
							RESULT_HA_FAILCOUNT_STATUS="Critical"
							RESULT_HA="Critical"
						fi
						if [ -z "$RESULT_HA_FAILCOUNT_MSG" ]
						then
							RESULT_HA_FAILCOUNT_MSG="$DB_NAME($FAIL_COUNT)"
						else
							RESULT_HA_FAILCOUNT_MSG="$RESULT_HA_FAILCOUNT_MSG, $DB_NAME($FAIL_COUNT)"
						fi
					fi
					for DELAY_COUNT in `cubrid applyinfo -a -r "$HOST_NAME_RES" -L $HA_COPY_DEST ${DB_NAME} | grep "Delay" | awk -F ':' '{print $2}' | sed 's/second(s)//g' | grep -v '^$'`
					do
						if [ "$DELAY_COUNT" == "-" ]
						then
							DELAY_COUNT=0
						fi
						if [ "0$DELAY_COUNT" -ge 300000 ]
						then
							if [ "$RESULT_HA" == "Normal" ]
							then
							RESULT_HA="Warning"
							fi
							if [ -z "$RESULT_HA_DELAY_STATUS" ]
							then
								RESULT_HA_DELAY_STATUS="Warning"
							fi
							if [ "0$DELAY_COUNT" -ge 1000000 ]
	                                        	then
								RESULT_HA_DELAY_STATUS="Critical"
	                                                	RESULT_HA="Critical"
							fi
							if [ -z "$RESULT_HA_DELAY_STATUS" ]
							then
								RESULT_HA_DELAY_MSG="$DB_NAME($DEALY_CONT)"
							else
								RESULT_HA_DELAY_MSG="$RESULT_HA_DELAY_MSG, $DB_NAME($DEALY_CONT)"
							fi
						fi
					done
				fi
			fi
		done
	IMSI_CNT=`expr $IMSI_CNT + 1`
	done
        echo
        echo "--------------------------------------------------------------------"
        echo "     4. Applylogdb Error List(Fail Count)                           "
        echo "--------------------------------------------------------------------"
	IMSI_CNT=1
	if [ -z "$HA_STATUS_CURR" ]
	then
	        echo "        The server was not configured for HA.                         "
	else
	        for DB_NAME in `cat $CUBRID/conf/cubrid_ha.conf | grep -v '#' | grep -w ha_db_list | cut -d '=' -f2 | sed -e 's/,/ /g'`
	        do
	                echo "     4-$IMSI_CNT. $DB_NAME"
	                echo
			APPLYLOGDB_CONFIRM=`ls -alrt $CUBRID/log | grep -w $DB_NAME | grep applylogdb`
                        if [ -n "$APPLYLOGDB_CONFIRM" ]
                        then
				ls -alrt $CUBRID/log | grep -w $DB_NAME | grep applylogdb | \
				awk '{print $NF}' | xargs -I{} grep 'class' "$CUBRID/log/{}" |  \
				awk -F '"' '{if (NF > 2) print $2}' | sed 's/^\[//; s/\]$//' | sort | uniq -c | awk '{printf "		* Count: %-6s |    * class name: %s\n", $1, $2}'
                        fi
	                IMSI_CNT=`expr $IMSI_CNT + 1`
	        done
	fi
	echo
	echo "--------------------------------------------------------------------"
	echo "     5. Fail-Over                                                   "
	echo "--------------------------------------------------------------------"
	if [ -s $JUMGUM_LOG/node.txt ]
	then
		PREV_NODE_MODE=`cat $JUMGUM_LOG/node.txt`
	else
		PREV_NODE_MODE=''
	fi
	CURR_NODE_MODE=`cubrid hb status | grep current | awk '{print $6}'`
	if [ -n "$PREV_NODE_MODE" ]
	then
		if [ "$PREV_NODE_MODE" != "$CURR_NODE_MODE" ]
		then
			echo "Fail-Over has occurred. (Current Node is $CURR_NODE_MODE" | awk '{print "         ", $n}'
			echo "$CURR_NODE_MODE" > $JUMGUM_LOG/node.txt
			if [ "$RESULT_HA" != "Critical" ]
			then 
				RESULT_HA="Warning"
				RESULT_HA_FAILOVER_STATUS="Warning"
				RESULT_HA_FAILOVER_STATUS="Current Node is $CURR_NODE_MODE"
			fi
		fi
	else
		echo "$CURR_NODE_MODE" > $JUMGUM_LOG/node.txt
		RESULT_HA_FAILOVER_STATUS="Check"
		RESULT_HA_FAILOVER_MSG="Current Node is ${CURR_NODE_MODE//)/}. Please verify manually."
	fi
	echo
	echo "--------------------------------------------------------------------"
	echo "     6. databases.txt                                               "
	echo "--------------------------------------------------------------------"
	cat $CUBRID/databases/databases.txt | awk '{print "    ", $n}'
	for DB_NAME in `cat $CUBRID/conf/cubrid_ha.conf | grep -v '#' | grep -w ha_db_list | cut -d '=' -f2 | sed -e 's/,/ /g'`
	do
		HOST_CONF=`awk -v dbname="$DB_NAME" '$1 == dbname {print $3}' $CUBRID/databases/databases.txt`
		HA_HOST_CONF=`echo $HOST_CONF | awk -F ":" '{print $2}'`
		if [ -z "$HA_HOST_CONF" ]
		then
			if [ "$RESULT_HA" != "Critical" ]
	                then
	                        RESULT_HA="Warning"
	                fi
			RESULT_HA_HOSTS_STATUS="Warning"
			if [ -z "$RESULT_HA_HOSTS_MSG" ]
			then
				RESULT_HA_HOSTS_MSG="$DB_NAME"
			else
				RESULT_HA_HOSTS_MSG="$RESULT_HA_HOSTS_MSG, $DB_NAME"
			fi
		fi
	done
	echo
	echo "--------------------------------------------------------------------"
	echo "     7. ha constraint check                                         "
	echo "--------------------------------------------------------------------"
	IMSI_CNT=1
	for DB_NAME in `cubrid server status | grep -w "HA-Server" | awk '{print $2}'`
	do
	        echo "     7-$IMSI_CNT. $DB_NAME"
	        echo
	        cubrid_check_ha -C $DB_NAME | awk '{print "    ", $n}'
		HA_CONST_CHECK=$(cubrid_check_ha -C "$DB_NAME")
		WITHOUT_PK_COUNT=$(echo "$HA_CONST_CHECK" | grep "Tables without PK" | awk -F'[()/]' '{print $2}')
		LOB_COUNT=$(echo "$HA_CONST_CHECK" | grep "Tables having LOB types" | awk -F'[(]' '{print $2}' | awk -F')' '{print $1}')
		SP_WITHOUT_CLASS_COUNT=$(echo "$HA_CONST_CHECK" | grep "without class file" | sed -E 's/.*without class file: ([0-9]+).*/\1/')
		if [ "$WITHOUT_PK_COUNT" -ge 1 ]
		then
			if [ -n "$RESULT_HA_CONST_MSG" ]
			then
				RESULT_HA_CONST_MSG+=", "
			fi
			RESULT_HA_CONST_MSG+="$DB_NAME(PK"
			RESULT_HA_CONST_STATUS="warning"
		        if [ "$RESULT_HA" != "Critical" ]
	                then
	                        RESULT_HA="Warning"
	                fi
		fi
		if [ "$LOB_COUNT" -ge 1 ]
		then
			if [ -n "$RESULT_HA_CONST_MSG" ]
			then
		        	RESULT_HA_CONST_MSG+=", "
		    	fi
		    	RESULT_HA_CONST_MSG+="LOB"
		    	RESULT_HA_CONST_STATUS="warning"
	                if [ "$RESULT_HA" != "Critical" ]
	                then
	                        RESULT_HA="Warning"
	                fi
		fi
		if [ "$SP_WITHOUT_CLASS_COUNT" -ge 1 ]
		then
			if [ -n "$RESULT_HA_CONST_MSG" ]
			then
		        	RESULT_HA_CONST_MSG+=", "
		    	fi
			RESULT_HA_CONST_MSG+="SP)"
			RESULT_HA_CONST_STATUS="warning"
	                if [ "$RESULT_HA" != "Critical" ]
	                then
	                        RESULT_HA="Warning"
	                fi
		fi
		if { [ "$WITHOUT_PK_COUNT" -ge 1 ] || [ "$LOB_COUNT" -ge 1 ]; } && [ "$SP_WITHOUT_CLASS_COUNT" -eq 0 ]
	        then
	                RESULT_HA_CONST_MSG+=")"
	        fi
	
	        echo
	        IMSI_CNT=`expr $IMSI_CNT + 1`
	done
        echo
        echo "--------------------------------------------------------------------"
        echo "     8. Copy Log Count	                                          "
        echo "--------------------------------------------------------------------"
        IMSI_CNT=1
        for DB_NAME in `cubrid server status | grep -w "HA-Server" | awk '{print $2}'`
        do
                echo "     8-$IMSI_CNT. $DB_NAME"
		COPY_LOG_DEST=`cubrid hb status | grep Applylogdb | grep $DB_NAME |sed "s/${DB_NAME}@localhost://g" | awk '{print $2}'`
		COPY_LOG_CURRENT=`ls -l $HA_COPY_DEST/"$DB_NAME"_lgar[0-9]* 2>/dev/null | wc -l`
		echo "          Current Copy Log Count : $COPY_LOG_CURRENT               "
		echo
		if [ "$COPY_LOG_CURRENT" -ge 10 ]
		then 
			if [ "$RESULT_HA" == "Normal" ]
	                then
		                RESULT_HA="Warning"
	                fi
			if [ -z "$RESULT_HA_COPYLOG_STATUS" ]
			then
				RESULT_HA_COPYLOG_STATUS="Warning"
			fi
			if [ "$COPY_LOG_CURRENT" -ge 30 ]
			then
				RESULT_HA="Critical"
				RESULT_HA_COPYLOG_STATUS="Critical"
			fi
			if [ -z "$RESULT_COLYLOG_MSG" ]
			then
				RESULT_COLYLOG_MSG="$DB_NAME($COPY_LOG_CURRENT)"
			else
				RESULT_COLYLOG_MSG="$RESULT_COLYLOG_MSG, $DB_NAME($COPY_LOG_CURRENT)"
			fi
		fi
	done
fi
}
function fn_database_space_9ver(){
IMSI_CNT=1
for DB_NAME in `cubrid server status | grep -v @ |grep -v not | awk '{print $2}'`
do
        echo "--------------------------------------------------------------------"
        echo "     $IMSI_CNT. $DB_NAME"
        echo "--------------------------------------------------------------------"
        echo
        cubrid spacedb -s $DB_NAME@localhost |awk '{print "    ", $n}'
        data_space=(`cubrid spacedb -s --size-unit=page "$DB_NAME"@localhost | grep DATA`)
        index_space=(`cubrid spacedb -s --size-unit=page "$DB_NAME"@localhost | grep INDEX`)
        temp_space=(`cubrid spacedb -s --size-unit=page "$DB_NAME"@localhost | grep TEMP | grep -v "TEMP TEMP"`)
        generic_space=(`cubrid spacedb -s --size-unit=page "$DB_NAME"@localhost | grep GENERIC`)

        data_capacity=`echo "${data_space[2]}*100/${data_space[1]}" | bc`
        index_capacity=`echo "${index_space[2]}*100/${index_space[1]}" | bc`
        temp_capacity=`echo "${temp_space[2]}*100/${temp_space[1]}" | bc`
        generic_capacity=`echo "${generic_space[2]}*100/${generic_space[1]}" | bc`

	if [ "0${data_space[4]}" -eq 0 ] 
	then
		RESULT_SPACE='Ciritical'
		RESULT_DATASPACE_STATUS='Critical'
		data_capacity='-'
		if [ -z "$RESULT_DATASPACE_MSG" ]
                        then
                                RESULT_DATASPACE_MSG="$DB_NAME($data_capacity)"
                        else
                                RESULT_DATASPACE_MSG="$RESULT_DATASPACE_MSG, $DB_NAME($data_capacity)"
                fi

	fi
	
	if [ "0${index_space[4]}" -eq 0 ] 
        then
                RESULT_SPACE='Ciritical'
                RESULT_INDEXSPACE_STATUS='Critical'
                index_capacity='-'
                if [ -z "$RESULT_INDEXSPACE_MSG" ]
                then
        		RESULT_INDEXSPACE_MSG="$DB_NAME($index_capacity)"
		else        
			RESULT_INDEXSPACE_MSG="$RESULT_INDEXSPACE_MSG, $DB_NAME($index_capacity)"	
		fi

        fi

	if [ "0${temp_space[4]}" -eq 0 ] 
	then
		RESULT_SPACE='Ciritical'
		RESULT_TEMPSPACE_STATUS='Critical'
		temp_capacity='-'
		if [ -z "$RESULT_TEMPSPACE_MSG" ]
		then
			RESULT_TEMPSPACE_MSG="$DB_NAME($temp_capacity)"
		else
			RESULT_TEMPSPACE_MSG="$RESULT_TEMPSPACE_MSG, $DB_NAME($temp_capacity)"
		fi
	fi


        if [ "0$data_capacity" -ge 90 ] && [ "0${data_space[3]}" -lt 1310720 ]
        then
                if [ "$RESULT_SPACE" == "Normal" ]
                then
                        RESULT_SPACE='Warning'
                fi
                if [ "0$data_capacity" -ge 95 ] && [ "0${data_space[3]}" -lt 1310720 ]
                then
                        RESULT_SPACE='Critical'
                fi

                RESULT_DATASPACE_STATUS='Critical'

                if [ -z "$RESULT_DATASPACE_MSG" ]
                        then
                                RESULT_DATASPACE_MSG="$DB_NAME($data_capacity%)"
                        else
                                RESULT_DATASPACE_MSG="$RESULT_DATASPACE_MSG, $DB_NAME($data_capacity%)"
                fi

        fi
	if [ "0$index_capacity" -ge 90 ] && [ "0${index_space[3]}" -lt 655360 ]
        then
                if [ "$RESULT_SPACE" == "Normal" ]
                then
                        RESULT_SPACE='Warning'
                fi
                if [ "0$index_capacity" -ge 95 ] && [ "0${index_space[3]}" -lt 655360 ]
                then
                        RESULT_SPACE='Critical'
                fi

                RESULT_INDEXSPACE_STATUS='Critical'

                if [ -z "$RESULT_INDEXSPACE_MSG" ]
                        then
                                RESULT_INDEXSPACE_MSG="$DB_NAME($index_capacity%)"
                        else
                                RESULT_INDEXSPACE_MSG="$RESULT_INDEXSPACE_MSG, $DB_NAME($index_capacity%)"
                fi

        fi
        if [ "0$temp_capacity" -ge 90 ]
        then
                if [ "$RESULT_SPACE" == "Normal" ]
                then
                        RESULT_SPACE='Warning'
                fi
                if [ "0$temp_capacity" -ge 95 ]
                then
                        RESULT_SPACE='Critical'
                fi

                RESULT_TEMPSPACE_STATUS='Critical'
                if [ -z "$RESULT_TEMPSPACE_MSG" ]
                        then
                                RESULT_TEMPSPACE_MSG="$DB_NAME($temp_capacity%)"
                        else
                                RESULT_TEMPSPACE_MSG="$RESULT_TEMPSPACE_MSG, $DB_NAME($temp_capacity%)"
                fi
        fi

        if [ "0$generic_capacity" -ge 90 ] && [ "0${generic_space[3]}" -lt 1310720 ]
        then
                if [ "$RESULT_SPACE" == "Normal" ]
                then
                        RESULT_SPACE='Warning'
                fi
                if [ "0$generic_capacity" -ge 95 ] && [ "0${generic_space[3]}" -lt 1310720 ]
                then
                        RESULT_SPACE='Critical'
                fi

                RESULT_GENERICSPACE_STATUS='Critical'

                if [ -z "$RESULT_GENERICSPACE_MSG" ]
                        then
                                RESULT_GENERICSPACE_MSG="$DB_NAME($generic_capacity%)"
                        else
                                RESULT_GENERICSPACE_MSG="$RESULT_GENERICSPACE_MSG, $DB_NAME($generic_capacity%)"
                fi
        fi


        IMSI_CNT=`expr $IMSI_CNT + 1`
done
}
				
function fn_database_space_10ver(){
IMSI_CNT=1
for DB_NAME in `cubrid server status | grep -v @ | awk '{print $2}'`
do
        echo "--------------------------------------------------------------------"
        echo "     $IMSI_CNT. $DB_NAME"
        echo "--------------------------------------------------------------------"
        echo
        cubrid spacedb -s $DB_NAME@localhost |awk '{print "    ", $n}'
        data_space=(`cubrid spacedb -s --size-unit=page "$DB_NAME"@localhost | grep "PERMANENT DATA"`)
        temp_space=(`cubrid spacedb -s --size-unit=page "$DB_NAME"@localhost | grep "PERMANENT           TEMPORARY"`)
	data_capacity=`echo "${data_space[4]}*100/${data_space[6]}" | bc`
	temp_capacity=`echo "${temp_space[4]}*100/${temp_space[6]}" | bc`
	
	
	if [ "0${temp_space[3]}" -eq 0 ]  
	then 
		RESULT_SPACE='Ciritical'
		RESULT_TEMPSPACE_STATUS='Critical'
		temp_capacity='-'
                if [ -z "$RESULT_TEMPSPACE_MSG" ]
                        then
                                RESULT_TEMPSPACE_MSG="$DB_NAME($temp_capacity)"
                        else
                                RESULT_TEMPSPACE_MSG="$RESULT_TEMPSPACE_MSG, $DB_NAME($temp_capacity)"
                fi
	
	fi	
	
        if [ "0$data_capacity" -ge 90 ] && [ "0${data_space[5]}" -lt 1310720 ]
        then
                if [ "$RESULT_SPACE" == "Normal" ]
                then
                        RESULT_SPACE='Warning'
                fi
                if [ "0$data_capacity" -ge 95 ] && [ "0${data_space[5]}" -lt 1310720 ]
                then
                        RESULT_SPACE='Critical'
                fi
                RESULT_DATASPACE_STATUS='Critical'
                if [ -z "$RESULT_DATASPACE_MSG" ]
                        then
                                RESULT_DATASPACE_MSG="$DB_NAME($data_capacity%)"
                        else
                                RESULT_DATASPACE_MSG="$RESULT_DATASPACE_MSG, $DB_NAME($data_capacity%)"
                fi
        fi
        if [ "0$temp_capacity" -ge 90 ]
        then
                if [ "$RESULT_SPACE" == "Normal" ]
                then
                        RESULT_SPACE='Warning'
                fi
                if [ "0$temp_capacity" -ge 95 ]
                then
                        RESULT_SPACE='Ciritical'

                fi
                RESULT_TEMPSPACE_STATUS='Critical'
                if [ -z "$RESULT_TEMPSPACE_MSG" ]
                        then
                                RESULT_TEMPSPACE_MSG="$DB_NAME($temp_capacity%)"
                        else
                                RESULT_TEMPSPACE_MSG="$RESULT_TEMPSPACE_MSG, $DB_NAME($temp_capacity%)"
                fi
        fi
        IMSI_CNT=`expr $IMSI_CNT + 1`
done
}

function fn_backup_status(){
IMSI_CNT=1
for DB_NAME in `cubrid server status | grep -v @ | awk '{print $2}'`
do
        echo "--------------------------------------------------------------------"
        echo "     $IMSI_CNT. $DB_NAME"
        echo "--------------------------------------------------------------------"
        echo "        $IMSI_CNT-1. FULL Backup                                    "
        echo
        BACK_DEST_01=`awk -v dbname="$DB_NAME"  '$1 == dbname {print $4}' $CUBRID/databases/databases.txt`
        if [ -e "$BACK_DEST_01"/"$DB_NAME"_bkvinf ]
	then
                FULLBACK_DEST_RES=`cat "$BACK_DEST_01"/"$DB_NAME"_bkvinf | grep -w "0 0" | awk '{print $3}' | rev | cut -d / -f 2- | rev`
                if [ -n "$FULLBACK_DEST_RES" ] 
		then
                        echo "        Backup Location  : $FULLBACK_DEST_RES                       "
                        FULLBACK_FILE_CONFIRM=`ls "$FULLBACK_DEST_RES" |grep "$DB_NAME"_bk0v000`
                        if [ -n "$FULLBACK_FILE_CONFIRM" ] 
			then
                                FULLBACK_BACK_TIME=`stat "$FULLBACK_DEST_RES"/"$DB_NAME"_bk0v000 | grep Modify | awk '{print $2, $3}' | awk -F '.' '{print $1}'`
                                echo "        Last Backup Time : $FULLBACK_BACK_TIME                      "
                                echo "        Backup File list : `ls -al "$FULLBACK_DEST_RES"/"$DB_NAME"_bk0v000`"
				FULLBACK_TIME_CHECK=`find $FULLBACK_DEST_RES/ -name "${DB_NAME}_bk0v000" -mtime -"$FULL_BACKUP_SCHEDULE"`
	
				if [[ -z "$FULLBACK_TIME_CHECK" ]]
				then
					RESULT_BACKUP="Critical"
                                        RESULT_FULLBACKUP_STATUS="Critical"
					if [ -z "$RESULT_FULLBACKUP_MSG" ]
   			                then
                        			RESULT_FULLBACKUP_MSG="$DB_NAME"
                			else
                  		      		RESULT_FULLBACKUP_MSG="$RESULT_FULLBACKUP_MSG ,$DB_NAME"
                			fi
				fi
                        else
				if [ -e "$CUBRID/log/cubrid_utility.log" ] 
				then
					LOG_CHK=''
                                        BK_LOG=`grep -i 'backupdb' $CUBRID/log/cubrid_utility.log  | grep -i "$DB_NAME" |  awk -v start="$(date -d "$FULL_BACKUP_SCHEDULE days ago" '+%y-%m-%d %H:%M:%S')" -v end="$(date '+%y-%m-%d %H:%M:%S')" '           {
                                                        log_time = $1 " " $2;
                                                                if (log_time >= start && log_time <= end) {
                                                                        print $0;
                                                                }
                                                }'`
					IFS=$'\n' 
					for line in $BK_LOG
					do					
						if [[ "$line" =~ "-l" ]]
						then
							PROCESS_ID=`echo "$line" | sed -n 's/.*(\([0-9]\+\)).*/\1/p'`
							FULLBACK_BACK_TIME=`echo "$line" | awk {'print $1 " " $2'}`
							BK_LEVEL=`echo "$line" | sed -n 's/.*-l[[:space:]]\+\([^ ]\+\).*/\1/p'`

						else
							PROCESS_ID=`echo "$line" | sed -n 's/.*(\([0-9]\+\)).*/\1/p'`
                                                	FULLBACK_BACK_TIME=`echo "$line" | awk {'print $1 " " $2'}`
                                                	BK_LEVEL=0
	
						fi
						if [ "$BK_LEVEL" -eq "0" ]
                                        	then
							LOG_CHK=`grep -w "$PROCESS_ID" $CUBRID/log/cubrid_utility.log | grep -o "SUCCESS"`
							if [ "$LOG_CHK" == "SUCCESS" ]
							then
								echo "        Last Backup Time : $FULLBACK_BACK_TIME                      "
								break
							fi
						fi
					done
					unset IFS
		
                                        if [ "$LOG_CHK" == "SUCCESS" ] 
					then
                                                echo "        $DB_NAME Full backup file does not exist but Full backup success "
                                        else
                                                echo "        $DB_NAME Full backup file does not exist. "
                                                RESULT_BACKUP="Critical"
                                                RESULT_FULLBACKUP_STATUS="Critical"
                                                if [ -z "$RESULT_FULLBACKUP_MSG" ] 
						then
                                                        RESULT_FULLBACKUP_MSG="$DB_NAME"
                                                else
                                                        RESULT_FULLBACKUP_MSG="$RESULT_FULLBACKUP_MSG ,$DB_NAME"
                                                fi
                                        fi
                                else
                                        echo "        $DB_NAME Full backup file does not exist. "
                                        RESULT_BACKUP="Critical"
                                        RESULT_FULLBACKUP_STATUS="Critical"
                                        if [ -z "$RESULT_FULLBACKUP_MSG" ] 
					then
                                                RESULT_FULLBACKUP_MSG="$DB_NAME"
                                        else
                                                RESULT_FULLBACKUP_MSG="$RESULT_FULLBACKUP_MSG ,$DB_NAME"
                                        fi

                                fi
                        fi
                fi
                                                        
		if [ "$BACKUP_MODE" -eq "1" ]
		then
                	FIR_INCREBACK_DEST_RES=`cat "$BACK_DEST_01"/"$DB_NAME"_bkvinf | grep -w "1 0" | awk '{print $3}' | rev | cut -d / -f 2- | rev`
                        	if [ -n "$FIR_INCREBACK_DEST_RES" ] 
				then
                                	echo "        $IMSI_CNT-2. INCRE Backup                                    "
                                	echo "  "
                                	echo "        Backup Location  : $FIR_INCREBACK_DEST_RES                       "
                                	FIR_INCREBACK_FILE_CONFIRM=`ls "$FIR_INCREBACK_DEST_RES" |grep "$DB_NAME"_bk1v000`
                                	if [ -n "$FIR_INCREBACK_FILE_CONFIRM" ] 
					then
                                        	FIR_INCREBACK_BACK_TIME=`stat "$FIR_INCREBACK_DEST_RES"/"$DB_NAME"_bk1v000 | grep Modify | awk '{print $2, $3}' | awk -F '.' '{print $1}'`
                                        	echo "        Last Backup Time : $FIR_INCREBACK_BACK_TIME                      "
                                        	echo "        Backup File list : `ls -al "$FIR_INCREBACK_DEST_RES"/"$DB_NAME"_bk1v000`"
                                        	FIR_INCREBACK_TIME_CHECK=`find $FIR_INCREBACK_DEST_RES/ -name "${DB_NAME}_bk1v000" -mtime -"$INCRE_BACKUP_SCHEDULE"`

                                		if [[ -z "$FIR_INCREBACK_TIME_CHECK" ]]
                                		then
                                        		RESULT_BACKUP="Critical"
                                        		RESULT_INCREBACKUP_STATUS="Critical"
                                        		if [ -z "$RESULT_INCREBACKUP_MSG" ]
                                        		then
                                        	        	RESULT_INCREBACKUP_MSG="$DB_NAME"
                                        		else
                                                		RESULT_INCREBACKUP_MSG="$RESULT_FULLBACKUP_MSG ,$DB_NAME"
                                        		fi
                                		fi


                                	else
                                        	if [ -e "$CUBRID/log/cubrid_utility.log" ] 
						then
							LOG_CHK=''
                                                	BK_LOG=`grep -i 'backupdb' $CUBRID/log/cubrid_utility.log  | grep -i "$DB_NAME" |  awk -v start="$(date -d "$INCRE_BACKUP_SCHEDULE days ago" '+%y-%m-%d %H:%M:%S')" -v end="$(date '+%y-%m-%d %H:%M:%S')" '           {
                                                        	log_time = $1 " " $2;
                                                                	if (log_time >= start && log_time <= end) {
                                                                        	print $0;
                                                                	}
                                                	}'`
							IFS=$'\n'
							for line in $BK_LOG
							do
                                                        	if [[ "$line" =~ "-l" ]] 
								then
                                                                	PROCESS_ID=`echo "$line" | sed -n 's/.*(\([0-9]\+\)).*/\1/p'`
                                                                	FIR_INCREBACK_BACK_TIME=`echo "$line" | awk {'print $1 " " $2'}`
                                                                	BK_LEVEL=`echo "$line" | sed -n 's/.*-l[[:space:]]\+\([^ ]\+\).*/\1/p'`
                                                        	fi
                                                        	if [ "$BK_LEVEL" -eq "1" ] 
								then
                                                                	LOG_CHK=`grep -w "$PROCESS_ID" $CUBRID/log/cubrid_utility.log | grep -o "SUCCESS"`
                                                                	if [ "$LOG_CHK" == "SUCCESS" ] 
									then
                                                                        	echo "        Last Backup Time : $FIR_INCREBACK_BACK_TIME                      "
                                                                        	break
                                                                	fi
                                                        	fi
							done
							unset IFS
                                                	if [ "$LOG_CHK" == "SUCCESS" ] 
							then
                                                        	echo "        $DB_NAME First Incre backup file does not exist but First Incre backup success "
                                                		else
                                                        	echo "        $DB_NAME First Incre backup file does not exist. "
                                                                RESULT_BACKUP="Critical"
                                                                RESULT_INCREBACKUP_STATUS="Critical"
                                                                if [ -z "$RESULT_INCREBACKUP_MSG" ] 
								then
                                                                        RESULT_INCREBACKUP_MSG="$DB_NAME"
                                                                else
                                                                        RESULT_INCREBACKUP_MSG="$RESULT_INCREBACKUP_MSG , $DB_NAME"
                                                                fi
                                                	fi
                                        	else
                                                	echo "        $DB_NAME First Incre backup file does not exist. "
                                                        RESULT_BACKUP="Critical"
                                                        RESULT_INCREBACKUP_STATUS="Critical"
                                                        if [ -z "$RESULT_INCREBACKUP_MSG" ] 
							then
                                                                RESULT_INCREBACKUP_MSG="$DB_NAME"
                                                        else
                                                                RESULT_INCREBACKUP_MSG="$RESULT_INCREBACKUP_MSG , $DB_NAME"
                                                        fi
                                        	fi
                                	fi
                        	else  
					echo "        $DB_NAME First Incre backup file does not exist. "
					RESULT_BACKUP="Critical"    
					RESULT_INCREBACKUP_STATUS="Critical"
					if [ -z "$RESULT_INCREBACKUP_MSG" ]
					then          	
						RESULT_INCREBACKUP_MSG="$DB_NAME"
					else
						RESULT_INCREBACKUP_MSG="$RESULT_INCREBACKUP_MSG , $DB_NAME"       
					fi
				
				fi
			fi 

        else
                echo "        $DB_NAME backup file does not exist. "
		RESULT_BACKUP="Critical"
                RESULT_FULLBACKUP_STATUS="Critical"
                if [ -z "$RESULT_FULLBACKUP_MSG" ]
                then
                        RESULT_FULLBACKUP_MSG="$DB_NAME"
                else
                        RESULT_FULLBACKUP_MSG="$RESULT_FULLBACKUP_MSG ,$DB_NAME"
                fi
		if [ "$BACKUP_MODE" -eq "1" ]
		then
			RESULT_INCREBACKUP_STATUS="Critical"
			echo "        $DB_NAME First Incre backup file does not exist. "
			if [ -z "$RESULT_INCREBACKUP_MSG" ]
			then
				RESULT_INCREBACKUP_MSG="$DB_NAME"
			else
				RESULT_INCREBACKUP_MSG="$RESULT_INCREBACKUP_MSG , $DB_NAME"
			fi
		fi
		
        fi
        echo
        IMSI_CNT=`expr $IMSI_CNT + 1`

done
}

function fn_broker_status(){
BR_COUNTER=0
for BROKER_STAT in `cubrid broker status -b -f -l 10 | grep '*' | awk '{print $10}'`
do
	((BR_COUNTER++))
	if [ "$BROKER_STAT" -ge 10 ]
	then
		if [ "$RESULT_BROKER" == "Normal" ]
		then
			RESULT_BROKER="Warning"
		fi
		if [ "$RESULT_BROKER_DELAY_STATUS" == "Normal" ]
		then
			RESULT_BROKER_DELAY_STATUS="Warning"
		fi
		if [ "$BROKER_STAT" -ge 30 ]
	        then
        	        RESULT_BROKER="Critical"
			RESULT_BROKER_DELAY_STATUS="Critical"
		fi
		ISSUE_BRO_NAME=`cubrid broker status -b  | grep '*' | sed -n "${BR_COUNTER}p" |awk '{print $2}'`
		if [ -z "$RESULT_BROKER_DELAY_MSG" ]
		then
			RESULT_BROKER_DELAY_MSG="$ISSUE_BRO_NAME($BROKER_STAT)"
		else
			RESULT_BROKER_DELAY_MSG="$RESULT_BROKER_DELAY_MSG, $ISSUE_BRO_NAME($BROKER_STAT)"
		fi
		cubrid broker status -f $ISSUE_BRO_NAME >> $JUMGUM_LOG/"$ISSUE_BRO_NAME"_`date +%y%m%d%H%M`.log
	fi
done

BR_COUNTER=0
for BROKER_STAT in `cubrid broker status -b -f -l 1000 | grep '*' | awk '{print $10}'`
do
	((BR_COUNTER++))
        if [ "$BROKER_STAT" -ne 0 ]
        then
                if [ "$RESULT_BROKER" == "Normal" ]
                then
                        RESULT_BROKER='Warning'
                fi
                if [ "$RESULT_BROKER_LONGQUERY_STATUS" == "Normal" ]
                then
                        RESULT_BROKER_LONGQUERY_STATUS="Warning"
                fi
		ISSUE_BRO_NAME=`cubrid broker status -b  | grep '*' | sed -n "${BR_COUNTER}p" |awk '{print $2}'`
                if [ -z "$RESULT_BROKER_LONGQUERY_MSG" ]
                then
                        RESULT_BROKER_LONGQUERY_MSG="$ISSUE_BRO_NAME($BROKER_STAT)"
                else
                        RESULT_BROKER_LONGQUERY_MSG="$RESULT_BROKER_LONGQUERY_MSG, $ISSUE_BRO_NAME($BROKER_STAT)"
                fi
                cubrid broker status -f $ISSUE_BRO_NAME >> $JUMGUM_LOG/"$ISSUE_BRO_NAME"_`date +%y%m%d%H%M`.log
        fi
done
}

function fn_server_errorlist(){
IMSI_CNT=1
if [ -n "$SERVER_ERROR_CONFIRM_DAY" ]
then
	SERVER_ERROR_CONFIRM_DAY_FMT=$(date -d "$SERVER_ERROR_CONFIRM_DAY" +"%Y%m%d" 2>/dev/null)
else
	SERVER_ERROR_CONFIRM_DAY_FMT=""
fi
for DB_NAME in `cat $CUBRID/databases/databases.txt | awk '{print $1}' | sed '/#/d'`
do
        echo "--------------------------------------------------------------------"
        echo "     $IMSI_CNT. $DB_NAME"
        echo "--------------------------------------------------------------------"
	LATEST_ERR_FILE=$(ls -t $CUBRID/log/server | grep "$DB_NAME" | grep ".err" | head -n1)
        if [ -n "$LATEST_ERR_FILE" ]
        then
                LOG_PATH="$CUBRID/log/server/$LATEST_ERR_FILE"
                ERROR_CONFIRM=$(awk -v confirm_day="$SERVER_ERROR_CONFIRM_DAY_FMT" '
                {
                        if ($0 ~ /[0-9]{2}\/[0-9]{2}\/[0-9]{2}/) {
                        date_str = substr($0, match($0, /[0-9]{2}\/[0-9]{2}\/[0-9]{2}/), 8);
                        split(date_str, parts, "/");
                        log_date = "20" parts[3] "-" parts[1] "-" parts[2];
                        cmd = "date -d \"" log_date "\" +\"%Y%m%d\" 2>/dev/null";
                        cmd | getline log_date_fmt;
                        close(cmd);
                        if (log_date_fmt != "" && (confirm_day == "" || log_date_fmt > confirm_day)) {
                            print $0;
                                }
                        }
                }' "$LOG_PATH" | \
                grep -E "ERROR CODE = -([0-9]+)" | \
                grep -E "ERROR CODE = -(2|13|14|17|19|21|22|23|34|35|38|39|40|41|43|46|48|49|50|51|52|54|55|56|59|60|61|62|63|67|68|69|70|71|77|78|79|81|85|88|96|97|120|177|210|263|313|407|504|518|544|545|546|551|563|572|573|574|584|586|588|603|604|605|625|626|644|668|678|689|698|699|700|702|703|725|734|757|760|761|762|763|764|766|780|976|1105|1119|1120|1131)\b" | \
                sed -nE 's/.*ERROR CODE = (-[0-9]+).*/\1/p' | \
                sort | uniq -c)
        fi
	if [ -n "$ERROR_CONFIRM" ]
        then
		echo "$ERROR_CONFIRM" | awk '{printf "          * Count: %-6s |     * Error code: %s\n", $1, $2}'
        	RESULT_SERVER_ERROR='Critical'
		if [ -z "$RESULT_SERVER_MSG" ]
		then
			RESULT_SERVER_MSG="$DB_NAME"
		else
			RESULT_SERVER_MSG="$RESULT_SERVER_MSG, $DB_NAME"
		fi
        fi
	IMSI_CNT=`expr $IMSI_CNT + 1`
done
}

function fn_restart_status(){
IMSI_CNT=1
ONE_MONTH_AGO=$(date -d "-1 month" +"%Y%m%d")
for DB_NAME in `cat $CUBRID/databases/databases.txt | awk '{print $1}' | sed '/#/d'`
do
        echo "--------------------------------------------------------------------"
        echo "     $IMSI_CNT. $DB_NAME"
        echo "--------------------------------------------------------------------"
	RESTART_COUNT=$(find $CUBRID/log/server/ -name "${DB_NAME}_*.err" -printf "%f\n" 2>/dev/null | awk -v start="$ONE_MONTH_AGO" -v end="$TODAY" '
			{
			    file_name = $0;
			    split(file_name, parts, "_");
			    if (length(parts) >= 3) {
			        date_str = substr(parts[2], 1, 8);
			        if (date_str >= start && date_str <= end) {
			            count++;
			        }
			    }
			}
			END { print count+0 }'
			)
	if [ "$RESTART_COUNT" -ge 2 ]
	then
		if [ "$RESULT_RESTART" == "Normal" ]
		then
	        	RESULT_RESTART="Warning"
		fi
		if [ "$RESTART_COUNT" -ge 3 ]
		then
			RESULT_RESTART="Critical"
		fi
		if [ -z "$RESULT_RESTART_MSG" ]
		then
			RESULT_RESTART_MSG="$DB_NAME($RESTART_COUNT times)"
		else
			RESULT_RESTART_MSG="$RESULT_RESTART_MSG, $DB_NAME($RESTART_COUNT times)"
		fi
		echo "Restarted $RESTART_COUNT times within the past month" |awk '{print "       ", $n}'
	fi
        IMSI_CNT=`expr $IMSI_CNT + 1`
done
}

function fn_dmesg_status(){
DMESG_ERROR=$(dmesg | grep -i "cub_server" | wc -l)
if [ "$DMESG_ERROR" -gt 0 ]
then
	DMESG_STATUS="Critical"
	DMESG_MSG="Check dmesg logs"
fi
echo "--------------------------------------------------------------------"
echo "     'cub_server' found $DMESG_ERROR times in dmesg.		  " 
echo "--------------------------------------------------------------------"
}

function fn_archivelog_count(){
IMSI_CNT=1
for DB_NAME in `cubrid server status | grep -v @ |grep -v not | awk '{print $2}'`
do
        echo "--------------------------------------------------------------------"
        echo "     $IMSI_CNT. $DB_NAME"
        echo "--------------------------------------------------------------------"
	ARCHIVE_LOG_CONFIG=`cubrid paramdump "$DB_NAME"@localhost | grep -w log_max_archives | awk -F '=' '{print $2}'`
	ARCHIVE_LOG_DIR=`awk -v dbname="$DB_NAME" '$1 == dbname {print $4}' "$CUBRID/databases/databases.txt"`
	ARCHIVE_LOG_CURRENT=`ls -al $ARCHIVE_LOG_DIR/"$DB_NAME"_lgar[0-9]* 2>/dev/null | wc -l`
	echo "     Archive Log Config Value  : $ARCHIVE_LOG_CONFIG                "
	echo "     Archive Log Current Value : $ARCHIVE_LOG_CURRENT               "
	echo 
	if [ "$ARCHIVE_LOG_CURRENT" -ge `expr "$ARCHIVE_LOG_CONFIG" + 15` ]
	then
		if [ "$RESULT_ARCHIVELOG" == "Normal" ]
		then
			RESULT_ARCHIVELOG="Warning"
		fi
		if [ "$RESULT_ARCHIVE_STATUS" == "Normal" ]
		then
			RESULT_ARCHIVE_STATUS="Warning"
		fi
		if [ "$ARCHIVE_LOG_CURRENT" -ge `expr "$ARCHIVE_LOG_CONFIG" + 30` ]
	        then
        	        RESULT_ARCHIVELOG="Critical"
			RESULT_ARCHIVE_STATUS="Critical"
		fi
		if [ -z "$RESULT_ARCHIVE_MSG" ]
		then
			RESULT_ARCHIVE_MSG="$DB_NAME($ARCHIVE_LOG_CURRENT)"
		else
			RESULT_ARCHIVE_MSG="$RESULT_ARCHIVE_MSG, $DB_NAME($ARCHIVE_LOG_CURRENT)"
		fi
	fi
	IMSI_CNT=`expr $IMSI_CNT + 1`
done
}

# Main 1---------------------------------------------------------------------------

echo "====================================================================" 	 > $JUMGUM_LOG/cubrid_jumgum_`date +%a`.log
echo "  CUBRID Jumgum Resultset - `hostname`   [`date +"%Y-%m-%d"`]       " 	 >> $JUMGUM_LOG/cubrid_jumgum_`date +%a`.log
echo "====================================================================" 	 >> $JUMGUM_LOG/cubrid_jumgum_`date +%a`.log
echo "  1) System Status                                                  "      >> $JUMGUM_LOG/cubrid_jumgum_`date +%a`.log
echo "--------------------------------------------------------------------"      >> $JUMGUM_LOG/cubrid_jumgum_`date +%a`.log
	fn_system_status 2>/dev/null 						 >> $JUMGUM_LOG/cubrid_jumgum_`date +%a`.log
echo										 >> $JUMGUM_LOG/cubrid_jumgum_`date +%a`.log
echo "===================================================================="	 >> $JUMGUM_LOG/cubrid_jumgum_`date +%a`.log
echo										 >> $JUMGUM_LOG/cubrid_jumgum_`date +%a`.log
echo "  2) Service Status                                                 "	 >> $JUMGUM_LOG/cubrid_jumgum_`date +%a`.log
echo "--------------------------------------------------------------------"	 >> $JUMGUM_LOG/cubrid_jumgum_`date +%a`.log
	fn_service_info 2>/dev/null 						 >> $JUMGUM_LOG/cubrid_jumgum_`date +%a`.log
echo										 >> $JUMGUM_LOG/cubrid_jumgum_`date +%a`.log
echo "===================================================================="	 >> $JUMGUM_LOG/cubrid_jumgum_`date +%a`.log
echo										 >> $JUMGUM_LOG/cubrid_jumgum_`date +%a`.log
echo "  3) HA Status                                                      "	 >> $JUMGUM_LOG/cubrid_jumgum_`date +%a`.log
	fn_ha_status 2>/dev/null 						 >> $JUMGUM_LOG/cubrid_jumgum_`date +%a`.log
echo										 >> $JUMGUM_LOG/cubrid_jumgum_`date +%a`.log
echo "===================================================================="	 >> $JUMGUM_LOG/cubrid_jumgum_`date +%a`.log
echo										 >> $JUMGUM_LOG/cubrid_jumgum_`date +%a`.log
echo "  4) Database Space                                                 "	 >> $JUMGUM_LOG/cubrid_jumgum_`date +%a`.log
if [ "$CUB_VERSION" == 2008 ] 					
then
        fn_database_space_9ver  2>/dev/null                                      >> $JUMGUM_LOG/cubrid_jumgum_`date +%a`.log
elif [ "$CUB_VERSION" -ge 10 ] 					
then
	fn_database_space_10ver	2>/dev/null 					 >> $JUMGUM_LOG/cubrid_jumgum_`date +%a`.log
else
	fn_database_space_9ver	2>/dev/null 					 >> $JUMGUM_LOG/cubrid_jumgum_`date +%a`.log
fi
echo										 >> $JUMGUM_LOG/cubrid_jumgum_`date +%a`.log
echo "===================================================================="	 >> $JUMGUM_LOG/cubrid_jumgum_`date +%a`.log
echo										 >> $JUMGUM_LOG/cubrid_jumgum_`date +%a`.log
echo "  5) Backup Status                                                  "	 >> $JUMGUM_LOG/cubrid_jumgum_`date +%a`.log
	fn_backup_status 2>/dev/null 						 >> $JUMGUM_LOG/cubrid_jumgum_`date +%a`.log
echo										 >> $JUMGUM_LOG/cubrid_jumgum_`date +%a`.log
echo "===================================================================="	 >> $JUMGUM_LOG/cubrid_jumgum_`date +%a`.log
echo										 >> $JUMGUM_LOG/cubrid_jumgum_`date +%a`.log
echo "  6) Broker status 			                          "	 >> $JUMGUM_LOG/cubrid_jumgum_`date +%a`.log
echo "--------------------------------------------------------------------"	 >> $JUMGUM_LOG/cubrid_jumgum_`date +%a`.log
echo										 >> $JUMGUM_LOG/cubrid_jumgum_`date +%a`.log
	cubrid broker status -f -b -l 10 2>/dev/null 				 >> $JUMGUM_LOG/cubrid_jumgum_`date +%a`.log
	fn_broker_status 2>/dev/null 						 >> $JUMGUM_LOG/cubrid_jumgum_`date +%a`.log
echo										 >> $JUMGUM_LOG/cubrid_jumgum_`date +%a`.log
echo "===================================================================="	 >> $JUMGUM_LOG/cubrid_jumgum_`date +%a`.log
echo										 >> $JUMGUM_LOG/cubrid_jumgum_`date +%a`.log
echo "  7) Server Critical Error List                                     "	 >> $JUMGUM_LOG/cubrid_jumgum_`date +%a`.log
	fn_server_errorlist 2>/dev/null 					 >> $JUMGUM_LOG/cubrid_jumgum_`date +%a`.log
echo										 >> $JUMGUM_LOG/cubrid_jumgum_`date +%a`.log
echo "===================================================================="	 >> $JUMGUM_LOG/cubrid_jumgum_`date +%a`.log
echo										 >> $JUMGUM_LOG/cubrid_jumgum_`date +%a`.log
echo "  8) Frequent Restarts		                                  "	 >> $JUMGUM_LOG/cubrid_jumgum_`date +%a`.log
	fn_restart_status	2>/dev/null 					 >> $JUMGUM_LOG/cubrid_jumgum_`date +%a`.log
echo										 >> $JUMGUM_LOG/cubrid_jumgum_`date +%a`.log
echo "===================================================================="      >> $JUMGUM_LOG/cubrid_jumgum_`date +%a`.log
echo                                                                             >> $JUMGUM_LOG/cubrid_jumgum_`date +%a`.log
echo "  9) dmesg Error Check	                                          "      >> $JUMGUM_LOG/cubrid_jumgum_`date +%a`.log
        fn_dmesg_status       2>/dev/null                                        >> $JUMGUM_LOG/cubrid_jumgum_`date +%a`.log
echo                                                                             >> $JUMGUM_LOG/cubrid_jumgum_`date +%a`.log
echo "===================================================================="	 >> $JUMGUM_LOG/cubrid_jumgum_`date +%a`.log
echo										 >> $JUMGUM_LOG/cubrid_jumgum_`date +%a`.log
echo " 10) Archive Log Count                                              "	 >> $JUMGUM_LOG/cubrid_jumgum_`date +%a`.log
	fn_archivelog_count 2>/dev/null 					 >> $JUMGUM_LOG/cubrid_jumgum_`date +%a`.log
echo										 >> $JUMGUM_LOG/cubrid_jumgum_`date +%a`.log


# Main 2---------------------------------------------------------------------------

echo "===================================================================="     > $JUMGUM_RESULT/cubrid_jumgum_summary.txt
echo "  CUBRID Jumgum Resultset - Total Detail    [`date +"%Y-%m-%d"`]    "     >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
echo "===================================================================="     >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
echo "   HOSTNAME             Classification            STATUS            "     >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
echo "--------------------------------------------------------------------"     >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
printf " %-20s %-27s %-15s\n" `hostname` " 1) System Status" $RESULT_SYSTEM     >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
printf " %-20s %-27s %-15s\n" `hostname` " 2) Service Status" $RESULT_SERVICE   >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
printf " %-20s %-27s %-15s\n" `hostname` " 3) HA Status" $RESULT_HA             >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
printf " %-20s %-27s %-15s\n" `hostname` " 4) Space Status" $RESULT_SPACE       >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
printf " %-20s %-27s %-15s\n" `hostname` " 5) Backup Status" $RESULT_BACKUP     >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
printf " %-20s %-27s %-15s\n" `hostname` " 6) Broker Status" $RESULT_BROKER     >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
printf " %-20s %-27s %-15s\n" `hostname` " 7) Server Error" $RESULT_SERVER_ERROR >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
printf " %-20s %-27s %-15s\n" `hostname` " 8) Applylogdb Error" $RESULT_APPLYLOGDB_ERROR >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
printf " %-20s %-27s %-15s\n" `hostname` " 9) Archive Log" $RESULT_ARCHIVELOG   >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt


echo "==============================================================================================="     > $JUMGUM_RESULT/cubrid_jumgum_summary.txt
echo "  CUBRID Jumgum Resultset - Total Detail    [`date +"%Y-%m-%d"`]    		             "     >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
echo "==============================================================================================="     >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
echo "       Category		   SubCategory         STATUS      	Detail			     "     >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
echo "-----------------------------------------------------------------------------------------------"     >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
printf " %-45s" " 1) System Status"                                                                        >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
if [ "$RESULT_SYSTEM" = "Normal" ]
then
        printf " %-15s \n" "$RESULT_SYSTEM"                                                                >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
else
        printf "\n"                                                                                        >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
fi
if [ "$RESULT_DISK_STATUS" != "Normal" ]
then
	printf " %-25s %-19s %-15s %-40s\n" "" "Disk Usage" "$RESULT_DISK_STATUS" "$RESULT_DISK_MSG" 	   >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
fi
if [ "$RESULT_CPU_STATUS" != "Normal" ]
then
        printf " %-25s %-19s %-15s %-40s\n" "" "Cpu Usage" "$RESULT_CPU_STATUS" "$RESULT_CPU_MSG" 	   >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
fi
if [ "$RESULT_MEMORY_STATUS" != "Normal" ]
then
        printf " %-25s %-19s %-15s %-40s\n" "" "Memory Usage" "$RESULT_MEMORY_STATUS" "$RESULT_MEMORY_MSG" >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
fi
if [ "$RESULT_SWAP_STATUS" != "Normal" ]
then
        printf " %-25s %-19s %-15s %-40s\n" "" "Swap Usage" "$RESULT_SWAP_STATUS" "$RESULT_SWAP_MSG" 	   >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
fi

#-------------------------------------------------------------------------------------------------------------------------------------------------------
printf " %-45s" " 2) Service Status"									   >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
if [ "$RESULT_SERVICE" = "Normal" ]
then
        printf " %-15s \n" "$RESULT_SERVICE"                                                               >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
else
        printf "\n"                                                                                        >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
fi
if [ "$RESULT_SERVICE_STATUS" != "Normal" ]
then
	printf " %-25s %-19s %-15s %-40s\n" "" "MASTER Process" "$RESULT_SERVICE_STATUS" "CUBRID service is not running" >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
else
	if [ "$RESULT_DB_STATUS" != "Normal" ]
	then
		printf " %-25s %-19s %-15s %-40s\n" "" "DB Process" "$RESULT_DB_STATUS" "$RESULT_DB_MSG"	           >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
	fi
	if [ "$RESULT_BROKER_STATUS" != "Normal" ]
	then
		printf " %-25s %-19s %-15s %-40s\n" "" "Broker Process" "$RESULT_BROKER_STATUS" "$RESULT_BROKER_MSG" >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
	fi
	if [ "$RESULT_MANAGER_STATUS" != "Normal" ]
	then
		printf " %-25s %-19s %-15s %-40s\n" "" "Manager Process" "$RESULT_MANAGER_STATUS" "$RESULT_MANAGER_MSG" >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
	fi
	
	#-------------------------------------------------------------------------------------------------------------------------------------------------------
	printf " %-45s" " 3) HA Status"  		         						   >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
	if [ "$RESULT_HA" = "Normal" ]
	then
	        printf " %-15s \n" "$RESULT_HA"	                                                                   >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
	else
	        printf "\n"                                                                                        >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
	fi
	if [ "$RESULT_HA_DB_STATUS" != "Normal" ]
	then
	        printf " %-25s %-19s %-15s %-40s\n" "" "DB Process" "$RESULT_HA_DB_STATUS" "$RESULT_HA_DB_MSG" >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
	fi
	if [ "$RESULT_HA_APPLY_STATUS" != "Normal" ]
	then
	        printf " %-25s %-19s %-15s %-40s\n" "" "Apply Process" "$RESULT_HA_APPLY_STATUS" "$RESULT_HA_APPLY_MSG" >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
	fi
	if [ "$RESULT_HA_COPY_STATUS" != "Normal" ]
	then
	        printf " %-25s %-19s %-15s %-40s\n" "" "Copy Process" "$RESULT_HA_COPY_STATUS" "$RESULT_HA_COPY_MSG" >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
	fi
	if [ "$RESULT_HA_FAILCOUNT_STATUS" != "Normal" ]
	then
		printf " %-25s %-19s %-15s %-40s\n" "" "Fail Count" "$RESULT_HA_FAILCOUNT_STATUS" "$RESULT_HA_FAILCOUNT_MSG" >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
	fi
	if [ "$RESULT_HA_DELAY_STATUS" != "Normal" ]
	then
	        printf " %-25s %-19s %-15s %-40s\n" "" "Delay Page" "$RESULT_HA_DELAY_STATUS" "$RESULT_HA_DELAY_MSG" >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
	fi
	if [ "$RESULT_HA_FAILOVER_STATUS" != "Normal" ]
	then
	        printf " %-25s %-19s %-15s %-40s\n" "" "Fail Over" "$RESULT_HA_FAILOVER_STATUS" "$RESULT_HA_FAILOVER_MSG" >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
	fi
	if [ "$RESULT_HA_HOSTS_STATUS" != "Normal" ]
	then
	        printf " %-25s %-19s %-15s %-40s\n" "" "databases.txt" "$RESULT_HA_HOSTS_STATUS" "$RESULT_HA_HOSTS_MSG" >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
	fi
	if [ "$RESULT_HA_CONST_STATUS" != "Normal" ]
	then
	        printf " %-25s %-19s %-15s %-40s\n" "" "Constraint" "$RESULT_HA_CONST_STATUS" "$RESULT_HA_CONST_MSG" >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
	fi
	if [ "$RESULT_HA_COPYLOG_STATUS" != "Normal" ]
	then
	        printf " %-25s %-19s %-15s %-40s\n" "" "Copylog Count" "$RESULT_HA_COPYLOG_STATUS" "$RESULT_COLYLOG_MSG" >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
	fi
	
	
	#-------------------------------------------------------------------------------------------------------------------------------------------------------
	printf " %-45s" " 4) Space Status"                                                   >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
	if [ "$RESULT_SPACE" == "Normal" ]
	then
	        printf " %-15s \n" "$RESULT_SPACE"                                                               >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
	else
	        printf "\n"                                                                                        >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
	fi
	
	if [ "$CUB_VERSION" == 2008 ]
	then
	        if [ "$RESULT_DATASPACE_STATUS" != "Normal" ]
	        then
	                printf " %-25s %-19s %-15s %-40s\n" "" "Data Usage" "$RESULT_DATASPACE_STATUS" "$RESULT_DATASPACE_MSG"       >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
	        fi
	
	        if [ "$RESULT_INDEXSPACE_STATUS" != "Normal" ]
	        then
	                printf " %-25s %-19s %-15s %-40s\n" "" "Index Usage" "$RESULT_INDEXSPACE_STATUS" "$RESULT_INDEXSPACE_MSG"       >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
	        fi
	
	        if [ "$RESULT_GENERICSPACE_STATUS" != "Normal" ]
	        then
	                printf " %-25s %-19s %-15s %-40s\n" "" "Generic Usage" "$RESULT_GENERICSPACE_STATUS" "$RESULT_GENERICSPACE_MSG"       >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
	        fi
	
	
	        if [ "$RESULT_TEMPSPACE_STATUS" != "Normal" ]
	        then
	                printf " %-25s %-19s %-15s %-40s\n" "" "Temp Usage" "$RESULT_TEMPSPACE_STATUS" "$RESULT_TEMPSPACE_MSG"       >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
	        fi
	
	
	elif [ "$CUB_VERSION" -ge 10 ]
	then
	        if [ "$RESULT_DATASPACE_STATUS" != "Normal" ]
	        then
	                printf " %-25s %-19s %-15s %-40s\n" "" "Data Usage" "$RESULT_DATASPACE_STATUS" "$RESULT_DATASPACE_MSG"       >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
	        fi
	
	        if [ "$RESULT_TEMPSPACE_STATUS" != "Normal" ]
	        then
	                printf " %-25s %-19s %-15s %-40s\n" "" "Temp Usage" "$RESULT_TEMPSPACE_STATUS" "$RESULT_TEMPSPACE_MSG"       >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
	        fi
	
	else
	        if [ "$RESULT_DATASPACE_STATUS" != "Normal" ]
	        then
	                printf " %-25s %-19s %-15s %-40s\n" "" "Data Usage" "$RESULT_DATASPACE_STATUS" "$RESULT_DATASPACE_MSG"       >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
	        fi
	
	        if [ "$RESULT_INDEXSPACE_STATUS" != "Normal" ]
	        then
	                printf " %-25s %-19s %-15s %-40s\n" "" "Index Usage" "$RESULT_INDEXSPACE_STATUS" "$RESULT_INDEXSPACE_MSG"       >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
	        fi
	
	        if [ "$RESULT_GENERICSPACE_STATUS" != "Normal" ]
	        then
	                printf " %-25s %-19s %-15s %-40s\n" "" "Generic Usage" "$RESULT_GENERICSPACE_STATUS" "$RESULT_GENERICSPACE_MSG"       >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
	        fi
	
	
	        if [ "$RESULT_TEMPSPACE_STATUS" != "Normal" ]
	        then
	                printf " %-25s %-19s %-15s %-40s\n" "" "Temp Usage" "$RESULT_TEMPSPACE_STATUS" "$RESULT_TEMPSPACE_MSG"       >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
	        fi
	fi
	
	#-------------------------------------------------------------------------------------------------------------------------------------------------------
	printf " %-45s" " 5) Backup Status"                                              >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
	if [ "$RESULT_BACKUP" = "Normal" ]
	then
	        printf " %-15s \n" "$RESULT_BACKUP"                                                                >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
	else
	        printf "\n"                                                                                        >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
	fi
	
	if [ "$RESULT_BACKUP" != "Normal" ]
	then
	        printf " %-25s %-19s %-15s %-40s\n" "" "Full backup" "$RESULT_FULLBACKUP_STATUS" "$RESULT_FULLBACKUP_MSG"       >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
		if [ "$RESULT_INCREBACKUP_STATUS" != "Normal" ]
		then
		        printf " %-25s %-19s %-15s %-40s\n" "" "Incre backup" "$RESULT_INCREBACKUP_STATUS" "$RESULT_INCREBACKUP_MSG"       >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
		fi
	fi
	
	
	#-------------------------------------------------------------------------------------------------------------------------------------------------------
	printf " %-45s" " 6) Broker Status"				     					   >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
	if [ "$RESULT_BROKER" = "Normal" ]
	then
	        printf " %-15s \n" "$RESULT_BROKER"                                                                >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
	else
	        printf "\n"                                                                                        >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
	fi
	if [ "$RESULT_BROKER_DELAY_STATUS" != "Normal" ]
	then
	        printf " %-25s %-19s %-15s %-40s\n" "" "Delay" "$RESULT_BROKER_DELAY_STATUS" "$RESULT_BROKER_DELAY_MSG" >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
	fi
	if [ "$RESULT_BROKER_LONGQUERY_STATUS" != "Normal" ]
	then
	        printf " %-25s %-19s %-15s %-40s\n" "" "Long Query" "$RESULT_BROKER_LONGQUERY_STATUS" "$RESULT_BROKER_LONGQUERY_MSG" >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
	fi
	
	#-------------------------------------------------------------------------------------------------------------------------------------------------------
	if [ "$RESULT_SERVER_ERROR" = "Normal" ]
	then
	printf " %-45s %-15s \n" " 7) Server Error" $RESULT_SERVER_ERROR                                 >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
	else
	        printf " %-45s %-15s %-40s \n" " 7) Server Error" "$RESULT_SERVER_ERROR" "$RESULT_SERVER_MSG"      >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
	fi
	
	#-------------------------------------------------------------------------------------------------------------------------------------------------------
	if [ "$RESULT_RESTART" = "Normal" ]
	then
	printf " %-45s %-15s \n" " 8) Frequent Restarts" $RESULT_RESTART                                 >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
	else
	        printf " %-45s %-15s %-40s \n" " 7) Frequent Restarts" "$RESULT_RESTART" "$RESULT_RESTART_MSG"      >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
	fi
	
	#-------------------------------------------------------------------------------------------------------------------------------------------------------
	if [ "$DMESG_STATUS" = "Normal" ]
	then
	printf " %-45s %-15s \n" " 9) dmesg Error Check" $DMESG_STATUS		                         >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
	else
	        printf " %-45s %-15s %-40s \n" " 9) Dmesg" "$DMESG_STATUS" "$DMESG_MSG"			 >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
	fi
	
	#-------------------------------------------------------------------------------------------------------------------------------------------------------
	printf " %-45s" "10) Archive Log" 			  					   >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
	if [ "$RESULT_ARCHIVELOG" = "Normal" ]
	then
	        printf " %-15s \n" "$RESULT_ARCHIVELOG"                                                   >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
	else
	        printf "\n"                                                                                        >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
	fi
	if [ "$RESULT_ARCHIVE_STATUS" != "Normal" ]
	then
	        printf " %-25s %-19s %-15s %-40s\n" "" "Archive log count" "$RESULT_ARCHIVE_STATUS" "$RESULT_ARCHIVE_MSG" >> $JUMGUM_RESULT/cubrid_jumgum_summary.txt
	fi
fi


# final print
cat $JUMGUM_RESULT/cubrid_jumgum_summary.txt


