#!/bin/sh
set -e
set -u

INPUT_FILE="docker-compose.yml"
OUTPUT_FILE=".env"

: > "$OUTPUT_FILE"

seen=""

while IFS= read -r line; do
    remainder="$line"
    while :; do
        case "$remainder" in
            *'${'*':-'*'}'*)
                inner="${remainder#*\$\{}"
                inner="${inner%%\}*}"
                key="${inner%%:-*}"
                value="${inner#*:-}"

                # Check if key has already been seen
                case "$seen" in
                    *"|${key}|"*)
                        ;;
                    *)
                        echo "${key}=${value}" >> "$OUTPUT_FILE"
                        seen="${seen}|${key}|"
                        ;;
                esac

                remainder="${remainder#*\$\{${inner}\}}"
                ;;
            *)
                break
                ;;
        esac
    done
done < "$INPUT_FILE"

echo ".env file generated"
