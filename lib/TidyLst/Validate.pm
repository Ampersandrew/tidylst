package TidyLst::Validate;

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

use TidyLst::Data qw(
   addValidSubEntity
   getEntityName 
   incCountInvalidTags
   isValidTag
   splitAndAddToValidEntities
   );
use TidyLst::LogFactory qw(getLogger);


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

   my ($line) = @_;

   my $log = getLogger();

   my $hasCHOOSE = 1 if $line->hasColumn('CHOOSE');
   my $hasMULT   = 1 if $line->hasColumn('MULT')  && $line->firstColumnMatches('MULT', qr/^MULT:Y/i);
   my $hasSTACK  = 1 if $line->hasColumn('STACK') && $line->firstColumnMatches('STACK', qr/^STACK:Y/i);

   # 1) if it has MULT:YES, it  _has_ to have CHOOSE
   # 2) if it has CHOOSE, it _has_ to have MULT:YES
   # 3) if it has STACK:YES, it _has_ to have MULT:YES (and CHOOSE)

   if ( $hasMULT && !$hasCHOOSE ) {

      $log->info(
         qq(The CHOOSE tag is mandantory when MULT:YES is present in ") 
         . $line->type . q(" ") . $line->entityName . q("),
         $line->file,
         $line->num
      );

   } elsif ( $hasCHOOSE && !$hasMULT && $line->firstColumnMatches('CHOOSE', qr/CHOOSE:(?:SPELLLEVEL|NUMBER)/i)) {

      # CHOOSE:SPELLLEVEL and CHOOSE:NUMBER are exempted from this particular rule.
      $log->info(
         qq(The MULT:YES tag is mandatory when CHOOSE is present in ") 
         . $line->type . q(" ") . $line->entityName . q("),
         $line->file,
         $line->num
      );
   }

   if ( $hasSTACK && !$hasMULT ) {
      $log->info(
         qq(The MULT:YES tag is mandatory when STACK:YES is present in ") 
         . $line->type . q(" ") . $line->entityName . q("),
         $line->file,
         $line->num
      );
   }

   # We identify the feats that can have sub-entities. e.g. Spell Focus(Spellcraft)
   # if ($hasCHOOSE) {

   #    my $entityName = $line->entityName =~ s/.MOD$//r;

   #    # The CHOOSE type tells us the type of sub-entities

   #    if ($line->firstColumnMatches('CHOOSE', qr/^CHOOSE:(?:NUMCHOICES=\d+\|)?(FEAT=[^|]*)/) ) {

   #       addValidSubEntity($line->type, $entityName, $1)

   #    } elsif ($line->firstColumnMatches('CHOOSE', qr/^CHOOSE:(?:NUMCHOICES=\d+\|)?FEATLIST/)) {

   #       addValidSubEntity($line->type, $entityName, 'FEAT')

   #    } elsif ($line->firstColumnMatches('CHOOSE', qr/^CHOOSE:(?:NUMCHOICES=\d+\|)?(?:WEAPONPROFS|Exotic|Martial)/)) {

   #       addValidSubEntity($line->type, $entityName, 'WEAPONPROF')

   #    } elsif ($line->firstColumnMatches('CHOOSE', qr/^CHOOSE:(?:NUMCHOICES=\d+\|)?SKILLSNAMED/)) {

   #       addValidSubEntity($line->type, $entityName, 'SKILL')

   #    } elsif ($line->firstColumnMatches('CHOOSE', qr/^CHOOSE:(?:NUMCHOICES=\d+\|)?SCHOOLS/)) {

   #       addValidSubEntity($line->type, $entityName, 'SPELL_SCHOOL')

   #    } elsif ($line->firstColumnMatches('CHOOSE', qr/^CHOOSE:(?:NUMCHOICES=\d+\|)?SPELLLIST/)) {

   #       addValidSubEntity($line->type, $entityName, 'SPELL')

   #    } elsif ($line->firstColumnMatches('CHOOSE', qr/^CHOOSE:(?:NUMCHOICES=\d+\|)?SPELLLEVEL/)
   #             ||$line->firstColumnMatches('CHOOSE', qr/^CHOOSE:(?:NUMCHOICES=\d+\|)?HP/)) {

   #       # Ad-Lib is a special case that means "Don't look for
   #       # anything else".
   #       addValidSubEntity($line->type, $entityName, 'Ad-Lib')

   #    } elsif ($line->firstColumnMatches('CHOOSE', qr/^CHOOSE:(?:COUNT=\d+\|)?(.*)/)) {

   #       # ad-hod/special list of thingy It adds to the valid
   #       # entities instead of the valid sub-entities.  We do
   #       # this when we find a CHOOSE but we do not know what
   #       # it is for.

   #       splitAndAddToValidEntities($line->type, $entityName, $1);
   #    }
   # }
}


=head2 validateEQMODKey

   Validate EQUIPMOD keys.

=cut

sub validateEQMODKey {

   my ($line) = @_;

   # We keep track of the KEYs for the equipmods.
   if (! $line->hasColumn('KEY') ) {

      # We get the contents of the tag at the start of the line (the one that
      # only has a value).
      my $fullEntityName = $line->entityName();

      # [ 1368562 ] .FORGET / .MOD don\'t need KEY entries
      if ($fullEntityName !~ /.FORGET$|.MOD$/) {

         getLogger()->info(
            qq(No KEY tag found for "${fullEntityName}"),
            $line->file,
            $line->num
         );
      }
   }
}


##################################################################
# Check to see if the TYPE contains Spellbook, if so, warn if NUMUSES or
# PAGEUSAGE aren't there.  Then check to see if NUMPAGES or PAGEUSAGE are
# there, and if they are there, but the TYPE doesn't contain Spellbook,
# warn.
#
# Do the same for Type Container with and without CONTAINS

=head2 validateEquipmentLine

   Give appropriate warnings for bad combinations of equipment tags

=cut

sub validateEquipmentLine {

   my ($self) = @_;

   my $log = getLogger();

   if ($self->hasType('Spellbook')) {

      if ($self->hasColumn('NUMPAGES') && $self->hasColumn('PAGEUSAGE')) {
         #Nothing to see here, move along.
      } else {
         $log->info(
            q{You have a Spellbook defined without providing NUMPAGES or PAGEUSAGE.} 
            . q{ If you want a spellbook of finite capacity, consider adding these tokens.},
            $self->file,
            $self->num
         );
      }

   } else {

      if ($self->hasColumn('NUMPAGES') ) {
         $log->warning(
            q{Invalid use of NUMPAGES token in a non-spellbook.} 
            . q{ Remove this token, or correct the TYPE.},
            $self->file,
            $self->num
         );
      }

      if  ($self->hasColumn('PAGEUSAGE'))
      {
         $log->warning(
            q{Invalid use of PAGEUSAGE token in a non-spellbook.} 
            . q{ Remove this token, or correct the TYPE.},
            $self->file,
            $self->num
         );
      }
   }

   if ($self->hasType('Container')) {

      if (! $self->hasColumn('CONTAINS')) {

         $log->warning(
            q{Any object with TYPE:Container must also have a CONTAINS }
            . q{token to be activated.},
            $self->file,
            $self->num
         );
      }

   } elsif ($self->hasColumn('CONTAINS')) {

      $log->warning(
         q{Any object with CONTAINS must also be TYPE:Container }
         . q{for the CONTAINS token to be activated.},
         $self->file,
         $self->num
      );
   }
}


=head2 validateLine

   This function perform validation that must be done on a whole line at a time.
   
   Paramter: $line a TidyLst::Line object

=cut

sub validateLine {

   my ($line) = @_;

   my $log = getLogger();

   # We get the contents of the tag at the start of the line (the one that only
   # has a value).
   my $fullEntityName = $line->entityName();

   my $entityName = $fullEntityName =~ s/.MOD$//r;

   if ($line->isType('EQUIPMENT')) {
      validateEquipmentLine($line)
   }

   ########################################################
   # Validation for the line entityName
   ########################################################

   if ( !(  $line->isType('SOURCE')
         || $line->isType('KIT LANGAUTO')
         || $line->isType('KIT NAME')
         || $line->isType('KIT FEAT')
         || $line->file =~ m{ [.] PCC \z }xmsi
         || $line->isType('COMPANIONMOD')) # FOLLOWER:Class1,Class2=level
   ) {

      my $key;
      if ($line->hasColumn('KEY')) {
         $key = $line->firstTokenInColumn('KEY');
      }

      # We hunt for the bad comma.
      if (defined $key && $key =~ /,/ ) {
         $log->notice(
            qq{"," (comma) should not be used in KEY: "$key"},
            $line->file,
            $line->num
         );
      } elsif (!defined $key && $entityName =~ /,/ ) {
         $log->notice(
            qq{"," (comma) should not be used in line entityName name: $entityName with no key},
            $line->file,
            $line->num
         );
      }
   }

   ########################################################
   # Special validation for specific lines
   ########################################################

   if ( $line->isType('ABILITY') ) {

      # Lines which are modifications don't need a separate CATEGORY tag, it is
      # embeded in the entityname.
      if ($fullEntityName =~ /\.(MOD|FORGET|COPY=)/ ) {

      # Find the other Abilities lines without Categories
      } elsif ( !$line->hasColumn('CATEGORY') ) {
         $log->warning(
            qq(The CATEGORY tag is required in ABILITY "${entityName}"),
            $line->file,
            $line->num
         );
      }

      validateAbilityLine($line);

   } elsif ( $line->isType('FEAT') ) {

      # [ 1671410 ] xcheck CATEGORY:Feat in Feat object.
      if ($line->hasColumn('CATEGORY')) {

         if (! $line->firstColumnMatches('CATEGORY', qr"CATEGORY:(?:Feat|Special Ability)")) {
            my $token = $line->firstTokenInColumn('CATEGORY');

            $log->info(
               q(The CATEGORY tag must have the value of Feat or Special Ability ) .
               q(when present on a FEAT. Remove or replace ") . $token->fullToken . q("),
               $line->file,
               $line->num
            );
         }
      }

      validateAbilityLine($line);

   } elsif ( $line->isType('EQUIPMOD') ) {

      validateEQMODKey($line);

      if ( $line->hasColumn('CHOOSE') ) {

         my $token  = $line->firstTokenInColumn('CHOOSE');
         my $choose = $token->fullToken;

         if ($line->firstColumnMatches('CHOOSE', qr/^CHOOSE:(NUMBER[^|]*)/)) {
            # Valid: CHOOSE:NUMBER|MIN=1|MAX=99129342|TITLE=Whatever
            # Valid: CHOOSE:NUMBER|1|2|3|4|5|6|7|8|TITLE=Whatever
            # Valid: CHOOSE:NUMBER|MIN=1|MAX=99129342|INCREMENT=5|TITLE=Whatever
            # Valid: CHOOSE:NUMBER|MAX=99129342|INCREMENT=5|MIN=1|TITLE=Whatever
            # Only testing for TITLE= for now.
            # Test for TITLE= and warn if not present.
         
         } elsif ($line->firstColumnMatches('CHOOSE', qr/^CHOOSE:NOCHOICE/)) {
         
            if (! $line->firstColumnMatches('CHOOSE', qr/(TITLE[=])/)) {
               $log->info(
                  qq(TITLE= is missing in CHOOSE:NUMBER for "$choose"),
                  $line->file,
                  $line->num
               );
            }

         
         } elsif ($line->firstColumnMatches('CHOOSE', qr/^CHOOSE:NOCHOICE/)) {

         # CHOOSE:STRING|Foo|Bar|Monkey|Poo|TITLE=these are choices
         } elsif ($line->firstColumnMatches('CHOOSE', qr/^CHOOSE:?(STRING)[^|]*/)) {

            # Test for TITLE= and warn if not present.
            if (! $line->firstColumnMatches('CHOOSE', qr/(TITLE[=])/)) {
         
               $log->info(
                  qq(TITLE= is missing in CHOOSE:STRING for "$choose"),
                  $line->file,
                  $line->num
               );
            }

         # CHOOSE:STATBONUS|statname|MIN=2|MAX=5|TITLE=Enhancement Bonus
         } elsif ($line->firstColumnMatches('CHOOSE', qr/^CHOOSE:?(STATBONUS)[^|]*/)) {
         
         } elsif ($line->firstColumnMatches('CHOOSE', qr/^CHOOSE:?(SKILLBONUS)[^|]*/)) {
         
         } elsif ($line->firstColumnMatches('CHOOSE', qr/^CHOOSE:?(SKILL)[^|]*/)) {

            if (! $line->firstColumnMatches('CHOOSE', qr/(TITLE[=])/)) {
               $log->info(
                  qq(TITLE= is missing in CHOOSE:SKILL for "$choose"),
                  $line->file,
                  $line->num
               );
            }

         } elsif ($line->firstColumnMatches('CHOOSE', qr/^CHOOSE:?(EQBUILDER.SPELL)[^|]*/)) {

         } elsif ($line->firstColumnMatches('CHOOSE', qr/^CHOOSE:?(EQBUILDER.EQTYPE)[^|]*/)) {

         # If not above, invaild CHOOSE for equipmod files.
         } else {
            $log->warning(
               qq(Invalid CHOOSE for Equipmod spells for "$choose"),
               $line->file,
               $line->num
            );
         }
      }

   } elsif ( $line->isType('CLASS') ) {

      if ( $line->hasColumn('SPELLTYPE') && !$line->hasColumn('BONUS:CASTERLEVEL') ) {
         $log->info(
            qq{Missing BONUS:CASTERLEVEL for "${entityName}"},
            $line->file,
            $line->num
         );
      }

   } elsif ( $line->isType('SKILL') ) {

      if ( $line->hasColumn('CHOOSE') ) {

         if ($line->firstColumnMatches('CHOOSE', qr/^CHOOSE:(?:NUMCHOICES=\d+\|)?Language/)) {
            addValidSubEntity('SKILL', $entityName, 'LANGUAGE')
         }
      }
   }
}

1;
