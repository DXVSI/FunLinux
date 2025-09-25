function _think --description 'cowthink (fallback echo) with color modes'
    set -l msg "$argv[1]"
    set -l mode "$argv[2]"

    if type -q cowthink
        if test "$mode" = "dead"
            echo "$msg" | cowthink -d -n | _fancy error
        else if test "$mode" = "warning"
            echo "$msg" | cowthink -n | _fancy warning
        else if test "$mode" = "info"
            echo "$msg" | cowthink -n | _fancy info
        else
            # По умолчанию думающая корова жёлто-оранжевая
            echo "$msg" | cowthink -n | _fancy think
        end
    else
        echo "$msg" | _fancy $mode
    end
end
