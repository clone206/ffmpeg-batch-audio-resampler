#!/bin/bash

#  Copyright 2018 Kevin Witmer
# 
#  This program is free software: you can redistribute it and/or modify
#  it under the terms of the GNU Lesser General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
# 
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU Lesser General Public License for more details.
# 
#  You should have received a copy of the GNU Lesser General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.

if [[ -z "$1" || "$1" == "-h" ]]
then
    echo ""
    echo "usage: "$(basename $0)" <file_name|glob>"
    echo ""
    echo "examples: "
    echo $(basename $0)" *.flac"
    echo $(basename $0)" test.aiff"
    echo ""
    echo "Takes either a single file name or a wildcard expression (glob)"
    echo "and reports the max peak level in dB any corresponding files, "
    echo "along with the highest found out of all files analyzed."
    echo ""
	exit 1
fi

glob=
highest=-32766  # Keep track of highest peak level found (start low)
db=$highest     # For storing the peak level found on each iteration

echo ""
echo "Peak Levels:"
echo ""

# Loop through all files of the given extension
for item in "$@"
do 
    # Find the peak db from the parsed output of ffmpeg's volumedetect filter
    db=$(ffmpeg -i "$item" -af volumedetect -map 0:a -f null /dev/null 2>&1 >/dev/null | awk '/max_volume/ {print $5}')

    # Update highest peak level found
    if (( $(echo "$db > $highest" | bc -l) ))
    then
        highest=$db
    fi

    # Print peak found for this file
    printf "%-70s %sdB\n" "$item:" "$db"
done

# Print highest peak found
printf "\n%-70s %sdB\n\n" "Highest peak level of all the files:" "$highest"

exit 0
