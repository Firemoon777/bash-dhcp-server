#!/bin/bash

nc -l 0.0.0.0 -up 67 | stdbuf -o0 od -v -w1 -t x1 -An | (
	msg=()
	for i in {0..239}; do
		read -r tmp
		msg[$i]=$tmp
	done

	echo ${msg[*]}

	if [[ "${msg[236]}${msg[237]}${msg[238]}${msg[239]}" == "63825363" ]]; then
		DHCP_53=0

		op=0
		while [[ $op != 'ff' ]]; do
			read -r op
			read -r len
			dec_len=$((16#$len))
			echo "op: $op, len $len, dec_len $dec_len"
			if [[ "$op" == 35 ]]; then 
				read -r DHCP_53
				echo "DHCP Message type: $DHCP_53"
			elif [[ $len > 0 ]]; then
				printf '\t'
				for i in $(seq 0 $(($dec_len-1))); do
					read -r data
					printf "%s " $data
				done
				echo
			fi
		done
	fi

	options=()

	case $DHCP_53 in
		"01")
			echo "DISCOVER"
			msg[0]="02"
			msg[16]="C0"
			msg[17]="A8"
			msg[18]="01"
			msg[19]="64"

			msg[20]="C0"
			msg[21]="A8"
			msg[22]="01"
			msg[23]="01"
			echo ${msg[*]}

			opt=(
				"35" "01" "02" 
				"01" "04" "FF" "FF" "FF" "00"
				"33" "04" "00" "00" "00" "FF"
				"36" "04" "C0" "A8" "01" "01"
				"FF" "00"
			)
			>/tmp/dhcp.payload
			for i in $(seq 0 $((${#msg[*]}-1))); do
				printf "\x${msg[i]}" >> /tmp/dhcp.payload 	
		    done
			for i in $(seq 0 $((${#opt[*]}-1))); do
				printf "\x${opt[i]}" >> /tmp/dhcp.payload	
		    done

			cat /tmp/dhcp.payload | nc -ub 255.255.255.255 68 -s 192.168.43.1 -p 67
		;;
		3) 
			echo "REQUEST"	
		;;
	esac
)
