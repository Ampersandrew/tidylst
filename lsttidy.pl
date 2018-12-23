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
use LstTidy::Parse;
use LstTidy::Reformat;
use LstTidy::Report;
use LstTidy::Validate;

# Subroutines
sub FILETYPE_parse;
sub validate_line;
sub additionnal_line_parsing;
sub additionnal_file_parsing;
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

# Move these into Parse.pm, or Validate.pm whenever the code using them is moved.
my @valid_system_alignments  = LstTidy::Parse::getValidSystemArr('alignments');
my @valid_system_stats       = LstTidy::Parse::getValidSystemArr('stats');


# Does a count, seems to be unused
my %classSpellTypes = ();

# For conversions
my %source_tags = ();
my %Spells_For_EQMOD = ();

# PCC processing
my %files = ();

# Only used in additional line processing, will likely be moved
my $source_curent_file = q{};

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

# Working variables
my %column_with_no_tag = (

        'ABILITY' => [
                '000AbilityName',
        ],

        'ABILITYCATEGORY' => [
                '000AbilityCategory',
        ],

        'ARMORPROF' => [
                '000ArmorName',
        ],

        'CLASS' => [
                '000ClassName',
        ],

        'CLASS Level' => [
                '000Level',
        ],

        'COMPANIONMOD' => [
                '000Follower',
        ],

        'DEITY' => [
                '000DeityName',
        ],

        'DOMAIN' => [
                '000DomainName',
        ],

        'EQUIPMENT' => [
                '000EquipmentName',
        ],

        'EQUIPMOD' => [
                '000ModifierName',
        ],

        'FEAT' => [
                '000FeatName',
        ],

        'LANGUAGE' => [
                '000LanguageName',
        ],

        'MASTERBONUSRACE' => [
                '000MasterBonusRace',
        ],

        'RACE' => [
                '000RaceName',
        ],

        'SHIELDPROF' => [
                '000ShieldName',
        ],

        'SKILL' => [
                '000SkillName',
        ],

        'SPELL' => [
                '000SpellName',
        ],

        'SUBCLASS' => [
                '000SubClassName',
        ],

        'SUBSTITUTIONCLASS' => [
                '000SubstitutionClassName',
        ],

        'TEMPLATE' => [
                '000TemplateName',
        ],

        'WEAPONPROF' => [
                '000WeaponName',
        ],

        'VARIABLE' => [
                '000VariableName',
        ],

        'DATACONTROL' => [
                '000DatacontrolName',
        ],

        'GLOBALMOD' => [
                '000GlobalmodName',
        ],

        'ALIGNMENT' => [
                '000AlignmentName',
        ],

        'SAVE' => [
                '000SaveName',
        ],

        'STAT' => [
                '000StatName',
        ],

);





################################################################################
# Global variables used by the validation code

# Will hold the entities that are allowed to include
# a sub-entity between () in their name.
# e.g. Skill Focus(Spellcraft)
# Format: $validSubEntities{$entity_type}{$entity_name} = $sub_entity_type;
# e.g. :  $validSubEntities{'FEAT'}{'Skill Focus'} = 'SKILL';
my %validSubEntities; 

# Add pre-defined valid entities
for my $var_name (LstTidy::Parse::getValidSystemArr('vars')) {
   LstTidy::Validate::setEntityValid('DEFINE Variable', $var_name);
}

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

               } elsif (
                     $tag->id eq 'CLASSSPELL' 
                  || $tag->id eq 'CLASSSKILL'
                  || $tag->id eq 'CLASS' 
                  || $tag->id eq 'DOMAIN' 
                  || $tag->id eq 'SPELL') {

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
      $log->error( "HTML file detected. Maybe you had a problem with your CSV checkout.\n", $file );
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
      warn "SKIP rewrite for $file because it is a multi-line file" if $filetype eq 'multi-line';
      next FILE_TO_PARSE if $filetype eq 'multi-line';                # we still need to implement rewriting for multi-line
      next FILE_TO_PARSE if ! LstTidy::Parse::isWriteableFileType( $filesToParse{$file} );

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
      for my $column ( @{ $column_with_no_tag{$curent_linetype} } ) {

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

      additionnal_line_parsing(\%line_tokens, $curent_linetype, $file, $line, $newline);

      ############################################################
      # Validate the line
      if (getOption('xcheck')) {
         validate_line(\%line_tokens, $curent_linetype, $file, $line) 
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

        additionnal_file_parsing(\@newlines, $fileType, $file);

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
                my ($curent_linetype, $line_tokens, $last_main_line,
                $curent_entity,   $line_info
                )
                = @$line_ref;
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
# validate_line
# -------------
#
# This function perform validation that must be done on a
# whole line at a time.
#
# Paramter: $line_ref           Ref to a hash containing the tags of the line
#               $linetype               Type for the current line
#               $file_for_error   Name of the current file
#               $line_for_error   Number of the current line

sub validate_line {
        my ( $line_ref, $linetype, $file_for_error, $line_for_error ) = @_;

        ########################################################
        # Validation for the line identifier
        ########################################################

        if ( !($linetype eq 'SOURCE'
                || $linetype eq 'KIT LANGAUTO'
                || $linetype eq 'KIT NAME'
                || $linetype eq 'KIT FEAT'
                || $file_for_error =~ m{ [.] PCC \z }xmsi
                || $linetype eq 'COMPANIONMOD') # FOLLOWER:Class1,Class2=level
        ) {

                # We get the line identifier.
                my $identifier = $line_ref->{ @{LstTidy::Reformat::getLineTypeOrder($linetype)}[0] }[0];

                # We hunt for the bad comma.
                if($identifier =~ /,/) {
                        $log->notice(
                                qq{"," (comma) should not be used in line identifier name: $identifier},
                                $file_for_error,
                                $line_for_error
                        );
                }
        }

        ########################################################
        # Special validation for specific tags
        ########################################################

        if ( 0 && $linetype eq 'SPELL' )        # disabled for now.
        {

                # Either or both CLASSES and DOMAINS tags must be
                # present in a normal SPELL line

                if (  exists $line_ref->{'000SpellName'}
                        && $line_ref->{'000SpellName'}[0] !~ /\.MOD$/
                        && exists $line_ref->{'TYPE'}
                        && $line_ref->{'TYPE'}[0] ne 'TYPE:Psionic.Attack Mode'
                        && $line_ref->{'TYPE'}[0] ne 'TYPE:Psionic.Defense Mode' )
                {
                        $log->info(
                                qq(No CLASSES or DOMAINS tag found for SPELL "$line_ref->{'000SpellName'}[0]"),
                                $file_for_error,
                                $line_for_error
                        ) if !( exists $line_ref->{'CLASSES'} || exists $line_ref->{'DOMAINS'} );
                }
        }
        elsif ( $linetype eq "ABILITY" ) {

                # On an ABILITY line type:
                # 0) MUST contain CATEGORY tag
                # 1) if it has MULT:YES, it  _has_ to have CHOOSE
                # 2) if it has CHOOSE, it _has_ to have MULT:YES
                # 3) if it has STACK:YES, it _has_ to have MULT:YES (and CHOOSE)

                # Find lines that modify or remove Categories of Abilityies without naming the Abilities
                my $MOD_Line = $line_ref->{'000AbilityName'}[0];
                study $MOD_Line;

                if ( $MOD_Line =~ /\.(MOD|FORGET|COPY=)/ ) {
                        # Nothing to see here. Move on.
                }
                # Find the Abilities lines without Categories
                elsif ( !$line_ref->{'CATEGORY'} ) {
                        $log->warning(
                                qq(The CATEGORY tag is required in ABILITY "$line_ref->{'000AbilityName'}[0]"),
                                $file_for_error,
                                $line_for_error
                        );
                }
                my ( $hasCHOOSE, $hasMULT, $hasSTACK );

                $hasCHOOSE = 1 if exists $line_ref->{'CHOOSE'};
                $hasMULT   = 1 if exists $line_ref->{'MULT'} && $line_ref->{'MULT'}[0] =~ /^MULT:Y/i;
                $hasSTACK  = 1 if exists $line_ref->{'STACK'} && $line_ref->{'STACK'}[0] =~ /^STACK:Y/i;

                if ( $hasMULT && !$hasCHOOSE ) {
                        $log->info(
                                qq(The CHOOSE tag is mandantory when MULT:YES is present in ABILITY "$line_ref->{'000AbilityName'}[0]"),
                                $file_for_error,
                                $line_for_error
                        );
                }
                elsif ( $hasCHOOSE && !$hasMULT && $line_ref->{'CHOOSE'}[0] !~ /CHOOSE:SPELLLEVEL/i ) {
                        # The CHOOSE:SPELLLEVEL is exempted from this particular rule.
                        $log->info(
                                qq(The MULT:YES tag is mandatory when CHOOSE is present in ABILITY "$line_ref->{'000AbilityName'}[0]"),
                                $file_for_error,
                                $line_for_error
                        );
                }
                elsif ( $hasCHOOSE && !$hasMULT && $line_ref->{'CHOOSE'}[0] !~ /CHOOSE:NUMBER/i ) {
                        # The CHOOSE:NUMBER is exempted from this particular rule.
                        $log->info(
                                qq(The MULT:YES tag is mandatory when CHOOSE is present in ABILITY "$line_ref->{'000AbilityName'}[0]"),
                                $file_for_error,
                                $line_for_error
                        );
                }

                if ( $hasSTACK && !$hasMULT ) {
                        $log->info(
                                qq(The MULT:YES tag is mandatory when STACK:YES is present in ABILITY "$line_ref->{'000AbilityName'}[0]"),
                                $file_for_error,
                                $line_for_error
                        );
                }

                # We identify the feats that can have sub-entities. e.g. Spell Focus(Spellcraft)
                if ($hasCHOOSE) {

                        # The CHOSE type tells us the type of sub-entities
                        my $choose      = $line_ref->{'CHOOSE'}[0];
                        my $ability_name = $line_ref->{'000AbilityName'}[0];
                        $ability_name =~ s/.MOD$//;

                        if ( $choose =~ /^CHOOSE:(?:NUMCHOICES=\d+\|)?(FEAT=[^|]*)/ ) {
                                $validSubEntities{'ABILITY'}{$ability_name} = $1;
                        }
                        elsif ( $choose =~ /^CHOOSE:(?:NUMCHOICES=\d+\|)?FEATLIST/ ) {
                                $validSubEntities{'ABILITY'}{$ability_name} = 'FEAT';
                        }
                        elsif ( $choose =~ /^CHOOSE:(?:NUMCHOICES=\d+\|)?(?:WEAPONPROFS|Exotic|Martial)/ ) {
                                $validSubEntities{'ABILITY'}{$ability_name} = 'WEAPONPROF';
                        }
                        elsif ( $choose =~ /^CHOOSE:(?:NUMCHOICES=\d+\|)?SKILLSNAMED/ ) {
                                $validSubEntities{'ABILITY'}{$ability_name} = 'SKILL';
                        }
                        elsif ( $choose =~ /^CHOOSE:(?:NUMCHOICES=\d+\|)?SCHOOLS/ ) {
                                $validSubEntities{'ABILITY'}{$ability_name} = 'SPELL_SCHOOL';
                        }
                        elsif ( $choose =~ /^CHOOSE:(?:NUMCHOICES=\d+\|)?SPELLLIST/ ) {
                                $validSubEntities{'ABILITY'}{$ability_name} = 'SPELL';
                        }
                        elsif ($choose =~ /^CHOOSE:(?:NUMCHOICES=\d+\|)?SPELLLEVEL/
                                || $choose =~ /^CHOOSE:(?:NUMCHOICES=\d+\|)?HP/ )
                        {

                                # Ad-Lib is a special case that means "Don't look for
                                # anything else".
                                $validSubEntities{'ABILITY'}{$ability_name} = 'Ad-Lib';
                        }
                        elsif ( $choose =~ /^CHOOSE:(?:COUNT=\d+\|)?(.*)/ ) {

                                # ad-hod/special list of thingy
                                # It adds to the valid entities instead of the
                                # valid sub-entities.
                                # We do this when we find a CHOOSE but we do not
                                # know what it is for.

                                LstTidy::Validate::splitAndAddToValidEntities('ABILITY', $ability_name, $1);
                        }
                }
        }

        elsif ( $linetype eq "FEAT" ) {

                # [ 1671410 ] xcheck CATEGORY:Feat in Feat object.
                my $hasCategory = 0;
                $hasCategory = 1 if exists $line_ref->{'CATEGORY'};
                if ($hasCategory) {
                        if ($line_ref->{'CATEGORY'}[0] eq "CATEGORY:Feat" ||
                            $line_ref->{'CATEGORY'}[0] eq "CATEGORY:Special Ability") {
                                # Good
                        }
                        else {
                                $log->info(
                                        qq(The CATEGORY tag must have the value of Feat or Special Ability when present on a FEAT. Remove or replace "$line_ref->{'CATEGORY'}[0]"),
                                        $file_for_error,
                                        $line_for_error
                                );
                        }
                }

                # On a FEAT line type:
                # 1) if it has MULT:YES, it  _has_ to have CHOOSE
                # 2) if it has CHOOSE, it _has_ to have MULT:YES
                # 3) if it has STACK:YES, it _has_ to have MULT:YES (and CHOOSE)
                my ( $hasCHOOSE, $hasMULT, $hasSTACK );

                $hasCHOOSE = 1 if exists $line_ref->{'CHOOSE'};
                $hasMULT   = 1 if exists $line_ref->{'MULT'} && $line_ref->{'MULT'}[0] =~ /^MULT:Y/i;
                $hasSTACK  = 1 if exists $line_ref->{'STACK'} && $line_ref->{'STACK'}[0] =~ /^STACK:Y/i;

                if ( $hasMULT && !$hasCHOOSE ) {
                        $log->info(
                                qq(The CHOOSE tag is mandatory when MULT:YES is present in FEAT "$line_ref->{'000FeatName'}[0]"),
                                $file_for_error,
                                $line_for_error
                        );
                }
                elsif ( $hasCHOOSE && !$hasMULT && $line_ref->{'CHOOSE'}[0] !~ /CHOOSE:SPELLLEVEL/i ) {

                        # The CHOOSE:SPELLLEVEL is exampted from this particular rule.
                        $log->info(
                                qq(The MULT:YES tag is mandatory when CHOOSE is present in FEAT "$line_ref->{'000FeatName'}[0]"),
                                $file_for_error,
                                $line_for_error
                        );
                }
                elsif ( $hasCHOOSE && !$hasMULT && $line_ref->{'CHOOSE'}[0] !~ /CHOOSE:NUMBER/i ) {

                        # The CHOOSE:NUMBER is exampted from this particular rule.
                        $log->info(
                                qq(The MULT:YES tag is mandatory when CHOOSE is present in FEAT "$line_ref->{'000FeatName'}[0]"),
                                $file_for_error,
                                $line_for_error
                        );
                }

                if ( $hasSTACK && !$hasMULT ) {
                        $log->info(
                                qq(The MULT:YES tag is mandatory when STACK:YES is present in FEAT "$line_ref->{'000FeatName'}[0]"),
                                $file_for_error,
                                $line_for_error
                        );
                }

                # We identify the feats that can have sub-entities. e.g. Spell Focus(Spellcraft)
                if ($hasCHOOSE) {

                        # The CHOSE type tells us the type of sub-entities
                        my $choose      = $line_ref->{'CHOOSE'}[0];
                        my $feat_name = $line_ref->{'000FeatName'}[0];
                        $feat_name =~ s/.MOD$//;

                        if ( $choose =~ /^CHOOSE:(?:NUMCHOICES=\d+\|)?(FEAT=[^|]*)/ ) {
                                $validSubEntities{'FEAT'}{$feat_name} = $1;
                        }
                        elsif ( $choose =~ /^CHOOSE:(?:NUMCHOICES=\d+\|)?FEATLIST/ ) {
                                $validSubEntities{'FEAT'}{$feat_name} = 'FEAT';
                        }
                        elsif ( $choose =~ /^CHOOSE:(?:NUMCHOICES=\d+\|)?(?:WEAPONPROFS|Exotic|Martial)/ ) {
                                $validSubEntities{'FEAT'}{$feat_name} = 'WEAPONPROF';
                        }
                        elsif ( $choose =~ /^CHOOSE:(?:NUMCHOICES=\d+\|)?SKILLSNAMED/ ) {
                                $validSubEntities{'FEAT'}{$feat_name} = 'SKILL';
                        }
                        elsif ( $choose =~ /^CHOOSE:(?:NUMCHOICES=\d+\|)?SCHOOLS/ ) {
                                $validSubEntities{'FEAT'}{$feat_name} = 'SPELL_SCHOOL';
                        }
                        elsif ( $choose =~ /^CHOOSE:(?:NUMCHOICES=\d+\|)?SPELLLIST/ ) {
                                $validSubEntities{'FEAT'}{$feat_name} = 'SPELL';
                        }
                        elsif ($choose =~ /^CHOOSE:(?:NUMCHOICES=\d+\|)?SPELLLEVEL/
                                || $choose =~ /^CHOOSE:(?:NUMCHOICES=\d+\|)?HP/ )
                        {

                                # Ad-Lib is a special case that means "Don't look for
                                # anything else".
                                $validSubEntities{'FEAT'}{$feat_name} = 'Ad-Lib';
                        }
                        elsif ( $choose =~ /^CHOOSE:(?:COUNT=\d+\|)?(.*)/ ) {

                           LstTidy::Validate::splitAndAddToValidEntities('FEAT', $feat_name, $1);
                        }
                }
        }
        elsif ( $linetype eq "EQUIPMOD" ) {

                # We keep track of the KEYs for the equipmods.
                if ( exists $line_ref->{'KEY'} ) {

                        # The KEY tag should only have one value and there should always be only
                        # one KEY tag by EQUIPMOD line.

                        # We extract the key name
                        my ($key) = ( $line_ref->{'KEY'}[0] =~ /KEY:(.*)/ );

                        if ($key) {
                           LstTidy::Validate::setEntityValid("EQUIPMOD Key", $key);
                        }
                        else {
                                $log->warning(
                                        qq(Could not parse the KEY in "$line_ref->{'KEY'}[0]"),
                                        $file_for_error,
                                        $line_for_error
                                );
                        }
                }
                else {
                        # [ 1368562 ] .FORGET / .MOD don\'t need KEY entries
                        my $report_tag = $line_ref->{$column_with_no_tag{'EQUIPMOD'}[0]}[0];
                        if ($report_tag =~ /.FORGET$|.MOD$/) {
                        }
                        else {
                                $log->info(
                                qq(No KEY tag found for "$report_tag"),
                                $file_for_error,
                                $line_for_error
                                );
                        }
                }
                if ( exists $line_ref->{'CHOOSE'} ) {               # [ 1870825 ] EqMod CHOOSE Changes
                        my $choose = $line_ref->{'CHOOSE'}[0];
                        my $eqmod_name = $line_ref->{'000ModifierName'}[0];
                        $eqmod_name =~ s/.MOD$//;
                        if ( $choose =~ /^CHOOSE:(NUMBER[^|]*)/ ) {
                        # Valid: CHOOSE:NUMBER|MIN=1|MAX=99129342|TITLE=Whatever
                        # Valid: CHOOSE:NUMBER|1|2|3|4|5|6|7|8|TITLE=Whatever
                        # Valid: CHOOSE:NUMBER|MIN=1|MAX=99129342|INCREMENT=5|TITLE=Whatever
                        # Valid: CHOOSE:NUMBER|MAX=99129342|INCREMENT=5|MIN=1|TITLE=Whatever
                        # Only testing for TITLE= for now.
                                # Test for TITLE= and warn if not present.
                                if ( $choose !~ /(TITLE[=])/ ) {
                                        $log->info(
                                        qq(TITLE= is missing in CHOOSE:NUMBER for "$choose"),
                                        $file_for_error,
                                        $line_for_error
                                        );
                                }
                        }
                        # Only CHOOSE:NOCHOICE is Valid
                        elsif ( $choose =~ /^CHOOSE:NOCHOICE/ ) {
                        }
                        # CHOOSE:STRING|Foo|Bar|Monkey|Poo|TITLE=these are choices
                        elsif ( $choose =~ /^CHOOSE:?(STRING)[^|]*/ ) {
                                # Test for TITLE= and warn if not present.
                                if ( $choose !~ /(TITLE[=])/ ) {
                                        $log->info(
                                        qq(TITLE= is missing in CHOOSE:STRING for "$choose"),
                                        $file_for_error,
                                        $line_for_error
                                        );
                                }
                        }
                        # CHOOSE:STATBONUS|statname|MIN=2|MAX=5|TITLE=Enhancement Bonus
                        # Statname is what I'd want to check to verify against the defined stats, but since it is optional....
                        elsif ( $choose =~ /^CHOOSE:?(STATBONUS)[^|]*/ ) {
#                               my $checkstat = $choose;
#                               $checkstat =~ s/(CHOOSE:STATBONUS)// ;
#                               $checkstat =~ s/[|]MIN=[-]?\d+\|MAX=\d+\|TITLE=.*//;
                        }
                        elsif ( $choose =~ /^CHOOSE:?(SKILLBONUS)[^|]*/ ) {
                        }
                        elsif ( $choose =~ /^CHOOSE:?(SKILL)[^|]*/ ) {
                                if ( $choose !~ /(TITLE[=])/ ) {
                                        $log->info(
                                        qq(TITLE= is missing in CHOOSE:SKILL for "$choose"),
                                        $file_for_error,
                                        $line_for_error
                                        );
                                }
                        }
                        elsif ( $choose =~ /^CHOOSE:?(EQBUILDER.SPELL)[^|]*/ ) {
                        }
                        elsif ( $choose =~ /^CHOOSE:?(EQBUILDER.EQTYPE)[^|]*/ ) {
                        }
                        # If not above, invaild CHOOSE for equipmod files.
                        else {
                                        $log->warning(
                                        qq(Invalid CHOOSE for Equipmod spells for "$choose"),
                                        $file_for_error,
                                        $line_for_error
                                        );
                        }
                }
        }
        elsif ( $linetype eq "CLASS" ) {

                # [ 876536 ] All spell casting classes need CASTERLEVEL
                #
                # If SPELLTYPE is present and BONUS:CASTERLEVEL is not present,
                # we warn the user.

                if ( exists $line_ref->{'SPELLTYPE'} && !exists $line_ref->{'BONUS:CASTERLEVEL'} ) {
                        $log->info(
                                qq{Missing BONUS:CASTERLEVEL for "$line_ref->{$column_with_no_tag{'CLASS'}[0]}[0]"},
                                $file_for_error,
                                $line_for_error
                        );
                }
        }
                elsif ( $linetype eq "CLASS" ) {

                # [ 876536 ] All spell casting classes need CASTERLEVEL
                #
                # If SPELLTYPE is present and BONUS:CASTERLEVEL is not present,
                # we warn the user.

                if ( exists $line_ref->{'FACT:SPELLTYPE'} && !exists $line_ref->{'BONUS:CASTERLEVEL'} ) {
                        $log->info(
                                qq{Missing BONUS:CASTERLEVEL for "$line_ref->{$column_with_no_tag{'CLASS'}[0]}[0]"},
                                $file_for_error,
                                $line_for_error
                        );
                }
        }

        elsif ( $linetype eq 'SKILL' ) {

                # We must identify the skills that have sub-entity e.g. Speak Language (Infernal)

                if ( exists $line_ref->{'CHOOSE'} ) {

                        # The CHOSE type tells us the type of sub-entities
                        my $choose      = $line_ref->{'CHOOSE'}[0];
                        my $skill_name = $line_ref->{'000SkillName'}[0];
                        $skill_name =~ s/.MOD$//;

                        if ( $choose =~ /^CHOOSE:(?:NUMCHOICES=\d+\|)?Language/ ) {
                                $validSubEntities{'SKILL'}{$skill_name} = 'LANGUAGE';
                        }
                }
        }
}

###############################################################
# additionnal_line_parsing
# ------------------------
#
# This function does additional parsing on each line once
# they have been seperated in tags.
#
# Most commun use is for addition, conversion or removal of tags.
#
# Paramter: $line_ref         Ref to a hash containing the tags of the line
#           $filetype         Type for the current file
#           $file_for_error   Name of the current file
#           $line_for_error   Number of the current line
#           $line_info        (Optional) structure generated by FILETYPE_parse
#

BEGIN {

        my $class_name = "";

        sub additionnal_line_parsing {
                my ( $line_ref, $filetype, $file_for_error, $line_for_error, $line_info ) = @_;

        ##################################################################
        # [ 1596310 ] xcheck: TYPE:Spellbook for equip w/ NUMPAGES and PAGEUSAGE
        # Gawaine42 (Richard)
        # Check to see if the TYPE contains Spellbook, if so, warn if
        # NUMUSES or PAGEUSAGE aren't there.
        # Then check to see if NUMPAGES or PAGEUSAGE are there, and if they
        # are there, but the TYPE doesn't contain Spellbook, warn.

        if ($filetype eq 'EQUIPMENT') {
                if (exists $line_ref->{'TYPE'}
                && $line_ref->{'TYPE'}[0] =~ /Spellbook/)
                {
                if (exists $line_ref->{'NUMPAGES'}
                        && exists $line_ref->{'PAGEUSAGE'}) {
                        #Nothing to see here, move along.
                }
                else {
                        $log->info(
                        qq{You have a Spellbook defined without providing NUMPAGES or PAGEUSAGE. If you want a spellbook of finite capacity, consider adding these tags.},
                        $file_for_error,
                        $line_for_error
                        );
                }
                }
                else {

                if (exists $line_ref->{'NUMPAGES'} )
                {
                        $log->warning(
                        qq{Invalid use of NUMPAGES tag in a non-spellbook. Remove this tag, or correct the TYPE.},
                        $file_for_error,
                        $line_for_error
                        );
                }
                if  (exists $line_ref->{'PAGEUSAGE'})
                {
                        $log->warning(
                        qq{Invalid use of PAGEUSAGE tag in a non-spellbook. Remove this tag, or correct the TYPE.},
                        $file_for_error,
                        $line_for_error
                        );
                }
                }
        #################################################################
        #  Do the same for Type Container with and without CONTAINS
                if (exists $line_ref->{'TYPE'}
                && $line_ref->{'TYPE'}[0] =~ /Container/)
                {
                if (exists $line_ref->{'CONTAINS'}) {
#                       $line_ref =~ s/'CONTAINS:-1'/'CONTAINS:UNLIM'/g;   # [ 1777282 ] CONTAINS Unlimited Weight is UNLIM, not -1
                }
                else {
                        $log->warning(
                        qq{Any object with TYPE:Container must also have a CONTAINS tag to be activated.},
                        $file_for_error,
                        $line_for_error
                        );
                }
                }
                elsif (exists $line_ref->{'CONTAINS'})
                {
                $log->warning(
                        qq{Any object with CONTAINS must also be TYPE:Container for the CONTAINS tag to be activated.},
                        $file_for_error,
                        $line_for_error
                        );
                }

   }

        ##################################################################
        # [ 1864711 ] Convert ADD:SA to ADD:SAB
        #
        # In most files, take ADD:SA and replace with ADD:SAB

        if (   isConversionActive('ALL:Convert ADD:SA to ADD:SAB')
                && exists $line_ref->{'ADD:SA'}
        ) {
                $log->warning(
                        qq{Change ADD:SA for ADD:SAB in "$line_ref->{'ADD:SA'}[0]"},
                        $file_for_error,
                        $line_for_error
                );
                my $satag;
                $satag = $line_ref->{'ADD:SA'}[0];
                $satag =~ s/ADD:SA/ADD:SAB/;
                $line_ref->{'ADD:SAB'}[0] = $satag;
                delete $line_ref->{'ADD:SA'};
        }



        ##################################################################
        # [ 1514765 ] Conversion to remove old defaultmonster tags
        # Gawaine42 (Richard Bowers)
        # Bonuses associated with a PREDEFAULTMONSTER:Y need to be removed
        # This should remove the whole tag.
        if (isConversionActive('RACE:Fix PREDEFAULTMONSTER bonuses')
                        && $filetype eq "RACE"
        ) {
        for my $key ( keys %$line_ref ) {
                my $ary = $line_ref->{$key};
                my $iCount = 0;
                foreach (@$ary) {
                my $ttag = $$ary[$iCount];
                if ($ttag =~ /PREDEFAULTMONSTER:Y/) {
                        $$ary[$iCount] = "";
                        $log->warning(
                                qq{Removing "$ttag".},
                                $file_for_error,
                                $line_for_error
                                );
                }
                $iCount++;
                }
        }
        }



        ##################################################################
        # [ 1615457 ] Replace ALTCRITICAL with ALTCRITMULT'
        #
        # In EQUIPMENT files, take ALTCRITICAL and replace with ALTCRITMULT'

        if (   isConversionActive('EQUIP: ALTCRITICAL to ALTCRITMULT')
                && $filetype eq "EQUIPMENT"
                && exists $line_ref->{'ALTCRITICAL'}
        ) {
        # Throw warning if both ALTCRITICAL and ALTCRITMULT are on the same line,
        #   then remove ALTCRITICAL.
        if ( exists $line_ref->{ALTCRITMULT} ) {
                $log->warning(
                        qq{Removing ALTCRITICAL, ALTCRITMULT already present on same line.},
                        $file_for_error,
                        $line_for_error
                );
                delete $line_ref->{'ALTCRITICAL'};
        } else {
                $log->warning(
                        qq{Change ALTCRITICAL for ALTCRITMULT in "$line_ref->{'ALTCRITICAL'}[0]"},
                        $file_for_error,
                        $line_for_error
                );
                my $ttag;
                $ttag = $line_ref->{'ALTCRITICAL'}[0];
                $ttag =~ s/ALTCRITICAL/ALTCRITMULT/;
                $line_ref->{'ALTCRITMULT'}[0] = $ttag;
                delete $line_ref->{'ALTCRITICAL'};
                }
        }


        ##################################################################
        # [ 1514765 ] Conversion to remove old defaultmonster tags
        #
        # In RACE files, remove all MFEAT and HITDICE tags, but only if
        # there is a MONSTERCLASS present.

        # We remove MFEAT or warn of missing MONSTERCLASS tag.
        if (   isConversionActive('RACE:Remove MFEAT and HITDICE')
                && $filetype eq "RACE"
                && exists $line_ref->{'MFEAT'}
                ) { if ( exists $line_ref->{'MONSTERCLASS'}
                        ) { for my $tag ( @{ $line_ref->{'MFEAT'} } ) {
                                $log->warning(
                                qq{Removing "$tag".},
                                $file_for_error,
                                $line_for_error
                                );
                        }
                        delete $line_ref->{'MFEAT'};
                        }
                else {$log->warning(
                        qq{MONSTERCLASS missing on same line as MFEAT, need to look at by hand.},
                                $file_for_error,
                                $line_for_error
                                );
                        }
        }

        # We remove HITDICE or warn of missing MONSTERCLASS tag.
        if (   isConversionActive('RACE:Remove MFEAT and HITDICE')
                && $filetype eq "RACE"
                && exists $line_ref->{'HITDICE'}
                ) { if ( exists $line_ref->{'MONSTERCLASS'}
                        ) { for my $tag ( @{ $line_ref->{'HITDICE'} } ) {
                                $log->warning(
                                qq{Removing "$tag".},
                                $file_for_error,
                                $line_for_error
                                );
                        }
                        delete $line_ref->{'HITDICE'};
                        }
                else {$log->warning(
                        qq{MONSTERCLASS missing on same line as HITDICE, need to look at by hand.},
                                $file_for_error,
                                $line_for_error
                                );
                        }
                }

        #######################################################
        ## [ 1689538 ] Conversion: Deprecation of FOLLOWERALIGN
        ## Gawaine42
        ## Note: Makes simplifying assumption that FOLLOWERALIGN
        ## will occur only once in a given line, although DOMAINS may
        ## occur multiple times.
        if ((isConversionActive('DEITY:Followeralign conversion'))
                && $filetype eq "DEITY"
                && (exists $line_ref->{'FOLLOWERALIGN'}))
        {
                my $followeralign = $line_ref->{'FOLLOWERALIGN'}[0];
                $followeralign =~ s/^FOLLOWERALIGN://;
                my $newprealign = "";
                my $aligncount = 0;

                for my $align (split //, $followeralign) {
                        # Is it a number?
                        my $number;
                        if ( (($number) = ($align =~ / \A (\d+) \z /xms))
                        && $number >= 0
                        && $number < scalar @valid_system_alignments)
                {
                                my $newalign = $valid_system_alignments[$number];
                        if ($aligncount > 0) {
                        $newprealign .= ',';
                        }
                        $aligncount++;
                        $newprealign .= "$newalign";
                        }
                else {
                                $log->notice(
                                qq{Invalid value "$align" for tag "$line_ref->{'FOLLOWERALIGN'}[0]"},
                                $file_for_error,
                                $line_for_error
                                );

                }
                }
                my $dom_count=0;

                if (exists $line_ref->{'DOMAINS'}) {
                for my $line ($line_ref->{'DOMAINS'})
                {
                        $line_ref->{'DOMAINS'}[$dom_count] .= "|PREALIGN:$newprealign";
                        $dom_count++;
                }
                $log->notice(
                                qq{Adding PREALIGN to domain information and removing "$line_ref->{'FOLLOWERALIGN'}[0]"},
                                $file_for_error,
                                $line_for_error
                                );

                delete $line_ref->{'FOLLOWERALIGN'};
                }
        }

                ##################################################################
                # [ 1353255 ] TYPE to RACETYPE conversion
                #
                # Checking race files for TYPE and if no RACETYPE,
                # convert TYPE to RACETYPE.
                # if Race file has no TYPE or RACETYPE, report as 'Info'

                # Do this check no matter what - valid any time
                if ( $filetype eq "RACE"
                && not ( exists $line_ref->{'RACETYPE'} )
                && not ( exists $line_ref->{'TYPE'}  )
                ) {
                # .MOD / .FORGET / .COPY don't need RACETYPE or TYPE'
                my $race_name = $line_ref->{'000RaceName'}[0];
                if ($race_name =~ /\.(FORGET|MOD|COPY=.+)$/) {
                } else { $log->warning(
                        qq{Race entry missing both TYPE and RACETYPE.},
                        $file_for_error,
                        $line_for_error
                        );
                }
                };

                if (   isConversionActive('RACE:TYPE to RACETYPE')
                && ( $filetype eq "RACE"
                        || $filetype eq "TEMPLATE" )
                && not (exists $line_ref->{'RACETYPE'})
                && exists $line_ref->{'TYPE'}
                ) { $log->warning(
                        qq{Changing TYPE for RACETYPE in "$line_ref->{'TYPE'}[0]".},
                        $file_for_error,
                        $line_for_error
                        );
                        $line_ref->{'RACETYPE'} = [ "RACE" . $line_ref->{'TYPE'}[0] ];
                        delete $line_ref->{'TYPE'};
                };

#                       $line_ref->{'MONCSKILL'} = [ "MON" . $line_ref->{'CSKILL'}[0] ];
#                       delete $line_ref->{'CSKILL'};


                ##################################################################
                # [ 1444527 ] New SOURCE tag format
                #
                # The SOURCELONG tags found on any linetype but the SOURCE line type must
                # be converted to use tab if | are found.

                if (   isConversionActive('ALL:New SOURCExxx tag format')
                && exists $line_ref->{'SOURCELONG'} ) {
                my @new_tags;

                for my $tag ( @{ $line_ref->{'SOURCELONG'} } ) {
                        if( $tag =~ / [|] /xms ) {
                                push @new_tags, split '\|', $tag;
                                $log->warning(
                                qq{Spliting "$tag"},
                                $file_for_error,
                                $line_for_error
                                );
                        }
                }

                if( @new_tags ) {
                        delete $line_ref->{'SOURCELONG'};

                        for my $new_tag (@new_tags) {
                                my ($tag_name) = ( $new_tag =~ / ( [^:]* ) [:] /xms );
                                push @{ $line_ref->{$tag_name} }, $new_tag;
                        }
                }
                }

                ##################################################################
                # [ 1070084 ] Convert SPELL to SPELLS
                #
                # Convert the old SPELL tags to the new SPELLS format.
                #
                # Old SPELL:<spellname>|<nb per day>|<spellbook>|...|PRExxx|PRExxx|...
                # New SPELLS:<spellbook>|TIMES=<nb per day>|<spellname>|<spellname>|PRExxx...

                if ( isConversionActive('ALL:Convert SPELL to SPELLS')
                && exists $line_ref->{'SPELL'} )
                {
                my %spellbooks;

                # We parse all the existing SPELL tags
                for my $tag ( @{ $line_ref->{'SPELL'} } ) {
                        my ( $tag_name, $tag_value ) = ( $tag =~ /^([^:]*):(.*)/ );
                        my @elements = split '\|', $tag_value;
                        my @pretags;

                        while ( $elements[ +@elements - 1 ] =~ /^!?PRE\w*:/ ) {

                                # We keep the PRE tags separated
                                unshift @pretags, pop @elements;
                        }

                        # We classify each triple <spellname>|<nb per day>|<spellbook>
                        while (@elements) {
                                if ( +@elements < 3 ) {
                                $log->warning(
                                        qq(Wrong number of elements for "$tag_name:$tag_value"),
                                        $file_for_error,
                                        $line_for_error
                                );
                                }

                                my $spellname = shift @elements;
                                my $times       = +@elements ? shift @elements : 99999;
                                my $pretags   = join '|', @pretags;
                                $pretags = "NONE" unless $pretags;
                                my $spellbook = +@elements ? shift @elements : "MISSING SPELLBOOK";

                                push @{ $spellbooks{$spellbook}{$times}{$pretags} }, $spellname;
                        }

                        $log->warning(
                                qq{Removing "$tag_name:$tag_value"},
                                $file_for_error,
                                $line_for_error
                        );
                }

                # We delete the SPELL tags
                delete $line_ref->{'SPELL'};

                # We add the new SPELLS tags
                for my $spellbook ( sort keys %spellbooks ) {
                        for my $times ( sort keys %{ $spellbooks{$spellbook} } ) {
                                for my $pretags ( sort keys %{ $spellbooks{$spellbook}{$times} } ) {
                                my $spells = "SPELLS:$spellbook|TIMES=$times";

                                for my $spellname ( sort @{ $spellbooks{$spellbook}{$times}{$pretags} } ) {
                                        $spells .= "|$spellname";
                                }

                                $spells .= "|$pretags" unless $pretags eq "NONE";

                                $log->warning( qq{Adding   "$spells"}, $file_for_error, $line_for_error );

                                push @{ $line_ref->{'SPELLS'} }, $spells;
                                }
                        }
                }
                }

                ##################################################################
                # We get rid of all the PREALIGN tags.
                #
                # This is needed by my good CMP friends.

                if ( isConversionActive('ALL:CMP remove PREALIGN') ) {
                if ( exists $line_ref->{'PREALIGN'} ) {
                        my $number = +@{ $line_ref->{'PREALIGN'} };
                        delete $line_ref->{'PREALIGN'};
                        $log->warning(
                                qq{Removing $number PREALIGN tags},
                                $file_for_error,
                                $line_for_error
                        );
                }

                if ( exists $line_ref->{'!PREALIGN'} ) {
                        my $number = +@{ $line_ref->{'!PREALIGN'} };
                        delete $line_ref->{'!PREALIGN'};
                        $log->warning(
                                qq{Removing $number !PREALIGN tags},
                                $file_for_error,
                                $line_for_error
                        );
                }
                }

                ##################################################################
                # Need to fix the STR bonus when the monster have only one
                # Natural Attack (STR bonus is then 1.5 * STR).
                # We add it if there is only one Melee attack and the
                # bonus is not already present.

                if ( isConversionActive('ALL:CMP NatAttack fix')
                && exists $line_ref->{'NATURALATTACKS'} )
                {

                # First we verify if if there is only one melee attack.
                if ( @{ $line_ref->{'NATURALATTACKS'} } == 1 ) {
                        my @NatAttacks = split '\|', $line_ref->{'NATURALATTACKS'}[0];
                        if ( @NatAttacks == 1 ) {
                                my ( $NatAttackName, $Types, $NbAttacks, $Damage ) = split ',', $NatAttacks[0];
                                if ( $NbAttacks eq '*1' && $Damage ) {

                                # Now, at last, we know there is only one Natural Attack
                                # Is it a Melee attack?
                                my @Types       = split '\.', $Types;
                                my $IsMelee  = 0;
                                my $IsRanged = 0;
                                for my $type (@Types) {
                                        $IsMelee  = 1 if uc($type) eq 'MELEE';
                                        $IsRanged = 1 if uc($type) eq 'RANGED';
                                }

                                if ( $IsMelee && !$IsRanged ) {

                                        # We have a winner!!!
                                        ($NatAttackName) = ( $NatAttackName =~ /:(.*)/ );

                                        # Well, maybe the BONUS:WEAPONPROF is already there.
                                        if ( exists $line_ref->{'BONUS:WEAPONPROF'} ) {
                                                my $AlreadyThere = 0;
                                                FIND_BONUS:
                                                for my $bonus ( @{ $line_ref->{'BONUS:WEAPONPROF'} } ) {
                                                if ( $bonus eq "BONUS:WEAPONPROF=$NatAttackName|DAMAGE|STR/2" )
                                                {
                                                        $AlreadyThere = 1;
                                                        last FIND_BONUS;
                                                }
                                                }

                                                unless ($AlreadyThere) {
                                                push @{ $line_ref->{'BONUS:WEAPONPROF'} },
                                                        "BONUS:WEAPONPROF=$NatAttackName|DAMAGE|STR/2";
                                                $log->warning(
                                                        qq{Added "$line_ref->{'BONUS:WEAPONPROF'}[0]"}
                                                                . qq{ to go with "$line_ref->{'NATURALATTACKS'}[0]"},
                                                        $file_for_error,
                                                        $line_for_error
                                                );
                                                }
                                        }
                                        else {
                                                $line_ref->{'BONUS:WEAPONPROF'}
                                                = ["BONUS:WEAPONPROF=$NatAttackName|DAMAGE|STR/2"];
                                                $log->warning(
                                                qq{Added "$line_ref->{'BONUS:WEAPONPROF'}[0]"}
                                                        . qq{to go with "$line_ref->{'NATURALATTACKS'}[0]"},
                                                $file_for_error,
                                                $line_for_error
                                                );
                                        }
                                }
                                elsif ( $IsMelee && $IsRanged ) {
                                        $log->warning(
                                                qq{This natural attack is both Melee and Ranged}
                                                . qq{"$line_ref->{'NATURALATTACKS'}[0]"},
                                                $file_for_error,
                                                $line_for_error
                                        );
                                }
                                }
                        }
                }
                }

                ##################################################################
                # [ 865826 ] Remove the deprecated MOVE tag in EQUIPMENT files
                # No conversion needed. We just have to remove the MOVE tags that
                # are doing nothing anyway.

                if (   isConversionActive('EQUIP:no more MOVE')
                && $filetype eq "EQUIPMENT"
                && exists $line_ref->{'MOVE'} )
                {
                $log->warning( qq{Removed MOVE tags}, $file_for_error, $line_for_error );
                delete $line_ref->{'MOVE'};
                }

                if (   isConversionActive('CLASS:no more HASSPELLFORMULA')
                && $filetype eq "CLASS"
                && exists $line_ref->{'HASSPELLFORMULA'} )
                {
                $log->warning( qq{Removed deprecated HASSPELLFORMULA tags}, $file_for_error, $line_for_error );
                delete $line_ref->{'HASSPELLFORMULA'};
                }


                ##################################################################
                # Every RACE that has a Climb or a Swim MOVE must have a
                # BONUS:SKILL|Climb|8|TYPE=Racial. If there is a
                # BONUS:SKILLRANK|Swim|8|PREDEFAULTMONSTER:Y present, it must be
                # removed or lowered by 8.

                if (   isConversionActive('RACE:BONUS SKILL Climb and Swim')
                && $filetype eq "RACE"
                && exists $line_ref->{'MOVE'} )
                {
                my $swim  = $line_ref->{'MOVE'}[0] =~ /swim/i;
                my $climb = $line_ref->{'MOVE'}[0] =~ /climb/i;

                if ( $swim || $climb ) {
                        my $need_swim  = 1;
                        my $need_climb = 1;

                        # Is there already a BONUS:SKILL|Swim of at least 8 rank?
                        if ( exists $line_ref->{'BONUS:SKILL'} ) {
                                for my $skill ( @{ $line_ref->{'BONUS:SKILL'} } ) {
                                if ( $skill =~ /^BONUS:SKILL\|([^|]*)\|(\d+)\|TYPE=Racial/i ) {
                                        my $skill_list = $1;
                                        my $skill_rank = $2;

                                        $need_swim  = 0 if $skill_list =~ /swim/i;
                                        $need_climb = 0 if $skill_list =~ /climb/i;

                                        if ( $need_swim && $skill_rank == 8 ) {
                                                $skill_list
                                                = join( ',', sort( split ( ',', $skill_list ), 'Swim' ) );
                                                $skill = "BONUS:SKILL|$skill_list|8|TYPE=Racial";
                                                $log->warning(
                                                qq{Added Swim to "$skill"},
                                                $file_for_error,
                                                $line_for_error
                                                );
                                        }

                                        if ( $need_climb && $skill_rank == 8 ) {
                                                $skill_list
                                                = join( ',', sort( split ( ',', $skill_list ), 'Climb' ) );
                                                $skill = "BONUS:SKILL|$skill_list|8|TYPE=Racial";
                                                $log->warning(
                                                qq{Added Climb to "$skill"},
                                                $file_for_error,
                                                $line_for_error
                                                );
                                        }

                                        if ( ( $need_climb || $need_swim ) && $skill_rank != 8 ) {
                                                $log->info(
                                                qq{You\'ll have to deal with this one yourself "$skill"},
                                                $file_for_error,
                                                $line_for_error
                                                );
                                        }
                                }
                                }
                        }
                        else {
                                $need_swim  = $swim;
                                $need_climb = $climb;
                        }

                        # Is there a BONUS:SKILLRANK to remove?
                        if ( exists $line_ref->{'BONUS:SKILLRANK'} ) {
                                for ( my $index = 0; $index < @{ $line_ref->{'BONUS:SKILLRANK'} }; $index++ ) {
                                my $skillrank = $line_ref->{'BONUS:SKILLRANK'}[$index];

                                if ( $skillrank =~ /^BONUS:SKILLRANK\|(.*)\|(\d+)\|PREDEFAULTMONSTER:Y/ ) {
                                        my $skill_list = $1;
                                        my $skill_rank = $2;

                                        if ( $climb && $skill_list =~ /climb/i ) {
                                                if ( $skill_list eq "Climb" ) {
                                                $skill_rank -= 8;
                                                if ($skill_rank) {
                                                        $skillrank
                                                                = "BONUS:SKILLRANK|Climb|$skill_rank|PREDEFAULTMONSTER:Y";
                                                        $log->warning(
                                                                qq{Lowering skill rank in "$skillrank"},
                                                                $file_for_error,
                                                                $line_for_error
                                                        );
                                                }
                                                else {
                                                        $log->warning(
                                                                qq{Removing "$skillrank"},
                                                                $file_for_error,
                                                                $line_for_error
                                                        );
                                                        delete $line_ref->{'BONUS:SKILLRANK'}[$index];
                                                        $index--;
                                                }
                                                }
                                                else {
                                                $log->info(
                                                        qq{You\'ll have to deal with this one yourself "$skillrank"},
                                                        $file_for_error,
                                                        $line_for_error
                                                );;
                                                }
                                        }

                                        if ( $swim && $skill_list =~ /swim/i ) {
                                                if ( $skill_list eq "Swim" ) {
                                                $skill_rank -= 8;
                                                if ($skill_rank) {
                                                        $skillrank
                                                                = "BONUS:SKILLRANK|Swim|$skill_rank|PREDEFAULTMONSTER:Y";
                                                        $log->warning(
                                                                qq{Lowering skill rank in "$skillrank"},
                                                                $file_for_error,
                                                                $line_for_error
                                                        );
                                                }
                                                else {
                                                        $log->warning(
                                                                qq{Removing "$skillrank"},
                                                                $file_for_error,
                                                                $line_for_error
                                                        );
                                                        delete $line_ref->{'BONUS:SKILLRANK'}[$index];
                                                        $index--;
                                                }
                                                }
                                                else {
                                                $log->info(
                                                        qq{You\'ll have to deal with this one yourself "$skillrank"},
                                                        $file_for_error,
                                                        $line_for_error
                                                );
                                                }
                                        }
                                }
                                }

                                # If there are no more BONUS:SKILLRANK, we remove the tag entry
                                delete $line_ref->{'BONUS:SKILLRANK'}
                                unless @{ $line_ref->{'BONUS:SKILLRANK'} };
                        }
                }
                }

                ##################################################################
                # [ 845853 ] SIZE is no longer valid in the weaponprof files
                #
                # The SIZE tag must be removed from all WEAPONPROF files since it
                # cause loading problems with the latest versio of PCGEN.

                if (   isConversionActive('WEAPONPROF:No more SIZE')
                && $filetype eq "WEAPONPROF"
                && exists $line_ref->{'SIZE'} )
                {
                   my $tagLookup = @{LstTidy::Reformat::getLineTypeOrder('WEAPONPROF')}[0];

                   $log->warning(
                      qq{Removing the SIZE tag in line "$line_ref->{$tagLookup}[0]"},
                      $file_for_error,
                      $line_for_error
                   );
                   delete $line_ref->{'SIZE'};
                }

                ##################################################################
                # [ 832164 ] Adding NoProfReq to AUTO:WEAPONPROF for most races
                #
                # NoProfReq must be added to AUTO:WEAPONPROF if the race has
                # at least one hand and if NoProfReq is not already there.

                if (   isConversionActive('RACE:NoProfReq')
                && $filetype eq "RACE" )
                {
                my $needNoProfReq = 1;

                # Is NoProfReq already present?
                if ( exists $line_ref->{'AUTO:WEAPONPROF'} ) {
                        $needNoProfReq = 0 if $line_ref->{'AUTO:WEAPONPROF'}[0] =~ /NoProfReq/;
                }

                my $nbHands = 2;        # Default when no HANDS tag is present

                # How many hands?
                if ( exists $line_ref->{'HANDS'} ) {
                        if ( $line_ref->{'HANDS'}[0] =~ /HANDS:(\d+)/ ) {
                                $nbHands = $1;
                        }
                        else {
                                $log->info(
                                        qq(Invalid value in tag "$line_ref->{'HANDS'}[0]"),
                                        $file_for_error,
                                        $line_for_error
                                );
                                $needNoProfReq = 0;
                        }
                }

                if ( $needNoProfReq && $nbHands ) {
                        if ( exists $line_ref->{'AUTO:WEAPONPROF'} ) {
                                $log->warning(
                                qq{Adding "TYPE=NoProfReq" to tag "$line_ref->{'AUTO:WEAPONPROF'}[0]"},
                                $file_for_error,
                                $line_for_error
                                );
                                $line_ref->{'AUTO:WEAPONPROF'}[0] .= "|TYPE=NoProfReq";
                        }
                        else {
                                $line_ref->{'AUTO:WEAPONPROF'} = ["AUTO:WEAPONPROF|TYPE=NoProfReq"];
                                $log->warning(
                                qq{Creating new tag "AUTO:WEAPONPROF|TYPE=NoProfReq"},
                                $file_for_error,
                                $line_for_error
                                );
                        }
                }
                }

                ##################################################################
                # [ 831569 ] RACE:CSKILL to MONCSKILL
                #
                # In the RACE files, all the CSKILL must be replaced with MONCSKILL
                # but only if MONSTERCLASS is present and there is not already a
                # MONCSKILL present.

                if (   isConversionActive('RACE:CSKILL to MONCSKILL')
                && $filetype eq "RACE"
                && exists $line_ref->{'CSKILL'}
                && exists $line_ref->{'MONSTERCLASS'}
                && !exists $line_ref->{'MONCSKILL'} )
                {
                $log->warning(
                        qq{Change CSKILL for MONSKILL in "$line_ref->{'CSKILL'}[0]"},
                        $file_for_error,
                        $line_for_error
                );

                $line_ref->{'MONCSKILL'} = [ "MON" . $line_ref->{'CSKILL'}[0] ];
                delete $line_ref->{'CSKILL'};
                }

                ##################################################################
                # [ 728038 ] BONUS:VISION must replace VISION:.ADD
                #
                # VISION:.ADD must be converted to BONUS:VISION
                # Some exemple of VISION:.ADD tags:
                #   VISION:.ADD,Darkvision (60')
                #   VISION:1,Darkvision (60')
                #   VISION:.ADD,See Invisibility (120'),See Etheral (120'),Darkvision (120')

                if (   isConversionActive('ALL: , to | in VISION')
                && exists $line_ref->{'VISION'}
                && $line_ref->{'VISION'}[0] =~ /(\.ADD,|1,)(.*)/i )
                {
                $log->warning(
                        qq{Removing "$line_ref->{'VISION'}[0]"},
                        $file_for_error,
                        $line_for_error
                );

                my $newvision = "VISION:";
                my $coma;

                for my $vision_bonus ( split ',', $2 ) {
                        if ( $vision_bonus =~ /(\w+)\s*\((\d+)\'\)/ ) {
                                my ( $type, $bonus ) = ( $1, $2 );
                                push @{ $line_ref->{'BONUS:VISION'} }, "BONUS:VISION|$type|$bonus";
                                $log->warning(
                                qq{Adding "BONUS:VISION|$type|$bonus"},
                                $file_for_error,
                                $line_for_error
                                );
                                $newvision .= "$coma$type (0')";
                                $coma = ',';
                        }
                        else {
                                $log->error(
                                qq(Do not know how to convert "VISION:.ADD,$vision_bonus"),
                                $file_for_error,
                                $line_for_error
                                );
                        }
                }

                $log->warning( qq{Adding "$newvision"}, $file_for_error, $line_for_error );

                $line_ref->{'VISION'} = [$newvision];
                }

                ##################################################################
                #
                #
                # For items with TYPE:Boot, Glove, Bracer, we must check for plural
                # form and add a SLOTS:2 tag is the item is plural.

                if (   isConversionActive('EQUIPMENT: SLOTS:2 for plurals')
                && $filetype            eq 'EQUIPMENT'
                && $line_info->[0] eq 'EQUIPMENT'
                && !exists $line_ref->{'SLOTS'} )
                {
                   my $tagLookup = @{LstTidy::Reformat::getLineTypeOrder('EQUIPMENT')}[0];
                   my $equipment_name = $line_ref->{ $tagLookup }[0];

                if ( exists $line_ref->{'TYPE'} ) {
                        my $type = $line_ref->{'TYPE'}[0];
                        if ( $type =~ /(Boot|Glove|Bracer)/ ) {
                                if (   $1 eq 'Boot' && $equipment_name =~ /boots|sandals/i
                                || $1 eq 'Glove'  && $equipment_name =~ /gloves|gauntlets|straps/i
                                || $1 eq 'Bracer' && $equipment_name =~ /bracers|bracelets/i )
                                {
                                $line_ref->{'SLOTS'} = ['SLOTS:2'];
                                $log->warning(
                                        qq{"SLOTS:2" added to "$equipment_name"},
                                        $file_for_error,
                                        $line_for_error
                                );
                                }
                                else {
                                $log->error( qq{"$equipment_name" is a $1}, $file_for_error, $line_for_error );
                                }
                        }
                }
                else {
                        $log->warning(
                                qq{$equipment_name has no TYPE.},
                                $file_for_error,
                                $line_for_error
                        ) unless $equipment_name =~ /.MOD$/i;
                }
                }

                ##################################################################
                # #[ 677962 ] The DMG wands have no charge.
                #
                # Any Wand that do not have a EQMOD tag most have one added.
                #
                # The syntax for the new tag is
                # EQMOD:SE_50TRIGGER|SPELLNAME[$spell_name]SPELLLEVEL[$spell_level]CASTERLEVEL[$caster_level]CHARGES[50]
                #
                # The $spell_level will also be extracted from the CLASSES tag.
                # The $caster_level will be $spell_level * 2 -1

                if ( isConversionActive('EQUIPMENT: generate EQMOD') ) {
                if (   $filetype eq 'SPELL'
                        && $line_info->[0] eq 'SPELL'
                        && ( exists $line_ref->{'CLASSES'} ) )
                {
                        my $spell_name  = $line_ref->{'000SpellName'}[0];
                        my $spell_level = -1;

                        CLASS:
                        for ( split '\|', $line_ref->{'CLASSES'}[0] ) {
                                if ( index( $_, 'Wizard' ) != -1 || index( $_, 'Cleric' ) != -1 ) {
                                $spell_level = (/=(\d+)$/)[0];
                                last CLASS;
                                }
                        }

                        $Spells_For_EQMOD{$spell_name} = $spell_level
                                if $spell_level > -1;

                }
                elsif ($filetype eq 'EQUIPMENT'
                        && $line_info->[0] eq 'EQUIPMENT'
                        && ( !exists $line_ref->{'EQMOD'} ) )
                {
                        my $equip_name = $line_ref->{'000EquipmentName'}[0];
                        my $spell_name;

                        if ( $equip_name =~ m{^Wand \((.*)/(\d\d?)(st|rd|th) level caster\)} ) {
                                $spell_name = $1;
                                my $caster_level = $2;

                                if ( exists $Spells_For_EQMOD{$spell_name} ) {
                                my $spell_level = $Spells_For_EQMOD{$spell_name};
                                my $eqmod_tag   = "EQMOD:SE_50TRIGGER|SPELLNAME[$spell_name]"
                                        . "SPELLLEVEL[$spell_level]"
                                        . "CASTERLEVEL[$caster_level]CHARGES[50]";
                                $line_ref->{'EQMOD'}    = [$eqmod_tag];
                                $line_ref->{'BASEITEM'} = ['BASEITEM:Wand']
                                        unless exists $line_ref->{'BASEITEM'};
                                delete $line_ref->{'COST'} if exists $line_ref->{'COST'};
                                $log->warning(
                                        qq{$equip_name: removing "COST" and adding "$eqmod_tag"},
                                        $file_for_error,
                                        $line_for_error
                                );
                                }
                                else {
                                $log->warning(
                                        qq($equip_name: not enough information to add charges),
                                        $file_for_error,
                                        $line_for_error
                                );
                                }
                        }
                        elsif ( $equip_name =~ /^Wand \((.*)\)/ ) {
                                $spell_name = $1;
                                if ( exists $Spells_For_EQMOD{$spell_name} ) {
                                my $spell_level  = $Spells_For_EQMOD{$spell_name};
                                my $caster_level = $spell_level * 2 - 1;
                                my $eqmod_tag   = "EQMOD:SE_50TRIGGER|SPELLNAME[$spell_name]"
                                        . "SPELLLEVEL[$spell_level]"
                                        . "CASTERLEVEL[$caster_level]CHARGES[50]";
                                $line_ref->{'EQMOD'} = [$eqmod_tag];
                                delete $line_ref->{'COST'} if exists $line_ref->{'COST'};
                                $log->warning(
                                        qq{$equip_name: removing "COST" and adding "$eqmod_tag"},
                                        $file_for_error,
                                        $line_for_error
                                );
                                }
                                else {
                                $log->warning(
                                        qq{$equip_name: not enough information to add charges},
                                        $file_for_error,
                                        $line_for_error
                                );
                                }
                        }
                        elsif ( $equip_name =~ /^Wand/ ) {
                                $log->warning(
                                qq{$equip_name: not enough information to add charges},
                                $file_for_error,
                                $line_for_error
                                );
                        }
                }
                }

                ##################################################################
                # [ 663491 ] RACE: Convert AGE, HEIGHT and WEIGHT tags
                #
                # For each HEIGHT, WEIGHT or AGE tags found in a RACE file,
                # we must call record_bioset_tags to record the AGE, HEIGHT and
                # WEIGHT tags.

                if (   isConversionActive('BIOSET:generate the new files')
                && $filetype            eq 'RACE'
                && $line_info->[0] eq 'RACE'
                && (   exists $line_ref->{'AGE'}
                        || exists $line_ref->{'HEIGHT'}
                        || exists $line_ref->{'WEIGHT'} )
                ) {
                my ( $tagLookup, $dir, $race, $age, $height, $weight );

                   $tagLookup = @{LstTidy::Reformat::getLineTypeOrder('RACE')}[0];
                   $dir       = File::Basename::dirname($file_for_error);
                   $race      = $line_ref->{ $tagLookup }[0];

                if ( $line_ref->{'AGE'} ) {
                        $age = $line_ref->{'AGE'}[0];
                        $log->warning( qq{Removing "$line_ref->{'AGE'}[0]"}, $file_for_error, $line_for_error );
                        delete $line_ref->{'AGE'};
                }
                if ( $line_ref->{'HEIGHT'} ) {
                        $height = $line_ref->{'HEIGHT'}[0];
                        $log->warning( qq{Removing "$line_ref->{'HEIGHT'}[0]"}, $file_for_error, $line_for_error );
                        delete $line_ref->{'HEIGHT'};
                }
                if ( $line_ref->{'WEIGHT'} ) {
                        $weight = $line_ref->{'WEIGHT'}[0];
                        $log->warning( qq{Removing "$line_ref->{'WEIGHT'}[0]"}, $file_for_error, $line_for_error );
                        delete $line_ref->{'WEIGHT'};
                }

                record_bioset_tags( $dir, $race, $age, $height, $weight, $file_for_error,
                        $line_for_error );
                }

                ##################################################################
                # [ 653596 ] Add a TYPE tag for all SPELLs
                # .

                if (   isConversionActive('SPELL:Add TYPE tags')
                && exists $line_ref->{'SPELLTYPE'}
                && $filetype            eq 'CLASS'
                && $line_info->[0] eq 'CLASS'
                ) {

                # We must keep a list of all the SPELLTYPE for each class.
                # It is assumed that SPELLTYPE cannot be found more than once
                # for the same class. It is also assumed that SPELLTYPE has only
                # one value. SPELLTYPE:Any is ignored.

                   my $tagLookup = @{LstTidy::Reformat::getLineTypeOrder('CLASS')}[0];
                my $class_name = $line_ref->{ $tagLookup }[0];
                SPELLTYPE_TAG:
                for my $spelltype_tag ( values %{ $line_ref->{'SPELLTYPE'} } ) {
                        my $spelltype = "";
                        ($spelltype) = ($spelltype_tag =~ /SPELLTYPE:(.*)/);
                        next SPELLTYPE_TAG if $spelltype eq "" or uc($spelltype) eq "ANY";
                        $classSpellTypes{$class_name}{$spelltype}++;
                }
                }

                if (   isConversionActive('SPELL:Add TYPE tags')
                && $filetype                    eq 'SPELL'
                && $line_info->{Linetype} eq 'SPELL' )
                {

                # For each SPELL we build the TYPE tag or we add to the
                # existing one.
                # The .MOD SPELL are ignored.

                }

                # SOURCE line replacement
                # =======================
                # Replace the SOURCELONG:xxx|SOURCESHORT:xxx|SOURCEWEB:xxx
                # with the values found in the .PCC of the same directory.
                #
                # Only the first SOURCE line found is replaced.

                if (   isConversionActive('SOURCE line replacement')
                && defined $line_info
                && $line_info->[0] eq 'SOURCE'
                && $source_curent_file ne $file_for_error )
                {

                my $inputpath =  getOption('inputpath');
                # Only the first SOURCE tag is replace.
                if ( exists $source_tags{ File::Basename::dirname($file_for_error) } ) {

                        # We replace the line with a concatanation of SOURCE tags found in
                        # the directory .PCC
                        my %line_tokens;
                        while ( my ( $tag, $value )
                                = each %{ $source_tags{ File::Basename::dirname($file_for_error) } } )
                        {
                                $line_tokens{$tag} = [$value];
                                $source_curent_file = $file_for_error;
                        }

                        $line_info->[1] = \%line_tokens;
                }
                elsif ( $file_for_error =~ / \A ${inputpath} /xmsi ) {
                        # We give this notice only if the curent file is under getOption('inputpath').
                        # If -basepath is used, there could be files loaded outside of the -inputpath
                        # without their PCC.
                        $log->notice( "No PCC source information found", $file_for_error, $line_for_error );
                }
                }

                # Extract lists
                # ====================
                # Export each file name and log them with the filename and the
                # line number

                if ( isConversionActive('Export lists') ) {
                my $filename = $file_for_error;
                $filename =~ tr{/}{\\};

                if ( $filetype eq 'SPELL' ) {

                        # Get the spell name
                        my $spellname  = $line_ref->{'000SpellName'}[0];
                        my $sourcepage = "";
                        $sourcepage = $line_ref->{'SOURCEPAGE'}[0] if exists $line_ref->{'SOURCEPAGE'};

                        # Write to file
                        LstTidy::Report::printToExportList('SPELL', qq{"$spellname","$sourcepage","$line_for_error","$filename"\n});
                }
                if ( $filetype eq 'CLASS' ) {
                        my $class = ( $line_ref->{'000ClassName'}[0] =~ /^CLASS:(.*)/ )[0];
                        if ($class_name ne $class) {
                           LstTidy::Report::printToExportList('CLASS', qq{"$class","$line_for_error","$filename"\n})
                        };
                        $class_name = $class;
                }

                if ( $filetype eq 'DEITY' ) {
                   LstTidy::Report::printToExportList('DEITY', qq{"$line_ref->{'000DeityName'}[0]","$line_for_error","$filename"\n});
                }

                if ( $filetype eq 'DOMAIN' ) {
                   LstTidy::Report::printToExportList('DOMAIN', qq{"$line_ref->{'000DomainName'}[0]","$line_for_error","$filename"\n});
                }

                if ( $filetype eq 'EQUIPMENT' ) {
                   my $tagLookup = @{LstTidy::Reformat::getLineTypeOrder($filetype)}[0];
                        my $equipname  = $line_ref->{ $tagLookup }[0];
                        my $outputname = "";
                        $outputname = substr( $line_ref->{'OUTPUTNAME'}[0], 11 )
                                if exists $line_ref->{'OUTPUTNAME'};
                        my $replacementname = $equipname;
                        if ( $outputname && $equipname =~ /\((.*)\)/ ) {
                                $replacementname = $1;
                        }
                        $outputname =~ s/\[NAME\]/$replacementname/;
                        LstTidy::Report::printToExportList('EQUIPMENT', qq{"$equipname","$outputname","$line_for_error","$filename"\n});
                }

                if ( $filetype eq 'EQUIPMOD' ) {
                   my $tagLookup = @{LstTidy::Reformat::getLineTypeOrder($filetype)}[0];
                        my $equipmodname = $line_ref->{ $tagLookup }[0];
                        my ( $key, $type ) = ( "", "" );
                        $key  = substr( $line_ref->{'KEY'}[0],  4 ) if exists $line_ref->{'KEY'};
                        $type = substr( $line_ref->{'TYPE'}[0], 5 ) if exists $line_ref->{'TYPE'};
                        LstTidy::Report::printToExportList('EQUIPMOD', qq{"$equipmodname","$key","$type","$line_for_error","$filename"\n});
                }

                if ( $filetype eq 'FEAT' ) {
                   my $tagLookup = @{LstTidy::Reformat::getLineTypeOrder($filetype)}[0];
                        my $featname = $line_ref->{ $tagLookup }[0];
                        LstTidy::Report::printToExportList('FEAT', qq{"$featname","$line_for_error","$filename"\n});
                }

                if ( $filetype eq 'KIT STARTPACK' ) {
                   my $tagLookup = @{LstTidy::Reformat::getLineTypeOrder($filetype)}[0];
                   my ($kitname) = ( $line_ref->{ $tagLookup }[0] =~ /\A STARTPACK: (.*) \z/xms );
                        LstTidy::Report::printToExportList('KIT', qq{"$kitname","$line_for_error","$filename"\n});
                }

                if ( $filetype eq 'KIT TABLE' ) {
                   my $tagLookup = @{LstTidy::Reformat::getLineTypeOrder($filetype)}[0];
                        my ($tablename)
                                = ( $line_ref->{ $tagLookup }[0] =~ /\A TABLE: (.*) \z/xms );
                        LstTidy::Report::printToExportList('TABLE', qq{"$tablename","$line_for_error","$filename"\n});
                }

                if ( $filetype eq 'LANGUAGE' ) {
                   my $tagLookup = @{LstTidy::Reformat::getLineTypeOrder($filetype)}[0];
                        my $languagename = $line_ref->{ $tagLookup }[0];
                        LstTidy::Report::printToExportList('LANGUAGE', qq{"$languagename","$line_for_error","$filename"\n});
                }

                if ( $filetype eq 'RACE' ) {
                   my $tagLookup = @{LstTidy::Reformat::getLineTypeOrder($filetype)}[0];
                        my $racename            = $line_ref->{ $tagLookup }[0];

                        my $race_type = q{};
                        $race_type = $line_ref->{'RACETYPE'}[0] if exists $line_ref->{'RACETYPE'};
                        $race_type =~ s{ \A RACETYPE: }{}xms;

                        my $race_sub_type = q{};
                        $race_sub_type = $line_ref->{'RACESUBTYPE'}[0] if exists $line_ref->{'RACESUBTYPE'};
                        $race_sub_type =~ s{ \A RACESUBTYPE: }{}xms;

                        LstTidy::Report::printToExportList('RACE', qq{"$racename","$race_type","$race_sub_type","$line_for_error","$filename"\n});
                }

                if ( $filetype eq 'SKILL' ) {
                   my $tagLookup = @{LstTidy::Reformat::getLineTypeOrder($filetype)}[0];
                        my $skillname = $line_ref->{ $tagLookup }[0];
                        LstTidy::Report::printToExportList('SKILL', qq{"$skillname","$line_for_error","$filename"\n});
                }

                if ( $filetype eq 'TEMPLATE' ) {
                   my $tagLookup = @{LstTidy::Reformat::getLineTypeOrder($filetype)}[0];
                        my $template_name = $line_ref->{ $tagLookup }[0];
                        LstTidy::Report::printToExportList('TEMPLATE', qq{"$template_name","$line_for_error","$filename"\n});
                }
                }

                ############################################################
                ######################## Conversion ########################
                # We manipulate the tags for the line here

                if ( isConversionActive('Generate BONUS and PRExxx report') ) {
                for my $tag_type ( sort keys %$line_ref ) {
                        if ( $tag_type =~ /^BONUS|^!?PRE/ ) {
                                addToBonusAndPreReport($line_ref, $filetype, $tag_type);
                        }
                }
                }

                1;
        }

}       # End of BEGIN

###############################################################
# additionnal_file_parsing
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

        sub additionnal_file_parsing {
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
                # to be renames and included in the .PCC manualy.
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

