package TidyLst::Parse;

use strict;
use warnings;
use English;

require Exporter;

our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
   extractTag
   isParseableFileType
   isWriteableFileType
   normaliseFile
   parseSystemFiles
   );

use Carp;
use YAML;

# expand library path so we can find TidyLst modules
use File::Basename qw(dirname);
use Cwd  qw(abs_path);
use lib dirname(dirname abs_path $0);

use TidyLst::Convert qw(
   convertAddTokens
   convertEntities
   doFileConversions
   doLineConversions
   doTokenConversions
   );

use TidyLst::Data qw(
   BLOCK BLOCK_HEADER COMMENT FIRST_COLUMN LINE LINE_HEADER MAIN
   NO NO_HEADER SINGLE SUB YES
   dirHasSourceTags
   getDirSourceTags
   getEntityFirstTag
   getEntityName
   getEntityNameTag
   getHeader
   getValidSystemArr
   incCountValidTags
   isValidMultiTag
   isValidTag
   registerXCheck
   setEntityValid
   setValidSystemArr
   );

use TidyLst::Line;
use TidyLst::LogFactory qw(getLogger);
use TidyLst::Options qw(getOption isConversionActive);
use TidyLst::Reformat qw(reformatFile);
use TidyLst::Token;
use TidyLst::Validate qw(scanForDeprecatedTokens validateLine);
use TidyLst::Variable;

my $className = "";


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
   DATATABLE       => \&parseFile,
   DYNAMIC         => \&parseFile,
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
   SIZE            => \&parseFile,
   SKILL           => \&parseFile,
   SPELL           => \&parseFile,
   STAT            => \&parseFile,
   TEMPLATE        => \&parseFile,
   VARIABLE        => \&parseFile,
   WEAPONPROF      => \&parseFile,
);



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
   'CLASS'           => 1,
   'COMPANIONMOD'    => 1,
   'DATACONTROL'     => 1,
   'DATATABLE'       => 1,
   'DYNAMIC'         => 1,
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


=head2 checkClearTokenOrder

   Verify that the .CLEAR tags are correctly put before the
   tags that they clear.

   Parameter: $line

=cut

sub checkClearTokenOrder {

   my ($line) = @_;

   TAG:
   for my $column ($line->columns) {

      # if only one of a kind, skip the rest
      next TAG if $line->columnHasSingleToken($column);
      $line->checkClear($column);
   }
}


=head2 extractTag

   This opeatrion takes a tag and makes sure it is suitable for further
   processing. It eliminates comments and identifies pragma.

   Paramter: $tagText   The text of the tag
             $linetype  The Type of the current line
             $file      The name of the current file
             $line      The number of 
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

=head2 getParseControl

   Get the Parse control record where the lineType field of the record matches
   the key used to look it up. This ensures we get an appropriate record for the line
   type as files can contain multiple line types.

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


=head2 makeExportListString

   Join the arguments into a string suitable for passing to export lists.

=cut

sub makeExportListString {

   my $guts = join qq{","}, @_;
   qq{"${guts}\n"};
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



=head2 parseFile

   This function uses the information of TidyLst::Parse::parseControl to
   parse the curent line type and parse it.

   Parameters: $fileType  The type of the file has defined by the .PCC file
               $lines_ref Reference to an array containing all the lines of
                          the file
               $file      File name to use with the logger

=cut

sub parseFile {
   my ($fileType, $lines_ref, $file) = @_;

   my $log = getLogger();

   ##################################################
   # Working variables

   my $curent_linetype = "";
   my $lastMainLine    = -1;

   my $curent_entity;

   my @newLines;   # New line generated

   ##################################################
   ##################################################
   # Phase I - Split line in tokens and parse
   #               the tokens

   my $lineNum = 1;
   LINE:
   for my $thisLine (@ {$lines_ref} ) {

      my $line_info;

      # Convert the non-ascii character in the line
      my $newLine = convertEntities($thisLine);

      # Remove spaces at the end of the line
      $newLine =~ s/\s+$//;

      # Remove spaces at the begining of the line
      $newLine =~ s/^\s+//;

      my $line = TidyLst::Line->new(
         type     => $curent_linetype,
         file     => $file,
         unsplit  => $newLine,
         num      => $lineNum,
         mode     => COMMENT,
         header   => NO_HEADER, # No header
         format   => LINE,
      );

      # Skip comments and empty lines
      if (length($newLine) == 0 || $newLine =~ /^\#/) {

         # We push the line as is.
         push @newLines, $line;
         next LINE;
      }

      ($line_info, $curent_entity) = matchLineType($newLine, $fileType);

      # If we didn't find a record with info how to parse this line
      if ( ! defined $line_info ) {
         $log->warning(
            qq(Can\'t find the line type for "$newLine"),
            $file,
            $lineNum
         );

         # We push the line as is.
         push @newLines, $line;
         next LINE;
      }

      $line->mode($line_info->{Mode});
      $line->format($line_info->{Format});
      $line->header($line_info->{Header});

      # What type of line is it?
      $curent_linetype = $line_info->{Linetype};

      if ( $line_info->{Mode} == MAIN ) {

         $lastMainLine = $lineNum - 1;

      } elsif ( $line_info->{Mode} == SUB ) {

         if ($lastMainLine == -1) {
            $log->warning(
               qq{SUB line "$curent_linetype" is not preceded by a MAIN line},
               $file,
               $lineNum
            )
         }

      } elsif ( $line_info->{Mode} == SINGLE ) {

         $lastMainLine = -1;

      } else {

         die qq(Invalid type for $curent_linetype);
      }

      # Got a line info hash, so update the line type in the line
      $line->type($line_info->{Linetype});

      # Identify the deprecated tags.
      scanForDeprecatedTokens( $newLine, $curent_linetype, $file, $lineNum, $line, );

      # By default, the tab character is used
      my $sep = $line_info->{SepRegEx} || qr(\t+);

      # We split the tokens, strip the spaces and silently remove the empty tags
      # (empty tokens are the result of [tab][space][tab] type of chracter
      # sequences).
      # [ 975999 ] [tab][space][tab] breaks prettylst
      my @tokens =
         grep { $_ ne q{} }
         map { s{ \A \s* | \s* \z }{}xmsg; $_ }
         split $sep, $newLine;

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
         my $value = shift @tokens;

         # We remove the enclosing quotes if any
         if ($value =~ s/^"(.*)"$/$1/) {
            $log->warning(
               qq{Removing quotes around the '$value' tag},
               $file,
               $lineNum
            )
         }

         my $token =  TidyLst::Token->new(
            tag       => $column,
            value     => $value,
            lineType  => $curent_linetype,
            file      => $file,
            line      => $lineNum,
         );

         $line->add($token);

         # Statistic gathering
         incCountValidTags($curent_linetype, $column);

         if ( index( $column, '000' ) == 0 && $line_info->{ValidateKeep} ) {
            my $exit = process000($line_info, $value, $curent_linetype, $file, $lineNum);
            last COLUMN if $exit;
         }
      }

      # Second, let's parse the regular columns
      for my $rawToken (@tokens) {

         my ($extractedToken, $value) =
            extractTag($rawToken, $curent_linetype, $file, $lineNum);

         # if extractTag returns a defined value, no further processing is
         # neeeded. If tag is defined but value is not, then the tag that was
         # returned is the cleaned token and should be processed further.
         if ($extractedToken && not defined $value) {

            my $token =  TidyLst::Token->new(
               fullToken => $extractedToken,
               lineType  => $curent_linetype,
               file      => $file,
               line      => $lineNum,
            );

            # Potentally modify the tag
            $token->process();

            my $tag = $token->tag;

            if ($line->hasColumn($tag) && ! isValidMultiTag($curent_linetype, $tag)) {
               $log->notice(
                  qq{The tag "$tag" should not be used more than once on the same }
                  . $curent_linetype . qq{ line.\n},
                  $file,
                  $lineNum
               );
            }
            $line->add($token);

         } else {
            $log->warning( "No tags in \"$rawToken\"\n", $file, $lineNum );
         }
      }

      # We manipulate the tags for the line here
      # This function call will parse individual lines, which will
      # in turn parse the tags within the lines.

      processLine($line);

      # Validate the line
      if (getOption('xcheck')) {
         validateLine($line)
      };

      # .CLEAR order verification
      checkClearTokenOrder($line);

      # Populate the lines array
      push @newLines, $line;

   }
   continue { $lineNum++ }

   #####################################################
   #####################################################
   # We find all the header lines

   CATEGORIZE_COMMENTS:
   for (my $i = 0; $i < @newLines; $i++) {

      my $line = $newLines[$i];

      # A header line either begins with the curent line_type header
      # or the next line header.
      #
      # Only comment lines (unsplit lines with no tokens) can be header lines
      if ($line->noTokens) {

         if (index(lc($line->unsplit), '###block') == 0) {
            $line->type('BLOCK_COMMENT');
            next CATEGORIZE_COMMENTS;
         }

         if ($line->unsplit eq '') {
            $line->type('BLANK');
            next CATEGORIZE_COMMENTS;
         }

         my $header = getHeader(getEntityFirstTag($line->type), $line->type);

         my $isHeader = $header && index($line->unsplit, $header) == 0;

         # If this line is not a header line for its own line type, try the
         # next different line type, is it a header for it?
         if (! $isHeader) {

            FIND_LINETYPE:
            for my $j ($i + 1 .. $#newLines) {
               my $next = $newLines[$j];

               # find the first non-blank line type that doesn't match the current
               # line's type
               if (! $next->type || $next->type eq $line->type) {
                  next FIND_LINETYPE;
               }

               my $header = getHeader(getEntityFirstTag($next->type), $next->type);
               $isHeader = $header && index($line->unsplit, $header) == 0;
               last FIND_LINETYPE;
            }
         }

         # If this line starts with the header for its line type, or if it
         # starts with a header for the line type of the next line with a
         # different line type.
         
         if ($isHeader) {

            # It is a header, let's tag it as such.
            $line->type('HEADER');

         } else {

            # This is either a comment or a line we couldn't find a parse record for. 
            # Either way we aren't going to be able to process it further, mark it to
            # be included verbatim in the new file.
            $line->type('COMMENT');
         }
      }
   }

   #################################################################
   ######################## Conversion #############################
   # We manipulate the tags for the whole file here

   doFileConversions(\@newLines, $fileType, $file);

   ##################################################
   ##################################################
   # Phase II - Reformating the lines
   
   print STDERR Dump @newLines;

   # No reformating needed?
   return $lines_ref unless getOption('outputpath') && isWriteableFileType($fileType);

   reformatFile($fileType, \@newLines);
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
   $log->header(TidyLst::LogHeader::get('System'));

   # Get the Unix directory separator even in a Windows environment
   $systemFilePath =~ tr{\\}{/};

   # Verify if the gameModes directory is present
   if ( !-d "$systemFilePath/gameModes" ) {
      die qq{No gameModes directory found in "$originalSystemFilePath"};
   }

   # We will now find all of the miscinfo.lst and statsandchecks.lst files
   my @systemFiles = ();;

   my $getSystem = sub {
      no warnings qw(once);
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
         TidyLst::Report::registerReferrer($linetype, $entity_name, $token, $file, $line);
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
               TidyLst::Report::add_to_xcheck_tables(
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


=head2 processLine

   This function does additional processing on each line once
   it have been seperated into tokens.

   The processing is a mix of validation and conversion.

=cut


sub processLine {

   my ($line) = @_;

   my $log = getLogger();

   ############################################################
   ######################## Conversion ########################
   # We manipulate the tags for the line here

   doLineConversions($line);

   # Checking race files for TYPE and if no RACETYPE,
   # Do this check no matter what it is valid all the time
   if ( $line->isType('RACE')
      && ! $line->hasColumn('RACETYPE')
      && ! $line->hasColumn('TYPE')) {

      # .MOD / .FORGET / .COPY don't need RACETYPE or TYPE'
      if ($line->entityName() !~ /\.(FORGET|MOD|COPY=.+)$/) {
         $log->info(
            q{Race entry missing both TYPE and RACETYPE.},
            $line->file,
            $line->num
         );
      }
   };

   # Extract lists
   # ====================
   # Export each file name and log them with the filename and the
   # line number

   if (getOption('exportlist')) {

      my $filename = $line->file;
      $filename =~ tr{/}{\\} if ($^O eq "MSWin32");

      my $name = $line->entityName;

      if ( $line->isType('SPELL') ) {

         # Get the spell name and source page
         my $sourcepage = "";

         if ($line->hasColumn('SOURCEPAGE')) {
            $sourcepage = $line->valueInFirstTokenInColumn('SOURCEPAGE');
         }

         # Write to file
         TidyLst::Report::printToExportList('SPELL',
            makeExportListString($name, $sourcepage, $line->num, $filename));
      }

      if ( $line->isType('CLASS') ) {

         # Only one report per class
         if ($className ne $name) {
            TidyLst::Report::printToExportList('CLASS',
               makeExportListString($className, $line->num, $filename));
         };
         $className = $name;
      }

      if ( $line->isType('DEITY') ) {
         TidyLst::Report::printToExportList('DEITY',
            makeExportListString($name, $line->num, $filename));
      }

      if ( $line->isType('DOMAIN') ) {
         TidyLst::Report::printToExportList('DOMAIN',
            makeExportListString($name, $line->num, $filename));
      }

      if ( $line->isType('EQUIPMENT') ) {

         my $outputname = "";

         if ($line->hasColumn('OUTPUTNAME')) {
            $outputname = $line->valueInFirstTokenInColumn('OUTPUTNAME');

            if ($outputname =~ /\[NAME\]/) {
               my $rep = ($name =~ /\((.*)\)/) ? $1 : $name;
               $outputname =~ s/\[NAME\]/$rep/;
            }
         }

         TidyLst::Report::printToExportList('EQUIPMENT',
            makeExportListString($name, $outputname, $line->num, $filename));
      }

      if ( $line->isType('EQUIPMOD') ) {

         my $key  = $line->hasColumn('KEY')  ? $line->valueInFirstTokenInColumn('KEY') : '';
         my $type = $line->hasColumn('TYPE') ? $line->valueInFirstTokenInColumn('TYPE') : '';

         TidyLst::Report::printToExportList('EQUIPMOD',
            makeExportListString($name, $key, $type, $line->num, $filename));
      }

      if ( $line->isType('FEAT') ) {
         TidyLst::Report::printToExportList('FEAT',
            makeExportListString($name, $line->num, $filename));
      }

      if ( $line->isType('KIT STARTPACK') ) {
         TidyLst::Report::printToExportList('KIT',
            makeExportListString($name, $line->num, $filename));
      }

      if ( $line->isType('KIT TABLE') ) {
         TidyLst::Report::printToExportList('TABLE',
            makeExportListString($name, $line->num, $filename));
      }

      if ( $line->isType('LANGUAGE') ) {
         TidyLst::Report::printToExportList('LANGUAGE',
            makeExportListString($name, $line->num, $filename));
      }

      if ( $line->isType('RACE') ) {

         my $type    = $line->valueInFirstTokenInColumn('RACETYPE');
         my $subType = $line->valueInFirstTokenInColumn('RACESUBTYPE');

         TidyLst::Report::printToExportList('RACE',
            makeExportListString($name, $type, $subType, $line->num, $filename));
      }

      if ( $line->isType('SKILL') ) {

         TidyLst::Report::printToExportList('SKILL',
            makeExportListString($name, $line->num, $filename));
      }

      if ( $line->isType('TEMPLATE') ) {

         TidyLst::Report::printToExportList('TEMPLATE',
            makeExportListString($name, $line->num, $filename));
      }
   }

   if (getOption('bonusreport')) {
      $line->addToBonusAndPreReport
   }
}

1;
