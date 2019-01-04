package LstTidy::Token;

use strict;
use warnings;

use Mouse;
use Carp;
use Text::Balanced ();

use File::Basename qw(dirname);
use Cwd  qw(abs_path);
use lib dirname(dirname abs_path $0);

use LstTidy::Convert qw(doTokenConversions);
use LstTidy::Data qw(
   addToValidTypes 
   addValidCategory
   getValidSystemArr
   incCountInvalidTags 
   incCountValidTags 
   isValidCheck
   isValidEntity 
   isValidFixedValue 
   isValidPreTag
   isValidTag
   mungKey
   registerXCheck 
   searchRace
   setEntityValid
   tagTakesFixedValues
   );

use LstTidy::Log;
use LstTidy::LogFactory qw{getLogger};

use LstTidy::Options qw(getOption isConversionActive);

use LstTidy::Variable qw(
   oldExtractVariables
   parseJepFormula
   );

has 'tag' => (
   is       => 'rw',
   isa      => 'Str',
   required => 1,
);

has 'isNegatedPre' => (
   is     => 'rw',
   isa    => 'Bool',
);

has 'origToken' => (
   is  => 'ro',
   isa => 'Str',
);

has 'value' => (
   is        => 'rw',
   isa       => 'Maybe[Str]',
   required  => 1,
);

has 'lineType' => (
   is       => 'rw',
   isa      => 'Str',
   required => 1,
);

has 'file' => (
   is      => 'rw',
   isa     => 'Str',
   required => 1,
);

has 'line' => (
   is        => 'rw',
   isa       => 'Int',
   predicate => 'hasLine',
);

has 'noMoreErrors' => (
   is     => 'rw',
   isa    => 'Bool',
);

around 'BUILDARGS' => sub {

   my $orig = shift;
   my $self = shift;

   my %args = ( @_ > 1 ) ? @_ : %{ $_[0] } ;

   if ( exists $args{'fullToken'} ) {
      @args{'tag', 'value'} = split ':', $args{'fullToken'}, 2;

      # got a fullToken store it as a readonly origToken
      $args{'origToken'} = $args{'fullToken'};

      delete $args{'fullToken'};

   # no fullToken, construct an origToken
   } else {
      
      my $tag   = exists $args{'tag'} ? $args{'tag'} : q{} ;
      my $value = exists $args{'value'} ? $args{'value'} : q{};

      $args{'origToken'} = $tag . ':' . $value;
   }

   return $self->$orig(%args);
};

sub BUILD {
   my $self = shift;

   # deal with negated PRE tags, set the tag to itself because teh constructor
   # doesn't trigger the around tag sub.
   if ($self->tag =~ m/^!(pre)/i) {
      $self->tag($self->tag);
   };
};

around 'tag' => sub {
   my $orig = shift;
   my $self = shift;

   # no arguments, so this is a simple accessor
   return $self->$orig() unless @_;

   # get the new value of tag
   my $newId = shift; 

   # modify new tag and get a boolean for if it was modified.
   my $mod = $newId =~ s/^!(pre)/$1/i;

   # only true if new tag was a negated PRE tag
   $self->isNegatedPre($mod);

   return $self->$orig($newId);
};

sub realTag {
   my ($self) = @_;

   my $return = defined $self->isNegatedPre && $self->isNegatedPre ? q{!} : q{};

   return  $return . $self->tag;
}

sub fullToken {
   my ($self) = @_;

   my $sep = $self->tag =~ m/:/ ? q{} : q{:};

   return $self->tag() . $sep . $self->value();
}

sub fullRealToken {
   my ($self) = @_;

   my $sep = $self->tag =~ m/:/ ? q{} : q{:};

   return $self->realTag() . $sep . $self->value();
}

sub clone {
   my ($self, %params) = @_;

   my $newToken = $self->meta->clone_object($self, %params);

   if (exists $params{tag}) {
      $newToken->tag($params{tag}) ;
   }

   return $newToken;
}



# These operations convert the id of tags with subTags to contain the embeded :
my %tagProcessor = (
   AUTO        => \&_auto,
   BONUS       => \&_sub,
   FACT        => \&_protean,
   FACTSET     => \&_protean,
   INFO        => \&_protean,
   PROFICIENCY => \&_sub,
   QUALIFY     => \&_sub,
   QUALITY     => \&_protean,
   SPELLKNOWN  => \&_sub,
   SPELLLEVEL  => \&_sub,
);


=head2 process

   This operation does all the validation and manipulation that is done at the
   token level.

=cut

sub process {

   my ($token) = @_;

   my $log = getLogger();

   # All PCGen tags should have at least TAG_NAME:TAG_VALUE (Some rare tags
   # have two colons). Anything without a token value is an anomaly. The only
   # exception to this rule is LICENSE that can be used without a value to
   # display an empty line.

   if ( (!defined $token->value || $token->value eq q{}) && $token->fullToken ne 'LICENSE:') {
      $log->warning(
         qq(The tag "} . $token->fullToken . q{" is missing a value (or you forgot a : somewhere)),
         $token->file,
         $token->line
      );

      # We set the value to prevent further errors
      $token->value(q{});
   }

   if ($token->tag eq 'ADD') {
      LstTidy::Convert::convertAddTokens($token);
   }

   # Special cases like BONUS:..., FACT:..., etc.
   #
   # These are converted from e.g. FACT  BaseSize|M  to  FACT:BaseSize  |M
   
   if (exists $tagProcessor{$token->tag}) {

      my $processor = $tagProcessor{$token->tag};

      if ( ref ($processor) eq "CODE" ) {
         &{ $processor }($token);
      }
   }

   if ( defined $token->value && $token->value =~ /^.CLEAR/i ) {
      $token->_clear();
   }

   # The tag is invalid and it's not a commnet.
   if ( ! isValidTag($token->lineType, $token->tag) && index( $token->fullToken, '#' ) != 0 ) {

      $token->_invalid();

   } elsif (isValidTag($token->lineType, $token->tag)) {

      # Statistic gathering
      incCountValidTags($token->lineType, $token->realTag);
   }

   # Check and reformat the values for the tags with only a limited number of
   # values.
   if (tagTakesFixedValues($token->tag)) {
      $token->_limited();
   }

   ############################################################
   ######################## Conversion ########################
   # We manipulate the tag here
   doTokenConversions($token);

   ############################################################
   # We call the validating function if needed
   if (getOption('xcheck')) {
      $token->_validate()
   };

   if ($token->value eq q{}) {
      $log->debug(qq{process: } . $token->fullToken, $token->file, $token->line)
   };
}



#################################################################################################
# Nothing below this should be called from outside the object (probably)

# Will hold the portions of a race that have been matched with wildcards.
# For example, if Elf% has been matched (given no default Elf races).
our %racePartialMatch;


my %nonPCCOperations = (
   'ADD:FEAT'  => \&_feats,
   'AUTO:FEAT' => \&_feats,
   'CLASS'     => \&_class,
   'DEITY'     => \&_deity,
   'DOMAIN'    => \&_domain,
   'FEAT'      => \&_feats,
   'FEATAUTO'  => \&_feats,
   'KIT'       => \&_kit,
   'MFEAT'     => \&_feats,
   'RACE'      => \&_race,
   'SKILL'     => \&_skill,
   'TEMPLATE'  => \&_template,
   'VFEAT'     => \&_feats,
);

my %spellOperations = (
   'DESC'         => \&_embededCasterLevel,
   'DURATION'     => \&_embededCasterLevel,
   'TARGETAREA'   => \&_embededCasterLevel,
);

my %standardOperations = (
   'ADD:EQUIP'          => \&_addEquip,
   'ADD:LANGUAGE'       => \&_addLanguage,
   'ADD:SKILL'          => \&_addSkill,
   'ADD:SPELLCASTER'    => \&_addSpellcaster,
   'ADDDOMAINS'         => \&_addDomains,
   'CATEGORY'           => \&_categories,
   'CCSKILL'            => \&_skill,
   'CHANGEPROF'         => \&_changeProf,
   'CLASSES'            => \&_classes,
   'CSKILL'             => \&_skill,
   'DEFINE'             => \&_define,
   'DOMAINS'            => \&_domains,
   'EQMOD'              => \&_eqmod,
   'IGNORES'            => \&_ignores,
   'LANGAUTOxxx'        => \&_language,
   'LANGBONUS'          => \&_language,
   'MONCCSKILL'         => \&_skill,
   'MONCSKILL'          => \&_skill,
   'MOVE'               => \&_move,
   'MOVECLONE'          => \&_moveClone,
   'NATURALATTACKS'     => \&_naturalAttacks,
   'RACESUBTYPE'        => \&_raceSubType,
   'RACETYPE'           => \&_raceType,
   'REPLACES'           => \&_ignores,
   'SA'                 => \&_sa,
   'SPELLKNOWN:CLASS'   => \&_spellLevelClass,
   'SPELLKNOWN:DOMAIN'  => \&_spellLevelDomain,
   'SPELLLEVEL:CLASS'   => \&_spellLevelClass,
   'SPELLLEVEL:DOMAIN'  => \&_spellLevelDomain,
   'SPELLS'             => \&_spells,
   'SR'                 => \&_numeric,
   'STARTPACK'          => \&_startPack,
   'STARTSKILLPTS'      => \&_numeric,
   'STAT'               => \&_stat,
   'SWITCHRACE'         => \&_switchRace,
   'TYPE'               => \&_types,
);

# List of types that are valid in BONUS:SLOTS
my %validBonusSlots = map { $_ => 1 } (
   'Amulet',
   'Armor',
   'Belt',
   'Boot',
   'Bracer',
   'Cape',
   'Clothing',
   'Eyegear',
   'Glove',
   'Hands',
   'Headgear',
   'Legs',
   'Psionictattoo',
   'Ring',
   'Robe',
   'Shield',
   'Shirt',
   'Suit',
   'Tattoo',
   'Transportation',
   'Vehicle',
   'Weapon',

   # These are the proper Pathfinder slots
   'Body',
   'Chest',
   'Feet',
   'Head',
   'Headband',
   'Neck',
   'Shoulders',
   'Wrists',

   # Special value for the CHOOSE tag
   'LIST',
);


my %validNaturalAttacksType = map { $_ => 1 } (

   # WEAPONTYPE defined in miscinfo.lst
   'Bludgeoning',
   'Piercing',
   'Slashing',
   'Fire',
   'Acid',
   'Electricity',
   'Cold',
   'Poison',
   'Sonic',

   # WEAPONCATEGORY defined in miscinfo.lst 3e and 35e
   'Simple',
   'Martial',
   'Exotic',
   'Natural',

   # Additional WEAPONCATEGORY defined in miscinfo.lst Modern and Sidewinder
   'HMG',
   'RocketLauncher',
   'GrenadeLauncher',

   # Additional WEAPONCATEGORY defined in miscinfo.lst Spycraft
   'Hurled',
   'Melee',
   'Handgun',
   'Rifle',
   'Tactical',

   # Additional WEAPONCATEGORY defined in miscinfo.lst Xcrawl
   'HighTechMartial',
   'HighTechSimple',
   'ShipWeapon',
);


my %validSubTags = (
   AUTO => {
      'ARMORPROF'             => 1,
      'EQUIP'                 => 1,
      'LANG'                  => 1,
      'SHIELDPROF'            => 1,
      'WEAPONPROF'            => 1,

      'FEAT'                  => 1,    # Deprecated
   },

   BONUS => {
      'ABILITYPOOL'           => 1,
      'CASTERLEVEL'           => 1,
      'COMBAT'                => 1,
      'CONCENTRATION'         => 1,
      'DC'                    => 1,
      'DOMAIN'                => 1,
      'DR'                    => 1,
      'EQM'                   => 1,
      'EQMARMOR'              => 1,
      'EQMWEAPON'             => 1,
      'FOLLOWERS'             => 1,
      'HD'                    => 1,
      'HP'                    => 1,
      'ITEMCOST'              => 1,
      'LOADMULT'              => 1,
      'MISC'                  => 1,
      'MONSKILLPTS'           => 1,
      'MOVEADD'               => 1,
      'MOVEMULT'              => 1,
      'POSTRANGEADD'          => 1,
      'POSTMOVEADD'           => 1,
      'PCLEVEL'               => 1,
      'RANGEADD'              => 1,
      'RANGEMULT'             => 1,
      'SIZEMOD'               => 1,
      'SAVE'                  => 1,
      'SKILL'                 => 1,
      'SITUATION'             => 1,
      'SKILLPOINTS'           => 1,
      'SKILLPOOL'             => 1,
      'SKILLRANK'             => 1,
      'SLOTS'                 => 1,
      'SPELL'                 => 1,
      'SPECIALTYSPELLKNOWN'   => 1,
      'SPELLCAST'             => 1,
      'SPELLCASTMULT'         => 1,
      'SPELLKNOWN'            => 1,
      'VISION'                => 1,
      'STAT'                  => 1,
      'UDAM'                  => 1,
      'VAR'                   => 1,
      'WEAPON'                => 1,
      'WEAPONPROF'            => 1,
      'WIELDCATEGORY'         => 1,

      'CHECKS'                => 1,    # Deprecated
      'DAMAGE'                => 1,    # Deprecated 4.3.8 - Remove 5.16.0 - Use BONUS:COMBAT|DAMAGE.x|y
      'ESIZE'                 => 1,    # Not listed in the Docs
      'FEAT'                  => 1,    # Deprecated
      'LANGUAGES'             => 1,    # Not listed in the Docs
      'MOVE'                  => 1,    # Deprecated 4.3.8 - Remove 5.16.0 - Use BONUS:MOVEADD or BONUS:POSTMOVEADD
      'REPUTATION'            => 1,    # Not listed in the Docs
      'TOHIT'                 => 1,    # Deprecated 5.3.12 - Remove 5.16.0 - Use BONUS:COMBAT|TOHIT|x
   },

   FACT => {
      'Abb'                   => 1,
      'Appearance'            => 1,
      'AppliedName'           => 1,
      'Article'               => 1,
      'BaseSize'              => 1,
      'ClassType'             => 1,
      'CompMaterial'          => 1,
      'IsPC'                  => 1,
      'RateOfFire'            => 1,
      'SpellType'             => 1,
      'Symbol'                => 1,
      'Title'                 => 1,
      'Worshipers'            => 1,
   },

   FACTSET => {
      'Pantheon'              => 1,
      'Race'                  => 1,
      'Worshipers'            => 1,
   },

   INFO => {
      'Prerequisite'          => 1,
      'Normal'                => 1,
      'Special'               => 1,
   },

   PROFICIENCY => {
      'WEAPON'                => 1,
      'ARMOR'                 => 1,
      'SHIELD'                => 1,
   },

   QUALIFY => {
      'ABILITY'               => 1,
      'CLASS'                 => 1,
      'DEITY'                 => 1,
      'DOMAIN'                => 1,
      'EQUIPMENT'             => 1,
      'EQMOD'                 => 1,
      'RACE'                  => 1,
      'SPELL'                 => 1,
      'SKILL'                 => 1,
      'TEMPLATE'              => 1,
      'WEAPONPROF'            => 1,

      'FEAT'                  => 1,    # Deprecated
   },

   QUALITY => {
      'Aura'                        => 1,
      'Capacity'                    => 1,
      'Caster Level'                => 1,
      'Construction Cost'           => 1,
      'Construction Craft DC'       => 1,
      'Construction Requirements'   => 1,
      'Slot'                        => 1,
      'Usage'                       => 1,
   },

   SPELLLEVEL => {
      CLASS                   => 1,
      DOMAIN                  => 1,
   },

   SPELLKNOWN => {
      CLASS                   => 1,
      DOMAIN                  => 1,
   },
);


my %validWieldCategory = map { $_ => 1 } (

   # From miscinfo.lst 35e
   'Light',
   'OneHanded',
   'TwoHanded',
   'ToSmall',
   'ToLarge',
   'Unusable',
   'None',

   # Hardcoded
   'ALL',
);




# Queue up Domain tags for cross checking

sub _addDomains {

   my ($self) = @_;

   # ADDDOMAINS:<domain1>.<domain2>.<domain3>. etc.
   registerXCheck(
      'DOMAIN', 
      $self->tag, 
      $self->file, 
      $self->line, 
      split '\.', $self->value );
}


# Queue up the EQUIPMENT and Variables from the ADD:EQUIP for cross checking.

sub _addEquip {

   my ($self) = @_;


   # ADD:EQUIP(<list of equipment>)<formula>
   if ( $self->value =~ 
      m{ [(]   # Opening brace
         (.*)  # Everything between braces include other braces
         [)]   # Closing braces
         (.*)  # The rest
      }xms ) {

      my ( $list, $formula ) = ( $1, $2 );

      # First the list of equipements
      # ANY is a spcial hardcoded cases for ADD:EQUIP
      registerXCheck(
         'EQUIPMENT', 
         qq{@@" in "} . $self->fullToken, 
         $self->file, 
         $self->line, 
         grep { uc($_) ne 'ANY' } split ',', $list );

      # Second, we deal with the formula
      registerXCheck(
         'DEFINE Variable', 
         qq{@@" from "$formula" in "} . $self->fullToken, 
         $self->file, 
         $self->line, 
         $self->_variables($formula) );

   } else {
      getLogger()->notice(
         qq{Invalid syntax: "} . $self->fullToken . q{"},
         $self->file,
         $self->line
      );
   }
}


# Split the value inside parens and queue for cross checking.

sub _addLanguage {

   my ($self) = @_;

   # Syntax: ADD:LANGUAGE(<coma separated list of languages)<number>
   if ( $self->value =~ /\((.*)\)/ ) {
      registerXCheck(
         'LANGUAGE', '
         ADD:LANGUAGE(@@)', 
         $self->file, 
         $self->line, 
         split ',',  $1 );
   } else {
      getLogger()->notice(
         qq{Invalid syntax "} . $self->fullToken . q{"},
         $self->file,
         $self->line
      );
   }
}


# Queue up the Skills and variables for cross checking

sub _addSkill {

   my ($self) = @_;

   # ADD:SKILL(<list of skills>)<formula>
   if ( $self->value =~ /\((.*)\)(.*)/ ) {
      my ( $list, $formula ) = ( $1, $2 );

      # First the list of skills
      # ANY is a spcial hardcoded cases for ADD:EQUIP
      registerXCheck(
         'SKILL', 
         qq{@@" in "} . $self->fullToken, 
         $self->file, 
         $self->line, 
         grep { uc($_) ne 'ANY' } split ',', $list );

      # Second, we deal with the formula
      registerXCheck(
         'DEFINE Variable', 
         qq{@@" from "$formula" in "} . $self->fullToken, 
         $self->file, 
         $self->line, 
         $self->_variables($formula) );

   } else {
      getLogger()->notice(
         qq{Invalid syntax: "} . $self->fullToken . q{"},
         $self->file,
         $self->line
      );
   }
}


# Queue up the Classes and variables from the Add:SPELLCASTER tag for cross
# checking.

sub _addSpellcaster {

   my ($self) = @_;

   # ADD:SPELLCASTER(<list of classes>)<formula>
   if ( $self->value =~ /\((.*)\)(.*)/ ) {
      my ( $list, $formula ) = ( $1, $2 );

      # First the list of classes
      # ANY, ARCANA, DIVINE and PSIONIC are spcial hardcoded cases for
      # the ADD:SPELLCASTER tag.
      registerXCheck(
         'CLASS', 
         qq{@@" in "} . $self->fullToken, 
         $self->file, 
         $self->line, 
         grep { uc($_) !~ qr{^(?:ANY|ARCANE|DIVINE|PSIONIC)$}  } split ',', $list );

      # Second, we deal with the formula
      registerXCheck(
         'DEFINE Variable',
         qq{@@" from "$formula" in "} . $self->fullToken,
         $self->file,
         $self->line,
         $self->_variables($formula) );

   } else {

      getLogger()->notice(
         qq{Invalid syntax: "} . $self->fullToken . q{"},
         $self->file,
         $self->line
      );
   }
}


# Check that the Auto token is valid and adjust it if necessary.

sub _auto {

   my ($self) = @_;

   my $log = getLogger();

   my $foundAutoType;

   AUTO_TYPE:
   for my $autoType ( sort { length($b) <=> length($a) || $a cmp $b } keys %{ $validSubTags{'AUTO'} } ) {

      if ( $self->value =~ m/^$autoType/ ) {
         # We found what we were looking for
         $self->value($self->value =~ s/^$autoType//r);
         $foundAutoType = $autoType;
         last AUTO_TYPE;
      }
   }

   if ($foundAutoType) {

      $self->tag($self->tag . ':' . $foundAutoType);

   } elsif ( $self->value =~ /^([^=:|]+)/ ) {

      my $potentialAddTag = $self->tag . ':' . $1;

      incCountInvalidTags($self->lineType, $potentialAddTag);
      $log->notice(
         qq{Invalid token "$potentialAddTag" found in } . $self->lineType,
         $self->file,
         $self->line
      );
      $self->noMoreErrors(1);

   } else {

      incCountInvalidTags($self->lineType, "AUTO");
      $log->notice(
         qq{Invalid ADD token "} . $self->origToken . q{" found in } . $self->lineType,
         $self->file,
         $self->line
      );
      $self->noMoreErrors(1);

   }
}



# Validate a Bonus checks tag. 

# BONUS:CHECKS|<check list>|<jep> {|TYPE=<bonus type>} {|<pre tags>}
# BONUS:CHECKS|ALL|<jep>          {|TYPE=<bonus type>} {|<pre tags>}
# <check list> :=   ( <check name 1> { | <check name 2> } { | <check name 3>} )
#                       | ( BASE.<check name 1> { | BASE.<check name 2> } { | BASE.<check name 3>} )


sub _bonusChecks {

   my ($self) = @_;

   # We get parameter 1 and 2 (0 is empty since $self->value begins with a |)
   my ($checks, $formula) = (split /[|]/, $self->value)[1, 2];
      
   if ( $checks ne 'ALL' ) {

      my ($base, $non_base) = ( 0, 0 );

      my $log = getLogger();

      for my $check ( split q{,}, $checks ) {

         # We keep the original name for error messages
         my $cleanCheck = $check;

         # Did we use BASE.? is yes, we remove it
         if ( $cleanCheck =~ s/ \A BASE [.] //xms ) {
            $base = 1;
         } else {
            $non_base = 1;
         }

         if ( ! isValidCheck($cleanCheck) ) {
            $log->notice(
               qq{Invalid save check name "$check" found in "} . $self->fullToken . q{"},
               $self->file,
               $self->line
            );
         }
      }

      # Warn the user if they're mixing base and non-base
      if ( $base && $non_base ) {
         $log->info(
            qq{Are you sure you want to mix BASE and non-BASE in "} . $self->fullToken . q{"},
            $self->file,
            $self->line
         );
      }
   }

   # The formula part
   registerXCheck(
      'DEFINE Variable', 
      qq{@@" in "} . $self->fullToken, 
      $self->file, 
      $self->line, 
      $self->_variables($formula) );
}


# BONUS:FEAT|POOL|<formula>|<prereq list>|<bonus type>
# 
# Validate the bonus FEAT tag. The first parameter must be POOL, the second
# must be a valid jep formula. This is then followed by a list of PRE tags and
# one single optional TYPE= tag.

sub _bonusFeat {

   my ($self) = @_;

   # @list_of_param will contains all the non-empty parameters
   # included in $self->value. The first one should always be
   # POOL.
   my @list_of_param = grep {/./} split '\|', $self->value;

   if ((shift @list_of_param) ne 'POOL') {

      # For now, only POOL is valid here
      LstTidy::LogFactory::getLogger()->notice(
         qq{Only POOL is valid as second paramater for BONUS:FEAT "} . $self->fullToken . q{"},
         $self->file,
         $self->line
      );
   }

   # The next parameter is the formula
   registerXCheck( 
      'DEFINE Variable', 
      qq{@@" in "} . $self->fullToken, 
      $self->file, 
      $self->line, 
      $self->_variables(shift @list_of_param) );

   # For the rest, we need to check if it is a PRExxx tag or a TYPE=
   my $type_present = 0;

   for my $param (@list_of_param) {

      if ( $param =~ /^(!?PRE[A-Z]+):(.*)/ ) {

         # It's a PRExxx tag, we delegate the validation
         my $preToken = $self->clone(tag => $1, value => $2);
         $preToken->_preToken($self->fullRealToken);

      } elsif ( $param =~ /^TYPE=(.*)/ ) {

         $type_present++;

      } else {

         LstTidy::LogFactory::getLogger()->notice(
            qq{Invalid parameter "$param" found in "} . $self->fullToken . q{"},
            $self->file,
            $self->line
         );
      }
   }

   if ( $type_present > 1 ) {
      LstTidy::LogFactory::getLogger()->notice(
         qq{There should be only one "TYPE=" in "} . $self->fullToken . q{"},
         $self->file,
         $self->line
      );
   }
}


# BONUS:MOVEMULT|<list of move types>|<number to add or mult>
# <list of move types> is a comma separated list of a weird TYPE=<move>.
# The <move> are found in the MOVE tags.
# <number to add or mult> can be a formula

sub _bonusMove {

   my ($self) = @_;

   # undef because the values starts with | which produces an empty field which
   # we discard
   my ( undef, $type_list, $formula ) = ( split '\|', $self->value );

   # We keep the move types for validation
   for my $type ( split ',', $type_list ) {

      if ( $type =~ /^TYPE(=|\.)(.*)/ ) {

         registerXCheck(
            'MOVE Type',
            qq{TYPE$1@@" in "} . $self->fullToken,
            $self->file,
            $self->line,
            $2 );

      } else {

         LstTidy::LogFactory::getLogger()->notice(
            qq{Missing "TYPE=" for "$type" in "} . $self->fullToken . q{"},
            $self->file,
            $self->line
         );
      }
   }

   # Then we deal with the var in formula
   registerXCheck(
      'DEFINE Variable',
      qq{@@" in "} . $self->fullToken,
      $self->file,
      $self->line,
      $self->_variables($formula) );
}


#  BONUS:SLOTS|<slot types>|<number of slots>
#  <slot types> is a comma separated list.  The valid types are defined in
#  %validBonusSlots
#  <number of slots> could be a formula.

sub _bonusSlots {

   my ($self) = @_;

   my ($type_list, $formula) = ( split '\|', $self->value )[1, 2];

   my $log = LstTidy::LogFactory::getLogger();

   # We first check the slot types
   for my $type ( split ',', $type_list ) {
      if ( ! exists $validBonusSlots{$type} ) {
         $log->notice(
            qq{Invalid slot type "$type" in "} . $self->fullToken . q{"},
            $self->file,
            $self->line
         );
      }
   }

   # Then we deal with the var in formula
   registerXCheck(
      'DEFINE Variable', 
      qq{@@" in "} . $self->fullToken,
      $self->file,
      $self->line,
      $self->_variables($formula) );
}


# Validate BONUS tags, over arching operation that delegates the checks to
# more specific operations.

sub _bonusTag {

   my ($self) = @_;

   my $subtag;

   if ($self->tag =~ qr(:)) {
      (undef, $subtag) = split qr/:/, $self->tag, 2;
   } else {
      ($subtag) = split qr/\|/, $self->tag, 2;
   }

   if (not defined $subtag) {
      print STDERR "!!! Full tag: <" . $self->fullRealToken . qq{>\n};
      print STDERR "!!! tag: <" . $self->tag . qq{>\n};
      print STDERR "!!! value <" . $self->value . qq{>\n};
   }

   # Are there any PRE tags in the BONUS tag.
   if ( $self->value =~ /(!?PRE[A-Z]*):([^|]*)/ ) {

      my $preToken = $self->clone(tag => $1, value => $2);
      $preToken->_preToken($self->fullRealToken);
   }

   if ( $subtag eq 'CHECKS' ) {

      $self->_bonusChecks();

   } elsif ( $subtag eq 'FEAT' ) {

      $self->_bonusFeat();

   } elsif ($subtag eq 'MOVEADD' || $subtag eq 'MOVEMULT' || $subtag eq 'POSTMOVEADD' ) {

      $self->_bonusMove();

   } elsif ( $subtag eq 'SLOTS' ) {

      $self->_bonusSlots();

   } elsif ( $subtag eq 'VAR' ) {

      $self->_bonusVar();

   } elsif ( $subtag eq 'WIELDCATEGORY' ) {

      $self->_bonusWeildCategory();
   }
}


# Extract the list of variables being bonused and the list of variables being
# used to bonus them.  Queue these separate lists up for cross checking.

sub _bonusVar {

   my ($self) = @_;

   # BONUS:VAR|List of Names|Formula|... only the first two values are variable related.
   my ($varNameList, @formulae) = ( split '\|', $self->value )[1, 2];

   # First we store the DEFINE variable name
   for my $varName ( split ',', $varNameList ) {
      if ( $varName =~ /^[a-z][a-z0-9_\s]*$/i ) {

         # LIST is filtered out as it may not be valid for the
         # other places were a variable name is used.
         if ( $varName ne 'LIST' ) {
            registerXCheck(
               'DEFINE Variable', 
               qq{@@" in "} . $self->fullToken, 
               $self->file, 
               $self->line, 
               $varName, );
         }

      } else {

         LstTidy::LogFactory::getLogger()->notice(
            qq{Invalid variable name "$varName" in "} . $self->fullToken . q{"},
            $self->file,
            $self->line
         );
      }
   }

   # Second we deal with the formula
   # %CHOICE is filtered out as it may not be valid for the
   # other places were a variable name is used.
   for my $formula ( grep { $_ ne '%CHOICE' } @formulae ) {
      registerXCheck(
         'DEFINE Variable', 
         qq{@@" in "} . $self->fullToken, 
         $self->file, 
         $self->line, 
         $self->_variables($formula) );
   }
}


# BONUS:WIELDCATEGORY|<List of category>|<formula>
#
# Extract the list of weildcategories and check agaist a list of valid ones.
# Also extract any variables in formula and queue them for checking.

sub _bonusWeildCategory {

   my ($self) = @_;


   # BONUS:WIELDCATEGORY|<List of category>|<formula>
   my ($category_list, $formula) = ( split '\|', $self->value )[1, 2];

   my $log = LstTidy::LogFactory::getLogger();

   # Validate the category to see if valid
   for my $category ( split ',', $category_list ) {
      if ( !exists $validWieldCategory{$category} ) {
         $log->notice(
            qq{Invalid category "$category" in "} . $self->fullToken . q{"},
            $self->file,
            $self->line
         );
      }
   }

   # Second, we deal with the formula
   registerXCheck(
      'DEFINE Variable', 
      qq{@@" in "} . $self->fullToken, 
      $self->file, 
      $self->line, 
      $self->_variables($formula) );
}



# Add the categories to Valid Categories.

sub _categories {

   my ($self) = @_;

   # The categories go into validCategories
   for my $category ( split '\.', $self->value ) {
      addValidCategory($self->lineType, $category) 
   }
}


# Extract the equipemnet (weapons) and weapon profs and queue them up for
# cross checking.

sub _changeProf {

   my ($self) = @_;

   # "CHANGEPROF:" <list of weapons> "=" <new prof> { "|"  <list of weapons> "=" <new prof> }*
   # <list of weapons> := ( <weapon> | "TYPE=" <weapon type> ) { "," ( <weapon> | "TYPE=" <weapon type> ) }*

   for my $entry ( split '\|', $self->value ) {
      if ( $entry =~ /^([^=]+)=([^=]+)$/ ) {
         my ( $list_of_weapons, $new_prof ) = ( $1, $2 );

         # First, the weapons (equipment)
         registerXCheck(
            'EQUIPMENT', 
            $self->tag, 
            $self->file, 
            $self->line, 
            split ',', $list_of_weapons );

         # Second, the weapon prof.
         registerXCheck(
            'WEAPONPROF', 
            $self->tag, 
            $self->file, 
            $self->line, 
            $new_prof );
      }
   }
}


# split the value of a PRE token on comma and ensure that the 
# first value is a number.

sub _checkFirstValue {

   my ($self) = @_;

   # We get the list of values
   my @values = split ',', $self->value;

   # first entry is a number
   my $valid = $values[0] =~ / \A \d+ \z /xms;

   # get rid of the number
   shift @values if $valid;

   return $valid, @values;
}



# Queue up the CLASS tag for cross checking
#
# Note: The CLASS linetype doesn't have any CLASS tag, it's called
#       000ClassName internaly. CLASS is a tag used in other line 
#       types like KIT CLASS.
#
# CLASS:<class name>,<class name>,...[BASEAGEADD:<dice expression>]

sub _class  {

   my ($self) = @_;

   # We remove and ignore [BASEAGEADD:xxx] if present

   my $list_of_class = $self->value;

   $list_of_class =~ s{ \[ BASEAGEADD: [^]]* \] }{}xmsg;

   registerXCheck(
      'CLASS', 
      $self->tag, 
      $self->file, 
      $self->line, 
      (split /[|,]/, $list_of_class), );
}



# Validate the CLASSES tag, it can appear on SKILL lines and SPELL lines

sub _classes {

   my ($self) = @_;
   
   if ( $self->lineType eq 'SKILL' ) {

      _classesOnSkill($self);

   } elsif ( $self->lineType eq 'SPELL' ) {

      _classesOnSpell($self);
   }
}



# Split the value and queue it up for cross checking.

sub _classesOnSkill {

   my ($self) = @_;


   # Only CLASSES in SKILL
   CLASS_FOR_SKILL:
   for my $class ( split '\|', $self->value ) {

      # ALL is valid here
      next CLASS_FOR_SKILL if $class eq 'ALL';

      registerXCheck(
         'CLASS', 
         $self->tag, 
         $self->file, 
         $self->line, 
         $class );
   }
}



# Validate CLASSES tags that appear on SPELL lines

sub _classesOnSpell {

   my ($self) = @_;

   my %seen;
   my $log = getLogger();

   # First we find all the classes used
   for my $level ( split '\|', $self->value ) {
      if ( $level =~ /(.*)=(\d+)/ ) {
         for my $entity ( split ',', $1 ) {

            # [ 849365 ] CLASSES:ALL
            # CLASSES:ALL is OK
            # Arcane and Divine are not really OK but they are used
            # as placeholders for use in the MSRD.
            if ($entity ne "ALL" && $entity ne "Arcane" && $entity ne "Divine") {

               registerXCheck(
                  'CLASS', 
                  $self->tag, 
                  $self->file, 
                  $self->line, 
                  $entity );

               if ( $seen{$entity}++ ) {
                  $log->notice(
                     qq{"$entity" found more than once in } . $self->tag,
                     $self->file,
                     $self->line
                  );
               }
            }
         }

      } else {
         if ( $self->tag . ":$level" eq 'CLASSES:.CLEARALL' ) {
            # Nothing to see here. Move on.
         } else {
            $log->warning(
               qq{Missing "=level" after "} . $self->tag . ":$level",
               $self->file,
               $self->line
            );
         }
      }
   }
}


# All the .CLEAR must be separated tags to help with the tag ordering. That
# is, we need to make sure the .CLEAR is ordered before the normal tag.  If
# the .CLEAR version of the tag doesn't exist, we do not change the tag
# name but we give a warning.

sub _clear {

   my ($self) = @_;;

   my $clearToken    = $self->tag . ':.CLEAR';
   my $clearAllToken = $self->tag . ':.CLEARALL';

   if (isValidTag($self->lineType, $clearAllToken)) {

      # Don't do the else clause at the bottom

   } elsif ( ! isValidTag($self->lineType, $clearToken )) {

      getLogger()->notice(
         q{The tag "} . $clearToken . q{" from "} . $self->origToken . 
         q{" is not in the } . $self->lineType . q{ tag list\n},
         $self->file,
         $self->line
      );

      incCountInvalidTags($self->lineType, $clearToken);
      $self->noMoreErrors(1);

   } else {

      # Its a valid CLEAR tag, move the subToken to tag
      $self->tag($clearToken);
      $self->value($self->value =~ s/^.CLEAR//ir);

   }
}


# Extract the defined name and any variables used to define it, queue them up
# for cross checking.

sub _define {

   my ($self) = @_;
   my $log = getLogger();

   my ( $var_name, @formulae ) = split '\|', $self->value;

   # First we store the DEFINE variable name
   if ($var_name) {
      if ( $var_name =~ /^[a-z][a-z0-9_]*$/i ) {
         setEntityValid('DEFINE Variable', $var_name);

         #####################################################
         # Export a list of variable names if requested
         if ( isConversionActive('Export lists') ) {
            my $file = $self->file;
            $file =~ tr{/}{\\};
            LstTidy::Report::printToExportList('VARIABLE', qq{"$var_name","$self->line","$file"\n});
         }

         # LOCK.xxx and BASE.xxx are not error (even if they are very ugly)
      } elsif ( $var_name !~ /(BASE|LOCK)\.(STR|DEX|CON|INT|WIS|CHA|DVR)/ ) {
         $log->notice(
            qq{Invalid variable name "$var_name" in "} . $self->fullToken . q{"},
            $self->file,
            $self->line
         );
      }

   } else {
      $log->notice(
         qq{I was not able to find a proper variable name in "} . $self->fullToken . q{"},
         $self->file,
         $self->line
      );
   }

   # Second we deal with the formula
   for my $formula (@formulae) {
      registerXCheck(
         'DEFINE Variable', 
         qq{@@" in "} . $self->fullToken, 
         $self->file, 
         $self->line, 
         $self->_variables($formula) );
   }
}


# Queue up Deity tags for cross checking

sub _deity {

   my ($self) = @_;

   # DEITY:<deity name>|<deity name>|etc.
   registerXCheck( 
      'DEITY', 
      $self->tag, 
      $self->file, 
      $self->line, 
      (split /[|]/, $self->value),);
}


# Queue up Domain tags for cross checking

sub _domain {

   my ($self) = @_;

   # DOMAIN:<domain name>|<domain name>|etc.
   registerXCheck(
      'DOMAIN', 
      $self->tag, 
      $self->file, 
      $self->line, 
      (split /[|]/, $self->value), );
}


# Validate the CLASSES tag, it can appear on either DEITY or SPELL lines

sub _domains {

   my ($self) = @_;


   if ($self->lineType eq 'DEITY') {

      _domainsOnDeity($self);

   } elsif ( $self->lineType eq 'SPELL' ) {

      _domainsOnSpell($self);

   } 
}


# Validate DOMAINS tags that appear on DEITY lines

sub _domainsOnDeity {

   my ($self) = @_;


   # Only DOMAINS in DEITY
   if ($self->value =~ /\|/ ) {
      my $value = substr($self->value, 0, rindex($self->value, "\|"));
      $self->value($value);
   }

   DOMAIN_FOR_DEITY:
   for my $domain ( split ',', $self->value ) {

      # ALL is valid here
      next DOMAIN_FOR_DEITY if $domain eq 'ALL';

      registerXCheck(
         'DOMAIN', 
         $self->tag, 
         $self->file, 
         $self->line, 
         $domain );
   }
}
                


# Validate DOMAINS tags that appear on SPELL lines

sub _domainsOnSpell {

   my ($self) = @_;

   my %seen;
   my $log = getLogger();

   # First we find all the classes used
   for my $level ( split '\|', $self->value ) {
      if ( $level =~ /(.*)=(\d+)/ ) {
         for my $entity ( split ',', $1 ) {

            # [ 849365 ] CLASSES:ALL
            # CLASSES:ALL is OK
            # Arcane and Divine are not really OK but they are used
            # as placeholders for use in the MSRD.

            registerXCheck(
               'DOMAIN', 
               $self->tag, 
               $self->file, 
               $self->line, 
               $entity );

            if ( $seen{$entity}++ ) {
               $log->notice(
                  qq{"$entity" found more than once in } . $self->tag,
                  $self->file,
                  $self->line
               );
            }
         }

      } else {
         $log->warning(
            qq{Missing "=level" after "} . $self->tag . ":$level",
            $self->file,
            $self->line
         );
      }
   }
}


# Find CASTERLEVEL where it appears embeded between () on SPELL linesi,
# extract any variables used for cross checking.

sub _embededCasterLevel {

   my ($self) = @_;

   # Inline f*#king tags.
   # We need to find CASTERLEVEL between ()
   my $value = $self->value;
   pos $value = 0;

   FIND_BRACKETS:
   while ( pos $value < length $value ) {

      my $result;

      # Find the first set of ()
      if ( (($result) = Text::Balanced::extract_bracketed( $value, '()' )) && $result) {

         # Is there a CASTERLEVEL inside?
         if ( $result =~ / CASTERLEVEL /xmsi ) {
            registerXCheck(
               'DEFINE Variable', 
               qq{@@" in "} . $self->fullToken,
               $self->file,
               $self->line,
               $self->_variables($result) );
         }

      } else {

         last FIND_BRACKETS;
      }
   }
}



# Split a list using the comma, ( or supplied separator) but part of the list
# may be between brackets and the comma must be ignored there.
# 
# Parameter: $list      List that need to be split
#            $separator optional expression used for the split, ',' is the default.

sub embedded_coma_split {

   # The list may contain other lists inside brackets.
   # Change all the , within brackets before doing our split.
   my ( $list, $separator ) = ( @_, ',' );

   return () unless $list;

   my $newlist;
   my @result;

   BRACE_LIST:
   while ($list) {

      # We find the next text within ()
      @result = Text::Balanced::extract_bracketed( $list, '()', qr([^()]*) );

      # If we didn't find any (), it's over
      if ( !$result[0] ) {
         $newlist .= $list;
         last BRACE_LIST;
      }

      # The prefix is added to $newlist
      $newlist .= $result[2];

      # We replace every , with &comma;
      $result[0] =~ s/,/&coma;/xmsg;

      # We add the bracket section
      $newlist .= $result[0];

      # We start again with what's left
      $list = $result[1];
   }

   # Now we can split
   return map { s/&coma;/,/xmsg; $_ } split $separator, $newlist;
}



# Extract any PREXXXs statements in the feat tags and vlaidate them.
# 
# Modify the list to remove the PREXXX statements, leaving only FEATS.

sub _embededPre {

   my ($self, $feats) = @_;

   FEAT:
   for my $feat (@{ $feats }) {

      # If it is a PRExxx tag section, we validate the PRExxx tag.
      if ( $self->tag eq 'VFEAT' && $feat =~ /^(!?PRE[A-Z]+):(.*)/ ) {

         my $preToken = $self->clone(tag => $1, value => $2);
         $preToken->_preToken($self->fullRealToken);

         $feat = "";
         next FEAT;
      }

      # We strip the embeded [PRExxx ...] tags
      if ( $feat =~ /([^[]+)\[(!?PRE[A-Z]*):(.*)\]$/ ) {

         $feat = $1;

         my $preToken = $self->clone(tag => $2, value => $3);
         $preToken->_preToken($self->fullRealToken);
      }

   }

   # Remove the empty strings
   return grep {$_ ne ""} @{ $feats };
}



# Queue up EQUIPMOD key for cross checking

sub _eqmod {

   my ($self) = @_;

   # The higher level for the EQMOD is the . (who's the genius who
   # dreamed that up...
   my @key_list = split '\.', $self->value;

   # The key name is everything found before the first |
   for $_ (@key_list) {
      my ($key) = (/^([^|]*)/);

      if ($key) {

         # To be processed later
         registerXCheck(
            'EQUIPMOD Key', 
            qq{@@" in "} . $self->fullToken, 
            $self->file, 
            $self->line, 
            $key );

      } else {

         getLogger()->warning(
            qq{Cannot find the key for "$_" in "} . $self->fullToken . q{"},
            $self->file,
            $self->line
         );
      }
   }
}


# Extract the list of feats and split into individual entries.

sub _extractFeatList {

   my ($self) = @_;
   
   my @feats;
   my $parent = 0;

   if ( $self->tag eq 'ADD:FEAT' ) {

      if ( $self->value =~ /^\((.*)\)(.*)?$/ ) {
         $parent = 1;
         my $formula = $2;

         # The ADD:FEAT list may contains list elements that
         # have () and will need the special split.
         # The LIST special feat name is valid in ADD:FEAT
         # So is ALL now.
         @feats = grep { $_ ne 'LIST' } grep { $_ ne 'ALL' } embedded_coma_split($1);

         # Here we deal with the formula part
         if ($formula) {
            registerXCheck(
               'DEFINE Variable', 
               qq{@@" in "} . $self->fullToken, 
               $self->file, 
               $self->line, 
               $self->_variables($formula))
         }

      } elsif ($self->value) {
         getLogger()->notice(
            qq{Invalid syntax: "} . $self->fullToken . q{"},
            $self->file,
            $self->line
         ) 
      }

   } elsif ( $self->tag eq 'FEAT' ) {

      # FEAT tags sometime use , and sometime use | as separator.

      # We can now safely split on the ,
      @feats = embedded_coma_split( $self->value, qr{,|\|} );

   } else {
      @feats = split '\|', $self->value;
   }

   return \@feats, $parent;
}


# Extract the list of Feats, check any PRE statements and then queue up for
# cross processing.

sub _feats {

   my ($self) = @_;

   # ADD:FEAT(feat,feat,TYPE=type)formula
   # FEAT:feat|feat|feat(xxx)
   # FEAT:feat,feat,feat(xxx)  in the TEMPLATE and DOMAIN
   # FEATAUTO:feat|feat|...
   # VFEAT:feat|feat|feat(xxx)|PRExxx:yyy
   # MFEAT:feat|feat|feat(xxx)|...
   # All these type may have embeded [PRExxx tags]

   my ($feats, $parent) = _extractFeatList($self);

   my @feats = _embededPre($self, $feats);

   # To be processed later
   registerXCheck(
      'FEAT', 
      $parent ? $self->tag . "(@@)" : $self->tag, 
      $self->file, 
      $self->line, 
      @feats );
}



# Process a PRE tag which doesn't need any additional checks.

sub _genericPRE {

   my ($self, $preType, $enclosingToken) = @_;

   my ($valid, @values) = $self->_checkFirstValue;

   # The PREtag doesn't begin with a number
   if ( not $valid ) {
      $self->_warnDeprecate($enclosingToken);
   }

   registerXCheck(
      $preType, 
      $self->tag, 
      $self->file, 
      $self->line, 
      @values);
}


# This is part of EQUIPMED processing, queue up for cross checking

sub _ignores {

   my ($self) = @_;


   # Comma separated list of KEYs
   # To be processed later
   registerXCheck(
      'EQUIPMOD Key', 
      qq{@@" in "} . $self->fullToken, 
      $self->file, 
      $self->line, 
      split ',', $self->value );
}


# After modifying the tag to account for sub tags, it is still invalid, check
# if it might be a valid ADD tag, if not log it (if allowed) and count it.

sub _invalid {

   my ($token) = @_;

   my $invalidTag = 1;

   # See if it might be a valid ADD tag.
   if ($token->fullToken =~ /^ADD:([^\(\|]+)[\|\(]+/) {
      my $subTag = ($1);
      if (isValidTag($token->lineType, "ADD:$subTag")) {
         $invalidTag = 0;
      }
   }

   if ($invalidTag && !$token->noMoreErrors) {

      getLogger()->notice(
         qq{The tag "} . $token->tag . q{" from "} . $token->origToken 
         . q{" is not in the } . $token->lineType . q{ tag list\n},
         $token->file,
         $token->line
      );

      # If no more errors is set, we have already counted the invalid tag.
      incCountInvalidTags($token->lineType, $token->realTag);
   }
}


# Split the list of kits and queue them up for cross checking.

sub _kit {

   my ($self) = @_;

   # KIT:<number of choice>|<kit name>|<kit name>|etc.
   # KIT:<kit name>
   my @kit_list = split /[|]/, $self->value;

   # The first item might be a number
   if ( $kit_list[0] =~ / \A \d+ \z /xms ) {
      # We discard the number
      shift @kit_list;
   }

   registerXCheck(
      'KIT STARTPACK', 
      $self->tag, 
      $self->file, 
      $self->line, 
      @kit_list, );
}


# Validate the Kit:Spells lines. check the systax is as expected and queue up
# the data for cross checking.

sub _kitSpells {

   my ($self) = @_;

   # KIT SPELLS line type
   # SPELLS:<parameter list>|<spell list>
   # <parameter list> = <param tag> = <param value { | <parameter list> }
   # <spell list> := <spell name> { = <number> } { | <spell list> }
   my @spells = ();

   for my $spell_or_param (split q{\|}, $self->value) {
      # Is it a parameter?
      if ( $spell_or_param =~ / \A ([^=]*) = (.*) \z/xms ) {
         my ($param_id,$param_value) = ($1,$2);

         if ( $param_id eq 'CLASS' ) {
            registerXCheck(
               'CLASS',
               qq{@@" in "} . $self->fullToken, 
               $self->file, 
               $self->line, 
               $param_value, );

         } elsif ( $param_id eq 'SPELLBOOK') {

            # Nothing to do
            #
         } elsif ( $param_value =~ / \A \d+ \z/mxs ) {

            # It's a spell after all...
            push @spells, $param_id;

         } else {
            getLogger()->notice(
               qq{Invalide SPELLS parameter: "$spell_or_param" found in "} . $self->fullToken . q{"},
               $self->file,
               $self->line
            );
         }

      } else {
         # It's a spell
         push @spells, $spell_or_param;
      }
   }

   if ( scalar @spells ) {
      registerXCheck(
         'SPELL',
         $self->tag,
         $self->file,
         $self->line,
         @spells, );
   }
}


# Split the value annd queue for cross checking later.

sub _language {

   my ($self) = @_;

   # To be processed later
   # The ALL keyword is removed here since it is not usable everywhere there are language
   # used.
   registerXCheck(
      'LANGUAGE', 
      $self->tag, 
      $self->file, 
      $self->line, 
      grep { $_ ne 'ALL' } split ',', $self->value );
}


# Certain tokens can only have a specific set of fixed values. This operation is
# used to ensure their values are in the valid set.
#
# ALIGN and PREALIGN can both take multiples of a specific set of tokens, they
# are handled separately.

sub _limited {

   my ($self) = @_;

   # Special treament for the ALIGN and PREALIGN tokens
   if ($self->tag eq 'ALIGN' || $self->tag eq 'PREALIGN') {

      $self->_limitedAlign();

   } else {

      $self->_limitedNonAlign();
   }
}


# It is possible for the ALIGN and PREALIGN tags to have more then one value,
# make sure they are all valid. Convert them from number to text if necessary.

sub _limitedAlign {

   my ($self) = @_;

   my $log = getLogger();
      
   # Most of the limited values are uppercase except TIMEUNITS and the alignment value 'Deity'
   my $newvalue = $self->value;
      
   my $is_valid = 1;

   # ALIGN uses | for separator, PREALIGN uses ,
   my $splitPatern = $self->tag eq 'PREALIGN' ? qr{[,]}xms : qr{[|]}xms;

   for my $value (split $splitPatern, $newvalue) {

      my $align = mungKey($self->tag , $value);

      # Is it a number?
      my ($number) = $align =~ / \A (\d+) \z /xms;

      if ( defined $number && $number >= 0 && $number < scalar @{getValidSystemArr('alignments')}) {
         $align = ${getValidSystemArr('alignments')}[$number];
         $newvalue =~ s{ (?<! \d ) ($number) (?! \d ) }{$align}xms;
      }

      # Is it not a valid alignment?
      if (!isValidFixedValue($self->tag, $align)) {
         $log->notice(
            qq{Invalid alignment "$align" for tag "} . $self->realTag . q{"},
            $self->file,
            $self->line
         );
         $is_valid = 0;
      }
   }

   # Was the tag changed ?
   if ( $is_valid && $self->value ne $newvalue) {

      $self->value($newvalue);

      $log->warning(
         qq{Replaced "} . $self->origToken . q{" with "} . $self->fullRealToken . qq{"},
         $self->file,
         $self->line
      );
   }
}


# Any tag that has limited values but is not an ALIGN or PREALIGN can only
# have one value.  The value should be uppercase, Check for validity and if
# necessary change the value.

sub _limitedNonAlign {

   my ($self) = @_;

   my $log = getLogger();

   # Convert the key if possible to make the lookup work
   my $value = mungKey($self->tag, $self->value);

   # Warn if it's not a proper value
   if ( !isValidFixedValue($self->tag, $value) ) {

      $log->notice(
         qq{Invalid value "} . $self->value . q{" for tag "} . $self->realTag . q{"},
         $self->file,
         $self->line
      );

   # If we had to modify the lookup, change the data
   } elsif ($self->value ne $value) {

      $self->value = $value;

      $log->warning(
         qq{Replaced "} . $self->origToken . q{" by "} . $self->fullRealToken . qq{"},
         $self->file,
         $self->line
      );
   }
}


# log a warning for no value in token

sub _missingValue {

   my ($self, $enclosingToken) = @_;
   
   my $log = getLogger();

   my $message = q{Check for missing ":", no value for "} . $self->tag . q{"};

   if ($enclosingToken) {
      $message .= qq{ found in "$enclosingToken"} 
   }

   $log->warning($message, $self->file, $self->line);
}


# Check that the value is alternating movetype value

sub _move {

   my ($self) = @_;

   my $log = getLogger();

   # MOVE:<move type>,<value>
   # ex. MOVE:Walk,30,Fly,20,Climb,10,Swim,10

   my @list = split ',', $self->value;

   MOVE_PAIR:
   while (@list) {
      my ( $type, $value ) = ( splice @list, 0, 2 );
      $value = "" if !defined $value;

      # $type should be a word and $value should be a number
      if ( $type =~ /^\d+$/ ) {
         $log->notice(
            qq{I was expecting a move type where I found "$type" in "} . $self->fullToken . q{"},
            $self->file,
            $self->line
         );
         last;
      }
      else {

         # We keep the move type for future validation
         setEntityValid('MOVE Type', $type);
      }

      unless ( $value =~ /^\d+$/ ) {
         $log->notice(
            qq{Expecting a number after "$type", but found "$value" in "} . $self->fullToken . q{"},
            $self->file,
            $self->line
         );
         last MOVE_PAIR;
      }
   }
}


# Validate that the first two parameters of MOVECLONE are valid move types.

sub _moveClone {

   my ($self) = @_;

   # MOVECLONE:A,B,formula  A and B must be valid move types.
   if ( $self->value =~ /^(.*),(.*),(.*)/ ) {
      # Error if more parameters (Which will show in the first group)
      if ( $1 =~ /,/ ) {
         getLogger()->warning(
            qq{Found too many parameters in "} . $self->fullToken . q{"},
            $self->file,
            $self->line
         );

      } else {

         # Cross check for used MOVE Types.
         registerXCheck(
            'MOVE Type',
            $self->tag,
            $self->file,
            $self->line, 
            $1, $2 );
      }

   } else {

      # Report missing requisite parameters.
      getLogger()->warning(
         qq{Missing a parameter in in "} . $self->fullToken . q{"},
         $self->file,
         $self->line
      );
   }
}


# Extract the data from Natural Attacks tags, validate it and queue the
# equipement types for cross checking.

sub _naturalAttacks {

   my ($self) = @_;

   my $log = getLogger();

   # NATURALATTACKS:<Natural weapon name>,<List of type>,<attacks>,<damage>|...
   #
   # We must make sure that there are always either four or five , separated
   # parameters between the |.

   for my $entry ( split '\|', $self->value ) {
      my @parameters = split ',', $entry;

      my $NumberOfParams = scalar @parameters;

      # must have 4 or 5 parameters
      if ($NumberOfParams == 5 or $NumberOfParams == 4) {

         # If Parameter 5 exists, it must be an SPROP
         if (defined $parameters[4]) {
            $log->notice(
               qq{5th parameter should be an SPROP in "NATURALATTACKS:$entry"},
               $self->file,
               $self->line
            ) unless $parameters[4] =~ /^SPROP=/;
         }

         # Parameter 3 is a number
         $log->notice(
            qq{3rd parameter should be a number in "NATURALATTACKS:$entry"},
            $self->file,
            $self->line
         ) unless $parameters[2] =~ /^\*?\d+$/;

         # Are the types valid EQUIPMENT types?
         registerXCheck(
            'EQUIPMENT TYPE', 
            qq{@@" in "} . $self->tag . q{:$entry}, 
            $self->file,
            $self->line, 
            grep { !$validNaturalAttacksType{$_} } split '\.', $parameters[1] );

      } else {

         $log->notice(
            qq{Wrong number of parameter for "NATURALATTACKS:$entry"},
            $self->file,
            $self->line
         );
      }
   }
}


# Extract and check the values in SPELLS tags, queue up for cross checking.

sub _nonKitSpells {

   my ($self) = @_;
   my $log = getLogger();

   # Syntax: SPELLS:<spellbook>|[TIMES=<times per day>|][TIMEUNIT=<unit of time>|][CASTERLEVEL=<CL>|]<Spell list>[|<prexxx tags>]
   # <Spell list> = <Spell name>,<DC> [|<Spell list>]
   my @list_of_param = split '\|', $self->value;
   my @spells;

   # We drop the Spell book name
   shift @list_of_param;

   my $nb_times            = 0;
   my $nb_timeunit         = 0;
   my $nb_casterlevel      = 0;
   my $AtWill_Flag         = 0;

   for my $param (@list_of_param) {

      if ( $param =~ /^(TIMES)=(.*)/ || $param =~ /^(TIMEUNIT)=(.*)/ || $param =~ /^(CASTERLEVEL)=(.*)/ ) {

         if ( $1 eq 'TIMES' ) {

            $AtWill_Flag = $param =~ /TIMES=ATWILL/;
            $nb_times++;
            registerXCheck(
               'DEFINE Variable',
               qq{@@" in "} . $self->fullToken,
               $self->file,
               $self->line,
               $self->_variables($2) );

         } elsif ( $1 eq 'TIMEUNIT' ) {

            my $key = mungKey($1, $2);

            $nb_timeunit++;
            # Is it a valid alignment?
            if (! isValidFixedValue($1, $key)) {
               $log->notice(
                  qq{Invalid value "$key" for tag "$1"},
                  $self->file,
                  $self->line
               );
            }

         } else {

            $nb_casterlevel++;
            registerXCheck(
               'DEFINE Variable', 
               qq{@@" in "} . $self->fullToken, 
               $self->file, 
               $self->line, 
               $self->_variables($2) );
         }

         # Embeded PRExxx tags
      } elsif ( $param =~ /^(PRE[A-Z]+):(.*)/ ) {

         my $preToken = $self->clone(tag => $1, value => $2);
         $preToken->_preToken($self->fullRealToken);

      } else {

         my ( $spellname, $dc ) = ( $param =~ /([^,]+),(.*)/ );

         if ($dc) {

            # Spell name must be validated with the list of spells and DC is a formula
            push @spells, $spellname;

            registerXCheck(
               'DEFINE Variable', 
               qq{@@" in "} . $self->fullToken, 
               $self->file, 
               $self->line, 
               $self->_variables($dc) );

         } else {

            # No DC present, the whole param is the spell name
            push @spells, $param;

            $log->info(
               qq{the DC value is missing for "$param" in "} . $self->fullToken . q{"},
               $self->file,
               $self->line
            );
         }
      }
   }

   registerXCheck(
      'SPELL', 
      $self->tag,
      $self->file,
      $self->line,
      @spells );

   # Validate the number of TIMES, TIMEUNIT, and CASTERLEVEL parameters
   if ( $nb_times != 1 ) {
      if ($nb_times) {
         $log->notice(
            qq{TIMES= should not be used more then once in "} . $self->fullToken . q{"},
            $self->file,
            $self->line
         );

      } else {

         $log->info(
            qq{the TIMES= parameter is missing in "} . $self->fullToken . q{"},
            $self->file,
            $self->line
         );
      }
   }

   if ( $nb_timeunit != 1 ) {
      if ($nb_timeunit) {
         $log->notice(
            qq{TIMEUNIT= should not be used more then once in "} . $self->fullToken . q{"},
            $self->file,
            $self->line
         );

      } else {

         if ( $AtWill_Flag ) {
            # Do not need a TIMEUNIT tag if the TIMES tag equals AtWill
            # Nothing to see here. Move along.
         } else {
            # [ 1997408 ] False positive: TIMEUNIT= parameter is missing
            # $log->info(
            #       qq{the TIMEUNIT= parameter is missing in "} . $self->fullToken . q{"},
            #       $self->file,
            #       $self->line
            # );
         }
      }
   }

   if ( $nb_casterlevel != 1 ) {
      if ($nb_casterlevel) {
         $log->notice(
            qq{CASTERLEVEL= should not be used more then once in "} . $self->fullToken . q{"},
            $self->file,
            $self->line
         );

      } else {

         $log->info(
            qq{the CASTERLEVEL= parameter is missing in "} . $self->fullToken . q{"},
            $self->file,
            $self->line
         );
      }
   }
}


# Certain tags only have numeric values, extract any variables and queue for
# cross checking.

sub _numeric {

   my ($self) = @_;

   # These tags should only have a numeribal value
   registerXCheck(
      'DEFINE Variable',
      qq{@@" in "} . $self->fullToken,
      $self->file,
      $self->line,
      $self->_variables($self->value) );
}



# Ensures that a PRECHECK token's value start with a number.
# and that it references valid checks.

sub _precheck {

   my ($self, $enclosingToken) = @_;

   # PRECHECK:<number>,<check equal value list>
   # PRECHECKBASE:<number>,<check equal value list>
   # <check equal value list> := <check name> "=" <number>
   my ($valid, @values) = $self->_checkFirstValue;

   # The PREtag doesn't begin with a number
   if ( not $valid ) {
      $self->_warnDeprecate($enclosingToken);
   }

   # Get the logger once outside the loop
   my $log = getLogger();

   for my $item ( @values ) {

      # Extract the check name
      if ( my ($checkName, $value) = ( $item =~ / \A ( \w+ ) = ( \d+ ) \z /xms ) ) {

         # If we don't recognise it.
         if ( ! isValidCheck($checkName) ) {
            $log->notice(
               qq{Invalid save check name "$checkName" found in "} . $self->fullRealValue . q{"},
               $self->file,
               $self->line
            );
         }
      } else {
         $log->notice(
            $self->tag . qq{ syntax error in "$item" found in "} . $self->fullRealValue . q{"},
            $self->file,
            $self->line
         );
      }
   }
}




# Queue up for Cross check.

sub _predeity {

   my ($self) = @_;

   # PREDEITY:Y
   # PREDEITY:YES
   # PREDEITY:N
   # PREDEITY:NO
   # PREDEITY:1,<deity name>,<deity name>,etc.

   if ( $self->value !~ / \A (?: Y(?:ES)? | N[O]? ) \z /xms ) {
      #We ignore the single yes or no
      registerXCheck(
         'DEITY',
         $self->tag,
         $self->file,
         $self->line, 
         (split /[,]/, $self->value)[1,-1],);
   }
};



# Check for deprecated syntax and queue up for cross check.

sub _prelang {

   my ($self, $enclosingToken) = @_;

   # PRELANG:number,language,language,TYPE=type
   my ($valid, @values) = $self->_checkFirstValue;

   # The PREtag doesn't begin with a number
   if ( not $valid ) {
      $self->_warnDeprecate($enclosingToken);
   }

   registerXCheck(
      'LANGUAGE', 
      $self->tag, 
      $self->file, 
      $self->line, 
      grep { $_ ne 'ANY' } @values);
}



# Check for deprecated syntax and queue up for cross check.

sub _premove {

   my ($self, $enclosingToken) = @_;

   # PREMOVE:[<number>,]<move>=<number>,<move>=<number>,...
   my ($valid, @values) = $self->_checkFirstValue;

   # The PREtag doesn't begin with a number
   if ( not $valid ) {
      $self->_warnDeprecate($enclosingToken);
   }

   for my $move (@values) {

      # Verify that the =<number> is there
      if ( $move =~ /^([^=]*)=([^=]*)$/ ) {

         registerXCheck(
            'MOVE Type',
            $self->tag,
            $self->file,
            $self->line,
            $1);

         # The value should be a number
         my $value = $2;

         if ($value !~ /^\d+$/ ) {
            my $message = qq{Not a number after the = for "$move" in "} 
               . $self->fullRealToken . q{"};
            $message .= qq{ found in "$enclosingToken"} if $enclosingToken;

            getLogger()->notice($message, $self->file, $self->line);
         }

      } else {

         my $message = qq{Invalid "$move" in "} . $self->fullRealToken . q{"};
         $message .= qq{ found in "$enclosingToken"} if $enclosingToken;

         getLogger()->notice($message, $self->file, $self->line);

      }
   }
}




# split and check the PREMULT tags
#
# Each PREMULT tag has two or more embedded PRE tags, which are individually
# checked using validatePreToken.

sub _premult {

   my ($self, $enclosingToken) = @_;

   my $workingValue = $self->value;
   my $inside;

   # We add only one level of PREMULT to the error message.
   my $newEncToken;
   if ($enclosingToken) {

      $newEncToken = $enclosingToken;
      $newEncToken .= ':PREMULT' unless $newEncToken =~ /PREMULT$/;

   } else {

      $newEncToken .= 'PREMULT';
   }

   FIND_BRACE:
   while ($workingValue) {

      ( $inside, $workingValue ) = 
         Text::Balanced::extract_bracketed( $workingValue, '[]', qr{[^[]*} );

      last FIND_BRACE if !$inside;

      # We extract what we need
      if ( $inside =~ /^\[(!?PRE[A-Z]+):(.*)\]$/ ) {

         my $preToken = $self->clone(tag => $1, value => $2);

         $preToken->_preToken($newEncToken);

      } else {

         # No PRExxx tag found inside the PREMULT
         getLogger()->warning(
            qq{No valid PRExxx tag found in "$inside" inside "PREMULT:} . $self->value . q{"},
            $self->file,
            $self->line
         );
      }
   }
}




# Check for deprecated syntax and queue up for cross check.

sub _prerace {

   my ($self, $enclosingToken) = @_;

   # We get the list of races
   my ($valid, @values) = $self->_checkFirstValue;

   # The PREtag doesn't begin with a number
   if ( not $valid ) {
      $self->_warnDeprecate($enclosingToken);
   }

   my ( @races, @races_wild );

   for my $race (@values) {

      if ( $race =~ / (.*?) [%] (.*?) /xms ) {
         # Special case for PRERACE:xxx%
         my $race_wild  = $1;
         my $after_wild = $2;

         push @races_wild, $race_wild;

         if ( $after_wild ne q{} ) {

            getLogger()->notice(
               qq{% used in wild card context should end the race name in "$race"},
               $self->file,
               $self->line
            );

         } else {

            # Don't bother warning if it matches everything.
            # For now, we warn and do nothing else.
            if ($race_wild eq '') {

               ## Matches everything, no reason to warn.

            } elsif (isValidEntity('RACE', $race_wild)) {

               ## Matches an existing race, no reason to warn.

            } elsif ($racePartialMatch{$race_wild}) {

               ## Partial match already confirmed, no need to confirm.
               #
            } else {

               my $found = searchRace($race_wild) ;

               if ($found) {
                  $racePartialMatch{$race_wild} = 1;
               } else {

                  getLogger()->info(
                     qq{Not able to validate "$race" in "PRERACE:} 
                     . $self->value. q{." This warning is order dependent.}
                     . q{ If the race is defined in a later file, }
                     . q{this warning may not be accurate.},
                     $self->file,
                     $self->line
                  )
               }
            }
         }
      } else {
         push @races, $race;
      }
   }

   registerXCheck(
      'RACE',
      $self->tag,
      $self->file,
      $self->line,
      @races);
}



# Check for deprecated syntax and queue up for cross check.

sub _prespell {

   my ($self, $enclosingToken) = @_;

   # We get the list of skills and skill types
   my ($valid, @values) = $self->_checkFirstValue;

   # The PREtag doesn't begin with a number
   if ( not $valid ) {
      $self->_warnDeprecate($enclosingToken);
   }

   registerXCheck(
      'SPELL', 
      $self->tag . ":@@", 
      $self->file, 
      $self->line, 
      @values);
}


# Validate the PRExxx tags. This function is reentrant and can be called
# recursivly.
#
# $enclosingToken,  # When the PRExxx tag is used in another tag
#
# preforms checks that pre tags are valid.

sub _preToken {

   my ($self, $enclosingToken) = @_;

   if ( !length($self->value) && $self->tag ne "PRE:.CLEAR" ) {
      $self->_missingValue($enclosingToken);
      return;
   }

   getLogger()->debug(
      q{PREToken: } 
         . $self->tag . q{; } 
         . $self->value . q{; } 
         . $enclosingToken . q{; } 
         . $self->lineType . q{;},
      $self->file,
      $self->line
   );

   if ( $self->tag eq 'PRECLASS' || $self->tag eq 'PRECLASSLEVELMAX' ) {

      $self->_genericPRE('CLASS', $enclosingToken);

   } elsif ( $self->tag eq 'PRECHECK' || $self->tag eq 'PRECHECKBASE') {

      $self->_precheck($enclosingToken);

   } elsif ( $self->tag eq 'PRECSKILL' ) {

      $self->_genericPRE('SKILL', $enclosingToken);

   } elsif ( $self->tag eq 'PREDEITY' ) {

      $self->_predeity();

   } elsif ( $self->tag eq 'PREDEITYDOMAIN' || $self->tag eq 'PREDOMAIN' ) {

      $self->_genericPRE('DOMAIN', $enclosingToken);

   } elsif ( $self->tag eq 'PREFEAT' ) {

      $self->_genericPRE('FEAT', $enclosingToken);

   } elsif ( $self->tag eq 'PREABILITY' ) {

      $self->_genericPRE('ABILITY', $enclosingToken);

   } elsif ( $self->tag eq 'PREITEM' ) {

      $self->_genericPRE('EQUIPMENT', $enclosingToken);

   } elsif ( $self->tag eq 'PRELANG' ) {

      $self->_prelang($enclosingToken);

   } elsif ( $self->tag eq 'PREMOVE' ) {

      $self->_premove($enclosingToken);

   } elsif ( $self->tag eq 'PREMULT' ) {

      # This tag is the reason why _preToken exists
      # PREMULT:x,[PRExxx 1],[PRExxx 2]
      # We need for find all the [] and call _preToken with the content

      $self->_premult($enclosingToken);

   } elsif ( $self->tag eq 'PRERACE' ) {

      $self->_prerace($enclosingToken);

   }
   elsif ( $self->tag eq 'PRESKILL' ) {

      $self->_genericPRE('SKILL', $enclosingToken);

   } elsif ( $self->tag eq 'PRESPELL' ) {

      $self->_prespell($self, $enclosingToken);

   } elsif ( $self->tag eq 'PREVAR' ) {

      $self->_prevar($self, $enclosingToken);

   }

   # No Check for Variable File #

   # Check for PRExxx that do not exist. We only check the
   # tags that are embeded since parse_tag already took care
   # of the PRExxx tags on the entry lines.
   elsif ( $enclosingToken && ! isValidPreTag($self->tag) ) {

      getLogger()->notice(
         qq{Unknown PRExxx tag "} . $self->tag . q{" found in "$enclosingToken"},
         $self->file,
         $self->line
      );
   }
}


# Queue up the embeded variables for cross checking.

sub _prevar {

   my ($self, $enclosingToken) = @_;

   my ($varName, @formulae) = split ',', $self->value;

   registerXCheck(
      'DEFINE Variable', 
      qq{@@" in "} . $self->fullRealToken, 
      $self->file, 
      $self->line, 
      $varName,);

   for my $formula (@formulae) {
      my @values = $self->_variables($formula);
      registerXCheck(
         'DEFINE Variable', 
         qq{@@" in "} . $self->fullRealToken, 
         $self->file, 
         $self->line, 
         @values);
   }
}


# Parse the sub set of tokens where data can freely define sub tokens.  Such
# as FACT or QUALITY.

# Some of these are standard and become tags with embeded colons (Similar to
# ADD). Others are accepted as valid as is, no token munging is done.

sub _protean {

   my ($self) = @_;

   my $log = getLogger();

   # If this is s a subTag, the subTag is currently on the front of the value.
   my ($subTag) = ($self->value =~ /^([^=:|]+)/ );

   my $potentialTag = $self->tag . ':' . $subTag;

   if ($subTag && exists $validSubTags{$self->tag}{$subTag}) {

      $self->tag($potentialTag);
      $self->value($self->value =~ s/^$subTag(.*)/$1/r);

   } elsif ($subTag) {
     
      # Give a really low priority note that we saw this. Mostly we don't care,
      # the data team can freely define these and they don't want to hear that
      # they've done that.
      $log->info(
         qq{Non-standard } . $self->tag . qq{ tag $potentialTag in "} 
         . $self->origToken . q{" found in } . $self->lineType,
         $self->file,
         $self->line
      );

   } else {

      incCountInvalidTags($self->lineType, $self->tag);
      $log->notice(
         q{Invalid } . $self->tag . q{ tag "} . $self->origToken 
         . q{" found in } . $self->lineType,
         $self->file,
         $self->line
      );
      $self->noMoreErrors(1);
   }
}


# Queue up the Race for cross checking

sub _race {

   my ($self) = @_;

   # There is only one race per RACE tag
   registerXCheck(
      'RACE',
      $self->tag,
      $self->file,
      $self->line,
      $self->value, );
}


# Extract the Race sub-types and queue them up for cross checking.

sub _raceSubType {

   my ($self) = @_;

   for my $race_subtype (split /[|]/, $self->value) {

      my $new_race_subtype = $race_subtype;

      if ( $self->lineType eq 'RACE' ) {

         # The RACE sub-types are created in the RACE file
         if ( $race_subtype =~ m{ \A [.] REMOVE [.] }xmsi ) {

            # The presence of a remove means that we are trying
            # to modify existing data, not create new sub-types

            registerXCheck(
               'RACESUBTYPE', 
               $self->tag, 
               $self->file,
               $self->line,
               $race_subtype, );

         } else {

            setEntityValid('RACESUBTYPE', $race_subtype);
         }

      } else {

         # The RACE type found here are not creates, we only get rid of the
         # .REMOVE. part

         $race_subtype =~ m{ \A [.] REMOVE [.] }xmsi;

         registerXCheck(
            'RACESUBTYPE',
            $self->tag,
            $self->file,
            $self->line,
            $race_subtype, );
      }
   }
}


# Extract the Race Types and queue them up for cross checking.

sub _raceType {

   my ($self) = @_;

   for my $race_type (split /[|]/, $self->value) {

      if ( $self->lineType eq 'RACE' ) {

         # The RACE type are created in the RACE file
         if ( $race_type =~ m{ \A [.] REMOVE [.] }xmsi ) {

            # The presence of a remove means that we are trying
            # to modify existing data and not create new one
            registerXCheck(
               'RACETYPE', 
               $self->tag, 
               $self->file, 
               $self->line, 
               $race_type, );

         } else {
            setEntityValid('RACETYPE', $race_type);
         }

      } else {

         # The RACE type found here are not create, we only
         # get rid of the .REMOVE. part
         $race_type =~ m{ \A [.] REMOVE [.] }xmsi;

         registerXCheck(
            'RACETYPE', 
            $self->tag, 
            $self->file, 
            $self->line, 
            $race_type, );
      }
   }
}


# Extract and validate any embeded PREs, then extract any variables for cross
# checking.

sub _sa {

   my ($self) = @_;

   my ($varString) = ( $self->value =~ /[^|]\|(.*)/ );

   if ($varString) {
      FORMULA:
      for my $formula ( split '\|', $varString ) {

         # Are there any PRE tags in the SA tag.
         if ( $formula =~ /(^!?PRE[A-Z]*):(.*)/ ) {

            my $preToken = $self->clone(tag => $1, value => $2);
            $preToken->_preToken($self->fullRealToken);

            next FORMULA;
         }

         registerXCheck(
            'DEFINE Variable', 
            qq{@@" in "} . $self->fullToken, 
            $self->file, 
            $self->line, 
            $self->_variables($formula) );
      }
   }
}


# Queue up the Skills for cross checking

sub _skill {

   my ($self) = @_;

   my @skills = split /[|]/, $self->value;

   @skills = grep { $_ ne 'ALL' } @skills;

   # We need to filter out %CHOICE for the SKILL tag
   if ( $self->tag eq 'SKILL' ) {
      @skills = grep { $_ ne '%CHOICE' } @skills;
   }

   # To be processed later
   registerXCheck(
      'SKILL', 
      $self->tag, 
      $self->file, 
      $self->line, 
      @skills, );
}


# Extract the CLASSes and SPELLs and queue them up for cross checking

sub _spellLevelClass {

   my ($self) = @_;
   my $log = getLogger();

   # The syntax for SPELLLEVEL:CLASS is
   # SPELLLEVEL:CLASS|<class-list of spells>
   # <class-list of spells> := <class> | <list of spells> [ | <class-list of spells> ]
   # <class>                       := <class name> = <level>
   # <list of spells>              := <spell name> [, <list of spells>]
   # <class name>          := ASCII WORDS that must be validated
   # <level>                       := INTEGER
   # <spell name>          := ASCII WORDS that must be validated
   #
   # ex. SPELLLEVEL:CLASS|Wizard=0|Detect Magic,Read Magic|Wizard=1|Burning Hands

   # Work with a copy because we do not want to change the original
   my $tag_line = $self->value;

   $tag_line =~ s/\|PRE\w+\:.+$//;

   # We extract the classes and the spell names
   if ( my $working_value = $tag_line ) {
      while ($working_value) {
         if ( $working_value =~ s/\|([^|]+)\|([^|]+)// ) {
            my $class  = $1;
            my $spells = $2;

            # The CLASS
            if ( $class =~ /([^=]+)\=(\d+)/ ) {

               # [ 849369 ] SPELLCASTER.Arcane=1
               # SPELLCASTER.Arcane and SPELLCASTER.Divine are specials
               # CLASS names that should not be cross-referenced.
               # To be processed later
               registerXCheck(
                  'CLASS',
                  qq{@@" in "} . $self->fullToken, 
                  $self->file, 
                  $self->line, 
                  $1 );

            } else {

               $log->notice(
                  qq{Invalid syntax for "$class" in "} . $self->fullToken . q{"},
                  $self->file,
                  $self->line
               );
            }

            # The SPELL names
            # To be processed later
            registerXCheck(
               'SPELL',
               qq{@@" in "} . $self->fullToken,
               $self->file,
               $self->line, 
               split ',', $spells );

         } else {

            $log->notice(
               qq{Invalid class/spell list paring in "} . $self->fullToken . q{"},
               $self->file,
               $self->line
            );
            $working_value = "";
         }
      }

   } else {
      $log->notice(
         qq{No value found for "} . $self->tag . q{"},
         $self->file,
         $self->line
      );
   }
}


# Extract the DOMAINs and SPELLs and queue them up for cross checking.

sub _spellLevelDomain {

   my ($self) = @_;
   my $log = getLogger();

   # The syntax for SPELLLEVEL:DOMAIN is
   # SPELLLEVEL:CLASS|<domain-list of spells>
   # <domain-list of spells> := <domain> | <list of spells> [ | <domain-list of spells> ]
   # <domain>                      := <domain name> = <level>
   # <list of spells>              := <spell name> [, <list of spells>]
   # <domain name>         := ASCII WORDS that must be validated
   # <level>                       := INTEGER
   # <spell name>          := ASCII WORDS that must be validated
   #
   # ex. SPELLLEVEL:DOMAIN|Air=1|Obscuring Mist|Animal=4|Repel Vermin

   # We extract the classes and the spell names
   if ( my $working_value = $self->value ) {
      while ($working_value) {
         if ( $working_value =~ s/\|([^|]+)\|([^|]+)// ) {
            my $domain = $1;
            my $spells = $2;

            # The DOMAIN
            if ( $domain =~ /([^=]+)\=(\d+)/ ) {
               registerXCheck(
                  'DOMAIN',
                  qq{@@" in "} . $self->fullToken,
                  $self->file,
                  $self->line,
                  $1 );

            } else {

               $log->notice(
                  qq{Invalid syntax for "$domain" in "} . $self->fullToken . q{"},
                  $self->file,
                  $self->line
               );
            }

            # The SPELL names
            # To be processed later
            registerXCheck(
               'SPELL', 
               qq{@@" in "} . $self->fullToken,
               $self->file,
               $self->line,
               split ',', $spells );

         } else {
            $log->notice(
               qq{Invalid domain/spell list paring in "} . $self->fullToken . q{"},
               $self->file,
               $self->line
            );
            $working_value = "";
         }
      }

   } else {
      $log->notice(
         qq{No value found for "} . $self->tag . q{"},
         $self->file,
         $self->line
      );
   }
}


# The way Spells are validated depends on the linetype

sub _spells {

   my ($self) = @_;


   if ($self->lineType eq 'KIT SPELLS') { 
      _kitSpells($self);
   } else {
      _nonKitSpells($self);
   }
}


# STARTPACK lines in Kit files weren't getting added to $valid_entities. If the
# verify flag is set and they aren't added to valid_entities, each Kit will
# cause a spurious error. I've added them to valid entities to prevent that.

sub _startPack {

   my ($self) = @_;

   my $value = $self->value;
   setEntityValid('KIT STARTPACK', "KIT:$value");
   setEntityValid('KIT STARTPACK', "$value");
}


# Extract the Stats from KIT STAT lines and validate them against the valid
# system stats.

sub _stat {

   my ($self) = @_;
   my $log = getLogger();

   if ( $self->lineType eq 'KIT STAT' ) {

      # STAT:STR=17|DEX=10|CON=14|INT=8|WIS=12|CHA=14
      my %stat_count_for = map { $_ => 0 } getValidSystemArr('stats');

      STAT:
      for my $stat_expression (split /[|]/, $self->value) {

         my ($stat) = ( $stat_expression =~ / \A ([A-Z]{3}) [=] (\d+|roll\(\"\w+\"\)((\+|\-)var\(\"STAT.*\"\))*) \z /xms );

         if ( !defined $stat ) {
            # Syntax error
            $log->notice(
               qq{Invalid syntax for "$stat_expression" in "} . $self->fullToken . q{"},
               $self->file,
               $self->line
            );

            next STAT;
         }

         if ( !exists $stat_count_for{$stat} ) {
            # The stat is not part of the official list
            $log->notice(
               qq{Invalid attribute name "$stat" in "} . $self->fullToken . q{"},
               $self->file,
               $self->line
            );
         } else {
            $stat_count_for{$stat}++;
         }
      }

      # We check to see if some stat are repeated
      for my $stat ( getValidSystemArr('stats')) {
         if ( $stat_count_for{$stat} > 1 ) {
            $log->notice(
               qq{Found $stat more then once in "} . $self->fullToken . q{"},
               $self->file,
               $self->line
            );
         }
      }
   }
}


# Check that the sub token is valid and adjust the $tag if appropraite.

sub _sub {

   my ($self) = @_;

   my $log = getLogger();

   # If this is s a subTag, the subTag is currently on the front of the value.
   my ($subTag) = ($self->value =~ /^([^=:|]+)/ );

   my $potentialTag = $self->tag . ':' . $subTag;

   if ($subTag && exists $validSubTags{$self->tag}{$subTag}) {

      $self->tag($potentialTag);
      $self->value($self->value =~ s/^$subTag(.*)/$1/r);

   } elsif ($subTag) {

      # No valid type found
      incCountInvalidTags($self->lineType, $potentialTag);
      $log->notice(
         qq{Invalid $potentialTag tag "} . $self->origToken . q{" found in } . $self->lineType,
         $self->file,
         $self->line
      );
      $self->noMoreErrors(1);

   } else {

      incCountInvalidTags($self->lineType, $self->tag);
      $log->notice(
         q{Invalid } . $self->tag . q{ tag "} . $self->origToken . q{" found in } . $self->lineType,
         $self->file,
         $self->line
      );
      $self->noMoreErrors(1);
   }
}


# Queue up the RaceType for cross checking.

sub _switchRace {

   my ($self) = @_;


   # To be processed later
   # Note: SWITCHRACE actually switch the race TYPE
   registerXCheck(
      'RACE TYPE',
      $self->tag,
      $self->file,
      $self->line, 
      (split '\|',  $self->value), );
}


# Extract the Template data and queue it for cross checking.

sub _template {

   my ($self) = @_;

   # TEMPLATE:<template name>|<template name>|etc.
   registerXCheck(
      'TEMPLATE', 
      $self->tag, 
      $self->file, 
      $self->line, 
      (split /[|]/, $self->value), );
}


# Add the types to Valid Types.

sub _types {

   my ($self) = @_;

   for my $type ( split '\.', $self->value ) {
      addToValidTypes($self->lineType, $type);
   }
}


# This function stores data for later validation. It also checks the syntax of
# certain tags and detects common errors and deprecations.

# The %referrer hash must be populated following this format
# $referrer{$lintype}{$name} = [ $err_desc, $file, $line ]

sub _validate {

   my ($token) = @_;

   my $valOp;

   if ($token->tag =~ qr/^\!?PRE/) {
      $token->_preToken("");

   } elsif ($token->tag =~ qr/^BONUS/) {
      $valOp = \&_bonusTag;
   } 
   
   if ($token->lineType eq 'SPELL' && not defined $valOp) {
      $valOp = $spellOperations{$token->tag};
   }
   
   if ($token->lineType ne 'PCC' && not defined $valOp) {
      $valOp = $nonPCCOperations{$token->tag};
   }

   if (not defined $valOp) {
      $valOp = $standardOperations{$token->tag};
   }

   if (defined $valOp) {
      $valOp->($token);
   }
}


# Parse an expression and return a list of variables found.

sub _variables {

   my ($self, $toParse) = @_;

   # We absolutely need to be called in array context.
   if (!wantarray) {
      croak q{_variables must be called in list context}
   };

   # If the -nojep command line option was used, we
   # call the old parser
   if ( getOption('nojep') ) {
      return oldExtractVariables($toParse, $self->fullRealToken, $self->file, $self->line);
   } else {
      return parseJepFormula($toParse, $self->fullRealToken, $self->file, $self->line, 0);
   }
}


# Generate a warning message about a deprecated tag.

sub _warnDeprecate {

   my ($self, $enclosingToken) = @_;

   my $message = qq{Deprecated syntax: "} . $self->fullRealToken . q{"};

   if($enclosingToken) {
      $message .= qq{ found in "} . $enclosingToken . q{"};
   }

   getLogger()->info( $message, $self->file, $self->line );
}

__PACKAGE__->meta->make_immutable;

1;
