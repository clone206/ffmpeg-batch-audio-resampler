# ffmpeg-batch-audio-resampler
A batch [ffmpeg](http://ffmpeg.org) audio file converter/resampler for *nix systems, written in bash. Tested in macOS and ubuntu, with bash 3.2+

This utility is meant to work only with audio files. It is mainly designed to help in situations where you have multiple lossless audio files in one or many format/sample rate(s), and you want to convert them all to one particular format/sample rate. It supports a specific target sample rate for all files, or you can set a maximum sample rate, and the closest even multiple of 44.1K or 48K below the specified maximum will be calculated and set for you.

For example, your phone may only support certain audio file formats, and it may have limitations as to which sample rates it supports. If you attempt to play back an audio file with a sample rate that is too high for your phone, it may get resampled "on-the-fly" by your phone, and the results may be less than pleasing to the discerning ear. Or perhaps you have Super Audio CD (SACD) rips in DSD format (.dff or .dsf files are supported), and you want to convert them to PCM files using the best freely-available resampling library ([sox](http://sox.sourceforge.net)), because you don't have a DSD-capable Digital-to-Analog Converter (DAC), and you don't want these files converted "on-the-fly" by whatever player software you're using.

The main script is batch_resample.sh. There is a helper script named analyze_levels.sh. Both of these scripts depend on a recent version of ffmpeg being installed (tested with 3.4.2) with the optional sox resampling library added into ffmpeg at compile-time.

## Installing
1. Make sure you have a recent version of ffmpeg installed that supports apple lossles, flac, dsf, and dff files, and that it was compiled with the sox resampling library.

2. Put batch_resample.sh and analyze_levels.sh somewhere in your path

3. Customize the $OUT_DIR variable within batch_resample.sh if you want. This variable is initialized near the top of the file and determines where the converted audio files go. By default a directory is created in your home directory called "batch_resampled" (~/batch_resampled/), but you may want to change this. For example if you are working on a mac, and want the converted files automatically added to iTunes, you could set it like the following:

OUT_DIR=~/Music/iTunes/iTunes\ Media/Automatically\ Add\ to\ iTunes.localized/

Notice how the above is escaped (but not quoted) and has a trailing slash. That's important!

## Usage
### batch_resample.sh

cd to the directory containing the audio files you want to convert/resample. This script is recursive, so any subdirectories will get processed as well. Now:


```batch_resample.sh <sample_rate> <outfile_extension> [vol_adjust_db]```

Converts all supported audio files in the current directory to the format corresponding
to the given file extension (don't include the dot), at the speciied sample rate (in Hz).
To specify a maximum output sample rate, where any input file of a greater rate gets downsampled
to the nearest even multiple of either 44100 or 48000, add an 'm' to the end of the number,
eg. '96000m'. If an input file has a sample rate that is already below this, it will not be upsampled.

An optional volume adjust (in dB) can be given (positive number for boost,
negative for cut).

Renames file basenames on conversion and doesn't re-convert already
converted files on subsequent runs.

Supported infile types: flac,dsf,dff,wav,aiff,m4a,mp3
Supported outfile types: flac,wav,aiff,m4a(alac),mp3

Each converted file gets an "ff\d+k" appended to the file's basename, where "\d+" is the sample rate of the converted file in kHz. If you run the script multiple times, and use the same output directory, any already converted file will be skipped, as long as you're specifying the same sample rate and file format (flac, m4a, etc) as on previous runs. This way you can keep adding files to your library and runnning the script again as needed.

When batch_resample.sh is working recursively, the directory structure from the input directory is copied to the output directory.

#### examples

Set all to 48K flac files with a 3dB boost:


```batch_resample.sh 48000 flac 3```

Apple Lossless files with a maximum sample rate of 96K. Rounds down to the closest even multiple of the input file's sample rate:


```batch_resample.sh 96000m m4a```

### analyze_levels.sh 

```analyze_levels.sh <file_name|glob>```

#### examples

```analyze_levels.sh *.flac```

```analyze_levels.sh test.aiff```

Takes either a single file name or a wildcard expression (glob)
and reports the max peak level in dB of any corresponding files,
along with the highest found out of all files analyzed.

This utility comes in handy when you want to boost the levels of your audio files, but don't want to overdo it and cause digital "clipping" by boosting too much. Many SACD's are mastered much more quietly than traditional digital files and CDs. Often the loudest levels on an SACD will effectively be in the neighborhood of -2.9dB, as opposed to the usual -0.1dB or so in other formats. So you may want to run this script within the folder containing the dsf or dff files for a SACD album, and figure out how loud the files are. Then when you convert with batch_resample.sh, you can use the optional volume boost parameter to specify how many decibels to boost. Then all of the tracks will get boosted by this amount so the relative levels of the tracks stay the same. Now you can get your files nice and hot if your phone's headphone amp is underpowered.

This can be tricky, however, as 0dB in a DSD file can correspond to -2.9dB or so in the converted PCM audio file, and it can be unclear at the time of running these scripts whether or not replay gain metadata is affecting the reported levels. Or if the DSD files have extraneous noise in them at the beginning or ending of the audio, due to a bad SACD rip, this can show up as very high levels, perhaps even clipping, while the audio remains well below these levels. Often you'll have to do some guesswork, doing multiple passes of analyze_levels.sh, before and after running batch_resample.sh, when converting DSD files. Many of the bad-sounding PCM-formatted SACD rips out there sound horrible in part because clipping was allowed to happen during the conversion, perhaps due to a blanket 6dB boost done on all conversions from DSD to PCM, which is sure to cause clipping on many albums.

## Wonky Q & A
#### What if I add more audio files to the same directory on my computer where the already-converted files live? Since batch_resample.sh is recursive, will it go through and re-convert all the files again?
It depends. batch_resample.sh tries to be smart about this. If you specify a new format/sample rate the next time you run the script, even if you use the same output directory as last time ($OUT_DIR), then yes, all of the files will get converted again. The script appends a special marker to each converted file name showing what sample rate it was converted to. If you request a conversion to a certain sample rate and file type, and batch_resample.sh sees that there's already a non-empty file in the specified output directory that meets the description of the requested conversion, it skips the conversion on that run. But if you're using the same settings and output directory as last time, then only the newly added files will be converted, and as usual, the directory structure from the source directory gets copied over to the output directory.

#### So why do I care if the sample rate gets converted to an even multiple of the original sample rate?
Because otherwise you have to use "interpolation" to guess at where the new samples' amplitudes should be. In theory this can be done extremely transparently, but in practice there are many variables that determine how the resultant audio sounds. If you're converting between lossless formats, I'm assuming you care about this stuff. Just for fun, have a look [here](http://src.infinitewave.ca). You'll see a wide array of differences in how audio comes out after converting to an uneven multiple of the original sample rate. I know, I know. You can't go by graphs. What matters is whether a human can hear the differences. That's another long discussion.

In any event, I've taken great pains to set up the sox resampler to sound the best it can, using the highest possible precision with dithering, so that if you do need to convert to an uneven multiple (like, say, if the resampling on your phone sounds afwul and everything gets resampled to 48K), you should get a nearly indistinguishable copy of your audio. But if you don't need to do this, better safe than sorry. You can also end up with smaller file sizes when setting a maximum/even multiple mode, because then some files have their sample rates rounded down, which means the files take up less storage space.

#### Can I set the output directory to the sd card/internal storage of my usb-connected android phone?
Yes! But your mileage may vary. This has been tested successfully on ubuntu with the phone mounted via [MTP](https://en.wikipedia.org/wiki/Media_Transfer_Protocol).

MTP can be kind of a pain, though. For one thing you have to [find out where the phone gets mounted](https://askubuntu.com/a/342549) into your linux filesystem, and it can change each time you plug your phone back into the usb port. Also, you may get done with a huge conversion, browse to your phone's mounted storage in ubuntu and see nothing but "0K" (empty) files. Don't panic. It's an MTP thing. Safely unmount/eject your phone, unplug and plug it back in, and the files should show the correct sizes now.

The batch_resample.sh script checks to see if it's already created the requested file in the specified output directory ($OUT_DIR), and whether or not it's empty. If there's a non-empty file there, and you run the script again, the conversion of that file will get skipped, but not if you're trying to write to an MTP-mounted phone that's still reporting the file as being "0K". The conversions will all happen again. In that case you'll have to follow the above unplugging/replugging procedure before rerunning batch_resample.sh.

