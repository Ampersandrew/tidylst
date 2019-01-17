#!/usr/bin/perl

use strict;
use warnings;
use Fatal qw( open close );             # Force some built-ins to die on error
use English qw( -no_match_vars );       # No more funky punctuation variables

my $VERSION        = "1.00.00";
my $VERSION_DATE   = "2019-01-01";
my ($PROGRAM_NAME) = "PCGen TidyLst";
my ($SCRIPTNAME)   = ( $PROGRAM_NAME =~ m{ ( [^/\\]* ) \z }xms );
my $VERSION_LONG   = "$SCRIPTNAME version: $VERSION -- $VERSION_DATE";

my $today = localtime;

use Carp;
use FileHandle;
use Pod::Html ();  # We do not import any function for
use Pod::Text ();  # the modules other than "system" modules
use Pod::Usage ();
use File::Find ();
use File::Basename ();

# Expand the local library path so we can find TidyLst modules
use File::Basename qw(dirname);
use Cwd qw(abs_path);
use lib dirname(abs_path $0) . '/lib';

use TidyLst::Convert qw(convertEntities);
use TidyLst::Data qw(
   BLOCK BLOCK_HEADER COMMENT FIRST_COLUMN LINE LINE_HEADER MAIN
   NO NO_HEADER SINGLE SUB YES
   addSourceToken
   addTagsForConversions
   constructValidTags
   getEntityFirstTag
   getEntityNameTag
   getOrderForLineType
   getHeader
   getValidSystemArr
   incCountValidTags
   isValidEntity
   isValidGamemode
   isValidMultiTag
   isValidTag
   seenSourceToken
   setEntityValid
   updateValidity
   );
use TidyLst::Line;
use TidyLst::Log;
use TidyLst::LogFactory qw(getLogger);
use TidyLst::LogHeader;
use TidyLst::Options qw(getOption isConversionActive parseOptions setOption);
use TidyLst::Parse qw(
   extractTag
   isParseableFileType
   isWriteableFileType
   normaliseFile
   parseSystemFiles
   );
use TidyLst::Report qw(closeExportListFileHandles openExportListFileHandles);
use TidyLst::Validate qw(scanForDeprecatedTokens validateLine);

# Subroutines
sub find_full_path;
sub create_dir;
sub generate_css;

# Print version information
print STDERR "$VERSION_LONG\n";

#######################################################################
# Parameter parsing

# Parse the command line options and set the error message if there are any issues.
my $errorMessage = "\n" . parseOptions(@ARGV);
my $dumpValidEntities = 0;

# Test function or display variables or anything else I need.
if ( getOption('test') ) {

   $dumpValidEntities = 1;
   # print "No tests set\n";
   # exit;
}

# The command line has been processed, if conversions have been requested, make
# sure the tag validity data in Reformat.pm is updated. In order to convert a
# tag it must be recognised as valid.
addTagsForConversions();

# Create the singleton logging object
my $log = getLogger();

#######################################################################
# Redirect STDERR if requeseted

if (getOption('outputerror')) {
   open STDERR, '>', getOption('outputerror');
   print STDERR "Error log for $VERSION_LONG\n";
   print STDERR qq{On the files in "} . getOption('inputpath') . qq{" on $today\n};
}

#######################################################################
# Path options

if (!getOption('inputpath') && !getOption('filetype') &&
   !(getOption('man') || getOption('htmlhelp')))
{
   $errorMessage .= "\n-inputpath parameter is missing\n";
   setOption('help', 1);
}

# Verify that the outputpath exists
if ( getOption('outputpath') && !-d getOption('outputpath') ) {

   $errorMessage = "\nThe directory " . getOption('outputpath') . " does not exist.";

   Pod::Usage::pod2usage(
      {
         -msg     => $errorMessage,
         -exitval => 1,
         -output  => \*STDERR,
      }
   );
   exit;
}

#######################################################################
# Diplay usage information

if ( getOption('help') or $TidyLst::Options::error ) {
   Pod::Usage::pod2usage(
      {
         -msg     => $errorMessage,
         -exitval => 1,
         -output  => \*STDERR
      }
   );
   exit;
}

#######################################################################
# Display the man page

if (getOption('man')) {
   Pod::Usage::pod2usage(
      {
         -msg     => $errorMessage,
         -verbose => 2,
         -output  => \*STDERR
      }
   );
   exit;
}

#######################################################################
# Generate the HTML man page and display it

if ( getOption('htmlhelp') ) {
   if( !-e "$PROGRAM_NAME.css" ) {
      generate_css("$PROGRAM_NAME.css");
   }

   Pod::Html::pod2html(
      "--infile=$PROGRAM_NAME",
      "--outfile=$PROGRAM_NAME.html",
      "--css=$PROGRAM_NAME.css",
      "--title=$PROGRAM_NAME -- Reformat the PCGEN .lst files",
      '--header',
   );

   `start /max $PROGRAM_NAME.html`;

   exit;
}

#######################################################################
# -systempath option
#
# If a system path was passed on the command line, call the function to
# generate the "game mode" variables.

if ( getOption('systempath') ne q{} ) {
   parseSystemFiles(getOption('systempath'));
}

# For Some tags, validity is based on the system mode variables
updateValidity();

# PCC processing
my %files = ();

# Finds the CVS lines at the top of LST files,so we can delete them
# and replace with a single line TidyLst Header.
my $CVSPattern       = qr{\#.*CVS.*Revision}i;
my $newHeaderPattern = qr{\#.*reformatt?ed by}i;
my $TidyLstHeader    = "# $today -- reformatted by $SCRIPTNAME v$VERSION\n";

my %filesToParse;    # Will hold the file to parse (including path)
my @lines;           # Will hold all the lines of the file
my @nodifiedFiles;   # Will hold the name of the modified files

#####################################
# Verify if the inputpath was given

if (getOption('inputpath')) {

   # Construct the valid tags for all file types
   constructValidTags();

   ##########################################################
   # Files that needs to be open for special conversions

   if (getOption('exportlist')) {
      openExportListFileHandles();
   }

   ##########################################################
   # Parse all the .pcc file to find the other file to parse

   # First, we list the .pcc files in the directory
   my @filelist;
   my %fileListNotPCC;
   my %fileListMissing;

   # Regular expressions for the files that must be skiped by mywanted.
   my @filetoskip = (
      qr(^\.\#),              # Files begining with .# (CVS conflict and deleted files)
      qr(^custom),            # Customxxx files generated by PCGEN
      qr(placeholder\.txt$),  # The CMP directories are full of these
      qr(\.zip$)i,            # Archives present in the directories
      qr(\.rar$)i,
      qr(\.jpg$),             # JPEG image files present in the directories
      qr(\.png$),             # PNG image files present in the directories
      qr(readme\.txt$),       # Readme files
      qr(\.bak$),             # Backup files
      qr(\.java$),            # Java code files
      qr(\.htm$),             # HTML files
      qr(\.xml$),
      qr(\.css$),

      qr(\.DS_Store$),        # Used with Mac OS
   );

   # Regular expressions for the directory that must be skiped by mywanted
   my @dirtoskip = (
      qr(cvs$)i,              # /cvs directories
      qr([.]svn[/])i,         # All .svn directories
      qr([.]svn$)i,           # All .svn directories
      qr([.]git[/])i,         # All .git directories
      qr([.]git$)i,           # All .git directories
      qr(customsources$)i,    # /customsources (for files generated by PCGEN)
      qr(gamemodes)i,         # for the system gameModes directories
   );

   sub mywanted {

      # We skip the files from directory matching the REGEX in @dirtoskip
      for my $regex (@dirtoskip) {
         return if $File::Find::dir =~ $regex;
      }

      # We also skip the files that match the REGEX in @filetoskip
      for my $regex (@filetoskip) {
         return if $_ =~ $regex;
      }

      # It's not a directory and ends with pcc
      if ( !-d && m/ [.] pcc \z /xmsi ) {
         push @filelist, $File::Find::name;
      }

      # It's not a directory and doesn't with pcc
      if ( !-d && !/ [.] pcc \z /xmsi ) {
         $fileListNotPCC{$File::Find::name} = lc $_;
      }
   }

   File::Find::find( \&mywanted, getOption('inputpath') );

   $log->header(TidyLst::LogHeader::get('PCC'));

   # Second we parse every .PCC and look for filetypes
   for my $filename ( sort @filelist ) {
      open my $pcc_fh, '<', $filename;

      # Needed to find the full path
      my $currentbasedir = File::Basename::dirname($filename);

      my %found = (
         'book type'    => NO,
         'gamemode'     => q{},
         'header'       => NO,
         'lst'          => NO,
         'source long'  => q{},
         'source short' => q{},
      );

      my $mustWrite      = NO;
      my @pccLines       = ();
      my %foundFileType;

      PCC_LINE:
      for my $pccLine ( <$pcc_fh> ) {

         chomp $pccLine;
         $mustWrite += $pccLine =~ s/[\x0d\x0a]//g; # Remove the real and weird CR-LF
         $mustWrite += $pccLine =~ s/\s+$//;        # Remove any tralling white spaces

         push @pccLines, $pccLine;

         # This is a PCC file, there is only one tag on a line
         my ($tag, $value) = extractTag(
            $pccLine,
            'PCC',
            $filename,
            $INPUT_LINE_NUMBER);

         # If extractTag returns a defined value, no further processing is
         # neeeded. If value is not defined then the tag that was returned
         # should be processed further.

         my $fullToken = (not defined $value) ?  $tag : "$tag:$value" ;

         my $token =  TidyLst::Token->new(
            fullToken => $fullToken,
            lineType  => 'PCC',
            file      => $filename,
            line      => $INPUT_LINE_NUMBER,
         );

         if (not defined $value) {

            # All of the individual tag parsing and correcting happens here,
            # this potentally modifys the tag
            $token->process();

            # If the tag has been altered, the the PCC file needs to be
            # written and the line should be overwritten.
            if ($token->origToken ne $token->fullRealToken) {
               $mustWrite = 1;
               $pccLines[-1] = $token->fullRealToken;
            }
         }

         if ($token->tag) {
            if (isParseableFileType($token->tag)) {

               # Keep track of the filetypes found
               $foundFileType{$token->tag}++;

               # Extract the name of the LST file from the token->value, and
               # store it back into token->value
               $token->value($token->value =~ s/^([^|]*).*/$1/r);

               my $lstFile = find_full_path($token->value, $currentbasedir);
               $filesToParse{$lstFile} = $token->tag;

               # Check to see if the file exists
               if ( !-e $lstFile ) {

                  $fileListMissing{$lstFile} = [ $filename, $INPUT_LINE_NUMBER ];
                  delete $filesToParse{$lstFile};

               # Remember some types of file, might need to process them first.
               } elsif (
                     $token->tag eq 'ALIGNMENT'
                  || $token->tag eq 'CLASS'
                  || $token->tag eq 'CLASSSPELL'
                  || $token->tag eq 'DOMAIN'
                  || $token->tag eq 'SAVE'
                  || $token->tag eq 'SPELL'
                  || $token->tag eq 'STAT'
               ) {

                  $files{$token->tag}{$lstFile} = 1;
               }

               if (exists $fileListNotPCC{$lstFile}) {
                  delete $fileListNotPCC{$lstFile}
               }
               $found{'lst'} = 1;

            } elsif ( $token->tag =~ m/^\#/ ) {

               if ($token->tag =~ $newHeaderPattern) {
                  $found{'header'} = 1;
               }

            } elsif (isValidTag('PCC', $token->tag)) {

               # All the tags that do not have a file should be caught here

               # Get the SOURCExxx tags for future ref.
               if (isConversionActive('SOURCE line replacement')
                  && (  $token->tag eq 'SOURCELONG'
                     || $token->tag eq 'SOURCESHORT'
                     || $token->tag eq 'SOURCEWEB'
                     || $token->tag eq 'SOURCEDATE' ) )
               {
                  my $path = File::Basename::dirname($filename);

                  # If a token with the same tag has been seen in this directory
                  if (seenSourceToken($path, $token) && $path !~ /custom|altpcc/i ) {

                     $log->notice(
                        $token->tag . " already found for $path",
                        $filename,
                        $INPUT_LINE_NUMBER
                     );

                  } else {
                     addSourceToken($path, $token->tag, $token->fullRealToken);
                  }

                  # For the PCC report
                  if ( $token->tag eq 'SOURCELONG' ) {
                     $found{'source long'} = $token->value;
                  } elsif ( $token->tag eq 'SOURCESHORT' ) {
                     $found{'source short'} = $token->value;
                  }

               } elsif ( $token->tag eq 'GAMEMODE' ) {

                  # Verify that the GAMEMODEs are valid
                  # and match the filer.
                  $found{'gamemode'} = $token->value;       # The GAMEMODE tag we found
                  my @modes = split /[|]/, $token->value;

                  my $gamemode = getOption('gamemode');
                  my $gamemode_regex = $gamemode ? qr{ \A (?: $gamemode  ) \z }xmsi : qr{ . }xms;
                  my $valid_game_mode = $gamemode ? 0 : 1;

                  # First the filter is applied
                  for my $mode (@modes) {
                     if ( $mode =~ $gamemode_regex ) {
                        $valid_game_mode = 1;
                     }
                  }

                  # Then we check if the game mode is valid only if
                  # the game modes have not been filtered out
                  if ($valid_game_mode) {
                     for my $mode (@modes) {
                        if ( ! isValidGamemode($mode) ) {
                           $log->notice(
                              qq{Invalid GAMEMODE "$mode" in "$_"},
                              $filename,
                              $INPUT_LINE_NUMBER
                           );
                        }
                     }
                  }

                  if ( !$valid_game_mode ) {
                     # We set the variables that will kick us out of the
                     # while loop that read the file and that will
                     # prevent the file from being written.
                     $mustWrite   = NO;
                     $found{'header'} = NO;
                     last PCC_LINE;
                  }

               } elsif ( $token->tag eq 'BOOKTYPE' || $token->tag eq 'TYPE' ) {

                  # Found a TYPE tag
                  $found{'book type'} = 1;

               } elsif ( $token->tag eq 'GAME' && isConversionActive('PCC:GAME to GAMEMODE') ) {

                  $value = $token->value;

                  # [ 707325 ] PCC: GAME is now GAMEMODE
                  $pccLines[-1] = "GAMEMODE:$value";
                  $log->warning(
                     q{Replacing "} . $token->fullRealToken . qq{" by "GAMEMODE:$value"},
                     $filename,
                     $INPUT_LINE_NUMBER
                  );
                  $found{'gamemode'} = $token->value;
                  $mustWrite = 1;
               }
            }

         } elsif ( $pccLine =~ m/ \A [#] /xms ) {

            if ($pccLine =~ $newHeaderPattern) {
               $found{'header'} = 1;
            }

         } elsif ( $pccLine =~ m/ <html> /xmsi ) {
            $log->error(
               "HTML file detected. Maybe you had a problem with your CSV checkout.\n",
               $filename
            );
            $mustWrite = NO;
            last PCC_LINE;
         }
      }

      close $pcc_fh;

      if ( !$found{'book type'} && $found{'lst'} ) {
         $log->notice( 'No BOOKTYPE tag found', $filename );
      }

      if (!$found{'gamemode'}) {
         $log->notice( 'No GAMEMODE tag found', $filename );
      }

      if ( $found{'gamemode'} && getOption('exportlist') ) {
         TidyLst::Report::printToExportList('PCC', qq{"$found{'source long'}","$found{'source short'}","$found{'gamemode'}","$filename"\n});
      }

      # Do we copy the .PCC???
      if ( getOption('outputpath') && ( $mustWrite || !$found{'header'} ) && isWriteableFileType("PCC") ) {
         my $new_pcc_file = $filename;
         my $inputpath  = getOption('inputpath');
         my $outputpath = getOption('outputpath');
         $new_pcc_file =~ s/${inputpath}/${outputpath}/i;

         # Create the subdirectory if needed
         create_dir( File::Basename::dirname($new_pcc_file), getOption('outputpath') );

         open my $new_pcc_fh, '>', $new_pcc_file;

         # We keep track of the files we modify
         push @nodifiedFiles, $filename;

         if ($pccLines[0] !~ $newHeaderPattern) {
            print {$new_pcc_fh} "# $today -- reformatted by $SCRIPTNAME v$VERSION\n";
         }

         for my $line (@pccLines) {
            print {$new_pcc_fh} "$line\n";
         }

         close $new_pcc_fh;
      }
   }

   # Is there anything to parse?
   if ( !keys %filesToParse ) {

      $log->error(
         qq{Could not find any .lst file to parse.},
         getOption('inputpath')
      );

      $log->error(
         qq{Is your -inputpath parameter valid? (} . getOption('inputpath') . ")",
         getOption('inputpath')
      );

      if ( getOption('gamemode') ) {
         $log->error(
            qq{Is your -gamemode parameter valid? (} . getOption('gamemode') . ")",
            getOption('inputpath')
         );
         exit;
      }
   }

   # Missing .lst files must be printed
   if ( keys %fileListMissing ) {

      $log->header(TidyLst::LogHeader::get('Missing LST'));

      for my $lstfile ( sort keys %fileListMissing ) {
         $log->notice(
            "Can't find the file: $lstfile",
            $fileListMissing{$lstfile}[0],
            $fileListMissing{$lstfile}[1]
         );
      }
   }

   # If the gamemode filter is active, we do not report files not refered to.
   if ( keys %fileListNotPCC && !getOption('gamemode') ) {

      $log->header(TidyLst::LogHeader::get('Unreferenced'));

      my $basepath = getOption('basepath');

      for my $file ( sort keys %fileListNotPCC ) {
         $file =~ s/${basepath}//i;
         $file =~ tr{/}{\\} if $^O eq "MSWin32";

         $log->notice("$file\n", "");
      }
   }

} else {
   $filesToParse{'STDIN'} = getOption('filetype');
}

$log->header(TidyLst::LogHeader::get('LST'));

my @filesToParse_sorted = ();
my %temp_filesToParse   = %filesToParse;

# This bit used to be separate checks and it only pulled files forward if
# certain conversions were active. It turns out that that ordering was
# mututally exclusive and we can just do it all, all the time. I've left the
# separate comments explaining why some files are pulled tot he front of the
# list.

# The CLASS files must be put at the start of the filesToParse_sorted array in
# order for them to be dealt with before the SPELL files.

# The CLASS and DOMAIN files must be put at the start of the
# filesToParse_sorted array in order for them to be dealt with before the
# CLASSSPELL files. The CLASSSPELL needs to be processed before the SPELL
# files.

# The SPELL file must be loaded before the EQUIPMENT in order to properly
# generate the EQMOD tags

for my $filetype (qw(CLASS DOMAIN CLASSSPELL SPELL)) {
   for my $file_name ( sort keys %{ $files{$filetype} } ) {
      push @filesToParse_sorted, $file_name;
      delete $temp_filesToParse{$file_name};
   }
}

# We sort the files that need to be parsed.
push @filesToParse_sorted, sort keys %temp_filesToParse;

FILE_TO_PARSE:
for my $file (@filesToParse_sorted) {
   my $numberofcf = 0;     # Number of extra CF found in the file.

   my $filetype = "tab-based";   # can be either 'tab-based' or 'multi-line'

   if ( $file eq "STDIN" ) {

      # We read from STDIN
      # henkslaaf - Multiline parsing
      #       1) read all to a buffer (files are not so huge that it is a memory hog)
      #       2) send the buffer to a method that splits based on the type of file
      #       3) let the method return split and normalized entries
      #       4) let the method return a variable that says what kind of file it is (multi-line, tab-based)
      local $/ = undef; # read all from buffer
      my $buffer = <>;

      (my $lines, $filetype) = normaliseFile($buffer);
      @lines = @$lines;

   } else {

      # We read only what we know needs to be processed
      my $parseable = isParseableFileType($filesToParse{$file});

      next FILE_TO_PARSE if ref( $parseable ) ne 'CODE';

      # We try to read the file and continue to the next one even if we
      # encounter problems
      #
      # henkslaaf - Multiline parsing
      #       1) read all to a buffer (files are not so huge that it is a memory hog)
      #       2) send the buffer to a method that splits based on the type of file
      #       3) let the method return split and normalized entries
      #       4) let the method return a variable that says what kind of file it is (multi-line, tab-based)

      eval {

         local $/ = undef; # read all from buffer
         open my $lst_fh, '<', $file;
         my $buffer = <$lst_fh>;
         close $lst_fh;

         (my $lines, $filetype) = normaliseFile($buffer);
         @lines = @$lines;
      };

      if ( $EVAL_ERROR ) {
         # There was an error in the eval
         $log->error( $EVAL_ERROR, $file );
         next FILE_TO_PARSE;
      }
   }

   # If the file is empty, we skip it
   unless (@lines) {
      $log->notice("Empty file.", $file);
      next FILE_TO_PARSE;
   }

   # Check to see if we are dealing with a HTML file
   if ( grep /<html>/i, @lines ) {
      $log->error( "HTML file detected. Maybe you had a problem with your CVS checkout.\n", $file );
      next FILE_TO_PARSE;
   }

   my $headerRemoved = 0;

   # While the first line is any sort of comment about pretty lst or TidyLst,
   # we remove it
   REMOVE_HEADER:
   while ( $lines[0] =~ $CVSPattern || $lines[0] =~ $newHeaderPattern ) {
      shift @lines;
      $headerRemoved++;
      last REMOVE_HEADER if not defined $lines[0];
   }

   # The full file is in the @lines array, remove the normal EOL characters
   chomp(@lines);

   # Remove and count any abnormal EOL characters i.e. anything that remains
   # after the chomp
   for my $line (@lines) {
      $numberofcf += $line =~ s/[\x0d\x0a]//g;
   }

   if($numberofcf) {
      $log->warning( "$numberofcf extra CF found and removed.", $file );
   }

   my $parser = isParseableFileType($filesToParse{$file});

   if ( ref($parser) eq "CODE" ) {

      # The overwhelming majority of checking, correcting and reformatting happens in this operation
      my ($newlines_ref) = &{ $parser }( $filesToParse{$file}, \@lines, $file);

      # Let's remove any tralling white spaces
      for my $line (@$newlines_ref) {
         $line =~ s/\s+$//;
      }

      # henkslaaf - we need to handle this in multi-line object files
      #       take the multi-line variable and use it to determine
      #       if we should skip writing this file

      # Some file types are never written
      if ($filetype eq 'multi-line') {
         $log->report("SKIP rewrite for $file because it is a multi-line file");
         next FILE_TO_PARSE;                # we still need to implement rewriting for multi-line
      }

      if (!isWriteableFileType($filesToParse{$file})) {
         next FILE_TO_PARSE
      }

      # We compare the result with the orginal file.
      # If there are no modifications, we do not create the new files
      my $same  = NO;
      my $index = 0;

      # First, we check if there are obvious resons not to write the new file
      # No extra CRLF char. were removed
      # Same number of lines
      if (!$numberofcf && $headerRemoved && scalar(@lines) == scalar(@$newlines_ref)) {

         # We assume the arrays are the same ...
         $same = YES;

         # ... but we check every line
         $index = -1;
         while ( $same && ++$index < scalar(@lines) ) {
            if ( $lines[$index] ne $newlines_ref->[$index] ) {
               $same = NO;
            }
         }
      }

      next FILE_TO_PARSE if $same;

      my $write_fh;

      if (getOption('outputpath')) {

         my $newfile = $file;
         my $inputpath  = getOption('inputpath');
         my $outputpath = getOption('outputpath');
         $newfile =~ s/${inputpath}/${outputpath}/i;

         # Create the subdirectory if needed
         create_dir( File::Basename::dirname($newfile), getOption('outputpath') );

         open $write_fh, '>', $newfile;

         # We keep track of the files we modify
         push @nodifiedFiles, $file;

      } else {

         # Output to standard output
         $write_fh = *STDOUT;
      }

      # The first line of the new file will be a comment line.
      print {$write_fh} $TidyLstHeader;

      # We print the result
      for my $line ( @{$newlines_ref} ) {
         print {$write_fh} "$line\n"
      }

      # If we opened a filehandle, then close it
      if (getOption('outputpath')) {
         close $write_fh;
      }

   } else {
      warn "Didn't process filetype \"$filesToParse{$file}\".\n";
   }
}

###########################################
# Print a report with the modified files
if ( getOption('outputpath') && scalar(@nodifiedFiles) ) {

   my $outputpath = getOption('outputpath');

   if ($^O eq "MSWin32") {
      $outputpath =~ tr{/}{\\}
   }

   $log->header(TidyLst::LogHeader::get('Created'), getOption('outputpath'));

   my $inputpath = getOption('inputpath');
   for my $file (@nodifiedFiles) {
      $file =~ s{ ${inputpath} }{}xmsi;
      $file =~ tr{/}{\\} if $^O eq "MSWin32";
      $log->notice( "$file\n", "" );
   }

   print STDERR "================================================================\n";
}

###########################################
# Print a report for the BONUS and PRExxx usage

if (getOption('bonusreport')) {
   TidyLst::Report::reportBonus();
}

if (getOption('report')) {
   TidyLst::Report::report('Valid');
}

if (TidyLst::Report::foundInvalidTags()) {
   TidyLst::Report::report('Invalid');
}

if (getOption('xcheck')) {
   TidyLst::Report::doXCheck();
}

#########################################
# Close the files that were opened for
# special conversion

if ( getOption('exportlist') ) {
   closeExportListFileHandles();
}

if ($dumpValidEntities) {
   TidyLst::Data::dumpValidEntities();
}

#########################################
# Close the redirected STDERR if needed

if (getOption('outputerror')) {
   close STDERR;
   print STDOUT "\cG"; # An audible indication that PL has finished.
}

###############################################################################
###############################################################################
####                                                                       ####
####                            Subroutine Definitions                     ####
####                                                                       ####
###############################################################################
###############################################################################

###############################################################
# find_full_path
# --------------
#
# Change the @ and relative paths found in the .lst for
# the real thing.
#
# Parameters: $fileName         File name
#             $current_base_dir  Current directory

sub find_full_path {
   my ($fileName, $currentBaseDir) = @_;

   my $base_path  = getOption('basepath');

   # Change all the \ for / in the file name
   $fileName =~ tr{\\}{/};

   # See if the vendor path replacement is necessary   
   if ($fileName =~ m{ ^[*] }xmsi) {

      # Remove the leading * and / if present
      $fileName =~ s{ ^[*] [/]? }{}xmsi;

      my $vendorFile = getOption('vendorpath') . $fileName;

      if ( -e $vendorFile ) {
         $fileName = $vendorFile; 
      } else {
         $fileName = '@' . $fileName; 
      }

   }

   # Replace @ by the base dir or add the current base dir to the file name.
   if ($fileName !~ s{ ^[@] }{$base_path}xmsi) {
      $fileName = "$currentBaseDir/$fileName";
   }

   # Remove the /xxx/../ for the directory
   if ($fileName =~ / [.][.] /xms ) {
      if( $fileName !~ s{ [/] [^/]+ [/] [.][.] [/] }{/}xmsg ) {
         die qq{Cannot deal with the .. directory in "$fileName"};
      }
   }

   return $fileName;
}


###############################################################
# create_dir
# ----------
#
# Create any part of a subdirectory structure that is not
# already there.

sub create_dir {
   my ( $dir, $outputdir ) = @_;

   # Only if the directory doesn't already exist
   if ( !-d $dir ) {
      my $parentdir = File::Basename::dirname($dir);

      # If the $parentdir doesn't exist, we create it
      if ( $parentdir ne $outputdir && !-d $parentdir ) {
         create_dir( $parentdir, $outputdir );
      }

      # Create the curent level directory
      mkdir $dir, oct(755) or die "Cannot create directory $dir: $OS_ERROR";
   }
}


###############################################################
# generate_css
# ------------
#
# Generate a new .css file for the .html help file.

sub generate_css {
        my ($newfile) = shift;

        open my $css_fh, '>', $newfile;

        print {$css_fh} << 'END_CSS';
BODY {
        font: small verdana, arial, helvetica, sans-serif;
        color: black;
        background-color: white;
}

A:link  {color: #0000FF}
A:visited   {color: #666666}
A:active        {color: #FF0000}


H1 {
        font: bold large verdana, arial, helvetica, sans-serif;
        color: black;
}


H2 {
        font: bold large verdana, arial, helvetica, sans-serif;
        color: maroon;
}


H3 {
        font: bold medium verdana, arial, helvetica, sans-serif;
                color: blue;
}


H4 {
        font: bold small verdana, arial, helvetica, sans-serif;
                color: maroon;
}


H5 {
        font: bold small verdana, arial, helvetica, sans-serif;
                color: blue;
}


H6 {
        font: bold small verdana, arial, helvetica, sans-serif;
                color: black;
}


UL {
        font: small verdana, arial, helvetica, sans-serif;
                color: black;
}


OL {
        font: small verdana, arial, helvetica, sans-serif;
                color: black;
}


LI
{
        font: small verdana, arial, helvetica, sans-serif;
        color: black;
}

TH {
        font: small verdana, arial, helvetica, sans-serif;
        color: blue;
}


TD {
        font: small verdana, arial, helvetica, sans-serif;
        color: black;
}

TD.foot {
        font: medium sans-serif;
        color: #eeeeee;
        background-color="#cc0066"
}

DL {
        font: small verdana, arial, helvetica, sans-serif;
        color: black;
}


DD {
        font: small verdana, arial, helvetica, sans-serif;
        color: black;
}


DT {
        font: small verdana, arial, helvetica, sans-serif;
                color: black;
}


CODE {
        font: small Courier, monospace;
}


PRE {
        font: small Courier, monospace;
}


P.indent {
        font: small verdana, arial, helvetica, sans-serif;
        color: black;
        background-color: white;
        list-style-type : circle;
        list-style-position : inside;
        margin-left : 16.0pt;
}

PRE.programlisting
{
        list-style-type : disc;
        margin-left : 16.0pt;
        margin-top : -14.0pt;
}


INPUT {
        font: bold small verdana, arial, helvetica, sans-serif;
        color: black;
        background-color: white;
}


TEXTAREA {
        font: bold small verdana, arial, helvetica, sans-serif;
        color: black;
        background-color: white;
}

.BANNER {
        background-color: "#cccccc";
        font: bold medium verdana, arial, helvetica, sans-serif;

}
END_CSS

        close $css_fh;
}

__END__

=head1 NAME

prettylst.pl -- Reformat the PCGEN .lst files

Version: 1.38

=head1 DESCRIPTION

B<tidylst.pl> is a script that parses PCGEN .lst files and generates
new ones with ordered fields. The original order was given by Mynex.

The script is also able to do some conversions of the .lst so that old
versions are made compatible with the latest release of PCGEN.

=head1 INSTALLATION

=head2 Get Perl

I'm using perl v5.24.1 built for debian but any standard distribution 
should work.

The script uses only two nonstandard modules, which you can get from cpan,
or if you use a package manager (activestate, debian etc.) you can get them
from there, for instance for activestate

  ppm install Mouse
  ppm install MouseX-AttributeHelpers

=head2 Put the script somewhere

Once Perl is installed on your computer, you just have to find a home for the script. After that,
all you have to do is type B<perl prettylst.pl> with the proper parameters to make it
work.

=head1 SYNOPSIS

  # parse all the files in PATH, create the new ones in NEWPATH
  # and produce a report of the TAG in usage
  perl prettylst.pl -inputpath=<PATH> -outputpath=<NEWPATH> -report
  perl prettylst.pl -i=<PATH> -o=<NEWPATH> -r

  # parse all the files in PATH and write the error messages in ERROR_FILE
  # without creating any new files
  perl prettylst.pl -inputpath=<PATH> -outputerror=<ERROR_FILE>
  perl prettylst.pl -i=<PATH> -e=<ERROR_FILE>

  # parse all the files in PATH and write the error messages in ERROR_FILE
  # without creating any new files
  # A compilation of cross-checking (xcheck) errors will not be displayed and
  # only the messages of warning level notice or worst will be outputed.
  perl prettylst.pl -noxcheck -warninglevel=notice -inputpath=<PATH> -outputerror=<ERROR_FILE>
  perl prettylst.pl -nx -wl=notice -i=<PATH> -e=<ERROR_FILE>

  # parse all the files in PATH and created new ones in NEWPATH
  # by applaying the conversion pcgen5713. The output is redirected
  # to ERROR_FILE
  perl prettylst.pl -inputpath=<PATH> -outputpath=<NEWPATH> \
                                -outputerror=<ERROR_FILE> -convert=pcgen5713
  perl prettylst.pl -i=<PATH> -o=<NEWPATH> -e=<ERROR_FILE> -c=pcgen5713

  # display the usage guide lines
  perl prettylst.pl -help
  perl prettylst.pl -h
  perl prettylst.pl -?

  # display the complete documentation
  perl prettylst.pl -man

  # generate and attemp to display a html file for
  # the complete documentation
  perl prettylst.pl -htmlhelp

=head1 PARAMETERS

=head2 B<-inputpath> or B<-i>

Path to an input directory that will be scanned for .pcc files. A list of
files to parse will be built from the .pcc files found. Only the known filetypes will
be parsed.

If B<-inputpath> is given without any B<-outputpath>, the script parse the files, produce the
warning messages but doesn't write any new files.

=head2 B<-basepath> or B<-b>

Path to the base directory use to replace the @ character in the .PCC files. If no B<-basepath> option is given,
the value of B<-inputpath> is used to replace the @ character.

=head2 B<-systempath> or B<-s>

Path to the B<pcgen/system> used for the .lst files in B<-inputpath>. This directory should contain the
game mode files. These files will be parse to get a list of valid alignment abbreviations, valid statistic
abbriviations, valid game modes and globaly defined variables.

If the B<-gamemode> parameter is used, only the system files found in the proper game mode directory will
be parsed.

=head2 B<-outputpath> or B<-o>

Only used when B<-inputpath> is defined. B<-outputpath> define where the new files will
be writen. The directory tree from the B<-inputpath> will be reproduce as well.

Note: the output directory must be created before calling the script.

=head2 B<-outputerror> or B<-e>

Redirect STDERR to a file. All the warning and errors found by this script are printed
to STDERR.

=head2 B<-gamemode> or B<-gm>

Apply a filter on the GAMEMODE values and only read and/or reformat the files that
meet the filter.

e.g. -gamemode=35e

=head2 B<-convert> or B<-c>

Activate some conversions on the files. The converted files are written in the directory specified
by B<-outputpath>. If no B<-outputpath> is provided, the conversions messages are displayed but
no actual conversions are done.

Only one conversion may be activate at a time.

Here are the list of the valid conversions so far:

=over 12

=item B<pcgen60>

=over 16

=item * [ 1973497 ] HASSPELLFORMULA is deprecated

Use to change a number of conversions needed for stable 6.0

=back

=back

=over 12

=item B<pcgen5120>

=over 16

=item * [ 1678570 ] Correct PRESPELLTYPE syntax

Use to change a number of conversions for stable 5.12.0.

B<This has a small issue:> if ADD:blah| syntax items that contain ( ) in the elements, it will attempt to convert again.  This has only caused a few problems in the srds, but it is something to be aware of on homebrews.

- changes PRESPELLTYPE format from PRESPELLTYPE:<A>,<x>,<y> to standard PRExxx:<x>,<A>=<y>

<L<http://sourceforge.net/tracker/index.php?func=detail&aid=1678570&group_id=25576&atid=750093>>

=item * [ 1678577 ] ADD: syntax no longer uses parens

- Converts ADD:xxx(choice)y to ADD:xxx|y|choice.

<L<http://sourceforge.net/tracker/index.php?func=detail&aid=1678577&group_id=25576&atid=750093>>

=item * [ 1689538 ] Conversion: Deprecation of FOLLOWERALIGN

- Changes the FOLLOWERALIGN tag to new DOMAINS tag imbedded PREALIGN tags.
This can also be done on its own with conversion 'followeralign'.

=item * [ 1353255 ] TYPE to RACETYPE conversion

Use to change the TYPE entry in race.lst to RACETYPE if no RACETYPE is present.

<L<http://sourceforge.net/tracker/index.php?func=detail&aid=1353255&group_id=25576&atid=750093>>


=item * [ 1324519 ] ASCII characters

- Converts a few known upper level characters to ASCII standard output
characters to prevent crashes and bad output when exporting from PCGen.

<L<http://sourceforge.net/tracker/index.php?func=detail&aid=1324519&group_id=25576&atid=750093>>

=back

=item B<followeralign>

Use to change the FOLLOWERALIGN tag to the new DOMAINS tag imbedded PREALIGN tags.  This is included in conversion 5120

<L<http://sourceforge.net/tracker/index.php?func=detail&aid=1689538&group_id=25576&atid=750093>>

=item B<racetype>

Use to change the TYPE entry in race.lst to RACETYPE if no RACETYPE is present.

<L<http://sourceforge.net/tracker/index.php?func=detail&aid=1353255&group_id=25576&atid=750093>>

=item B<pcgen5713>

Use to apply the conversions that bring the .lst files from v5.7.4 of PCGEN
to vertion 5.7.13.

=over 16

=item * [ 1070084 ] Convert SPELL to SPELLS

The old SPELL tags have been deprecated and must be replaced by SPELLS. This conversion
does only part of the job since not all the information needed by the new SPELLS tags
is present in the old SPELL tags.

<L<http://sourceforge.net/tracker/index.php?func=detail&aid=1070084&group_id=36698&atid=450221>>

=item * [ 1070344 ] HITDICESIZE to HITDIE in templates.lst

The old HITDICESIZE tag has been deprecated and my be replaced by the new HITDIE. HITDICESIZE
was only present in the TEMPLATE files.

<L<http://sourceforge.net/tracker/?func=detail&atid=578825&aid=1070344&group_id=36698>>

=item * [ 731973 ] ALL: new PRECLASS syntax

All the PRECLASS tags -- including the ones found within BONUS tags -- are converted to the new
syntax -- B<PRECLASS:E<lt>number of classesE<gt>,E<lt>list of classesE<gt>=E<lt>levelE<gt>>.

Note: this conversion was done a long time ago (pcgen511) but I've reactivated it since
a lot of old PRECLASS formats have reaappeared in the data sets resently.

<L<http://sourceforge.net/tracker/index.php?func=detail&aid=731973&group_id=36698&atid=450221>>

=back

=item B<pcgen574>


Use to apply the conversions that bring the .lst files from v5.6.x or v5.7.x of PCGEN
to vertion 5.7.4.

=over 16

=item * [ 876536 ] All spell casting classes need CASTERLEVEL

Add BONUS:CASTERLEVEL tags to casting classes that do not already have it.

<L<http://sourceforge.net/tracker/index.php?func=detail&aid=876536&group_id=36698&atid=417816>>

=item * [ 1006285 ] Conversion MOVE:<number> to MOVE:Walk,<Number>

The old MOVE tags are changed to the proper syntax i.e. the syntax that
identify the type of move. In this case, we assume that if no move
type was given, the move type is Walk.

<L<http://sourceforge.net/tracker/?func=detail&atid=450221&aid=1006285&group_id=36698>>

=back

=item B<pcgen56>

Use to apply the conversions that bring the .lst files from v5.4.x of PCGEN
to vertion 5.6.

=over 16

=item * [ 892746 ] KEYS entries were changed in the main files

Attempt at automatically conerting the KEYS entries that were changed in the
main xSRD files. Not all the changes were covered though.

<L<http://sourceforge.net/tracker/index.php?func=detail&aid=892746&group_id=36698&atid=578825>>

=back

=item B<pcgen555>

Use to apply the conversions that bring the .lst files from v5.4.x of PCGEN
to vertion 5.5.5.

=over 16

=item * [ 865826 ] Remove the deprecated MOVE tag in EQUIPMENT files

The MOVE tags are removed from the equipments files since they are now useless there.

<L<http://sourceforge.net/tracker/?func=detail&atid=450221&aid=865826&group_id=36698>>

=back

=item B<pcgen541>

Use to apply the conversions that bring the .lst files from v5.4 of PCGEN
to vertion 5.4.1.

=over 16

=item * [ 845853 ] SIZE is no longer valid in the weaponprof files

SIZE is removed from WEAPONPROF files and is not replaced.

<L<http://sourceforge.net/tracker/index.php?func=detail&aid=845853&group_id=36698&atid=578825>>

=back

=item B<pcgen54>

Use this switch to convert from PCGEN 5.2 files to PCGGEN 5.4.

B<WARNING>: Do B<not> use this switch with B<CMP> files! You will break them.

=over 16

=item * [ 707325 ] PCC: GAME is now GAMEMODE

Straight change from one tag to the other. Why? Beats me but it sure helps the conversion script
buisiness to prosper :-).

<L<http://sourceforge.net/tracker/?func=detail&atid=450221&aid=707325&group_id=36698>>

=item * [ 784363 ] Add TYPE=Base.REPLACE to most BONUS:COMBAT|BAB

This change is needed to allow users to completely replace the BAB formulas with something
of their choice. For example, users can now have a customized class with
B<BONUS:COMBAT|BAB|TL|TYPE=Base> that would replace all the other Base bonus to BAB
(because it is greater).

<L<http://sourceforge.net/tracker/?func=detail&atid=450221&aid=784363&group_id=36698>>

=item * [ 825005 ] convert GAMEMODE:DnD to GAMEMODE:3e

PCGEN is droping the d20 licence. Because of that, the DnD keyword can no longer be used
as a game mode. As of PCGEN 5.4, the change to the system files were done and all the
.PCC files that linked to B<GAMEMODE:DnD> must now link to B<GAMEMODE:3e>.

<L<http://sourceforge.net/tracker/?func=detail&atid=578825&aid=825005&group_id=36698>>

B<WARNING>: Do B<not> use this conversion with B<CMP> files! You will break them.

=item * [ 831569 ] RACE:CSKILL to MONCSKILL

The new MONCSKILL tag along with the MFEAT and MONSTERCLASS are used when the default monsters
opotion is enabled in the PCGEN pref. Otherwise, the FEAT and CSKILL tags are used.

<L<http://sourceforge.net/tracker/?func=detail&atid=578825&aid=831569&group_id=36698>>

=back

=item B<pcgen534>

The following conversions were done on the .lst files between version 5.1.1 and 5.3.4 of PCGEN. See
the links for more information about the conversions in question.

=over 16

=item * [ 707325 ] PCC: GAME is now GAMEMODE

All the B<GAME> tags in the B<.PCC> files are converted to B<GAMEMODE> tags.

<L<https://sourceforge.net/tracker/?func=detail&atid=450221&aid=707325&group_id=36698>>

=item * [ 784363 ] Add TYPE=Base.REPLACE to most BONUS:COMBAT|BAB

All the B<BONUS:COMBAT|BAB> related to classes now have a B<TYPE=Base.REPLACE> added to them. This is
an important conversion if you want to mix files with the files included with PCGEN. If this is not done,
the BAB calculation will be all out of wack and you won't really know why.

<L<https://sourceforge.net/tracker/?func=detail&atid=450221&aid=784363&group_id=36698>>

=back

=item B<pcgen511>

The following conversions were done on the .lst files between version 4.3.4 and 5.1.1 of PCGEN. See
the links for more information about the conversions in question.

=over 16

=item * [ 699834 ] Incorrect loading of multiple vision types

=item * [ 728038 ] BONUS:VISION must replace VISION:.ADD

The B<VISION> tag used to allow the B<,> as a separator. This is no longer the case. Only the B<|>
can now be used as a separator. This conversion will replace all the B<,> by B<|> in the B<VISION>
tags except for those using the B<VISION:.ADD> syntax. The B<VISION:.ADD> tags are replaced by
B<BONUS:VISION> tags.

<L<https://sourceforge.net/tracker/?func=detail&atid=417816&aid=699834&group_id=36698>>
<L<https://sourceforge.net/tracker/?func=detail&atid=450221&aid=728038&group_id=36698>>

=item * [ 731973 ] ALL: new PRECLASS syntax

All the PRECLASS tags -- including the ones found within BONUS tags -- are converted to the new
syntax -- B<PRECLASS:E<lt>number of classesE<gt>,E<lt>list of classesE<gt>=E<lt>levelE<gt>>.

<L<http://sourceforge.net/tracker/index.php?func=detail&aid=731973&group_id=36698&atid=450221>>

=back

=item B<pcgen438>

The following conversions were done on the .lst files between version 4.3.3 and 4.3.4 of PCGEN. See
the links for more information about the conversions in question.

=over 16

=item * [ 686169 ] remove ATTACKS: tag

The B<ATTACKS> tags in the EQUIPMENT line types are replaced by B<BONUS:COMBAT|ATTACKS|> tags.

<L<https://sourceforge.net/tracker/?func=detail&atid=450221&aid=686169&group_id=36698>>

=item * [ 695677 ] EQUIPMENT: SLOTS for gloves, bracers and boots

The equipment of type Glove, Bracer and Boot needs a B<SLOTS:2> tag if the pair must
be equiped to give the bonus. The conversion looks at the equipement name and adds
the B<SLOTS:2> tag if the item is in the plural form. If the equipment name is in the
singular, a message is printed to show that fact but the SLOTS:2 tag is not added.

<L<https://sourceforge.net/tracker/?func=detail&atid=450221&aid=695677&group_id=36698>>

=item * PRESTAT now only accepts the format PRESTAT:1,<stat>=<n>

The B<PRESTAT> no longer accepts the old syntax. Now, every B<PRESTAT> tag needs a leading
number and coma before the stats enumaration. e.g. B<PRESTAT:STR=13> becaumes B<PRESTAT:1,STR=13>.

No tracker found.

=back

=item B<pcgen433>

This convert the references to equipement names and path that were changed with the release 4.3.3 of
PCGEN. This only changes the path values in the .PCC, the files stay in the directories they are found.

=back

=head2 B<-oldsourcetag>

From PCGen version 5.9.6, there is a new format for the SOURCExxx tag that use the tab instead of the |. prettylst.pl
automatically converts the SOURCExxx tags to the new format. The B<-oldsourcetag> option must be used if
you want to keep the old format in place.

=head2 B<-report> or B<-r>

Produce a report of the valid tags found in all the .lst and .pcc files. The report for
the invalid tags is always printed.

=head2 B<-xcheck> or B<-x>

B<This option is now on by default>

Verify the existance of values refered by other tags and produce a report of the
missing/inconsistant values.

=head2 B<-nojep>

Disable the new extractVariables function for the formula. This makes the
script use the old style formula parser.

=head2 B<-noxcheck> or B<-nx>

Disable the cross-check validations.

=head2 B<-warninglevel> or B<-wl>

Select the level of warning that should be displayed. The more critical levels include
the less critical ones. ex. B<-wl=informational> will output messages of level
informational, notice, warning and error but will not output the debug level messages.

The possible levels are:

=over 12

=item B<error>, B<err> or B<3>

Critical errors that need to be checked otherwise the resulting .lst files will not
work properly with PCGen.

=item B<warning>, B<warn> or B<4>

Important messages that should be verified. All the conversion messages are
at this level.

=item B<notice> or B<5>

The normal messages including common syntax mistakes and unknown tags.

=item B<informational>, B<info> or B<6> (default)

Can be very noisy. Include messages that warn about style, best practice and deprecated tags.

=item B<debug> or B<7>

Messages used by the programmer to debug the script.

=back

=head2 B<-exportlist>

Generate files which list objects with a reference on the file and line where they are located.
This is very useful when correcting the problems found by the -x options.

The files generated are:

=over 12

=item * class.csv

=item * domain.csv

=item * equipment.csv

=item * equipmod.csv

=item * feat.csv

=item * language.csv

=item * pcc.csv

=item * skill.csv

=item * spell.csv

=item * variable.csv

=back

=head2 B<-missingheader> or B<-mh>

List all the requested headers (with the getHeader function) that are not
defined in the %tagheader hash. When a header is not defined, the tag name
is used as is in the generated header lines.

=head2 B<-help>, B<-h> or B<-?>

Print a brief help message and exits.

=head2 B<-man>

Prints the manual page and exits. You might want to pipe the output to your favorite pager
(e.g. more).

=head2 B<-htmlhelp>

Generate a .html file with the complete documentation (as it is)
for the script and tries to display it in a browser. The display portion only
works on the Windows platform.


=head1 MANIFEST

The distribution of this script includes the following files:

=over 8

=item * prettylst.pl

The script itself.

=item * prettylst.pl.html

HMTL version of the perldoc for the script. You can generate this file
by typing C<perl prettylst.pl -htmlhelp>.

=item * prettylst.pl.css

Style sheet files for prettylst.pl.html

=item * prettylst-release-notes-135.html

The release notes for the curent version.

=item * prettylst.pl.sig

PGP signature for the script. You can get a copy of my
key here: <L<http://pgp.mit.edu:11371/pks/lookup?op=get&search=0x5187D5D2>>

=back

=head1 COPYRIGHT

Copyright 2002 to 2006 by E<Eacute>ric E<quot>Space MonkeyE<quot> Beaudoin -- <mailto:beaudoer@videotron.ca>

Copyright 2006 to 2010 by Andrew E<quot>Tir GwaithE<quot> McDougall -- <mailto:tir.gwaith@gmail.com>

Copyright 2007 by Richard Bowers

Copyright 2008 Phillip Ryan

All rights reserved.  You can redistribute and/or modify
this program under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>.

=head1 TO DO

=over 8

=item * Default monster race conversion to KITs

=item * Add better examples

=item * Add more cross-reference checks

=item * Add more Ability object checks

=back

=head1 KNOWN BUGS

=over 8

=item * When running conversions pcgen5120 on a file with ADD:xxx|, and the sub-elements contain ( ), prettylst will run the conversion script on that tag again, resulting in too many | in the tag, and no loading in pcgen.  Please be careful and make backups before running the script conversion (as usual)

=item * When running coversions pcgen5120, lots of duplicate item warnings when replacing the ADD:xxx syntax.  running the script after that will show better accuracy, but remove the replacement statements in the report.

=item * The script is still unwilling to do the coffee...

=back

