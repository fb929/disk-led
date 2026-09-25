#!/bin/bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin

do_usage(){
	cat <<EOF 1>&2
for control leds on disks

usage: $0 [status|help]

options:
    info options:
        status      -- print led status (action by default)
        statusShort -- print short led status, format: main_sg:slot | blockDevice | locate | fault
        -v, verbose -- print verbose status
        -vv         -- print extra verbose
    led options:
        ident /dev/sdX    - by block device
        ident /dev/sgX:Y  - by slot number
        fail  /dev/sdX
        fail  /dev/sgX:Y
        clean /dev/sdX
        clean /dev/sgX:Y
        clean all
EOF
	exit 1
}
go_get_sg_info(){
	LOCATE_FILE="$1"
	DIR=$( dirname "$LOCATE_FILE" )
	MAIN_SG=$( ls "$DIR/../device/scsi_generic/" 2>/dev/null )
	SLOT=$( cat "$DIR/slot" 2>/dev/null )
	STATUS=$( cat "$DIR/status" 2>/dev/null | sed 's|\s\+|_|g' )
	SAS_ADDRESS=$( cat "$DIR/device/sas_address" 2>/dev/null )
	DEVICE_BLOCK=$( ls "$DIR/device/block/" 2>/dev/null )
	DEVICE_BLOCK_PARTS=$( ls -d $DIR/device/block/$DEVICE_BLOCK/${DEVICE_BLOCK}* 2>/dev/null | awk -F '/' '{print $NF}' | xargs echo )
	LOCATE=$( cat "$LOCATE_FILE" 2>/dev/null )
	FAULT_FILE="$DIR/fault"
	FAULT=$( cat "$FAULT_FILE" 2>/dev/null )
}
do_status(){
	local VERBOSE=false		# if true - also print smartctl details for each disk (slower)
	local EXTRA_VERBOSE=false	# if true - additionally print the sas address of each disk
	local SHORT=false		# if true - short status output, used by auto_change_disk
	for ARG in $@; do
		if [[ "$ARG" == "verbose" ]]; then
			local VERBOSE=true
		elif [[ "$ARG" == "extra_verbose" ]]; then
			local VERBOSE=true
			local EXTRA_VERBOSE=true
		elif [[ "$ARG" == "short" ]]; then
			local SHORT=true
		fi
	done

	FILES="$( find /sys/ -name locate )"
	if [[ -z $FILES ]]; then
		exit 1
	fi
	local FIRST=true
	IFS=$'\n'
	if $SHORT; then
		# short output
		for FILE in $FILES; do
			go_get_sg_info $FILE
			MSG="$MAIN_SG:$SLOT|$DEVICE_BLOCK|$LOCATE|$FAULT"
			if $VERBOSE; then
				LEGENDA='# main_sg:slot| device_block | locate | fault'
				if $FIRST; then
					echo -e "$LEGENDA"
					FIRST=false
				fi
			fi
			echo -e "$MSG"
		done
	else
		# regular output
		for FILE in $FILES; do
			go_get_sg_info $FILE
			if [[ $LOCATE -gt 0 ]]; then
				local P_LOCATE="\e[1;32mident\e[0m"
			else
				local P_LOCATE="\e[1;30mident\e[0m"
			fi
			if [[ $FAULT -gt 0 ]]; then
				local P_FAULT="\e[1;31mfail\e[0m"
			else
				local P_FAULT="\e[1;30mfail\e[0m"
			fi

			LEGENDA="#main_sg:slot | status | device_block | device_block_parts"
			MSG="/dev/$MAIN_SG:$SLOT | $STATUS | $DEVICE_BLOCK | $DEVICE_BLOCK_PARTS"

			if $VERBOSE; then
				local DEVICE_MODEL=$( cat "$DIR/device/model" 2>/dev/null )
				local SMARTCTL_INFO=$( smartctl -i /dev/$DEVICE_BLOCK )
				local SERIAL_NUMBER=$( echo "$SMARTCTL_INFO" | grep -P "^Serial Number:" | awk '{print $NF}' )
				local USER_CAPACITY=$( echo "$SMARTCTL_INFO" | grep -P "^User Capacity:" | sed 's|.*bytes\s\+||' | tr -d '[ ]' )
				LEGENDA="$LEGENDA | device_model | serial_number | user_capacity"
				MSG="$MSG | $DEVICE_MODEL | $SERIAL_NUMBER | $USER_CAPACITY"
			fi
			if $EXTRA_VERBOSE; then
				LEGENDA="$LEGENDA | sas_address"
				MSG="$MSG | $SAS_ADDRESS"
			fi
			LEGENDA="$LEGENDA | led"
			MSG="$MSG | $P_LOCATE:$P_FAULT $LOCATE:$FAULT"
			if $FIRST; then
				echo -e "$LEGENDA" 1>&2
				FIRST=false
			fi
			echo -e "$MSG"
		done | column -t -s '|' | sort -V
	fi
}
do_led_clean_all(){
	IFS=$'\n'
	for FILE in $( find /sys/ -name locate ); do
		go_get_sg_info $FILE
		if [[ $LOCATE -ne 0 ]]; then
			echo 0 > $DIR/locate
		fi
		if [[ $FAULT -ne 0 ]]; then
			echo 0 > $DIR/fault
		fi
	done
}
do_led(){
	local ACTION="$1"
	local LED="$2"
	local DEV="$( echo $3 | sed 's|/dev/||' )"
	IFS=$'\n'
	DEVICE_MATCHED=0
	for FILE in $( find /sys/ -name locate ); do
		go_get_sg_info $FILE
		if [[ $MAIN_SG:$SLOT == $DEV || $DEVICE_BLOCK == $DEV ]]; then
			DEVICE_MATCHED=$(( $DEVICE_MATCHED + 1 ))
			break
		fi
	done
	case $ACTION in
		set)
			if [[ $DEVICE_MATCHED == 0 ]]; then
				echo "ERROR: device='$DEV' for led action='$ACTION $LED' not found" 1>&2
				exit 1
			fi
			case $LED in
				all)
					echo 1 > "$LOCATE_FILE"
					echo 1 > "$FAULT_FILE"
				;;
				locate)
					echo 1 > "$LOCATE_FILE"
				;;
				fault)
					echo 1 > "$FAULT_FILE"
				;;
			esac
		;;
		clear)
			if [[ $LED == 'all' && $DEV == 'all' ]]; then
				do_led_clean_all
			elif [[ $LED == 'all' && $DEV == '' ]]; then
				do_led_clean_all
			else
				if [[ $DEVICE_MATCHED == 0 ]]; then
					echo "ERROR: device='$DEV' for led action='$ACTION $LED' not found" 1>&2
					exit 1
				fi
				case $LED in
					all)
						echo 0 > "$LOCATE_FILE"
						echo 0 > "$FAULT_FILE"
					;;
					locate)
						echo 0 > "$LOCATE_FILE"
					;;
					fault)
						echo 0 > "$FAULT_FILE"
					;;
				esac
			fi
		;;
		*)
			echo "ERROR: action='$ACTION' unsupported for function ${FUNCNAME[0]}" 1>&2
			exit 1
		;;
	esac
}

# status options are collected first and do_status is called once after
# parsing, so "status -v" prints only the verbose status (not status twice)
STATUS_REQUESTED=false
STATUS_ARGS=""
if [[ -z $@ ]]; then
	STATUS_REQUESTED=true
fi
for ARG in $@; do
	if echo "$ARG" | grep -qP -- "^(statusShort|--statusShort)$"; then
		STATUS_REQUESTED=true
		STATUS_ARGS="$STATUS_ARGS short"
	elif echo "$ARG" | grep -qP -- "^(status|--status)$"; then
		STATUS_REQUESTED=true
	elif echo "$ARG" | grep -qP -- "^(-v|-verbose|--verbose|verbose)$"; then
		STATUS_REQUESTED=true
		STATUS_ARGS="$STATUS_ARGS verbose"
	elif echo "$ARG" | grep -qP -- "^(-vv|-extra_verbose|--extra_verbose|extra_verbose)$"; then
		STATUS_REQUESTED=true
		STATUS_ARGS="$STATUS_ARGS extra_verbose"
	elif echo "$ARG" | grep -qP -- "^(help|--help|-h)$"; then
		do_usage
	elif echo "$ARG" | grep -qP -- "^(ident|-i|--ident|locate|--locate)$"; then
		shift
		ARG2="$1"
		do_led set locate "$ARG2"
	elif echo "$ARG" | grep -qP -- "^(fail|-f|--fail|fault|--fault)$"; then
		shift
		ARG2="$1"
		do_led set fault "$ARG2"
	elif echo "$ARG" | grep -qP -- "^(clear|-c|--clear|clean|--clean)$"; then
		shift
		ARG2="$1"
		do_led clear all "$ARG2"
	fi
	if ! [[ -z "$1" ]]; then
		shift
	fi
done
if $STATUS_REQUESTED; then
	unset IFS	# do_led may have changed IFS, restore default word splitting for STATUS_ARGS
	do_status $STATUS_ARGS
fi
