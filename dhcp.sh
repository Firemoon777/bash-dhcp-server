#!/bin/bash

VERSION="1.2"

# Enable debug output
DEBUG=0

# Server ip
SERVER="192.168.45.1"
# Netmask for client
NETMASK="255.255.255.0"
# Proposed ip
CLIENT="192.168.45.101"
# Gateway ip
GATEWAY="$SERVER"
# Lease time in seconds
LEASE_TIME=500

NC=${NC:-/bin/nc}

while getopts "s:m:i:g:l:p:hd" opt; do
	case $opt in
		s)
			SERVER=$OPTARG
		;;
		m)
			NETMASK=$OPTARG
		;;
		i)
			CLIENT=$OPTARG
		;;
		g)
			GATEWAY=$OPTARG
		;;
		l)
			LEASE_TIME=$OPTARG
		;;
		p)
			INTERFACE=$OPTARG
		;;
		d)
			DEBUG=1
		;;
		h)
			echo -e "bash-dhcp-server $VERSION"
			echo -e "Usage: $0 [option]..."
			echo -e "\t-s <ip>   set server's ip (default $CLIENT)"
			echo -e "\t-m <ip>   set netmask (default $NETMASK)"
			echo -e "\t-i <ip>   set ip address, proposed to client with dhcp (default $CLIENT)"
			echo -e "\t-g <ip>   set gateway (default $GATEWAY)"
			echo -e "\t-l <time> set lease time (default $LEASE_TIME)"
			echo -e "\t-p <interface> set server's ip on an interface"
			echo -e "\t-h        show this help"
			echo -e "\t-d        enable debug output"
			exit
		;;
		*)
			echo -e "Help:\n\t$0 -h";
			exit
		;;
	esac
done

if [[ $($NC -h 2>&1 | head -1 | grep -q OpenBSD; echo $?) == "1" ]]; then 
	echo "Not supported nc."
	echo "This solution works only with OpenBSD netcat."
	echo "Your netcat: $NC"
	echo "You can use alternative with variable NC"
	echo "Example:"
	echo -e "\tNC=/usr/local/bin/nc $0"
	exit	
fi

if [[ $(id -u) -ne 0 ]]; then
	echo "Please, run as root"	
	exit
fi

# Convert to 32-bit hex
LEASE_TIME=$(printf "%08X" $LEASE_TIME)

# SIGINT from parent or child cause stopping
RUNNING=1
trap "{ RUNNING=0; echo Stopped.; }" SIGINT

echo "Started"

if [ -n "$INTERFACE" ]; then
	echo "Add $SERVER to $INTERFACE"
	ip addr add $SERVER/24 dev $INTERFACE
fi

# Handle requests while server is running
while [[ "$RUNNING" == "1" ]];  do
	# One netcat handles only one broadcast packet
	"$NC" -lup 67 -w0 | stdbuf -o0 od -v -w1 -t x1 -An | {

		function read_dhcp() {
			# Read beginning with constant size
			msg=()
			for i in {0..235}; do
				read -r tmp
				msg[$i]=$tmp
			done

			# Get unique request id
			for i in $(seq 4 7); do
				xid=${xid}${msg[i]}
			done

			# Get hardware addr
			chaddr=${msg[28]}
			for i in $(seq 29 $((28+16#${msg[2]}-1))); do
				chaddr=${chaddr}:${msg[i]}
			done

			# Attempt to read cookie
			cookie=()
			for i in {0..3}; do
				read -r tmp
				cookie[$i]=$tmp
			done

			# Read DHCP options if available
			dhcp_opt_keys=""
			dhcp_opt_data=()
			dhcp_opt_len=()
			if [[ "${cookie[0]}${cookie[1]}${cookie[2]}${cookie[3]}" == "63825363" ]]; then
				while [[ $op != '255' ]]; do
					read -r op
					read -r len
					# Convert from hex to dec
					op=$((16#$op))
					len=$((16#$len))
					dhcp_opt_keys="$dhcp_opt_keys$op "
					dhcp_opt_len[$op]=$len
					for i in $(seq 0 $(($len-1))); do
						read -r data
						dhcp_opt_data[$op]="${dhcp_opt_data[$op]}$data "
					done
				done
			fi
			
			if [[ "$DEBUG" == "1" ]]; then
				echo "Packet:"; echo ${msg[*]}
				echo "xid: $xid"
				echo "chaddr: $chaddr"
				echo "Options:"
				for i in $dhcp_opt_keys; do
					echo "Option $i length ${dhcp_opt_len[i]}"
					[[ ${dhcp_opt_len[i]} != "0" ]] && echo -e "\tData: ${dhcp_opt_data[i]}"
				done
			fi	

			# Check, if packet is BOOTREQUEST
			if [[ "${msg[1]}" != "01" ]]; then
				return 1
			fi

			return 0

		}

		function dhcp_answer_offer() {
			# Set first byte to BOOTREPLY
			msg[0]="02"

			# Set proposed address to yiaddr field
			msg[16]=$(printf "%02X" $(echo $CLIENT | cut -d. -f1))
			msg[17]=$(printf "%02X" $(echo $CLIENT | cut -d. -f2))
			msg[18]=$(printf "%02X" $(echo $CLIENT | cut -d. -f3))
			msg[19]=$(printf "%02X" $(echo $CLIENT | cut -d. -f4))

			# Set dhcp server address to siaddr field
			msg[20]=$(printf "%02X" $(echo $SERVER | cut -d. -f1))
			msg[21]=$(printf "%02X" $(echo $SERVER | cut -d. -f2))
			msg[22]=$(printf "%02X" $(echo $SERVER | cut -d. -f3))
			msg[23]=$(printf "%02X" $(echo $SERVER | cut -d. -f4))

			raw_opt=(
					# Set "magic" cookie
					"63" "82" "53" "63"
					# "op" "len" "data", "data", ...
					# Gateway
					"03" "04" $(printf "%02X" $(echo $GATEWAY | cut -d. -f1)) $(printf "%02X" $(echo $GATEWAY | cut -d. -f2)) $(printf "%02X" $(echo $GATEWAY | cut -d. -f3)) $(printf "%02X" $(echo $GATEWAY | cut -d. -f4))
					# DHCP Message type OFFER	
					"35" "01" "02" 
					# Netmask 
					"01" "04" $(printf "%02X" $(echo $NETMASK | cut -d. -f1)) $(printf "%02X" $(echo $NETMASK | cut -d. -f2)) $(printf "%02X" $(echo $NETMASK | cut -d. -f3)) $(printf "%02X" $(echo $NETMASK | cut -d. -f4))
					# Lease time in seconds
					"33" "04" $(echo $LEASE_TIME | cut -b1,2) $(echo $LEASE_TIME | cut -b3,4) $(echo $LEASE_TIME | cut -b5,6) $(echo $LEASE_TIME | cut -b7,8)
					# DHCP Server ip
					"36" "04" $(printf "%02X" $(echo $SERVER | cut -d. -f1)) $(printf "%02X" $(echo $SERVER | cut -d. -f2)) $(printf "%02X" $(echo $SERVER | cut -d. -f3)) $(printf "%02X" $(echo $SERVER | cut -d. -f4))
					# End 
					"FF" "00"
			)
		}

		function dhcp_answer_ack() {
			# Set first byte to BOOTREPLY
			msg[0]="02"

			# Set proposed address to yiaddr field
			msg[16]=$(printf "%02X" $(echo $CLIENT | cut -d. -f1))
			msg[17]=$(printf "%02X" $(echo $CLIENT | cut -d. -f2))
			msg[18]=$(printf "%02X" $(echo $CLIENT | cut -d. -f3))
			msg[19]=$(printf "%02X" $(echo $CLIENT | cut -d. -f4))
			raw_opt=(
					# Set "magic" cookie
					"63" "82" "53" "63"
					# "op" "len" "data", "data", ...
					# Gateway
					"03" "04" $(printf "%02X" $(echo $GATEWAY | cut -d. -f1)) $(printf "%02X" $(echo $GATEWAY | cut -d. -f2)) $(printf "%02X" $(echo $GATEWAY | cut -d. -f3)) $(printf "%02X" $(echo $GATEWAY | cut -d. -f4))
					# DHCP Message type ACK	
					"35" "01" "05" 
					# Netmask 
					"01" "04" $(printf "%02X" $(echo $NETMASK | cut -d. -f1)) $(printf "%02X" $(echo $NETMASK | cut -d. -f2)) $(printf "%02X" $(echo $NETMASK | cut -d. -f3)) $(printf "%02X" $(echo $NETMASK | cut -d. -f4))
					# Lease time in seconds
					"33" "04" $(echo $LEASE_TIME | cut -b1,2) $(echo $LEASE_TIME | cut -b3,4) $(echo $LEASE_TIME | cut -b5,6) $(echo $LEASE_TIME | cut -b7,8)
					# DHCP Server ip
					"36" "04" $(printf "%02X" $(echo $SERVER | cut -d. -f1)) $(printf "%02X" $(echo $SERVER | cut -d. -f2)) $(printf "%02X" $(echo $SERVER | cut -d. -f3)) $(printf "%02X" $(echo $SERVER | cut -d. -f4))
					# End 
					"FF" "00"
			)
		}

		function write_dhcp() {
				>/tmp/dhcp.payload
				for i in ${msg[*]}; do
					printf "\x$i" >> /tmp/dhcp.payload 	
	     			done
				for i in ${raw_opt[*]}; do
					printf "\x$i" >> /tmp/dhcp.payload	
				done
				cat /tmp/dhcp.payload | "$NC" -ub 255.255.255.255 68 -s $SERVER -p 67 -w0
				[[ "$DEBUG" != "1" ]] && rm /tmp/dhcp.payload
		}

		# Sets:
		#	msg, 
		#	dhcp_opt_key, dhcp_opt_len, dhcp_opt_data
		#	xid, chaddr
		read_dhcp

		[[ "$?" != 0 ]] && exit

		DONE=0

		# Prepare answer
		# Gets:
		#	msg, 
		#	dhcp_opt_key, dhcp_opt_len, dhcp_opt_data
		#	xid, chaddr
		# Sets:
		# 	msg, raw_opt
		if [[ "${dhcp_opt_data[53]}" == "01 " ]]; then
			echo "DHCPDISCOVER from $chaddr"
			dhcp_answer_offer
		elif [[ ${dhcp_opt_data[53]} == "03 " ]]; then
			echo "DHCPREQUEST from $chaddr"
			dhcp_answer_ack
			DONE=1
		else
			exit
		fi

		# Gets:
		#	msg, raw_opt
		write_dhcp

		if [[ "$DONE" == "1" ]]; then
			echo "$CLIENT/$NETMASK given to $chaddr"
			kill -INT $$
		fi
	}
done
