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


########################
# CONSTANTS
########################
# The requested output sample rate.
MAX_SR=$1
# The specified output file extension
OUTFILE_EXT=$2
# The specified volume boost for output file
VOL_BOOST=$3
# Don't go below this sample rate:
MIN_SR=44100
# The directory to output converted files to. Use trailing slash. Needs manual escaping (not quotes)
# if this is customized and there are special chars (spaces, etc) in the pathname supplied, eg: 
# OUT_DIR=~/Music/iTunes/iTunes\ Media/Automatically\ Add\ to\ iTunes.localized/
OUT_DIR=~/batch_resampled/

########################
# UTILITY FUNCTIONS
########################
# Send string to stderr
err() {
    >&2 echo "$1"
}

# Display usage info
print_usage() {
    err ""
    err "USAGE: "$(basename $0)" <sample_rate> <outfile_extension> [vol_adjust_db]"
    err ""
    err "Converts all supported audio files in the current directory to the format corresponding "
    err "to the given file extension (don't include the dot), at the speciied sample rate (in Hz). "
    err "To specify a maximum output sample rate, where any input file of a greater rate gets downsampled "
    err "to the nearest even multiple of either 44100 or 48000, add an 'm' to the end of the number, "
    err "eg. '96000m'. If an input file has a sample rate that is already below this, it will not be upsampled. "
    err ""
    err "An optional volume adjust (in dB) can be given (positive number for boost, "
    err "negative for cut). "
    err ""
    err "Renames file basenames on conversion and doesn't re-convert already "
    err "converted files on subsequent runs."
    err ""
    err "Supported infile types: flac,dsf,dff,wav,aiff,m4a,mp3"
    err "Supported outfile types: flac,wav,aiff,m4a(alac),mp3"
    err ""
}

########################
# ARGS CHECKING
########################
if [[ -z "$OUTFILE_EXT" || $OUTFILE_EXT == "dsf" || $OUTFILE_EXT == "dff" ]]
then
    print_usage
    exit 1
fi

########################
# GLOBALS
########################
# Added to the end of the file basename
suffix=""
# Args to pass to the resampler
filter_args=""
pre_filter_args=""
# Args for the output file, like codec
out_args=""
# Volume filter level. Setting to 0dB explicitly seems to prevent replaygain-related clipping.
# Also comes in handy for boosting DSD file levels on conversion to PCM.
vol_level=""
# The sample rate of each input file
infile_sr=""
# The sample format of each input file
infile_sfmt=""
# Output file name
output_file=""
# Level of any errors encountered.
error_level=0
# Lowest factor of input file
lowest_factor=0
# Destination sample rate of a given output file
dest_sr=$MAX_SR

########################
# FUNCTIONS
########################
# Recalculate sample rate to nearest even multiple
# of 44.1/48K, depending on the input file's sample rate and the max sample rate given
recalc_sr() {
    infile_sr=$1
    lowest_factor=$2
    max_sr=$(echo $MAX_SR | sed 's/m$//')
    dest_sr=0

    # Make sure our output sample rate is a multiple of either 44.1K or 48K
    if [[ ! $(($max_sr % 44100)) -eq 0 && ! $(($max_sr % 48000)) -eq 0 ]]
    then
        err "ERROR: Only even multiples of 44100 and 48000 are allowed to be specified for maximum output sample rates!"
        return 2
    fi

    # If the input is already at or below the specified max...
    if [[ $infile_sr -le $max_sr ]]
    then
        # Nothing to calculate. Keep sr the same
        dest_sr=$infile_sr

        err "INFO: Input sample rate <= output rate. Will not be upsampled."
        echo "$dest_sr"
        return 0
    # If user specified the min sr as the max
    elif [[ $max_sr -eq $MIN_SR ]]
    then
        # Downsample even if not even multiple
        dest_sr=$max_sr

        err "INFO: No even multiple available below minimum rate of ${MIN_SR}, so downsampling to ${MIN_SR}."
        echo "$dest_sr"
        return 0
    else
        # Find closest even multiple below the max. Takes advantage of the dropping of decimals by bash for easy math.
        dest_sr=$(( ($max_sr/$lowest_factor)*$lowest_factor ))

        err "INFO: Downsampling to even multiple of ${lowest_factor}"
        echo "$dest_sr"
        return 0
    fi
}

# Takes input file sample rate as the only param.
# Determines whether this is an even multiple or 44.1K or 48K
# Delegates to the recalc_sr function and passes through the results via echo's
find_lowest_factor() {
    infile_sr=$1

    if [[ $infile_sr && $(($infile_sr % 44100)) -eq 0 ]]
    then
        echo "44100"
        return 0
    elif [[ $infile_sr && $(($infile_sr % 48000)) -eq 0 ]]
    then
        echo "48000"
        return 0
    else
        err "ERROR: Only multiples of 44100 and 48000 are allowed for input sample rates when in maximum mode!"
        return 1
    fi
}

# Takes an input file as the only argument and converts it
# based on certain conditions, or returns an error if necessary
conv() {
    # The input file with "./" stripped from the beginning
    item=${1#./}

    err "item: $item"

    # Get some specifics about this input file
    # To see all info about a particular input file on the command line, type ffprobe -v error -show_streams <file>
    infile_sfmt=$(ffprobe -v error -select_streams a:0 -show_entries stream=sample_fmt -of default=noprint_wrappers=1:nokey=1 "$item" \
        | xargs echo -n)
    infile_sr=$(ffprobe -v error -select_streams a:0 -show_entries stream=sample_rate -of default=noprint_wrappers=1:nokey=1 "$item" \
        | xargs echo -n)

    # If user appended an "m" for "maximum" to the end of
    # the sample rate param, find nearest even multiple of
    # this infile's sample rate
    if [[ $MAX_SR =~ m$ ]]
    then
        err "INFO: Maximum sample rate specified for output. Recalculating destination sample rate"

        # Get lowest factor from infile sr and skip this file on error
        if ! lowest_factor=$(find_lowest_factor $infile_sr)
        then
            error_level=1
            err "SKIPPING ${item}..."
            return 0
        fi

        # Get destination sample rate for this file. Stop all conversion on error
        if ! dest_sr=$(recalc_sr $infile_sr $lowest_factor)
        then
            error_level=2
            err "FATAL"
            return 1
        fi
    fi
    
    # Append a marker to the end of the output filename indicating new sample rate
    suffix="_ff"$(($dest_sr / 1000))"k"
    filter_args="aresample=resampler=soxr:precision=32:dither_method=triangular:osr=${dest_sr}"

    # Double pass for signed to signed resampling, as ffmpeg has some kind of problem
    # with this while setting the output sample rate of a signed audio codec type w sox. 
    # This way it gets double dithered with sox, which seems to be the best way of 
    # avoiding the bug, which causes pops in the converted audio.
    if [[ $infile_sfmt =~ ^s[0-9]+ && ($item =~ .flac$ || $item =~ .m[^\.]+$) ]]
    then
        pre_filter_args="aresample=resampler=soxr:precision=32:dither_method=triangular,"
    fi

    # Set the right output codec/sfmt for m4a, wav, aif, flac
    if [[ $OUTFILE_EXT == "aiff" ]]
    then
        out_args="-acodec pcm_${infile_sfmt}be"
    elif [[ $OUTFILE_EXT == "wav" ]]
    then
        out_args="-acodec pcm_${infile_sfmt}le"
    elif [[ $OUTFILE_EXT == "m4a" ]]
    then
        out_args="-acodec alac"
    # For some reason (perhaps bc of the precision set in sox resampler),
    # signed pcm files are having their bit depth increased from 16 to 24 if we
    # don't specify to keep the sample format the same.
    elif [[ $OUTFILE_EXT == "flac" && $infile_sfmt =~ ^s[0-9]+ ]]
    then
        if [[ $infile_sfmt =~ p$ ]]
        then
            # Flac doesn't support the "p" variants of signed sample fmts
            infile_sfmt=${infile_sfmt%p}
        fi
        out_args="-sample_fmt ${infile_sfmt}"
    fi

    # Prepend output directory, strip infile extension, add suffix, add outfile extension
    output_file=${OUT_DIR}${item%.*}${suffix}.${OUTFILE_EXT}

    # Skip if we've already created this output file and it's not zero-size
    if [[ -e $output_file && -s $output_file ]]
    then
        err "INFO: Output file already exists!"
        err "SKIPPING ${output_file}"
        return 0
    fi

    # Print some info about the output file to be created
    err "filter_args: $pre_filter_args$filter_args$vol_level"
    err "out_args: $out_args"
    err "output_file: $output_file"

    # Where the magic happens
    ffmpeg -y -i "$item" -af "$pre_filter_args$filter_args$vol_level" $out_args "$output_file"

    return 0
}

########################
# DRIVER CODE
########################
# Set volume boost/cut if given as argument
if [[ $VOL_BOOST ]]
then
    vol_level=",volume=${3}dB"
fi

# Recreate the directory structure from the input dir in the output dir
# First create the output directory in case there are no subdirectories in CWD
mkdir "$OUT_DIR"
find . -mindepth 1 -type d -exec mkdir -p -- "${OUT_DIR}{}" \;

# Recursively loop through all supported audio files, call the conv function on each
# Using brace expansion to search both the current dir, and subdirs
for item in ./{*,**/*}.{flac,dsf,dff,wav,aiff,m4a,mp3}
do 
    # Skip unexpanded globs
    if [[ -e $item ]] 
    then 
        # Reset some file-specific resampler args
        pre_filter_args=""
        out_args=""

        # If we got a fatal error on trying to convert this file...
        if ! conv "$item"
        then
            # Exit loop
            break
        fi
    fi
done

# Not doing anything specific with the various error levels for now. Just checking for existence.
if [[ $error_level -ne 0 ]]
then
    err ""
    err "WARNING: Errors were encountered. Some or all files may not have been converted"
    print_usage
    exit 1
else
    exit 0
fi
