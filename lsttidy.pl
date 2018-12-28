#!/usr/bin/perl

use strict;
use warnings;
use Fatal qw( open close );             # Force some built-ins to die on error
use English qw( -no_match_vars );       # No more funky punctuation variables

my $VERSION        = "1.00.00";
my $VERSION_DATE   = "2018-12-22";
my ($PROGRAM_NAME) = "PCGen LstTidy";
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

# Expand the local library path so we can find LstTidy modules
use File::Basename qw(dirname);
use Cwd qw(abs_path);
use lib dirname(abs_path $0) . '/lib';
                        
use LstTidy::Convert qw(convertEntities);
use LstTidy::Log;
use LstTidy::LogFactory qw(getLogger);
use LstTidy::LogHeader;
use LstTidy::Options qw(getOption setOption isConversionActive);
use LstTidy::Parse qw(parseLine);
use LstTidy::Reformat qw(getEntityNameTag);
use LstTidy::Report;
use LstTidy::Validate qw(validateLine);

# Subroutines
sub FILETYPE_parse;
sub parseFile;
sub check_clear_tag_order;
sub find_full_path;
sub create_dir;
sub record_bioset_tags;
sub generate_bioset_files;
sub generate_css;

# Print version information
print STDERR "$VERSION_LONG\n";

#######################################################################
# Parameter parsing

# Parse the command line options and set the error message if there are any issues.
my $errorMessage = "\n" . LstTidy::Options::parseOptions(@ARGV);

# Test function or display variables or anything else I need.
if ( getOption('test') ) {

   print "No tests set\n";
   exit;
}

# The command line has been processed, if conversions have been requested, make
# sure the tag validity data in Reformat.pm is updated. In order to convert a
# tag it must be recognised as valid. 
LstTidy::Reformat::addTagsForConversions(); 

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

if ( getOption('help') or $LstTidy::Options::error ) {
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
   LstTidy::Parse::parseSystemFiles(getOption('systempath'));
} 

# For Some tags, validity is based on the system mode variables 
LstTidy::Parse::updateValidity();


# PCC processing
my %files = ();

# Constants for master_line_type

# Line importance (Mode)
use constant MAIN          => 1;      # Main line type for the file
use constant SUB           => 2;      # Sub line type, must be linked to a MAIN
use constant SINGLE        => 3;      # Idependant line type
use constant COMMENT       => 4;      # Comment or empty line.

# Line formatting option
use constant LINE          => 1;   # Every line formatted by itself
use constant BLOCK         => 2;   # Lines formatted as a block
use constant FIRST_COLUMN  => 3;   # Only the first column of the block
                                                # gets aligned

# Line header option
use constant NO_HEADER     => 1;   # No header
use constant LINE_HEADER   => 2;   # One header before each line
use constant BLOCK_HEADER  => 3;   # One header for the block

# Standard YES NO constants
use constant NO  => 0;
use constant YES => 1;


################################################################################
# Global variables used by the validation code

# Add pre-defined valid entities
for my $var_name (LstTidy::Parse::getValidSystemArr('vars')) {
   LstTidy::Validate::setEntityValid('DEFINE Variable', $var_name);
}

# Move these into Parse.pm, or Validate.pm whenever the code using them is moved.
my @valid_system_stats = LstTidy::Parse::getValidSystemArr('stats');

for my $stat (@valid_system_stats) {
   LstTidy::Validate::setEntityValid('DEFINE Variable', $stat);
   LstTidy::Validate::setEntityValid('DEFINE Variable', $stat . 'SCORE');
}
# Add the magical values 'ATWILL' fot the SPELLS tag's TIMES= component.
LstTidy::Validate::setEntityValid('DEFINE Variable', 'ATWILL');

# Add the magical values 'UNLIM' fot the CONTAINS tag.
LstTidy::Validate::setEntityValid('DEFINE Variable', 'UNLIM');



# this is a temporary hack until we can move the actual parse routine into LstTidy Parse

INIT {
   
   # At this point everything is compiled, so we can pass a sub ref to
   # a helper module.

   LstTidy::Parse::setParseRoutine(\&FILETYPE_parse);

}

my $tablength = 6;      # Tabulation each 6 characters

# Finds the CVS lines at the top of LST files,so we can delete them
# and replace with a single line LstTidy Header.
my $CVSPattern       = qr{\#.*CVS.*Revision}i;
my $newHeaderPattern = qr{\#.*reformatt?ed by}i;
my $LstTidyHeader    = "# $today -- reformatted by $SCRIPTNAME v$VERSION\n";

my %filesToParse;    # Will hold the file to parse (including path)
my @lines;           # Will hold all the lines of the file
my @nodifiedFiles;   # Will hold the name of the modified files

#####################################
# Verify if the inputpath was given

if (getOption('inputpath')) {

   # Construct the valid tags for all file types
   LstTidy::Reformat::constructValidTags();

   ##########################################################
   # Files that needs to be open for special conversions

   if ( isConversionActive('Export lists') ) {
      LstTidy::Report::openExportListFileHandles();
   }

   ##########################################################
   # Cross-checking must be activated for the CLASSSPELL
   # conversion to work
   if ( isConversionActive('CLASSSPELL conversion to SPELL') ) {
      setOption('xcheck', 1);
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

   $log->header(LstTidy::LogHeader::get('PCC'));

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
         my ($tag, $value) = LstTidy::Parse::extractTag(
            $pccLine, 
            'PCC', 
            $filename, 
            $INPUT_LINE_NUMBER);

         # If extractTag returns a defined value, no further processing is
         # neeeded. If value is not defined then the tag that was returned
         # should be processed further. 

         my $fullTag = (not defined $value) ?  $tag : "$tag:$value" ;

         $tag =  LstTidy::Tag->new(
            fullTag  => $fullTag,
            lineType => 'PCC', 
            file     => $filename, 
            line     => $INPUT_LINE_NUMBER,
         );

         if (not defined $value) {

            # All of the individual tag parsing and correcting happens here,
            # this potentally modifys the tag
            LstTidy::Parse::parseTag($tag);

            # If the tag has been altered, the the PCC file needs to be
            # written and the line should be overwritten.
            if ($tag->origTag ne $tag->fullRealTag) {
               $mustWrite = 1;
               $pccLines[-1] = $tag->fullRealTag;
            }
         }

         if ($tag->id) {
            if (LstTidy::Parse::isParseableFileType($tag->id)) {

               # Keep track of the filetypes found
               $foundFileType{$tag->id}++;

               # Extract the name of the LST file from the tag->value, and
               # store it back into tag->value
               $tag->value($tag->value =~ s/^([^|]*).*/$1/r);
               my $lstFile = find_full_path( $tag->value, $currentbasedir, getOption('basepath') );
               $filesToParse{$lstFile} = $tag->id;

               # Check to see if the file exists
               if ( !-e $lstFile ) {

                  $fileListMissing{$lstFile} = [ $filename, $INPUT_LINE_NUMBER ];
                  delete $filesToParse{$lstFile};

               # Remember some types of file, might need to process them first.
               } elsif (
                     $tag->id eq 'ALIGNMENT'
                  || $tag->id eq 'CLASS' 
                  || $tag->id eq 'CLASSSKILL'
                  || $tag->id eq 'CLASSSPELL' 
                  || $tag->id eq 'DOMAIN' 
                  || $tag->id eq 'SAVE'     
                  || $tag->id eq 'SPELL'
                  || $tag->id eq 'STAT'     
               ) {

                  $files{$tag->id}{$lstFile} = 1;

                  my $commentOutPCC = 
                     (isConversionActive('CLASSSPELL conversion to SPELL') && $tag eq 'CLASSSPELL') || 
                     (isConversionActive('CLASSSKILL conversion to CLASS') && $tag eq 'CLASSSKILL');

                  # When doing either of these two conversions, the original
                  # PCC line must be commented out
                  if ($commentOutPCC) {

                     push @pccLines, q{#} . pop @pccLines;
                     $mustWrite = 1;

                     $log->warning(
                        qq{Commenting out "$pccLines[$#pccLines]"},
                        $filename,
                        $INPUT_LINE_NUMBER
                     );
                  }
               }

               delete $fileListNotPCC{$lstFile} if exists $fileListNotPCC{$lstFile};
               $found{'lst'} = 1;

            } elsif ( $tag->id =~ m/^\#/ ) {

               if ($tag->id =~ $newHeaderPattern) {
                  $found{'header'} = 1;
               }

            } elsif (LstTidy::Reformat::isValidTag('PCC', $tag->id)) {

               # All the tags that do not have a file should be caught here

               # Get the SOURCExxx tags for future ref.
               if (isConversionActive('SOURCE line replacement')
                  && (  $tag->id eq 'SOURCELONG'
                     || $tag->id eq 'SOURCESHORT'
                     || $tag->id eq 'SOURCEWEB'
                     || $tag->id eq 'SOURCEDATE' ) ) 
               {
                  my $path = File::Basename::dirname($filename);

                  if ( exists $source_tags{$path}{$tag->id} && $path !~ /custom|altpcc/i ) {

                     $log->notice(
                        $tag->id . " already found for $path",
                        $filename,
                        $INPUT_LINE_NUMBER
                     );

                  } else {
                     $source_tags{$path}{$tag->id} = $tag->fullRealTag;
                  }

                  # For the PCC report
                  if ( $tag->id eq 'SOURCELONG' ) {
                     $found{'source long'} = $tag->value;
                  } elsif ( $tag->id eq 'SOURCESHORT' ) {
                     $found{'source short'} = $tag->value;
                  }

               } elsif ( $tag->id eq 'GAMEMODE' ) {

                  # Verify that the GAMEMODEs are valid
                  # and match the filer.
                  $found{'gamemode'} = $tag->value;       # The GAMEMODE tag we found
                  my @modes = split /[|]/, $tag->value;

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
                        if ( ! LstTidy::Parse::isValidGamemode($mode) ) {
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

               } elsif ( $tag->id eq 'BOOKTYPE' || $tag->id eq 'TYPE' ) {

                  # Found a TYPE tag
                  $found{'book type'} = 1;

               } elsif ( $tag->id eq 'GAME' && isConversionActive('PCC:GAME to GAMEMODE') ) {

                  $value = $tag->value;

                  # [ 707325 ] PCC: GAME is now GAMEMODE
                  $pccLines[-1] = "GAMEMODE:$value";
                  $log->warning(
                     q{Replacing "} . $tag->fullRealTag . qq{" by "GAMEMODE:$value"},
                     $filename,
                     $INPUT_LINE_NUMBER
                  );
                  $found{'gamemode'} = $tag->value;
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

      if (isConversionActive('CLASSSPELL conversion to SPELL')) {

         if ($foundFileType{'CLASSSPELL'} && !$foundFileType{'SPELL'}) {
            $log->warning(
               'No SPELL file found, create one.',
               $filename
            );
         }
      }

      if (isConversionActive('CLASSSKILL conversion to CLASS')) {

         if ( $foundFileType{'CLASSSKILL'} && !$foundFileType{'CLASS'} ) {
            $log->warning(
               'No CLASS file found, create one.',
               $filename
            );
         }
      }

      if ( !$found{'book type'} && $found{'lst'} ) {
         $log->notice( 'No BOOKTYPE tag found', $filename );
      }

      if (!$found{'gamemode'}) {
         $log->notice( 'No GAMEMODE tag found', $filename );
      }

      if ( $found{'gamemode'} && getOption('exportlist') ) {
         LstTidy::Report::printToExportList('PCC', qq{"$found{'source long'}","$found{'source short'}","$found{'gamemode'}","$filename"\n});
      }

      # Do we copy the .PCC???
      if ( getOption('outputpath') && ( $mustWrite || !$found{'header'} ) && LstTidy::Parse::isWriteableFileType("PCC") ) {
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

      $log->header(LstTidy::LogHeader::get('Missing LST'));

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

      $log->header(LstTidy::LogHeader::get('Unreferenced'));

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

$log->header(LstTidy::LogHeader::get('LST'));

my @filesToParse_sorted = ();
my %temp_filesToParse   = %filesToParse;

if ( isConversionActive('SPELL:Add TYPE tags') ) {

   # The CLASS files must be put at the start of the
   # filesToParse_sorted array in order for them
   # to be dealt with before the SPELL files.

   for my $class_file ( sort keys %{ $files{CLASS} } ) {
      push @filesToParse_sorted, $class_file;
      delete $temp_filesToParse{$class_file};
   }
}

if ( isConversionActive('CLASSSPELL conversion to SPELL') ) {

   # The CLASS and DOMAIN files must be put at the start of the
   # filesToParse_sorted array in order for them
   # to be dealt with before the CLASSSPELL files.
   # The CLASSSPELL needs to be processed before the SPELL files.

   # CLASS first
   for my $filetype (qw(CLASS DOMAIN CLASSSPELL)) {
      for my $file_name ( sort keys %{ $files{$filetype} } ) {
         push @filesToParse_sorted, $file_name;
         delete $temp_filesToParse{$file_name};
      }
   }
}

if ( keys %{ $files{SPELL} } ) {

   # The SPELL file must be loaded before the EQUIPMENT
   # in order to properly generate the EQMOD tags or do
   # the Spell.MOD conversion to SPELLLEVEL.

   for my $file_name ( sort keys %{ $files{SPELL} } ) {
      push @filesToParse_sorted, $file_name;
      delete $temp_filesToParse{$file_name};
   }
}

if ( isConversionActive('CLASSSKILL conversion to CLASS') ) {

   # The CLASSSKILL files must be put at the start of the
   # filesToParse_sorted array in order for them
   # to be dealt with before the CLASS files
   for my $file_name ( sort keys %{ $files{CLASSSKILL} } ) {
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

      (my $lines, $filetype) = LstTidy::Parse::normaliseFile($buffer);
      @lines = @$lines;

   } else {

      # We read only what we know needs to be processed
      my $parseable = LstTidy::Parse::isParseableFileType($filesToParse{$file});

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

         (my $lines, $filetype) = LstTidy::Parse::normaliseFile($buffer);
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

   # While the first line is any sort of commant about pretty lst or LstTidy,
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

   my $parser = LstTidy::Parse::isParseableFileType($filesToParse{$file});

   if ( ref($parser) eq "CODE" ) {

      # The overwhelming majority of checking, correcting and reformatting happens in this operation
      my ($newlines_ref) = &{ $parser }( $filesToParse{$file}, \@lines, $file);

      # Let's remove the tralling white spaces
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

      if (!LstTidy::Parse::isWriteableFileType($filesToParse{$file})) {
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
      print {$write_fh} $LstTidyHeader;

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
# Generate the new BIOSET files

if ( isConversionActive('BIOSET:generate the new files') ) {
        print STDERR "\n================================================================\n";
        print STDERR "List of new BIOSET files generated\n";
        print STDERR "----------------------------------------------------------------\n";

        generate_bioset_files();
}

###########################################
# Print a report with the modified files
if ( getOption('outputpath') && scalar(@nodifiedFiles) ) {

   my $outputpath = getOption('outputpath');

   if ($^O eq "MSWin32") {
      $outputpath =~ tr{/}{\\} 
   }

   $log->header(LstTidy::LogHeader::get('Created'), getOption('outputpath'));

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

if ( isConversionActive('Generate BONUS and PRExxx report') ) {
   LstTidy::Report::reportBonus();
}

if (getOption('report')) {
   LstTidy::Report::report('Valid');
}

if (LstTidy::Report::foundInvalidTags()) {
   LstTidy::Report::report('Invalid');
}

if (getOption('xcheck')) {
   LstTidy::Report::doXCheck();
}

#########################################
# Close the files that were opened for
# special conversion

if (isConversionActive('Export lists')) {
   LstTidy::Report::closeExportListFileHandles();
}

LstTidy::Validate::dumpValidEntities();

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
# FILETYPE_parse
# --------------
#
# This function uses the information of LstTidy::Parse::parseControl to
# identify the curent line type and parse it.
#
# Parameters: $fileType  = The type of the file has defined by the .PCC file
#             $lines_ref = Reference to an array containing all the lines of the file
#             $file      = File name to use with the logger

sub FILETYPE_parse {
   my ($fileType, $lines_ref, $file) = @_;

   ##################################################
   # Working variables

   my $curent_linetype = "";
   my $last_main_line  = -1;

   my $curent_entity;

   my @newlines;   # New line generated

   ##################################################
   ##################################################
   # Phase I - Split line in tokens and parse
   #               the tokens

   my $line = 1;
   LINE:
   for my $thisLine (@ {$lines_ref} ) {

      my $line_info;
     
      # Convert the non-ascii character in the line if that conversion is
      # active, otherwise just copy it. 
      my $new_line = isConversionActive('ALL:Fix Common Extended ASCII')
                        ? convertEntities($thisLine)
                        : $thisLine;

      # Remove spaces at the end of the line
      $new_line =~ s/\s+$//;

      # Remove spaces at the begining of the line
      $new_line =~ s/^\s+//;

      # Skip comments and empty lines
      if ( length($new_line) == 0 || $new_line =~ /^\#/ ) {

         # We push the line as is.
         push @newlines, [ $curent_linetype, $new_line, $last_main_line, undef, undef, ];
         next LINE;
      }
            
      ($line_info, $curent_entity) = LstTidy::Parse::matchLineType($new_line, $fileType); 

      # If we didn't find a record with info how to parse this line
      if ( ! defined $line_info ) {
         $log->warning(
            qq(Can\'t find the line type for "$new_line"),
            $file,
            $line
         );

         # We push the line as is.
         push @newlines, [ $curent_linetype, $new_line, $last_main_line, undef, undef, ];
         next LINE;
      }

      # What type of line is it?
      $curent_linetype = $line_info->{Linetype};
      if ( $line_info->{Mode} == MAIN ) {

         $last_main_line = $line - 1;

      } elsif ( $line_info->{Mode} == SUB ) {

         if ($last_main_line == -1) {
            $log->warning(
               qq{SUB line "$curent_linetype" is not preceded by a MAIN line},
               $file,
               $line
            )
         }

      } elsif ( $line_info->{Mode} == SINGLE ) {

         $last_main_line = -1;

      } else {

         die qq(Invalid type for $curent_linetype);
      }

      # Identify the deprecated tags.
      LstTidy::Validate::scanForDeprecatedTags( $new_line, $curent_linetype, $file, $line );

      # Split the line in tokens
      my %line_tokens;

      # By default, the tab character is used
      my $sep = $line_info->{SepRegEx} || qr(\t+);

      # We split the tokens, strip the spaces and silently remove the empty tags
      # (empty tokens are the result of [tab][space][tab] type of chracter
      # sequences).
      # [ 975999 ] [tab][space][tab] breaks prettylst
      my @tokens = grep { $_ ne q{} } map { s{ \A \s* | \s* \z }{}xmsg; $_ } split $sep, $new_line;

      #First, we deal with the tag-less columns
      COLUMN:
      for my $column ( getEntityNameTag($curent_linetype) ) {

         # If this line type does not have tagless first entry
         if (not defined $column) {
            last COLUMN;
         }

         # If the line has no tokens        
         if ( scalar @tokens == 0 ) {
            last COLUMN;
         }
         
         # Grab the token from the front of the line 
         my $token = shift @tokens;

         # We remove the enclosing quotes if any
         if ($token =~ s/^"(.*)"$/$1/) {
            $log->warning(
               qq{Removing quotes around the '$token' tag},
               $file,
               $line
            )
         }

         # and add it to line_tokens
         $line_tokens{$column} = [$token];

         # Statistic gathering
         LstTidy::Report::incCountValidTags($curent_linetype, $column);

         if ( index( $column, '000' ) == 0 && $line_info->{ValidateKeep} ) {
            my $exit = LstTidy::Parse::process000($line_info, $token, $curent_linetype, $file, $line);
            last COLUMN if $exit;
         }
      }

      #Second, let's parse the regular columns
      for my $token (@tokens) {

         my ( $tag, $value ) = LstTidy::Parse::extractTag($token, $curent_linetype, $file, $line );

         # if extractTag returns a defined value, no further processing is
         # neeeded. If tag is defined but value is not, then the tag that was
         # returned is the cleaned token and should be processed further.
         if ($tag && not defined $value) {

            my $tag =  LstTidy::Tag->new(
               fullTag  => $tag,
               lineType => $curent_linetype,
               file     => $file,
               line     => $line,
            );

            # Potentally modify the tag
            LstTidy::Parse::parseTag( $tag );

            my $key = $tag->realId;

            if ( exists $line_tokens{$key} && ! LstTidy::Reformat::isValidMultiTag($curent_linetype, $key) ) {
               $log->notice(
                  qq{The tag "$key" should not be used more than once on the same $curent_linetype line.\n},
                  $file,
                  $line
               );
            }

            $line_tokens{$key} = exists $line_tokens{$key} ? [ @{ $line_tokens{$key} }, $tag->fullRealTag ] : [$tag->fullRealTag];

         } else {

            $log->warning( "No tags in \"$token\"\n", $file, $line );
            $line_tokens{$token} = $token;
         }
      }

      my $newline = [
         $curent_linetype,
         \%line_tokens,
         $last_main_line,
         $curent_entity,
         $line_info,
      ];

      ############################################################
      ######################## Conversion ########################
      # We manipulate the tags for the line here
      # This function call will parse individual lines, which will
      # in turn parse the tags within the lines.

      parseLine($curent_linetype, \%line_tokens, $file, $line, $newline);

      ############################################################
      # Validate the line
      if (getOption('xcheck')) {
         validateLine($curent_linetype, \%line_tokens, $file, $line) 
      };

      ############################################################
      # .CLEAR order verification
      check_clear_tag_order(\%line_tokens, $file, $line);

      #Last, we put the tokens and other line info in the @newlines array
      push @newlines, $newline;

   }
   continue { $line++ }

        #####################################################
        #####################################################
        # We find all the header lines
        for ( my $line_index = 0; $line_index < @newlines; $line_index++ ) {
                my $curent_linetype = $newlines[$line_index][0];
                my $line_tokens = $newlines[$line_index][1];
                my $next_linetype;
                $next_linetype = $newlines[ $line_index + 1 ][0]
                if $line_index + 1 < @newlines;

                # A header line either begins with the curent line_type header
                # or the next line header.
                #
                # Only comment -- $line_token is not a hash --  can be header lines
                if ( ref($line_tokens) ne 'HASH' ) {

                        # We are on a comment line, we need to find the
                        # curent and the next line header.



                        # Curent header
                        my $this_header =
                                $curent_linetype
                                ? LstTidy::Parse::getHeader( @{LstTidy::Reformat::getLineTypeOrder($curent_linetype)}[0], $curent_linetype )
                                : "";

                        # Next line header
                        my $next_header =
                                $next_linetype
                                ? LstTidy::Parse::getHeader( @{LstTidy::Reformat::getLineTypeOrder($next_linetype)}[0], $next_linetype )
                                : "";

                        if (   ( $this_header && index( $line_tokens, $this_header ) == 0 )
                                || ( $next_header && index( $line_tokens, $next_header ) == 0 ) )
                        {

                                # It is a header, let's tag it as such.
                                $newlines[$line_index] = [ 'HEADER', $line_tokens, ];
                        } else {

                                # It is just a comment, we won't botter with it ever again.
                                $newlines[$line_index] = $line_tokens;
                        }
                }
        }


        #################################################################
        ######################## Conversion #############################
        # We manipulate the tags for the whole file here

        parseFile(\@newlines, $fileType, $file);

        ##################################################
        ##################################################
        # Phase II - Reformating the lines

        # No reformating needed?
        return $lines_ref unless getOption('outputpath') && LstTidy::Parse::isWriteableFileType($fileType);

        # Now on to all the non header lines.
        CORE_LINE:
        for ( my $line_index = 0; $line_index < @newlines; $line_index++ ) {

                # We skip the text lines and the header lines
                next CORE_LINE
                if ref( $newlines[$line_index] ) ne 'ARRAY'
                || $newlines[$line_index][0] eq 'HEADER';

                my $line_ref = $newlines[$line_index];

                my ($curent_linetype, $line_tokens, $last_main_line, $curent_entity, $line_info) = @$line_ref;

                my $newline = "";

                # If the separator is not a tab, with just join the
                # tag in order
                my $sep = $line_info->{Sep} || "\t";
                if ( $sep ne "\t" ) {

                # First, the tag known in masterOrder
                for my $tag ( @{LstTidy::Reformat::getLineTypeOrder($curent_linetype)} ) {
                        if ( exists $line_tokens->{$tag} ) {
                                $newline .= join $sep, @{ $line_tokens->{$tag} };
                                $newline .= $sep;
                                delete $line_tokens->{$tag};
                        }
                }

                # The remaining tag are not in the masterOrder list
                for my $tag ( sort keys %$line_tokens ) {
                        $newline .= join $sep, @{ $line_tokens->{$tag} };
                        $newline .= $sep;
                }

                # We remove the extra separator
                for ( my $i = 0; $i < length($sep); $i++ ) {
                        chop $newline;
                }

                # We replace line_ref with the new line
                $newlines[$line_index] = $newline;
                next CORE_LINE;
                }

                ##################################################
                # The line must be formatted according to its
                # TYPE, FORMAT and HEADER parameters.

                my $mode   = $line_info->{Mode};
                my $format = $line_info->{Format};
                my $header = $line_info->{Header};

                if ( $mode == SINGLE || $format == LINE ) {

                # LINE: the line if formatted independently.
                #               The FORMAT is ignored.
                if ( $header == NO_HEADER ) {

                        # Just put the line in order and with a single tab
                        # between the columns. If there is a header in the previous
                        # line, we remove it.

                        # First, the tag known in masterOrder
                        for my $tag ( @{LstTidy::Reformat::getLineTypeOrder($curent_linetype)} ) {
                                if ( exists $line_tokens->{$tag} ) {
                                $newline .= join $sep, @{ $line_tokens->{$tag} };
                                $newline .= $sep;
                                delete $line_tokens->{$tag};
                                }
                        }

                        # The remaining tag are not in the masterOrder list
                        for my $tag ( sort keys %$line_tokens ) {
                                $newline .= join $sep, @{ $line_tokens->{$tag} };
                                $newline .= $sep;
                        }

                        # We remove the extra separator
                        for ( my $i = 0; $i < length($sep); $i++ ) {
                                chop $newline;
                        }

                        # If there was an header before this line, we remove it
                        if ( ref( $newlines[ $line_index - 1 ] ) eq 'ARRAY'
                                && $newlines[ $line_index - 1 ][0] eq 'HEADER' )
                        {
                                splice( @newlines, $line_index - 1, 1 );
                                $line_index--;
                        }

                        # Replace the array with the new line
                        $newlines[$line_index] = $newline;
                        next CORE_LINE;
                }
                elsif ( $header == LINE_HEADER ) {

                        # Put the line with a header in front of it.
                        my %col_length  = ();
                        my $header_line = "";
                        my $line_entity = "";

                        # Find the length for each column
                        $col_length{$_} = mylength( $line_tokens->{$_} ) for ( keys %$line_tokens );

                        # Find the columns order and build the header and
                        # the curent line
                        TAG_NAME:
                        for my $tag ( @{LstTidy::Reformat::getLineTypeOrder($curent_linetype)} ) {

                                # We skip the tag is not present
                                next TAG_NAME if !exists $col_length{$tag};

                                # The first tag is the line entity and most be kept
                                $line_entity = $line_tokens->{$tag}[0] unless $line_entity;

                                # What is the length of the column?
                                my $header_text   = LstTidy::Parse::getHeader( $tag, $curent_linetype );
                                my $header_length = mylength($header_text);
                                my $col_length    = $header_length > $col_length{$tag}
                                                       ? $header_length
                                                       : $col_length{$tag};

                                # Round the col_length up to the next tab
                                $col_length = $tablength * ( int( $col_length / $tablength ) + 1 );

                                # The header
                                my $tab_to_add = int( ( $col_length - $header_length ) / $tablength )
                                + ( ( $col_length - $header_length ) % $tablength ? 1 : 0 );
                                $header_line .= $header_text . $sep x $tab_to_add;

                                # The line
                                $tab_to_add = int( ( $col_length - $col_length{$tag} ) / $tablength )
                                + ( ( $col_length - $col_length{$tag} ) % $tablength ? 1 : 0 );
                                $newline .= join $sep, @{ $line_tokens->{$tag} };
                                $newline .= $sep x $tab_to_add;

                                # Remove the tag we just dealt with
                                delete $line_tokens->{$tag};
                        }

                        # Add the tags that were not in the masterOrder
                        for my $tag ( sort keys %$line_tokens ) {

                                # What is the length of the column?
                                my $header_text   = LstTidy::Parse::getHeader( $tag, $curent_linetype );
                                my $header_length = mylength($header_text);
                                my $col_length  =
                                        $header_length > $col_length{$tag}
                                ? $header_length
                                : $col_length{$tag};

                                # Round the col_length up to the next tab
                                $col_length = $tablength * ( int( $col_length / $tablength ) + 1 );

                                # The header
                                my $tab_to_add = int( ( $col_length - $header_length ) / $tablength )
                                + ( ( $col_length - $header_length ) % $tablength ? 1 : 0 );
                                $header_line .= $header_text . $sep x $tab_to_add;

                                # The line
                                $tab_to_add = int( ( $col_length - $col_length{$tag} ) / $tablength )
                                + ( ( $col_length - $col_length{$tag} ) % $tablength ? 1 : 0 );
                                $newline .= join $sep, @{ $line_tokens->{$tag} };
                                $newline .= $sep x $tab_to_add;
                        }

                        # Remove the extra separators (tabs) at the end of both lines
                        $header_line =~ s/$sep$//g;
                        $newline        =~ s/$sep$//g;

                        # Put the header in place
                        if ( ref( $newlines[ $line_index - 1 ] ) eq 'ARRAY'
                                && $newlines[ $line_index - 1 ][0] eq 'HEADER' )
                        {

                                # We replace the existing header
                                $newlines[ $line_index - 1 ] = $header_line;
                        }
                        else {

                                # We add the header before the line
                                splice( @newlines, $line_index++, 0, $header_line );
                        }

                        # Add an empty line in front of the header unless
                        # there is already one or the previous line
                        # match the line entity.
                        if ( $newlines[ $line_index - 2 ] ne ''
                                && index( $newlines[ $line_index - 2 ], $line_entity ) != 0 )
                        {
                                splice( @newlines, $line_index - 1, 0, '' );
                                $line_index++;
                        }

                        # Replace the array with the new line
                        $newlines[$line_index] = $newline;
                        next CORE_LINE;
                }
                else {

                        # Invalid option
                        die "Invalid \%LstTidy::Parse::parseControl options: $fileType:$curent_linetype:$mode:$header";
                }
                }
                elsif ( $mode == MAIN ) {
                if ( $format == BLOCK ) {
                        #####################################
                        # All the main lines must be found
                        # up until a different main line type
                        # or a ###Block comment.
                        my @main_lines;
                        my $main_linetype = $curent_linetype;

                        BLOCK_LINE:
                        for ( my $index = $line_index; $index < @newlines; $index++ ) {

                                # If the line_type  change or
                                # if a '###Block' comment is found,
                                # we are out of the block
                                last BLOCK_LINE
                                if ( ref( $newlines[$index] ) eq 'ARRAY'
                                && ref $newlines[$index][4] eq 'HASH'
                                && $newlines[$index][4]{Mode} == MAIN
                                && $newlines[$index][0] ne $main_linetype )
                                || ( ref( $newlines[$index] ) ne 'ARRAY'
                                && index( lc( $newlines[$index] ), '###block' ) == 0 );

                                # Skip the lines already dealt with
                                next BLOCK_LINE
                                if ref( $newlines[$index] ) ne 'ARRAY'
                                || $newlines[$index][0] eq 'HEADER';

                                push @main_lines, $index
                                if $newlines[$index][4]{Mode} == MAIN;
                        }

                        #####################################
                        # We find the length of each tag for the block
                        my %col_length;
                        for my $block_line (@main_lines) {
                                for my $tag ( keys %{ $newlines[$block_line][1] } ) {
                                my $col_length = mylength( $newlines[$block_line][1]{$tag} );
                                $col_length{$tag} = $col_length
                                        if !exists $col_length{$tag} || $col_length > $col_length{$tag};
                                }
                        }

                        if ( $header != NO_HEADER ) {

                                # We add the length of the headers if needed.
                                for my $tag ( keys %col_length ) {
                                my $length = mylength( LstTidy::Parse::getHeader( $tag, $fileType ) );

                                $col_length{$tag} = $length if $length > $col_length{$tag};
                                }
                        }

                        #####################################
                        # Find the columns order
                        my %seen;
                        my @col_order;

                        # First, the columns included in masterOrder
                        for my $tag ( @{LstTidy::Reformat::getLineTypeOrder($curent_linetype)} ) {
                                push @col_order, $tag if exists $col_length{$tag};
                                $seen{$tag}++;
                        }

                        # Put the unknown columns at the end
                        for my $tag ( sort keys %col_length ) {
                                push @col_order, $tag unless $seen{$tag};
                        }

                        # Each of the block lines must be reformated
                        for my $block_line (@main_lines) {
                                my $newline;

                                for my $tag (@col_order) {
                                my $col_max_length
                                        = $tablength * ( int( $col_length{$tag} / $tablength ) + 1 );

                                # Is the tag present in this line?
                                if ( exists $newlines[$block_line][1]{$tag} ) {
                                        my $curent_length = mylength( $newlines[$block_line][1]{$tag} );

                                        my $tab_to_add
                                                = int( ( $col_max_length - $curent_length ) / $tablength )
                                                + ( ( $col_max_length - $curent_length ) % $tablength ? 1 : 0 );
                                        $newline .= join $sep, @{ $newlines[$block_line][1]{$tag} };
                                        $newline .= $sep x $tab_to_add;
                                }
                                else {

                                        # We pad with tabs
                                        $newline .= $sep x ( $col_max_length / $tablength );
                                }
                                }

                                # We remove the extra $sep at the end
                                $newline =~ s/$sep+$//;

                                # We replace the array with the new line
                                $newlines[$block_line] = $newline;
                        }

                        if ( $header == NO_HEADER ) {

                                # If there are header before any of the block line,
                                # we need to remove them
                                for my $block_line ( reverse @main_lines ) {
                                if ( ref( $newlines[ $block_line - 1 ] ) eq 'ARRAY'
                                        && $newlines[ $block_line - 1 ][0] eq 'HEADER' )
                                {
                                        splice( @newlines, $block_line - 1, 1 );
                                        $line_index--;
                                }
                                }
                        }
                        elsif ( $header == LINE_HEADER ) {
                                die "MAIN:BLOCK:LINE_HEADER not implemented yet";
                        }
                        elsif ( $header == BLOCK_HEADER ) {

                                # We must add the header line at the top of the block
                                # and anywhere else we find them whitin the block.

                                my $header_line;
                                for my $tag (@col_order) {

                                # Round the col_length up to the next tab
                                my $col_max_length
                                        = $tablength * ( int( $col_length{$tag} / $tablength ) + 1 );
                                my $curent_header = LstTidy::Parse::getHeader( $tag, $main_linetype );
                                my $curent_length = mylength($curent_header);
                                my $tab_to_add  = int( ( $col_max_length - $curent_length ) / $tablength )
                                        + ( ( $col_max_length - $curent_length ) % $tablength ? 1 : 0 );
                                $header_line .= $curent_header . $sep x $tab_to_add;
                                }

                                # We remove the extra $sep at the end
                                $header_line =~ s/$sep+$//;

                                # Before the top of the block
                                my $need_top_header = NO;
                                if ( ref( $newlines[ $main_lines[0] - 1 ] ) ne 'ARRAY'
                                || $newlines[ $main_lines[0] - 1 ][0] ne 'HEADER' )
                                {
                                $need_top_header = YES;
                                }

                                # Anywhere in the block
                                for my $block_line (@main_lines) {
                                if ( ref( $newlines[ $block_line - 1 ] ) eq 'ARRAY'
                                        && $newlines[ $block_line - 1 ][0] eq 'HEADER' )
                                {
                                        $newlines[ $block_line - 1 ] = $header_line;
                                }
                                }

                                # Add a header line at the top of the block
                                if ($need_top_header) {
                                splice( @newlines, $main_lines[0], 0, $header_line );
                                $line_index++;
                                }

                        }
                }
                else {
                        die "Invalid \%LstTidy::Parse::parseControl format: $fileType:$curent_linetype:$mode:$header";
                }
                }
                elsif ( $mode == SUB ) {
                if ( $format == LINE ) {
                        die "SUB:LINE not implemented yet";
                }
                elsif ( $format == BLOCK || $format == FIRST_COLUMN ) {
                        #####################################
                        # Need to find all the file in the SUB BLOCK i.e. same
                        # line type within two MAIN lines.
                        # If we encounter a ###Block comment, that's the end
                        # of the block
                        my @sub_lines;
                        my $begin_block  = $last_main_line;
                        my $sub_linetype = $curent_linetype;

                        BLOCK_LINE:
                        for ( my $index = $line_index; $index < @newlines; $index++ ) {

                                # If the last_main_line change or
                                # if a '###Block' comment is found,
                                # we are out of the block
                                last BLOCK_LINE
                                if ( ref( $newlines[$index] ) eq 'ARRAY'
                                && $newlines[$index][0] ne 'HEADER'
                                && $newlines[$index][2] != $begin_block )
                                || ( ref( $newlines[$index] ) ne 'ARRAY'
                                && index( lc( $newlines[$index] ), '###block' ) == 0 );

                                # Skip the lines already dealt with
                                next BLOCK_LINE
                                if ref( $newlines[$index] ) ne 'ARRAY'
                                || $newlines[$index][0] eq 'HEADER';

                                push @sub_lines, $index
                                if $newlines[$index][0] eq $curent_linetype;
                        }

                        #####################################
                        # We find the length of each tag for the block
                        my %col_length;
                        for my $block_line (@sub_lines) {
                                for my $tag ( keys %{ $newlines[$block_line][1] } ) {
                                my $col_length = mylength( $newlines[$block_line][1]{$tag} );
                                $col_length{$tag} = $col_length
                                        if !exists $col_length{$tag} || $col_length > $col_length{$tag};
                                }
                        }

                        if ( $header == BLOCK_HEADER ) {

                                # We add the length of the headers if needed.
                                for my $tag ( keys %col_length ) {
                                my $length = mylength( LstTidy::Parse::getHeader( $tag, $fileType ) );

                                $col_length{$tag} = $length if $length > $col_length{$tag};
                                }
                        }

                        #####################################
                        # Find the columns order
                        my %seen;
                        my @col_order;

                        # First, the columns included in masterOrder
                        for my $tag ( @{LstTidy::Reformat::getLineTypeOrder($curent_linetype)} ) {
                                push @col_order, $tag if exists $col_length{$tag};
                                $seen{$tag}++;
                        }

                        # Put the unknown columns at the end
                        for my $tag ( sort keys %col_length ) {
                                push @col_order, $tag unless $seen{$tag};
                        }

                        # Each of the block lines must be reformated
                        if ( $format == BLOCK ) {
                                for my $block_line (@sub_lines) {
                                my $newline;

                                for my $tag (@col_order) {
                                        my $col_max_length
                                                = $tablength * ( int( $col_length{$tag} / $tablength ) + 1 );

                                        # Is the tag present in this line?
                                        if ( exists $newlines[$block_line][1]{$tag} ) {
                                                my $curent_length = mylength( $newlines[$block_line][1]{$tag} );

                                                my $tab_to_add
                                                = int( ( $col_max_length - $curent_length ) / $tablength )
                                                + ( ( $col_max_length - $curent_length ) % $tablength ? 1 : 0 );
                                                $newline .= join $sep, @{ $newlines[$block_line][1]{$tag} };
                                                $newline .= $sep x $tab_to_add;
                                        }
                                        else {

                                                # We pad with tabs
                                                $newline .= $sep x ( $col_max_length / $tablength );
                                        }
                                }

                                # We replace the array with the new line
                                $newlines[$block_line] = $newline;
                                }
                        }
                        else {

                                # $format == FIRST_COLUMN

                                for my $block_line (@sub_lines) {
                                my $newline;
                                my $first_column = YES;
                                my $tab_to_add;

                                TAG:
                                for my $tag (@col_order) {

                                        # Is the tag present in this line?
                                        next TAG if !exists $newlines[$block_line][1]{$tag};

                                        if ($first_column) {
                                                my $col_max_length
                                                = $tablength * ( int( $col_length{$tag} / $tablength ) + 1 );
                                                my $curent_length = mylength( $newlines[$block_line][1]{$tag} );

                                                $tab_to_add
                                                = int( ( $col_max_length - $curent_length ) / $tablength )
                                                + ( ( $col_max_length - $curent_length ) % $tablength ? 1 : 0 );

                                                # It's no longer the first column
                                                $first_column = NO;
                                        }
                                        else {
                                                $tab_to_add = 1;
                                        }

                                        $newline .= join $sep, @{ $newlines[$block_line][1]{$tag} };
                                        $newline .= $sep x $tab_to_add;
                                }

                                # We replace the array with the new line
                                $newlines[$block_line] = $newline;
                                }
                        }

                        if ( $header == NO_HEADER ) {

                                # If there are header before any of the block line,
                                # we need to remove them
                                for my $block_line ( reverse @sub_lines ) {
                                if ( ref( $newlines[ $block_line - 1 ] ) eq 'ARRAY'
                                        && $newlines[ $block_line - 1 ][0] eq 'HEADER' )
                                {
                                        splice( @newlines, $block_line - 1, 1 );
                                        $line_index--;
                                }
                                }
                        }
                        elsif ( $header == LINE_HEADER ) {
                                die "SUB:BLOCK:LINE_HEADER not implemented yet";
                        }
                        elsif ( $header == BLOCK_HEADER ) {

                                # We must add the header line at the top of the block
                                # and anywhere else we find them whitin the block.

                                my $header_line;
                                for my $tag (@col_order) {

                                # Round the col_length up to the next tab
                                my $col_max_length
                                        = $tablength * ( int( $col_length{$tag} / $tablength ) + 1 );
                                my $curent_header = LstTidy::Parse::getHeader( $tag, $sub_linetype );
                                my $curent_length = mylength($curent_header);
                                my $tab_to_add  = int( ( $col_max_length - $curent_length ) / $tablength )
                                        + ( ( $col_max_length - $curent_length ) % $tablength ? 1 : 0 );
                                $header_line .= $header . $sep x $tab_to_add;
                                }

                                # Before the top of the block
                                my $need_top_header = NO;
                                if ( ref( $newlines[ $sub_lines[0] - 1 ] ) ne 'ARRAY'
                                || $newlines[ $sub_lines[0] - 1 ][0] ne 'HEADER' )
                                {
                                $need_top_header = YES;
                                }

                                # Anywhere in the block
                                for my $block_line (@sub_lines) {
                                if ( ref( $newlines[ $block_line - 1 ] ) eq 'ARRAY'
                                        && $newlines[ $block_line - 1 ][0] eq 'HEADER' )
                                {
                                        $newlines[ $block_line - 1 ] = $header_line;
                                }
                                }

                                # Add a header line at the top of the block
                                if ($need_top_header) {
                                splice( @newlines, $sub_lines[0], 0, $header_line );
                                $line_index++;
                                }

                        }
                        else {
                                die "Invalid \%LstTidy::Parse::parseControl $curent_linetype:$mode:$format:$header";
                        }
                }
                else {
                        die "Invalid \%LstTidy::Parse::parseControl $curent_linetype:$mode:$format:$header";
                }
                }
                else {
                die "Invalid \%LstTidy::Parse::parseControl mode: $fileType:$curent_linetype:$mode";
                }

        }

        # If there are header lines remaining, we keep the old value
        for (@newlines) {
                $_ = $_->[1] if ref($_) eq 'ARRAY' && $_->[0] eq 'HEADER';
        }

        return \@newlines;

}

###############################################################
# parseFile
# ------------------------
#
# This function does additional parsing on each file once
# they have been seperated in lines of tags.
#
# Most commun use is for addition, conversion or removal of tags.
#
# Paramter: $lines_ref  Ref to an array containing lines of tags
#               $filetype   Type for the current file
#               $filename   Name of the current file
#
#               The $line_ref entries may now be in a new format, we need to find out
#               before using it. ref($line_ref) eq 'ARRAY'means new format.
#
#               The format is: [ $curent_linetype,
#                                       \%line_tokens,
#                                       $last_main_line,
#                                       $curent_entity,
#                                       $line_info,
#                                       ];
#

{

        my %class_skill;
        my %class_spell;
        my %domain_spell;

        sub parseFile {
                my ( $lines_ref, $filetype, $filename ) = @_;

                ##################################################################
                # [ 779341 ] Spell Name.MOD to CLASS's SPELLLEVEL
                #

#  if(isConversionActive('CLASS: SPELLLIST from Spell.MOD'))
#  {
#       if($filetype eq 'SPELL')
#       {
#       # All the Spell Name.MOD entries must be parsed to find the
#       # CLASSES and DOMAINS tags.
#       #
#       # The .MOD lines that have no other tags then CLASSES or DOMAINS
#       # will be removed entirely.
#
#       my ($directory,$spellfile) = File::Basename::dirname($filename);
#
#       for(my $i = 0; $i < @$lines_ref; $i++)
#       {
#               # Is this a .MOD line?
#               next unless ref($lines_ref->[$i]) eq 'ARRAY' &&
#                               $lines_ref->[$i][0] eq 'SPELL';
#
#               my $is_mod = $lines_ref->[$i][3] =~ /(.*)\.MOD$/;
#               my $spellname = $is_mod ? $1 : $lines_ref->[$i][3];
#
#               # Is there a CLASSES tag?
#               if(exists $lines_ref->[$i][1]{'CLASSES'})
#               {
#               my $tag = substr($lines_ref->[$i][1]{'CLASSES'}[0],8);
#
#               # We find each group of classes of the same level
#               for (split /\|/, $tag)
#               {
#               if(/(.*)=(\d+)$/)
#               {
#                       my $level = $2;
#                       my $classes = $1;
#
#                       for my $class (split /,/, $classes)
#                       {
#                       #push @{$class_spell{
#                       }
#               }
#               else
#               {
#                       ewarn( NOTICE,  qq(!! No level were given for "$_" found in "$lines_ref->[$i][1]{'CLASSES'}[0]"),
#                       $filename,$i );
#               }
#               }
#
##              ewarn( NOTICE,  qq(**** $spellname: $_),$filename,$i for @classes_by_level );
                #               }
                #
                #               if(exists $lines_ref->[$i][1]{'DOMAINS'})
                #               {
                #               my $tag = substr($lines_ref->[$i][1]{'DOMAINS'}[0],8);
                #               my @domains_by_level = split /\|/, $tag;
                #
                #               ewarn( NOTICE,  qq(**** $spellname: $_),$filename,$i for @domains_by_level );
                #               }
                #       }
                #       }
                #  }

                ###############################################################
                # Reformat multiple lines to one line for RACE and TEMPLATE.
                #
                # This is only useful for those who like to start new entries
                # with multiple lines (for clarity) and then want them formatted
                # properly for submission.

                if ( isConversionActive('ALL:Multiple lines to one') ) {
                my %valid_line_type = (
                        'RACE'  => 1,
                        'TEMPLATE' => 1,
                );

                if ( exists $valid_line_type{$filetype} ) {
                        my $last_main_line = -1;

                        # Find all the lines with the same identifier
                        ENTITY:
                        for ( my $i = 0; $i < @{$lines_ref}; $i++ ) {

                                # Is this a linetype we are interested in?
                                if ( ref $lines_ref->[$i] eq 'ARRAY'
                                && exists $valid_line_type{ $lines_ref->[$i][0] } )
                                {
                                my $first_line = $i;
                                my $last_line  = $i;
                                my $old_length;
                                my $curent_linetype = $lines_ref->[$i][0];
                                my %new_line            = %{ $lines_ref->[$i][1] };
                                $last_main_line = $i;
                                my $entity_name  = $lines_ref->[$i][3];
                                my $line_info   = $lines_ref->[$i][4];
                                my $j           = $i + 1;
                                my $extra_entity = 0;
                                my @new_lines;

                                #Find all the line with the same entity name
                                ENTITY_LINE:
                                for ( ; $j < @{$lines_ref}; $j++ ) {

                                        # Skip empty and comment lines
                                        next ENTITY_LINE
                                                if ref( $lines_ref->[$j] ) ne 'ARRAY'
                                                || $lines_ref->[$j][0] eq 'HEADER'
                                                || ref( $lines_ref->[$j][1] ) ne 'HASH';

                                        # Is it an entity of the same name?
                                        if (   $lines_ref->[$j][0] eq $curent_linetype
                                                && $entity_name eq $lines_ref->[$j][3] )
                                        {
                                                $last_line = $j;
                                                $extra_entity++;
                                                for ( keys %{ $lines_ref->[$j][1] } ) {

                                                # We add the tags except for the first one (the entity tag)
                                                # that is already there.
                                                push @{ $new_line{$_} }, @{ $lines_ref->[$j][1]{$_} }
                                                        if $_ ne @{LstTidy::Reformat::getLineTypeOrder($curent_linetype)}[0];
                                                     }
                                        }
                                        else {
                                                last ENTITY_LINE;
                                        }
                                }

                                # If there was only one line for the entity, we do nothing
                                next ENTITY if !$extra_entity;

                                # Number of lines included in the CLASS
                                $old_length = $last_line - $first_line + 1;

                                # We prepare the replacement lines
                                $j = 0;

                                # The main line
                                if ( keys %new_line > 1 ) {
                                        push @new_lines,
                                                [
                                                $curent_linetype,
                                                \%new_line,
                                                $last_main_line,
                                                $entity_name,
                                                $line_info,
                                                ];
                                        $j++;
                                }

                                # We splice the new class lines in place
                                splice @$lines_ref, $first_line, $old_length, @new_lines;

                                # Continue with the rest
                                $i = $first_line + $j - 1;      # -1 because the $i++ happen right after
                                }
                                elsif (ref $lines_ref->[$i] eq 'ARRAY'
                                && $lines_ref->[$i][0] ne 'HEADER'
                                && defined $lines_ref->[$i][4]
                                && $lines_ref->[$i][4]{Mode} == SUB )
                                {

                                # We must replace the last_main_line with the correct value
                                $lines_ref->[$i][2] = $last_main_line;
                                }
                                elsif (ref $lines_ref->[$i] eq 'ARRAY'
                                && $lines_ref->[$i][0] ne 'HEADER'
                                && defined $lines_ref->[$i][4]
                                && $lines_ref->[$i][4]{Mode} == MAIN )
                                {

                                # We update the last_main_line value and
                                # put the correct value in the curent line
                                $lines_ref->[$i][2] = $last_main_line = $i;
                                }
                        }
                }
                }

                ###############################################################
                # [ 641912 ] Convert CLASSSPELL to SPELL
                #
                #
                # "CLASSSPELL"  => [
                #   'CLASS',
                #   'SOURCEPAGE',
                #   '#HEADER#SOURCE',
                #   '#HEADER#SOURCELONG',
                #   '#HEADER#SOURCESHORT',
                #   '#HEADER#SOURCEWEB',
                # ],
                #
                # "CLASSSPELL Level"    => [
                #   '000ClassSpellLevel',
                #   '001ClassSpells'

                if ( isConversionActive('CLASSSPELL conversion to SPELL') ) {
                if ( $filetype eq 'CLASSSPELL' ) {

                        # Here we will put aside all the CLASSSPELL that
                        # we find for later use.

                        my $dir = File::Basename::dirname($filename);

                        $log->warning(
                                qq(Already found a CLASSSPELL file in $dir),
                                $filename
                        ) if exists $class_spell{$dir};

                        my $curent_name;
                        my $curent_type = 2;    # 0 = CLASS, 1 = DOMAIN, 2 = invalid
                        my $line_number = 1;

                        LINE:
                        for my $line (@$lines_ref) {

                                # We skip all the lines that do not begin by CLASS or a number
                                next LINE
                                if ref($line) ne 'HASH'
                                || ( !exists $line->{'CLASS'} && !exists $line->{'000ClassSpellLevel'} );

                                if ( exists $line->{'CLASS'} ) {

                                # We keep the name
                                $curent_name = ( $line->{'CLASS'}[0] =~ /CLASS:(.*)/ )[0];

                                # Is it a CLASS or a DOMAIN ?


                                if (LstTidy::Validate::isEntityValid('CLASS', $curent_name)) {
                                        $curent_type = 0;
                                }
                                elsif (LstTidy::Validate::isEntityValid('DOMAIN', $curent_name)) {
                                        $curent_type = 1;
                                }
                                else {
                                        $curent_type = 2;
                                        $log->warning(
                                                qq(Don\'t know if "$curent_name" is a CLASS or a DOMAIN),
                                                $filename,
                                                $line_number
                                        );
                                }
                                }
                                else {
                                next LINE if $curent_type == 2 || !exists $line->{'001ClassSpells'};

                                # We store the CLASS name and Level

                                for my $spellname ( split '\|', $line->{'001ClassSpells'}[0] ) {
                                        push @{ $class_spell{$dir}{$spellname}[$curent_type]
                                                { $line->{'000ClassSpellLevel'}[0] } }, $curent_name;

                                }
                                }
                        }
                        continue { $line_number++; }
                }
                elsif ( $filetype eq 'SPELL' ) {
                        my $dir = File::Basename::dirname($filename);

                        if ( exists $class_spell{$dir} ) {

                                # There was a CLASSSPELL in the directory, we need to add
                                # the CLASSES and DOMAINS tag for it.

                                # First we find all the SPELL lines and add the CLASSES
                                # and DOMAINS tags if needed
                                my $line_number = 1;
                                LINE:
                                for my $line (@$lines_ref) {
                                next LINE if ref($line) ne 'ARRAY' || $line->[0] ne 'SPELL';
                                $_ = $line->[1];

                                next LINE if ref ne 'HASH' || !exists $_->{'000SpellName'};
                                my $spellname = $_->{'000SpellName'}[0];

                                if ( exists $class_spell{$dir}{$spellname} ) {
                                        if ( defined $class_spell{$dir}{$spellname}[0] ) {

                                                # We have classes
                                                # Is there already a CLASSES tag?
                                                if ( exists $_->{'CLASSES'} ) {
                                                $log->warning(
                                                        qq(The is already a CLASSES tag for "$spellname"),
                                                        $filename,
                                                        $line_number
                                                );
                                                }
                                                else {
                                                my @new_levels;
                                                for my $level ( sort { $a <=> $b }
                                                        keys %{ $class_spell{$dir}{$spellname}[0] } )
                                                {
                                                        my $new_level = join ',',
                                                                @{ $class_spell{$dir}{$spellname}[0]{$level} };
                                                        push @new_levels, "$new_level=$level";
                                                }
                                                my $new_classes = 'CLASSES:' . join '|', @new_levels;
                                                $_->{'CLASSES'} = [$new_classes];

                                                $log->warning(
                                                        qq{SPELL $spellname: adding "$new_classes"},
                                                        $filename,
                                                        $line_number
                                                );
                                                }
                                        }

                                        if ( defined $class_spell{$dir}{$spellname}[1] ) {

                                                # We have domains
                                                # Is there already a CLASSES tag?
                                                if ( exists $_->{'DOMAINS'} ) {
                                                $log->warning(
                                                        qq(The is already a DOMAINS tag for "$spellname"),
                                                        $filename,
                                                        $line_number
                                                );
                                                }
                                                else {
                                                my @new_levels;
                                                for my $level ( sort { $a <=> $b }
                                                        keys %{ $class_spell{$dir}{$spellname}[1] } )
                                                {
                                                        my $new_level = join ',',
                                                                @{ $class_spell{$dir}{$spellname}[1]{$level} };
                                                        push @new_levels, "$new_level=$level";
                                                }
                                                my $new_domains = 'DOMAINS:' . join '|', @new_levels;
                                                $_->{'DOMAINS'} = [$new_domains];

                                                $log->warning(
                                                        qq{SPELL $spellname: adding "$new_domains"},
                                                        $filename,
                                                        $line_number
                                                );
                                                }
                                        }

                                        # We remove the curent spell from the list.
                                        delete $class_spell{$dir}{$spellname};
                                }
                                }
                                continue { $line_number++; }

                                # Second, we add .MOD line for the SPELL that were not present.
                                if ( keys %{ $class_spell{$dir} } ) {

                                # Put a comment line and a new header line
                                push @$lines_ref, "",
                                        "###Block:SPELL.MOD generated from the old CLASSSPELL files";

                                for my $spellname ( sort keys %{ $class_spell{$dir} } ) {
                                        my %newline = ( '000SpellName' => ["$spellname.MOD"] );
                                        $line_number++;

                                        if ( defined $class_spell{$dir}{$spellname}[0] ) {

                                                # New CLASSES
                                                my @new_levels;
                                                for my $level ( sort { $a <=> $b }
                                                keys %{ $class_spell{$dir}{$spellname}[0] } )
                                                {
                                                my $new_level = join ',',
                                                        @{ $class_spell{$dir}{$spellname}[0]{$level} };
                                                push @new_levels, "$new_level=$level";
                                                }
                                                my $new_classes = 'CLASSES:' . join '|', @new_levels;
                                                $newline{'CLASSES'} = [$new_classes];

                                                $log->warning(
                                                qq{SPELL $spellname.MOD: adding "$new_classes"},
                                                $filename,
                                                $line_number
                                                );
                                        }

                                        if ( defined $class_spell{$dir}{$spellname}[1] ) {

                                                # New DOMAINS
                                                my @new_levels;
                                                for my $level ( sort { $a <=> $b }
                                                keys %{ $class_spell{$dir}{$spellname}[1] } )
                                                {
                                                my $new_level = join ',',
                                                        @{ $class_spell{$dir}{$spellname}[1]{$level} };
                                                push @new_levels, "$new_level=$level";
                                                }

                                                my $new_domains = 'DOMAINS:' . join '|', @new_levels;
                                                $newline{'DOMAINS'} = [$new_domains];

                                                $log->warning(
                                                qq{SPELL $spellname.MOD: adding "$new_domains"},
                                                $filename,
                                                $line_number
                                                );
                                        }

                                        push @$lines_ref, [
                                                'SPELL',
                                                \%newline,
                                                1 + @$lines_ref,
                                                $spellname,
                                                LstTidy::Parse::getParseControl('SPELL'),
                                        ];

                                }
                                }
                        }
                }
                }

                ###############################################################
                # [ 626133 ] Convert CLASS lines into 4 lines
                #
                # The 3 lines are:
                #
                # General (all tags not put in the two other lines)
                # Prereq. (all the PRExxx tags)
                # Class skills (the STARTSKILLPTS, the CKSILL and the CCSKILL tags)
                #
                # 2003.07.11: a fourth line was added for the SPELL related tags

                if (   isConversionActive('CLASS:Four lines')
                && $filetype eq 'CLASS' )
                {
                my $last_main_line = -1;

                # Find all the CLASS lines
                for ( my $i = 0; $i < @{$lines_ref}; $i++ ) {

                        # Is this a CLASS line?
                        if ( ref $lines_ref->[$i] eq 'ARRAY' && $lines_ref->[$i][0] eq 'CLASS' ) {
                                my $first_line = $i;
                                my $last_line  = $i;
                                my $old_length;
                                my %new_class_line = %{ $lines_ref->[$i][1] };
                                my %new_pre_line;
                                my %new_skill_line;
                                my %new_spell_line;
                                my %skill_tags = (
                                'CSKILL:.CLEAR' => 1,
                                CCSKILL         => 1,
                                CSKILL          => 1,
                                MODTOSKILLS             => 1,   #
                                MONSKILL                => 1,   # [ 1097487 ] MONSKILL in class.lst
                                MONNONSKILLHD   => 1,
                                SKILLLIST                       => 1,   # [ 1580059 ] SKILLLIST tag
                                STARTSKILLPTS   => 1,
                                );
                                my %spell_tags = (
                                BONUSSPELLSTAT                  => 1,
                                'BONUS:CASTERLEVEL'             => 1,
                                'BONUS:DC'                              => 1,  #[ 1037456 ] Move BONUS:DC on class line to the spellcasting portion
                                'BONUS:SCHOOL'                  => 1,
                                'BONUS:SPELL'                   => 1,
                                'BONUS:SPECIALTYSPELLKNOWN'     => 1,
                                'BONUS:SPELLCAST'                       => 1,
                                'BONUS:SPELLCASTMULT'           => 1,
                                'BONUS:SPELLKNOWN'              => 1,
                                CASTAS                          => 1,
                                ITEMCREATE                              => 1,
                                KNOWNSPELLS                             => 1,
                                KNOWNSPELLSFROMSPECIALTY        => 1,
                                MEMORIZE                                => 1,
                                HASSPELLFORMULA                 => 1, # [ 1893279 ] HASSPELLFORMULA Class Line tag
                                PROHIBITED                              => 1,
                                SPELLBOOK                               => 1,
                                SPELLKNOWN                              => 1,
                                SPELLLEVEL                              => 1,
                                SPELLLIST                               => 1,
                                SPELLSTAT                               => 1,
                                SPELLTYPE                               => 1,
                                );
                                $last_main_line = $i;
                                my $class               = $lines_ref->[$i][3];
                                my $line_info   = $lines_ref->[$i][4];
                                my $j                   = $i + 1;
                                my @new_class_lines;

                                #Find the next line that is not empty or of the same CLASS
                                CLASS_LINE:
                                for ( ; $j < @{$lines_ref}; $j++ ) {

                                # Skip empty and comment lines
                                next CLASS_LINE
                                        if ref( $lines_ref->[$j] ) ne 'ARRAY'
                                        || $lines_ref->[$j][0] eq 'HEADER'
                                        || ref( $lines_ref->[$j][1] ) ne 'HASH';

                                # Is it a CLASS line of the same CLASS?
                                if ( $lines_ref->[$j][0] eq 'CLASS' && $class eq $lines_ref->[$j][3] ) {
                                        $last_line = $j;
                                        for ( keys %{ $lines_ref->[$j][1] } ) {
                                                push @{ $new_class_line{$_} }, @{ $lines_ref->[$j][1]{$_} }
                                                if $_ ne @{LstTidy::Reformat::getLineTypeOrder('CLASS')}[0];
                                        }
                                }
                                else {
                                        last CLASS_LINE;
                                }
                                }

                                # Number of lines included in the CLASS
                                $old_length = $last_line - $first_line + 1;

                                # We build the two other lines.
                                for ( keys %new_class_line ) {

                                # Is it a SKILL tag?
                                if ( exists $skill_tags{$_} ) {
                                        $new_skill_line{$_} = delete $new_class_line{$_};
                                }

                                # Is it a PRExxx tag?
                                elsif (/^\!?PRE/
                                        || /^DEITY/ ) {
                                        $new_pre_line{$_} = delete $new_class_line{$_};
                                }

                                # Is it a SPELL tag?
                                elsif ( exists $spell_tags{$_} ) {
                                        $new_spell_line{$_} = delete $new_class_line{$_};
                                }
                                }

                                # We prepare the replacement lines
                                $j = 0;

                                # The main line
                                if ( keys %new_class_line > 1
                                || ( !keys %new_pre_line && !keys %new_skill_line && !keys %new_spell_line )
                                )
                                {
                                push @new_class_lines,
                                        [
                                        'CLASS',
                                        \%new_class_line,
                                        $last_main_line,
                                        $class,
                                        $line_info,
                                        ];
                                $j++;
                                }

                                # The PRExxx line
                                if ( keys %new_pre_line ) {

                                # Need to tell what CLASS we are dealing with
                                my $tagLookup = @{LstTidy::Reformat::getLineTypeOrder('CLASS')}[0];
                                $new_pre_line{ $tagLookup }
                                        = $new_class_line{ $tagLookup };
                                push @new_class_lines,
                                        [
                                        'CLASS',
                                        \%new_pre_line,
                                        ++$last_main_line,
                                        $class,
                                        $line_info,
                                        ];
                                $j++;
                                }

                                # The skills line
                                if ( keys %new_skill_line ) {

                                # Need to tell what CLASS we are dealing with
                                my $tagLookup = @{LstTidy::Reformat::getLineTypeOrder('CLASS')}[0];
                                $new_skill_line{ $tagLookup }
                                        = $new_class_line{ $tagLookup };
                                push @new_class_lines,
                                        [
                                        'CLASS',
                                        \%new_skill_line,
                                        ++$last_main_line,
                                        $class,
                                        $line_info,
                                        ];
                                $j++;
                                }

                                # The spell line
                                if ( keys %new_spell_line ) {

                                # Need to tell what CLASS we are dealing with
                                my $tagLookup = @{LstTidy::Reformat::getLineTypeOrder('CLASS')}[0];
                                $new_spell_line{ $tagLookup }
                                        = $new_class_line{ $tagLookup };

                                ##################################################################
                                # [ 876536 ] All spell casting classes need CASTERLEVEL
                                #
                                # BONUS:CASTERLEVEL|<class name>|CL will be added to all classes
                                # that have a SPELLTYPE tag except if there is also an
                                # ITEMCREATE tag present.

                                if (   isConversionActive('CLASS:CASTERLEVEL for all casters')
                                        && exists $new_spell_line{'SPELLTYPE'}
                                        && !exists $new_spell_line{'BONUS:CASTERLEVEL'} )
                                {
                                        my $tagLookup = @{LstTidy::Reformat::getLineTypeOrder('CLASS')}[0];
                                        my $class = $new_spell_line{ $tagLookup }[0];

                                        if ( exists $new_spell_line{'ITEMCREATE'} ) {

                                                # ITEMCREATE is present, we do not convert but we warn.
                                                $log->warning(
                                                        "Can't add BONUS:CASTERLEVEL for class \"$class\", "
                                                        . "\"$new_spell_line{'ITEMCREATE'}[0]\" was found.",
                                                        $filename
                                                );
                                        }
                                        else {

                                                # We add the missing BONUS:CASTERLEVEL
                                                $class =~ s/^CLASS:(.*)/$1/;
                                                $new_spell_line{'BONUS:CASTERLEVEL'}
                                                = ["BONUS:CASTERLEVEL|$class|CL"];
                                                $log->warning(
                                                qq{Adding missing "BONUS:CASTERLEVEL|$class|CL"},
                                                $filename
                                                );
                                        }
                                }

                                push @new_class_lines,
                                        [
                                        'CLASS',
                                        \%new_spell_line,
                                        ++$last_main_line,
                                        $class,
                                        $line_info,
                                        ];
                                $j++;
                                }

                                # We splice the new class lines in place
                                splice @{$lines_ref}, $first_line, $old_length, @new_class_lines;

                                # Continue with the rest
                                $i = $first_line + $j - 1;      # -1 because the $i++ happen right after
                        }
                        elsif (ref $lines_ref->[$i] eq 'ARRAY'
                                && $lines_ref->[$i][0] ne 'HEADER'
                                && defined $lines_ref->[$i][4]
                                && $lines_ref->[$i][4]{Mode} == SUB )
                        {

                                # We must replace the last_main_line with the correct value
                                $lines_ref->[$i][2] = $last_main_line;
                        }
                        elsif (ref $lines_ref->[$i] eq 'ARRAY'
                                && $lines_ref->[$i][0] ne 'HEADER'
                                && defined $lines_ref->[$i][4]
                                && $lines_ref->[$i][4]{Mode} == MAIN )
                        {

                                # We update the last_main_line value and
                                # put the correct value in the curent line
                                $lines_ref->[$i][2] = $last_main_line = $i;
                        }
                }
                }

                ###############################################################
                # The CLASSSKILL files must be deprecated in favor of extra
                # CSKILL in the CLASS files.
                #
                # For every CLASSSKILL found, an extra line must be added after
                # the CLASS line with the class name and the list of
                # CSKILL in the first CLASS file on the same directory as the
                # CLASSSKILL.
                #
                # If no CLASS with the same name can be found in the same
                # directory, entries with class name.MOD must be generated
                # at the end of the first CLASS file in the same directory.

                if ( isConversionActive('CLASSSKILL conversion to CLASS') ) {
                if ( $filetype eq 'CLASSSKILL' ) {

                        # Here we will put aside all the CLASSSKILL that
                        # we find for later use.

                        my $dir = File::Basename::dirname($filename);
                        LINE:
                        for ( @{ $lines_ref } ) {

                                # Only the 000ClassName are of interest to us
                                next LINE
                                if ref ne 'HASH'
                                || !exists $_->{'000ClassName'}
                                || !exists $_->{'001SkillName'};

                                # We preserve the list of skills for the class
                                $class_skill{$dir}{ $_->{'000ClassName'} } = $_->{'001SkillName'};
                        }
                }
                elsif ( $filetype eq 'CLASS' ) {
                        my $dir = File::Basename::dirname($filename);
                        my $skipnext = 0;
                        if ( exists $class_skill{$dir} ) {

                                # There was a CLASSSKILL file in this directory
                                # We need to incorporate it

                                # First, we find all of the existing CLASS and
                                # add an extra line to them
                                my $index = 0;
                                LINE:
                                for (@$lines_ref) {

                                # If the line is text only, skip
                                next LINE if ref ne 'ARRAY';

                                my $line_tokens = $_->[1];

                                # If it is not a CLASS line, we skip it
                                next LINE
                                        if ref($line_tokens) ne 'HASH'
                                        || !exists $line_tokens->{'000ClassName'};

                                my $class = ( $line_tokens->{'000ClassName'}[0] =~ /CLASS:(.*)/ )[0];

                                if ( exists $class_skill{$dir}{$class} ) {
                                        my $line_no = $- > [2];

                                        # We build a new CLASS, CSKILL line to add.
                                        my $newskills = join '|',
                                                sort split( '\|', $class_skill{$dir}{$class} );
                                        $newskills =~ s/Craft[ %]\|/TYPE.Craft\|/;
                                        $newskills =~ s/Knowledge[ %]\|/TYPE.Knowledge\|/;
                                        $newskills =~ s/Profession[ %]\|/TYPE.Profession\|/;
                                        splice @$lines_ref, $index + 1, 0,
                                                [
                                                'CLASS',
                                                {   '000ClassName' => ["CLASS:$class"],
                                                'CSKILL'                => ["CSKILL:$newskills"]
                                                },
                                                $line_no, $class,
                                                LstTidy::Parse::getParseControl('CLASS'),
                                                ];
                                        delete $class_skill{$dir}{$class};

                                        $log->warning( qq{Adding line "CLASS:$class\tCSKILL:$newskills"}, $filename );
                                }
                                }
                                continue { $index++ }

                                # If there are any CLASSSKILL remaining for the directory,
                                # we have to create .MOD entries

                                if ( exists $class_skill{$dir} ) {
                                for ( sort keys %{ $class_skill{$dir} } ) {
                                        my $newskills = join '|', sort split( '\|', $class_skill{$dir}{$_} );
                                        $newskills =~ s/Craft \|/TYPE.Craft\|/;
                                        $newskills =~ s/Knowledge \|/TYPE.Knowledge\|/;
                                        $newskills =~ s/Profession \|/TYPE.Profession\|/;
                                        push @$lines_ref,
                                                [
                                                'CLASS',
                                                {   '000ClassName' => ["CLASS:$_.MOD"],
                                                'CSKILL'                => ["CSKILL:$newskills"]
                                                },
                                                scalar(@$lines_ref),
                                                "$_.MOD",
                                                LstTidy::Parse::getParseControl('CLASS'),
                                                ];

                                        delete $class_skill{$dir}{$_};

                                        $log->warning( qq{Adding line "CLASS:$_.MOD\tCSKILL:$newskills"}, $filename );
                                }
                                }
                        }
                }
                }

                1;
        }

}

###############################################################
# mylength
# --------
#
# Find the number of characters for a string or a list of strings
# that would be separated by tabs.

sub mylength {

   return 0 unless defined $_[0];

   my @list = ref $_[0] eq 'ARRAY' ? @{ $_[0] } : @_;

   # if ( ref( $_[0] ) eq 'ARRAY' ) {
   #    @list = @{ $_[0] };
   # } else {
   #    @list = @_;
   # }

   my $Length  = 0;
   my $last    = pop @list;
   $last = defined $last ? $last : "";

   # All the elements except the last must be rounded to the next tab
   for my $tag ( @list ) {
      $Length += ( int( length($tag) / $tablength ) + 1 ) * $tablength;
   }

   # The last item is not rounded to the tab length
   $Length += length $last;

}

###############################################################
# check_clear_tag_order
# ---------------------
#
# Verify that the .CLEAR tags are put correctly before the
# tags that they clear.
#
# Parameter:  $line_ref         : Hash reference to the line
#                       $file_for_error
#                       $line_for_error

sub check_clear_tag_order {
        my ( $line_ref, $file_for_error, $line_for_error ) = @_;

        TAG:
        for my $tag ( keys %$line_ref ) {

                # if the current value is not an array, there is only one
                # tag and no order to check.
                next unless ref( $line_ref->{$tag} );

                # if only one of a kind, skip the rest
                next TAG if scalar @{ $line_ref->{$tag} } <= 1;

                my %value_found;

                if ( $tag eq "SA" ) {

                # The SA tag is special because it is only checked
                # up to the first (
                for ( @{ $line_ref->{$tag} } ) {
                        if (/:\.?CLEAR.?([^(]*)/) {

                                # clear tag either clear the whole thing,
                                # in which case it must be the very beginning,
                                # or it clear a particular value, in which case
                                # it must be before any such value.
                                if ( $1 ne "" ) {

                                # Let's check if the value was found before
                                $log->notice(  qq{"$tag:$1" found before "$_"}, $file_for_error, $line_for_error )
                                        if exists $value_found{$1};
                                }
                                else {

                                # Let's check if any value was found before
                                $log->notice(  qq{"$tag" tag found before "$_"}, $file_for_error, $line_for_error )
                                        if keys %value_found;
                                }
                        }
                        elsif ( / : ([^(]*) /xms ) {

                                # Let's store the value
                                $value_found{$1} = 1;
                        }
                        else {
                                $log->error(
                                "Didn't anticipate this tag: $_",
                                $file_for_error,
                                $line_for_error
                                );
                        }
                }
                }
                else {
                for ( @{ $line_ref->{$tag} } ) {
                        if (/:\.?CLEAR.?(.*)/) {

                                # clear tag either clear the whole thing,
                                # in which case it must be the very beginning,
                                # or it clear a particular value, in which case
                                # it must be before any such value.
                                if ( $1 ne "" ) {

                                # Let's check if the value was found before
                                $log->notice( qq{"$tag:$1" found before "$_"}, $file_for_error, $line_for_error )
                                        if exists $value_found{$1};
                                }
                                else {

                                # Let's check if any value was found before
                                $log->notice( qq{"$tag" tag found before "$_"}, $file_for_error, $line_for_error )
                                        if keys %value_found;
                                }
                        }
                        elsif (/:(.*)/) {

                                # Let's store the value
                                $value_found{$1} = 1;
                        }
                        else {
                                $log->error(
                                        "Didn't anticipate this tag: $_",
                                        $file_for_error,
                                        $line_for_error
                                );
                        }
                }
                }
        }
}

###############################################################
# find_full_path
# --------------
#
# Change the @ and relative paths found in the .lst for
# the real thing.
#
# Parameters: $file_name         File name
#             $current_base_dir  Current directory
#             $base_path         Origin for the @ replacement

sub find_full_path {
   my ( $file_name, $current_base_dir, $base_path ) = @_;

   # Change all the \ for / in the file name
   $file_name =~ tr{\\}{/};

   # Replace @ by the base dir or add the current base dir to the file name.
   if( $file_name !~ s{ ^[@] }{$base_path}xmsi )
   {
      $file_name = "$current_base_dir/$file_name";
   }

   # Remove the /xxx/../ for the directory
   if ($file_name =~ / [.][.] /xms ) {
      if( $file_name !~ s{ [/] [^/]+ [/] [.][.] [/] }{/}xmsg ) {
         die qq{Cannot deal with the .. directory in "$file_name"};
      }
   }

   return $file_name;
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
###############################################################
###
### Start of closure for BIOSET generation functions
### [ 663491 ] RACE: Convert AGE, HEIGHT and WEIGHT tags
###

{

        # Moving this out of the BEGIN as a workaround for bug
        # [perl #30058] Perl 5.8.4 chokes on perl -e 'BEGIN { my %x=(); }'

        my %RecordedBiosetTags;

        BEGIN {

                my %DefaultBioset = (

                # Race          AGE                             HEIGHT                                  WEIGHT
                'Human' =>      [ 'AGE:15:1:4:1:6:2:6',   'HEIGHT:M:58:2:10:0:F:53:2:10:0',   'WEIGHT:M:120:2:4:F:85:2:4'       ],
                'Dwarf' =>      [ 'AGE:40:3:6:5:6:7:6',   'HEIGHT:M:45:2:4:0:F:43:2:4:0',       'WEIGHT:M:130:2:6:F:100:2:6'    ],
                'Elf' =>        [ 'AGE:110:4:6:6:6:10:6', 'HEIGHT:M:53:2:6:0:F:53:2:6:0',       'WEIGHT:M:85:1:6:F:80:1:6'      ],
                'Gnome' =>      [ 'AGE:40:4:6:6:6:9:6',   'HEIGHT:M:36:2:4:0:F:34:2:4:0',       'WEIGHT:M:40:1:1:F:35:1:1'      ],
                'Half-Elf' => [ 'AGE:20:1:6:2:6:3:6',   'HEIGHT:M:55:2:8:0:F:53:2:8:0', 'WEIGHT:M:100:2:4:F:80:2:4'     ],
                'Half-Orc' => [ 'AGE:14:1:4:1:6:2:6',   'HEIGHT:M:58:2:10:0:F:52:2:10:0',   'WEIGHT:M:130:2:4:F:90:2:4' ],
                'Halfling' => [ 'AGE:20:2:4:3:6:4:6',   'HEIGHT:M:32:2:4:0:F:30:2:4:0', 'WEIGHT:M:30:1:1:F:25:1:1'      ],
                );

                ###############################################################
                # record_bioset_tags
                # ------------------
                #
                # This function record the BIOSET information found in the
                # RACE files so that the BIOSET files can later be generated.
                #
                # If the value are equal to the default, they are not generated
                # since the default apply.
                #
                # Parameters: $dir              Directory where the RACE file was found
                #                       $race           Name of the race
                #                       $age                    AGE tag
                #                       $height         HEIGHT tag
                #                       $weight         WEIGHT tag
                #                       $file_for_error To use with ewarn
                #                       $line_for_error To use with ewarn

                sub record_bioset_tags {
                my ($dir,
                        $race,
                        $age,
                        $height,
                        $weight,
                        $file_for_error,
                        $line_for_error
                ) = @_;

                # Check to see if default apply
                RACE:
                for my $master_race ( keys %DefaultBioset ) {
                        if ( index( $race, $master_race ) == 0 ) {

                                # The race name is included in the default
                                # We now verify the values
                                $age    = "" if $DefaultBioset{$master_race}[0] eq $age;
                                $height = "" if $DefaultBioset{$master_race}[1] eq $height;
                                $weight = "" if $DefaultBioset{$master_race}[2] eq $weight;
                                last RACE;
                        }
                }

                # Everything that is not blank must be kept
                if ($age) {
                        if ( exists $RecordedBiosetTags{$dir}{$race}{AGE} ) {
                                $log->notice(
                                qq{BIOSET generation: There is already a AGE tag recorded}
                                        . qq{ for a race named "$race" in this directory.},
                                $file_for_error,
                                $line_for_error
                                );
                        }
                        else {
                                $RecordedBiosetTags{$dir}{$race}{AGE} = $age;
                        }
                }

                if ($height) {
                        if ( exists $RecordedBiosetTags{$dir}{$race}{HEIGHT} ) {
                                $log->notice(
                                qq{BIOSET generation: There is already a HEIGHT tag recorded}
                                        . qq{ for a race named "$race" in this directory.},
                                $file_for_error,
                                $line_for_error
                                );
                        }
                        else {
                                $RecordedBiosetTags{$dir}{$race}{HEIGHT} = $height;
                        }
                }

                if ($weight) {
                        if ( exists $RecordedBiosetTags{$dir}{$race}{WEIGHT} ) {
                                $log->notice(
                                qq{BIOSET generation: There is already a WEIGHT tag recorded}
                                        . qq{ for a race named "$race" in this directory.},
                                $file_for_error,
                                $line_for_error
                                );
                        }
                        else {
                                $RecordedBiosetTags{$dir}{$race}{WEIGHT} = $weight;
                        }
                }
                }

                ###############################################################
                # generate_bioset_files
                # ---------------------
                #
                # Generate the new BIOSET files from the data included in the
                # %RecordedBiosetTags hash.
                #
                # The new files will all be named bioset.lst and will required
                # to be renamed and included in the .PCC manualy.
                #
                # No parameter

                sub generate_bioset_files {
                for my $dir ( sort keys %RecordedBiosetTags ) {
                        my $filename = $dir . '/biosettings.lst';
                        my $inputpath  = getOption('inputpath');
                        my $outputpath = getOption('outputpath');
                        $filename =~ s/${inputpath}/${outputpath}/i;

                        open my $bioset_fh, '>', $filename;

                        # Printing the name of the new file generated
                        print STDERR $filename, "\n";

                        # Header part.
                        print {$bioset_fh} << "END_OF_HEADER";
AGESET:0|Adulthood
END_OF_HEADER

                        # Let's find the longest race name
                        my $racename_length = 0;
                        for my $racename ( keys %{ $RecordedBiosetTags{$dir} } ) {
                                $racename_length = length($racename) if length($racename) > $racename_length;
                        }

                        # Add the length for RACENAME:
                        $racename_length += 9;

                        # Bring the length to the next tab
                        if ( $racename_length % $tablength ) {

                                # We add the remaining spaces to get to the tab
                                $racename_length += $tablength - ( $racename_length % $tablength );
                        }
                        else {

                                # Already on a tab length, we add an extra tab
                                $racename_length += $tablength;
                        }

                        # We now format and print the lines for each race
                        for my $racename ( sort keys %{ $RecordedBiosetTags{$dir} } ) {
                                my $height_weight_line = "";
                                my $age_line            = "";

                                if (   exists $RecordedBiosetTags{$dir}{$racename}{HEIGHT}
                                && exists $RecordedBiosetTags{$dir}{$racename}{WEIGHT} )
                                {
                                my $space_to_add = $racename_length - length($racename) - 9;
                                my $tab_to_add   = int( $space_to_add / $tablength )
                                        + ( $space_to_add % $tablength ? 1 : 0 );
                                $height_weight_line = 'RACENAME:' . $racename . "\t" x $tab_to_add;

                                my ($m_ht_min, $m_ht_dice, $m_ht_sides, $m_ht_bonus,
                                        $f_ht_min, $f_ht_dice, $f_ht_sides, $f_ht_bonus
                                        )
                                        = ( split ':', $RecordedBiosetTags{$dir}{$racename}{HEIGHT} )
                                        [ 2, 3, 4, 5, 7, 8, 9, 10 ];

                                my ($m_wt_min, $m_wt_dice, $m_wt_sides,
                                        $f_wt_min, $f_wt_dice, $f_wt_sides
                                        )
                                        = ( split ':', $RecordedBiosetTags{$dir}{$racename}{WEIGHT} )
                                                [ 2, 3, 4, 6, 7, 8 ];

# 'HEIGHT:M:58:2:10:0:F:53:2:10:0'
# 'WEIGHT:M:120:2:4:F:85:2:4'
#
# SEX:Male[BASEHT:58|HTDIEROLL:2d10|BASEWT:120|WTDIEROLL:2d4|TOTALWT:BASEWT+(HTDIEROLL*WTDIEROLL)]Female[BASEHT:53|HTDIEROLL:2d10|BASEWT:85|WTDIEROLL:2d4|TOTALWT:BASEWT+(HTDIEROLL*WTDIEROLL)]

                                # Male height caculation
                                $height_weight_line .= 'SEX:Male[BASEHT:'
                                        . $m_ht_min
                                        . '|HTDIEROLL:'
                                        . $m_ht_dice . 'd'
                                        . $m_ht_sides;
                                $height_weight_line .= '+' . $m_ht_bonus if $m_ht_bonus > 0;
                                $height_weight_line .= $m_ht_bonus              if $m_ht_bonus < 0;

                                # Male weight caculation
                                $height_weight_line .= '|BASEWT:'
                                        . $m_wt_min
                                        . '|WTDIEROLL:'
                                        . $m_wt_dice . 'd'
                                        . $m_wt_sides;
                                $height_weight_line .= '|TOTALWT:BASEWT+(HTDIEROLL*WTDIEROLL)]';

                                # Female height caculation
                                $height_weight_line .= 'Female[BASEHT:'
                                        . $f_ht_min
                                        . '|HTDIEROLL:'
                                        . $f_ht_dice . 'd'
                                        . $f_ht_sides;
                                $height_weight_line .= '+' . $f_ht_bonus if $f_ht_bonus > 0;
                                $height_weight_line .= $f_ht_bonus              if $f_ht_bonus < 0;

                                # Female weight caculation
                                $height_weight_line .= '|BASEWT:'
                                        . $f_wt_min
                                        . '|WTDIEROLL:'
                                        . $f_wt_dice . 'd'
                                        . $f_wt_sides;
                                $height_weight_line .= '|TOTALWT:BASEWT+(HTDIEROLL*WTDIEROLL)]';
                                }

                                if ( exists $RecordedBiosetTags{$dir}{$racename}{AGE} ) {

                                # We only generate a comment from the AGE tag
                                $age_line = '### Old tag for race '
                                        . $racename . '=> '
                                        . $RecordedBiosetTags{$dir}{$racename}{AGE};
                                }

                                print {$bioset_fh} $height_weight_line, "\n" if $height_weight_line;
                                print {$bioset_fh} $age_line,           "\n" if $age_line;

                                #       print BIOSET "\n";
                        }

                        close $bioset_fh;
                }
                }

        }       # BEGIN

}       # The entra encapsulation is a workaround for the bug
        # [perl #30058] Perl 5.8.4 chokes on perl -e 'BEGIN { my %x=(); }'

###
### End of  closure for BIOSET generation funcitons
###
###############################################################
###############################################################

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

B<prettylst.pl> is a script that parse a PCGEN .lst files and generate
new ones with the proper ordering of the fields. The original order was
given by Mynex. Nowadays, it's Tir-Gwait that is the
head-honcho-master-lst-monkey (well, he decide the order anyway :-).

The script is also able to do some conversions of the .lst so that old
versions are compatibled with the latest release of PCGEN.

=head1 INSTALLATION

=head2 Get Perl

I'm using ActivePerl v5.8.6 (build 811) but any standard distribution with version 5.5 and
over should work. The script has been tested on Windows 98, Windows 2000, Windows XP and FreeBSD.

To my knowledge, I'm using only one module that is not included in the standard distribution: Text::Balanced
(this module is included in the 5.8 standard distribution and maybe with some others).

To get Perl use <L<http://www.activestate.com/Products/ActivePerl/>> or <L<http://www.cpan.org/ports/index.html>>
To get Text::Balanced use <L<http://search.cpan.org/author/DCONWAY/Text-Balanced-1.89/lib/Text/Balanced.pm>> or
use the following command if you use the ActivePerl distribution:

  ppm install text-balanced

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

Disable the new LstTidy::Parse::extractVariables function for the formula. This
makes the script use the old style formula parser.

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

