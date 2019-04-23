#!/bin/bash
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'
CYAN='\033[0;36m'

DOUBLE_CHECK=1
COUNTER=7
SLEEP_TIME=3

#Check That Firefox Profile was Passed
if [ -z $1 ] ; then
	echo -e "\n[${YELLOW}!${NC}] Error with Firefox Profile [${YELLOW}!${NC}]\n"
	echo -e "\tEXITING SCRIPT\n"
	sleep 7
	killall xterm >/dev/null 2>&1
	exit
fi 

SELENIUM_FIREFOX="$1"
DEFAULT_DEVICE=$( ip -br link | awk '/<BROADCAST/ {print $1; exit}' )

#Main Loop, Ensure Connectivity
while : ; do
	clear
	echo -e "Active$CYAN FIDELITY$NC Monitoring [${RED}+${NC}] \n"
	sleep $SLEEP_TIME
	
	DIG_DNS=$( dig +time=1 +tries=1 +noall +noedns +answer +short google.com )
	VALUE=$( wpa_cli -i $DEFAULT_DEVICE scan_results | grep -m 1 "xfinitywifi" )
   	AVAIL=$( curl -I -k -m 2 -s -w %{http_code} -o /dev/null $DIG_DNS )
   	WIFI_ID=$( iwgetid -r )
   	
   	if [[ ! -f 'script1.lock' ]] ; then  
		STATE=$( cat /sys/class/net/$DEFAULT_DEVICE/operstate )
		ONLINE=$( cat /sys/class/net/$DEFAULT_DEVICE/carrier )
		
		#Check if DEFAULT_DEVICE is up
		if [[ "$STATE" == "down" ]] ; then
			clear
			echo -e "[${YELLOW}!${NC}] Err: DEFAULT DEVICE IS NOT UP [${YELLOW}!${NC}]\n"
			sleep 2
			ifconfig $DEFAULT_DEVICE up
			if [ $? -eq 0 ] ; then
				continue;
			else 
				echo -e "\n[${RED}!${NC}] Err: IFCONFIG FAILED TO RAISE DEFAULT DEVICE [${RED}!${NC}]\n"
				sleep 7
				killall xterm >/dev/null 2>&1
				exit
			fi
		fi
		
		#Check if DEFAULT_DEVICE is online
		if [[ -z "$VALUE" && "$ONLINE" -eq 1 ]] ; then
			clear
			echo -e "Xfinitywifi Is No Longer In The Area \n"
			echo -e	"$CYAN	   Goodbye$NC [$YELLOW!$NC] \n"
			sleep 7
			killall xterm >/dev/null 2>&1
			exit
		fi
		
		
		#Check if bad default gateway
		DEFAULT_GW=$( ip route show )
		if [[ -z $DEFAULT_GW ]] ; then
			clear		
			systemctl restart network-manager 
			echo -e "[${YELLOW}!${NC}] Err: NO DEFAULT GATEWAY [${YELLOW}!${NC}]\n"
			sleep 2
			while true ; do 
				ip route show
				if [[ $? -eq 0 ]] ; then
					sleep 10
					break 
				fi
				sleep 0.5
			done
			continue
		fi
		
		#If Connected To Xfinity, Check If There is Internet Access
		if [[ "$AVAIL" == "000" && "$WIFI_ID" == "xfinitywifi" ]] ; then
			if [[ `expr $DOUBLE_CHECK % 5` -eq 0 ]]; then
				DOUBLE_CHECK=1
				SCRIPT_CHECK=$(pgrep -f script1.sh)
				echo -e "Internet$YELLOW DISCONTINUITY$NC Detected [${RED}!${NC}] \n"
				sleep 1
				clear
				if [ -n "$SCRIPT_CHECK" ]; then
					for pid in $(pgrep -f script1); do kill -9 $pid; done
				fi
				sudo xterm -T "Xfinity Wifi" -geometry 70x20+0+0 -fa monospace -fs 8 -e "./script1.sh $SELENIUM_FIREFOX"  & disown
				echo -e "Active$CYAN FIDELITY$NC Monitoring$YELLOW ReSynced$NC [${RED}+${NC}]"
				sleep 2
				COUNTER=7
				continue
			fi
			((DOUBLE_CHECK++))
			sleep 1
		fi
	fi
	if [ "$DOUBLE_CHECK" -gt 1 ]; then
		((COUNTER--))
		SLEEP_TIME=2
		if [[ "$COUNTER" -eq 0 && "$DOUBLE_CHECK" -ne 1 && `expr $DOUBLE_CHECK % 5` -ne 0 ]]; then 
			DOUBLE_CHECK=1
			COUNTER=7
			SLEEP_TIME=10
		fi
	fi	
done
