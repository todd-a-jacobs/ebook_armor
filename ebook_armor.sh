#!/bin/bash
# vim: sw=4 et:

# Name:
#    ebook_armor.sh
# Version:
#    $Id$
# Purpose:
#     Ensure the long-term integrity of electronic books and guard
#     against bit-rot.
# Usage:
#    ebook_armor.sh [-h|-u|-d|-v]
# Options:
#    -h = show documentation
#    -u = show usage
#    -d = display environment variables
#    -v = show version
# Environment Variables
#    REDUNDANCY = % damamge each book can recover from
#    BOOK_DIR   = top-level directory for e-books
#    INDEX      = location of md5sums
#    CSV        = location of enhanced, tab-delimited index
#    REPAIR     = directory for storing par2 files
# Copyright:
#    Copyright 2010 by Todd A. Jacobs
#        <codegnome.consulting+ebook_armor -AT- gmail.com>
# License:
#    Released under the GNU General Public License (GPL)
#    http://www.gnu.org/copyleft/gpl.html
#
#    This program is free software; you can redistribute it and/or
#    modify it under the terms of the GNU General Public License as
#    published by the Free Software Foundation; either version 3 of the
#    License, or (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful, but
#    WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
#    General Public License for more details.

set -e
set -o pipefail

######################################################################
# Environment Variable Defaults
######################################################################
: "${REDUNDANCY:=10}"
: "${BOOK_DIR:=$HOME/Desktop/Ebooks}"
: "${INDEX=$BOOK_DIR/index.md5sum}"
: "${CSV=$BOOK_DIR/index.csv}"
: "${REPAIR=$BOOK_DIR/repair}"

######################################################################
# Functions
######################################################################
# Ensure that essential files are created.
init () {
    for file in "$INDEX" "$CSV"; do
        file=$(basename "$file")
        [[ -f "$file" ]] || touch "$file"
    done
    for dir in "$REPAIR"; do
        dir=$(basename "$dir")
        [[ -d "$dir" ]] || mkdir -p "$dir"
    done
}

# Display list of arguments and their values.
show_variables () {
    for var in $*; do
        echo -e "    $var:\t\t${!var}"
    done
}

# Show help stored at top of file.
show_help () {
    perl -ne 'if (/^# Name:/ .. /^$/) {
                  s/^# ?//;
                  s/^\S/\n$&/;
                  print;
              }' $0
    exit 2
}

show_usage () {
    perl -ne 's/^# ?// && print if /^# Usage:/ ... /^\S/' $0
    exit 2
}

show_version () {
    perl -ne 's/^# ?// && print if /^# (Version|Revision):/ ... /^\S/' $0
    exit 2
}

# Process command-line options. Returns number of positional parameters
# to shift away after calling this function.
#
# Example:
#     options "$@" || shift #?
options () {
    while getopts ':hudv' opt; do
	case $opt in
            d)  # Show environment variables.
                echo Environment Variables:
                show_variables REDUNDANCY BOOK_DIR INDEX CSV REPAIR
                exit 2
                ;;
	    h)  show_help
		;;
            v)  show_version
                ;;
	    \? | u) show_usage
		;;
	esac # End "case $opt"
    done # End "while getopts"

    # Return number of processed options caller should shift away.
    return $(($OPTIND - 1))
}

# Use index of md5sums to identify duplicate books.
check_for_duplicates () {
    local duplicates=$(sort < "$INDEX" | uniq -d)
    if [[ -n $duplicates ]]; then
        echo 'Duplicates found:'
        echo $duplicates | uniq | sed 's/^/    /'
        return 1
    fi
}

# Validate par2 files and the current integrity of a book. This function
# does double-duty: an additonal validity check, as well as making sure
# that the par2 data will work when it's needed.
verify_parity () {
    echo -n "Verifying  $book is recoverable ... "
    pushd $REPAIR 2>&1 > /dev/null
    par2verify -qq "$book"
    local return_value=$?
    popd 2>&1 > /dev/null
    return $return_value
}

# Create par2 data for a book. Stores the data in the REPAIR directory,
# along with a symlink to the original book file. No symlink, no
# par2verify from a different directory. :/
make_repairable () {
    [[ -d $REPAIR ]] || mkdir -p $REPAIR
    echo "Protecting $book ..."
    par2create -qq -u -r${REDUNDANCY} "$book" &&
        mv --backup=numbered *par2 $REPAIR/
    ln -s "$PWD/$book" $REPAIR/
    if verify_parity; then
        echo yes.
    else
        echo no.
        false
    fi
}

# Validate book using MD5 returned by filename lookup in INDEX.
#
# Currently does not handle duplicate titles in the INDEX, which might
# happen if books with identical filenames but different md5sums are
# cataloged.
verify_book () {
    echo "Verifying $book ..."
    md5sum -c < <(fgrep "$book" $INDEX)
}

# If book is a zip archive, we get another integrity check almost for
# free. Since EPUB books are technically zip archives too, they're
# checked here as well.
verify_zipfile () {
    if file --brief "$book" | egrep -q '^Zip'; then
        echo "ZIP check  $book ... "
        unzip -qqt "$book"
    fi
}

# Handle indexing and validation.
#
# - pushd/popd are very chatty, but are necessary in the event that
# functions called here make addition changes to the current working
# directory, as OLDPWD will get lost along the way.
# - Make sure to skip regular files in BOOK_DIR, as well as the REPAIR
# directory, when indexing or traversing the tree. This obviously
# assumes that no books are ever stored in the top-level of BOOK_DIR.
main () {
    for dir in *; do
        [[ -d $dir ]] || continue
        [[ $dir == $(basename $REPAIR) ]] && continue
        pushd "$dir" 2>&1 > /dev/null
        for book in *; do
            [[ ! -f "$book" ]] && continue
            if ! fgrep -q "$book" $INDEX; then
                echo "Cataloging $book ..."
                verify_zipfile
                md5sum "$book" >> $INDEX
                printf "%s\t%s\n" \
                    "$(date +%F)" \
                    "$(tail -n1 $INDEX)" \
                    >> $CSV
                make_repairable
            else
                verify_book
            fi
            echo
        done
        popd 2>&1 > /dev/null
    done
}

######################################################################
# Main
######################################################################
init
options "$@" || shift #?
main
check_for_duplicates
