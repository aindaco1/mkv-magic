#!/usr/local/bin/bash

cd ~/Desktop/Movies

# Language map for mkvmerge (ALL CAPS language names ONLY)
declare -A lang_map=(
    [AFAR]="aa" [ABKHAZIAN]="ab" [AFRIKAANS]="af" [AKAN]="ak" [ALBANIAN]="sq" [AMHARIC]="am" [ARABIC]="ar"
    [ARMENIAN]="hy" [ASSAMESE]="as" [AYMARA]="ay" [AZERBAIJANI]="az" [BASHKIR]="ba" [BASQUE]="eu" [BELARUSIAN]="be"
    [BENGALI]="bn" [BIHARI]="bh" [BISLAMA]="bi" [BOSNIAN]="bs" [BRETON]="br" [BULGARIAN]="bg" [BURMESE]="my"
    [CATALAN]="ca" [CHAMORRO]="ch" [CHECHEN]="ce" [CHICHEWA]="ny" [CHINESE]="zh" [CORNISH]="kw"
    [CORSICAN]="co" [CREE]="cr" [CROATIAN]="hr" [CZECH]="cs" [DANISH]="da" [DIVEHI]="dv" [DUTCH]="nl"
    [DZONGKHA]="dz" [ENGLISH]="en" [ESPERANTO]="eo" [ESTONIAN]="et" [EWE]="ee" [FAROESE]="fo" [FIJIAN]="fj"
    [FINNISH]="fi" [FRENCH]="fr" [FRISIAN]="fy" [FULAH]="ff" [GALICIAN]="gl" [GEORGIAN]="ka" [GERMAN]="de"
    [GREEK]="el" [GREENLANDIC]="kl" [GUARANI]="gn" [GUJARATI]="gu" [HAITIAN]="ht" [HAUSA]="ha" [HEBREW]="he"
    [HERERO]="hz" [HINDI]="hi" [HMONG]="hmn" [HUNGARIAN]="hu" [ICELANDIC]="is" [IGBO]="ig" [INDONESIAN]="id"
    [INTERLINGUA]="ia" [INTERLINGUE]="ie" [INUKTITUT]="iu" [INUPIAK]="ik" [IRISH]="ga" [ITALIAN]="it"
    [JAPANESE]="ja" [JAVANESE]="jv" [KANNADA]="kn" [KASHMIRI]="ks" [KAZAKH]="kk" [KHMER]="km" [KIKUYU]="ki"
    [KINYARWANDA]="rw" [KIRGHIZ]="ky" [KOMI]="kv" [KONGO]="kg" [KOREAN]="ko" [KURDISH]="ku" [LAO]="lo"
    [LATIN]="la" [LATVIAN]="lv" [LIMBURGISH]="li" [LINGALA]="ln" [LITHUANIAN]="lt" [LUXEMBOURGISH]="lb"
    [MACEDONIAN]="mk" [MALAGASY]="mg" [MALAY]="ms" [MALAYALAM]="ml" [MALTESE]="mt" [MANX]="gv" [MAORI]="mi"
    [MARATHI]="mr" [MARSHALLESE]="mh" [MONGOLIAN]="mn" [NAURU]="na" [NAVAJO]="nv" [NDONGA]="ng" [NEPALI]="ne"
    [NORWEGIAN]="no" [NORWEGIAN_BOKMAL]="nb" [NORWEGIAN_NYNORSK]="nn" [OCCITAN]="oc" [ORIYA]="or" [OROMO]="om"
    [OSSETIAN]="os" [PALI]="pi" [PASHTO]="ps" [PERSIAN]="fa" [POLISH]="pl" [PORTUGUESE]="pt" [PUNJABI]="pa"
    [QUECHUA]="qu" [ROMANIAN]="ro" [ROMANSH]="rm" [RUNDI]="rn" [RUSSIAN]="ru" [SAMOAN]="sm" [SANGO]="sg"
    [SANSKRIT]="sa" [SCOTS_GAELIC]="gd" [SERBIAN]="sr" [SERBOCROATIAN]="sh" [SESOTHO]="st" [SETSWANA]="tn"
    [SHONA]="sn" [SINDHI]="sd" [SINHALA]="si" [SLOVAK]="sk" [SLOVENIAN]="sl" [SOMALI]="so" [SPANISH]="es"
    [SUNDANESE]="su" [SWAHILI]="sw" [SWATI]="ss" [SWEDISH]="sv" [TAGALOG]="tl" [TAHITIAN]="ty" [TAJIK]="tg"
    [TAMIL]="ta" [TATAR]="tt" [TELUGU]="te" [THAI]="th" [TIBETAN]="bo" [TIGRINYA]="ti" [TONGA]="to" [TSONGA]="ts"
    [TURKISH]="tr" [TURKMEN]="tk" [TWI]="tw" [UKRAINIAN]="uk" [URDU]="ur" [UZBEK]="uz" [VIETNAMESE]="vi"
    [VOLAPUK]="vo" [WALLOON]="wa" [WELSH]="cy" [WOLOF]="wo" [XHOSA]="xh" [YIDDISH]="yi" [YORUBA]="yo"
    [ZHUANG]="za" [ZULU]="zu" [FILIPINO]="tl" [FLEMISH]="nl" [BASAA]="bas" [HAWAIIAN]="haw" [KINYAMBO]="nyo"
    [PASHTO]="ps" [CANTONESE]="yue" [MANDARIN]="cmn" [MIN_NAN]="nan" [HOKKIEN]="nan" [BURMESE]="my"
    [MONTENEGRIN]="cnr" [ESTONIAN]="et" [LATVIAN]="lv" [LITHUANIAN]="lt"
)
lang_keys=($(printf "%s\n" "${!lang_map[@]}" | awk '{ print length, $0 }' | sort -rn | cut -d" " -f2-))

move_to_trash() {
    local target="$1"
    local abspath
    abspath="$(cd "$(dirname "$target")"; pwd)/$(basename "$target")"
    echo "Moving to Trash: $abspath"
    osascript -e "tell application \"Finder\" to move (POSIX file \"$abspath\") to trash" >/dev/null 2>&1
}

hide_extension() {
    osascript -e "tell application \"Finder\" to set extension hidden of (POSIX file \"$1\") to true" >/dev/null 2>&1
}

prettify_filename() {
    local filename="$1"
    local name="${filename%.*}"

    # Replace _ and . with spaces
    name="${name//_/ }"
    name="${name//./ }"

    # Find the last year in the name
    # Use awk to get everything before and including the last year
    prettified=$(echo "$name" | awk '
        {
            for(i=NF;i>0;i--) {
                if ($i ~ /^[12][09][0-9]{2}$/) {
                    for(j=1;j<=i;j++) {
                        printf "%s ", $j
                    }
                    printf "\n"
                    exit
                }
            }
        }
    ')

    prettified="${prettified%"${prettified##*[![:space:]]}"}"  # Trim trailing whitespace

    # Now split off the title and year
    if [[ "$prettified" =~ ^(.+)\ ([12][09][0-9]{2})$ ]]; then
        local title="${BASH_REMATCH[1]}"
        local year="${BASH_REMATCH[2]}"
        # Clean up extra spaces
        title="$(echo "$title" | sed 's/^[ \t]*//;s/[ \t]*$//;s/  */ /g')"

        # Apply proper casing with exceptions
        exceptions="a an and as at in of on or the to vs"
        read -ra words <<< "$title"
        for i in "${!words[@]}"; do
            word="${words[$i]}"
            lower=$(echo "$word" | tr '[:upper:]' '[:lower:]')
            if [[ $i -eq 0 || $i -eq $((${#words[@]}-1)) ]]; then
                words[$i]="$(tr '[:lower:]' '[:upper:]' <<< "${word:0:1}")${word:1}"
            elif [[ " $exceptions " =~ " $lower " ]]; then
                words[$i]="$lower"
            else
                words[$i]="$(tr '[:lower:]' '[:upper:]' <<< "${word:0:1}")${word:1}"
            fi
        done
        title="$(IFS=" "; echo "${words[*]}")"
        echo "$title ($year).mkv"
    else
        # Fallback
        echo "$name.mkv"
    fi
}

shopt -s nullglob
for mp4 in *.mp4; do
    base="${mp4%.mp4}"
    shrtvid="${mp4:0:20}"
    mkvout="${base}.mkv"

    # Find audio language from filename (default: eng)
    lang="eng"
    mp4_upper=$(echo "$mp4" | tr '[:lower:]' '[:upper:]')
    for key in "${lang_keys[@]}"; do
        if [[ "$mp4_upper" =~ (^|[^A-Z])${key}([^A-Z]|$) ]]; then
            lang="${lang_map[$key]}"
            break
        fi
    done

    # Detect if audio/video present
    has_audio=$(mkvmerge -i "$mp4" | grep -i 'audio')
    has_video=$(mkvmerge -i "$mp4" | grep -i 'video')

    args=(--output "$mkvout" --title "" --no-global-tags --no-attachments)
    if [[ -n "$has_video" ]]; then
        args+=(--track-name 0:"")
    fi
    if [[ -n "$has_audio" ]]; then
        args+=(--language 1:"$lang" --track-name 1:"")
    fi
    args+=("$mp4")

    # Subtitle tracks (.srt)
    srt_to_trash=()
    for srt in *.srt; do
        basesrt="${srt%.srt}"
        shrtsrt="${srt:0:20}"
        if [[ "$shrtsrt" == "$shrtvid" ]]; then
            sl="eng"
            srt_upper=$(echo "$srt" | tr '[:lower:]' '[:upper:]')
            for key in "${lang_keys[@]}"; do
                if [[ "$srt_upper" =~ (^|[^A-Z])${key}([^A-Z]|$) ]]; then
                    sl="${lang_map[$key]}"
                    break
                fi
            done
            if [[ "$srt" == *"FORCED"* ]]; then
                args+=(--language 0:"$sl" --track-name 0:"Forced" --forced-track 0:yes "$srt")
            else
                args+=(--language 0:"$sl" --track-name 0:"" "$srt")
            fi
            srt_to_trash+=("$srt")
        fi
    done

    echo "Running mkvmerge ${args[*]}"
        if ! mkvmerge "${args[@]}"; then
            echo "❌ mkvmerge failed for: $mp4"
            echo "Skipping file cleanup for this entry to avoid data loss."
            continue
        fi

    # Move source files to Trash
    echo "Moving $mp4 to Trash"
    move_to_trash "$mp4"
    for srt in "${srt_to_trash[@]}"; do
        echo "Moving $srt to Trash"
        move_to_trash "$srt"
    done

    # Prettify and rename the mkv
    newname=$(prettify_filename "$mkvout")
    if [[ "$newname" != "$mkvout" ]]; then
        mv -v "$mkvout" "$newname"
        mkvout="$newname"
    fi

    # Hide extension
    hide_extension "$mkvout"
    echo "Created and cleaned: $mkvout"
done