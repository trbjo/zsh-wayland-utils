__colorpicker() {
    if [[ $#@ -lt 1 ]]
    then
        colorcode=$(grim -g "$(env XCURSOR_SIZE=48 slurp -p )" -t ppm - | convert - -format "%[pixel:p{0,0}]" txt:- | awk 'FNR == 2 {print $2 " " $3}' | tr -d "\n" | tee /dev/tty | sed 's/.*#//') 2> /dev/null
        if [ $colorcode ]
        then
            perl -e 'foreach $a(@ARGV){print " \e[48:2::".join(":",unpack("C*",pack("H*",$a)))."m  \e[49m"; };print "\n"' "$colorcode"
            wl-copy -n $colorcode
        fi
    else
        perl -e 'foreach $a(@ARGV){print "\e[48:2::".join(":",unpack("C*",pack("H*",$a)))."m  \e[49m "}; print "\n"' "${@//\#/}"
    fi
}
alias ss='noglob __colorpicker'

notify(){
    if [ $? -eq 0 ]; then
        title="Succes"
        icon="process-completed"
    else
        title="Failure"
        icon="dialog-error"
    fi

    message="$(echo $PWD | sed -e 's/\/.*\///g')"
    [ "$1" ] && message=$1
    swaymsg "output * dpms on"
    notify-send "Notification $title" "$message" --icon="$icon" --expire-time=99999
}

fd() {
    /usr/bin/fd --color always ${@} | tee >(wc -l | read num; if [[ $num -eq 1 ]]; then /usr/bin/fd -a ${@} | sed -e 's/ /\\ /g' | wl-copy -n --; fi)
}

confirm() {
    echo -n "Continue? y or n? "
    read REPLY
    case $REPLY in
    [Yy]) _ans='yes' ;; # you can change what you do here for instance
    [Nn]) _ans='no' ;;
    # Here are a few optional options to choose between
    # Any other answer:

    # 1. Repeat the question
    *) confirm ;;

    # 2. ignore
    # *) ;;

    # 3. Exit terminal
    # *) exit ;;

    esac
    REPLY=''
}


stc() {
    local _myfile
    subl --command doas_edit
    _myfile=$(</tmp/doasedit)
    print "Do you want to delete this file: $(_colorizer $_myfile)"
    confirm
    if [[ $_ans == "yes" ]]; then
        subl --command close
        rm $_myfile
    fi
    return 0
}

copy-to-wlcopy() {
    [ -z $BUFFER ] && return 0
    if ((REGION_ACTIVE)); then
        if [[ $CURSOR -gt $MARK ]]; then
            wl-copy -n -- ${BUFFER[$MARK,$CURSOR]:1}
        else
            wl-copy -n -- ${BUFFER[$CURSOR,$MARK]:1}
        fi
        zle set-mark-command -n -1
    else
        wl-copy -n -- $BUFFER
    fi
}
zle -N copy-to-wlcopy
bindkey -e "\ew" copy-to-wlcopy

backward-kill-line() {
    [ -z $BUFFER ] && return 0
    if ((REGION_ACTIVE)); then
        if [[ $CURSOR -gt $MARK ]]; then
            wl-copy -n -- ${BUFFER[$MARK,$CURSOR]:1}
            BUFFER=$BUFFER[0,MARK]$BUFFER[CURSOR+1,-1]
            CURSOR=$MARK
        else
            wl-copy -n -- ${BUFFER[$CURSOR,$MARK]:1}
            BUFFER=$BUFFER[1,CURSOR]$BUFFER[MARK+1,-1]
        fi
        zle set-mark-command -n -1
    else
        wl-copy -n -- $BUFFER
        unset BUFFER
    fi
}
zle -N backward-kill-line
bindkey -e "^U" backward-kill-line

# copies the full path of a file for later mv
cpp() {
    if [[ ${#@} == 0 ]]; then
        pwd |& tee /dev/tty |& wl-copy -n
    else
        wl-copy -n -- $(realpath "${1}") && wl-paste
    fi
}

if command -v iwctl &> /dev/null
then

    wifi() {
        clear
        doas /usr/bin/ip link set dev wlan0 up
        # ! systemctl is-active --quiet iwd && doas systemctl enable --now --quiet iwd.service && notify-send "Wi-Fi Manager" "Turning Wi-Fi on" --icon=preferences-system-network
        doas /usr/bin/rfkill unblock wifi
        iwctl station wlan0 scan on
        clear
        local name=$(iwctl station wlan0 get-networks | sed -e "/Available networks/d" -e "/------/d" -e "s/^\x1b\[[0-9;]*m//" -e "/^\s*$/d" -e "s/^\s...//g" -e "s/^.....>.....\(.*\)/`printf "\x1B[1m\033[3m"`\1`printf "\033[0m"`/" | fzf --color='prompt:3,header:bold:underline:8' --no-preview --bind 'change:reload(iwctl station wlan0 get-networks | sed -e "/Available networks/d" -e "/------/d" -e "s/^\x1b\[[0-9;]*m//" -e "/^\s*$/d" -e "s/^\s...//g" -e "s/^.....>.....\(.*\)/`printf "\x1B[1m\033[3m"`\1`printf "\033[0m"`/")' --bind 'tab:reload(iwctl station wlan0 get-networks | sed -e "/Available networks/d" -e "/------/d" -e "s/^\x1b\[[0-9;]*m//" -e "/^\s*$/d" -e "s/^\s...//g" -e "s/^.....>.....\(.*\)/`printf "\x1B[1m\033[3m"`\1`printf "\033[0m"`/")' --nth='..-3' --inline-info --reverse --header-lines=1 --ansi --no-multi | grep --color=never -ozP "^.+?(?=\s{1,99}(psk|open))")
        if [[ -z ${name} ]]; then
            return 0
        fi
        iwctl station wlan0 connect "$name"
        wait
        /usr/lib/systemd/systemd-networkd-wait-online --ignore=lo --timeout=30 --interface=wlan0 --operational-state=dormant && notify-send "Wi-Fi Manager" --icon=preferences-system-network "Connected to $(iw dev wlan0 link | grep -oP '(?<=SSID: ).+')" && pkill -RTMIN+13 i3blocks
        iwctl station wlan0 scan off
    }

    wifipw() {
        before=$EPOCHREALTIME
        ! systemctl is-active --quiet iwd.service && echo "Wi-Fi service is not running" && return 1
        ssid="$(iw dev wlan0 link | grep --color=never -oP '(?<=SSID: ).+')"
        [ -z $ssid ] && echo "Not connected to a network" && return 1
        # requires /etc/sudoers to have the line: tb ALL=(ALL) NOPASSWD:/usr/bin/cat /var/lib/iwd/*
        doas /usr/bin/cat "/var/lib/iwd/"${ssid}.psk"" | grep --color=never -oP '(?<=Passphrase=)\w+' | tee /dev/tty | wl-copy -n
        after=$EPOCHREALTIME
        # if command took more than a second, print advice that you do not need password
        if (( after - before > 1 )); then
            print "Consider adding /usr/bin/cat to /etc/sudoers or /etc/doas.conf"
        fi

    }
fi
