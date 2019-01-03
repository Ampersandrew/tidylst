package LstTidy::Parse;

use strict;
use warnings;
use English;

require Exporter;

our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
   extractTag
   isParseableFileType
   isWriteableFileType
   matchLineType
   normaliseFile
   parseLine
   parseSystemFiles
   parseToken
   process000
   );

use Carp;


# expand library path so we can find LstTidy modules
use File::Basename qw(dirname);
use Cwd  qw(abs_path);
use lib dirname(dirname abs_path $0);

use LstTidy::Convert qw(convertAddTokens doTokenConversions);
use LstTidy::Data qw(
   dirHasSourceTags
   getDirSourceTags
   getEntityName 
   getValidSystemArr
   isValidTag
   registerXCheck
   setEntityValid
   setValidSystemArr
   );
use LstTidy::LogFactory qw(getLogger);
use LstTidy::Options qw(getOption isConversionActive);
use LstTidy::Token;
use LstTidy::Variable;

# Constants for the master_line_type
use constant {
   # Line importance (Mode)
   MAIN           => 1, # Main line type for the file
   SUB            => 2, # Sub line type, must be linked to a MAIN
   SINGLE         => 3, # Idependant line type
   COMMENT        => 4, # Comment or empty line.

   # Line formatting option (Format)
   LINE           => 1, # Every line formatted by itself
   BLOCK          => 2, # Lines formatted as a block
   FIRST_COLUMN   => 3, # Only the first column of the block gets aligned

   # Line header option (Header)
   NO_HEADER      => 1, # No header
   LINE_HEADER    => 2, # One header before each line
   BLOCK_HEADER   => 3, # One header for the block

   # Standard YES NO constants
   NO             => 0,
   YES            => 1,

   # The defined (non-standard) size of a tab
   TABSIZE        => 6,
};

my $className         = "";
my $sourceCurrentFile = "";
my %classSpellTypes   = ();
my %spellsForEQMOD    = ();


# Valid filetype are the only ones that will be parsed Some filetype are valid
# but not parsed yet (no function name)
my %parsableFileType = (

   INFOTEXT        => 0,
   LSTEXCLUDE      => 0,
   SOURCEDATE      => 0,
   SOURCELINK      => 0,
   SOURCELONG      => 0,
   SOURCESHORT     => 0,
   SOURCEWEB       => 0,

   '#EXTRAFILE'    => 1,
   PCC             => 1,

   ABILITY         => \&parseFile,
   ABILITYCATEGORY => \&parseFile,
   ALIGNMENT       => \&parseFile,
   ARMORPROF       => \&parseFile,
   BIOSET          => \&parseFile,
   CLASS           => \&parseFile,
   COMPANIONMOD    => \&parseFile,
   DATACONTROL     => \&parseFile,
   DEITY           => \&parseFile,
   DOMAIN          => \&parseFile,
   EQUIPMENT       => \&parseFile,
   EQUIPMOD        => \&parseFile,
   FEAT            => \&parseFile,
   GLOBALMODIFIER  => \&parseFile,
   KIT             => \&parseFile,
   LANGUAGE        => \&parseFile,
   RACE            => \&parseFile,
   SAVE            => \&parseFile,
   SHIELDPROF      => \&parseFile,
   SKILL           => \&parseFile,
   SPELL           => \&parseFile,
   STAT            => \&parseFile,
   TEMPLATE        => \&parseFile,
   VARIABLE        => \&parseFile,
   WEAPONPROF      => \&parseFile,
);






=head2 parseFile

   placeholder, will be replaced when the script is split up.

=cut

sub parseFile {
   return 1;
};


=head2 setParseRoutine

   placeholder, will be replaced when the script is split up.

=cut

sub setParseRoutine {
   my ($ref) = @_;

   # Replace the placeholder routines with the routine from the script
   for my $key (keys %parsableFileType) {
      if (ref $parsableFileType{$key} eq 'CODE') {
         $parsableFileType{$key} = $ref;
      }
   }
}

# The file type that will be rewritten.
my %writefiletype = (
   '#EXTRAFILE'      => 0,
   'COPYRIGHT'       => 0,
   'COVER'           => 0,
   'INFOTEXT'        => 0,
   'LSTEXCLUDE'      => 0,

   'ABILITY'         => 1,
   'ABILITYCATEGORY' => 1,
   'ALIGNMENT'       => 1,
   'ARMORPROF'       => 1,
   'BIOSET'          => 1,
   'CLASS Level'     => 1,
   'CLASS'           => 1,
   'COMPANIONMOD'    => 1,
   'DATACONTROL'     => 1,
   'DEITY'           => 1,
   'DOMAIN'          => 1,
   'EQUIPMENT'       => 1,
   'EQUIPMOD'        => 1,
   'FEAT'            => 1,
   'GLOBALMODIFIER'  => 1,
   'KIT'             => 1,
   'LANGUAGE'        => 1,
   'PCC'             => 1,
   'RACE'            => 1,
   'SAVE'            => 1,
   'SHIELDPROF'      => 1,
   'SKILL'           => 1,
   'SPELL'           => 1,
   'STAT'            => 1,
   'TEMPLATE'        => 1,
   'VARIABLE'        => 1,
   'WEAPONPROF'      => 1,
);

# The SOURCE line is use in nearly all file types
our %SourceLineDef = (
   Linetype  => 'SOURCE',
   RegEx     => qr(^SOURCE\w*:([^\t]*)),
   Mode      => SINGLE,
   Format    => LINE,
   Header    => NO_HEADER,
   SepRegEx  => qr{ (?: [|] ) | (?: \t+ ) }xms,  # Catch both | and tab
);

# Some people may still want to use the old ways (for PCGen v5.9.5 and older)
if( getOption('oldsourcetag') ) {
   $SourceLineDef{Sep} = q{|};  # use | instead of [tab] to split
}

# Information needed to parse the line type
our %parseControl = (

   ABILITY => [
      \%SourceLineDef,
      {  Linetype       => 'ABILITY',
         RegEx          => qr(^([^\t:]+)),
         Mode           => MAIN,
         Format         => BLOCK,
         Header         => BLOCK_HEADER,
         ValidateKeep   => YES,
      },
   ],

   ABILITYCATEGORY => [
      \%SourceLineDef,
      {  Linetype       => 'ABILITYCATEGORY',
         RegEx          => qr(^([^\t:]+)),
         Mode           => MAIN,
         Format         => BLOCK,
         Header         => BLOCK_HEADER,
         ValidateKeep   => YES,
      },
   ],
   
   ALIGNMENT => [
      \%SourceLineDef,
      {  Linetype       => 'ALIGNMENT',
         RegEx          => qr(^([^\t:]+)),
         Mode           => MAIN,
         Format         => BLOCK,
         Header         => BLOCK_HEADER,
         ValidateKeep   => YES,
      },
   ],

   ARMORPROF => [
      \%SourceLineDef,
      {  Linetype       => 'ARMORPROF',
         RegEx          => qr(^([^\t:]+)),
         Mode           => MAIN,
         Format         => BLOCK,
         Header         => BLOCK_HEADER,
         ValidateKeep   => YES,
      },
   ],

   BIOSET => [
      \%SourceLineDef,
      {  Linetype       => 'BIOSET AGESET',
         RegEx          => qr(^AGESET:([^\t]*)),
         Mode           => MAIN,
         Format         => BLOCK,
         Header         => NO_HEADER,
         ValidateKeep   => YES,
         RegExIsMod     => qr(AGESET:(.*)\.([^\t]+)),
         RegExGetEntry  => qr(AGESET:(.*)),
      },
      {  Linetype       => 'BIOSET RACENAME',
         RegEx          => qr(^RACENAME:([^\t]*)),
         Mode           => SUB,
         Format         => FIRST_COLUMN,
         Header         => NO_HEADER,
      },
   ],

   CLASS => [
      {  Linetype       => 'CLASS Level',
         RegEx          => qr(^(\d+)($|\t|:REPEATLEVEL:\d+)),
         Mode           => SUB,
         Format         => BLOCK,
         Header         => NO_HEADER,
      },
      {  Linetype       => 'CLASS',
         RegEx          => qr(^CLASS:([^\t]*)),
         Mode           => MAIN,
         Format         => LINE,
         Header         => LINE_HEADER,
         ValidateKeep   => YES,
         RegExIsMod     => qr(CLASS:(.*)\.(MOD|FORGET|COPY=[^\t]+)),
         RegExGetEntry  => qr(CLASS:(.*)),
      },
      \%SourceLineDef,
      {  Linetype          => 'SUBCLASS',
         RegEx             => qr(^SUBCLASS:([^\t]*)),
         Mode              => SUB,
         Format            => BLOCK,
         Header            => NO_HEADER,
         ValidateKeep      => YES,
         RegExIsMod        => qr(SUBCLASS:(.*)\.(MOD|FORGET|COPY=[^\t]+)),
         RegExGetEntry     => qr(SUBCLASS:(.*)),
         # SUBCLASS can be refered to anywhere CLASS works.
         OtherValidEntries => ['CLASS'],
      },
      {  Linetype          => 'SUBSTITUTIONCLASS',
         RegEx             => qr(^SUBSTITUTIONCLASS:([^\t]*)),
         Mode              => SUB,
         Format            => BLOCK,
         Header            => NO_HEADER,
         ValidateKeep      => YES,
         RegExIsMod        => qr(SUBSTITUTIONCLASS:(.*)\.(MOD|FORGET|COPY=[^\t]+)),
         RegExGetEntry     => qr(SUBSTITUTIONCLASS:(.*)),
         # SUBSTITUTIONCLASS can be refered to anywhere CLASS works.
         OtherValidEntries => ['CLASS'],
      },
      {  Linetype          => 'SUBCLASSLEVEL',
         RegEx             => qr(^SUBCLASSLEVEL:([^\t]*)),
         Mode              => SUB,
         Format            => BLOCK,
         Header            => NO_HEADER,
      },
      {  Linetype          => 'SUBSTITUTIONLEVEL',
         RegEx             => qr(^SUBSTITUTIONLEVEL:([^\t]*)),
         Mode              => SUB,
         Format            => BLOCK,
         Header            => NO_HEADER,
      },
   ],

   COMPANIONMOD => [
      \%SourceLineDef,
      { Linetype        => 'SWITCHRACE',
         RegEx          => qr(^SWITCHRACE:([^\t]*)),
         Mode           => SINGLE,
         Format         => LINE,
         Header         => NO_HEADER,
      },
      { Linetype        => 'COMPANIONMOD',
         RegEx          => qr(^FOLLOWER:([^\t]*)),
         Mode           => MAIN,
         Format         => BLOCK,
         Header         => BLOCK_HEADER,
         ValidateKeep   => YES,
         RegExIsMod     => qr(FOLLOWER:(.*)\.(MOD|FORGET|COPY=[^\t]+)),
         RegExGetEntry  => qr(FOLLOWER:(.*)),

         # Identifier that refer to other entry type
         IdentRefType   => 'CLASS,DEFINE Variable',
         IdentRefTag    => 'FOLLOWER',  # Tag name for the reference check
         # Get the list of reference identifiers
         # The syntax is FOLLOWER:class1,class2=level
         # We need to extract the class names.
         GetRefList     => sub { split q{,}, ( $_[0] =~ / \A ( [^=]* ) /xms )[0]  },
      },
      { Linetype        => 'MASTERBONUSRACE',
         RegEx          => qr(^MASTERBONUSRACE:([^\t]*)),
         Mode           => MAIN,
         Format         => BLOCK,
         Header         => BLOCK_HEADER,
         ValidateKeep   => YES,
         RegExIsMod     => qr(MASTERBONUSRACE:(.*)\.(MOD|FORGET|COPY=[^\t]+)),
         RegExGetEntry  => qr(MASTERBONUSRACE:(.*)),
         IdentRefType   => 'RACE',                 # Identifier that refers to other entry type
         IdentRefTag    => 'MASTERBONUSRACE',      # Tag name for the reference check
         # Get the list of reference identifiers
         # The syntax is MASTERBONUSRACE:race
         # We need to extract the race name.
         GetRefList     => sub { return @_ },
      },
   ],

   DATACONTROL => [
      \%SourceLineDef,
      {  Linetype       => 'DATACONTROL DEFAULTVARIABLEVALUE',
         RegEx          => qr{^DEFAULTVARIABLEVALUE([^\t]*)},
         Mode           => SINGLE,
         Format         => LINE,
         Header         => NO_HEADER,
      },
      {  Linetype       => 'DATACONTROL FUNCTION',
         RegEx          => qr{^FUNCTION([^\t]*)},
         Mode           => MAIN,
         Format         => BLOCK,
         Header         => BLOCK_HEADER,
      },
      {  Linetype       => 'DATACONTROL FACTDEF',
         RegEx          => qr{^FACTDEF([^\t]*)},
         Mode           => MAIN,
         Format         => BLOCK,
         Header         => BLOCK_HEADER,
      },
      {  Linetype       => 'DATACONTROL FACTSETDEF',
         RegEx          => qr{^FACTSETDEF([^\t]*)},
         Mode           => MAIN,
         Format         => BLOCK,
         Header         => BLOCK_HEADER,
      },
   ],

   DEITY => [
      \%SourceLineDef,
      {  Linetype       => 'DEITY',
         RegEx          => qr(^([^\t:]+)),
         Mode           => MAIN,
         Format         => BLOCK,
         Header         => BLOCK_HEADER,
         ValidateKeep   => YES,
      },
   ],

   DOMAIN => [
      \%SourceLineDef,
      {  Linetype       => 'DOMAIN',
         RegEx          => qr(^([^\t:]+)),
         Mode           => MAIN,
         Format         => BLOCK,
         Header         => BLOCK_HEADER,
         ValidateKeep   => YES,
      },
   ],

   EQUIPMENT => [
      \%SourceLineDef,
      {  Linetype       => 'EQUIPMENT',
         RegEx          => qr(^([^\t:]+)),
         Mode           => MAIN,
         Format         => BLOCK,
         Header         => BLOCK_HEADER,
         ValidateKeep   => YES,
      },
   ],

   EQUIPMOD => [
      \%SourceLineDef,
      {  Linetype       => 'EQUIPMOD',
         RegEx          => qr(^([^\t:]+)),
         Mode           => MAIN,
         Format         => BLOCK,
         Header         => BLOCK_HEADER,
         ValidateKeep   => YES,
      },
   ],

   FEAT => [
      \%SourceLineDef,
      {  Linetype       => 'FEAT',
         RegEx          => qr(^([^\t:]+)),
         Mode           => MAIN,
         Format         => BLOCK,
         Header         => BLOCK_HEADER,
         ValidateKeep   => YES,
      },
   ],

   GLOBALMODIFIER => [
      \%SourceLineDef,
      {  Linetype       => 'GLOBALMODIFIER',
         RegEx          => qr(^([^\t:]+)),
         Mode           => MAIN,
         Format         => BLOCK,
         Header         => BLOCK_HEADER,
         ValidateKeep   => YES,
      },
   ],

   KIT => [
      \%SourceLineDef,
      {  Linetype       => 'KIT REGION',                 # Kits are grouped by Region.
         RegEx          => qr{^REGION:([^\t]*)},         # So REGION has a line of its own.
         Mode           => SINGLE,
         Format         => LINE,
         Header         => NO_HEADER,
      },
      {  Linetype       => 'KIT STARTPACK',              # The KIT name is defined here
         RegEx          => qr{^STARTPACK:([^\t]*)},
         Mode           => MAIN,
         Format         => LINE,
         Header         => NO_HEADER,
         ValidateKeep   => YES,
      },
      {  Linetype       => 'KIT ABILITY',
         RegEx          => qr{^ABILITY:([^\t]*)},
         Mode           => SUB,
         Format         => FIRST_COLUMN,
         Header         => NO_HEADER,
      },
      {  Linetype       => 'KIT AGE',
         RegEx          => qr{^AGE:([^\t]*)},
         Mode           => SUB,
         Format         => FIRST_COLUMN,
         Header         => NO_HEADER,
      },
      {  Linetype       => 'KIT ALIGN',
         RegEx          => qr{^ALIGN:([^\t]*)},
         Mode           => SUB,
         Format         => FIRST_COLUMN,
         Header         => NO_HEADER,
      },
      {  Linetype       => 'KIT CLASS',
         RegEx          => qr{^CLASS:([^\t]*)},
         Mode           => SUB,
         Format         => FIRST_COLUMN,
         Header         => NO_HEADER,
      },
      {  Linetype       => 'KIT DEITY',
         RegEx          => qr{^DEITY:([^\t]*)},
         Mode           => SUB,
         Format         => FIRST_COLUMN,
         Header         => NO_HEADER,
      },
      {  Linetype       => 'KIT FEAT',
         RegEx          => qr{^FEAT:([^\t]*)},
         Mode           => SUB,
         Format         => BLOCK,
         Header         => NO_HEADER,
      },
      {  Linetype       => 'KIT FUNDS',
         RegEx          => qr{^FUNDS:([^\t]*)},
         Mode           => SUB,
         Format         => BLOCK,
         Header         => NO_HEADER,
      },
      {  Linetype       => 'KIT GEAR',
         RegEx          => qr{^GEAR:([^\t]*)},
         Mode           => SUB,
         Format         => BLOCK,
         Header         => NO_HEADER,
      },
      {  Linetype       => 'KIT GENDER',
         RegEx          => qr{^GENDER:([^\t]*)},
         Mode           => SUB,
         Format         => FIRST_COLUMN,
         Header         => NO_HEADER,
      },
      {  Linetype       => 'KIT KIT',
         RegEx          => qr{^KIT:([^\t]*)},
         Mode           => SUB,
         Format         => FIRST_COLUMN,
         Header         => NO_HEADER,
      },
      {  Linetype       => 'KIT LANGAUTO',
         RegEx          => qr{^LANGAUTO:([^\t]*)},
         Mode           => SUB,
         Format         => FIRST_COLUMN,
         Header         => NO_HEADER,
      },
      {  Linetype       => 'KIT LANGBONUS',
         RegEx          => qr{^LANGBONUS:([^\t]*)},
         Mode           => SUB,
         Format         => FIRST_COLUMN,
         Header         => NO_HEADER,
      },
      {  Linetype       => 'KIT LEVELABILITY',
         RegEx          => qr{^LEVELABILITY:([^\t]*)},
         Mode           => SUB,
         Format         => FIRST_COLUMN,
         Header         => NO_HEADER,
      },
      {  Linetype       => 'KIT NAME',
         RegEx          => qr{^NAME:([^\t]*)},
         Mode           => SUB,
         Format         => FIRST_COLUMN,
         Header         => NO_HEADER,
      },
      {  Linetype       => 'KIT PROF',
         RegEx          => qr{^PROF:([^\t]*)},
         Mode           => SUB,
         Format         => BLOCK,
         Header         => NO_HEADER,
      },
      {  Linetype       => 'KIT RACE',
         RegEx          => qr{^RACE:([^\t]*)},
         Mode           => SUB,
         Format         => FIRST_COLUMN,
         Header         => NO_HEADER,
      },
      {  Linetype       => 'KIT SELECT',
         RegEx          => qr{^SELECT:([^\t]*)},
         Mode           => SUB,
         Format         => FIRST_COLUMN,
         Header         => NO_HEADER,
      },
      {  Linetype       => 'KIT SKILL',
         RegEx          => qr{^SKILL:([^\t]*)},
         Mode           => SUB,
         Format         => BLOCK,
         Header         => NO_HEADER,
      },
      {  Linetype       => 'KIT STAT',
         RegEx          => qr{^STAT:([^\t]*)},
         Mode           => SUB,
         Format         => FIRST_COLUMN,
         Header         => NO_HEADER,
      },
      {  Linetype       => 'KIT SPELLS',
         RegEx          => qr{^SPELLS:([^\t]*)},
         Mode           => SUB,
         Format         => BLOCK,
         Header         => NO_HEADER,
      },
      {  Linetype       => 'KIT TABLE',
         RegEx          => qr{^TABLE:([^\t]*)},
         Mode           => SUB,
         Format         => FIRST_COLUMN,
         Header         => NO_HEADER,
         ValidateKeep   => YES,
      },
      {  Linetype       => 'KIT TEMPLATE',
         RegEx          => qr{^TEMPLATE:([^\t]*)},
         Mode           => SUB,
         Format         => FIRST_COLUMN,
         Header         => NO_HEADER,
      },
   ],

   LANGUAGE => [
      \%SourceLineDef,
      {  Linetype       => 'LANGUAGE',
         RegEx          => qr(^([^\t:]+)),
         Mode           => MAIN,
         Format         => BLOCK,
         Header         => BLOCK_HEADER,
         ValidateKeep   => YES,
      },
   ],

   RACE => [
      \%SourceLineDef,
      {  Linetype       => 'RACE',
         RegEx          => qr(^([^\t:]+)),
         Mode           => MAIN,
         Format         => BLOCK,
         Header         => BLOCK_HEADER,
         ValidateKeep   => YES,
      },
   ],

   SAVE => [
      \%SourceLineDef,
      {  Linetype       => 'SAVE',
         RegEx          => qr(^([^\t:]+)),
         Mode           => MAIN,
         Format         => BLOCK,
         Header         => BLOCK_HEADER,
         ValidateKeep   => YES,
      },
   ],

   SHIELDPROF => [
      \%SourceLineDef,
      {  Linetype       => 'SHIELDPROF',
         RegEx          => qr(^([^\t:]+)),
         Mode           => MAIN,
         Format         => BLOCK,
         Header         => BLOCK_HEADER,
         ValidateKeep   => YES,
      },
   ],

   SKILL => [
      \%SourceLineDef,
      {  Linetype       => 'SKILL',
         RegEx          => qr(^([^\t:]+)),
         Mode           => MAIN,
         Format         => BLOCK,
         Header         => BLOCK_HEADER,
         ValidateKeep   => YES,
      },
   ],

   SPELL => [
      \%SourceLineDef,
      {  Linetype       => 'SPELL',
         RegEx          => qr(^([^\t:]+)),
         Mode           => MAIN,
         Format         => BLOCK,
         Header         => BLOCK_HEADER,
         ValidateKeep   => YES,
      },
   ],

   STAT => [
      \%SourceLineDef,
      {  Linetype       => 'STAT',
         RegEx          => qr(^([^\t:]+)),
         Mode           => MAIN,
         Format         => BLOCK,
         Header         => BLOCK_HEADER,
         ValidateKeep   => YES,
      },
   ],

   TEMPLATE => [
      \%SourceLineDef,
      {  Linetype       => 'TEMPLATE',
         RegEx          => qr(^([^\t:]+)),
         Mode           => MAIN,
         Format         => BLOCK,
         Header         => BLOCK_HEADER,
         ValidateKeep   => YES,
      },
   ],

   VARIABLE => [
      \%SourceLineDef,
      {  Linetype       => 'VARIABLE',
         RegEx          => qr(^([^\t:]+)),
         Mode           => MAIN,
         Format         => BLOCK,
         Header         => BLOCK_HEADER,
         ValidateKeep   => YES,
      },
   ],

   WEAPONPROF => [
      \%SourceLineDef,
      {  Linetype       => 'WEAPONPROF',
         RegEx          => qr(^([^\t:]+)),
         Mode           => MAIN,
         Format         => BLOCK,
         Header         => BLOCK_HEADER,
         ValidateKeep   => YES,
      },
   ],
   
# New files already added

# ALIGNMENT
# DATACONTROL
# GLOBALMODIFIER
# SAVE
# STAT
# VARIABLE

# New files, not added yet

   'DATATABLE' => [
      \%SourceLineDef,
   ],

   'DYNAMIC' => [
      \%SourceLineDef,
   ],

   'SIZE' => [
      \%SourceLineDef,
      {  Linetype       => 'DATACONTROL',
         RegEx          => qr(^([^\t:]+)),
         Mode           => MAIN,
         Format         => BLOCK,
         Header         => BLOCK_HEADER,
         ValidateKeep   => YES,
      },
   ],

);

=head2 getParseControl

   Get the Parse control record where the lineType field of the record matches
   the key used to look it up. This ensure we get the main record for the line
   type as lines can multiple linetype records.

=cut

sub getParseControl {
   my ($fileType) = @_;

   for my $rec ( @{ $parseControl{$fileType} } ) {
      return $rec if $rec->{ lineType } = $fileType;
   }

   # didn't find the record
   return undef;
}



=head2 isParseableFileType

   Returns a code ref that can be used to parse the lst file.

=cut

sub isParseableFileType {
   my ($fileType) = @_;

   return $parsableFileType{$fileType};
}

=head2 isWriteableFileType

   Returns true if the system should rewrite the given file type

=cut

sub isWriteableFileType {
   my $file = shift;

   return $writefiletype{$file};
}

=head2 matchLineType

   Match the given line, and return the line definition.

=cut

sub matchLineType {
   my ($line, $fileType) = @_;

   # Try each of the line types for this file type until we get a match or
   # exhaust the types.

   my ($lineSpec, $entity);
   for my $rec ( @{ $parseControl{$fileType} } ) {
      if ( $line =~ $rec->{RegEx} ) {

         $lineSpec = $rec;
         $entity   = $1;
         last;
      }
   }

   return($lineSpec, $entity);
}

=head2 normaliseFile

   Detect filetype and normalize lines

   Parameters: $buffer => raw file data in a single buffer

   Returns: $filetype => either 'tab-based' or 'multi-line'
            $lines => arrayref containing logical lines normalized to tab-based format

=cut

sub normaliseFile {

   # TODO: handle empty buffers, other corner-cases
   my $buffer = shift || "";     # default to empty line when passed undef

   my $filetype;
   my @lines;

   # First, we clean out empty lines that contain only white-space. Otherwise,
   # we could have false positives on the filetype.  Simply remove all
   # whitespace that is alone on its line.

   $buffer =~ s/^\s*$//g;

   # having a tab as a first character on a non-whitespace line is a sign of a
   # multi-line file

   if ($buffer =~ /^\t+\S/m) {

      $filetype = "multi-line";

      # Normalize to tab-based
      # 1) All lines that start with a tab belong to the previous line.
      # 2) Copy the lines as-is to the end of the previous line

      # We use a regexp that just removes the newlines, which is easier than
      # copying

      $buffer =~ s/\n\t/\t/mg;

      @lines = split /\n/, $buffer;

   } else {
      $filetype = "tab-based";
   }

   # Split into an array of lines.
   @lines = split /\n/, $buffer;

   # return a arrayref so we are a little more efficient
   return (\@lines, $filetype);
}


###############################################################
# parseLine
# ------------------------
#
# This function does additional parsing on each line once
# they have been seperated into tokens.
#
# Most commun use is for addition, conversion or removal of tokens.
#
# Paramter: $filetype   Type for the current file
#           $lineTokens Ref to a hash containing the tokens of the line
#           $file       Name of the current file
#           $line       Number of the current line
#           $line_info  (Optional) structure generated by FILETYPE_parse
#


sub parseLine {

   my ( $filetype, $lineTokens, $file, $line, $line_info ) = @_;

   my $log = getLogger();

   ##################################################################
   # [ 1596310 ] xcheck: TYPE:Spellbook for equip w/ NUMPAGES and PAGEUSAGE
   # Gawaine42 (Richard)
   # Check to see if the TYPE contains Spellbook, if so, warn if
   # NUMUSES or PAGEUSAGE aren't there.
   # Then check to see if NUMPAGES or PAGEUSAGE are there, and if they
   # are there, but the TYPE doesn't contain Spellbook, warn.

   if ($filetype eq 'EQUIPMENT') {

      if (exists $lineTokens->{'TYPE'} && $lineTokens->{'TYPE'}[0] =~ /Spellbook/) {

         if (exists $lineTokens->{'NUMPAGES'} && exists $lineTokens->{'PAGEUSAGE'}) {
            #Nothing to see here, move along.
         } else {
            $log->info(
               qq{You have a Spellbook defined without providing NUMPAGES or PAGEUSAGE.} 
               . qq{ If you want a spellbook of finite capacity, consider adding these tokens.},
               $file,
               $line
            );
         }

      } else {

         if (exists $lineTokens->{'NUMPAGES'} ) {
            $log->warning(
               qq{Invalid use of NUMPAGES token in a non-spellbook. Remove this token, or correct the TYPE.},
               $file,
               $line
            );
         }

         if  (exists $lineTokens->{'PAGEUSAGE'})
         {
            $log->warning(
               qq{Invalid use of PAGEUSAGE token in a non-spellbook. Remove this token, or correct the TYPE.},
               $file,
               $line
            );
         }
      }

      #################################################################
      #  Do the same for Type Container with and without CONTAINS
      if (exists $lineTokens->{'TYPE'} && $lineTokens->{'TYPE'}[0] =~ /Container/) {

         if (exists $lineTokens->{'CONTAINS'}) {
#           $lineTokens =~ s/'CONTAINS:-1'/'CONTAINS:UNLIM'/g;   # [ 1777282 ] CONTAINS Unlimited Weight is UNLIM, not -1
         } else {
            $log->warning(
               qq{Any object with TYPE:Container must also have a CONTAINS token to be activated.},
               $file,
               $line
            );
         }

      } elsif (exists $lineTokens->{'CONTAINS'}) {

         $log->warning(
            qq{Any object with CONTAINS must also be TYPE:Container for the CONTAINS token to be activated.},
            $file,
            $line
         );
      }

   }

   ##################################################################
   # [ 1864711 ] Convert ADD:SA to ADD:SAB
   #
   # In most files, take ADD:SA and replace with ADD:SAB

   if (isConversionActive('ALL:Convert ADD:SA to ADD:SAB') && exists $lineTokens->{'ADD:SA'}) {
      $log->warning(
         qq{Change ADD:SA for ADD:SAB in "$lineTokens->{'ADD:SA'}[0]"},
         $file,
         $line
      );
      my $satag;
      $satag = $lineTokens->{'ADD:SA'}[0];
      $satag =~ s/ADD:SA/ADD:SAB/;
      $lineTokens->{'ADD:SAB'}[0] = $satag;
      delete $lineTokens->{'ADD:SA'};
   }



   ##################################################################
   # [ 1514765 ] Conversion to remove old defaultmonster tags
   # Gawaine42 (Richard Bowers)
   # Bonuses associated with a PREDEFAULTMONSTER:Y need to be removed
   # This should remove the whole tag.
   if (isConversionActive('RACE:Fix PREDEFAULTMONSTER bonuses') && $filetype eq "RACE") {

      for my $key ( keys %$lineTokens ) {

         my $ary = $lineTokens->{$key};
         my $iCount = 0;

         foreach (@$ary) {
            my $ttag = $$ary[$iCount];
            if ($ttag =~ /PREDEFAULTMONSTER:Y/) {
               $$ary[$iCount] = "";
               $log->warning(
                  qq{Removing "$ttag".},
                  $file,
                  $line
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
      && exists $lineTokens->{'ALTCRITICAL'}
   ) {
      # Throw warning if both ALTCRITICAL and ALTCRITMULT are on the same line,
      #   then remove ALTCRITICAL.
      if ( exists $lineTokens->{ALTCRITMULT} ) {
         $log->warning(
            qq{Removing ALTCRITICAL, ALTCRITMULT already present on same line.},
            $file,
            $line
         );
         delete $lineTokens->{'ALTCRITICAL'};
      } else {
         $log->warning(
            qq{Change ALTCRITICAL for ALTCRITMULT in "$lineTokens->{'ALTCRITICAL'}[0]"},
            $file,
            $line
         );
         my $ttag;
         $ttag = $lineTokens->{'ALTCRITICAL'}[0];
         $ttag =~ s/ALTCRITICAL/ALTCRITMULT/;
         $lineTokens->{'ALTCRITMULT'}[0] = $ttag;
         delete $lineTokens->{'ALTCRITICAL'};
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
      && exists $lineTokens->{'MFEAT'}
   ) { 
      
      if ( exists $lineTokens->{'MONSTERCLASS'}) { 

         for my $tag ( @{ $lineTokens->{'MFEAT'} } ) {
            $log->warning(
               qq{Removing "$tag".},
               $file,
               $line
            );
         }
         delete $lineTokens->{'MFEAT'};
      }
      else {$log->warning(
            qq{MONSTERCLASS missing on same line as MFEAT, need to look at by hand.},
            $file,
            $line
         );
      }
   }

   # We remove HITDICE or warn of missing MONSTERCLASS tag.
   if (   isConversionActive('RACE:Remove MFEAT and HITDICE')
      && $filetype eq "RACE"
      && exists $lineTokens->{'HITDICE'}
   ) { 
      
      if ( exists $lineTokens->{'MONSTERCLASS'}) { 
         
         for my $tag ( @{ $lineTokens->{'HITDICE'} } ) {
            $log->warning(
               qq{Removing "$tag".},
               $file,
               $line
            );
         }
         delete $lineTokens->{'HITDICE'};

      } else {
         
         $log->warning(
            qq{MONSTERCLASS missing on same line as HITDICE, need to look at by hand.},
            $file,
            $line
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
      && (exists $lineTokens->{'FOLLOWERALIGN'}))
   {
      my $followeralign = $lineTokens->{'FOLLOWERALIGN'}[0];
      $followeralign =~ s/^FOLLOWERALIGN://;
      my $newprealign = "";
      my $aligncount  = 0;
      my @valid_alignments = getValidSystemArr('alignments');

      for my $align (split //, $followeralign) {
         # Is it a number?
         my $number;
         if ( (($number) = ($align =~ / \A (\d+) \z /xms))
            && $number >= 0
            && $number < scalar @valid_alignments)
         {
            my $newalign = $valid_alignments[$number];
            if ($aligncount > 0) {
               $newprealign .= ',';
            }
            $aligncount++;
            $newprealign .= "$newalign";
         }
         else {
            $log->notice(
               qq{Invalid value "$align" for tag "$lineTokens->{'FOLLOWERALIGN'}[0]"},
               $file,
               $line
            );

         }
      }

      my $dom_count=0;

      if (exists $lineTokens->{'DOMAINS'}) {
         for my $line ($lineTokens->{'DOMAINS'})
         {
            $lineTokens->{'DOMAINS'}[$dom_count] .= "|PREALIGN:$newprealign";
            $dom_count++;
         }
         $log->notice(
            qq{Adding PREALIGN to domain information and removing "$lineTokens->{'FOLLOWERALIGN'}[0]"},
            $file,
            $line
         );

         delete $lineTokens->{'FOLLOWERALIGN'};
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
      && not ( exists $lineTokens->{'RACETYPE'} )
      && not ( exists $lineTokens->{'TYPE'}  )
   ) {
      # .MOD / .FORGET / .COPY don't need RACETYPE or TYPE'
      my $race_name = $lineTokens->{'000RaceName'}[0];
      if ($race_name =~ /\.(FORGET|MOD|COPY=.+)$/) {
      } else { $log->warning(
            qq{Race entry missing both TYPE and RACETYPE.},
            $file,
            $line
         );
      }
   };

   if (   isConversionActive('RACE:TYPE to RACETYPE')
      && ( $filetype eq "RACE"
         || $filetype eq "TEMPLATE" )
      && not (exists $lineTokens->{'RACETYPE'})
      && exists $lineTokens->{'TYPE'}
   ) { $log->warning(
         qq{Changing TYPE for RACETYPE in "$lineTokens->{'TYPE'}[0]".},
         $file,
         $line
      );
      $lineTokens->{'RACETYPE'} = [ "RACE" . $lineTokens->{'TYPE'}[0] ];
      delete $lineTokens->{'TYPE'};
   };



   ##################################################################
   # [ 1444527 ] New SOURCE tag format
   #
   # The SOURCELONG tags found on any linetype but the SOURCE line type must
   # be converted to use tab if | are found.

   if (   isConversionActive('ALL:New SOURCExxx tag format')
      && exists $lineTokens->{'SOURCELONG'} ) {
      my @new_tags;

      for my $tag ( @{ $lineTokens->{'SOURCELONG'} } ) {
         if( $tag =~ / [|] /xms ) {
            push @new_tags, split '\|', $tag;
            $log->warning(
               qq{Spliting "$tag"},
               $file,
               $line
            );
         }
      }

      if( @new_tags ) {
         delete $lineTokens->{'SOURCELONG'};

         for my $new_tag (@new_tags) {
            my ($tag_name) = ( $new_tag =~ / ( [^:]* ) [:] /xms );
            push @{ $lineTokens->{$tag_name} }, $new_tag;
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
      && exists $lineTokens->{'SPELL'} )
   {
      my %spellbooks;

      # We parse all the existing SPELL tags
      for my $tag ( @{ $lineTokens->{'SPELL'} } ) {
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
                  $file,
                  $line
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
            $file,
            $line
         );
      }

      # We delete the SPELL tags
      delete $lineTokens->{'SPELL'};

      # We add the new SPELLS tags
      for my $spellbook ( sort keys %spellbooks ) {
         for my $times ( sort keys %{ $spellbooks{$spellbook} } ) {
            for my $pretags ( sort keys %{ $spellbooks{$spellbook}{$times} } ) {
               my $spells = "SPELLS:$spellbook|TIMES=$times";

               for my $spellname ( sort @{ $spellbooks{$spellbook}{$times}{$pretags} } ) {
                  $spells .= "|$spellname";
               }

               $spells .= "|$pretags" unless $pretags eq "NONE";

               $log->warning( qq{Adding   "$spells"}, $file, $line );

               push @{ $lineTokens->{'SPELLS'} }, $spells;
            }
         }
      }
   }

   ##################################################################
   # We get rid of all the PREALIGN tags.
   #
   # This is needed by my good CMP friends.

   if ( isConversionActive('ALL:CMP remove PREALIGN') ) {
      if ( exists $lineTokens->{'PREALIGN'} ) {
         my $number = +@{ $lineTokens->{'PREALIGN'} };
         delete $lineTokens->{'PREALIGN'};
         $log->warning(
            qq{Removing $number PREALIGN tags},
            $file,
            $line
         );
      }

      if ( exists $lineTokens->{'!PREALIGN'} ) {
         my $number = +@{ $lineTokens->{'!PREALIGN'} };
         delete $lineTokens->{'!PREALIGN'};
         $log->warning(
            qq{Removing $number !PREALIGN tags},
            $file,
            $line
         );
      }
   }

   ##################################################################
   # Need to fix the STR bonus when the monster have only one
   # Natural Attack (STR bonus is then 1.5 * STR).
   # We add it if there is only one Melee attack and the
   # bonus is not already present.

   if ( isConversionActive('ALL:CMP NatAttack fix')
      && exists $lineTokens->{'NATURALATTACKS'} )
   {

      # First we verify if if there is only one melee attack.
      if ( @{ $lineTokens->{'NATURALATTACKS'} } == 1 ) {
         my @NatAttacks = split '\|', $lineTokens->{'NATURALATTACKS'}[0];
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
                  if ( exists $lineTokens->{'BONUS:WEAPONPROF'} ) {
                     my $AlreadyThere = 0;
                     FIND_BONUS:
                     for my $bonus ( @{ $lineTokens->{'BONUS:WEAPONPROF'} } ) {
                        if ( $bonus eq "BONUS:WEAPONPROF=$NatAttackName|DAMAGE|STR/2" )
                        {
                           $AlreadyThere = 1;
                           last FIND_BONUS;
                        }
                     }

                     unless ($AlreadyThere) {
                        push @{ $lineTokens->{'BONUS:WEAPONPROF'} },
                        "BONUS:WEAPONPROF=$NatAttackName|DAMAGE|STR/2";
                        $log->warning(
                           qq{Added "$lineTokens->{'BONUS:WEAPONPROF'}[0]"}
                           . qq{ to go with "$lineTokens->{'NATURALATTACKS'}[0]"},
                           $file,
                           $line
                        );
                     }
                  }
                  else {
                     $lineTokens->{'BONUS:WEAPONPROF'}
                     = ["BONUS:WEAPONPROF=$NatAttackName|DAMAGE|STR/2"];
                     $log->warning(
                        qq{Added "$lineTokens->{'BONUS:WEAPONPROF'}[0]"}
                        . qq{to go with "$lineTokens->{'NATURALATTACKS'}[0]"},
                        $file,
                        $line
                     );
                  }
               }
               elsif ( $IsMelee && $IsRanged ) {
                  $log->warning(
                     qq{This natural attack is both Melee and Ranged}
                     . qq{"$lineTokens->{'NATURALATTACKS'}[0]"},
                     $file,
                     $line
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
      && exists $lineTokens->{'MOVE'} )
   {
      $log->warning( qq{Removed MOVE tags}, $file, $line );
      delete $lineTokens->{'MOVE'};
   }

   if (   isConversionActive('CLASS:no more HASSPELLFORMULA')
      && $filetype eq "CLASS"
      && exists $lineTokens->{'HASSPELLFORMULA'} )
   {
      $log->warning( qq{Removed deprecated HASSPELLFORMULA tags}, $file, $line );
      delete $lineTokens->{'HASSPELLFORMULA'};
   }


   ##################################################################
   # Every RACE that has a Climb or a Swim MOVE must have a
   # BONUS:SKILL|Climb|8|TYPE=Racial. If there is a
   # BONUS:SKILLRANK|Swim|8|PREDEFAULTMONSTER:Y present, it must be
   # removed or lowered by 8.

   if (   isConversionActive('RACE:BONUS SKILL Climb and Swim')
      && $filetype eq "RACE"
      && exists $lineTokens->{'MOVE'} )
   {
      my $swim  = $lineTokens->{'MOVE'}[0] =~ /swim/i;
      my $climb = $lineTokens->{'MOVE'}[0] =~ /climb/i;

      if ( $swim || $climb ) {
         my $need_swim  = 1;
         my $need_climb = 1;

         # Is there already a BONUS:SKILL|Swim of at least 8 rank?
         if ( exists $lineTokens->{'BONUS:SKILL'} ) {
            for my $skill ( @{ $lineTokens->{'BONUS:SKILL'} } ) {
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
                        $file,
                        $line
                     );
                  }

                  if ( $need_climb && $skill_rank == 8 ) {
                     $skill_list
                     = join( ',', sort( split ( ',', $skill_list ), 'Climb' ) );
                     $skill = "BONUS:SKILL|$skill_list|8|TYPE=Racial";
                     $log->warning(
                        qq{Added Climb to "$skill"},
                        $file,
                        $line
                     );
                  }

                  if ( ( $need_climb || $need_swim ) && $skill_rank != 8 ) {
                     $log->info(
                        qq{You\'ll have to deal with this one yourself "$skill"},
                        $file,
                        $line
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
         if ( exists $lineTokens->{'BONUS:SKILLRANK'} ) {
            for ( my $index = 0; $index < @{ $lineTokens->{'BONUS:SKILLRANK'} }; $index++ ) {
               my $skillrank = $lineTokens->{'BONUS:SKILLRANK'}[$index];

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
                              $file,
                              $line
                           );
                        }
                        else {
                           $log->warning(
                              qq{Removing "$skillrank"},
                              $file,
                              $line
                           );
                           delete $lineTokens->{'BONUS:SKILLRANK'}[$index];
                           $index--;
                        }
                     }
                     else {
                        $log->info(
                           qq{You\'ll have to deal with this one yourself "$skillrank"},
                           $file,
                           $line
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
                              $file,
                              $line
                           );
                        }
                        else {
                           $log->warning(
                              qq{Removing "$skillrank"},
                              $file,
                              $line
                           );
                           delete $lineTokens->{'BONUS:SKILLRANK'}[$index];
                           $index--;
                        }
                     }
                     else {
                        $log->info(
                           qq{You\'ll have to deal with this one yourself "$skillrank"},
                           $file,
                           $line
                        );
                     }
                  }
               }
            }

            # If there are no more BONUS:SKILLRANK, we remove the tag entry
            delete $lineTokens->{'BONUS:SKILLRANK'}
            unless @{ $lineTokens->{'BONUS:SKILLRANK'} };
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
      && exists $lineTokens->{'SIZE'} )
   {
      my $entityName = getEntityName('WEAPONPROF', $lineTokens);

      $log->warning(
         qq{Removing the SIZE tag in line "$entityName"},
         $file,
         $line
      );
      delete $lineTokens->{'SIZE'};
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
      if ( exists $lineTokens->{'AUTO:WEAPONPROF'} ) {
         $needNoProfReq = 0 if $lineTokens->{'AUTO:WEAPONPROF'}[0] =~ /NoProfReq/;
      }

      my $nbHands = 2;        # Default when no HANDS tag is present

      # How many hands?
      if ( exists $lineTokens->{'HANDS'} ) {
         if ( $lineTokens->{'HANDS'}[0] =~ /HANDS:(\d+)/ ) {
            $nbHands = $1;
         }
         else {
            $log->info(
               qq(Invalid value in tag "$lineTokens->{'HANDS'}[0]"),
               $file,
               $line
            );
            $needNoProfReq = 0;
         }
      }

      if ( $needNoProfReq && $nbHands ) {
         if ( exists $lineTokens->{'AUTO:WEAPONPROF'} ) {
            $log->warning(
               qq{Adding "TYPE=NoProfReq" to tag "$lineTokens->{'AUTO:WEAPONPROF'}[0]"},
               $file,
               $line
            );
            $lineTokens->{'AUTO:WEAPONPROF'}[0] .= "|TYPE=NoProfReq";
         }
         else {
            $lineTokens->{'AUTO:WEAPONPROF'} = ["AUTO:WEAPONPROF|TYPE=NoProfReq"];
            $log->warning(
               qq{Creating new tag "AUTO:WEAPONPROF|TYPE=NoProfReq"},
               $file,
               $line
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
      && exists $lineTokens->{'CSKILL'}
      && exists $lineTokens->{'MONSTERCLASS'}
      && !exists $lineTokens->{'MONCSKILL'} )
   {
      $log->warning(
         qq{Change CSKILL for MONSKILL in "$lineTokens->{'CSKILL'}[0]"},
         $file,
         $line
      );

      $lineTokens->{'MONCSKILL'} = [ "MON" . $lineTokens->{'CSKILL'}[0] ];
      delete $lineTokens->{'CSKILL'};
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
      && exists $lineTokens->{'VISION'}
      && $lineTokens->{'VISION'}[0] =~ /(\.ADD,|1,)(.*)/i )
   {
      $log->warning(
         qq{Removing "$lineTokens->{'VISION'}[0]"},
         $file,
         $line
      );

      my $newvision = "VISION:";
      my $coma;

      for my $vision_bonus ( split ',', $2 ) {
         if ( $vision_bonus =~ /(\w+)\s*\((\d+)\'\)/ ) {
            my ( $type, $bonus ) = ( $1, $2 );
            push @{ $lineTokens->{'BONUS:VISION'} }, "BONUS:VISION|$type|$bonus";
            $log->warning(
               qq{Adding "BONUS:VISION|$type|$bonus"},
               $file,
               $line
            );
            $newvision .= "$coma$type (0')";
            $coma = ',';
         }
         else {
            $log->error(
               qq(Do not know how to convert "VISION:.ADD,$vision_bonus"),
               $file,
               $line
            );
         }
      }

      $log->warning( qq{Adding "$newvision"}, $file, $line );

      $lineTokens->{'VISION'} = [$newvision];
   }

   ##################################################################
   #
   #
   # For items with TYPE:Boot, Glove, Bracer, we must check for plural
   # form and add a SLOTS:2 tag is the item is plural.

   if (   isConversionActive('EQUIPMENT: SLOTS:2 for plurals')
      && $filetype            eq 'EQUIPMENT'
      && $line_info->[0] eq 'EQUIPMENT'
      && !exists $lineTokens->{'SLOTS'} )
   {
      my $equipment_name = getEntityName('EQUIPMENT', $lineTokens);

      if ( exists $lineTokens->{'TYPE'} ) {
         my $type = $lineTokens->{'TYPE'}[0];
         if ( $type =~ /(Boot|Glove|Bracer)/ ) {
            if (   $1 eq 'Boot' && $equipment_name =~ /boots|sandals/i
               || $1 eq 'Glove'  && $equipment_name =~ /gloves|gauntlets|straps/i
               || $1 eq 'Bracer' && $equipment_name =~ /bracers|bracelets/i )
            {
               $lineTokens->{'SLOTS'} = ['SLOTS:2'];
               $log->warning(
                  qq{"SLOTS:2" added to "$equipment_name"},
                  $file,
                  $line
               );
            }
            else {
               $log->error( qq{"$equipment_name" is a $1}, $file, $line );
            }
         }
      }
      else {
         $log->warning(
            qq{$equipment_name has no TYPE.},
            $file,
            $line
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
         && ( exists $lineTokens->{'CLASSES'} ) )
      {
         my $spell_name  = $lineTokens->{'000SpellName'}[0];
         my $spell_level = -1;

         CLASS:
         for ( split '\|', $lineTokens->{'CLASSES'}[0] ) {
            if ( index( $_, 'Wizard' ) != -1 || index( $_, 'Cleric' ) != -1 ) {
               $spell_level = (/=(\d+)$/)[0];
               last CLASS;
            }
         }

         $spellsForEQMOD{$spell_name} = $spell_level
         if $spell_level > -1;

      }
      elsif ($filetype eq 'EQUIPMENT'
         && $line_info->[0] eq 'EQUIPMENT'
         && ( !exists $lineTokens->{'EQMOD'} ) )
      {
         my $equip_name = $lineTokens->{'000EquipmentName'}[0];
         my $spell_name;

         if ( $equip_name =~ m{^Wand \((.*)/(\d\d?)(st|rd|th) level caster\)} ) {
            $spell_name = $1;
            my $caster_level = $2;

            if ( exists $spellsForEQMOD{$spell_name} ) {
               my $spell_level = $spellsForEQMOD{$spell_name};
               my $eqmod_tag   = "EQMOD:SE_50TRIGGER|SPELLNAME[$spell_name]"
               . "SPELLLEVEL[$spell_level]"
               . "CASTERLEVEL[$caster_level]CHARGES[50]";
               $lineTokens->{'EQMOD'}    = [$eqmod_tag];
               $lineTokens->{'BASEITEM'} = ['BASEITEM:Wand']
               unless exists $lineTokens->{'BASEITEM'};
               delete $lineTokens->{'COST'} if exists $lineTokens->{'COST'};
               $log->warning(
                  qq{$equip_name: removing "COST" and adding "$eqmod_tag"},
                  $file,
                  $line
               );
            }
            else {
               $log->warning(
                  qq($equip_name: not enough information to add charges),
                  $file,
                  $line
               );
            }
         }
         elsif ( $equip_name =~ /^Wand \((.*)\)/ ) {
            $spell_name = $1;
            if ( exists $spellsForEQMOD{$spell_name} ) {
               my $spell_level  = $spellsForEQMOD{$spell_name};
               my $caster_level = $spell_level * 2 - 1;
               my $eqmod_tag   = "EQMOD:SE_50TRIGGER|SPELLNAME[$spell_name]"
               . "SPELLLEVEL[$spell_level]"
               . "CASTERLEVEL[$caster_level]CHARGES[50]";
               $lineTokens->{'EQMOD'} = [$eqmod_tag];
               delete $lineTokens->{'COST'} if exists $lineTokens->{'COST'};
               $log->warning(
                  qq{$equip_name: removing "COST" and adding "$eqmod_tag"},
                  $file,
                  $line
               );
            }
            else {
               $log->warning(
                  qq{$equip_name: not enough information to add charges},
                  $file,
                  $line
               );
            }
         }
         elsif ( $equip_name =~ /^Wand/ ) {
            $log->warning(
               qq{$equip_name: not enough information to add charges},
               $file,
               $line
            );
         }
      }
   }


   ##################################################################
   # [ 653596 ] Add a TYPE tag for all SPELLs
   # .

   if (   isConversionActive('SPELL:Add TYPE tags')
      && exists $lineTokens->{'SPELLTYPE'}
      && $filetype            eq 'CLASS'
      && $line_info->[0] eq 'CLASS'
   ) {

      # We must keep a list of all the SPELLTYPE for each class.
      # It is assumed that SPELLTYPE cannot be found more than once
      # for the same class. It is also assumed that SPELLTYPE has only
      # one value. SPELLTYPE:Any is ignored.

      my $className = getEntityName('CLASS', $lineTokens);
      SPELLTYPE_TAG:
      for my $spelltype_tag ( values %{ $lineTokens->{'SPELLTYPE'} } ) {
         my $spelltype = "";
         ($spelltype) = ($spelltype_tag =~ /SPELLTYPE:(.*)/);
         next SPELLTYPE_TAG if $spelltype eq "" or uc($spelltype) eq "ANY";
         $classSpellTypes{$className}{$spelltype}++;
      }
   }

   if (isConversionActive('SPELL:Add TYPE tags') && $filetype eq 'SPELL' && $line_info->{Linetype} eq 'SPELL' ) {

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
      && $sourceCurrentFile ne $file )
   {

      my $inputpath =  getOption('inputpath');
      # Only the first SOURCE tag is replaced.
      if ( dirHasSourceTags($file) ) {

         # We replace the line with a concatanation of SOURCE tags found in
         # the directory .PCC
         my %line_tokens;
         while ( my ( $tag, $value ) = each %{ getDirSourceTags($file) } )
         {
            $line_tokens{$tag} = [$value];
            $sourceCurrentFile = $file;
         }

         $line_info->[1] = \%line_tokens;

      } elsif ( $file =~ / \A ${inputpath} /xmsi ) {
         # We give this notice only if the curent file is under getOption('inputpath').
         # If -basepath is used, there could be files loaded outside of the -inputpath
         # without their PCC.
         $log->notice( "No PCC source information found", $file, $line );
      }
   }

   # Extract lists
   # ====================
   # Export each file name and log them with the filename and the
   # line number

   if ( isConversionActive('Export lists') ) {
      my $filename = $file;
      $filename =~ tr{/}{\\};

      if ( $filetype eq 'SPELL' ) {

         # Get the spell name
         my $spellname  = $lineTokens->{'000SpellName'}[0];
         my $sourcepage = "";
         $sourcepage = $lineTokens->{'SOURCEPAGE'}[0] if exists $lineTokens->{'SOURCEPAGE'};

         # Write to file
         LstTidy::Report::printToExportList('SPELL', qq{"$spellname","$sourcepage","$line","$filename"\n});
      }
      if ( $filetype eq 'CLASS' ) {
         my $class = ( $lineTokens->{'000ClassName'}[0] =~ /^CLASS:(.*)/ )[0];
         if ($className ne $class) {
            LstTidy::Report::printToExportList('CLASS', qq{"$class","$line","$filename"\n})
         };
         $className = $class;
      }

      if ( $filetype eq 'DEITY' ) {
         LstTidy::Report::printToExportList('DEITY', qq{"$lineTokens->{'000DeityName'}[0]","$line","$filename"\n});
      }

      if ( $filetype eq 'DOMAIN' ) {
         LstTidy::Report::printToExportList('DOMAIN', qq{"$lineTokens->{'000DomainName'}[0]","$line","$filename"\n});
      }

      if ( $filetype eq 'EQUIPMENT' ) {
         my $equipname  = getEntityName($filetype, $lineTokens);
         my $outputname = "";
         $outputname = substr( $lineTokens->{'OUTPUTNAME'}[0], 11 )
         if exists $lineTokens->{'OUTPUTNAME'};
         my $replacementname = $equipname;
         if ( $outputname && $equipname =~ /\((.*)\)/ ) {
            $replacementname = $1;
         }
         $outputname =~ s/\[NAME\]/$replacementname/;
         LstTidy::Report::printToExportList('EQUIPMENT', qq{"$equipname","$outputname","$line","$filename"\n});
      }

      if ( $filetype eq 'EQUIPMOD' ) {
         my $equipmodname = getEntityName($filetype, $lineTokens);
         my ( $key, $type ) = ( "", "" );
         $key  = substr( $lineTokens->{'KEY'}[0],  4 ) if exists $lineTokens->{'KEY'};
         $type = substr( $lineTokens->{'TYPE'}[0], 5 ) if exists $lineTokens->{'TYPE'};
         LstTidy::Report::printToExportList('EQUIPMOD', qq{"$equipmodname","$key","$type","$line","$filename"\n});
      }

      if ( $filetype eq 'FEAT' ) {
         my $featname = getEntityName($filetype, $lineTokens);
         LstTidy::Report::printToExportList('FEAT', qq{"$featname","$line","$filename"\n});
      }

      if ( $filetype eq 'KIT STARTPACK' ) {
         my ($kitname) = (getEntityName($filetype, $lineTokens) =~ /\A STARTPACK: (.*) \z/xms );
         LstTidy::Report::printToExportList('KIT', qq{"$kitname","$line","$filename"\n});
      }

      if ( $filetype eq 'KIT TABLE' ) {
         my ($tablename) = ( getEntityName($filetype, $lineTokens) =~ /\A TABLE: (.*) \z/xms );
         LstTidy::Report::printToExportList('TABLE', qq{"$tablename","$line","$filename"\n});
      }

      if ( $filetype eq 'LANGUAGE' ) {
         my $languagename = getEntityName($filetype, $lineTokens);
         LstTidy::Report::printToExportList('LANGUAGE', qq{"$languagename","$line","$filename"\n});
      }

      if ( $filetype eq 'RACE' ) {
         my $racename = getEntityName($filetype, $lineTokens);

         my $race_type = q{};
         $race_type = $lineTokens->{'RACETYPE'}[0] if exists $lineTokens->{'RACETYPE'};
         $race_type =~ s{ \A RACETYPE: }{}xms;

         my $race_sub_type = q{};
         $race_sub_type = $lineTokens->{'RACESUBTYPE'}[0] if exists $lineTokens->{'RACESUBTYPE'};
         $race_sub_type =~ s{ \A RACESUBTYPE: }{}xms;

         LstTidy::Report::printToExportList('RACE', qq{"$racename","$race_type","$race_sub_type","$line","$filename"\n});
      }

      if ( $filetype eq 'SKILL' ) {
         my $skillname = getEntityName($filetype, $lineTokens);
         LstTidy::Report::printToExportList('SKILL', qq{"$skillname","$line","$filename"\n});
      }

      if ( $filetype eq 'TEMPLATE' ) {
         my $template_name = getEntityName($filetype, $lineTokens);
         LstTidy::Report::printToExportList('TEMPLATE', qq{"$template_name","$line","$filename"\n});
      }
   }

   ############################################################
   ######################## Conversion ########################
   # We manipulate the tags for the line here

   if ( isConversionActive('Generate BONUS and PRExxx report') ) {
      for my $tag_type ( sort keys %$lineTokens ) {
         if ( $tag_type =~ /^BONUS|^!?PRE/ ) {
            addToBonusAndPreReport($lineTokens, $filetype, $tag_type);
         }
      }
   }

   1;
}


=head2 parseSystemFiles

   This operation searches the given gamemode directory and parses out
   Allowable game modes, Stats, alignments, variable names and check names. These
   are then used to populate the valid data for later parses of LST files.

=cut

sub parseSystemFiles {

   my ($systemFilePath) = @_;

   my $originalSystemFilePath = $systemFilePath;
   
   my $log = getLogger();

   my @verifiedAllowedModes = ();
   my @verifiedStats        = ();
   my @verifiedAlignments   = ();
   my @verifiedVarNames     = ();
   my @verifiedCheckNames   = ();

   # Set the header for the error messages
   $log->header(LstTidy::LogHeader::get('System'));

   # Get the Unix direcroty separator even in a Windows environment
   $systemFilePath =~ tr{\\}{/};

   # Verify if the gameModes directory is present
   if ( !-d "$systemFilePath/gameModes" ) {
      die qq{No gameModes directory found in "$originalSystemFilePath"};
   }

   # We will now find all of the miscinfo.lst and statsandchecks.lst files
   my @systemFiles = ();;

   my $getSystem = sub {
      push @systemFiles, $File::Find::name
      if lc $_ eq 'miscinfo.lst' || lc $_ eq 'statsandchecks.lst';
   };

   File::Find::find( $getSystem, $systemFilePath );

   # Did we find anything (hopefuly yes)
   if ( scalar @systemFiles == 0 ) {
      $log->error(
         qq{No miscinfo.lst or statsandchecks.lst file were found in the system directory},
         getOption('systempath')
      );
   }

   # We only keep the files that correspond to the selected
   # game mode
   if (getOption('gamemode')) {
      my $gamemode = getOption('gamemode') ;
      @systemFiles = grep { m{ \A $systemFilePath [/] gameModes [/] (?: ${gamemode} ) [/] }xmsi; } @systemFiles;
   }

   # Anything left?
   if ( scalar @systemFiles == 0 ) {
      my $gamemode = getOption('gamemode') ;
      $log->error(
         qq{No miscinfo.lst or statsandchecks.lst file were found in the gameModes/${gamemode}/ directory},
         getOption('systempath')
      );
   }

   # Now we search for the interesting part in the miscinfo.lst files
   for my $systemFile (@systemFiles) {
      open my $systemFileFh, '<', $systemFile;

      LINE:
      while ( my $line = <$systemFileFh> ) {
         chomp $line;

         # Skip comment lines
         next LINE if $line =~ / \A [#] /xms;

         # ex. ALLOWEDMODES:35e|DnD
         if ( my ($modes) = ( $line =~ / ALLOWEDMODES: ( [^\t]* )/xms ) ) {
            push @verifiedAllowedModes, split /[|]/, $modes;
            next LINE;

            # ex. STATNAME:Strength ABB:STR DEFINE:MAXLEVELSTAT=STR|STRSCORE-10
         } elsif ( $line =~ / \A STATNAME: /xms ) {

            LINE_TAG:
            for my $tag (split /\t+/, $line) {

               # STATNAME lines have more then one interesting tags
               if ( my ($stat) = ( $tag =~ / \A ABB: ( .* ) /xms ) ) {
                  push @verifiedStats, $stat;

               } elsif ( my ($defineExpression) = ( $tag =~ / \A DEFINE: ( .* ) /xms ) ) {

                  if ( my ($varName) = ( $defineExpression =~ / \A ( [\t=|]* ) /xms ) ) {
                     push @verifiedVarNames, $varName;
                  } else {
                     $log->error(
                        qq{Cannot find the variable name in "$defineExpression"},
                        $systemFile,
                        $INPUT_LINE_NUMBER
                     );
                  }
               }
            }

            # ex. ALIGNMENTNAME:Lawful Good ABB:LG
         } elsif ( my ($alignment) = ( $line =~ / \A ALIGNMENTNAME: .* ABB: ( [^\t]* ) /xms ) ) {
            push @verifiedAlignments, $alignment;

            # ex. CHECKNAME:Fortitude   BONUS:CHECKS|Fortitude|CON
         } elsif ( my ($checkName) = ( $line =~ / \A CHECKNAME: .* BONUS:CHECKS [|] ( [^\t|]* ) /xms ) ) {
            # The check name used by PCGen is actually the one defined with the first BONUS:CHECKS.
            # CHECKNAME:Sagesse     BONUS:CHECKS|Will|WIS would display Sagesse but use Will internaly.
            push @verifiedCheckNames, $checkName;
         }
      }

      close $systemFileFh;
   }

   # We keep only the first instance of every list items and replace
   # the default values with the result.
   # The order of elements must be preserved
   my %seen = ();

   setValidSystemArr('alignments', grep { !$seen{$_}++ } @verifiedAlignments);

   %seen = ();
   setValidSystemArr('checks' , grep { !$seen{$_}++ } @verifiedCheckNames);

   %seen = ();
   setValidSystemArr('gamemodes', grep { !$seen{$_}++ } @verifiedAllowedModes);

   %seen = ();
   setValidSystemArr('stats', grep { !$seen{$_}++ } @verifiedStats);

   %seen = ();
   setValidSystemArr('vars', grep { !$seen{$_}++ } @verifiedVarNames);

   # Now we bitch if we are not happy
   if ( scalar @verifiedStats == 0 ) {
      $log->error(
         q{Could not find any STATNAME: tag in the system files},
         $originalSystemFilePath
      );
   }

   if ( scalar @{getValidSystemArr('gamemodes')} == 0 ) {
      $log->error(
         q{Could not find any ALLOWEDMODES: tag in the system files},
         $originalSystemFilePath
      );
   }

   if ( scalar @{getValidSystemArr('checks')} == 0 ) {
      $log->error(
         q{Could not find any valid CHECKNAME: tag in the system files},
         $originalSystemFilePath
      );
   }

   # If the -exportlist option was used, we generate a system.csv file
   if ( getOption('exportlist') ) {

      open my $csvFile, '>', 'system.csv';

      print {$csvFile} qq{"System Directory","$originalSystemFilePath"\n};

      if ( getOption('gamemode') ) {
         my $gamemode = getOption('gamemode') ;
         print {$csvFile} qq{"Game Mode Selected","${gamemode}"\n};
      }
      print {$csvFile} qq{\n};

      print {$csvFile} qq{"Alignments"\n};
      for my $alignment (@{getValidSystemArr('alignments')}) {
         print {$csvFile} qq{"$alignment"\n};
      }
      print {$csvFile} qq{\n};

      print {$csvFile} qq{"Allowed Modes"\n};
      for my $mode (sort @{getValidSystemArr('gamemodes')}) {
         print {$csvFile} qq{"$mode"\n};
      }
      print {$csvFile} qq{\n};

      print {$csvFile} qq{"Stats Abbreviations"\n};
      for my $stat (@{getValidSystemArr('stats')}) {
         print {$csvFile} qq{"$stat"\n};
      }
      print {$csvFile} qq{\n};

      print {$csvFile} qq{"Variable Names"\n};
      for my $varName (sort @{getValidSystemArr('vars')}) {
         print {$csvFile} qq{"$varName"\n};
      }
      print {$csvFile} qq{\n};

      close $csvFile;
   }

   return;
}

=head2 extractTag

   This opeatrion takes a tag and makes sure it is suitable for further
   processing. It eliminates comments and dentifies pragma.

   Paramter: $tagText   The text of the tag
             $linetype  The Type of the current line
             $file      The name of the current file
             $line      The number of the current line

   Return: Tag and value, if value is defined the tag needs no further
           parsing.

=cut

sub extractTag {

   my ($tagText, $linetype, $file, $line) = @_;

   # We remove the enclosing quotes if any
   if ($tagText =~ s/^"(.*)"$/$1/) {
      getLogger()->warning( qq{Removing quotes around the '$tagText' tag}, $file, $line)
   }

   # Is this a pragma (e.g. #EXTRAFILE) rather than a comment
   if ( $tagText =~ m/^(\#.*?):(.*)/ && isValidTag($linetype, $1)) {
      return ( $1, $2 )
   }

   # If there is no text to parse or if this is a comment
   if (length $tagText == 0 || $tagText =~ /^\s*\#/) {
      return  ( "", "" )
   }

   # Remove any spaces before and after the tag
   $tagText =~ s/^\s+//;
   $tagText =~ s/\s+$//;
   
   return $tagText;
}

=head2 process000

   The first tag on a line may need to be processed because it is a MOD, FORGET
   or COPY. It may also need to be added to crosschecking data to allow other
   lines to do MOD, FORGETs or COPYs.

=cut

sub process000 {

   my ($line_info, $token, $linetype, $file, $line) = @_;

   # Are we dealing with a .MOD, .FORGET or .COPY type of tag?
   my $check_mod = $line_info->{RegExIsMod} || qr{ \A (.*) [.] (MOD|FORGET|COPY=[^\t]+) }xmsi;

   if ( my ($entity_name, $mod_part) = ($token =~ $check_mod) ) {

      # We keep track of the .MOD type tags to
      # later validate if they are valid
      if (getOption('xcheck')) {
         LstTidy::Report::registerReferrer($linetype, $entity_name, $token, $file, $line);
      }

      # Special case for .COPY=<new name>
      # <new name> is a valid entity
      if ( my ($new_name) = ( $mod_part =~ / \A COPY= (.*) /xmsi ) ) {
         setEntityValid($linetype, $new_name);
      }

      # Exit the loop
      return 1; #last COLUMN;

   } elsif ( getOption('xcheck') ) {

      # We keep track of the entities that could be used with a .MOD type of
      # tag for later validation.
      #
      # Some line types need special code to extract the entry.

      if ( $line_info->{RegExGetEntry} ) {

         if ( $token =~ $line_info->{RegExGetEntry} ) {
            $token = $1;

            # Some line types refer to other line entries directly
            # in the line identifier.
            if ( exists $line_info->{GetRefList} ) {
               LstTidy::Report::add_to_xcheck_tables(
                  $line_info->{IdentRefType},
                  $line_info->{IdentRefTag},
                  $file,
                  $line,
                  &{ $line_info->{GetRefList} }($token)
               );
            }

         } else {

            getLogger()->warning(
               qq(Cannot find the $linetype name),
               $file,
               $line
            );
         }
      }

      setEntityValid($linetype, $token);

      # Check to see if the token must be recorded for other
      # token types.
      if ( exists $line_info->{OtherValidEntries} ) {
         for my $entry_type ( @{ $line_info->{OtherValidEntries} } ) {
            setEntityValid($entry_type, $token);
         }
      }
   }

   # don't exit the loop
   return 0;
}



1;
