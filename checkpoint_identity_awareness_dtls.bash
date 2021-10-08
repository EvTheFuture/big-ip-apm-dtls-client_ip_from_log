#!/bin/bash
#
#    Trigger REST API call to Checkpoint Identity Aware Firewall
#    when a user have been assigned a VPN IP address.
#
#    Version 0.9.10
#
#    Copyright (C) 2021    Valitron AB <magnus.sandin@Valitron.se>
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

log_identifier="$(basename "$0")"
apmlog="/var/log/apm"
pidfile="/run/${log_identifier}.pid"
abort=0

address=""
secret=""
vpnip=""
debug=0
daemonize=0

notice() {
	logger -p local0.notice -t "${log_identifier}" "$@"
}

warning() {
	logger -p local0.warning -t "${log_identifier}" "$@"
}

error() {
	logger -p local0.err -t "${log_identifier}" "$@"
	echo "ERROR:" "$@" >&2
}

debug() {
	test "$debug" == "1" && logger -p local0.debug -t "${log_identifier}" "$@"
}

cleanup() {
	abort=1

	notice "Cleaning up $BASHPID"

	test -f "$pidfile" && rm "$pidfile"

	notice "Done cleaning, goodbye..."
	kill 0
}

scan_apmlog() {
	install_handlers

	notice "Starting to scan ${apmlog}..."

	while read -r line ; do
		test "$abort" == "1" && break

		# Only match lines containing VPN address assignment
		echo "$line" | grep -F -q ": Assigned PPP Dynamic IPv4:" || continue

		# Find session ID from the log line
		sid="$(echo "$line" | sed -E 's/^.*:(.{8}): Assigned PPP Dynamic IPv4:.*$/\1/')"

		# Bail out and log an error if we are unable to parse the line
		test -z "$sid" && error "Unable to read session id from '$line'" && continue

		# Find IP address assigned to the VPN client from the log line
		vpnip="$(sessiondump --sid "$sid" | grep -F session.assigned.clientip | cut -d " " -f 3)"

		# Bail out and log an error if we don't find an IP address in the session
		test -z "$vpnip" && error "Unable to read assigned VPN IP from session '$sid'" && continue

		username="$(sessiondump --sid "$sid" | grep -F session.logon.last.username | cut -d " " -f 3)"

		# Bail out and log an error if we don't find a username in the session
		test -z "$username" && error "Unable to read username from session '$sid'" && continue

		notice "Successfully got username: '$username' and IP: '$vpnip' from session: '$sid'"
		register_uid_ip "$username" "$vpnip"
	done < <(tail -n0 -F "$apmlog")
}

register_uid_ip() {
	user="$1"
	ip="$2"

	notice "Sending $user / $ip to: $address"
	curl -k -v --data "{ \"shared-secret\":\"$secret\", \"ip-address\":\"$ip\", \"user\":\"$user\" }" "https://$address/_IA_API/v1.0/add-identity" | notice
}

kill_old() {
	notice "Checking if old process exists"
	# Check if we are already running
	if [ -f "$pidfile" ] ; then
		opid="$(<"$pidfile")"
		if [ "$opid" != "" ] && [ -d "/proc/$opid" ] ; then
			notice "Sending SIGHUP to $opid"
			kill -1 "$opid"
		fi
	fi
}

sigint() {
	notice "SIGINT received ($BASHPID)"
	trap - INT
	cleanup
}

sighup() {
	notice "SIGHUP received ($BASHPID)"
	trap - HUP
	cleanup
}


install_handlers() {
	# Store PID in the pidfile
	echo "$BASHPID" > "$pidfile"

	# Install signal handlers
	trap sigint INT
	trap sighup HUP

	notice "Signal handlers intalled for ($BASHPID)"
}


usage() {
	echo "Usage: ${log_identifier} -a <address> -s <secret> [-u <username> -i <ip address>] [OPTIONS]"
	echo ""
	echo "Options:"
	echo "	-a <address>	Address where to POST Username/IP"
	echo "	-s <secret>	Secret to use"
	echo "	-u <username>	Send this username immediately and exit"
	echo "	-i <ip address>	Send this IP address immediately and exit"
	echo "	-d		Run in backgroud"
	echo "	-v		Be verbose (debug)"
	echo "	-k		kill previous instance (if any in /run/<pid>)"
	echo "	-h		Print this help"
	exit 1
}


while getopts "kvhda:s:u:i:" options ; do
	case "${options}" in
		a)
			address="${OPTARG}"
			;;
		s)
			secret="${OPTARG}"
			;;
		u)
			username="${OPTARG}"
			;;
		i)
			vpnip="${OPTARG}"
			;;
		v)
			debug=1
			;;
		d)
			daemonize=1
			;;
		k)
			kill_old
			exit 0
			;;
		*)
			usage
			;;
	esac
done

set -e nounset

# If address or secret missing, bail out...
#
if [ "$address" == "" ] || [ "$secret" == "" ] ; then
	error "Address and/or secret missing..."
	usage
fi

# if username or vpnip (client address) is set
# handle direct publish to the API
#
if [ "$username" != "" ] || [ "$vpnip" != "" ] ; then
	test "$username" == "" -o "$vpnip" == "" && usage

	register_uid_ip "$username" "$vpnip"
	exit $?
fi

# If there is a pid file and process exists, bail out
# Check if we are already running
if [ -f "$pidfile" ] ; then
	opid="$(<"$pidfile")"
	if [ "$opid" != "" ] && [ -d "/proc/$opid" ] ; then
		error "Already running ($opid), exiting..."
		exit 2
	fi
fi

# Loop until it's time to end upon signal received
loop() {
	while [ ${abort} -ne 1 ] ; do
		scan_apmlog 2| warning
		test ${abort} -ne 1 && warning "Unexpected end of reading, retrying in 1s..." && sleep 1
	done
}

if [ "$daemonize" == "1" ] ; then
	loop > /dev/null 2>&1 &

	notice "Forked child into background (-d)"
else
	loop > /dev/null 2>&1
fi

exit 0
