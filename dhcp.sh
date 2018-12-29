#!/bin/bash

# Enable debug output
DEBUG=1

# Server ip
SERVER="192.168.43.1"
CLIENT="192.168.43.100"

# SIGINT from parent or child cause stopping
RUNNING=1
trap "{ RUNNING=0; echo Stopped.; }" SIGINT

# Handle requests while server is running
while [[ "$RUNNING" == "1" ]];  do
	# One netcat handles only one broadcast packet
	nc -l 0.0.0.0 -up 67 -w0 | stdbuf -o0 od -v -w1 -t x1 -An | {

		function read_dhcp() {
			# Read beginnig with constant size
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

			# Check, if packet if BOOTREQUEST
			if [[ "${msg[1]}" != "01" ]]; then
				return 1
			fi

			return 0

		}


	
		# Sets msg, dhcp_opt_key, dhcp_opt_len, dhcp_opt_data
		read_dhcp

		[[ "$?" != 0 ]] && exit

		if [[ "${dhcp_opt_data[53]}" == "01 " ]]; then
			echo "DISCOVER"
		fi

		if [[ ${dhcp_opt_data[53]} == "03 " ]]; then
			echo "REQUEST"
		fi
		
		exit
		# Check if there are magic cookie that means optional part of DHCP packet
		if [[ "${msg[236]}${msg[237]}${msg[238]}${msg[239]}" == "63825363" ]]; then
			DHCP_53=0
	
			# Read options until DHCP Option 255 is reached
			op=0
		fi
	
		options=()
	
		case $DHCP_53 in
			"01")
				echo "DISCOVER"
				msg[0]="02"
				msg[16]="C0"
				msg[17]="A8"
				msg[18]="2B"
				msg[19]="64"
	
				msg[20]="C0"
				msg[21]="A8"
				msg[22]="2B"
				msg[23]="01"
				echo ${msg[*]}
	
				opt=(
					"35" "01" "02" 
					"01" "04" "FF" "FF" "FF" "00"
					"33" "04" "00" "00" "00" "FF"
					"36" "04" "C0" "A8" "2B" "01"
					"FF" "00"
				)
				>/tmp/dhcp.payload
				for i in $(seq 0 $((${#msg[*]}-1))); do
					printf "\x${msg[i]}" >> /tmp/dhcp.payload 	
			    done
				for i in $(seq 0 $((${#opt[*]}-1))); do
					printf "\x${opt[i]}" >> /tmp/dhcp.payload	
			    done
				echo "Saved."
				cat /tmp/dhcp.payload | nc -ub 255.255.255.255 68 -s 192.168.43.1 -p 67 -w0
				echo "Sent."
			;;
			"03") 
				echo "REQUEST"	
				msg[0]="02"
				msg[16]="C0"
				msg[17]="A8"
				msg[18]="2B"
				msg[19]="64"
				opt=(
					"35" "01" "05" 
					"01" "04" "FF" "FF" "FF" "00"
					"33" "04" "00" "00" "00" "FF"
					"36" "04" "C0" "A8" "2B" "01"
					"FF" "00"
				)
				>/tmp/dhcp.payload
				for i in $(seq 0 $((${#msg[*]}-1))); do
					printf "\x${msg[i]}" >> /tmp/dhcp.payload 	
			    done
				for i in $(seq 0 $((${#opt[*]}-1))); do
					printf "\x${opt[i]}" >> /tmp/dhcp.payload	
			    done
				echo "Saved."
				cat /tmp/dhcp.payload | nc -ub 255.255.255.255 68 -s 192.168.43.1 -p 67 -w0
				echo "Sent."
				kill -INT $$
			;;
		esac
	}
done
