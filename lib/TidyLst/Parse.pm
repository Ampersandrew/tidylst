package TidyLst::Parse;

use strict;
use warnings;

use Fatal qw( open close );             # Force some built-ins to die on error
use English qw( -no_match_vars );       # No more funky punctuation variables

require Exporter;

our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
   create_dir
   extractTag
   isParseableFileType
   isWriteableFileType
   normaliseFile
   parseSystemFiles
   processFile
   );

use Carp;

# expand library path so we can find TidyLst modules
use File::Basename qw(dirname fileparse);
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
   getTaglessColumn
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
use TidyLst::Report qw(
   makeExportListString
   printToExportList 
   registerReferrer
   );
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
      },
      \%SourceLineDef,
      {  Linetype          => 'SUBCLASS',
         RegEx             => qr(^SUBCLASS:([^\t]*)),
         Mode              => SUB,
         Format            => BLOCK,
         Header            => NO_HEADER,
         ValidateKeep      => YES,
         # SUBCLASS can be refered to anywhere CLASS works.
         OtherValidEntries => ['CLASS'],
      },
      {  Linetype          => 'SUBSTITUTIONCLASS',
         RegEx             => qr(^SUBSTITUTIONCLASS:([^\t]*)),
         Mode              => SUB,
         Format            => BLOCK,
         Header            => NO_HEADER,
         ValidateKeep      => YES,
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
      { Linetype        => 'FOLLOWER',
         RegEx          => qr(^FOLLOWER:([^\t]*)),
         Mode           => MAIN,
         Format         => BLOCK,
         Header         => BLOCK_HEADER,
         ValidateKeep   => YES,
         RegExIsMod     => qr(FOLLOWER:(.*)\.(MOD|FORGET|COPY=[^\t]+)),
         RegExGetEntry  => qr(FOLLOWER:(.*?)=),

         # Identifier that refer to other entry type
         IdentRefType   => 'CLASS,DEFINE Variable',
      },
      { Linetype        => 'MASTERBONUSRACE',
         RegEx          => qr(^MASTERBONUSRACE:([^\t]*)),
         Mode           => MAIN,
         Format         => BLOCK,
         Header         => BLOCK_HEADER,
         ValidateKeep   => YES,
         RegExIsMod     => qr(MASTERBONUSRACE:(.*)\.(MOD|FORGET|COPY=[^\t]+)),
         RegExGetEntry  => qr(MASTERBONUSRACE:(.*)),
         
         # Identifier that refers to other entry type
         IdentRefType   => 'RACE',                 
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
      {  Linetype       => 'SIZE',
         RegEx          => qr(^([^\t:]+)),
         Mode           => MAIN,
         Format         => BLOCK,
         Header         => BLOCK_HEADER,
         ValidateKeep   => YES,
      },
   ],

);

my %tagsWithValidityData = (
   'DEFINE'      => 1,
   'MOVE'        => 1,
   'RACESUBTYPE' => 1,
   'RACETYPE'    => 1,
   'STARTPACK'   => 1,
);


=head2 addNameToValidEntities

   The first tag on a line may need to be processed because it is a MOD, FORGET
   or COPY. It may also need to be added to crosschecking data to allow other
   lines to do MOD, FORGETs or COPYs.

=cut

sub addNameToValidEntities {

   my ($line, $lineInfo) = @_;

   # Only add the name valitdity info if the line info calls for it.
   if (! $lineInfo->{ValidateKeep} ) {
      return;
   }

   # Get the token that holds the name of this entity
   my $column = getEntityFirstTag($lineInfo->{Linetype});

   return unless defined $column;

   my $token = $line->firstTokenInColumn($column);

   return unless defined $token;

   my ($entityName, $modPart);

   if (defined $lineInfo->{RegExIsMod}) {
      ($entityName, $modPart) = ($token->fullRealToken =~ $lineInfo->{RegExIsMod});
   } else {
      ($entityName, $modPart) = ($token->value =~ qr{ \A (.*) [.] (MOD|FORGET|COPY=[^\t]+) }xmsi);
   }
   
   if (defined $modPart) {

      # getLogger->report("In the valid entries, adding: " . $token->value); 

      # We keep track of the .MOD type tags to
      # later validate if they are valid
      if (getOption('xcheck')) {
         registerReferrer(
            $lineInfo->{Linetype}, 
            $entityName, 
            $token->fullRealToken, 
            $token->file, 
            $token->line);
      }

      my ($newName) = ($modPart =~ / \A COPY= (.*) /xmsi);

      # Special case for .COPY=<new name>
      # <new name> is a valid entity
      if (defined $newName) {
         setEntityValid($lineInfo->{Linetype}, $newName);
      }

   } elsif ( getOption('xcheck') ) {

      # We keep track of the entities that could be used with a .MOD type of
      # tag for later validation.
      #
      # Some line types need special code to extract the entry.

      if ( $lineInfo->{RegExGetEntry} ) {

         if ( $token->fullRealToken =~ $lineInfo->{RegExGetEntry} ) {
            my $tok = $1;
            my @entries = split /,(?:\w+)?/, $tok;

            # Some line types refer to other line entries directly
            # in the line identifier.
               TidyLst::Report::add_to_xcheck_tables(
                  $lineInfo->{IdentRefType},
                  $lineInfo->{Linetype},
                  $token->file,
                  $token->line,
                  @entries,
               );

         } else {

            getLogger()->warning(
               qq(Cannot find the ) . $lineInfo->{Linetype} . q( name),
               $token->file,
               $token->line
            );
         }
      }

      # if we stripped of a modification (MOD, FORGET, COPY), use the
      # unmodified value, otherwise, just use ->value
      $entityName //= $token->value;

      setEntityValid($lineInfo->{Linetype}, $entityName);

      # Check to see if the token must be recorded for other
      # token types.
      if ( exists $lineInfo->{OtherValidEntries} ) {
         for my $tokenType ( @{ $lineInfo->{OtherValidEntries} } ) {
            setEntityValid($tokenType, $token->value);
         }
      }
   }
}

=head2 addValidEntities

   Extract the name of any valid entities defined on this line and queue them
   up to be used in the validity testing of other tags.

=cut

sub addValidEntities {

   my ($line, $lineInfo) = @_;

   for my $column (keys %tagsWithValidityData) {
      if ($line->hasColumn($column)) {

         # If this column has entity data stored, add it for validity checking
         # of other tags.
         COLUMN:
         for my $token (@{ $line->column($column) }) {

            next COLUMN unless $token->hasEntityLabel;

            # Start kits store two values (don't know why, prettylst did it)
            if ($token->entityLabel =~ qr/^KIT/) {
               setEntityValid($token->entityLabel, "KIT:". $token->entityValue);
            }
            setEntityValid($token->entityLabel, $token->entityValue);
         }
      }
   }

   if ( $line->isType('EQUIPMOD') ) {
      # We keep track of the KEYs for the equipmods.
      if ( $line->hasColumn('KEY') ) {

         # We extract the key
         my $token = $line->firstTokenInColumn('KEY');

         setEntityValid("EQUIPMOD Key", $token->value);
      }
   }

   # For Abilities, add the key and the name, both with a category prefix,
   # should solve most of the missing abilities reports.
   if ($line->type eq 'ABILITY') {

      my $category;
      my $key;
      my $entityName = $line->entityName;

      if ($line->hasColumn('CATEGORY')) {
         $category = $line->valueInFirstTokenInColumn('CATEGORY'); 
      }

      if ($line->hasColumn('KEY')) {
         $key = $line->valueInFirstTokenInColumn('KEY'); 
      }

      if (defined $category && defined $key) {

         my $value = "CATEGORY=${category}|${key}";
         setEntityValid('ABILITY', $value);
      }

      if (defined $category && defined $entityName) {

         my $value = "CATEGORY=${category}|${entityName}";
         setEntityValid('ABILITY', $value);
      }

   } else {

      # This adds the tagless first column in many lines to the validity data. It
      # doesn't really handle abilities because they have CATEGORIES that you have
      # to add to MOD or COPY. This means that anything referencing a modified
      # ability can never find it.
      addNameToValidEntities($line, $lineInfo);
   }

}


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


=head2 

   Create any part of a subdirectory structure that is not already there.

=cut 

sub create_dir {
   my ( $dir, $outputdir ) = @_;

   # Only if the directory doesn't already exist
   if ( !-d $dir ) {

      # Needed to find the full path
      my $parentdir = dirname($dir);

      # If the $parentdir doesn't exist, we create it
      if ( $parentdir ne $outputdir && !-d $parentdir ) {
         create_dir( $parentdir, $outputdir );
      }

      # Create the curent level directory
      mkdir $dir, oct(755) or die "Cannot create directory $dir: $OS_ERROR";
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


=head2 matchLineType

   Match the given line, and return the line definition.

=cut

sub matchLineType {
   my ($line, $fileType) = @_;

   # Try each of the line types for this file type until we get a match or
   # exhaust the types.

   my $lineSpec;
   for my $rec ( @{ $parseControl{$fileType} } ) {
      if ( $line =~ $rec->{RegEx} ) {

         $lineSpec = $rec;
         last;
      }
   }

   return $lineSpec
}

=head2 normaliseFile

   Normalize the lines, and detect if the file wasMultiLine 

   Parameters: $buffer => raw file data in a single line

   Returns: $lines an arrayref containing lines normalized to tab-based format
            $wasMultiLine a boolean which is true if logical lines were split across physical lines

=cut

sub normaliseFile {

   # TODO: handle empty buffers, other corner-cases
   my $buffer = shift || "";     # default to empty line when passed undef

   my @lines;
   my $wasMultiLine;

   # First, we clean out empty lines that contain only white-space. Otherwise,
   # we could have false positives on the filetype.  Simply remove all
   # whitespace that is alone on its line.

   $buffer =~ s/^\s*$//g;

   # having a tab as a first character on a non-whitespace line is a sign of a
   # multi-line file

   if ($buffer =~ /^\t+\S/m) {

      $wasMultiLine = 1;

      # Normalize to tab-based
      # 1) All lines that start with a tab belong to the previous line.
      # 2) Copy the lines as-is to the end of the previous line

      # We use a regexp that just removes the newlines, which is easier than
      # copying

      $buffer =~ s/\n\t/\t/mg;

   } else {
      $wasMultiLine = 0;
   }

   # Split into an array of lines.
   @lines = split /\n/, $buffer;

   # return a arrayref so we are a little more efficient
   return (\@lines, $wasMultiLine);
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

   my $currentLineType = "";

   # This used to be used in the reformatting code, now it's only use is to
   # recognise sub lines which are not preceeded by a MAIN line.
   my $lastMainLine = -1;

   # New lines generated
   my @newLines;   

   # Phase I - Split line in tokens and parse the tokens

   my $lineNum = 1;
   LINE:
   for my $thisLine (@ {$lines_ref} ) {

      # Convert the non-ascii character in the line
      my $newLine = convertEntities($thisLine);

      # Remove spaces at the end of the line
      $newLine =~ s/\s+$//;

      # Remove spaces at the begining of the line
      $newLine =~ s/^\s+//;

      # Using $currentLineType because it was set on a previous cycle (or is
      # an empty string until we find a line type)..
      my $line = TidyLst::Line->new(
         type     => $currentLineType,
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

      my $lineInfo = matchLineType($newLine, $fileType);

      # If we didn't find a record with info how to parse this line
      if ( ! defined $lineInfo ) {
         $log->warning(
            qq(Can\'t find the line type for "$newLine"),
            $file,
            $lineNum
         );

         # We push the line as is.
         push @newLines, $line;
         next LINE;
      }

      # Found an info record, overwrite the defaults we added for these fields
      # we created this line object.
      $line->mode($lineInfo->{Mode});
      $line->format($lineInfo->{Format});
      $line->header($lineInfo->{Header});

      # What type of line is it?
      $currentLineType = $lineInfo->{Linetype};

      if ( $lineInfo->{Mode} == MAIN ) {

         $lastMainLine = $lineNum - 1;

      } elsif ( $lineInfo->{Mode} == SUB ) {

         if ($lastMainLine == -1) {
            $log->warning(
               qq{SUB line "$currentLineType" is not preceded by a MAIN line},
               $file,
               $lineNum
            )
         }

      } elsif ( $lineInfo->{Mode} == SINGLE ) {

         $lastMainLine = -1;

      } else {

         die qq(Invalid type for $currentLineType);
      }

      # Got a line info hash, so update the line type in the line
      $line->type($lineInfo->{Linetype});

      # Identify the deprecated tags.
      scanForDeprecatedTokens( $newLine, $lineInfo->{Linetype}, $file, $lineNum, $line, );

      # By default, the tab character is used
      my $sep = $lineInfo->{SepRegEx} || qr(\t+);

      # We split the tokens, strip the spaces and silently remove the empty tags
      # (empty tokens are the result of [tab][space][tab] type of chracter
      # sequences).
      # [ 975999 ] [tab][space][tab] breaks prettylst
      my @tokens =
         grep { $_ ne q{} }
         map { s{ \A \s* | \s* \z }{}xmsg; $_ }
         split $sep, $newLine;

      #First, we deal with the tag-less column
      COLUMN:
      for my $column ( getTaglessColumn($lineInfo->{Linetype}) ) {

         # If this line type does not have tagless first entry then it doesn't
         # need this separate treatment
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
            lineType  => $lineInfo->{Linetype},
            file      => $file,
            line      => $lineNum,
         );

         $line->add($token);

         # Statistic gathering
         incCountValidTags($lineInfo->{Linetype}, $column);
      }

      # Second, let's parse the regular columns
      for my $rawToken (@tokens) {

         my ($extractedToken, $value) =
            extractTag($rawToken, $lineInfo->{Linetype}, $file, $lineNum);

         # if extractTag returns a defined value, no further processing is
         # neeeded. If tag is defined but value is not, then the tag that was
         # returned is the cleaned token and should be processed further.
         if ($extractedToken && not defined $value) {

            my $token =  TidyLst::Token->new(
               fullToken => $extractedToken,
               lineType  => $lineInfo->{Linetype},
               file      => $file,
               line      => $lineNum,
            );

            # Potentally modify the tag
            $token->process();

            my $tag = $token->tag;

            if ($line->hasColumn($tag) && ! isValidMultiTag($lineInfo->{Linetype}, $tag)) {
               $log->notice(
                  qq{The tag "$tag" should not be used more than once on the same }
                  . $lineInfo->{Linetype} . qq{ line.\n},
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

      processLine($line, $lineInfo);

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

   # Phase II - Categorise comment and blank lines.
   #
   # Comments can be Header lines, Block comments or ordinary comments.  Header
   # lines are replaced. Block comments are passed through unaltered, but are
   # used to split up locks of MAIN lines. Ordinary comments are passed through
   # unaltered into the newly formatted file. 

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

   # Phase III - File Conversion 
   #
   # We manipulate the tags for the whole file here

   doFileConversions(\@newLines, $fileType, $file);

   # Phase IV - Potential reformating of the lines

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


=head2 processFile

   Check that the file type is parseable, and if so, parse the file
   and write the modified result (if necessary and permitted).

=cut

sub processFile {
   
   my ($file, $typeAndGameMode) = @_;

   my $fileType  = $typeAndGameMode->{'fileType'}; 
   my $gameModes = $typeAndGameMode->{'gameMode'}; 

   my $log = getLogger();

   my $numberofcf   = 0;     # Number of extra CF found in the file.
   my $wasMultiLine = 0;

   # Will hold all the lines of the file
   my @lines;           

   if ( $file eq "STDIN" ) {

      local $/ = undef; # read all from buffer
      my $buffer = <>;

      (my $lines, $wasMultiLine) = normaliseFile($buffer);
      @lines = @{$lines};

   } else {

      # We read only what we know needs to be processed
      my $parseable = isParseableFileType($fileType);

      if (ref( $parseable ) ne 'CODE') {
         return 0;
      }

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

         (my $lines, $wasMultiLine) = normaliseFile($buffer);
         @lines = @{$lines};
      };

      if ( $EVAL_ERROR ) {
         # There was an error in the eval
         $log->error( $EVAL_ERROR, $file );
         return 0;
      }
   }

   # If the file is empty, we skip it
   unless (@lines) {
      $log->notice("Empty file.", $file);
      return 0;
   }

   # Check to see if we are dealing with a HTML file
   if ( grep /<html>/i, @lines ) {
      $log->error( "HTML file detected. Maybe you had a problem with your CVS checkout.\n", $file );
      return 0;
   }

   my $headerRemoved = 0;

   # While the first line is any sort of comment about pretty lst or TidyLst,
   # we remove it
   REMOVE_HEADER:
   while (  $lines[0] =~ $TidyLst::Data::CVSPattern 
         || $lines[0] =~ $TidyLst::Data::headerPattern ) {
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

   my $parser = isParseableFileType($fileType);

   if ( ref($parser) eq "CODE" ) {

      # The overwhelming majority of checking, correcting and reformatting happens in this operation
      my ($newlines_ref) = &{ $parser }( $fileType, \@lines, $file);

      # Let's remove any tralling white spaces
      for my $line (@$newlines_ref) {
         $line =~ s/\s+$//;
      }

      # Some file types are never written
      if ($wasMultiLine) {
         $log->report("SKIP rewrite for $file because it is a multi-line file");
         return 0;
      }

      if (!isWriteableFileType($fileType)) {
         return 0;
      }

      # We compare the result with the orginal file.
      # If there are no modifications, we do not create the new files
      my $same  = NO;
      my $index = 0;

      # First, we check if there are obvious reasons not to write the new file
      # No extra CRLF characters were removed, same number of lines
      if (!getOption('writeall') && !$numberofcf && $headerRemoved && scalar(@lines) == scalar(@$newlines_ref)) {

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

      if ($same) {
         return 0;
      }

      my $write_fh;

      if (getOption('outputpath')) {

         my $newfile = $file;
         my $inputpath  = getOption('inputpath');
         my $outputpath = getOption('outputpath');
         $newfile =~ s/${inputpath}/${outputpath}/i;

         # Needed to find the full path
         my ($file, $basedir) = fileparse($newfile);

         # Create the subdirectory if needed
         create_dir( $basedir, getOption('outputpath') );

         open $write_fh, '>', $newfile;

      } else {

         # Output to standard output
         $write_fh = *STDOUT;
      }

      # The first line of the new file will be a comment line.
      print {$write_fh} $TidyLst::Data::TidyLstHeader;

      # We print the result
      for my $line ( @{$newlines_ref} ) {
         print {$write_fh} "$line\n"
      }

      # If we opened a filehandle, then close it
      if (getOption('outputpath')) {
         close $write_fh;
      }

      return 1;

   } else {
      warn "Didn't process filetype \"$fileType\".\n";
      return 0;
   }
}


=head2 processLine

   This function does additional processing on each line once
   it has been seperated into tokens.

   The processing is a mix of validation and conversion.

=cut


sub processLine {

   my ($line, $lineInfo) = @_;

   my $log = getLogger();

   ############################################################
   ######################## Conversion ########################
   # We manipulate the tags for the line here

   doLineConversions($line);

   addValidEntities($line, $lineInfo);

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
         printToExportList('SPELL', makeExportListString($name, $sourcepage, $line->num, $filename));
      }

      if ( $line->isType('CLASS') ) {

         # Only one report per class
         if ($className ne $name) {
            printToExportList('CLASS', makeExportListString($className, $line->num, $filename));
         };
         $className = $name;
      }

      if ( $line->isType('DEITY') ) {
         printToExportList('DEITY', makeExportListString($name, $line->num, $filename));
      }

      if ( $line->isType('DOMAIN') ) {
         printToExportList('DOMAIN', makeExportListString($name, $line->num, $filename));
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

         printToExportList('EQUIPMENT', makeExportListString($name, $outputname, $line->num, $filename));
      }

      if ( $line->isType('EQUIPMOD') ) {

         my $key  = $line->hasColumn('KEY')  ? $line->valueInFirstTokenInColumn('KEY') : '';
         my $type = $line->hasColumn('TYPE') ? $line->valueInFirstTokenInColumn('TYPE') : '';

         printToExportList('EQUIPMOD', makeExportListString($name, $key, $type, $line->num, $filename));
      }

      if ( $line->isType('FEAT') ) {
         printToExportList('FEAT', makeExportListString($name, $line->num, $filename));
      }

      if ( $line->isType('KIT STARTPACK') ) {
         printToExportList('KIT', makeExportListString($name, $line->num, $filename));
      }

      if ( $line->isType('KIT TABLE') ) {
         printToExportList('TABLE', makeExportListString($name, $line->num, $filename));
      }

      if ( $line->isType('LANGUAGE') ) {
         printToExportList('LANGUAGE', makeExportListString($name, $line->num, $filename));
      }

      if ( $line->isType('RACE') ) {

         my $type    = $line->valueInFirstTokenInColumn('RACETYPE');
         my $subType = $line->valueInFirstTokenInColumn('RACESUBTYPE');

         printToExportList('RACE', makeExportListString($name, $type, $subType, $line->num, $filename));
      }

      if ( $line->isType('SKILL') ) {

         printToExportList('SKILL', makeExportListString($name, $line->num, $filename));
      }

      if ( $line->isType('TEMPLATE') ) {

         printToExportList('TEMPLATE', makeExportListString($name, $line->num, $filename));
      }
   }

   if (getOption('bonusreport')) {
      $line->addToBonusAndPreReport
   }
}

1;
