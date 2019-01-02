package LstTidy::Validate;

use strict;
use warnings;

require Exporter;

our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
   scanForDeprecatedTokens
   validateLine
   );

use Text::Balanced ();

use File::Basename qw(dirname);
use Cwd  qw(abs_path);
use lib dirname(dirname abs_path $0);

use LstTidy::Data qw(
   addValidSubEntity
   getEntityName 
   incCountInvalidTags
   isValidTag
   splitAndAddToValidEntities
   setEntityValid
   );
use LstTidy::LogFactory qw(getLogger);
use LstTidy::Options qw(getOption isConversionActive);


=head2 scanForDeprecatedTokens

   This function establishes a centralized location to search
   each line for deprecated tags.

   Parameters: $line     = The line to be searched
               $linetype = The type of line
               $file     = File name to use with ewarn
               $line     = The currrent line's number within the file

=cut

sub scanForDeprecatedTokens {
   my ( $line, $linetype, $file, $lineNum ) = @_ ;

   my $log = getLogger();

   # Deprecated tags
   if ( $line =~ /\scl\(/ ) {
      $log->info(
         qq{The Jep function cl() is deprecated, use classlevel() instead},
         $file,
         $lineNum
      );
   }

   # [ 1938933 ] BONUS:DAMAGE and BONUS:TOHIT should be Deprecated
   if ( $line =~ /\sBONUS:DAMAGE\s/ ) {
      $log->info(
         qq{BONUS:DAMAGE is deprecated 5.5.8 - Remove 5.16.0 - Use BONUS:COMBAT|DAMAGE.x|y instead},
         $file,
         $lineNum
      );
   }

   # [ 1938933 ] BONUS:DAMAGE and BONUS:TOHIT should be Deprecated
   if ( $line =~ /\sBONUS:TOHIT\s/ ) {
      $log->info(
         qq{BONUS:TOHIT is deprecated 5.3.12 - Remove 5.16.0 - Use BONUS:COMBAT|TOHIT|x instead},
         $file,
         $lineNum
      );
   }

   # [ 1973497 ] HASSPELLFORMULA is deprecated
   if ( $line =~ /\sHASSPELLFORMULA/ ) {
      $log->warning(
         qq{HASSPELLFORMULA is no longer needed and is deprecated in PCGen 5.15},
         $file,
         $lineNum
      );
   }

   if ( $line =~ /[\d+|\)]MAX\d+/ ) {
      $log->info(
         qq{The function aMAXb is deprecated, use the Jep function max(a,b) instead},
         $file,
         $lineNum
      );
   }

   if ( $line =~ /[\d+|\)]MIN\d+/ ) {
      $log->info(
         qq{The function aMINb is deprecated, use the Jep function min(a,b) instead},
         $file,
         $lineNum
      );
   }

   if ( $line =~ /\b]TRUNC\b/ ) {
      $log->info(
         qq{The function TRUNC is deprecated, use the Jep function floor(a) instead},
         $file,
         $lineNum
      );
   }

   if ( $line =~ /\sHITDICESIZE\s/ ) {
      $log->info(
         qq{HITDICESIZE is deprecated, use HITDIE instead},
         $file,
         $lineNum
      );
   }

   if ( $line =~ /\sSPELL\s/ && $linetype ne 'PCC' ) {
      $log->info(
         qq{SPELL is deprecated, use SPELLS instead},
         $file,
         $lineNum
      );
   }

   if ( $line =~ /\sWEAPONAUTO\s/ ) {
      $log->info(
         qq{WEAPONAUTO is deprecated, use AUTO:WEAPONPROF instead},
         $file,
         $lineNum
      );
   }

   if ( $line =~ /\sADD:WEAPONBONUS\s/ ) {
      $log->info(
         qq{ADD:WEAPONBONUS is deprecated, use BONUS instead},
         $file,
         $lineNum
      );
   }

   if ( $line =~ /\sADD:LIST\s/ ) {
      $log->info(
         qq{ADD:LIST is deprecated, use BONUS instead},
         $file,
         $lineNum
      );
   }

   if ( $line =~ /\sFOLLOWERALIGN/) {
      $log->info(
         qq{FOLLOWERALIGN is deprecated, use PREALIGN on Domain instead. Use the -c=pcgen5120 command line switch to fix this problem},
         $file,
         $lineNum
      );
   }

   # [ 1905481 ] Deprecate CompanionMod SWITCHRACE
   if ( $line =~ /\sSWITCHRACE\s/) {
      $log->info(
         qq{SWITCHRACE is deprecated 5.13.11 - Remove 6.0 - Use RACETYPE:x tag instead },
         $file,
         $lineNum
      );
   }

   # [ 1804786 ] Deprecate SA: replace with SAB:
   if ( $line =~ /\sSA:/) {
      $log->info(
         qq{SA is deprecated 5.x.x - Remove 6.0 - use SAB instead },
         $file,
         $lineNum
      );
   }

   # [ 1804780 ] Deprecate CHOOSE:EQBUILDER|1
   if ( $line =~ /\sCHOOSE:EQBUILDER\|1/) {
      $log->info(
         qq{CHOOSE:EQBUILDER|1 is deprecated use CHOOSE:NOCHOICE instead },
         $file,
         $lineNum
      );
   }

   # [ 1864704 ] AUTO:ARMORPROF|TYPE=x is deprecated
   if ( $line =~ /\sAUTO:ARMORPROF\|TYPE\=/) {
      $log->info(
         qq{AUTO:ARMORPROF|TYPE=x is deprecated Use AUTO:ARMORPROF|ARMORTYPE=x instead},
         $file,
         $lineNum
      );
   }

   # [ 1870482 ] AUTO:SHIELDPROF changes
   if ( $line =~ /\sAUTO:SHIELDPROF\|TYPE\=/) {
      $log->info(
         qq{AUTO:SHIELDPROF|TYPE=x is deprecated Use AUTO:SHIELDPROF|SHIELDTYPE=x instead},
         $file,
         $lineNum
      );
   }

   # [ NEWTAG-19 ] CHOOSE:ARMORPROF= is deprecated
   if ( $line =~ /\sCHOOSE:ARMORPROF\=/) {
      $log->info(
         qq{CHOOSE:ARMORPROF= is deprecated 5.15 - Remove 6.0. Use CHOOSE:ARMORPROFICIENCY instead},
         $file,
         $lineNum
      );
   }

   # [ NEWTAG-17 ] CHOOSE:FEATADD= is deprecated
   if ( $line =~ /\sCHOOSE:FEATADD\=/) {
      $log->info(
         qq{CHOOSE:FEATADD= is deprecated 5.15 - Remove 6.0. Use CHOOSE:FEAT instead},
         $file,
         $lineNum
      );
   }

   # [ NEWTAG-17 ] CHOOSE:FEATLIST= is deprecated
   if ( $line =~ /\sCHOOSE:FEATLIST\=/) {
      $log->info(
         qq{CHOOSE:FEATLIST= is deprecated 5.15 - Remove 6.0. Use CHOOSE:FEAT instead},
         $file,
         $lineNum
      );
   }

   # [ NEWTAG-17 ] CHOOSE:FEATSELECT= is deprecated
   if ( $line =~ /\sCHOOSE:FEATSELECT\=/) {
      $log->info(
         qq{CHOOSE:FEATSELECT= is deprecated 5.15 - Remove 6.0. Use CHOOSE:FEAT instead},
         $file,
         $lineNum
      );
   }


   # [ 1888288 ] CHOOSE:COUNT= is deprecated
   if ( $line =~ /\sCHOOSE:COUNT\=/) {
      $log->info(
         qq{CHOOSE:COUNT= is deprecated 5.13.9 - Remove 6.0. Use SELECT instead},
         $file,
         $lineNum
      );
   }
}



=head2 validateAbilityLine

   Ensure the tags on an ABILITY line are consistent.

=cut

sub validateAbilityLine {

   my ($entityName, $lineType, $lineTokens, $file, $line) = @_;

   my $log = getLogger();

   my $hasCHOOSE = 1 if exists $lineTokens->{'CHOOSE'};
   my $hasMULT   = 1 if exists $lineTokens->{'MULT'} && $lineTokens->{'MULT'}[0] =~ /^MULT:Y/i;
   my $hasSTACK  = 1 if exists $lineTokens->{'STACK'} && $lineTokens->{'STACK'}[0] =~ /^STACK:Y/i;
   
   my $choose;
   
   if ($hasCHOOSE) {
      $choose = $lineTokens->{'CHOOSE'}[0];
   }

   # 1) if it has MULT:YES, it  _has_ to have CHOOSE
   # 2) if it has CHOOSE, it _has_ to have MULT:YES
   # 3) if it has STACK:YES, it _has_ to have MULT:YES (and CHOOSE)

   if ( $hasMULT && !$hasCHOOSE ) {

      $log->info(
         qq(The CHOOSE tag is mandantory when MULT:YES is present in ${lineType} "${entityName}"),
         $file,
         $line
      );

   } elsif ( $hasCHOOSE && !$hasMULT && $choose !~ /CHOOSE:(?:SPELLLEVEL|NUMBER)/i ) {

      # CHOOSE:SPELLLEVEL and CHOOSE:NUMBER are exempted from this particular rule.
      $log->info(
         qq(The MULT:YES tag is mandatory when CHOOSE is present in ${lineType} "${entityName}"),
         $file,
         $line
      );
   }

   if ( $hasSTACK && !$hasMULT ) {
      $log->info(
         qq(The MULT:YES tag is mandatory when STACK:YES is present in ${lineType} "${entityName}"),
         $file,
         $line
      );
   }

   # We identify the feats that can have sub-entities. e.g. Spell Focus(Spellcraft)
   if ($hasCHOOSE) {

      $entityName =~ s/.MOD$//;

      # The CHOOSE type tells us the type of sub-entities

      if ( $choose =~ /^CHOOSE:(?:NUMCHOICES=\d+\|)?(FEAT=[^|]*)/ ) {

         addValidSubEntity($lineType, $entityName, $1)

      } elsif ( $choose =~ /^CHOOSE:(?:NUMCHOICES=\d+\|)?FEATLIST/ ) {

         addValidSubEntity($lineType, $entityName, 'FEAT')

      } elsif ( $choose =~ /^CHOOSE:(?:NUMCHOICES=\d+\|)?(?:WEAPONPROFS|Exotic|Martial)/ ) {

         addValidSubEntity($lineType, $entityName, 'WEAPONPROF')

      } elsif ( $choose =~ /^CHOOSE:(?:NUMCHOICES=\d+\|)?SKILLSNAMED/ ) {

         addValidSubEntity($lineType, $entityName, 'SKILL')

      } elsif ( $choose =~ /^CHOOSE:(?:NUMCHOICES=\d+\|)?SCHOOLS/ ) {

         addValidSubEntity($lineType, $entityName, 'SPELL_SCHOOL')

      } elsif ( $choose =~ /^CHOOSE:(?:NUMCHOICES=\d+\|)?SPELLLIST/ ) {

         addValidSubEntity($lineType, $entityName, 'SPELL')

      } elsif ($choose =~ /^CHOOSE:(?:NUMCHOICES=\d+\|)?SPELLLEVEL/ 
         || $choose =~ /^CHOOSE:(?:NUMCHOICES=\d+\|)?HP/ ) {

         # Ad-Lib is a special case that means "Don't look for
         # anything else".
         addValidSubEntity($lineType, $entityName, 'Ad-Lib')

      } elsif ( $choose =~ /^CHOOSE:(?:COUNT=\d+\|)?(.*)/ ) {

         # ad-hod/special list of thingy It adds to the valid
         # entities instead of the valid sub-entities.  We do
         # this when we find a CHOOSE but we do not know what
         # it is for.

         splitAndAddToValidEntities($lineType, $entityName, $1);
      }
   }
}


=head2 validateEQMODKey

   Validate EQUIPMOD keys.

=cut

sub validateEQMODKey {

   my ($lineType, $lineTokens, $file, $line) = @_;

   my $log = getLogger();

   # We keep track of the KEYs for the equipmods.
   if ( exists $lineTokens->{'KEY'} ) {

      # We extract the key name
      my ($key) = ( $lineTokens->{'KEY'}[0] =~ /KEY:(.*)/ );

      if ($key) {

         setEntityValid("EQUIPMOD Key", $key);

      } else {

         $log->warning(
            qq(Could not parse the KEY in "$lineTokens->{'KEY'}[0]"),
            $file,
            $line
         );
      }

   } else {

      # We get the contents of the tag at the start of the line (the one that
      # only has a value).
      my $fullEntityName = getEntityName($lineType, $lineTokens);

      # [ 1368562 ] .FORGET / .MOD don\'t need KEY entries
      if ($fullEntityName =~ /.FORGET$|.MOD$/) {

      } else {
         $log->info(
            qq(No KEY tag found for "${fullEntityName}"),
            $file,
            $line
         );
      }
   }
}


=head2 validateLine

   This function perform validation that must be done on a whole line at a time.
   
   Paramter: $lineType   Type for the current line
             $lineTokens Ref to a hash containing the tags of the line
             $file       Name of the current file
             $line       Number of the current line

=cut

sub validateLine {

   my ($lineType, $lineTokens, $file, $line) = @_;

   my $log = getLogger();

   # We get the contents of the tag at the start of the line (the one that only
   # has a value).
   my $fullEntityName = getEntityName($lineType, $lineTokens);

   my $entityName = $fullEntityName =~ s/.MOD$//r;

   ########################################################
   # Validation for the line entityName
   ########################################################

   if ( !(  $lineType eq 'SOURCE'
         || $lineType eq 'KIT LANGAUTO'
         || $lineType eq 'KIT NAME'
         || $lineType eq 'KIT FEAT'
         || $file =~ m{ [.] PCC \z }xmsi
         || $lineType eq 'COMPANIONMOD') # FOLLOWER:Class1,Class2=level
   ) {

      my $key;
      if (exists $lineTokens->{'KEY'}) {
         $key = $lineTokens->{'KEY'}[0];
      }

      # We hunt for the bad comma.
      if (defined $key && $key =~ /,/ ) {
         $log->notice(
            qq{"," (comma) should not be used in KEY: "$key"},
            $file,
            $line
         );
      } elsif (!defined $key && $entityName =~ /,/ ) {
         $log->notice(
            qq{"," (comma) should not be used in line entityName name: $entityName with no key},
            $file,
            $line
         );
      }
   }

   ########################################################
   # Special validation for specific lines
   ########################################################

   if ( $lineType eq "ABILITY" ) {

      # Lines which are modifications don't need a separate CATEGORY tag, it is
      # embeded in the entityname.
      if ($fullEntityName =~ /\.(MOD|FORGET|COPY=)/ ) {

      # Find the other Abilities lines without Categories
      } elsif ( !$lineTokens->{'CATEGORY'} ) {
         $log->warning(
            qq(The CATEGORY tag is required in ${lineType} "${entityName}"),
            $file,
            $line
         );
      }

      validateAbilityLine($entityName, $lineType, $lineTokens, $file, $line);

   } elsif ( $lineType eq "FEAT" ) {

      # [ 1671410 ] xcheck CATEGORY:Feat in Feat object.
      if (exists $lineTokens->{'CATEGORY'}) {
         my $category = $lineTokens->{'CATEGORY'}[0];
         if ($category !~ qr"CATEGORY:(?:Feat|Special Ability)") {

            $log->info(
               qq(The CATEGORY tag must have the value of Feat or Special Ability ) .
               qq(when present on a FEAT. Remove or replace "${category}"),
               $file,
               $line
            );
         }
      }

      validateAbilityLine($entityName, $lineType, $lineTokens, $file, $line);

   } elsif ( $lineType eq "EQUIPMOD" ) {

      validateEQMODKey($lineType, $lineTokens, $file, $line);

      if ( exists $lineTokens->{'CHOOSE'} ) {

         my $choose  = $lineTokens->{'CHOOSE'}[0];

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
                  $file,
                  $line
               );
            }

         } elsif ( $choose =~ /^CHOOSE:NOCHOICE/ ) {

         # CHOOSE:STRING|Foo|Bar|Monkey|Poo|TITLE=these are choices
         } elsif ( $choose =~ /^CHOOSE:?(STRING)[^|]*/ ) {

            # Test for TITLE= and warn if not present.
            if ( $choose !~ /(TITLE[=])/ ) {
               $log->info(
                  qq(TITLE= is missing in CHOOSE:STRING for "$choose"),
                  $file,
                  $line
               );
            }

         # CHOOSE:STATBONUS|statname|MIN=2|MAX=5|TITLE=Enhancement Bonus
         } elsif ( $choose =~ /^CHOOSE:?(STATBONUS)[^|]*/ ) {

         } elsif ( $choose =~ /^CHOOSE:?(SKILLBONUS)[^|]*/ ) {

         } elsif ( $choose =~ /^CHOOSE:?(SKILL)[^|]*/ ) {
            if ( $choose !~ /(TITLE[=])/ ) {
               $log->info(
                  qq(TITLE= is missing in CHOOSE:SKILL for "$choose"),
                  $file,
                  $line
               );
            }

         } elsif ( $choose =~ /^CHOOSE:?(EQBUILDER.SPELL)[^|]*/ ) {

         } elsif ( $choose =~ /^CHOOSE:?(EQBUILDER.EQTYPE)[^|]*/ ) {

         # If not above, invaild CHOOSE for equipmod files.
         } else {
            $log->warning(
               qq(Invalid CHOOSE for Equipmod spells for "$choose"),
               $file,
               $line
            );
         }
      }

   } elsif ( $lineType eq "CLASS" ) {

      if ( exists $lineTokens->{'SPELLTYPE'} && !exists $lineTokens->{'BONUS:CASTERLEVEL'} ) {
         $log->info(
            qq{Missing BONUS:CASTERLEVEL for "${entityName}"},
            $file,
            $line
         );
      }

   } elsif ( $lineType eq 'SKILL' ) {

      if ( exists $lineTokens->{'CHOOSE'} ) {

         my $choose  = $lineTokens->{'CHOOSE'}[0];

         if ( $choose =~ /^CHOOSE:(?:NUMCHOICES=\d+\|)?Language/ ) {
            addValidSubEntity('SKILL', $entityName, 'LANGUAGE')
         }
      }
   }
}

1;
