# Make it easy to files for wayland session
if [[ ! -d "${HOME}/.grconfig" ]]; then
    export INSTALL_WAYLAND_CONFIG="git clone --depth=1 --bare https://github.com/trbjo/grconfig $HOME/.grconfig &&\
    git --git-dir=$HOME/.grconfig/ --work-tree=$HOME config --local core.bare false &&\
    git --git-dir=$HOME/.grconfig/ --work-tree=$HOME config --local core.worktree "$HOME" &&\
    git --git-dir=$HOME/.grconfig/ --work-tree=$HOME checkout &&\
    git --git-dir=$HOME/.grconfig/ --work-tree=$HOME remote set-url origin git@github.com:trbjo/grconfig.git &&\
    unset INSTALL_WAYLAND_CONFIG"
fi

[[ -d "${HOME}/.grconfig" ]] && alias grconfig='/usr/bin/git --git-dir=$HOME/.grconfig/ --work-tree=$HOME'

if [[ -n $SWAYSOCK ]]; then
    alias commit="git commit -v"
    alias swaymsg='noglob swaymsg'
    alias dvorak='swaymsg input "1:1:AT_Translated_Set_2_keyboard" xkb_layout us(dvorak)'
    alias qwerty='swaymsg input "1:1:AT_Translated_Set_2_keyboard" xkb_layout us'
fi

# this is meant to be bound to the same key as the terminal paste key
delete_active_selection() {
    if ((REGION_ACTIVE)) then
        if [[ $CURSOR -gt $MARK ]]; then
            BUFFER=$BUFFER[0,MARK]$BUFFER[CURSOR+1,-1]
            CURSOR=$MARK
        else
            BUFFER=$BUFFER[1,CURSOR]$BUFFER[MARK+1,-1]
        fi
        zle set-mark-command -n -1
    fi
}
zle -N delete_active_selection
bindkey "\ee" delete_active_selection

__colorpicker() {
    if [[ $#@ -lt 1 ]]
    then
        local colorcode=$(grim -g "$(env XCURSOR_SIZE=48 slurp -p )" -t ppm - | convert - -format "%[pixel:p{0,0}]" txt:- | awk 'FNR == 2 {print $2 " " $3}' | tr -d "\n" | tee /dev/tty | sed 's/.*#//') 2> /dev/null
        if [[ $colorcode ]]
        then
            perl -e 'foreach $a(@ARGV){print " \e[48:2::".join(":",unpack("C*",pack("H*",$a)))."m  \e[49m"; };print "\n"' "$colorcode"
            wl-copy -n $colorcode
        fi
    else
        perl -e 'foreach $a(@ARGV){print "\e[48:2::".join(":",unpack("C*",pack("H*",$a)))."m  \e[49m "}; print "\n"' "${@//\#/}"
    fi
}
alias ss='noglob __colorpicker'

if command -v iwctl &> /dev/null
then

    wifi() {
        set -o localoptions -o localtraps
        ! systemctl is-active --quiet iwd && doas /usr/bin/systemctl enable --now --quiet iwd.service && notify-send "Wi-Fi Manager" "Turning Wi-Fi on" --icon=preferences-system-network
        local iface
        if [[ -n "$1" ]] && [[ $1 == --iface=* ]]; then
            iface="${1##*=}"
            shift
        else
            iface=$(networkctl --json=short | jq -r '[.Interfaces.[] | select(.Type == "wlan")] | min_by(.Index) | .Name')
            [[ -z $iface ]] && print "no wlan interfaces found" && return 1
        fi

        if [[ -n "$@" ]]; then
            typeset -ag callback_args=($@)
            callbackfn() {
                $callback_args
                unset callback_args
            }
            trap callbackfn EXIT
        fi

        doas /usr/bin/ip link set dev $iface up || return 1
        doas /usr/bin/rfkill unblock wifi
        iwctl station $iface scan on 2>&1 1>/dev/null

        local evalstr="iwctl station $iface get-networks"
        evalstr+=' | tail -n +5 | \
            sed --regexp-extended \
                -e "s/^\x1b\[0m//g" \
                -e "s/\s*\x1b\[1;90m> \x1b\[[0-9;]*m  /✓│/" \
                -e "s/^\s+/ │/g" \
                -e "s/(\S+)\s*(\S+)\s*$/│\1│\2/g" | \
            column -s "│" -t --table-columns "✓,Network Name,Security,Signal" --output-separator " │ "'

        local name=$(\
            eval $evalstr | fzf --color='prompt:3,header:bold:underline:7' \
            --no-preview \
            --bind "change:reload(eval $evalstr)" \
            --bind "tab:reload(eval $evalstr)" \
            --nth='2' \
            --delimiter=" │ " \
            --inline-info \
            --reverse \
            --header-lines=1 \
            --ansi \
            --no-multi \
            | perl -pe 's/^.*? │ (.*?)│.*$/\1/' | xargs
            )
        iwctl station $iface scan off 2>&1 1>/dev/null
        [[ -n ${name} ]] || return 0
        iwctl station $iface disconnect
        iwctl station $iface connect "$name" && \
        /usr/lib/systemd/systemd-networkd-wait-online \
            --ignore=lo \
            --timeout=30 \
            --interface=$iface \
            --operational-state=dormant && \
        notify-send \
            "Wi-Fi Manager" \
            --icon=preferences-system-network \
            "Connected to $(networkctl --json=short | jq -r "[.Interfaces.[] | select(.Name == \"$iface\")] | min_by(.Index) | .SSID")"

    }


    wifipw() {
        local before=$EPOCHREALTIME
        ! systemctl is-active --quiet iwd.service && echo "Wi-Fi service is not running" && return 1

        ssid="$(iw dev $iface link | grep --color=never -oP '(?<=SSID: ).+')"
        [ -z $ssid ] && echo "Not connected to a network" && return 1

        # requires /etc/sudoers to have the line: tb ALL=(ALL) NOPASSWD:/usr/bin/cat /var/lib/iwd/*
        doas /usr/bin/cat "/var/lib/iwd/"${ssid}.psk"" | grep --color=never -oP '(?<=Passphrase=)\w+' | tee /dev/tty | wl-copy -n

        # if command took more than a second, print advice that you do not need password
        if (( $EPOCHREALTIME - before > 1 )); then
            print "Consider adding /usr/bin/cat to /etc/sudoers or /etc/doas.conf"
        fi

    }
fi
