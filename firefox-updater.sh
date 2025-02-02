#!/bin/bash

# shellcheck disable=SC2317
# dependencies:
# bash >= 5.2, versioninfo, ln, updater, wget, shasum

benchmark(){
     local -i a="${EPOCHREALTIME/.}-${EPOCHSTARTTIME/.}"
     local    b
    printf -v b %07d "$a" && printf %s "${b/%??????/.&}"
}

EPOCHSTARTTIME=$EPOCHREALTIME
  set -e
shopt -s extglob nullglob failglob

declare -a o=()
declare -A A=()

if ! [[ -d /opt/unpack && -w /opt/unpack ]]; then
    echo "Directory '/opt/unpack´ is missing or not enough permission."
    exit 1
fi

# Backup check log.
[[ -r /opt/unpack/check.ini ]] && \
printf '%s\n' "$(< /opt/unpack/check.ini)" > /opt/unpack/check.ini~

# clear check log.
printf '# Created: %(%F %T)T\n%s\n' -1 "#" > /opt/unpack/check.ini

# Write array state to log file.
write_state(){
    local -n __a__=$1
    eval "printf '[%s] = %s\n' ${__a__[*]@K}" >> /opt/unpack/check.ini
}

log(){
    case "$1" in
        0)
        printf '[ \e[0;32mOK\e[0m ] %s\n' "${*:2}" ;;
        *)
        printf '[ \e[0;31m!!\e[0m ] %s\n' "${*:2}" ;;
    esac
    if (($1 != 0)); then
        write_state A; exit "$1"
    fi
}

# Save this in case it's needed.
# toolkit/modules/tests/xpcshell/test_UpdateUtils_url.js (line: ~200)
percent_encoding(){
    local -n __s__=$2
    local i c r="[[:alnum:].!~*'()_-]"
    for ((i=0; i<${#1}; i++)); do
        [[ ${1:i:1} =~ $r ]] && \
            c=${1:i:1} || printf -v c %%%02X "'${1:i:1}" ; __s__+=$c
    done
}

# Parse and Decode xml
# shellcheck disable=SC2154,SC2004
parse_update_xml(){
    local -n __a__=$1
    local -A B entities=( \
        ['&amp;']='&' ['&lt;']='<' ['&gt;']='>' ['&quot;']='"' ['&apos;']="'" \
    )
    local m0=/ m1 m2 m3 m4 n1 n2 n3 x route entity \
          attr='([^\ =]+)=\"([^\"]+)\"(.*)$' \
          elem='(</?([^?/>!\ ]+)\ ?([^>]+)?>)(.*)$'

    m4=$(< /opt/unpack/update.xml)

    while [[ $m4 =~ $elem ]]; do
        m1=${BASH_REMATCH[1]} m2=${BASH_REMATCH[2]} \
        m3=${BASH_REMATCH[3]} m4=${BASH_REMATCH[4]}
        case $m0 in
            "${m1:1:1}") ;&
            "${m1:(-2):1}") route=${route%/"$m2"} ;;&
            "${m1:1:1}") continue ;;
        esac
        route=$route/$m2
        n3=$m3
        while [[ $n3 =~ $attr ]]; do
            n1=${BASH_REMATCH[1]} \
            n2=${BASH_REMATCH[2]} n3=${BASH_REMATCH[3]}
            for entity in "${!entities[@]}"; do
                n2=${n2//"$entity"/"${entities[$entity]}"}
            done
            [[ $route =~ (/update|/patch) ]] && B[$n1]=$n2
        done
        if [[ ${B[type]} = @(minor|complete) ]]; then
            for x in "${!B[@]}"; do __a__[UpdateXML,$x]=${B[$x]}; done
        fi
    done
}

# format: A[section,key]=value.
# shellcheck disable=SC2178,SC2004
parse_application_ini() {
    local -n __a__=$1
    local s i
    mapfile -t < /usr/lib/firefox/application.ini
    for i in "${MAPFILE[@]}"; do
        case "$i" in
            \[*\]) s=${i:1:(-1)}
                   ;;
         [^\[\;]*) __a__[$s,${i%%=*}]=${i#*=}
                   ;;
        esac
    done
}

log 0 "Import application.ini and channel-prefs.js files .."

parse_application_ini A

# Only parse app.update.channel pref for now.
regex='pref\("(app.update.channel)", +"([^"]+)"\);.*$'
[[ $(< /etc/firefox/defaults/pref/channel-prefs.js) =~ $regex ]] && A[Pref,${BASH_REMATCH[1]}]=${BASH_REMATCH[2]}

log 0 "Parse kernel os properties from /proc .."

# Kernel information.
read -r 'A[Capabilities,osType]' _ 'A[Capabilities,osRelease]' _ < /proc/version

log 0 "versioninfo: read version form shared libraries .."

# Enable loadable module.
enable -f versioninfo versioninfo || log $? "Unable to load builtin module .."

versioninfo && \
    A[Capabilities,GtkVersion]=${VERSIONINFO[0]} \
    A[Capabilities,libPulseVersion]=${VERSIONINFO[1]} || log $? "Unable to read version info .."

log 0 "Check Streaming SIMD Extension set .."

# SIMD Extension set.
data=$(< /proc/cpuinfo) flags=() regex=$'flags\t+: ([^\n]+)(.*)$'
while [[ $data =~ $regex ]]; do
    flags+=("${BASH_REMATCH[1]}") data=${BASH_REMATCH[2]}
done

for simd in sse4_2 sse4_1 sse4a ssse3 sse3 sse2 sse mmx neon armv7 armv6; do
    if [[ " ${flags[*]} " = *\ $simd\ * ]]; then
        A[Capabilities,SimdFlag]=${simd^^}
        break
    fi
done

log 0 "Get total memory in MB .."

# Total memory MB.
# shellcheck disable=SC2015
read -r _ meminfo _ < /proc/meminfo && \
    ((A[Capabilities,MemInfo] = meminfo / 1024)) || log $? "Failed to read /proc meminfo .."

log 0 "Populate associative URL %component% .."

# Populate associative %component%.
[[ -v A[AppUpdate,URL] ]] || log 1 "AppUpdate URL missing .."

u=${A[AppUpdate,URL]}
IFS=/
for component in $u; do
    case $component in
        %PRODUCT%)
            u=${u//%PRODUCT%/"${A[App,Name]:?}"} ;;
        %VERSION%)
            u=${u//%VERSION%/"${A[App,Version]:?}"} ;;
        %BUILD_ID%)
            u=${u//%BUILD_ID%/"${A[App,BuildID]:?}"} ;;
        %BUILD_TARGET%)
            u=${u//%BUILD_TARGET%/"Linux_x86_64-gcc3"} ;;
        %LOCALE%)
            u=${u//%LOCALE%/"en-US"} ;;
        %CHANNEL%)
            u=${u//%CHANNEL%/"${A[Pref,app.update.channel]:?}"} ;;
        %OS_VERSION%)
            u=${u//%OS_VERSION%/"${A[Capabilities,osType]:?}%2520${A[Capabilities,osRelease]:?}%2520(GTK%2520${A[Capabilities,GtkVersion]:?}%252Clibpulse%2520${A[Capabilities,libPulseVersion]:?})"} ;;
        %SYSTEM_CAPABILITIES%)
            u=${u//%SYSTEM_CAPABILITIES%/"ISET%3A${A[Capabilities,SimdFlag]:?}%2CMEM%3A${A[Capabilities,MemInfo]:?}"} ;;
        %DISTRIBUTION%)
            u=${u//%DISTRIBUTION%/"default"} ;;
        %DISTRIBUTION_VERSION%)
            u=${u//%DISTRIBUTION_VERSION%/"default"} ;;
        %+([_A-Z])%)
            log 1 "Error: '$component´, unknown %component% .." ;;
    esac
done
IFS=$' \t\n'
A[AppUpdate,xmlURL]="$u?force=1"

log 0 "Wget: ${A[AppUpdate,xmlURL]}"

# Benchmark first stage.
printf '\nFirst stage successful! (%ss)..\n\n' "$(benchmark)"

log 0 "Download update.xml file .."

# Fetch update.xml
o=( \
    --quiet \
    --level=1 \
    --no-directories \
    --content-disposition \
    --trust-server-names \
    --backups=0 \
)

command wget "${o[@]}" \
    -O /opt/unpack/update.xml "${A[AppUpdate,xmlURL]}" || log $? "wget: failed fetching update.xml file .."

log 0 "Parse update.xml file .."

parse_update_xml A

[[ -v A[UpdateXML,URL] ]] || log 1 "UpdateXML URL missing .."

log 0 "Wget: ${A[UpdateXML,URL]}"
log 0 "Download *.${A[UpdateXML,type]}.mar file (${A[UpdateXML,displayVersion]}) .."

work_path=/opt/unpack
work_path+=/${A[UpdateXML,type]}
work_path+=/${A[UpdateXML,appVersion]}
work_path+=/${A[UpdateXML,buildID]}

command wget "${o[@]}" \
    -P "$work_path" "${A[UpdateXML,URL]}" || log $? "Wget: failed fetching UpdateXML URL .."

[[ ${A[UpdateXML,hashFunction]} = @(sha256|sha384|sha512) ]] || log 1 "Hash function not recogized .."

log 0 "Save and check SHA checksum .."

# Just one file, thank you.
x=0
for i in "$work_path"/*.mar; do
    ((x++)) \
        && log 1 "To many *.mar files detected.."; A[Updater,file]=$i
done

printf '%s  %s\n' \
    "${A[UpdateXML,hashValue]}" "${A[Updater,file]##*/}" > "${A[Updater,file]}.${A[UpdateXML,hashFunction]}"

# shellcheck disable=SC2015
( \
    builtin cd "$work_path"; \
    command shasum -a "${A[UpdateXML,hashFunction]/#sha}" -s -c "${A[Updater,file]}.${A[UpdateXML,hashFunction]}" \
) && \
    command ln -rfs "${A[Updater,file]}" /opt/unpack/update.mar || \
        log $? "${A[UpdateXML,hashFunction]}: update.mar checksum mismatch .."

log 0 "Updater file: ${A[Updater,file]} .."

command /usr/lib/firefox/updater \
        /opt/unpack/ \
        /usr/lib/firefox/ /usr/lib/firefox/ || log $? "Fail to update firefox .."

# Re-parse application.ini and compare with update.xml.
parse_application_ini A

[[ ${A[App,BuildID]} = "${A[UpdateXML,buildID]}" ]] || \
    log 1 "BuildID mismatch (${A[App,BuildID]} != ${A[UpdateXML,buildID]}) .."

# Write A[@] array state to check.ini.
write_state A

printf '[ ** ] \e[0;35mNew Firefox Version: %s (%ss)\e[0m\n' "${A[UpdateXML,displayVersion]}" "$(benchmark)"
