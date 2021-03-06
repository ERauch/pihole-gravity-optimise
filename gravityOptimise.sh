#!/usr/bin/env bash

# Set file variables
file_gravity="/etc/pihole/gravity.list"
dir_wildcards="/etc/dnsmasq.d"
file_regex="/etc/pihole/regex.list"

invertMatchConflicts () {

	# Conditional exit
	# Return supplied match criteria (all domains)
	if [ -z "$1" ] || [ -z "$2" ]; then
		echo "$2"
		return 1
	fi

	# Convert target - something.com -> ^something.com$
        match_target=$(sed 's/^/\^/;s/$/\$/' <<< "$2")
        # Convert exact domains (pattern source) - something.com -> ^something.com$
        exact_domains=$(sed 's/^/\^/;s/$/\$/' <<< "$1")
        # Convert wildcard domains (pattern source) - something.com - .something.com$
        wildcard_domains=$(sed 's/^/\./;s/$/\$/' <<< "$1")
	# Combine exact and wildcard matches
        match_patterns=$(printf '%s\n' "$exact_domains" "$wildcard_domains")

	# Invert match wildcards
        # Invert match exact domains
        # Remove start / end markers
        grep -vFf <(echo "$match_patterns") <<< "$match_target" |
			sed 's/[\^$]//g'
}

pihole_update ()
{
	echo "#### Gravity List ####"

	# Update gravity.list
	echo "--> Updating gravity.list"
	pihole updateGravity > /dev/null
	# Count gravity entries
	count_gravity=$(wc -l < $file_gravity)
	# Status update
	echo "--> $count_gravity gravity list entries"
}

process_wildcards () {

	echo "#### Wildcard Removals ####"

	# Check gravity.list is not empty
	if [ ! -s $file_gravity ]; then
			echo "--> gravity.list is empty or does not exist"
			return 1
	fi

	# Fetch initial gravity count
	count_gravity=$(wc -l < $file_gravity)

	# Grab unique base domains from dnsmasq conf files
	echo "--> Fetching wildcards from $dir_wildcards"
	domains=$(find $dir_wildcards -name "*.conf" -type f -print0 |
		xargs -r0 grep -hE "^address=\/.+\/(([0-9]+\.){3}[0-9]+|::)?$" |
			cut -d'/' -f2 |
				sort -u)

	# Conditional exit
	if [ -z "$domains" ]; then
			echo "--> No wildcards were captured from $dir_wildcards"
			return 1
	fi

	echo "--> $(wc -l <<< "$domains") wildcards found"

	# Read gravity.list
	echo "--> Reading $file_gravity"
	gravity_contents=$(cat $file_gravity)

	# Invert match wildcards against gravity.list
	echo "--> Removing wildcard matches"
	new_gravity=$(invertMatchConflicts "$domains" "$gravity_contents")

	# Status update
	removal_count=$(($count_gravity-$(wc -l <<< "$new_gravity")))

	# If there was an error populating new_gravity.list
	# Or no changes need to be made
	if [ -z "$new_gravity" ] || [ "$removal_count" = 0 ]; then
		echo "--> No changes required."
		return 0
	fi

	# Status update
	echo "--> $removal_count unnecessary domains found"

	# Output gravity.list
	echo "--> Outputting $file_gravity"
	echo "$new_gravity" | sudo tee $file_gravity > /dev/null

	# Status update
	echo "--> $(wc -l < $file_gravity) domains in gravity.list"

	return 0
}

process_regex ()
{
	echo "#### Regex Removals ####"

	# Check gravity.list is not empty
	if [ ! -s $file_gravity ]; then
			echo "--> gravity.list is empty or does not exist"
			return 1
	fi

	# Count gravity entries
	count_gravity=$(wc -l < $file_gravity)

	# Only read it if it exists and is not empty
	if [ -s $file_regex ]; then
		regexList=$(grep '^[^#]' $file_regex)
	else
		echo "--> Regex list is empty or does not exist."
		return 1
	fi

	# Status update
	echo "--> $(wc -l <<< "$regexList") regexps found"

	# Invert match regex patterns against gravity.list
	echo "--> Identifying unnecessary domains"

	new_gravity=$(grep -vEf <(echo "$regexList") $file_gravity)

	# If there are no domains after regex removals
	if [ -z "$new_gravity" ]; then
		echo "--> No unnecessary domains were found"
		return 0
	fi

	# Status update
	echo "--> $(($count_gravity-$(wc -l <<< "$new_gravity"))) unnecessary hosts identified"

	# Output file
	echo "--> Outputting $file_gravity"
	echo "$new_gravity" | sudo tee $file_gravity > /dev/null

	# Status update
	echo "--> $(wc -l < $file_gravity) domains in gravity.list"

	return 0
}

finalise () {

	echo "#### Finalise changes ####"

	# Refresh Pihole
	echo "--> Sending SIGHUP to Pihole"
	sudo killall -SIGHUP pihole-FTL
}

# Run gravity update
pihole_update
# Process wildcard removals
process_wildcards
# Process regex removals
process_regex
# Finish up
finalise
