ss() {
    if [[ $#@ -lt 1 ]]
    then
        colorcode=$(grim -g "$(env XCURSOR_SIZE=48 slurp -p )" -t ppm - | convert - -format "%[pixel:p{0,0}]" txt:- | awk 'FNR == 2 {print $2 " " $3}' | tr -d "\n" | tee /dev/tty | sed 's/.*#//') 2> /dev/null
        if [ $colorcode ]
        then
            perl -e 'foreach $a(@ARGV){print " \e[48:2::".join(":",unpack("C*",pack("H*",$a)))."m \e[49m"; print"\e[48:2::".join(":",unpack("C*",pack("H*",$a)))."m \e[49m "};print "\n"' "$colorcode"
            wl-copy -n $colorcode
        fi
    else
        perl -e 'foreach $a(@ARGV){print " \e[48:2::".join(":",unpack("C*",pack("H*",$a)))."m \e[49m"; print"\e[48:2::".join(":",unpack("C*",pack("H*",$a)))."m \e[49m "};print "\n"' "$@"
    fi
}

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

backward-delete-char() {
    if ((REGION_ACTIVE))
    then
        if [[ $CURSOR -gt $MARK ]]; then
            BUFFER=$BUFFER[0,MARK]$BUFFER[CURSOR+1,-1]
            CURSOR=$MARK
        else
            BUFFER=$BUFFER[1,CURSOR]$BUFFER[MARK+1,-1]
        fi
        zle set-mark-command -n -1
    else
        [ $BUFFER ] && zle .backward-delete-char || ([ $PopUp ] && swaymsg "[app_id=^PopUp$] scratchpad show; [app_id=^(subl|sublime_text|firefox)$ app_id=__focused__ workspace=^(3|2λ)$] fullscreen enable" > /dev/null) 2>&1
    fi
}
zle -N backward-delete-char
bindkey "^?" backward-delete-char

# copies the full path of a file for later mv
cpp() {
    if [[ ${#@} == 0 ]]; then
        pwd |& tee /dev/tty |& wl-copy -n
    else
        wl-copy -n -- $(realpath "${1}") && wl-paste
    fi
}

goto_sublime_current_dir() {
    [ $BUFFER ] && LBUFFER+=" " && return 0
    subl --command goto_sublime_current_dir
    read subldir </tmp/sublfile 2> /dev/null
    if [[ "${subldir}" == "${PWD}" ]]; then
        redraw-prompt
        zle reset-prompt
        return 0
    fi
    cd "$subldir" 2> /dev/null
    redraw-prompt
    zle reset-prompt
}
zle -N goto_sublime_current_dir
bindkey -e " " goto_sublime_current_dir


if command -v iwctl &> /dev/null
then

    wifi() {
        clear
        ! systemctl is-active --quiet iwd && sudo systemctl enable --now --quiet iwd.service && notify-send "Wi-Fi Manager" "Turning Wi-Fi on" --icon=preferences-system-network
        sudo /usr/bin/rfkill unblock wifi
        iwctl station wlan0 scan on
        clear
        local name=$(iwctl station wlan0 get-networks | sed -e "/Available networks/d" -e "/------/d" -e "s/^\x1b\[[0-9;]*m//" -e "/^\s*$/d" -e "s/^\s...//g" -e "s/^.....>.....\(.*\)/`printf "\x1B[1m\033[3m"`\1`printf "\033[0m"`/" | fzf --color='prompt:3,header:bold:underline:8' --no-preview --bind 'change:reload(iwctl station wlan0 get-networks | sed -e "/Available networks/d" -e "/------/d" -e "s/^\x1b\[[0-9;]*m//" -e "/^\s*$/d" -e "s/^\s...//g" -e "s/^.....>.....\(.*\)/`printf "\x1B[1m\033[3m"`\1`printf "\033[0m"`/")' --bind 'tab:reload(iwctl station wlan0 get-networks | sed -e "/Available networks/d" -e "/------/d" -e "s/^\x1b\[[0-9;]*m//" -e "/^\s*$/d" -e "s/^\s...//g" -e "s/^.....>.....\(.*\)/`printf "\x1B[1m\033[3m"`\1`printf "\033[0m"`/")' --inline-info --reverse --header-lines=1 --ansi --no-multi | sed -e 's/................$//' | xargs)
        iwctl station wlan0 scan off
        if [[ -z ${name} ]]; then
            return 0
        fi
        iwctl station wlan0 connect $name
        wait
        /usr/lib/systemd/systemd-networkd-wait-online --ignore=lo --timeout=30 --interface=wlan0 --operational-state=dormant && notify-send "Wi-Fi Manager" --icon=preferences-system-network "Connected to $(iw dev wlan0 link | grep -oP '(?<=SSID: ).+')" && pkill -RTMIN+13 i3blocks
    }

    wifipw() {
        ! systemctl is-active --quiet iwd.service && echo "Wi-Fi service is not running" && return 1
        ssid="$(iw dev wlan0 link | grep --color=never -oP '(?<=SSID: ).+')"
        [ -z $ssid ] && echo "Not connected to a network" && return 1
        # requires /etc/sudoers to have the line: tb ALL=(ALL) NOPASSWD:/usr/bin/cat /var/lib/iwd/*
        sudo /usr/bin/cat "/var/lib/iwd/"${ssid}.psk"" | grep --color=never -oP '(?<=Passphrase=)\w+' | tee /dev/tty | wl-copy -n
    }
fi
