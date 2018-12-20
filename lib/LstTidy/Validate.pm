package LstTidy::Validate;

use strict;
use warnings;

use Text::Balanced ();

use File::Basename qw(dirname);
use Cwd  qw(abs_path);
use lib dirname(dirname abs_path $0);

use LstTidy::Parse;

# The PRExxx tags. They are used in many of the line types.
# From now on, they are defined in only one place and every
# line type will get the same sort order.
my @PreTags = (
   'PRE:.CLEAR',
   'PREABILITY:*',
   '!PREABILITY',
   'PREAGESET',
   '!PREAGESET',
   'PREALIGN:*',
   '!PREALIGN:*',
   'PREARMORPROF:*',
   '!PREARMORPROF',
   'PREARMORTYPE',
   '!PREARMORTYPE',
   'PREATT',
   '!PREATT',
   'PREBASESIZEEQ',
   '!PREBASESIZEEQ',
   'PREBASESIZEGT',
   '!PREBASESIZEGT',
   'PREBASESIZEGTEQ',
   '!PREBASESIZEGTEQ',
   'PREBASESIZELT',
   '!PREBASESIZELT',
   'PREBASESIZELTEQ',
   '!PREBASESIZELTEQ',
   'PREBASESIZENEQ',
   'PREBIRTHPLACE',
   '!PREBIRTHPLACE',
   'PRECAMPAIGN',
   '!PRECAMPAIGN',
   'PRECHECK',
   '!PRECHECK',
   'PRECHECKBASE',
   '!PRECHECKBASE',
   'PRECITY',
   '!PRECITY',
   'PRECHARACTERTYPE',
   '!PRECHARACTERTYPE',
   'PRECLASS',
   '!PRECLASS',
   'PRECLASSLEVELMAX',
   '!PRECLASSLEVELMAX',
   'PRECSKILL',
   '!PRECSKILL',
   'PREDEITY',
   '!PREDEITY',
   'PREDEITYALIGN',
   '!PREDEITYALIGN',
   'PREDEITYDOMAIN',
   '!PREDEITYDOMAIN',
   'PREDOMAIN',
   '!PREDOMAIN',
   'PREDR',
   '!PREDR',
   'PREEQUIP',
   '!PREEQUIP',
   'PREEQUIPBOTH',
   '!PREEQUIPBOTH',
   'PREEQUIPPRIMARY',
   '!PREEQUIPPRIMARY',
   'PREEQUIPSECONDARY',
   '!PREEQUIPSECONDARY',
   'PREEQUIPTWOWEAPON',
   '!PREEQUIPTWOWEAPON',
   'PREFEAT:*',
   '!PREFEAT',
   'PREFACT:*',
   '!PREFACT',
   'PREGENDER',
   '!PREGENDER',
   'PREHANDSEQ',
   '!PREHANDSEQ',
   'PREHANDSGT',
   '!PREHANDSGT',
   'PREHANDSGTEQ',
   '!PREHANDSGTEQ',
   'PREHANDSLT',
   '!PREHANDSLT',
   'PREHANDSLTEQ',
   '!PREHANDSLTEQ',
   'PREHANDSNEQ',
   'PREHD',
   '!PREHD',
   'PREHP',
   '!PREHP',
   'PREITEM',
   '!PREITEM',
   'PRELANG',
   '!PRELANG',
   'PRELEGSEQ',
   '!PRELEGSEQ',
   'PRELEGSGT',
   '!PRELEGSGT',
   'PRELEGSGTEQ',
   '!PRELEGSGTEQ',
   'PRELEGSLT',
   '!PRELEGSLT',
   'PRELEGSLTEQ',
   '!PRELEGSLTEQ',
   'PRELEGSNEQ',
   'PRELEVEL',
   '!PRELEVEL',
   'PRELEVELMAX',
   '!PRELEVELMAX',
   'PREKIT',
   '!PREKIT',
   'PREMOVE',
   '!PREMOVE',
   'PREMULT:*',
   '!PREMULT:*',
   'PREPCLEVEL',
   '!PREPCLEVEL',
   'PREPROFWITHARMOR',
   '!PREPROFWITHARMOR',
   'PREPROFWITHSHIELD',
   '!PREPROFWITHSHIELD',
   'PRERACE:*',
   '!PRERACE:*',
   'PREREACH',
   '!PREREACH',
   'PREREACHEQ',
   '!PREREACHEQ',
   'PREREACHGT',
   '!PREREACHGT',
   'PREREACHGTEQ',
   '!PREREACHGTEQ',
   'PREREACHLT',
   '!PREREACHLT',
   'PREREACHLTEQ',
   '!PREREACHLTEQ',
   'PREREACHNEQ',
   'PREREGION',
   '!PREREGION',
   'PRERULE',
   '!PRERULE',
   'PRESA',
   '!PRESA',
   'PRESITUATION',
   '!PRESITUATION',
   'PRESHIELDPROF',
   '!PRESHIELDPROF',
   'PRESIZEEQ',
   '!PRESIZEEQ',
   'PRESIZEGT',
   '!PRESIZEGT',
   'PRESIZEGTEQ',
   '!PRESIZEGTEQ',
   'PRESIZELT',
   '!PRESIZELT',
   'PRESIZELTEQ',
   '!PRESIZELTEQ',
   'PRESIZENEQ',
   'PRESKILL:*',
   '!PRESKILL',
   'PRESKILLMULT',
   '!PRESKILLMULT',
   'PRESKILLTOT',
   '!PRESKILLTOT',
   'PRESPELL:*',
   '!PRESPELL',
   'PRESPELLBOOK',
   '!PRESPELLBOOK',
   'PRESPELLCAST:*',
   '!PRESPELLCAST:*',
   'PRESPELLDESCRIPTOR',
   'PRESPELLSCHOOL:*',
   '!PRESPELLSCHOOL',
   'PRESPELLSCHOOLSUB',
   '!PRESPELLSCHOOLSUB',
   'PRESPELLTYPE:*',
   '!PRESPELLTYPE',
   'PRESREQ',
   '!PRESREQ',
   'PRESRGT',
   '!PRESRGT',
   'PRESRGTEQ',
   '!PRESRGTEQ',
   'PRESRLT',
   '!PRESRLT',
   'PRESRLTEQ',
   '!PRESRLTEQ',
   'PRESRNEQ',
   'PRESTAT:*',
   '!PRESTAT',
   'PRESTATEQ',
   '!PRESTATEQ',
   'PRESTATGT',
   '!PRESTATGT',
   'PRESTATGTEQ',
   '!PRESTATGTEQ',
   'PRESTATLT',
   '!PRESTATLT',
   'PRESTATLTEQ',
   '!PRESTATLTEQ',
   'PRESTATNEQ',
   'PRESUBCLASS',
   '!PRESUBCLASS',
   'PRETEMPLATE:*',
   '!PRETEMPLATE:*',
   'PRETEXT',
   '!PRETEXT',
   'PRETYPE:*',
   '!PRETYPE:*',
   'PRETOTALAB:*',
   '!PRETOTALAB:*',
   'PREUATT',
   '!PREUATT',
   'PREVAREQ:*',
   '!PREVAREQ:*',
   'PREVARGT:*',
   '!PREVARGT:*',
   'PREVARGTEQ:*',
   '!PREVARGTEQ:*',
   'PREVARLT:*',
   '!PREVARLT:*',
   'PREVARLTEQ:*',
   '!PREVARLTEQ:*',
   'PREVARNEQ:*',
   'PREVISION',
   '!PREVISION',
   'PREWEAPONPROF:*',
   '!PREWEAPONPROF:*',
   'PREWIELD',
   '!PREWIELD',

   # Removed tags
   #       'PREVAR',
);

# Hash used by validatePreTag to verify if a PRExxx tag exists
my %PreTags = (
   'PREAPPLY'          => 1,   # Only valid when embeded - THIS IS DEPRECATED
   'PREDEFAULTMONSTER' => 1,   # Only valid when embeded
);

for my $preTag (@PreTags) {

   # We need a copy since we don't want to modify the original
   my $preTagName = $preTag;

   # We strip the :* at the end to get the real name for the lookup table
   $preTagName =~ s/ [:][*] \z//xms;

   $PreTags{$preTagName} = 1;
}


# Will hold the portions of a race that have been matched with wildcards.
# For example, if Elf% has been matched (given no default Elf races).
my %racePartialMatch;

# Will hold the entries that may be refered to by other tags Format
# $validEntities{$entitytype}{$entityname} We initialise the hash with global
# system values that are valid but never defined in the .lst files.
my %validEntities;

# Will hold the valid types for the TYPE. or TYPE= found in different tags.
# Format validTypes{$entitytype}{$typename}
my %validTypes;

# Will hold the valid categories for CATEGORY= found in abilities.
# Format validCategories{$entitytype}{$categoryname}
my %validCategories;

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

# List of types that are valid in BONUS:SLOTS
# 
my %validBonusSlots = map { $_ => 1 } (
   'AMULET',
   'ARMOR',
   'BELT',
   'BOOT',
   'BRACER',
   'CAPE',
   'CLOTHING',
   'EYEGEAR',
   'GLOVE',
   'HANDS',
   'HEADGEAR',
   'LEGS',
   'PSIONICTATTOO',
   'RING',
   'ROBE',
   'SHIELD',
   'SHIRT',
   'SUIT',
   'TATTOO',
   'TRANSPORTATION',
   'VEHICLE',
   'WEAPON',

   # Special value for the CHOOSE tag
   'LIST',
);

=head2 embedded_coma_split

   split a list using the comma but part of the list may be
   between brackets and the comma must be ignored there.
   
   Parameter: $list      List that need to be splited
              $separator optional expression used for the
                                 split, ',' is the default.
   
   Return the splited list.

=cut

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



=head2 getValidTypes

   Return a reference to the has of valid types for cross checking.

   Format validTypes{$entitytype}{$typename}

=cut

sub getValidTypes {
   return \%validTypes;
}

=head2 getValidCategories

   Return a reference to the hash of valid categories for cross checking.

   Format validCategories{$entitytype}{$categoryname}

=cut

sub getValidCategories {
   return \%validCategories;
}



=head2 isEntityValid

   Returns true if the entity is valid.

=cut

sub isEntityValid {
   my ($entitytype, $entityname) = @_;

   return exists $validEntities{$entitytype}{$entityname};
}

=head2 scanForDeprecatedTags

   This function establishes a centralized location to search
   each line for deprecated tags.

   Parameters: $line     = The line to be searched
               $linetype = The type of line
               $file     = File name to use with ewarn
               $line     = The currrent line's number within the file

=cut

sub scanForDeprecatedTags {
   my ( $line, $linetype, $file, $lineNum ) = @_ ;

   my $logger = LstTidy::LogFactory::getLogger();

   # Deprecated tags
   if ( $line =~ /\scl\(/ ) {
      $logger->info(
         qq{The Jep function cl() is deprecated, use classlevel() instead},
         $file,
         $lineNum
      );
   }

   # [ 1938933 ] BONUS:DAMAGE and BONUS:TOHIT should be Deprecated
   if ( $line =~ /\sBONUS:DAMAGE\s/ ) {
      $logger->info(
         qq{BONUS:DAMAGE is deprecated 5.5.8 - Remove 5.16.0 - Use BONUS:COMBAT|DAMAGE.x|y instead},
         $file,
         $lineNum
      );
   }

   # [ 1938933 ] BONUS:DAMAGE and BONUS:TOHIT should be Deprecated
   if ( $line =~ /\sBONUS:TOHIT\s/ ) {
      $logger->info(
         qq{BONUS:TOHIT is deprecated 5.3.12 - Remove 5.16.0 - Use BONUS:COMBAT|TOHIT|x instead},
         $file,
         $lineNum
      );
   }

   # [ 1973497 ] HASSPELLFORMULA is deprecated
   if ( $line =~ /\sHASSPELLFORMULA/ ) {
      $logger->warning(
         qq{HASSPELLFORMULA is no longer needed and is deprecated in PCGen 5.15},
         $file,
         $lineNum
      );
   }

   if ( $line =~ /[\d+|\)]MAX\d+/ ) {
      $logger->info(
         qq{The function aMAXb is deprecated, use the Jep function max(a,b) instead},
         $file,
         $lineNum
      );
   }

   if ( $line =~ /[\d+|\)]MIN\d+/ ) {
      $logger->info(
         qq{The function aMINb is deprecated, use the Jep function min(a,b) instead},
         $file,
         $lineNum
      );
   }

   if ( $line =~ /\b]TRUNC\b/ ) {
      $logger->info(
         qq{The function TRUNC is deprecated, use the Jep function floor(a) instead},
         $file,
         $lineNum
      );
   }

   if ( $line =~ /\sHITDICESIZE\s/ ) {
      $logger->info(
         qq{HITDICESIZE is deprecated, use HITDIE instead},
         $file,
         $lineNum
      );
   }

   if ( $line =~ /\sSPELL\s/ && $linetype ne 'PCC' ) {
      $logger->info(
         qq{SPELL is deprecated, use SPELLS instead},
         $file,
         $lineNum
      );
   }

   if ( $line =~ /\sWEAPONAUTO\s/ ) {
      $logger->info(
         qq{WEAPONAUTO is deprecated, use AUTO:WEAPONPROF instead},
         $file,
         $lineNum
      );
   }

   if ( $line =~ /\sADD:WEAPONBONUS\s/ ) {
      $logger->info(
         qq{ADD:WEAPONBONUS is deprecated, use BONUS instead},
         $file,
         $lineNum
      );
   }

   if ( $line =~ /\sADD:LIST\s/ ) {
      $logger->info(
         qq{ADD:LIST is deprecated, use BONUS instead},
         $file,
         $lineNum
      );
   }

   if ( $line =~ /\sFOLLOWERALIGN/) {
      $logger->info(
         qq{FOLLOWERALIGN is deprecated, use PREALIGN on Domain instead. Use the -c=pcgen5120 command line switch to fix this problem},
         $file,
         $lineNum
      );
   }

   # [ 1905481 ] Deprecate CompanionMod SWITCHRACE
   if ( $line =~ /\sSWITCHRACE\s/) {
      $logger->info(
         qq{SWITCHRACE is deprecated 5.13.11 - Remove 6.0 - Use RACETYPE:x tag instead },
         $file,
         $lineNum
      );
   }

   # [ 1804786 ] Deprecate SA: replace with SAB:
   if ( $line =~ /\sSA:/) {
      $logger->info(
         qq{SA is deprecated 5.x.x - Remove 6.0 - use SAB instead },
         $file,
         $lineNum
      );
   }

   # [ 1804780 ] Deprecate CHOOSE:EQBUILDER|1
   if ( $line =~ /\sCHOOSE:EQBUILDER\|1/) {
      $logger->info(
         qq{CHOOSE:EQBUILDER|1 is deprecated use CHOOSE:NOCHOICE instead },
         $file,
         $lineNum
      );
   }

   # [ 1864704 ] AUTO:ARMORPROF|TYPE=x is deprecated
   if ( $line =~ /\sAUTO:ARMORPROF\|TYPE\=/) {
      $logger->info(
         qq{AUTO:ARMORPROF|TYPE=x is deprecated Use AUTO:ARMORPROF|ARMORTYPE=x instead},
         $file,
         $lineNum
      );
   }

   # [ 1870482 ] AUTO:SHIELDPROF changes
   if ( $line =~ /\sAUTO:SHIELDPROF\|TYPE\=/) {
      $logger->info(
         qq{AUTO:SHIELDPROF|TYPE=x is deprecated Use AUTO:SHIELDPROF|SHIELDTYPE=x instead},
         $file,
         $lineNum
      );
   }

   # [ NEWTAG-19 ] CHOOSE:ARMORPROF= is deprecated
   if ( $line =~ /\sCHOOSE:ARMORPROF\=/) {
      $logger->info(
         qq{CHOOSE:ARMORPROF= is deprecated 5.15 - Remove 6.0. Use CHOOSE:ARMORPROFICIENCY instead},
         $file,
         $lineNum
      );
   }

   # [ NEWTAG-17 ] CHOOSE:FEATADD= is deprecated
   if ( $line =~ /\sCHOOSE:FEATADD\=/) {
      $logger->info(
         qq{CHOOSE:FEATADD= is deprecated 5.15 - Remove 6.0. Use CHOOSE:FEAT instead},
         $file,
         $lineNum
      );
   }

   # [ NEWTAG-17 ] CHOOSE:FEATLIST= is deprecated
   if ( $line =~ /\sCHOOSE:FEATLIST\=/) {
      $logger->info(
         qq{CHOOSE:FEATLIST= is deprecated 5.15 - Remove 6.0. Use CHOOSE:FEAT instead},
         $file,
         $lineNum
      );
   }

   # [ NEWTAG-17 ] CHOOSE:FEATSELECT= is deprecated
   if ( $line =~ /\sCHOOSE:FEATSELECT\=/) {
      $logger->info(
         qq{CHOOSE:FEATSELECT= is deprecated 5.15 - Remove 6.0. Use CHOOSE:FEAT instead},
         $file,
         $lineNum
      );
   }


   # [ 1888288 ] CHOOSE:COUNT= is deprecated
   if ( $line =~ /\sCHOOSE:COUNT\=/) {
      $logger->info(
         qq{CHOOSE:COUNT= is deprecated 5.13.9 - Remove 6.0. Use SELECT instead},
         $file,
         $lineNum
      );
   }
}

=head2 setEntityValid

   Increments the number of times entity has been seen, and makes the exists
   test true for this entity.

=cut

sub setEntityValid {
   my ($entitytype, $entityname) = @_;

   $validEntities{$entitytype}{$entityname}++;
}

=head2 splitAndAddToValidEntities

   ad-hod/special list of thingy It adds to the valid entities instead of the
   valid sub-entities.  We do this when we find a CHOOSE but we do not know what
   it is for.

=cut

sub splitAndAddToValidEntities {
   my ($entitytype, $ability, $value) = @_;

   for my $abil ( split '\|', $value ) {
      $validEntities{'ABILITY'}{"$ability($abil)"}  = $value;
      $validEntities{'ABILITY'}{"$ability ($abil)"} = $value;
   }
}

=head2 searchRace

   Searches the Race entries of valid entities looking for a match for
   the given race.

=cut

sub searchRace {
   my ($race_wild) = @_;

   for my $toCheck (keys %{$validEntities{'RACE'}} ) {
      if ($toCheck =~  m/^\Q$race_wild/) {
         return 1;
      }
   }
   return 0;
}


=head2 warnDeprecate

   Generate a warning message about a deprecated tag.

   Parameters: $tag            Tag that has been deprecated
               $enclosing_tag  (Optionnal) tag into which the deprecated tag is included

=cut

sub warnDeprecate {

   my ($tag, $enclosing_tag) = @_;

   my $message = qq{Deprecated syntax: "} . $$tag->fullRealTag . q{"};

   if($enclosing_tag) {
      $message .= qq{ found in "} . $enclosing_tag . q{"};
   }

   LstTidy::LogFactory::getLogger->info( $message, $tag->file, $tag->line );
}







=head2 checkFirstValue

   Check the Values in the PRE tag to ensure it starts with a number.

=cut

sub checkFirstValue {

   my ($value) = @_;

   # We get the list of values
   my @values = split ',', $value;

   # first entry is a number
   my $valid = $values[0] =~ / \A \d+ \z /xms;

   # get rid of the number
   shift @values if $valid;

   return $valid, @values;
}

=head2 processGenericPRE

   Process a PRE tag

   Check for deprecated syntax and queue up for cross check.

=cut

sub processGenericPRE {

   my ($preType, $tag, $enclosingTag) = @_;

   my ($valid, @values) = checkFirstValue($tag->value);

   # The PREtag doesn't begin with a number
   if ( not $valid ) {
      warnDeprecate($tag, $enclosingTag);
   }

   LstTidy::Report::registerXCheck($preType, $tag->id, $tag->file, $tag->line, @values);
}

=head2 processPRECHECK

   Check the PRECHECK familiy of PRE tags for validity.

   Ensures they start with a number.

   Ensures that the checks are valid.

=cut

sub processPRECHECK {

   my ($tag, $enclosingTag) = @_;

   # PRECHECK:<number>,<check equal value list>
   # PRECHECKBASE:<number>,<check equal value list>
   # <check equal value list> := <check name> "=" <number>
   my ($valid, @values) = checkFirstValue($tag->value);

   # The PREtag doesn't begin with a number
   if ( not $valid ) {
      warnDeprecate($tag, $enclosingTag);
   }

   # Get the logger once outside the loop
   my $logger = LstTidy::LogFactory::getLogger();

   for my $item ( @values ) {

      # Extract the check name
      if ( my ($check_name, $value) = ( $item =~ / \A ( \w+ ) = ( \d+ ) \z /xms ) ) {

         # If we don't recognise it.
         if ( ! LstTidy::Parse::isValidCheck($check_name) ) {
            $logger->notice(
               qq{Invalid save check name "$check_name" found in "} . $tag->fullRealValue . q{"},
               $tag->file,
               $tag->line
            );
         }
      } else {
         $logger->notice(
            $tag->id . qq{ syntax error in "$item" found in "} . $tag->fullRealValue . q{"},
            $tag->file,
            $tag->line
         );
      }
   }
}


=head2 processPREDIETY

   Process the PREDIETY tags

   Queue up for Cross check.

=cut

sub processPREDIETY {

   my ($tag) = @_;

   #PREDEITY:Y
   #PREDEITY:YES
   #PREDEITY:N
   #PREDEITY:NO
   #PREDEITY:1,<deity name>,<deity name>,etc.

   if ( $tag->value !~ / \A (?: Y(?:ES)? | N[O]? ) \z /xms ) {
      #We ignore the single yes or no
      LstTidy::Report::registerXCheck('DEITY', $tag->id, $tag->file, $tag->line, (split /[,]/, $tag->value)[1,-1],);
   }
};


=head2 processPRELANG

   Process the PRELANG tags

   Check for deprecated syntax and quque up for cross check.

=cut

sub processPRELANG {

   my ($tag, $enclosingTag) = @_;

   # PRELANG:number,language,language,TYPE=type
   my ($valid, @values) = checkFirstValue(i$tag->value);

   # The PREtag doesn't begin with a number
   if ( not $valid ) {
      warnDeprecate($tag, $enclosingTag);
   }

   LstTidy::Report::registerXCheck('LANGUAGE', $tag->id, $tag->file, $tag->line, grep { $_ ne 'ANY' } @values);
}

=head2 processPREMOVE

   Process the PREMOVE tags

   Check for deprecated syntax and quque up for cross check.

=cut

sub processPREMOVE {

   my ($tag, $enclosingTag) = @_;

   # PREMOVE:[<number>,]<move>=<number>,<move>=<number>,...
   my ($valid, @values) = checkFirstValue(i$tag->value);

   # The PREtag doesn't begin with a number
   if ( not $valid ) {
      warnDeprecate($tag, $enclosingTag);
   }

   for my $move (@values) {

      # Verify that the =<number> is there
      if ( $move =~ /^([^=]*)=([^=]*)$/ ) {

         LstTidy::Report::registerXCheck('MOVE Type', $tag->id, $tag->file, $tag->line, $1);

         # The value should be a number
         my $value = $2;

         if ($value !~ /^\d+$/ ) {
            my $message = qq{Not a number after the = for "$move" in "} . $tag->fullRealTag . q{"};
            $message .= qq{ found in "$enclosingTag"} if $enclosingTag;

            LstTidy::LogFactory::getLogger()->notice($message, $tag->file, $tag->line);
         }

      } else {

         my $message = qq{Invalid "$move" in "} . $tag->fullRealTag . q{"};
         $message .= qq{ found in "$enclosingTag"} if $enclosingTag;

         LstTidy::LogFactory::getLogger()->notice($message, $tag->file, $tag->line);

      }
   }
}

=head2 processPREMULT

   split and check the PREMULT tags

   Each PREMULT tag has two or more embedded PRE tags, which are individually
   checked using validatePreTag.

=cut

sub processPREMULT {

   my ($tag, $enclosingTag) = @_;

   my $working_value = $tag->value;
   my $inside;

   # We add only one level of PREMULT to the error message.
   my $emb_tag;
   if ($enclosingTag) {

      $emb_tag = $enclosingTag;
      $emb_tag .= ':PREMULT' unless $emb_tag =~ /PREMULT$/;

   } else {

      $emb_tag .= 'PREMULT';
   }

   FIND_BRACE:
   while ($working_value) {

      ( $inside, $working_value ) = Text::Balanced::extract_bracketed( $working_value, '[]', qr{[^[]*} );

      last FIND_BRACE if !$inside;

      # We extract what we need
      if ( $inside =~ /^\[(!?PRE[A-Z]+):(.*)\]$/ ) {

         my $preTag = $tag->clone(id => $1, value => $2);

         validatePreTag($preTag, $tag->fullRealTag);

      } else {

         # No PRExxx tag found inside the PREMULT
         LstTidy::LogFactory::getLogger()->warning(
            qq{No valid PRExxx tag found in "$inside" inside "PREMULT:} . $tag->value . q{"},
            $tag->file,
            $tag->line
         );
      }
   }
}

=head2 processPRERACE

   Process the PREMOVE tags

   Check for deprecated syntax and quque up for cross check.

=cut

sub processPRERACE {

   my ($tag, $enclosingTag) = @_;

   # We get the list of races
   my ($valid, @values) = checkFirstValue($tag->value);

   # The PREtag doesn't begin with a number
   if ( not $valid ) {
      warnDeprecate($tag, $enclosingTag);
   }

   my ( @races, @races_wild );

   for my $race (@values) {

      if ( $race =~ / (.*?) [%] (.*?) /xms ) {
         # Special case for PRERACE:xxx%
         my $race_wild  = $1;
         my $after_wild = $2;

         push @races_wild, $race_wild;

         if ( $after_wild ne q{} ) {

            LstTidy::LogFactory::getLogger()->notice(
               qq{% used in wild card context should end the race name in "$race"},
               $tag->file,
               $tag->line
            );

         } else {

            # Don't bother warning if it matches everything.
            # For now, we warn and do nothing else.
            if ($race_wild eq '') {

               ## Matches everything, no reason to warn.

            } elsif ($validEntities{'RACE'}{$race_wild}) {

               ## Matches an existing race, no reason to warn.

            } elsif ($racePartialMatch{$race_wild}) {

               ## Partial match already confirmed, no need to confirm.
               #
            } else {

               my $found = searchRace($race_wild) ;

               if ($found) {
                  $racePartialMatch{$race_wild} = 1;
               } else {

                  LstTidy::LogFactory::getLogger()->info(
                     qq{Not able to validate "$race" in "PRERACE:} . $tag->value. q{." This warning is order dependent.} .
                     q{ If the race is defined in a later file, this warning may not be accurate.},
                     $tag->file,
                     $tag->line
                  )
               }
            }
         }
      } else {
         push @races, $race;
      }
   }

   LstTidy::Report::registerXCheck('RACE', $tag->id, $tag->file, $tag->line, @races);
}


=head2 processPRESPELL

   Process the PRESPELL tags

   Check for deprecated syntax and quque up for cross check.

=cut

sub processPRESPELL {

   my ($tag, $enclosingTag) = @_;

   # We get the list of skills and skill types
   my ($valid, @values) = checkFirstValue($tag->value);

   # The PREtag doesn't begin with a number
   if ( not $valid ) {
      warnDeprecate($tag, $enclosingTag);
   }

   LstTidy::Report::registerXCheck('SPELL', $tag->id . ":@@", $tag->file, $tag->line, @values);
}

=head2 processPREVAR

=cut

sub processPREVAR {

   my ($tag, $enclosingTag) = @_;

   my ( $var_name, @formulas ) = split ',', $tag->value;

   LstTidy::Report::registerXCheck('DEFINE Variable', qq{@@" in "} . $tag->fullRealTag, $tag->file, $tag->line, $var_name,);

   for my $formula (@formulas) {
      my @values = LstTidy::Parse::extractVariables($formula, $tag);
      LstTidy::Report::registerXCheck('DEFINE Variable', qq{@@" in "} . $tag->fullRealTag, $tag->file, $tag->line, @values);
   }
}

=head2 validateBonusChecks

   Validate a Bonus checks tag. 

   BONUS:CHECKS|<check list>|<jep> {|TYPE=<bonus type>} {|<pre tags>}
   BONUS:CHECKS|ALL|<jep>          {|TYPE=<bonus type>} {|<pre tags>}
   <check list> :=   ( <check name 1> { | <check name 2> } { | <check name 3>} )
                         | ( BASE.<check name 1> { | BASE.<check name 2> } { | BASE.<check name 3>} )

=cut

sub validateBonusChecks {

   my ($tag) = @_;

   # We get parameter 1 and 2 (0 is empty since $tag->value begins with a |)
   my (undef, $checks, $formula) = (split /[|]/, $tag->value);
      
   if ( $checks ne 'ALL' ) {

      my ($base, $non_base) = ( 0, 0 );

      my $logger = LstTidy::LogFactory::getLogger();

      for my $check ( split q{,}, $checks ) {

         # We keep the original name for error messages
         my $cleanCheck = $check;

         # Did we use BASE.? is yes, we remove it
         if ( $cleanCheck =~ s/ \A BASE [.] //xms ) {
            $base = 1;
         } else {
            $non_base = 1;
         }

         if ( ! LstTidy::Parse::isValidCheck($cleanCheck) ) {
            $logger->notice(
               qq{Invalid save check name "$check" found in "} . $tag->fullTag . q{"},
               $tag->file,
               $tag->line
            );
         }
      }

      # Warn the user if they're mixing base and non-base
      if ( $base && $non_base ) {
         $logger->info(
            qq{Are you sure you want to mix BASE and non-BASE in "} . $tag->fullTag . q{"},
            $tag->file,
            $tag->line
         );
      }
   }

   # The formula part
   push @LstTidy::Report::xcheck_to_process,
   [
      'DEFINE Variable',
      qq{@@" in "} . $tag->fullTag,
      $tag->file,
      $tag->line,
      LstTidy::Parse::extractVariables($formula, $tag)
   ];
}

=head2 validateBonusTag

=cut

sub validateBonusTag {

   my ($tag) = @_;

   # Are there any PRE tags in the BONUS tag.
   if ( $tag->value =~ /(!?PRE[A-Z]*):([^|]*)/ ) {

      my $preTag = $tag->clone(id => $1, value => $2);
      validatePreTag($preTag, $tag->fullRealTag);
   }

   if ( $tag->id eq 'BONUS:CHECKS' ) {

      validateBonusChecks($tag);

   } elsif ( $tag->id eq 'BONUS:FEAT' ) {

      # BONUS:FEAT|POOL|<formula>|<prereq list>|<bonus type>

      # @list_of_param will contains all the non-empty parameters
      # included in $tag->value. The first one should always be
      # POOL.
      my @list_of_param = grep {/./} split '\|', $tag->value;

      if ( ( shift @list_of_param ) ne 'POOL' ) {

         # For now, only POOL is valid here
         LestTidy::LogFactory::getLogger->notice(
            qq{Only POOL is valid as second paramater for BONUS:FEAT "} . $tag->fullTag . q{"},
            $tag->file,
            $tag->line
         );
      }

      # The next parameter is the formula
      push @LstTidy::Report::xcheck_to_process,
      [
         'DEFINE Variable',
         qq{@@" in "} . $tag->fullTag,
         $tag->file,
         $tag->line,
         LstTidy::Parse::extractVariables(shift @list_of_param, $tag)
      ];

      # For the rest, we need to check if it is a PRExxx tag or a TYPE=
      my $type_present = 0;
      for my $param (@list_of_param) {
         if ( $param =~ /^(!?PRE[A-Z]+):(.*)/ ) {

            # It's a PRExxx tag, we delegate the validation
            my $preTag = $tag->clone(id => $1, value => $2);
            validatePreTag($preTag, $tag->fullRealTag);

         } elsif ( $param =~ /^TYPE=(.*)/ ) {

            $type_present++;

         } else {

            LestTidy::LogFactory::getLogger->notice(
               qq{Invalid parameter "$param" found in "} . $tag->fullTag . q{"},
               $tag->file,
               $tag->line
            );
         }
      }

      if ( $type_present > 1 ) {
         LestTidy::LogFactory::getLogger->notice(
            qq{There should be only one "TYPE=" in "} . $tag->fullTag . q{"},
            $tag->file,
            $tag->line
         );
      }
   }

   if (   $tag->id eq 'BONUS:MOVEADD'
      || $tag->id eq 'BONUS:MOVEMULT'
      || $tag->id eq 'BONUS:POSTMOVEADD' )
   {

      # BONUS:MOVEMULT|<list of move types>|<number to add or mult>
      # <list of move types> is a comma separated list of a weird TYPE=<move>.
      # The <move> are found in the MOVE tags.
      # <number to add or mult> can be a formula

      my ( undef, $type_list, $formula ) = ( split '\|', $tag->value );

      # We keep the move types for validation
      for my $type ( split ',', $type_list ) {
         if ( $type =~ /^TYPE(=|\.)(.*)/ ) {
            push @LstTidy::Report::xcheck_to_process,
            [
               'MOVE Type',
               qq{TYPE$1@@" in "} . $tag->fullTag,
               $tag->file,
               $tag->line,
               $2
            ];
         }
         else {
            LestTidy::LogFactory::getLogger->notice(
               qq{Missing "TYPE=" for "$type" in "} . $tag->fullTag . q{"},
               $tag->file,
               $tag->line
            );
         }
      }

      # Then we deal with the var in formula
      push @LstTidy::Report::xcheck_to_process,
      [
         'DEFINE Variable',
         qq{@@" in "} . $tag->fullTag,
         $tag->file,
         $tag->line,
         LstTidy::Parse::extractVariables($formula, $tag)
      ];
   }
   elsif ( $tag->id eq 'BONUS:SLOTS' ) {

      # BONUS:SLOTS|<slot types>|<number of slots>
      # <slot types> is a comma separated list.
      # The valid types are defined in %validBonusSlots
      # <number of slots> could be a formula.

      my ( undef, $type_list, $formula ) = ( split '\|', $tag->value );

      my $logger = LestTidy::LogFactory::getLogger();

      # We first check the slot types
      for my $type ( split ',', $type_list ) {
         unless ( exists $validBonusSlots{$type} ) {
            $logger->notice(
               qq{Invalid slot type "$type" in "} . $tag->fullTag . q{"},
               $tag->file,
               $tag->line
            );
         }
      }

      # Then we deal with the var in formula
      push @LstTidy::Report::xcheck_to_process,
      [
         'DEFINE Variable',
         qq{@@" in "} . $tag->fullTag,
         $tag->file,
         $tag->line,
         LstTidy::Parse::extractVariables($formula, $tag)
      ];
   }
   elsif ( $tag->id eq 'BONUS:VAR' ) {

      # BONUS:VAR|List of Names|Formula|... only the first two values are variable related.
      my ( undef, $var_name_list, @formulas ) = ( split '\|', $tag->value );

      # First we store the DEFINE variable name
      for my $var_name ( split ',', $var_name_list ) {
         if ( $var_name =~ /^[a-z][a-z0-9_\s]*$/i ) {
            # LIST is filtered out as it may not be valid for the
            # other places were a variable name is used.
            if ( $var_name ne 'LIST' ) {
               push @LstTidy::Report::xcheck_to_process,
               [
                  'DEFINE Variable',
                  qq{@@" in "} . $tag->fullTag,
                  $tag->file,
                  $tag->line,
                  $var_name,
               ];
            }
         }
         else {
            LestTidy::LogFactory::getLogger->notice(
               qq{Invalid variable name "$var_name" in "} . $tag->fullTag . q{"},
               $tag->file,
               $tag->line
            );
         }
      }

      # Second we deal with the formula
      # %CHOICE is filtered out as it may not be valid for the
      # other places were a variable name is used.
      for my $formula ( grep { $_ ne '%CHOICE' } @formulas ) {
         push @LstTidy::Report::xcheck_to_process,
         [
            'DEFINE Variable',
            qq{@@" in "} . $tag->fullTag,
            $tag->file,
            $tag->line,
            LstTidy::Parse::extractVariables($formula, $tag)
         ];
      }
   }
   elsif ( $tag->id eq 'BONUS:WIELDCATEGORY' ) {

      # BONUS:WIELDCATEGORY|<List of category>|<formula>
      my ( undef, $category_list, $formula ) = ( split '\|', $tag->value );

      my $logger = LestTidy::LogFactory::getLogger();

      # Validate the category to see if valid
      for my $category ( split ',', $category_list ) {
         if ( !exists $validWieldCategory{$category} ) {
            $logger->notice(
               qq{Invalid category "$category" in "} . $tag->fullTag . q{"},
               $tag->file,
               $tag->line
            );
         }
      }

      # Second, we deal with the formula
      push @LstTidy::Report::xcheck_to_process,
      [
         'DEFINE Variable',
         qq{@@" in "} . $tag->fullTag,
         $tag->file,
         $tag->line,
         LstTidy::Parse::extractVariables($formula, $tag)
      ];

   }
}


=head2 validateClearTag

   Validate the Clear tag.

   IF necessary, move the CLEAR from the value to the id.

=cut

sub validateClearTag {

   my ($tag) = @_;;

   # All the .CLEAR must be separated tags to help with the tag ordering. That
   # is, we need to make sure the .CLEAR is ordered before the normal tag.  If
   # the .CLEAR version of the tag doesn't exist, we do not change the tag
   # name but we give a warning.

   my $clearTag    = $tag->id . ':.CLEAR';
   my $clearAllTag = $tag->id . ':.CLEARALL';

   if ( LstTidy::Reformat::isValidTag($tag->lineType, $clearAllTag)) {

      # Don't do the else clause at the bottom

   } elsif ( ! LstTidy::Reformat::isValidTag($tag->lineType, $clearTag )) {

      LstTidy::LogFactory::getLogger->notice(
         q{The tag "} . $clearTag . q{" from "} . $tag->origTag . q{" is not in the } . $tag->lineType . q{ tag list\n},
         $tag->file,
         $tag->line
      );

      LstTidy::Report::incCountInvalidTags($tag->lineType, $clearTag);
      $tag->noMoreErrors(1);

   } else {

      # Its a valid CLEAR tag, move the subTag to id
      $tag->id($clearTag);
      $tag->value($tag->value =~ s/^.CLEAR//ir);

   }
}


=head2 validatePreTag

   Validate the PRExxx tags. This function is reentrant and can be called
   recursivly.

   $tag,             # Name of the tag (before the :)
   $tagValue,        # Value of the tag (after the :)
   $enclosingTag,    # When the PRExxx tag is used in another tag
   $lineType,        # Type for the current file
   $file,            # Name of the current file
   $line             # Number of the current line

   preforms checks that pre tags are valid.

=cut

sub validatePreTag {
   my ($tag, $enclosingTag) = @_;

   if ( !length($tag->value) && $tag->id ne "PRE:.CLEAR" ) {
      missingValue();
      return;
   }

   LstTidy::LogFactory::getLogger()->debug(
      q{validatePreTag: } . $tag->id . q{; } . $tag->value . q{; } . $enclosingTag .q{; } . $tag->lineType .q{;},
      $tag->file,
      $tag->line
   );

   if ( $tag->id eq 'PRECLASS' || $tag->id eq 'PRECLASSLEVELMAX' ) {

      processGenericPRE('CLASS', $tag, $enclosingTag);

   } elsif ( $tag->id eq 'PRECHECK' || $tag->id eq 'PRECHECKBASE') {

      processPRECHECK ($tag->id, $enclosingTag);

   } elsif ( $tag->id eq 'PRECSKILL' ) {

      processGenericPRE('SKILL', $tag, $enclosingTag);

   } elsif ( $tag->id eq 'PREDEITY' ) {

      processPREDIETY($tag);

   } elsif ( $tag->id eq 'PREDEITYDOMAIN' || $tag->id eq 'PREDOMAIN' ) {

      processGenericPRE('DOMAIN', $tag, $enclosingTag);

   } elsif ( $tag->id eq 'PREFEAT' ) {

      processGenericPRE('FEAT', $tag, $enclosingTag);

   } elsif ( $tag->id eq 'PREABILITY' ) {

      processGenericPRE('ABILITY', $tag, $enclosingTag);

   } elsif ( $tag->id eq 'PREITEM' ) {

      processGenericPRE('EQUIPMENT', $tag, $enclosingTag);

   } elsif ( $tag->id eq 'PRELANG' ) {

      processPRELANG($tag, $enclosingTag);

   } elsif ( $tag->id eq 'PREMOVE' ) {

      processPREMOVE($tag, $enclosingTag);

   } elsif ( $tag->id eq 'PREMULT' ) {

      # This tag is the reason why validatePreTag exists
      # PREMULT:x,[PRExxx 1],[PRExxx 2]
      # We need for find all the [] and call validatePreTag with the content

      processPREMULT($tag, $enclosingTag);

   } elsif ( $tag->id eq 'PRERACE' ) {

      processPRERACE($tag, $enclosingTag);

   }
   elsif ( $tag->id eq 'PRESKILL' ) {

      processGenericPRE('SKILL', $tag, $enclosingTag);

   } elsif ( $tag->id eq 'PRESPELL' ) {

      processPRESPELL($tag, $enclosingTag);

   } elsif ( $tag->id eq 'PREVAR' ) {

      processPREVAR($tag, $enclosingTag);

   }

   # No Check for Variable File #

   # Check for PRExxx that do not exist. We only check the
   # tags that are embeded since parse_tag already took care
   # of the PRExxx tags on the entry lines.
   elsif ( $enclosingTag && !exists $PreTags{$tag->id} ) {

      LstTidy::LogFactory::getLogger()->notice(
         qq{Unknown PRExxx tag "} . $tag->id . q{" found in "$enclosingTag"},
         $tag->file,
         $tag->line
      );
   }
}


###############################################################
# validateTag
# ------------
#
# This function stores data for later validation. It also checks
# the syntax of certain tags and detects common errors and
# deprecations.
#
# The %referrer hash must be populated following this format
# $referrer{$lintype}{$name} = [ $err_desc, $file, $line ]

sub validateTag {

   my ($tag) = @_;

   my $logger = LstTidy::LogFactory::getLogger();

   if ($tag->id eq 'STARTPACK')
   {
      LstTidy::Validate::setEntityValid('KIT STARTPACK', "KIT:" . $tag->value);
      LstTidy::Validate::setEntityValid('KIT', "KIT:" . $tag->value);

   } elsif ( $tag->id =~ /^\!?PRE/ ) {

      # It's a PRExxx tag, we delegate
      return LstTidy::Validate::validatePreTag( $tag, "");

   } elsif (index( $tag->id, 'PROFICIENCY' ) == 0 ) {

   } elsif ( index( $tag->id, 'BONUS' ) == 0 ) {

      validateBonusTag($tag);

   } elsif ( $tag->id eq 'CLASSES' || $tag->id eq 'DOMAINS' ) {

                if ( $tag->lineType eq 'SPELL' ) {
                        my %seen;
                        my $tag_to_check = $tag->id eq 'CLASSES' ? 'CLASS' : 'DOMAIN';

                        # First we find all the classes used
                        for my $level ( split '\|', $tag->value ) {
                                if ( $level =~ /(.*)=(\d+)/ ) {
                                for my $entity ( split ',', $1 ) {

                                        # [ 849365 ] CLASSES:ALL
                                        # CLASSES:ALL is OK
                                        # Arcane and Divine are not really OK but they are used
                                        # as placeholders for use in the MSRD.
                                        if ((  $tag_to_check eq "CLASS"
                                                && (   $entity ne "ALL"
                                                        && $entity ne "Arcane"
                                                        && $entity ne "Divine" )
                                                )
                                                || $tag_to_check eq "DOMAIN"
                                                )
                                        {
                                                push @LstTidy::Report::xcheck_to_process,
                                                [
                                                $tag_to_check,
                                                $tag->id,
                                                $tag->file,
                                                $tag->line,
                                                $entity
                                                ];

                                                if ( $seen{$entity}++ ) {
                                                $logger->notice(
                                                        qq{"$entity" found more then once in } . $tag->id,
                                                        $tag->file,
                                                        $tag->line
                                                );
                                                }
                                        }
                                }
                                }
                                else {
                                        if ( $tag->id . ":$level" eq 'CLASSES:.CLEARALL' ) {
                                                # Nothing to see here. Move on.
                                        }
                                        else {
                                                $logger->warning(
                                                        qq{Missing "=level" after "} . $tag->id . ":$level",
                                                        $tag->file,
                                                        $tag->line
                                                );
                                        }
                                }
                        }
                }
                elsif ( $tag->lineType eq 'SKILL' ) {

                        # Only CLASSES in SKILL
                        CLASS_FOR_SKILL:
                        for my $class ( split '\|', $tag->value ) {

                                # ALL is valid here
                                next CLASS_FOR_SKILL if $class eq 'ALL';

                                push @LstTidy::Report::xcheck_to_process,
                                [
                                'CLASS',
                                $tag->id,
                                $tag->file,
                                $tag->line,
                                $class
                                ];
                        }
                }
                elsif (   $tag->lineType eq 'DEITY' ) {
                        # Only DOMAINS in DEITY
                        if ($tag->value =~ /\|/ ) {
                           $tag->value(substr($tag->value, 0, rindex($tag->value, "\|")));
                        }
                        DOMAIN_FOR_DEITY:
                        for my $domain ( split ',', $tag->value ) {

                                # ALL is valid here
                                next DOMAIN_FOR_DEITY if $domain eq 'ALL';

                                push @LstTidy::Report::xcheck_to_process,
                                [
                                'DOMAIN',
                                $tag->id,
                                $tag->file,
                                $tag->line,
                                $domain
                                ];
                        }
                }
                }
                elsif ( $tag->id eq 'CLASS'
                        && $tag->lineType ne 'PCC'
                ) {
                # Note: The CLASS linetype doesn't have any CLASS tag, it's
                #               called 000ClassName internaly. CLASS is a tag used
                #               in other line types like KIT CLASS.
                # CLASS:<class name>,<class name>,...[BASEAGEADD:<dice expression>]

                # We remove and ignore [BASEAGEADD:xxx] if present
                my $list_of_class = $tag->value;
                $list_of_class =~ s{ \[ BASEAGEADD: [^]]* \] }{}xmsg;

                push @LstTidy::Report::xcheck_to_process,
                        [
                                'CLASS',
                                $tag->id,
                                $tag->file,
                                $tag->line,
                                (split /[|,]/, $list_of_class),
                        ];
                }
                elsif ( $tag->id eq 'DEITY'
                        && $tag->lineType ne 'PCC'
                ) {
                # DEITY:<deity name>|<deity name>|etc.
                push @LstTidy::Report::xcheck_to_process,
                        [
                                'DEITY',
                                $tag->id,
                                $tag->file,
                                $tag->line,
                                (split /[|]/, $tag->value),
                        ];
                }
                elsif ( $tag->id eq 'DOMAIN'
                        && $tag->lineType ne 'PCC'
                ) {
                # DOMAIN:<domain name>|<domain name>|etc.
                push @LstTidy::Report::xcheck_to_process,
                        [
                                'DOMAIN',
                                $tag->id,
                                $tag->file,
                                $tag->line,
                                (split /[|]/, $tag->value),
                        ];
                }
                elsif ( $tag->id eq 'ADDDOMAINS' ) {

                # ADDDOMAINS:<domain1>.<domain2>.<domain3>. etc.
                push @LstTidy::Report::xcheck_to_process,
                        [
                        'DOMAIN',
                        $tag->id,
                        $tag->file,
                        $tag->line,
                        split '\.', $tag->value
                        ];
                }
                elsif ( $tag->id eq 'ADD:SPELLCASTER' ) {

                # ADD:SPELLCASTER(<list of classes>)<formula>
                if ( $tag->value =~ /\((.*)\)(.*)/ ) {
                        my ( $list, $formula ) = ( $1, $2 );

                        # First the list of classes
                        # ANY, ARCANA, DIVINE and PSIONIC are spcial hardcoded cases for
                        # the ADD:SPELLCASTER tag.
                        push @LstTidy::Report::xcheck_to_process, [
                                'CLASS',
                                qq{@@" in "} . $tag->fullTag,
                                $tag->file,
                                $tag->line,
                                grep {
                                           uc($_) ne 'ANY'
                                        && uc($_) ne 'ARCANE'
                                        && uc($_) ne 'DIVINE'
                                        && uc($_) ne 'PSIONIC'
                                }
                                split ',', $list
                        ];

                        # Second, we deal with the formula
                        push @LstTidy::Report::xcheck_to_process,
                                [
                                'DEFINE Variable',
                                qq{@@" from "$formula" in "} . $tag->fullTag,
                                $tag->file,
                                $tag->line,
                                LstTidy::Parse::extractVariables($formula, $tag)
                                ];
                }
                else {
                        $logger->notice(
                                qq{Invalid syntax: "} . $tag->fullTag . q{"},
                                $tag->file,
                                $tag->line
                        );
                }
                }
                elsif ( $tag->id eq 'ADD:EQUIP' ) {

                # ADD:EQUIP(<list of equipments>)<formula>
                if ( $tag->value =~ m{ [(]   # Opening brace
                                                (.*)  # Everything between braces include other braces
                                                [)]   # Closing braces
                                                (.*)  # The rest
                                                }xms ) {
                        my ( $list, $formula ) = ( $1, $2 );

                        # First the list of equipements
                        # ANY is a spcial hardcoded cases for ADD:EQUIP
                        push @LstTidy::Report::xcheck_to_process,
                                [
                                'EQUIPMENT',
                                qq{@@" in "} . $tag->fullTag,
                                $tag->file,
                                $tag->line,
                                grep { uc($_) ne 'ANY' } split ',', $list
                                ];

                        # Second, we deal with the formula
                        push @LstTidy::Report::xcheck_to_process,
                                [
                                'DEFINE Variable',
                                qq{@@" from "$formula" in "} . $tag->fullTag,
                                $tag->file,
                                $tag->line,
                                LstTidy::Parse::extractVariables($formula, $tag)
                                ];
                }
                else {
                        $logger->notice(
                                qq{Invalid syntax: "} . $tag->fullTag . q{"},
                                $tag->file,
                                $tag->line
                        );
                }
                }
                elsif ($tag->id eq 'EQMOD'
                || $tag->id eq 'IGNORES'
                || $tag->id eq 'REPLACES'
                || ( $tag->id =~ /!?PRETYPE/ && $tag->value =~ /(\d+,)?EQMOD=/ )
                ) {

                # This section check for any reference to an EQUIPMOD key
                if ( $tag->id eq 'EQMOD' ) {

                        # The higher level for the EQMOD is the . (who's the genius who
                        # dreamed that up...
                        my @key_list = split '\.', $tag->value;

                        # The key name is everything found before the first |
                        for $_ (@key_list) {
                                my ($key) = (/^([^|]*)/);
                                if ($key) {

                                # To be processed later
                                push @LstTidy::Report::xcheck_to_process,
                                        [
                                        'EQUIPMOD Key',
                                        qq{@@" in "} . $tag->fullTag,
                                        $tag->file,
                                        $tag->line,
                                        $key
                                        ];
                                }
                                else {
                                $logger->warning(
                                        qq{Cannot find the key for "$_" in "} . $tag->fullTag . q{"},
                                        $tag->file,
                                        $tag->line
                                );
                                }
                        }
                }
                elsif ( $tag->id eq "IGNORES" || $tag->id eq "REPLACES" ) {

                        # Comma separated list of KEYs
                        # To be processed later
                        push @LstTidy::Report::xcheck_to_process,
                                [
                                'EQUIPMOD Key',
                                qq{@@" in "} . $tag->fullTag,
                                $tag->file,
                                $tag->line,
                                split ',', $tag->value
                                ];
                }
                }
                elsif (
                $tag->lineType ne 'PCC'
                && (   $tag->id eq 'ADD:FEAT'
                        || $tag->id eq 'AUTO:FEAT'
                        || $tag->id eq 'FEAT'
                        || $tag->id eq 'FEATAUTO'
                        || $tag->id eq 'VFEAT'
                        || $tag->id eq 'MFEAT' )
                )
                {
                my @feats;
                my $parent = 0;

                # ADD:FEAT(feat,feat,TYPE=type)formula
                # FEAT:feat|feat|feat(xxx)
                # FEAT:feat,feat,feat(xxx)  in the TEMPLATE and DOMAIN
                # FEATAUTO:feat|feat|...
                # VFEAT:feat|feat|feat(xxx)|PRExxx:yyy
                # MFEAT:feat|feat|feat(xxx)|...
                # All these type may have embeded [PRExxx tags]
                if ( $tag->id eq 'ADD:FEAT' ) {
                        if ( $tag->value =~ /^\((.*)\)(.*)?$/ ) {
                                $parent = 1;
                                my $formula = $2;

                                # The ADD:FEAT list may contains list elements that
                                # have () and will need the special split.
                                # The LIST special feat name is valid in ADD:FEAT
                                # So is ALL now.
                                @feats = grep { $_ ne 'LIST' } grep { $_ ne 'ALL' } embedded_coma_split($1);

                                #               # We put the , back in place
                                #               s/&comma;/,/g for @feats;

                                # Here we deal with the formula part
                                if ($formula) {
                                   push @LstTidy::Report::xcheck_to_process,
                                   [
                                      'DEFINE Variable',
                                      qq{@@" in "} . $tag->fullTag,
                                      $tag->file,
                                      $tag->line,
                                      LstTidy::Parse::extractVariables($formula, $tag)
                                   ]
                                }
                        }
                        else {
                                $logger->notice(
                                qq{Invalid syntax: "} . $tag->fullTag . q{"},
                                $tag->file,
                                $tag->line
                                ) if $tag->value;
                        }
                }
                elsif ( $tag->id eq 'FEAT' ) {

                        # FEAT tags sometime use , and sometime use | as separator.

                        # We can now safely split on the ,
                        @feats = embedded_coma_split( $tag->value, qr{,|\|} );

                        #       # We put the , back in place
                        #       s/&coma;/,/g for @feats;
                }
                else {
                        @feats = split '\|', $tag->value;
                }

                FEAT:
                for my $feat (@feats) {

                        # If it is a PRExxx tag section, we validate the PRExxx tag.
                        if ( $tag->id eq 'VFEAT' && $feat =~ /^(!?PRE[A-Z]+):(.*)/ ) {

                           my $preTag = $tag->clone(id => $1, value => $2);
                           validatePreTag($preTag, $tag->fullRealTag);

                           $feat = "";
                           next FEAT;
                        }

                        # We strip the embeded [PRExxx ...] tags
                        if ( $feat =~ /([^[]+)\[(!?PRE[A-Z]*):(.*)\]$/ ) {

                           $feat = $1;

                           my $preTag = $tag->clone(id => $2, value => $3);
                           validatePreTag($preTag, $tag->fullRealTag);
                        }

                }

                my $message_format = $tag->id;
                if ($parent) {
                        $message_format = $tag->id . "(@@)";
                }

                # To be processed later
                push @LstTidy::Report::xcheck_to_process,
                        [ 'FEAT', $message_format, $tag->file, $tag->line, @feats ];
                }
                elsif ( $tag->id eq 'KIT' && $tag->lineType ne 'PCC' ) {
                # KIT:<number of choice>|<kit name>|<kit name>|etc.
                # KIT:<kit name>
                my @kit_list = split /[|]/, $tag->value;

                # The first item might be a number
                if ( $kit_list[0] =~ / \A \d+ \z /xms ) {
                        # We discard the number
                        shift @kit_list;
                }

                push @LstTidy::Report::xcheck_to_process,
                        [
                                'KIT STARTPACK',
                                $tag->id,
                                $tag->file,
                                $tag->line,
                                @kit_list,
                        ];
                }
                elsif ( $tag->id eq 'LANGAUTOxxx' || $tag->id eq 'LANGBONUS' ) {

                # To be processed later
                # The ALL keyword is removed here since it is not usable everywhere there are language
                # used.
                push @LstTidy::Report::xcheck_to_process,
                        [
                        'LANGUAGE',
                        $tag->id,
                        $tag->file,
                        $tag->line,
                        grep { $_ ne 'ALL' } split ',', $tag->value
                        ];
                }
                elsif ( $tag->id eq 'ADD:LANGUAGE' ) {

                        # Syntax: ADD:LANGUAGE(<coma separated list of languages)<number>
                        if ( $tag->value =~ /\((.*)\)/ ) {
                                push @LstTidy::Report::xcheck_to_process,
                                        [
                                        'LANGUAGE', 'ADD:LANGUAGE(@@)', $tag->file, $tag->line, split ',',  $1
                                        ];
                        }
                        else {
                                $logger->notice(
                                        qq{Invalid syntax "} . $tag->fullTag . q{"},
                                        $tag->file,
                                        $tag->line
                                );
                        }
                }
                elsif ( $tag->id eq 'MOVE' ) {

                        # MOVE:<move type>,<value>
                        # ex. MOVE:Walk,30,Fly,20,Climb,10,Swim,10

                        my @list = split ',', $tag->value;

                        MOVE_PAIR:
                        while (@list) {
                                my ( $type, $value ) = ( splice @list, 0, 2 );
                                $value = "" if !defined $value;

                                # $type should be a word and $value should be a number
                                if ( $type =~ /^\d+$/ ) {
                                        $logger->notice(
                                        qq{I was expecting a move type where I found "$type" in "} . $tag->fullTag . q{"},
                                        $tag->file,
                                        $tag->line
                                        );
                                        last;
                                }
                                else {

                                        # We keep the move type for future validation
                                        LstTidy::Validate::setEntityValid('MOVE Type', $type);
                                }

                                unless ( $value =~ /^\d+$/ ) {
                                        $logger->notice(
                                        qq{I was expecting a number after "$type" and found "$value" in "} . $tag->fullTag . q{"},
                                        $tag->file,
                                        $tag->line
                                        );
                                        last MOVE_PAIR;
                                }
                        }
                }
                elsif ( $tag->id eq 'MOVECLONE' ) {
                # MOVECLONE:A,B,formula  A and B must be valid move types.
                        if ( $tag->value =~ /^(.*),(.*),(.*)/ ) {
                                # Error if more parameters (Which will show in the first group)
                                if ( $1 =~ /,/ ) {
                                        $logger->warning(
                                        qq{Found too many parameters in "} . $tag->fullTag . q{"},
                                        $tag->file,
                                        $tag->line
                                        );
                                }
                                else {
                                        # Cross check for used MOVE Types.
                                        push @LstTidy::Report::xcheck_to_process,
                                                [
                                                'MOVE Type',
                                                $tag->id,
                                                $tag->file,
                                                $tag->line,
                                                $1,
                                                $2
                                                ];
                                }
                        }
                        else {
                                # Report missing requisite parameters.
                                $logger->warning(
                                qq{Missing a parameter in in "} . $tag->fullTag . q{"},
                                $tag->file,
                                $tag->line
                                );
                        }


                }
                elsif ( $tag->id eq 'RACE' && $tag->lineType ne 'PCC' ) {
                # There is only one race per RACE tag
                push @LstTidy::Report::xcheck_to_process,
                        [  'RACE',
                                $tag->id,
                                $tag->file,
                                $tag->line,
                                $tag->value,
                        ];
                }
                elsif ( $tag->id eq 'SWITCHRACE' ) {

                # To be processed later
                # Note: SWITCHRACE actually switch the race TYPE
                push @LstTidy::Report::xcheck_to_process,
                        [   'RACE TYPE',
                                $tag->id,
                                $tag->file,
                                $tag->line,
                                (split '\|',  $tag->value),
                        ];
                }
                elsif ( $tag->id eq 'CSKILL'
                        || $tag->id eq 'CCSKILL'
                        || $tag->id eq 'MONCSKILL'
                        || $tag->id eq 'MONCCSKILL'
                        || ($tag->id eq 'SKILL' && $tag->lineType ne 'PCC')
                ) {
                my @skills = split /[|]/, $tag->value;

                # ALL is a valid use in BONUS:SKILL, xCSKILL  - [ 1593872 ] False warning: No SKILL entry for CSKILL:ALL
                @skills = grep { $_ ne 'ALL' } @skills;

                # We need to filter out %CHOICE for the SKILL tag
                if ( $tag->id eq 'SKILL' ) {
                        @skills = grep { $_ ne '%CHOICE' } @skills;
                }

                # To be processed later
                push @LstTidy::Report::xcheck_to_process,
                        [   'SKILL',
                                $tag->id,
                                $tag->file,
                                $tag->line,
                                @skills,
                        ];
                }
                elsif ( $tag->id eq 'ADD:SKILL' ) {

                # ADD:SKILL(<list of skills>)<formula>
                if ( $tag->value =~ /\((.*)\)(.*)/ ) {
                        my ( $list, $formula ) = ( $1, $2 );

                        # First the list of skills
                        # ANY is a spcial hardcoded cases for ADD:EQUIP
                        push @LstTidy::Report::xcheck_to_process,
                                [
                                'SKILL',
                                qq{@@" in "} . $tag->fullTag,
                                $tag->file,
                                $tag->line,
                                grep { uc($_) ne 'ANY' } split ',', $list
                                ];

                        # Second, we deal with the formula
                        push @LstTidy::Report::xcheck_to_process,
                                [
                                'DEFINE Variable',
                                qq{@@" from "$formula" in "} . $tag->fullTag,
                                $tag->file,
                                $tag->line,
                                LstTidy::Parse::extractVariables($formula, $tag)
                                ];
                }
                else {
                        $logger->notice(
                                qq{Invalid syntax: "} . $tag->fullTag . q{"},
                                $tag->file,
                                $tag->line
                        );
                }
                }
                elsif ( $tag->id eq 'SPELLS' ) {
                if ( $tag->lineType ne 'KIT SPELLS' ) {
 # Syntax: SPELLS:<spellbook>|[TIMES=<times per day>|][TIMEUNIT=<unit of time>|][CASTERLEVEL=<CL>|]<Spell list>[|<prexxx tags>]
 # <Spell list> = <Spell name>,<DC> [|<Spell list>]
                        my @list_of_param = split '\|', $tag->value;
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
#                                               $param =~ s/TIMES=-1/TIMES=ATWILL/g;   # SPELLS:xxx|TIMES=-1 to SPELLS:xxx|TIMES=ATWILL conversion
                                                $AtWill_Flag = $param =~ /TIMES=ATWILL/;
                                                $nb_times++;
                                                push @LstTidy::Report::xcheck_to_process,
                                                [
                                                   'DEFINE Variable',
                                                   qq{@@" in "} . $tag->fullTag,
                                                   $tag->file,
                                                   $tag->line,
                                                   LstTidy::Parse::extractVariables($2, $tag)
                                                ];

                                        } elsif ( $1 eq 'TIMEUNIT' ) {
                                                $nb_timeunit++;
                                                # Is it a valid alignment?
                                                if (! LstTidy::Parse::isValidFixedValue($1, $2)) {
                                                   $logger->notice(
                                                      qq{Invalid value "$2" for tag "$1"},
                                                      $tag->file,
                                                      $tag->line
                                                   );
#                                                       $is_valid = 0;
                                                }

                                        } else {
                                                $nb_casterlevel++;
                                                push @LstTidy::Report::xcheck_to_process,
                                                [
                                                   'DEFINE Variable',
                                                   qq{@@" in "} . $tag->fullTag,
                                                   $tag->file,
                                                   $tag->line,
                                                   LstTidy::Parse::extractVariables($2, $tag)
                                                ];
                                        }

                                # Embeded PRExxx tags
                                } elsif ( $param =~ /^(PRE[A-Z]+):(.*)/ ) {

                                   my $preTag = $tag->clone(id => $1, value => $2);
                                   validatePreTag($preTag, $tag->fullRealTag);

                                } else {

                                my ( $spellname, $dc ) = ( $param =~ /([^,]+),(.*)/ );

                                if ($dc) {

                                        # Spell name must be validated with the list of spells and DC is a formula
                                        push @spells, $spellname;

                                        push @LstTidy::Report::xcheck_to_process,
                                                [
                                                'DEFINE Variable',
                                                qq{@@" in "} . $tag->fullTag,
                                                $tag->file,
                                                $tag->line,
                                                LstTidy::Parse::extractVariables($dc, $tag)
                                                ];
                                }
                                else {

                                        # No DC present, the whole param is the spell name
                                        push @spells, $param;

                                        $logger->info(
                                                qq{the DC value is missing for "$param" in "} . $tag->fullTag . q{"},
                                                $tag->file,
                                                $tag->line
                                        );
                                }
                                }
                        }

                        push @LstTidy::Report::xcheck_to_process,
                                [
                                'SPELL',
                                $tag->id,
                                $tag->file,
                                $tag->line,
                                @spells
                                ];

                        # Validate the number of TIMES, TIMEUNIT, and CASTERLEVEL parameters
                        if ( $nb_times != 1 ) {
                                if ($nb_times) {
                                        $logger->notice(
                                                qq{TIMES= should not be used more then once in "} . $tag->fullTag . q{"},
                                                $tag->file,
                                                $tag->line
                                        );
                                }
                                else {
                                        $logger->info(
                                                qq{the TIMES= parameter is missing in "} . $tag->fullTag . q{"},
                                                $tag->file,
                                                $tag->line
                                        );
                                }
                        }

                        if ( $nb_timeunit != 1 ) {
                                if ($nb_timeunit) {
                                        $logger->notice(
                                                qq{TIMEUNIT= should not be used more then once in "} . $tag->fullTag . q{"},
                                                $tag->file,
                                                $tag->line
                                        );
                                }
                                else {
                                        if ( $AtWill_Flag ) {
                                                # Do not need a TIMEUNIT tag if the TIMES tag equals AtWill
                                                # Nothing to see here. Move along.
                                        }
                                        else {
                                                # [ 1997408 ] False positive: TIMEUNIT= parameter is missing
                                                # $logger->info(
                                                #       qq{the TIMEUNIT= parameter is missing in "} . $tag->fullTag . q{"},
                                                #       $tag->file,
                                                #       $tag->line
                                                # );
                                        }
                                }
                        }

                        if ( $nb_casterlevel != 1 ) {
                                if ($nb_casterlevel) {
                                $logger->notice(
                                        qq{CASTERLEVEL= should not be used more then once in "} . $tag->fullTag . q{"},
                                        $tag->file,
                                        $tag->line
                                );
                                }
                                else {
                                $logger->info(
                                        qq{the CASTERLEVEL= parameter is missing in "} . $tag->fullTag . q{"},
                                        $tag->file,
                                        $tag->line
                                );
                                }
                        }
                }
                else {
                        # KIT SPELLS line type
                        # SPELLS:<parameter list>|<spell list>
                        # <parameter list> = <param id> = <param value { | <parameter list> }
                        # <spell list> := <spell name> { = <number> } { | <spell list> }
                        my @spells = ();

                        for my $spell_or_param (split q{\|}, $tag->value) {
                                # Is it a parameter?
                                if ( $spell_or_param =~ / \A ([^=]*) = (.*) \z/xms ) {
                                my ($param_id,$param_value) = ($1,$2);

                                if ( $param_id eq 'CLASS' ) {
                                        push @LstTidy::Report::xcheck_to_process,
                                                [
                                                'CLASS',
                                                qq{@@" in "} . $tag->fullTag,
                                                $tag->file,
                                                $tag->line,
                                                $param_value,
                                                ];

                                }
                                elsif ( $param_id eq 'SPELLBOOK') {
                                        # Nothing to do
                                }
                                elsif ( $param_value =~ / \A \d+ \z/mxs ) {
                                        # It's a spell after all...
                                        push @spells, $param_id;
                                }
                                else {
                                        $logger->notice(
                                                qq{Invalide SPELLS parameter: "$spell_or_param" found in "} . $tag->fullTag . q{"},
                                                $tag->file,
                                                $tag->line
                                        );
                                }
                                }
                                else {
                                # It's a spell
                                push @spells, $spell_or_param;
                                }
                        }

                        if ( scalar @spells ) {
                                push @LstTidy::Report::xcheck_to_process,
                                        [
                                        'SPELL',
                                        $tag->id,
                                        $tag->file,
                                        $tag->line,
                                        @spells,
                                        ];
                        }
                }
                }
                elsif ( index( $tag->id, 'SPELLLEVEL:' ) == 0
                        || index( $tag->id, 'SPELLKNOWN:' ) == 0
                ) {

                # [ 813504 ] SPELLLEVEL:DOMAIN in domains.lst
                # [ 2544134 ] New Token - SPELLKNOWN
                # -------------------------------------------
                # There are two different SPELLLEVEL tags that must
                # be x-check. SPELLLEVEL:CLASS and SPELLLEVEL:DOMAIN.
                #
                # The CLASS type have CLASSes and SPELLs to check and
                # the DOMAIN type have DOMAINs and SPELLs to check.
                #
                # SPELLKNOWN has exact same syntax as SPELLLEVEL, so doing both checks at once.

                if ( $tag->id eq "SPELLLEVEL:CLASS"
                        || $tag->id eq "SPELLKNOWN:CLASS"
                ) {

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

                        # [ 1958872 ] trim PRExxx before checking SPELLLEVEL
                        # Work with a copy because we do not want to change the original
                        my $tag_line = $tag->value;
                        study $tag_line;
                        # Remove the PRExxx tags at the end of the line.
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
                                                        push @LstTidy::Report::xcheck_to_process,
                                                        [
                                                        'CLASS',
                                                        qq{@@" in "} . $tag->fullTag,
                                                        $tag->file,
                                                        $tag->line,
                                                        $1
                                                        ];
                                                }
                                                else {
                                                        $logger->notice(
                                                                qq{Invalid syntax for "$class" in "} . $tag->fullTag . q{"},
                                                                $tag->file,
                                                                $tag->line
                                                        );
                                                }

                                                # The SPELL names
                                                # To be processed later
                                                push @LstTidy::Report::xcheck_to_process,
                                                        [
                                                        'SPELL',
                                                        qq{@@" in "} . $tag->fullTag,
                                                        $tag->file,
                                                        $tag->line,
                                                        split ',', $spells
                                                        ];
                                        }
                                        else {
                                                $logger->notice(
                                                        qq{Invalid class/spell list paring in "} . $tag->fullTag . q{"},
                                                        $tag->file,
                                                        $tag->line
                                                );
                                                $working_value = "";
                                        }
                                }
                        }
                        else {
                                $logger->notice(
                                qq{No value found for "} . $tag->id . q{"},
                                $tag->file,
                                $tag->line
                                );
                        }
                }
                if ( $tag->id eq "SPELLLEVEL:DOMAIN"
                        || $tag->id eq "SPELLKNOWN:DOMAIN"
                ) {

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
                        if ( my $working_value = $tag->value ) {
                                while ($working_value) {
                                if ( $working_value =~ s/\|([^|]+)\|([^|]+)// ) {
                                        my $domain = $1;
                                        my $spells = $2;

                                        # The DOMAIN
                                        if ( $domain =~ /([^=]+)\=(\d+)/ ) {
                                                push @LstTidy::Report::xcheck_to_process,
                                                [
                                                'DOMAIN',
                                                qq{@@" in "} . $tag->fullTag,
                                                $tag->file,
                                                $tag->line,
                                                $1
                                                ];
                                        }
                                        else {
                                                $logger->notice(
                                                qq{Invalid syntax for "$domain" in "} . $tag->fullTag . q{"},
                                                $tag->file,
                                                $tag->line
                                                );
                                        }

                                        # The SPELL names
                                        # To be processed later
                                        push @LstTidy::Report::xcheck_to_process,
                                                [
                                                'SPELL',
                                                qq{@@" in "} . $tag->fullTag,
                                                $tag->file,
                                                $tag->line,
                                                split ',', $spells
                                                ];
                                }
                                else {
                                        $logger->notice(
                                                qq{Invalid domain/spell list paring in "} . $tag->fullTag . q{"},
                                                $tag->file,
                                                $tag->line
                                        );
                                        $working_value = "";
                                }
                                }
                        }
                        else {
                                $logger->notice(
                                qq{No value found for "} . $tag->id . q{"},
                                $tag->file,
                                $tag->line
                                );
                        }
                }
                }
                elsif ( $tag->id eq 'STAT' ) {
                if ( $tag->lineType eq 'KIT STAT' ) {
                        # STAT:STR=17|DEX=10|CON=14|INT=8|WIS=12|CHA=14
                        my %stat_count_for = map { $_ => 0 } @{LstTidy::Parse::getValidSystemArr('stats')};

                        STAT:
                        for my $stat_expression (split /[|]/, $tag->value) {
                                my ($stat) = ( $stat_expression =~ / \A ([A-Z]{3}) [=] (\d+|roll\(\"\w+\"\)((\+|\-)var\(\"STAT.*\"\))*) \z /xms );
                                if ( !defined $stat ) {
                                # Syntax error
                                $logger->notice(
                                        qq{Invalid syntax for "$stat_expression" in "} . $tag->fullTag . q{"},
                                        $tag->file,
                                        $tag->line
                                );

                                next STAT;
                                }

                                if ( !exists $stat_count_for{$stat} ) {
                                # The stat is not part of the official list
                                $logger->notice(
                                        qq{Invalid attribute name "$stat" in "} . $tag->fullTag . q{"},
                                        $tag->file,
                                        $tag->line
                                );
                                }
                                else {
                                $stat_count_for{$stat}++;
                                }
                        }

                        # We check to see if some stat are repeated
                        for my $stat ( @{LstTidy::Parse::getValidSystemArr('stats')}) {
                                if ( $stat_count_for{$stat} > 1 ) {
                                $logger->notice(
                                        qq{Found $stat more then once in "} . $tag->fullTag . q{"},
                                        $tag->file,
                                        $tag->line
                                );
                                }
                        }
                }
                }
                elsif ( $tag->id eq 'TEMPLATE' && $tag->lineType ne 'PCC' ) {
                # TEMPLATE:<template name>|<template name>|etc.
                push @LstTidy::Report::xcheck_to_process,
                        [  'TEMPLATE',
                                $tag->id,
                                $tag->file,
                                $tag->line,
                                (split /[|]/, $tag->value),
                        ];
                }
                ######################################################################
                # Here we capture data for later validation
                elsif ( $tag->id eq 'RACESUBTYPE' ) {
                for my $race_subtype (split /[|]/, $tag->value) {
                        my $new_race_subtype = $race_subtype;
                        if ( $tag->lineType eq 'RACE' ) {
                                # The RACE sub-type are created in the RACE file
                                if ( $race_subtype =~ m{ \A [.] REMOVE [.] }xmsi ) {
                                # The presence of a remove means that we are trying
                                # to modify existing data and not create new one
                                push @LstTidy::Report::xcheck_to_process,
                                        [  'RACESUBTYPE',
                                                $tag->id,
                                                $tag->file,
                                                $tag->line,
                                                $race_subtype,
                                        ];
                                }
                                else {
                                   LstTidy::Validate::setEntityValid('RACESUBTYPE', $race_subtype);
                                }
                        }
                        else {
                                # The RACE type found here are not create, we only
                                # get rid of the .REMOVE. part
                                $race_subtype =~ m{ \A [.] REMOVE [.] }xmsi;

                                push @LstTidy::Report::xcheck_to_process,
                                        [  'RACESUBTYPE',
                                        $tag->id,
                                        $tag->file,
                                        $tag->line,
                                        $race_subtype,
                                ];
                        }
                }
                }
                elsif ( $tag->id eq 'RACETYPE' ) {
                for my $race_type (split /[|]/, $tag->value) {
                        if ( $tag->lineType eq 'RACE' ) {
                                # The RACE type are created in the RACE file
                                if ( $race_type =~ m{ \A [.] REMOVE [.] }xmsi ) {
                                # The presence of a remove means that we are trying
                                # to modify existing data and not create new one
                                push @LstTidy::Report::xcheck_to_process,
                                        [  'RACETYPE',
                                                $tag->id,
                                                $tag->file,
                                                $tag->line,
                                                $race_type,
                                        ];
                                }
                                else {
                                   LstTidy::Validate::setEntityValid('RACETYPE', $race_type);
                                }
                        }
                        else {
                                # The RACE type found here are not create, we only
                                # get rid of the .REMOVE. part
                                $race_type =~ m{ \A [.] REMOVE [.] }xmsi;

                                push @LstTidy::Report::xcheck_to_process,
                                        [  'RACETYPE',
                                        $tag->id,
                                        $tag->file,
                                        $tag->line,
                                        $race_type,
                                ];
                        }
                }
                }
                elsif ( $tag->id eq 'TYPE' ) {
                        # The types go into validTypes
                        $validTypes{$tag->lineType}{$_}++ for ( split '\.', $tag->value );
                }
                elsif ( $tag->id eq 'CATEGORY' ) {
                        # The categories go into validCategories
                        $validCategories{$tag->lineType}{$_}++ for ( split '\.', $tag->value );
                }
                ######################################################################
                # Tag with numerical values
                elsif ( $tag->id eq 'STARTSKILLPTS' || $tag->id eq 'SR') {

                   # These tags should only have a numeribal value
                   push @LstTidy::Report::xcheck_to_process,
                   [
                      'DEFINE Variable',
                      qq{@@" in "} . $tag->fullTag,
                      $tag->file,
                      $tag->line,
                      LstTidy::Parse::extractVariables($tag->value, $tag)
                   ];
                }
                elsif ( $tag->id eq 'DEFINE' ) {
                        my ( $var_name, @formulas ) = split '\|', $tag->value;

                        # First we store the DEFINE variable name
                        if ($var_name) {
                                if ( $var_name =~ /^[a-z][a-z0-9_]*$/i ) {
                                   LstTidy::Validate::setEntityValid('DEFINE Variable', $var_name);

                                        #####################################################
                                        # Export a list of variable names if requested
                                        if ( LstTidy::Options::isConversionActive('Export lists') ) {
                                                my $file = $$tag->file;
                                                $file =~ tr{/}{\\};
                                                LstTidy::Report::printToExportList('VARIABLE', qq{"$var_name","$tag->line","$file"\n});
                                        }

                                }

                                # LOCK.xxx and BASE.xxx are not error (even if they are very ugly)
                                elsif ( $var_name !~ /(BASE|LOCK)\.(STR|DEX|CON|INT|WIS|CHA|DVR)/ ) {
                                        $logger->notice(
                                                qq{Invalid variable name "$var_name" in "} . $tag->fullTag . q{"},
                                                $$tag->file,
                                                $tag->line
                                        );
                                }
                        }
                        else {
                                $logger->notice(
                                        qq{I was not able to find a proper variable name in "} . $tag->fullTag . q{"},
                                        $$tag->file,
                                        $tag->line
                                );
                        }

                        # Second we deal with the formula
                        for my $formula (@formulas) {
                           push @LstTidy::Report::xcheck_to_process,
                           [
                              'DEFINE Variable',
                              qq{@@" in "} . $tag->fullTag,
                              $$tag->file,
                              $tag->line,
                              LstTidy::Parse::extractVariables($formula, $tag)
                           ];
                        }
                }
                elsif ( $tag->id eq 'SA' ) {
                        my ($var_string) = ( $tag->value =~ /[^|]\|(.*)/ );
                        if ($var_string) {
                                FORMULA:
                                for my $formula ( split '\|', $var_string ) {

                                        # Are there any PRE tags in the SA tag.
                                        if ( $formula =~ /(^!?PRE[A-Z]*):(.*)/ ) {

                                           my $preTag = $tag->clone(id => $1, value => $2);
                                           validatePreTag($preTag, $tag->fullRealTag);

                                           next FORMULA;
                                        }

                                        push @LstTidy::Report::xcheck_to_process,
                                        [
                                           'DEFINE Variable',
                                           qq{@@" in "} . $tag->fullTag,
                                           $$tag->file,
                                           $tag->line,
                                           LstTidy::Parse::extractVariables($formula, $tag)
                                        ];
                                }
                        }
                }
                elsif ( $tag->lineType eq 'SPELL' && ( $tag->id eq 'TARGETAREA' || $tag->id eq 'DURATION' || $tag->id eq 'DESC' ) )
                {

                        # Inline f*#king tags.
                        # We need to find CASTERLEVEL between ()
                        my $value = $tag->value;
                        pos $value = 0;

                        FIND_BRACKETS:
                        while ( pos $value < length $value ) {

                           my $result;

                           # Find the first set of ()
                           if ( (($result) = Text::Balanced::extract_bracketed( $value, '()' )) && $result) {

                              # Is there a CASTERLEVEL inside?
                              if ( $result =~ / CASTERLEVEL /xmsi ) {
                                 push @LstTidy::Report::xcheck_to_process,
                                 [
                                    'DEFINE Variable',
                                    qq{@@" in "} . $tag->fullTag,
                                    $$tag->file,
                                    $tag->line,
                                    LstTidy::Parse::extractVariables($result, $tag)
                                 ];
                              }
                           
                           } else {

                              last FIND_BRACKETS;
                           }
                        }
                }
                elsif ( $tag->id eq 'NATURALATTACKS' ) {

                        # NATURALATTACKS:<Natural weapon name>,<List of type>,<attacks>,<damage>|...
                        #
                        # We must make sure that there are always four , separated parameters
                        # between the |.

                        for my $entry ( split '\|', $tag->value ) {
                                my @parameters = split ',', $entry;

                                my $NumberOfParams = scalar @parameters;

                                # must have 4 or 5 parameters
                                if ($NumberOfParams == 5 or $NumberOfParams == 4) {

                                        # If Parameter 5 exists, it must be an SPROP
                                        if (defined $parameters[4]) {
                                                $logger->notice(
                                                        qq{5th parameter should be an SPROP in "NATURALATTACKS:$entry"},
                                                        $$tag->file,
                                                        $tag->line
                                                ) unless $parameters[4] =~ /^SPROP=/;
                                        }

                                        # Parameter 3 is a number
                                        $logger->notice(
                                                qq{3rd parameter should be a number in "NATURALATTACKS:$entry"},
                                                $$tag->file,
                                                $tag->line
                                        ) unless $parameters[2] =~ /^\*?\d+$/;

                                        # Are the types valid EQUIPMENT types?
                                        push @LstTidy::Report::xcheck_to_process,
                                                [
                                                        'EQUIPMENT TYPE', 
                                                        qq{@@" in "} . $tag->id . q{:$entry},
                                                        $$tag->file,  
                                                        $tag->line,
                                                        grep { !$validNaturalAttacksType{$_} } split '\.', $parameters[1]
                                                ];
                                }
                                else {
                                        $logger->notice(
                                                qq{Wrong number of parameter for "NATURALATTACKS:$entry"},
                                                $$tag->file,
                                        $tag->line
                                        );
                                }
                        }
                }
                elsif ( $tag->id eq 'CHANGEPROF' ) {

                # "CHANGEPROF:" <list of weapons> "=" <new prof> { "|"  <list of weapons> "=" <new prof> }*
                # <list of weapons> := ( <weapon> | "TYPE=" <weapon type> ) { "," ( <weapon> | "TYPE=" <weapon type> ) }*

                        for my $entry ( split '\|', $tag->value ) {
                                if ( $entry =~ /^([^=]+)=([^=]+)$/ ) {
                                        my ( $list_of_weapons, $new_prof ) = ( $1, $2 );

                                        # First, the weapons (equipment)
                                        push @LstTidy::Report::xcheck_to_process,
                                                [
                                                        'EQUIPMENT', 
                                                        $tag->id, 
                                                        $$tag->file, 
                                                        $tag->line,
                                                        split ',', $list_of_weapons
                                                ];

                                        # Second, the weapon prof.
                                        push @LstTidy::Report::xcheck_to_process,
                                                [
                                                        'WEAPONPROF', 
                                                        $tag->id, 
                                                        $$tag->file, 
                                                        $tag->line,
                                                        $new_prof
                                                ];

                                }
                                else {
                                }
                        }
                }


        }



1;
