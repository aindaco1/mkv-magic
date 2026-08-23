#!/usr/bin/env bash
cd ~/Desktop/Movies
declare -a args
for mkv in *.mkv
do
    base="${mkv%mkv}"
    shrtvid="${mkv::30}"
    args=(-o "1${base}mkv" "${mkv}")
    for idx in *.idx
        do
            baseidx="${idx%idx}"
            shrtidx="${idx::30}"
            if [[ "${shrtidx}" == "${shrtvid}" ]]
            then args=("${args[@]}" --language 0:eng "${baseidx}idx")
            fi
        done
    for m4a in *.m4a
        do
            basem4a="${m4a%m4a}"
            shrtm4a="${m4a::30}"
            if [[ "${shrtm4a}" == "${shrtvid}" ]]
            then args=("${args[@]}" --language 0:eng "${basem4a}m4a")
            fi
        done
    echo "${args[@]}"
    /usr/local/Cellar/mkvtoolnix/87.0/bin/mkvmerge "${args[@]}"
done