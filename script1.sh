#!/bin/bash

CYAN='\033[0;36m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

CYCLECOUNT=0
SLOWPING=6
RETRY_ATTEMPTS=(2 2) #1st is actual value, 2nd same value to replace 1st 

IFACE=$( ip -br link | awk '/<BROADCAST,MULTICAST,UP/ {print $1; exit}' )
RES_DNS=$( cat /etc/resolv.conf 2> /dev/null )
DIG_DNS=$( dig +time=3 +tries=1 +noedns +noall +answer +short \
		  xfwweb.g.comcast.net @75.75.75.75 )

function check_firefoxlog_empty {
	[[ -s './firefox.log' ]] || shred -fzu -n 1 './firefox.log' 
}
		  
#Check That Firefox Profile, and Bin Dir was Passed
if [ -z $1 ] ; then
	echo -e "[${RED}!${NC}] Error with Firefox Profile [${RED}!${NC}]\n"
	echo -e "\tEXITING SCRIPT\n"
	sleep 7
	exit
elif [ -z $2 ] ; then
	echo -e "\n[${RED}!${NC}] Error with Firefox Bin Dir [${RED}!${NC}]\n"
	echo -e "\tEXITING SCRIPT\n"
	sleep 7
	exit	
fi 

SELENIUM_FIREFOX="$1"
SELENIUM_F_BIN="$2"

#Garbage Collection
shred -fzu -n 1 *.out *.lock wget* 2>/dev/null &

while : ; do
	clear
	#Prevent Script2 from interfering
	touch script1.lock
	
	#Network Card Reset Block
	systemctl stop network-manager.service
	ifconfig $IFACE down 
	sudo macchanger -r -b $IFACE 
	ifconfig $IFACE up
	systemctl start network-manager.service

	#Store New Values in global_vars 
	macchanger -s $IFACE | awk -F " " '/Current/ {print $3}' > "global_vars.csv";
	echo -e "\nWaiting for Connection [${YELLOW}?${NC}] \n"
	
	sleep 1 # Dont Spam NetworkManager Prematurely 
		
	#Wait For Established Connection	
	while true ; do
		wget --spider --timeout=1 --tries=1 $DIG_DNS  > /dev/null 2>&1
			if [[ $? -eq 0 ]] ; then
				echo -e "Connected [${RED}+${NC}]\n"
				break
			else
				if ! (( $SLOWPING % 6)) ; then
					DIG_DNS=$(dig +time=1 +tries=1 +noedns +noall +answer +short \
								xfwweb.g.comcast.net @75.75.75.75)
					echo -e  "${CYAN}	Pinging Xfinity...${NC}\n"
				fi
				((SLOWPING++))
				sleep 0.75
			fi
	done

	echo -e "Headless Firefox Launched [${YELLOW}+${NC}]\n"
	
	python3 logger.py "$SELENIUM_FIREFOX" "$SELENIUM_F_BIN" >> firefox.log 2>&1 
	EXIT_RETRY=($? 1)
	check_firefoxlog_empty 
	# Catch error code from Firefox, keep retrying for RETRY_ATTEMPTS amount

	if [[ ${EXIT_RETRY[0]} -eq 255 && ${RETRY_ATTEMPTS[0]} -lt 1 ]] ; then 					#No Free Option, No attempts left, exit
		echo -e "[${RED}!${NC}] Err: No Free Opt Dectected, Exiting [${RED}!${NC}]\n"	
		sleep 7
		killall xterm > /dev/null 2>&1
	elif [[ ${EXIT_RETRY[0]} -eq 255 && ${RETRY_ATTEMPTS[0]} -ne 0 ]] ; then				#No Free Option, restart at the begining
		echo -e "[${YELLOW}!${NC}] Err: No Free Opt Dectected, Retrying with New Mac [${YELLOW}!${NC}]\n"	
		sleep 2
		((RETRY_ATTEMPTS[0]--))
		continue
	elif [[ ${EXIT_RETRY[0]} -eq 254 && ${RETRY_ATTEMPTS[0]} -lt 1 ]] ; then 				#1 of the 4 Forms Failed to complete, No attempts left, exit
		echo -e "[${RED}!${NC}] Err: Failed To Complete a Form Page [${RED}!${NC}]\n"
		sleep 7
		killall xterm > /dev/null 2>&1
	elif [[ ${EXIT_RETRY[0]} -eq 254 && ${RETRY_ATTEMPTS[0]} -ne 0 ]] ; then				#1 of the 4 Forms Failed to complete
		echo -e "[${YELLOW}!${NC}] Err: Failed to Complete a Form Page [${YELLOW}!${NC}]\n"	
		sleep 2
	elif [[ ${EXIT_RETRY[0]} -ne 0 ]] ; then												#Failed to Launch, exit
		echo -e "[${RED}!${NC}] Err: Failed To Launch Firefox [${RED}!${NC}]\n"	
		sleep 7
		#Clean Up Dead Children
		kill -9 $(ps -ef | grep -P '(?!.*(/bin/bash|xterm -T))^(?=.*pts)(?=.*firefox)' \
						 | awk '{ print $2 }') 2>/dev/null
		killall xterm > /dev/null 2>&1
	fi
	
	while [[ ${EXIT_RETRY[0]} -ne 0  && ${RETRY_ATTEMPTS[0]} -ne 0 ]] ; do					#Try for RETRY_ATTEMPTS to re Launch
		echo -e "Headless Firefox [${CYAN}Re${NC}]Launched [${YELLOW}!${NC}]\n"
		((EXIT_RETRY[1]++))
		
		python3 logger.py "$SELENIUM_FIREFOX" "$SELENIUM_F_BIN" ${EXIT_RETRY[1]} >> firefox.log 2>&1 
		EXIT_RETRY[0]=$?
		check_firefoxlog_empty

		((RETRY_ATTEMPTS[0]--))
		
		#Clean Up Dead Children
		kill -9 $(ps -ef | grep -P '(?!.*(/bin/bash|xterm -T))^(?=.*pts)(?=.*firefox)' \
						 | awk '{ print $2 }') 2>/dev/null
	done

	if [[ ${EXIT_RETRY[0]} -ne 0 && ${EXIT_RETRY[1]} -ne 0 ]] ; then 						#Tried to Launch without Failure, No attempts left
		echo -e "[${RED}!${NC}] Err: Form Could Not Be Filled Out [${RED}!${NC}]\n"
		sleep 7
		killall xterm >/dev/null 2>&1
		exit
	fi

	#Remove Prescribed DNS and Replace With 3rd Party DNS 
	if [ -n "$RES_DNS" ] ; then
		cat > /etc/resolv.conf <<- EOM 
			nameserver 8.8.8.8
			nameserver 1.1.1.1
			nameserver 8.8.4.4
			nameserver 1.0.0.1
		EOM
	else
		echo -e "\nResolv File Missing or No DNS values Were Generated[${RED}!${NC}]"
		echo -e "\n${YELLOW}CHECK${NC} '/etc/resolv.conf' ${YELLOW}FILE${NC}\n"
		sleep 3
	fi
	
	shred -fzu -n 1 'script1.lock'
	
	#Check If Script2 Is Already Running
	if [ -z "$(pgrep script2.sh)" ] ; then
		sudo xterm -T "Xfinity Wifi" -geometry 70x5+0-0 -fa monospace -fs 8 \
				-e "./script2.sh $SELENIUM_FIREFOX $SELENIUM_F_BIN" & disown
	fi; clear
	
	((CYCLECOUNT++))
	echo -e "Entering Current Cycle at [${CYAN}$(date +%I:%M ) $(date +%p)${NC}]\n"
	echo -e "Cycle Number: [${YELLOW}$CYCLECOUNT${NC}]\n"

	#Check if Default is Set, Then Reference Time Given by Xfinity
	TIME=($(awk -F ',' 'NR==2 { gsub(/\r/,"",$0); gsub("^0*", "", $0); print $1, $2 }' global_vars.csv))
	
	HOURS=$(( ${TIME[0]} - $(date +%-H) ))
	OFFSET=25 #Margin of Error in seconds 
	
	#Determine Duration, deriving 12H Time from Military Time
	if [ $HOURS -eq 24 ] ; then 
 		MINS=$(( (60 % ${TIME[1]}) + $(date +%-M) ))
	elif [ $HOURS -ne 0 ] ; then
		HOURS=$(( $HOURS - 1 ))
		MINS=$(( ${TIME[1]} + (60 - $(date +%-M)) ))
	else 
		MINS=$(( $(date +%-M) - ${TIME[1]} ))
	fi

	SECS=$(( ($HOURS * 600) + ($MINS * 60) - $OFFSET))
	T_REF=$(date +%s -d +${SECS}sec)

	while [ $SECS -gt 1 ] ; do
		T_ACT=$(( ($(date +%s) - 1) - $OFFSET))
		#Hibernating Device ReSync
		if [ $T_REF -lt $T_ACT ] ; then
			echo -e "SysTime is Out Of Sync Due to Hibernating Device [${RED}!${NC}]"
			sleep 1.5
			SECS=0
		fi
		echo -ne "Countdown Until Next Cycle [${YELLOW}$SECS${NC}]\033[0K\r"
		sleep 1
		: $((SECS--))
	done
	RETRY_ATTEMPTS[0]=${RETRY_ATTEMPTS[1]} #Restore Retry Attempts to Previous Value
done
