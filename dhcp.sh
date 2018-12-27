#!/bin/bash

nc -l 0.0.0.0 -up 67 | stdbuf -o0 od -v -w1 -t u1 -An | (
	msg=()
	for i in {0..239}; do
		read -r tmp
		msg[$i]=$tmp
	done

	echo ${msg[*]}

	if [[ "${msg[236]}${msg[237]}${msg[238]}${msg[239]}" == "991308399" ]]; then
		op=0
		while [[ $op -ne 255 ]]; do
			read -r op
			read -r len
			echo "op: $op, len $len"
			if [[ $len > 0 ]]; then
				printf '\t'
				for i in $(seq 0 $(($len-1))); do
					read -r data
					printf "%x " $data
				done
				echo
			fi
		done
	fi
)
