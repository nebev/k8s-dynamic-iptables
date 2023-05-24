#!/bin/bash
# Dynamically gets the IP Addresses of a set of hosts
#  and adds them to an ipset, then ensures iptables ONLY allows those

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
set=whitelist

echo "Dynamic IPTables Whitelist"
echo "--------------------------"

if [ -z ${hosts_csv+x} ]; then echo "hosts_csv is unset" exit 1; else echo "hosts_csv: '$hosts_csv'"; fi

OLDIFS=$IFS # Save the current value of the IFS (Internal Field Separator)
IFS=',' # Set the IFS to a comma (,) to split the string by commas

# Add Iptables to the image
echo "Installing IPTables"
apk add --update iptables ip6tables ipset bind-tools

# make sure the set exists
ipset -exist create $set hash:ip

for host in $hosts_csv; do
    me=$(basename "$0")
    ips=$(dig +short $host)

    IFS=$'\n' # make newlines the only separator; That's what dig outputs

    echo "Whitelisting $host"
    for ip in $ips; do
        if [ -z "$ip" ]; then
            echo "IP for '$host' not found"
            exit 1
        fi

        if ipset -q test $set $ip; then
            echo "IP '$ip' already in set '$set'."
        else
            echo ">> + '$ip' to set '$set'."
            ipset add $set $ip
        fi
    done

    IFS=',' # reset to comma separator for next loop
done

# restore the IFS
IFS=$OLDIFS

# Now let's do the IPTables rules
echo "Setting up IPTables"
iptables -F
iptables -P OUTPUT DROP
iptables -A OUTPUT -m state --state RELATED,ESTABLISHED -j ACCEPT

# Allow loopback connections (optional)
iptables -A OUTPUT -o lo -j ACCEPT

# Listening Ports
if [ -z ${listening_ports_csv+x} ]; then
    echo "listening_ports_csv is unset. Not adding exceptions for any listening ports"
else
    echo "Adding listening ports: $listening_ports_csv"
    IFS=','
    for port in $listening_ports_csv; do
        iptables -A INPUT -p tcp --dport $port -j ACCEPT
    done
fi
IFS=$OLDIFS

# Extra ranges
if [ -z ${extra_whitelist_ips_csv+x} ]; then
    echo "extra_whitelist_ips_csv is unset. Not adding further exceptions"
else
    echo "Allowing connectivity via extra_whitelist_ips_csv to: $extra_whitelist_ips_csv"
    IFS=','
    for tmpip in $extra_whitelist_ips_csv; do
        iptables -A OUTPUT -d $tmpip -j ACCEPT
    done
fi
IFS=$OLDIFS

# Allow outbound DNS queries
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT

# Allow outbound connections matching the "whitelist" match set
iptables -A OUTPUT -m set --match-set whitelist dst -j ACCEPT

# Drop all other outbound connections
iptables -A OUTPUT -j DROP

echo "Completed"
echo "Full list of IPTable rules:"

iptables -L