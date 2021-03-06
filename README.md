# tidylst
A program to validate and reformat files in PCGen's LST format

NAME
    tidylist.pl -- Reformat the PCGEN .lst files

    Version: 1.04.00

DESCRIPTION
    tidylst.pl is a script that parses PCGEN .lst files and generates new
    ones with ordered fields. The original order was given by Mynex.

    The script is also able to do some conversions of the .lst so that old
    versions are made compatible with the latest release of PCGEN.

INSTALLATION
  Get Perl
    I'm using perl v5.24.1 built for debian but any standard distribution
    should work. Note with Windows 10, you can install various versions of
    linux as a service and these make running perl very easy.

    The script uses only two nonstandard modules, which you can get from
    cpan, or if you use a package manager (activestate, debian etc.) you can
    get them from there, for instance for debian:

       apt install libmouse-perl
       apt-install libmousex-nativetraits-perl

    and for activestate:

      ppm install Mouse
      ppm install MouseX-AttributeHelpers

  Put the script somewhere
    Once Perl is installed on your computer, you just have to find a home
    for the script. After that, all you have to do is type perl tidylst.pl
    with the proper parameters to make it work.

SYNOPSIS
      # parse all the files in PATH, create the new ones in NEWPATH
      # and produce a report of the TAG in usage
      perl tidylst.pl -inputpath=<PATH> -outputpath=<NEWPATH> -report
      perl tidylst.pl -i=<PATH> -o=<NEWPATH> -r

      # parse all the files in PATH and write the error messages in ERROR_FILE
      # without creating any new files
      perl tidylst.pl -inputpath=<PATH> -outputerror=<ERROR_FILE>
      perl tidylst.pl -i=<PATH> -e=<ERROR_FILE>

      # parse all the files in PATH and write the error messages in ERROR_FILE
      # without creating any new files
      # A compilation of cross-checking (xcheck) errors will not be displayed and
      # only the messages of warning level notice or worst will be outputed.
      perl tidylst.pl -noxcheck -warninglevel=notice -inputpath=<PATH> -outputerror=<ERROR_FILE>
      perl tidylst.pl -nx -wl=notice -i=<PATH> -e=<ERROR_FILE>

      # parse all the files in PATH and created new ones in NEWPATH
      # by applaying the conversion pcgen5713. The output is redirected
      # to ERROR_FILE
      perl tidylst.pl -inputpath=<PATH> -outputpath=<NEWPATH> \
                                    -outputerror=<ERROR_FILE> -convert=pcgen5713
      perl tidylst.pl -i=<PATH> -o=<NEWPATH> -e=<ERROR_FILE> -c=pcgen5713

      # display the usage guide lines
      perl tidylst.pl -help
      perl tidylst.pl -h
      perl tidylst.pl -?

      # display the complete documentation
      perl tidylst.pl -man

      # generate and attemp to display a html file for
      # the complete documentation
      perl tidylst.pl -htmlhelp

PARAMETERS
  -inputpath or -i
    The path of a directory which will be scanned for .pcc files. A list of
    files to parse will be built from the .pcc files found. Only the known
    filetypes will be parsed.

    If an -inputpath is given without an -outputpath, the script parses the
    lst files and produces warning messages. It does not write any new
    files.

  -basepath or -b
    The path of the base data directory. This is the root of the data
    "tree", it is used to replace the @ character in the paths of LST files
    specified in.PCC files. If no -basepath option is given, the value of
    -inputpath is used to replace the @ character.

  -vendorpath or -v
    The path of the vendor data directory. The path to a LST file given in a
    .pcc may be prefixed with a * character. A path will be constructed
    replacing the * with the vale of this option and a separating /. If this
    file exists it will be parsed. If it does not exist, the * is replaced
    with a @ and the script tries it to see if it is a file. Thus if no
    vendor path is supplied, it falls back to the basepath.

  -systempath or -s
    The path of the game mode files used for the .lst files in -inputpath.
    These files will be parsed to get a list of valid alignment
    abbreviations, valid statistic abbrreviations, valid game modes and
    globaly defined variables.

    If the -gamemode parameter is used, only the system files found in the
    proper game mode directory will be parsed.

  -outputpath or -o
    This is only used if -inputpath is defined. Any files generated by the
    script will be written to a directory tree under -outputpath which
    mirrors the tree under -inputpath.

    Note: the output directory must be created before calling the script.

  -outputerror or -e
    Redirect STDERR to a file. All the warnings and errors produced by this
    script are printed to STDERR.

  -gamemode or -gm
    Apply a filter on the GAMEMODE values and only read and/or reformat the
    files that meet the filter.

    e.g. -gamemode=35e

  -report or -r
    Produce a report on the valid tags found in all the .lst and .pcc files.
    The report for invalid tags is always printed.

  -nojep
    Disable the new extractVariables function for the formula. This makes
    the script use the old style formula parser.

  -noxcheck or -nx
    By default, tidylst.pl verifies that values refered to by other tags are
    valid entities. It produces a report of any missing or inconsistent
    values.

    These default checks may be disabled using this flag.

  -warninglevel or -wl
    Select the level of warnings displayed. Less critical levels include the
    more critical ones. ex. -wl=info will produce messages for levels info,
    notice, warning and error but will not produce the debug level messages.

    The possible levels are:

    error, err or 3
                Critical errors that need to be checked. These .lst files
                are unlikely to work properly with PCGen.

    warning, warn or 4
                Important messages that should be verified. All the
                conversion messages are at this level.

    notice or 5 The normal messages including common syntax mistakes and
                unknown tags.

    informational, info or 6 (default)
                This level can be very noisy. It includes messages that warn
                about style, best practices and about deprecated tags.

    debug or 7  Messages used by the programmer to debug the script.

  -exportlist
    Generate files which list entities with a the file and line where they
    are located. This is very useful when correcting the problems found by
    the cross check.

    The files generated are:

    *           class.csv

    *           domain.csv

    *           equipment.csv

    *           equipmod.csv

    *           feat.csv

    *           language.csv

    *           pcc.csv

    *           skill.csv

    *           spell.csv

    *           variable.csv

  -missingheader or -mh
    List all the requested headers (with the getHeader function) that are
    not defined in the %tagheader hash. When a header is not defined, the
    tag is used in the generated header lines.

  -help, -h or -?
    Print a brief help message and exit.

  -man
    Print the manual page and exit. You might want to pipe the output to
    your favorite pager (e.g. more).

  -htmlhelp
    Generate an .html file and a .css file with the complete documentation.

COPYRIGHT
    Tidylst and its accociated perl modules are Copyright 2019 Andrew Wilson
    <mailto:andrew@rivendale.net>

    This program is a rewritten version of prettylst.pl. Prettylst was
    written/maintianed by

    Copyright 2002 to 2006 by Éric "Space Monkey" Beaudoin --
    <mailto:beaudoer@videotron.ca>

    Copyright 2006 to 2010 by Andrew "Tir Gwaith" McDougall --
    <mailto:tir.gwaith@gmail.com>

    Copyright 2007 by Richard Bowers

    Copyright 2008 Phillip Ryan

    All rights reserved. You can redistribute and/or modify this program
    under the same terms as Perl itself.

    See <http://www.perl.com/perl/misc/Artistic.html>.
