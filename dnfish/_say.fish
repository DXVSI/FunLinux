function _say --description 'cowsay (fallback echo) with color modes'
    set -l msg "$argv[1]"
    set -l mode "$argv[2]"

    if type -q cowsay
        if test "$mode" = "dead"
            echo "$msg" | cowsay -d -n | _fancy error
        else if test "$mode" = "success"
            echo "$msg" | cowsay -n | _fancy success
        else if test "$mode" = "warning"
            echo "$msg" | cowsay -n | _fancy warning
        else if test "$mode" = "info"
            echo "$msg" | cowsay -n | _fancy info
        else if test "$mode" = "random"
            echo "$msg" | cowsay -n | _fancy random
        else
            echo "$msg" | cowsay -n | _fancy
        end
    else
        echo "$msg" | _fancy $mode
    end
end