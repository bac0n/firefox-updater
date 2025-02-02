#!/bin/bash

# depends: bash >= 5.2
benchmark(){
     local -i a="${EPOCHREALTIME/.}-${EPOCHSTARTTIME/.}"
     local    b
    printf -v b %07d "$a" && printf %s "${b/%??????/.&}"
}

EPOCHSTARTTIME=$EPOCHREALTIME

# Load builtin module,
if ! enable -f versioninfo versioninfo; then
    echo "Failed to enable loadable module versioninfo."
    exit 1
fi

# Display help summary.
help versioninfo

printf '\n\e[0;34mtest with `-a` flag and write protect array named protected.\e[m\n'
readonly -a protected && { \
    versioninfo -a protected; declare -p protected; \
} || echo "can't write protect array named `protected`."

printf '\n\e[0;34mtest without flags.\e[m\n'
versioninfo; declare -p VERSIONINFO

printf '\n\e[0;34mtest with `-a` flag.\e[m\n'
versioninfo -a array; declare -p array

printf '\n\e[0;34mtest with `-v` flag.\e[m\n'
versioninfo -v; declare -p VERSIONINFO

printf '\n\e[0;34mtest with `-v`, `-a` flags.\e[m\n'
versioninfo -v -a array; declare -p array

printf '\n\e[0;34mtest with `-va` flags combined.\e[m\n'
versioninfo -v -a array; declare -p array

printf '\n\e[0;34mtest exit status code without flags.\e[m\n'
versioninfo && \
    declare -p VERSIONINFO || echo 'Failed to exec versioninfo.'

printf '\n\e[0;34mtest exit status code with `-v` flag.\e[m\n'
versioninfo -v && \
    declare -p VERSIONINFO || echo 'Failed to exec versioninfo.'

printf '\n\e[0;34mtest exit status code with both `-v`, `-a` flags.\e[m\n'
versioninfo -v -a array && \
    declare -p array  || echo 'Failed to exec versioninfo.'

printf '\n\e[0;34mtest setting VERSIONINFO to readonly.\e[m\n'
readonly VERSIONINFO && { \
    versioninfo; declare -p VERSIONINFO; \
} || echo "can't write protect array named `VERSIONINFO`."

printf '\nBenchmark (%ss).\n' $(benchmark)
