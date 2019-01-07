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
   parseSystemFiles
   process000
   processLine
   );

use Carp;


# expand library path so we can find LstTidy modules
use File::Basename qw(dirname);
use Cwd  qw(abs_path);
use lib dirname(dirname abs_path $0);

use LstTidy::Convert qw(
   convertAddTokens 
   doTokenConversions
   doLineConversions
   );
use LstTidy::Data qw(
   BLOCK BLOCK_HEADER COMMENT FIRST_COLUMN LINE LINE_HEADER MAIN
   NO NO_HEADER SINGLE SUB YES
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


=head2 extractTag

   This opeatrion takes a tag and makes sure it is suitable for further
   processing. It eliminates comments and identifies pragma.

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


=head2 processLine

   This function does additional processing on each line once
   it have been seperated into tokens.

   The processing is a mix of validation and conversion.

=cut


sub processLine {

   my ($lineTokens, $line) = @_;

   my $log = getLogger();
   
   doLineConversions($line);

   # Checking race files for TYPE and if no RACETYPE,
   # Do this check no matter what it is valid all the time
   if ( $line->isType('RACE')
      && ! $line->hasColumn('RACETYPE')
      && ! $line->hasColumn('TYPE')) {

      # .MOD / .FORGET / .COPY don't need RACETYPE or TYPE'
      if ($line->getEntityName() !~ /\.(FORGET|MOD|COPY=.+)$/) {
         $log->info(
            q{Race entry missing both TYPE and RACETYPE.},
            $line->file,
            $line->num
         );
      }
   };


   ##################################################################
   # Every RACE that has a Climb or a Swim MOVE must have a
   # BONUS:SKILL|Climb|8|TYPE=Racial. If there is a
   # BONUS:SKILLRANK|Swim|8|PREDEFAULTMONSTER:Y present, it must be
   # removed or lowered by 8.

   if (isConversionActive('RACE:BONUS SKILL Climb and Swim')
      && $line->isType("RACE")
      && $line->hasColumn('MOVE')) {

      my $swim  = $lineTokens->{'MOVE'}[0] =~ /swim/i;
      my $climb = $lineTokens->{'MOVE'}[0] =~ /climb/i;

      if ( $swim || $climb ) {
         my $need_swim  = 1;
         my $need_climb = 1;

         # Is there already a BONUS:SKILL|Swim of at least 8 rank?
         if ( $line->hasColumn('BONUS:SKILL') ) {
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
                        $line->file,
                        $line->num
                     );
                  }

                  if ( $need_climb && $skill_rank == 8 ) {
                     $skill_list
                     = join( ',', sort( split ( ',', $skill_list ), 'Climb' ) );
                     $skill = "BONUS:SKILL|$skill_list|8|TYPE=Racial";
                     $log->warning(
                        qq{Added Climb to "$skill"},
                        $line->file,
                        $line->num
                     );
                  }

                  if ( ( $need_climb || $need_swim ) && $skill_rank != 8 ) {
                     $log->info(
                        qq{You\'ll have to deal with this one yourself "$skill"},
                        $line->file,
                        $line->num
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
         if ( $line->hasColumn('BONUS:SKILLRANK') ) {
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
                              $line->file,
                              $line->num
                           );
                        }
                        else {
                           $log->warning(
                              qq{Removing "$skillrank"},
                              $line->file,
                              $line->num
                           );
                           delete $lineTokens->{'BONUS:SKILLRANK'}[$index];
                           $index--;
                        }
                     }
                     else {
                        $log->info(
                           qq{You\'ll have to deal with this one yourself "$skillrank"},
                           $line->file,
                           $line->num
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
                              $line->file,
                              $line->num
                           );
                        }
                        else {
                           $log->warning(
                              qq{Removing "$skillrank"},
                              $line->file,
                              $line->num
                           );
                           delete $lineTokens->{'BONUS:SKILLRANK'}[$index];
                           $index--;
                        }
                     }
                     else {
                        $log->info(
                           qq{You\'ll have to deal with this one yourself "$skillrank"},
                           $line->file,
                           $line->num
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
   # [ 832164 ] Adding NoProfReq to AUTO:WEAPONPROF for most races
   #
   # NoProfReq must be added to AUTO:WEAPONPROF if the race has
   # at least one hand and if NoProfReq is not already there.

   if (   isConversionActive('RACE:NoProfReq')
      && $line->isType("RACE") )
   {
      my $needNoProfReq = 1;

      # Is NoProfReq already present?
      if ( $line->hasColumn('AUTO:WEAPONPROF') ) {
         $needNoProfReq = 0 if $lineTokens->{'AUTO:WEAPONPROF'}[0] =~ /NoProfReq/;
      }

      my $nbHands = 2;        # Default when no HANDS tag is present

      # How many hands?
      if ( $line->hasColumn('HANDS') ) {
         if ( $lineTokens->{'HANDS'}[0] =~ /HANDS:(\d+)/ ) {
            $nbHands = $1;
         }
         else {
            $log->info(
               qq(Invalid value in tag "$lineTokens->{'HANDS'}[0]"),
               $line->file,
               $line->num
            );
            $needNoProfReq = 0;
         }
      }

      if ( $needNoProfReq && $nbHands ) {
         if ( $line->hasColumn('AUTO:WEAPONPROF') ) {
            $log->warning(
               qq{Adding "TYPE=NoProfReq" to tag "$lineTokens->{'AUTO:WEAPONPROF'}[0]"},
               $line->file,
               $line->num
            );
            $lineTokens->{'AUTO:WEAPONPROF'}[0] .= "|TYPE=NoProfReq";
         }
         else {
            $lineTokens->{'AUTO:WEAPONPROF'} = ["AUTO:WEAPONPROF|TYPE=NoProfReq"];
            $log->warning(
               qq{Creating new tag "AUTO:WEAPONPROF|TYPE=NoProfReq"},
               $line->file,
               $line->num
            );
         }
      }
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
      && $line->hasColumn('VISION')
      && $lineTokens->{'VISION'}[0] =~ /(\.ADD,|1,)(.*)/i )
   {
      $log->warning(
         qq{Removing "$lineTokens->{'VISION'}[0]"},
         $line->file,
         $line->num
      );

      my $newvision = "VISION:";
      my $coma;

      for my $vision_bonus ( split ',', $2 ) {
         if ( $vision_bonus =~ /(\w+)\s*\((\d+)\'\)/ ) {
            my ( $type, $bonus ) = ( $1, $2 );
            push @{ $lineTokens->{'BONUS:VISION'} }, "BONUS:VISION|$type|$bonus";
            $log->warning(
               qq{Adding "BONUS:VISION|$type|$bonus"},
               $line->file,
               $line->num
            );
            $newvision .= "$coma$type (0')";
            $coma = ',';
         }
         else {
            $log->error(
               qq(Do not know how to convert "VISION:.ADD,$vision_bonus"),
               $line->file,
               $line->num
            );
         }
      }

      $log->warning( qq{Adding "$newvision"}, $line->file, $line->num );

      $lineTokens->{'VISION'} = [$newvision];
   }

   ##################################################################
   #
   #
   # For items with TYPE:Boot, Glove, Bracer, we must check for plural
   # form and add a SLOTS:2 tag is the item is plural.

   if (   isConversionActive('EQUIPMENT: SLOTS:2 for plurals')
      && $line->isType('EQUIPMENT')
      && !$line->hasColumn('SLOTS') )
   {
      my $equipment_name = getEntityName('EQUIPMENT', $lineTokens);

      if ( $line->hasColumn('TYPE') ) {
         my $type = $lineTokens->{'TYPE'}[0];
         if ( $type =~ /(Boot|Glove|Bracer)/ ) {
            if (   $1 eq 'Boot' && $equipment_name =~ /boots|sandals/i
               || $1 eq 'Glove'  && $equipment_name =~ /gloves|gauntlets|straps/i
               || $1 eq 'Bracer' && $equipment_name =~ /bracers|bracelets/i )
            {
               $lineTokens->{'SLOTS'} = ['SLOTS:2'];
               $log->warning(
                  qq{"SLOTS:2" added to "$equipment_name"},
                  $line->file,
                  $line->num
               );
            }
            else {
               $log->error( qq{"$equipment_name" is a $1}, $line->file, $line->num );
            }
         }
      }
      else {
         $log->warning(
            qq{$equipment_name has no TYPE.},
            $line->file,
            $line->num
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
      if (   $line->isType('SPELL')
         && ( $line->hasColumn('CLASSES') ) )
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
      elsif ($line->isType('EQUIPMENT')
         && ( !$line->hasColumn('EQMOD') ) )
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
               unless $line->hasColumn('BASEITEM');
               delete $lineTokens->{'COST'} if $line->hasColumn('COST');
               $log->warning(
                  qq{$equip_name: removing "COST" and adding "$eqmod_tag"},
                  $line->file,
                  $line->num
               );
            }
            else {
               $log->warning(
                  qq($equip_name: not enough information to add charges),
                  $line->file,
                  $line->num
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
               delete $lineTokens->{'COST'} if $line->hasColumn('COST');
               $log->warning(
                  qq{$equip_name: removing "COST" and adding "$eqmod_tag"},
                  $line->file,
                  $line->num
               );
            }
            else {
               $log->warning(
                  qq{$equip_name: not enough information to add charges},
                  $line->file,
                  $line->num
               );
            }
         }
         elsif ( $equip_name =~ /^Wand/ ) {
            $log->warning(
               qq{$equip_name: not enough information to add charges},
               $line->file,
               $line->num
            );
         }
      }
   }


   ##################################################################
   # [ 653596 ] Add a TYPE tag for all SPELLs
   # .

   if (   isConversionActive('SPELL:Add TYPE tags')
      && $line->hasColumn('SPELLTYPE')
      && $line->istype('CLASS')
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

   if (isConversionActive('SPELL:Add TYPE tags') 
      && $line->isType('SPELL') 
   ) {

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

   if (isConversionActive('SOURCE line replacement')
      && $line->isType('SOURCE') 
      && $sourceCurrentFile ne $line->file )
   {

      my $inputpath =  getOption('inputpath');
      # Only the first SOURCE tag is replaced.
      if ( dirHasSourceTags($line->file) ) {

         # We replace the line with a concatanation of SOURCE tags found in
         # the directory .PCC
         my %line_tokens;
         while ( my ( $tag, $value ) = each %{ getDirSourceTags($line->file) } )
         {
            $line_tokens{$tag} = [$value];
            $sourceCurrentFile = $line->file;
         }

      } elsif ( $line->file =~ / \A ${inputpath} /xmsi ) {
         # We give this notice only if the curent file is under getOption('inputpath').
         # If -basepath is used, there could be files loaded outside of the -inputpath
         # without their PCC.
         $log->notice( "No PCC source information found", $line->file, $line->num );
      }
   }

   # Extract lists
   # ====================
   # Export each file name and log them with the filename and the
   # line number

   if ( isConversionActive('Export lists') ) {
      my $filename = $line->file;
      $filename =~ tr{/}{\\};

      if ( $line->isType('SPELL') ) {

         # Get the spell name
         my $spellname  = $lineTokens->{'000SpellName'}[0];
         my $sourcepage = "";
         $sourcepage = $lineTokens->{'SOURCEPAGE'}[0] if $line->hasColumn('SOURCEPAGE');





         # Write to file
         LstTidy::Report::printToExportList('SPELL', 
            makeExportListString($spellname, $sourcepage, $line->num, $filename));
      }
      if ( $line->isType('CLASS') ) {
         my $class = ( $lineTokens->{'000ClassName'}[0] =~ /^CLASS:(.*)/ )[0];
         if ($className ne $class) {
            LstTidy::Report::printToExportList('CLASS', 
               makeExportListString($class, $line->num, $filename));
         };
         $className = $class;
      }

      if ( $line->isType('DEITY') ) {
         LstTidy::Report::printToExportList('DEITY', 
            makeExportListString($lineTokens->{'000DeityName'}[0], $line->num, $filename));
      }

      if ( $line->isType('DOMAIN') ) {
         LstTidy::Report::printToExportList('DOMAIN', 
            makeExportListString($lineTokens->{'000DomainName'}[0], $line->num, $filename));
      }

      if ( $line->isType('EQUIPMENT') ) {
         my $equipname  = getEntityName($line->type, $lineTokens);
         my $outputname = "";
         $outputname = substr( $lineTokens->{'OUTPUTNAME'}[0], 11 )
         if $line->hasColumn('OUTPUTNAME');
         my $replacementname = $equipname;
         if ( $outputname && $equipname =~ /\((.*)\)/ ) {
            $replacementname = $1;
         }
         $outputname =~ s/\[NAME\]/$replacementname/;
         LstTidy::Report::printToExportList('EQUIPMENT', 
            makeExportListString($equipname, $outputname, $line->num, $filename));
      }

      if ( $line->isType('EQUIPMOD') ) {
         my $equipmodname = getEntityName($line->type, $lineTokens);
         my ( $key, $type ) = ( "", "" );
         $key  = substr( $lineTokens->{'KEY'}[0],  4 ) if $line->hasColumn('KEY');
         $type = substr( $lineTokens->{'TYPE'}[0], 5 ) if $line->hasColumn('TYPE');
         LstTidy::Report::printToExportList('EQUIPMOD', 
            makeExportListString($equipmodname, $key, $type, $line->num, $filename));
      }

      if ( $line->isType('FEAT') ) {
         my $featname = getEntityName($line->type, $lineTokens);
         LstTidy::Report::printToExportList('FEAT', 
            makeExportListString($featname, $line->num, $filename));
      }

      if ( $line->isType('KIT STARTPACK') ) {
         my ($kitname) = (getEntityName($line->type, $lineTokens) =~ /\A STARTPACK: (.*) \z/xms );
         LstTidy::Report::printToExportList('KIT', 
            makeExportListString($kitname, $line->num, $filename));
      }

      if ( $line->isType('KIT TABLE') ) {
         my ($tablename) = ( getEntityName($line->type, $lineTokens) =~ /\A TABLE: (.*) \z/xms );
         LstTidy::Report::printToExportList('TABLE', 
            makeExportListString($tablename, $line->num, $filename));
      }

      if ( $line->isType('LANGUAGE') ) {
         my $languagename = getEntityName($line->type, $lineTokens);
         LstTidy::Report::printToExportList('LANGUAGE', 
            makeExportListString($languagename, $line->num, $filename));
      }

      if ( $line->isType('RACE') ) {
         my $racename = getEntityName($line->type, $lineTokens);

         my $race_type = q{};
         $race_type = $lineTokens->{'RACETYPE'}[0] if $line->hasColumn('RACETYPE');
         $race_type =~ s{ \A RACETYPE: }{}xms;

         my $race_sub_type = q{};
         $race_sub_type = $lineTokens->{'RACESUBTYPE'}[0] if $line->hasColumn('RACESUBTYPE');
         $race_sub_type =~ s{ \A RACESUBTYPE: }{}xms;

         LstTidy::Report::printToExportList('RACE', 
            makeExportListString($racename, $race_type, $race_sub_type, $line->num, $filename));
      }

      if ( $line->isType('SKILL') ) {
         my $skillname = getEntityName($line->type, $lineTokens);
         LstTidy::Report::printToExportList('SKILL', 
            makeExportListString($skillname, $line->num, $filename));
      }

      if ( $line->isType('TEMPLATE') ) {
         my $template_name = getEntityName($line->type, $lineTokens);
         LstTidy::Report::printToExportList('TEMPLATE', 
            makeExportListString($template_name, $line->num, $filename));
      }
   }

   ############################################################
   ######################## Conversion ########################
   # We manipulate the tags for the line here

   if ( isConversionActive('Generate BONUS and PRExxx report') ) {
      for my $tag_type ( sort keys %$lineTokens ) {
         if ( $tag_type =~ /^BONUS|^!?PRE/ ) {
            addToBonusAndPreReport($lineTokens, $line->type, $tag_type);
         }
      }
   }

   1;
}



1;
