# bash-dhcp-server

Simple DHCP server based on OpenBSD and bash programming. 
bash-dhcp-server suitable **only** for assigning IP address in networks with single host sending DHCP Discover. 
This dhcp-server is **NOT** fit RFC2132, but still able to assign and renew IP addresses in small or temporary networks. 

Developed just for fun.

## Requirements
- OpenBSD netcat (tested on `debian patchlevel 1.130-3`)
- bash (tested on `4.4.12(1)-release`)
- root privileges

## Usage 
By default bash-dhcp-server assumes that host ip address is `192.168.45.1` and reserved ip for client is `192.168.45.101`. 
This can be changed with command-line options:
```
./dhcp.sh -s 10.0.0.1 -i 10.0.0.15
```
Full list of options available with option `-h`:
```
# ./dhcp.sh -h
Usage: ./dhcp.sh [option]...
	-s <ip>   set server's ip (default 192.168.45.101)
	-m <ip>   set netmask (default 255.255.255.0)
	-i <ip>   set ip address, proposed to client with dhcp (default 192.168.45.101)
	-g <ip>   set gateway (default 192.168.45.1)
	-l <time> set lease time (default 500)
	-h        show this help
	-d        enable debug output
```

Server quits after `DHCPACK` is sent. 
So, if there are many `DHCPDISCOVER`ing devices in network, ip address would be assigned to fastest one.
