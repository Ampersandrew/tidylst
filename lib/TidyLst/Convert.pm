package TidyLst::Convert;

use strict;
use warnings;

require Exporter;

our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
   convertAddTokens
   convertEntities
   doFileConversions
   doLineConversions
   doTokenConversions
);

# expand library path so we can find TidyLst modules
use File::Basename qw(dirname);
use Cwd  qw(abs_path);
use lib dirname(dirname abs_path $0);

use TidyLst::Data qw(
   BLOCK BLOCK_HEADER COMMENT FIRST_COLUMN LINE LINE_HEADER MAIN
   NO NO_HEADER SINGLE SUB YES
   dirHasSourceTags
   getDirSourceTags
   incCountInvalidTags
   );
use TidyLst::LogFactory qw(getLogger);
use TidyLst::Options qw(getOption isConversionActive);

our $tokenlessRegex = qr(^(?:HEADER|COMMENT|BLOCK_COMMENT|BLANK)$);

my $sourceCurrentFile = "";
my %classSpellTypes   = ();
my %spellsForEQMOD    = ();

# KEYS entries were changed in the main files
my %convertEquipmodKey = qw(
   BIND            BLIND
   ABENHABON       BNS_ENHC_AB
   ABILITYMINUS    BNS_ENHC_AB
   ABILITYPLUS     BNS_ENHC_AB
   ACDEFLBON       BNS_AC_DEFL
   ACENHABON       BNS_ENHC_AC
   ACINSIBON       BNS_AC_INSI
   ACLUCKBON       BNS_AC_LUCK
   ACOTHEBON       BNS_AC_OTHE
   ACPROFBON       BNS_AC_PROF
   ACSACRBON       BNS_AC_SCRD
   ADAARH          ADAM
   ADAARH          ADAM
   ADAARL          ADAM
   ADAARM          ADAM
   ADAWE           ADAM
   AMINAT          ANMATD
   AMMO+1          PLUS1W
   AMMO+2          PLUS2W
   AMMO+3          PLUS3W
   AMMO+4          PLUS4W
   AMMO+5          PLUS5W
   AMMODARK        DARK
   AMMOSLVR        SLVR
   ARFORH          FRT_HVY
   ARFORL          FRT_LGHT
   ARFORM          FRT_MOD
   ARMFOR          FRT_LGHT
   ARMFORH         FRT_HVY
   ARMFORM         FRT_MOD
   ARMORENHANCE    BNS_ENHC_AC
   ARMR+1          PLUS1A
   ARMR+2          PLUS2A
   ARMR+3          PLUS3A
   ARMR+4          PLUS4A
   ARMR+5          PLUS5A
   ARMRADMH        ADAM
   ARMRADML        ADAM
   ARMRADMM        ADAM
   ARMRMITH        MTHRL
   ARMRMITL        MTHRL
   ARMRMITM        MTHRL
   ARWCAT          ARW_CAT
   ARWDEF          ARW_DEF
   BANEA           BANE_A
   BANEM           BANE_M
   BANER           BANE_R
   BASHH           BASH_H
   BASHL           BASH_L
   BIND            BLIND
   BONSPELL        BNS_SPELL
   BONUSSPELL      BNS_SPELL
   BRIENAI         BRI_EN_A
   BRIENM          BRI_EN_M
   BRIENT          BRI_EN_T
   CHAOSA          CHAOS_A
   CHAOSM          CHAOS_M
   CHAOSR          CHAOS_R
   CLDIRNAI        CIRON
   CLDIRNW         CIRON
   DAGSLVR         SLVR
   DEFLECTBONUS    BNS_AC_DEFL
   DRGNAR          DRACO
   DRGNSH          DRACO
   DRKAMI          DARK
   DRKSH           DARK
   DRKWE           DARK
   ENBURM          EN_BUR_M
   ENBURR          EN_BUR_R
   ENERGM          ENERG_M
   ENERGR          ENERG_R
   FLAMA           FLM_A
   FLAMM           FLM_M
   FLAMR           FLM_R
   FLBURA          FLM_BR_A
   FLBURM          FLM_BR_M
   FLBURR          FLM_BR_R
   FROSA           FROST_A
   FROSM           FROST_M
   FROSR           FROST_R
   GHTOUA          GHOST_A
   GHTOUAM         GHOST_AM
   GHTOUM          GHOST_M
   GHTOUR          GHOST_R
   HCLDIRNW        CIRON/2
   HOLYA           HOLY_A
   HOLYM           HOLY_M
   HOLYR           HOLY_R
   ICBURA          ICE_BR_A
   ICBURM          ICE_BR_M
   ICBURR          ICE_BR_R
   LAWA            LAW_A
   LAWM            LAW_M
   LAWR            LAW_R
   LUCKBONUS       BNS_SAV_LUC
   LUCKBONUS2      BNS_SKL_LCK
   MERCA           MERC_A
   MERCM           MERC_M
   MERCR           MERC_R
   MICLE           MI_CLE
   MITHAMI         MTHRL
   MITHARH         MTHRL
   MITHARL         MTHRL
   MITHARM         MTHRL
   MITHGO          MTHRL
   MITHSH          MTHRL
   MITHWE          MTHRL
   NATENHA         BNS_ENHC_NAT
   NATURALARMOR    BNS_ENHC_NAT
   PLUS1AM         PLUS1W
   PLUS1AMI        PLUS1W
   PLUS1WI         PLUS1W
   PLUS2AM         PLUS2W
   PLUS2AMI        PLUS2W
   PLUS2WI         PLUS2W
   PLUS3AM         PLUS3W
   PLUS3AMI        PLUS3W
   PLUS3WI         PLUS3W
   PLUS4AM         PLUS4W
   PLUS4AMI        PLUS4W
   PLUS4WI         PLUS4W
   PLUS5AM         PLUS5W
   PLUS5AMI        PLUS5W
   PLUS5WI         PLUS5W
   RESIMP          RST_IMP
   RESIST          RST_IST
   RESISTBONUS     BNS_SAV_RES
   SAVINSBON       BNS_SAV_INS
   SAVLUCBON       BNS_SAV_LUC
   SAVOTHBON       BNS_SAV_OTH
   SAVPROBON       BNS_SAV_PRO
   SAVRESBON       BNS_SAV_RES
   SAVSACBON       BNS_SAV_SAC
   SE50CST         SPL_CHRG
   SECW            SPL_CMD
   SESUCAMA        A_1USEMI
   SESUCAME        A_1USEMI
   SESUCAMI        A_1USEMI
   SESUCDMA        D_1USEMI
   SESUCDME        D_1USEMI
   SESUCDMI        D_1USEMI
   SESUUA          SPL_1USE
   SEUA            SPL_ACT
   SE_1USEACT      SPL_1USE
   SE_50TRIGGER    SPL_CHRG
   SE_COMMANDWORD  SPL_CMD
   SE_USEACT       SPL_ACT
   SHBURA          SHK_BR_A
   SHBURM          SHK_BR_M
   SHBURR          SHK_BR_R
   SHDGRT          SHDW_GRT
   SHDIMP          SHDW_IMP
   SHDOW           SHDW
   SHFORH          FRT_HVY
   SHFORL          FRT_LGHT
   SHFORM          FRT_MOD
   SHLDADAM        ADAM
   SHLDDARK        DARK
   SHLDMITH        MTHRL
   SHOCA           SHOCK_A
   SHOCM           SHOCK_M
   SHOCR           SHOCK_R
   SKILLBONUS      BNS_SKL_CIR
   SKILLBONUS2     BNS_SKL_CMP
   SKLCOMBON       BNS_SKL_CMP
   SLICK           SLK
   SLKGRT          SLK_GRT
   SLKIMP          SLK_IMP
   SLMV            SLNT_MV
   SLMVGRT         SLNT_MV_GRT
   SLMVIM          SLNT_MV_IM
   SLVRAMI         ALCHM
   SLVRWE1         ALCHM
   SLVRWE2         ALCHM
   SLVRWEF         ALCHM
   SLVRWEH         ALCHM/2
   SLVRWEL         ALCHM
   SPELLRESI       BNS_SPL_RST
   SPELLRESIST     BNS_SPL_RST
   SPLRES          SPL_RST
   SPLSTR          SPL_STR
   THNDRA          THNDR_A
   THNDRM          THNDR_M
   THNDRR          THNDR_R
   UNHLYA          UNHLY_A
   UNHLYM          UNHLY_M
   UNHLYR          UNHLY_R
   WEAP+1          PLUS1W
   WEAP+2          PLUS2W
   WEAP+3          PLUS3W
   WEAP+4          PLUS4W
   WEAP+5          PLUS5W
   WEAPADAM        ADAM
   WEAPDARK        DARK
   WEAPMITH        MTHRL
   WILDA           WILD_A
   WILDS           WILD_S
);

# PREALIGN now accept letters instead of numbers to specify alignments
my %convertPreAlign = qw(
   0   LG
   1   LN
   2   LE
   3   NG
   4   TN
   5   NE
   6   CG
   7   CN
   8   CE
   9   NONE
   10  Deity
);

# Name change for SRD compliance (PCGEN 4.3.3)
my %convertWeaponName = (
   q{Sword (Great)}                => q{Greatsword},
   q{Sword (Long)}                 => q{Longsword},
   q{Dagger (Venom)}               => q{Venom Dagger},
   q{Dagger (Assassin's)}          => q{Assassin's Dagger},
   q{Mace (Smiting)}               => q{Mace of Smiting},
   q{Mace (Terror)}                => q{Mace of Terror},
   q{Greataxe (Life-Drinker)}      => q{Life Drinker},
   q{Rapier (Puncturing)}          => q{Rapier of Puncturing},
   q{Scimitar (Sylvan)}            => q{Sylvan Scimitar},
   q{Sword (Flame Tongue)}         => q{Flame Tongue},
   q{Sword (Planes)}               => q{Sword of the Planes},
   q{Sword (Luck Blade)}           => q{Luck Blade},
   q{Sword (Subtlety)}             => q{Sword of Subtlety},
   q{Sword (Holy Avenger)}         => q{Holy Avenger},
   q{Sword (Life Stealing)}        => q{Sword of Life Stealing},
   q{Sword (Nine Lives Stealer)}   => q{Nine Lives Stealer},
   q{Sword (Frost Brand)}          => q{Frost Brand},
   q{Trident (Fish Command)}       => q{Trident of Fish Command},
   q{Trident (Warning)}            => q{Trident of Warning},
   q{Warhammer (Dwarven Thrower)}  => q{Dwarven Thrower},
);


my %tokenAddTag = (
   '.CLEAR'            => 1,
   'CLASSSKILLS'       => 1,
   'DOMAIN'            => 1,
   'EQUIP'             => 1,
   'FAVOREDCLASS'      => 1,
   'LANGUAGE'          => 1,
   'SAB'               => 1,
   'SPELLCASTER'       => 1,
   'SKILL'             => 1,
   'TEMPLATE'          => 1,
   'WEAPONPROFS'       => 1,

   'FEAT'              => 1,    # Deprecated
   'FORCEPOINT'        => 1,    # Deprecated - never heard of this!
   'INIT'              => 1,    # Deprecated
   'SPECIAL'           => 1,    # Deprecated - Remove 5.16 - Special abilities are now set using hidden feats or Abilities.
   'VFEAT'             => 1,    # Deprecated
);


=head2 addCasterLevel
               
   [ 876536 ] All spell casting classes need CASTERLEVEL
               
   BONUS:CASTERLEVEL|<class name>|CL will be added to all classes
   that have a SPELLTYPE tag except if there is also an
   ITEMCREATE tag present.

=cut

sub addCasterLevel {

   my ($line) = @_;

   my $log = getLogger();

   my $class = $line->entityName;

   if ( $line->hasColumn('ITEMCREATE') ) {

      my $token = $line->firstTokenInColumn('ITEMCREATE');

      # ITEMCREATE is present, we do not convert but we warn.
      $log->warning(
         qq(Can't add BONUS:CASTERLEVEL for class "$class", ")
         . $token->fullToken . q(" was found.), 
         $line->file,
         $line->num,
      );

   } else {

      # We add the missing BONUS:CASTERLEVEL
      my $token = $line->tokenFor(
         tag   => 'BONUS:CASTERLEVEL',
         value => "|$class|CL"
      );

      $line->add($token);

      $log->warning(
         qq{Adding missing "BONUS:CASTERLEVEL|$class|CL"},
         $line->file,
         $line->num,
      );
   }
}



=head2 addGenericDnDVersion

   Add 3e to GAMEMODE:DnD_v30e and 35e to GAMEMODE:DnD_v35e

=cut

sub addGenericDnDVersion {

   my ($token) = @_;

   if ($token->tag eq "GAMEMODE" && $token->value =~ /DnD_/) {
      my ( $has_3e, $has_35e, $has_DnD_v30e, $has_DnD_v35e );

      for my $gameMode (split q{\|}, $token->value) {
         $has_3e       = 1 if $gameMode eq "3e";
         $has_DnD_v30e = 1 if $gameMode eq "DnD_v30e";
         $has_35e      = 1 if $gameMode eq "35e";
         $has_DnD_v35e = 1 if $gameMode eq "DnD_v35e";
      }

      if (!$has_3e && $has_DnD_v30e) {
         $token->value($token->value =~ s/(DnD_v30e)/3e\|$1/r)
      }

      if (!$has_35e && $has_DnD_v35e) {
         $token->value($token->value =~ s/(DnD_v35e)/35e\|$1/r)
      }

      if ($token->origToken ne $token->fullRealToken) {
         reportReplacement($token);
      }
   }
}


=head2 addSlotsToPlural

   For items with TYPE:Boot, Glove, Bracer, we must check for plural form and
   add a SLOTS:2 tag is the item is plural.

=cut

sub addSlotsToPlural {

   my ($line) = @_;

   my $log = getLogger();

   my $equipment_name = $line->entityName;

   if ( $line->hasColumn('TYPE') ) {

      for my $toCheck (qw(Boot Glove Bracer)) {
         if ($line->hasType($toCheck)) {
            if (  $1 eq 'Boot'   && $equipment_name =~ /boots|sandals/i
               || $1 eq 'Glove'  && $equipment_name =~ /gloves|gauntlets|straps/i
               || $1 eq 'Bracer' && $equipment_name =~ /bracers|bracelets/i) {

               my $token = $line->tokenFor(fullToken => 'SLOTS:2');

               $log->warning(
                  qq{"SLOTS:2" added to "$equipment_name"},
                  $line->file,
                  $line->num
               )

            } else {
               $log->error( qq{"$equipment_name" is a $1}, $line->file, $line->num )
            }
         }
      }

   } elsif ($equipment_name !~ /.MOD$/i) {
      $log->warning(
         qq{$equipment_name has no TYPE.},
         $line->file,
         $line->num
      )
   }
}


=head2 categoriseAddToken

   The ADD tag has a very adlib form. It can be many of the
   ADD:Token define in the master_list but is also can be
   of the form ADD:Any test whatsoever(...). And there is also
   the fact that the ':' is used in the name...

   In short, it's a pain.

   The above describes the pre 5.12 syntax
   For 5.12, the syntax has changed.
   It is now:
   ADD:subtoken[|number]|blah

   This function return a list of three elements.
      The first one is a return code
      The second one is the effective TAG if any
      The third one is anything found after the tag if any
      The fourth one is the count if one is detected

      Return code 0 = no valid ADD tag found,
                          1 = old format token ADD tag found,
                          2 = old format adlib ADD tag found.
                          3 = 5.12 format ADD tag, using known token.
                          4 = 5.12 format ADD tag, not using known token.

=cut

sub categoriseAddToken {

   my $tag = shift;

   # Old Format
   if ($tag =~ /\s*ADD:([^\(]+)\((.+)\)(\d*)/) {

      my ($token, $theRest, $numCount) = ($1, $2, $3);

      if (!$numCount) {
         $numCount = 1;
      }

      return ( exists $tokenAddTag{$token} ? 1 : 2, "ADD:$token", $theRest, $numCount);
   }

   # New format ADD tag.
   if ($tag =~ /\s*ADD:([^\|]+)(\|\d+)?\|(.+)/) {

      my ($token, $numCount, $optionList) = ($1, $2, $3);

      if (!$numCount) {
         $numCount = 1;
      }

      return ( exists $tokenAddTag{$token} ? 3 : 4, "ADD:$token", $optionList, $numCount);
   }

   # Not a good ADD tag.
   return ( 0, "", undef, 0 );
}



=head2 convertAddTokens

   If the ADD token parses as valid, the token object is rewritten in standard
   form.

=cut

sub convertAddTokens {
   my ($token) = @_;

   my ($type, $addToken, $theRest, $addCount) = categoriseAddToken( $token->fullToken );
   # Return code 0 = no valid ADD token found,
   #             1 = old format token ADD token found,
   #             2 = old format adlib ADD token found.
   #             3 = 5.12 format ADD token, using known token.
   #             4 = 5.12 format ADD token, not using token.

   if ($type) {

      # It's an ADD:token token
      if ( $type == 1) {
         $token->tag($addToken);
         $token->value("($theRest)$addCount");
      }

      if (isConversionActive('ALL:ADD Syntax Fix') && ($type == 1 || $type == 2)) {

         $token->tag("ADD:");
         $addToken =~ s/ADD://;
         $token->value("$addToken|$addCount|$theRest");
      }

   } else {

      # the token wasn't recognised as a valid ADD and is not a comment
      if ( index( $token->fullToken, '#' ) != 0 ) {

         getLogger()->notice(
            qq{Invalid ADD token "} . $token->fullToken . q{" found in } . $token->lineType,
            $token->file,
            $token->line
         );

         incCountInvalidTags($token->lineType, $addToken);
         $token->noMoreErrors(1);
      }
   }
}

=head2 convertBonusCombatBAB

   The BONUS:COMBAT|BAB found in CLASS, CLASS Level, SUBCLASS and SUBCLASSLEVEL
   lines must have a |TYPE=Base.REPLACE added to them.

   The same BONUSes found in RACE files with PREDEFAULTMONSTER tags must also
   have the TYPE added.

   All the other BONUS:COMBAT|BAB should be reported since there should not be
   any really.

=cut

sub convertBonusCombatBAB {

   my ($token) = @_;

   if ($token->tag eq "BONUS:COMBAT" && $token->value =~ /^\|(BAB)\|/i) {

      # Is the BAB in uppercase ?
      if ( $1 ne 'BAB' ) {
         $token->value($token->value =~ s/\|bab\|/\|BAB\|/ir);
         reportReplacement($token, " (BAB must be in uppercase)");
      }

      # Is there already a TYPE= in the token?
      my $is_type = $token->value =~ /TYPE=/;

      # Is it the good one?
      my $is_type_base = $is_type && $token->value =~ /TYPE=Base/;

      # Is there a .REPLACE at after the TYPE=Base?
      my $is_type_replace = $is_type_base && $token->value =~ /TYPE=Base\.REPLACE/;

      # Is there a PREDEFAULTMONSTER token embedded?
      my $is_predefaultmonster = $token->value =~ /PREDEFAULTMONSTER/;

      # We must replace the CLASS, CLASS Level, SUBCLASS, SUBCLASSLEVEL and
      # PREDEFAULTMONSTER RACE lines

      if (   $token->lineType eq 'CLASS'
         || $token->lineType eq 'CLASS Level'
         || $token->lineType eq 'SUBCLASS'
         || $token->lineType eq 'SUBCLASSLEVEL'
         || ( ( $token->lineType eq 'RACE' || $token->lineType eq 'TEMPLATE' ) && $is_predefaultmonster ) ) {

         if ( !$is_type ) {

            # We add the TYPE= statement at the end
            $token->value($token->value .= '|TYPE=Base.REPLACE');

            getLogger()->warning(
               q{Adding "|TYPE=Base.REPLACE" to "} . $token->fullToken . q{"},
               $token->file,
               $token->line
            );

            # The TYPE is already there but is it the correct one?
         } elsif ( !$is_type_replace && $is_type_base ) {

            # We add the .REPLACE part
            $token->value($token->value =~ s/\|TYPE=Base/\|TYPE=Base.REPLACE/r);
            getLogger()->warning(
               qq{Adding ".REPLACE" to "} . $token->fullToken . q{"},
               $token->file,
               $token->line
            );

         } elsif ( !$is_type_base ) {

            getLogger()->info(
               qq{Verify the TYPE of "} . $token->fullToken . q{"},
               $token->file,
               $token->line
            );
         }

      } else {

         # If there is a BONUS:COMBAT elsewhere, we report it for manual
         # inspection.
         getLogger()->info(
            qq{Verify this token "} . $token->origToken . q{"},
            $token->file,
            $token->line
         );
      }
   }
}

=head2 convertBonusMove

   BONUS:MOVE must be replaced by BONUS:MOVEADD in all line types except
   EQUIPMENT and EQUIPMOD where it must be replaced by BONUS:POSTMOVEADD

=cut

sub convertBonusMove {

   my ($token) = @_;


   if ($token->tag eq 'BONUS:MOVE') {

      if ( $token->lineType eq "EQUIPMENT" || $token->lineType eq "EQUIPMOD" ) {
         $token->tag("BONUS:POSTMOVEADD");
      }
      else {
         $token->tag("BONUS:MOVEADD");
      }

      reportReplacement($token);
   }
}


=head2 convertClassLines

   [ 626133 ] Convert CLASS lines into 4 lines

   The four lines are:

   General (all tags not put in the two other lines)
   Prereq. (all the PRExxx tags)
   Class skills (the STARTSKILLPTS, the CKSILL and the CCSKILL tags)
   SPELL related tags (expanded from the 3 line version 2003.07.11)

=cut

sub convertClassLines {

   my ($lines_ref, $filetype, $filename) = @_;

   # Find all the CLASS lines
   ENTITY:
   for ( my $i = 0; $i < @{$lines_ref}; $i++ ) {

      my $line = $lines_ref->[$i];

      # Is this a CLASS line?
      if (ref $line eq 'TidyLst::Line' && $line->type eq 'CLASS') {

         my $first_line = $i;
         my $last_line  = $i;
         my $old_length;
         my $j          = $i + 1;

         #Find the next line that is not empty or of the same CLASS
         ENTITY_LINE:
         for ( ; $j < @{$lines_ref}; $j++ ) {

            my $jLine = $lines_ref->[$j];

            # if this isn't a line
            if (! defined $jLine || ref $jLine ne 'TidyLst::Line' ) {
               next ENTITY_LINE
            }

            # Is this line blank or a comment?
            if ($jLine->type =~ $tokenlessRegex) {

               next ENTITY_LINE
            }

            # Is it a CLASS line of the same CLASS?
            if ($jLine->isType('CLASS') && $jLine->entityName eq $line->entityName) {

               $last_line = $j;
               $line->mergeLines($jLine);

            } else {
               last ENTITY_LINE;
            }
         }

         # If there was only one line for the entity, we do nothing
         next ENTITY if $last_line == $i;

         # Number of lines included in the CLASS
         $old_length = $last_line - $first_line + 1;

         # extract the other lines
         my $skillLine = $line->extractSkillLine();
         my $spellLine = $line->extractSpellLine();
         my $preLine   = $line->extractPreLine();

         # We prepare the replacement lines
         $j = 0;
         my @newLines;

         # The main line
         if ($line->columns > 1 || ( 
               $preLine->columns   == 1 && 
               $skillLine->columns == 1 && 
               $spellLine->columns == 1 )) {

            push @newLines, $line;
            $j++;
         }

         if ($preLine->columns > 1) {

            push @newLines, $preLine;
            $j++;
         }

         if ($skillLine->columns > 1) {

            push @newLines, $skillLine;
            $j++;
         }

         # The spell line
         if ($spellLine->columns > 1) {

            push @newLines, $spellLine;
            $j++;
         }

         # We splice the new class lines in place
         splice @{$lines_ref}, $first_line, $old_length, @newLines;

         # Continue with the rest
         $i = $first_line + $j - 1;      # -1 because the $i++ happen right after

      }
   }
}


=head2 convertCountFeatType

   # [ 737718 ] COUNT[FEATTYPE] data change
   # A ALL. must be added at the end of every COUNT[FEATTYPE=FooBar]
   # found in the DEFINE tags if not already there.

=cut

sub convertCountFeatType {

   my ($token) = @_;

   if ($token->tag eq "DEFINE") {

      if ( $token->value =~ /COUNT\[FEATTYPE=/i ) {

         my $value = $token->value;
         my $new_value;

         while ( $value =~ /(.*?COUNT\[FEATTYPE=)([^\]]*)(\].*)/i ) {

            $new_value .= $1;
            my $count_value = $2;
            my $remaining   = $3;

            # We found a COUNT[FEATTYPE=, let's see if there is already
            # a ALL keyword in it.
            if ( $count_value !~ /^ALL\.|\.ALL\.|\.ALL$/i ) {
               $count_value = 'ALL.' . $count_value;
            }

            $new_value .= $count_value;
            $value = $remaining;
         }

         $new_value .= $value;

         if ( $new_value ne $token->value ) {
            $token->value($new_value);
            reportReplacement($token);
         }
      }
   }
}

=head2 convertDnD

   GAMEMODE DnD is now 3e

=cut

sub convertDnD {

   my ($token) = @_;

   if ($token->tag eq "GAMEMODE" && $token->value eq "DnD") {
      $token->value("3e");
      reportReplacement($token);
   }
}

=head2 convertEntities

   This subroutine takes a single string and converts all special characters in
   it to an ascii equivalent. It returns a modified copy of the input.

=cut

sub convertEntities {
   my ($line) = @_;

   $line =~ s/\x82/,/g;
   $line =~ s/\x84/,,/g;
   $line =~ s/\x85/.../g;
   $line =~ s/\x88/^/g;
   $line =~ s/\x8B/</g;
   $line =~ s/\x8C/Oe/g;
   $line =~ s/\x91/\'/g;
   $line =~ s/\x92/\'/g;
   $line =~ s/\x93/\"/g;
   $line =~ s/\x94/\"/g;
   $line =~ s/\x95/*/g;
   $line =~ s/\x96/-/g;
   $line =~ s/\x97/-/g;
   # $line =~ s-\x98-<sup>~</sup>-g;
   # $line =~ s-\x99-<sup>TM</sup>-g;
   $line =~ s/\x9B/>/g;
   $line =~ s/\x9C/oe/g;

   return $line;
};

=head2 convertEquipmentAttacks

   ATTACKS:<attacks> must be replaced by BONUS:COMBAT|ATTACKS|<attacks>

=cut

sub convertEquipmentAttacks {

   my ($token) = @_;


   if ($token->tag eq 'ATTACKS' && $token->lineType eq 'EQUIPMENT') {

      $token->tag('BONUS:COMBAT');
      $token->value('|ATTACKS|' . $token->value);

      reportReplacement($token);
   }
}

=head2 convertEqModKeys

   All the EQMOD and PRETYPE:EQMOD tags must be scanned for
   possible KEY replacement.

=cut

sub convertEqModKeys {

   my ($token) = @_;

   if ($token->tag eq "EQMOD" || $token->tag eq "REPLACES" || ($token->tag eq "PRETYPE" && $token->value =~ /^(\d+,)?EQMOD/)) {

      for my $old_key (keys %convertEquipmodKey) {

         if ($token->value =~ /\Q$old_key\E/) {

            $token->value($token->value =~ s/\Q$old_key\E/$convertEquipmodKey{$old_key}/r);

            getLogger()->notice(
               qq(=> Replacing "$old_key" with "$convertEquipmodKey{$old_key}" in ") . $token->origToken . q("),
               $token->file,
               $token->line
            );
         }
      }
   }
}

=head2 convertHitDieSize

   [ 1070344 ] HITDICESIZE to HITDIE in templates.lst

   HITDICESIZE:.* must become HITDIE:.* in the TEMPLATE line types.

=cut

sub convertHitDieSize {

   my ($token) = @_;

   if ($token->tag eq 'HITDICESIZE' && $token->lineType eq 'TEMPLATE') {

      # We just change the token name, the value remains the same.
      $token->tag('HITDIE');
      reportReplacement($token);
   }
}

=head2 convertMove

   All the MOVE:<number> tags must be converted to MOVE:Walk,<number>

=cut

sub convertMove {

   my ($token) = @_;

   if ($token->tag eq "MOVE" && $token->value =~ /^(\d+$)/ ) {

      $token->value("Walk,$1");
      reportReplacement($token);
   }
}


=head2 convertNaturalAttack

   Need to fix the STR bonus when the monster have only one Natural Attack (STR
   bonus is then 1.5 * STR).

   We add it if there is only one Melee attack and the bonus is not already
   present.

=cut

sub convertNaturalAttack {

   my ($line) = @_;

   # First we verify if if there is only one melee attack.
   if ($line->columnHasSingleToken('NATURALATTACKS')) {

      my $token = $line->firstTokenInColumn('NATURALATTACKS');
      my @NatAttacks = split '\|', $token->value;
      my ($attackName, $types, $numAttacks, $damage) = split ',', $NatAttacks[0];

      $types = uc $types;

      # Is there a single Natural Attack which is a melee attack
      if (@NatAttacks == 1 && $numAttacks eq '*1' && $damage && $types =~ qr{\bMELEE\b}) {

         if ($types =~ qr{\bRANGED\b}) {
            getLogger()->warning(
               qq{This natural attack is both Melee and Ranged} . $token->value,
               $line->file,
               $line->num
            );

         } else {

            # Make a token for the new bonus
            ($attackName) = ( $attackName =~ /:(.*)/ );

            my $WPtoken = $token->clone(
               tag   => 'BONUS:WEAPONPROF',
               value => "=$attackName|DAMAGE|STR/2");

            # is the potential new bonus already there.
            my $addIt = 1;
            if ($line->hasColumn('BONUS:WEAPONPROF')) {
               FIND_BONUS:
               for my $bonus (@{ $line->column('BONUS:WEAPONPROF') }) {
                  if ($bonus->fullToken eq $WPtoken->fullToken){
                     $addIt = 0;
                     last FIND_BONUS;
                  }
               }
            }

            if ($addIt) {
               $line->add($WPtoken);

               getLogger()->warning(
                  qq(Added ") . $WPtoken->fullToken
                  . qq(" to go with ") . $token->fullToken . q("),
                  $line->file,
                  $line->num
               );
            }
         }
      }
   }
}


=head2 convertPreAlign

   Convert old style PREALIGN to new style

   PREALIGN now accepts text (two letters) instead of numbers to specify
   alignments. All the PREALIGN tags must be reformated to use textual form.

=cut

sub convertPreAlign {

   my ($token) = @_;

   if ( $token->tag eq 'PREALIGN' ) {

      my $new_value = join ',', map { $convertPreAlign{$_} || $_ } split ',', $token->value;

      if ( $token->value ne $new_value ) {
         $token->value($new_value);
         reportReplacement($token);
      }

   } elsif (index( $token->tag, 'BONUS' ) == 0 || $token->tag eq 'SA' || $token->tag eq 'PREMULT' ) {

      my $changed = 0;

      while ( $token->value =~ /PREALIGN:([^]|]*)/g ) {

         my $old_value = $1;
         my $new_value = join ',', map { $convertPreAlign{$_} || $_ } split ',', $old_value;

         if ( $new_value ne $old_value ) {

            $token->value($new_value);

            $token->value($token->value =~ s/PREALIGN:$old_value/PREALIGN:$new_value/r);
            $changed = 1;
         }
      }

      if ($changed) {
         reportReplacement($token);
      }
   }
}

=head2 convertPreClass

   PRECLASS now only accepts the format PRECLASS:1,<class>=<n>
   All the PRECLASS tags must be reformated to use the default way.

=cut

sub convertPreClass {

   my ($token) = @_;

   if ( $token->tag eq 'PRECLASS' || $token->tag eq '!PRECLASS' ) {

      if ( $token->value !~ /^\d+,/ ) {
         $token->value('1,' . $token->value);
         reportReplacement($token);
      }

   } elsif ( (index( $token->tag, 'BONUS' ) == 0 || $token->tag eq 'SA' || $token->tag eq 'PREMULT') && $token->value =~ /PRECLASS:([^]|]*)/) {

      my $preclass_value = $1;

      if ( $preclass_value !~ /^\d+,/ ) {

         # There is no ',', we need to add one
         $token->value($token->value =~ s/PRECLASS:(?!\d)/PRECLASS:1,/gr);
         reportReplacement($token);

      }
   }
}

=head2 convertPreDefaultMonster

   Remove the PREDEFAULTMONSTER tags where appropraite.

=cut

sub convertPreDefaultMonster {

   my ($token) = @_;

   if ($token->tag =~ /BONUS/ && $token->value =~ /PREDEFAULTMONSTER:N/) {
      $token->value($token->value =~ s/[|]PREDEFAULTMONSTER:N//r);
      reportReplacement($token);
   }
}

=head2 convertPreSpellType

   PRESPELLTYPE was previously separated with commas, now uses =

   Takes the value (following the :), the line type, the file and the line
   number. It returns the modified value.

=cut

sub convertPreSpellType {

   my ($token) = @_;

   if ($token->tag eq 'PRESPELLTYPE') {

      if ($token->value =~ /^([^\d]+),(\d+),(\d+)/) {

         my ($spelltype, $num_spells, $num_levels) = ($1, $2, $3);

         my $value = "$num_spells";

         # Common homebrew mistake is to include Arcade|Divine, since the
         # 5.8 documentation had an example that showed this. Might
         # as well handle it while I'm here.
         my @spelltypes = split(/\|/,$spelltype);

         foreach my $st (@spelltypes) {
            $value .= ",$st=$num_levels";
         }

         getLogger()->notice(
            qq{Invalid standalone PRESPELLTYPE token "PRESPELLTYPE:}
            . $token->value . qq{" found and converted in } . $token->lineType,
            $token->file,
            $token->line
         );

         $token->value($value);
      }

      # Continuing the fix - fix it anywhere. This is meant to address PRE tags
      # that are on the end of other tags or in PREMULTS.
      # I'll leave out the pipe-delimited error here, since it's more likely
      # to end up with confusion when the token isn't standalone.

   } elsif ($token->value =~ /PRESPELLTYPE:([^\d]+),(\d+),(\d+)/) {

      $token->value($token->value =~ s/PRESPELLTYPE:([^\d,]+),(\d+),(\d+)/PRESPELLTYPE:$2,$1=$3/gr);

      getLogger()->notice(
         qq{Invalid embedded PRESPELLTYPE token "}
         . $token->fullToken . q{" found and converted } . $token->lineType . q{.},
         $token->file,
         $token->line
      );
   }
}

=head2 convertPreStat

   PRESTAT now only accepts the format PRESTAT:1,<stat>=<n> All the PRESTAT
   tags must be reformated to use the default way.

=cut

sub convertPreStat {

   my ($token) = @_;

   if ($token->tag eq 'PRESTAT' && index( $token->value, ',' ) == -1 ) {
      # There is no ',', we need to add one
      $token->value('1,' . $token->value);
      reportReplacement($token);
   }
}


=head2 convertRaceClimbandSwim

   Every RACE that has a Climb or a Swim MOVE must have a
   BONUS:SKILL|Climb|8|TYPE=Racial.

   If there is a BONUS:SKILLRANK|Swim|8|PREDEFAULTMONSTER:Y present, it must be
   removed or lowered by 8.

=cut

sub convertRaceClimbandSwim {

   my ($line) = @_;

   my $log = getLogger();

   my $swim  = $line->firstTokenMatches('MOVE', /swim/i);
   my $climb = $line->firstTokenMatches('MOVE', /climb/i);

   if ( $swim || $climb ) {
      my $need_swim  = 1;
      my $need_climb = 1;

      # Is there already a BONUS:SKILL|Swim of at least 8 rank?
      if ( $line->hasColumn('BONUS:SKILL') ) {
         for my $token (@{ $line->column('BONUS:SKILL') }) {
            if ($token->value =~ /^\|([^|]*)\|(\d+)\|TYPE=Racial/i) {

               my $skill_list = $1;
               my $skill_rank = $2;

               $need_swim  = 0 if $skill_list =~ /swim/i;
               $need_climb = 0 if $skill_list =~ /climb/i;

               if ( $need_swim && $skill_rank == 8 ) {

                  $skill_list = join( ',', sort( split ( ',', $skill_list ), 'Swim' ) );

                  $token->value("|$skill_list|8|TYPE=Racial");

                  $log->warning(
                     q(Added Swim to ") . $token->origToken . q("),
                     $line->file,
                     $line->num
                  );
               }

               if ( $need_climb && $skill_rank == 8 ) {

                  $skill_list = join( ',', sort( split ( ',', $skill_list ), 'Climb' ) );

                  $token->value("|$skill_list|8|TYPE=Racial");

                  $log->warning(
                     qq(Added Climb to ") . $token->origToken . q("),
                     $line->file,
                     $line->num
                  );
               }

               if ( ( $need_climb || $need_swim ) && $skill_rank != 8 ) {
                  $log->info(
                     qq(You\'ll have to deal with this one yourself ")
                     . $token->origToken . q("),
                     $line->file,
                     $line->num
                  );
               }
            }
         }

      } else {
         $need_swim  = $swim;
         $need_climb = $climb;
      }

      # Is there a BONUS:SKILLRANK to remove?
      if ( $line->hasColumn('BONUS:SKILLRANK') ) {
         my @keepTokens;
         for my $token (@{ $line->column('BONUS:SKILLRANK') }) {
            push @keepTokens, $token;
            if ($token->value =~ /^\|(.*)\|(\d+)\|PREDEFAULTMONSTER:Y/i) {

               my $skill_list = $1;
               my $skill_rank = $2;

               if ( $climb && $skill_list =~ /climb/i ) {
                  if ( $skill_list eq "Climb" ) {

                     $skill_rank -= 8;

                     if ($skill_rank) {

                        $token->value("|Climb|$skill_rank|PREDEFAULTMONSTER:Y");

                        $log->warning(
                           q(Lowering skill rank in ") . $token->origToken . q("),
                           $line->file,
                           $line->num
                        );

                     } else {

                        $log->warning(
                           q(Removing ") . $token->fullToken . q("),
                           $line->file,
                           $line->num
                        );
                        pop @keepTokens;
                     }

                  } else {

                     $log->info(
                        q(You\'ll have to deal with this one yourself ") . $token->fullToken . q("),
                        $line->file,
                        $line->num
                     );
                  }
               }

               if ( $swim && $skill_list =~ /swim/i ) {
                  if ( $skill_list eq "Swim" ) {

                     $skill_rank -= 8;

                     if ($skill_rank) {

                        $token->value("|Swim|$skill_rank|PREDEFAULTMONSTER:Y");

                        $log->warning(
                           q(Lowering skill rank in ") . $token->origToken . q("),
                           $line->file,
                           $line->num
                        );

                     } else {

                        $log->warning(
                           q(Removing ") . $token->fullToken . q("),
                           $line->file,
                           $line->num
                        );
                        pop @keepTokens;
                     }

                  } else {

                     $log->info(
                        q(You\'ll have to deal with this one yourself ") . $token->fullToken . q("),
                        $line->file,
                        $line->num
                     );
                  }
               }
            }
         }

         # delete all the current BONUS:SKILLRANK tokens
         $line->deleteColumn('BONUS:SKILLRANK');

         # put any we didn't delete above back
         for my $token (@keepTokens) {
            $line->add($token);
         }
      }
   }
}

=head2 convertRaceNoProfReq

   NoProfReq must be added to AUTO:WEAPONPROF if the race has
   at least one hand and if NoProfReq is not already there.

=cut

sub convertRaceNoProfReq {

   my ($line) = @_;

   my $log = getLogger();

   my $needNoProfReq = 1;

   # Is NoProfReq already present?
   if ($line->hasColumn('AUTO:WEAPONPROF')) {
      if ($line->firstColumnMatches('AUTO:WEAPONPROF', /NoProfReq/) ) {
         $needNoProfReq = 0
      }
   }

   # Default when no HANDS tag is present
   my $nbHands = 2;

   # How many hands?
   if ($line->hasColumn('HANDS')) {

      if ($line->firstColumnMatches('HANDS', /HANDS:(\d+)/) ) {
         $nbHands = $1;

      } else {
         my $token = $line->firstTokenInColumn('HANDS');

         $log->info(
            q(Invalid value in tag ") . $token->fullToken . q("),
            $line->file,
            $line->num
         );
         $needNoProfReq = 0;
      }
   }

   if ( $needNoProfReq && $nbHands ) {
      if ($line->hasColumn('AUTO:WEAPONPROF')) {
         my $token = $line->firstTokenInColumn('AUTO:WEAPONPROF');

         $log->warning(
            q(Adding "TYPE=NoProfReq" to tag ") . $token->fullToken . q("),
            $line->file,
            $line->num
         );
         $token->value($token->value . "|TYPE=NoProfReq");

      } else {

         # Create a new token for the lineType, line number and file name
         $line->add($line->tokenFor(fullToken => "AUTO:WEAPONPROF|TYPE=NoProfReq"));

         $log->warning(
            q{Creating new token "AUTO:WEAPONPROF|TYPE=NoProfReq"},
            $line->file,
            $line->num
         );
      }
   }
}


=head2 convertSpells

   Convert the old SPELL tags to the new SPELLS format.

   Old SPELL:<spellname>|<nb per day>|<spellbook>|...|PRExxx|PRExxx|...
   New SPELLS:<spellbook>|TIMES=<nb per day>|<spellname>|<spellname>|PRExxx...

=cut

sub convertSpells {

   my ($line) = @_;

   my $log = getLogger();

   my %spellbooks;

   # We parse all the existing SPELL tags
   for my $token ( @{ $line->column('SPELL') } ) {

      my @elements = split '\|', $token->value;
      my @pretags;

      while ( $elements[-1] =~ /^!?PRE\w*:/ ) {

         # We keep the PRE tags separated
         unshift @pretags, pop @elements;
      }

      my $pretags = scalar @pretags ? join '|', @pretags : 'NONE';

      # We classify each triple <spellname>|<nb per day>|<spellbook>
      while (@elements) {
         if ( scalar @elements < 3 ) {
            $log->warning(
               qq(Wrong number of elements for ") . $token->fullToken . q("),
               $line->file,
               $line->num
            );
         }

         my $spellname = shift @elements;
         my $times     = scalar @elements ? shift @elements : 99999;
         my $spellbook = scalar @elements ? shift @elements : "MISSING SPELLBOOK";

         push @{ $spellbooks{$spellbook}{$times}{$pretags} }, $spellname;
      }

      # warn about the impending deletion
      $log->warning(
         qq{Removing "} . $token->fullToken . q{"},
         $line->file,
         $line->num
      );
   }

   # delete the SPELL tags
   $line->replaceTag('SPELL');

   # add the new format SPELLS tags
   for my $spellbook ( sort keys %spellbooks ) {
      for my $times ( sort keys %{ $spellbooks{$spellbook} } ) {
         for my $pretags ( sort keys %{ $spellbooks{$spellbook}{$times} } ) {

            my $spells = "SPELLS:$spellbook|TIMES=$times";

            for my $spellname ( sort @{ $spellbooks{$spellbook}{$times}{$pretags} } ) {
               $spells .= "|$spellname";
            }

            $spells .= "|$pretags" unless $pretags eq "NONE";

            my $token = TidyLst::Token->new(
               fullToken => $spells,
               lineType  => $line->type,
               file      => $line->file,
               line      => $line->num,
            );

            $line->add($token);
            $log->warning( qq{Adding "$spells"}, $line->file, $line->num );
         }
      }
   }
}


=head2 convertToSRDName

   Name change for SRD compliance (PCGEN 4.3.3)

=cut

sub convertToSRDName {

   my ($token) = @_;

   if (
      $token->tag eq 'WEAPONBONUS'
      || $token->tag eq 'WEAPONAUTO'
      || $token->tag eq 'PROF'
      || $token->tag eq 'GEAR'
      || $token->tag eq 'FEAT'
      || $token->tag eq 'PROFICIENCY'
      || $token->tag eq 'DEITYWEAP'
      || $token->tag eq 'MFEAT'
   ) {

      WEAPONNAME:
      for my $name ( keys %convertWeaponName ) {

         my $value = $token->value;

         if ($value =~ s/\Q$name\E/$convertWeaponName{$name}/ig ) {
            $token->value($value);
            reportReplacement($token);
            last WEAPONNAME;
         }
      }
   }
}


=head2 convertVisionCommaToBar

   VISION:.ADD must be converted to BONUS:VISION
   Some exemple of VISION:.ADD tags:
     VISION:.ADD,Darkvision (60')
     VISION:1,Darkvision (60')
     VISION:.ADD,See Invisibility (120'),See Etheral (120'),Darkvision (120')

=cut

sub convertVisionCommaToBar {

   my ($line) = @_;

   my $log = getLogger();
   my $token = $line->firstTokenInColumn('VISION');

   $log->warning(
      qq(Removing ") . $token->fullToken . q("),
      $line->file,
      $line->num
   );

   $line->deleteColumn('VISION');

   my $newvision = "VISION:";
   my $comma;

   for my $vision_bonus ( split ',', $2 ) {
      if ($vision_bonus =~ /(\w+)\s*\((\d+)\'\)/) {

         my ($type, $bonus) = ($1, $2);

         $line->add($line->tokenFor(fullToken => "BONUS:VISION|$type|$bonus"));

         $log->warning(
            qq(Adding "BONUS:VISION|$type|$bonus"),
            $line->file,
            $line->num
         );

         $newvision .= "$comma$type (0')";
         $comma = ',';

      } else {

         $log->error(
            qq(Do not know how to convert "VISION:.ADD,$vision_bonus"),
            $line->file,
            $line->num
         );
      }
   }

   $log->warning( qq{Adding "$newvision"}, $line->file, $line->num );
   $line->add($line->tokenFor(fullToken => $newvision));
}


=head2 convertVisionCommas

   [ 699834 ] Incorrect loading of multiple vision types All the , in the
   VISION tags must be converted to | except for the VISION:.ADD (these will be
   converted later to BONUS:VISION)

=cut

sub convertVisionCommas {

   my ($token) = @_;

   if ($token->tag eq 'VISION' && $token->value !~ /(\.ADD,|1,)/i) {

      my $value = $token->value;

      if ($value =~ tr{,}{|}) {
         $token->value($value);
         reportReplacement($token);
      }
   }
}


=head2 convertWandForEqmod

   Any Wand that does not have a EQMOD tag must have one added.

   The syntax for the new tag is
   EQMOD:SE_50TRIGGER|SPELLNAME[$spell_name]SPELLLEVEL[$spell_level]CASTERLEVEL[$caster_level]CHARGES[50]

   $spell_level is extracted from the CLASSES tag.
   $caster_level (if not explicitly given) is $spell_level * 2 - 1

=cut

sub convertWandForEqmod {

   my ($line) = @_;

   # If this is a spell line, populate the hash that is used by
   # equipment lines.
   if ($line->isType('SPELL') && $line->hasColumn('CLASSES')) {

      my $level = $line->levelForWizardOrCleric();

      if ($level > -1) {
         $spellsForEQMOD{$line->entityName} = $level
      }

   } elsif ($line->isType('EQUIPMENT') && !$line->hasColumn('EQMOD')) {

      my $equip_name = $line->entityName;
      my $doWarn     = 0;

      if ( $equip_name =~ m{^Wand \((.*)/(\d\d?)(st|rd|th) level caster\)} ) {

         my $name = $1;

         if (exists $spellsForEQMOD{$name}) {

            my $sl = $spellsForEQMOD{$name};
            my $cl = $2;

            replaceWithEqmod($line, $name, $sl, $cl);

         } else {
            $doWarn = 1;
         }

      } elsif ( $equip_name =~ /^Wand \((.*)\)/ ) {

         my $name = $1;

         if (exists $spellsForEQMOD{$name}) {

            my $sl = $spellsForEQMOD{$name};
            my $cl = $sl * 2 - 1;

            replaceWithEqmod($line, $name, $sl, $cl);

         } else {
            $doWarn = 1;
         }

      } elsif ( $equip_name =~ /^Wand/ ) {
         $doWarn = 1;
      }

      if ($doWarn) {
         getLogger()->warning(
            qq{$equip_name: not enough information to add charges},
            $line->file,
            $line->num
         )
      }
   }
}



=head2 convertWeaponAuto

   'ALL:Weaponauto simple conversion'

   WEAPONAUTO:Simple token becomes AUTO:WEAPONPROF|TYPE.Simple etc.

=cut

sub convertWeaponAuto {

   my ($token) = @_;

   if ($token->tag =~ /WEAPONAUTO/) {
      $token->tag('AUTO');

      my $value = $token->value;
      $value =~ s/Simple/TYPE.Simple/;
      $value =~ s/Martial/TYPE.Martial/;
      $value =~ s/Exotic/TYPE.Exotic/;
      $value =~ s/SIMPLE/TYPE.Simple/;
      $value =~ s/MARTIAL/TYPE.Martial/;
      $value =~ s/EXOTIC/TYPE.Exotic/;
      $token->value("WEAPONPROF|$value");

      reportReplacement($token);
   }
}

=head2

   The BONUS:CHECKS and PRECHECKBASE tags must be converted

   BONUS:CHECKS|<list of save types>|<other token parameters>
   PRECHECKBASE:<number>,<list of saves>

=cut

sub convertWillpower{
   my ($token) = @_;

   if ( $token->tag eq 'BONUS:CHECKS' ) {
      # We split the token parameters
      my @values = split q{\|}, $token->value;

      # The Willpower keyword must be replaced only in parameter 1
      # (parameter 0 is empty since the value begins with | )
      if ( $values[1] =~ s{ \b Willpower \b }{Will}xmsg ) {
         $token->value(join q{|}, @values);
         reportReplacement($token);
      }

   } elsif ( $token->tag eq 'PRECHECKBASE' ) {

      # Since the first parameter is a number, no need to
      # split before replacing.
      my $value = $token->value =~ s{ \b Willpower \b }{Will}xmsgr;

      if ( $value ne $token->value ) {
         $token->value($value);
         reportReplacement($token);
      }
   }
}


=head2 doFileConversions

   This function does conversion on the entire file after it has been assembled into
   Lines of parsed Tokens.

=cut

sub doFileConversions {

   my ($lines_ref, $filetype, $filename) = @_;


   if (isConversionActive('ALL:Multiple lines to one')
      && ($filetype eq 'RACE' || $filetype eq 'TEMPLATE')) {

      multiLineToSingle($lines_ref, $filetype, $filename);
   }

   if (isConversionActive('CLASS:Four lines')
      && $filetype eq 'CLASS' ) {

      convertClassLines($lines_ref, $filetype, $filename);
   }


}



=head2 doLineConversions

   This function does token conversion. It is called on individual tags after
   they have been separated.

   Most commun use is for addition, conversion or removal of tags.

=cut

sub doLineConversions {

   my ($line) = @_;

   if (isConversionActive('ALL: , to | in VISION')
      && $line->hasColumn('VISION')
      && $line->firstColumnMatches('VISION', /(\.ADD,|1,)(.*)/i)) {

      convertVisionCommaToBar($line);
   }

   if (isConversionActive('ALL:Convert ADD:SA to ADD:SAB')
      && $line->hasColumn('ADD:SA')) {

      $line->replaceTag('ADD:SA', 'ADD:SAB')
   }

   if (isConversionActive('ALL:Convert SPELL to SPELLS')
      && $line->hasColumn('SPELL')) {

      convertSpells($line)
   }

   if (isConversionActive('ALL:CMP NatAttack fix')
      && $line->hasColumn('NATURALATTACKS')) {

      convertNaturalAttack($line);
   }

   if (isConversionActive('ALL:CMP remove PREALIGN')
      && $line->hasColumn('PREALIGN')) {

      $line->replaceTag('PREALIGN')
   }

   if (isConversionActive('ALL:New SOURCExxx tag format')
      && $line->hasColumn('SOURCELONG')) {

      $line->_splitToken('SOURCELONG')
   }

   if (isConversionActive('CLASS:CASTERLEVEL for all casters')
      && $line->hasColumn('SPELLTYPE')
      && !$line->hasColumn('BONUS:CASTERLEVEL')) {

      addCasterLevel($line);
   }

   if (isConversionActive('CLASS:no more HASSPELLFORMULA')
      && $line->isType("CLASS")
      && $line->hasColumn('HASSPELLFORMULA') )
   {

      $line->replaceTag('HASSPELLFORMULA')
   }

   if (isConversionActive('DEITY:Followeralign conversion')
      && $line->isType("DEITY")
      && $line->hasColumn('FOLLOWERALIGN')
      && $line->hasColumn('DOMAINS')) {

      removeFollowerAlign($line)
   }

   if (isConversionActive('EQUIP: ALTCRITICAL to ALTCRITMULT')
      && $line->isType("EQUIPMENT")
      && $line->hasColumn('ALTCRITICAL')) {

      replaceAltCritical($line)
   }

   if (isConversionActive('EQUIPMENT: generate EQMOD')) {

      convertWandForEqmod($line);
   }

   if (isConversionActive('EQUIP:no more MOVE')
      && $line->isType("EQUIPMENT")
      && $line->hasColumn('MOVE')) {

      $line->replaceTag('MOVE')
   }

   if (isConversionActive('EQUIPMENT: SLOTS:2 for plurals')
      && $line->isType('EQUIPMENT')
      && !$line->hasColumn('SLOTS') )
   {

      addSlotsToPlural($line);
   }

   if (isConversionActive('RACE:BONUS SKILL Climb and Swim')
      && $line->isType("RACE")
      && $line->hasColumn('MOVE')) {

      convertRaceClimbandSwim($line);
   }

   if (isConversionActive('RACE:CSKILL to MONCSKILL')
      && $line->isType("RACE")
      && $line->hasColumn('CSKILL')
      && $line->hasColumn('MONSTERCLASS')
      && !$line->hasColumn('MONCSKILL')) {

      $line->replaceTag('CSKILL', 'MONCSKILL')
   }

   if (isConversionActive('RACE:Fix PREDEFAULTMONSTER bonuses')
      && $line->isType("RACE")) {

      removePreDefaultMonster($line)
   }

   if (isConversionActive('RACE:NoProfReq')
      && $line->isType("RACE")) {

      convertRaceNoProfReq($line);
   }

   if (isConversionActive('RACE:Remove MFEAT and HITDICE')
      && $line->isType("RACE")
      && $line->hasColumn('MFEAT')) {

      removeMonsterTag($line, 'MFEAT')
   }

   if (isConversionActive('RACE:Remove MFEAT and HITDICE')
      && $line->isType("RACE")
      && $line->hasColumn('HITDICE')) {

      removeMonsterTag($line, 'HITDICE')
   }

   if (isConversionActive('RACE:TYPE to RACETYPE')
      && ($line->isType("RACE") || $line->isType("TEMPLATE") )
      && ! $line->hasColumn('RACETYPE')
      && $line->hasColumn('TYPE')) {

      $line->replaceTag('TYPE', 'RACETYPE')
   }

   if (isConversionActive('SOURCE line replacement')
      && $line->isType('SOURCE')
      && $sourceCurrentFile ne $line->file ) {

      sourceReplacement($line);
   }

   if (isConversionActive('SPELL:Add TYPE tags')
      && $line->istype('CLASS')
      && $line->hasColumn('SPELLTYPE')) {

      populateSpellType($line);
   }

   if (isConversionActive('SPELL:Add TYPE tags')
      && $line->isType('SPELL')) {

      # For each SPELL we build the TYPE tag or we add to the existing one.
      # The .MOD SPELL are ignored.
   }

   if (isConversionActive('WEAPONPROF:No more SIZE')
      && $line->isType("WEAPONPROF")
      && $line->hasColumn('SIZE')) {

      $line->replaceTag('SIZE')
   }



}


=head2 doTokenConversions

   This function does token conversion. It is called on individual tags after
   they have been separated.

   Most commun use is for addition, conversion or removal of tags.

=cut

sub doTokenConversions {

   my ($token) = @_;

   if (isConversionActive('ALL: , to | in VISION'))               { convertVisionCommas($token)      }
   if (isConversionActive('ALL: 4.3.3 Weapon name change'))       { convertToSRDName($token)         }
   if (isConversionActive('ALL:Add TYPE=Base.REPLACE'))           { convertBonusCombatBAB($token)    }
   if (isConversionActive('ALL:BONUS:MOVE conversion'))           { convertBonusMove($token)         }
   if (isConversionActive('ALL:CMP remove PREALIGN'))             { removePreAlign($token)           }
   if (isConversionActive('ALL:COUNT[FEATTYPE=...'))              { convertCountFeatType($token)     }
   if (isConversionActive('ALL:EQMOD has new keys'))              { convertEqModKeys($token)         }
   if (isConversionActive('ALL:Find Willpower'))                  { reportWillpower($token)          }
   if (isConversionActive('ALL:MOVE:nn to MOVE:Walk,nn'))         { convertMove($token)              }
   if (isConversionActive('ALL:PREALIGN conversion'))             { convertPreAlign($token)          }
   if (isConversionActive('ALL:PRECLASS needs a ,'))              { convertPreClass($token)          }
   if (isConversionActive('ALL:PRERACE needs a ,'))               { reformatPreRace($token)          }
   if (isConversionActive('ALL:PRESPELLTYPE Syntax'))             { convertPreSpellType($token)      }
   if (isConversionActive('ALL:PRESTAT needs a ,'))               { convertPreStat($token)           }
   if (isConversionActive('ALL:Weaponauto simple conversion'))    { convertWeaponAuto($token)        }
   if (isConversionActive('ALL:Willpower to Will') )              { convertWillpower($token)         }
   if (isConversionActive('EQUIPMENT: remove ATTACKS'))           { convertEquipmentAttacks($token)  }
   if (isConversionActive('PCC:GAMEMODE Add to the CMP DnD_'))    { addGenericDnDVersion($token)     }
   if (isConversionActive('PCC:GAMEMODE DnD to 3e'))              { convertDnD($token)               }
   if (isConversionActive('RACE:CSKILL to MONCSKILL'))            { reportRaceCSkill($token)         }
   if (isConversionActive('RACE:Fix PREDEFAULTMONSTER bonuses'))  { convertPreDefaultMonster($token) }
   if (isConversionActive('TEMPLATE:HITDICESIZE to HITDIE'))      { convertHitDieSize($token)        }
}

=head2 ensureLeadingDigit

   We found a PRERACE, make sure it starts with a <digit>,

=cut

sub ensureLeadingDigit {

   my ($token, $value) = @_;

   if ( $value !~ / \A \d+ [,] /xms ) {

      # There is no ',', we need to add one
      $token->value($token->value =~ s/ PRERACE: (?!\d) /PRERACE:1,/xmsgr);
      reportReplacement($token);
   }
}


=head2 multiLineToSingle

   Reformat multiple lines to one line for RACE and TEMPLATE.
   
   This is only useful for those who like to start new entries
   with multiple lines (for clarity) and then want them formatted
   properly for submission.

=cut

sub multiLineToSingle {

   my ($lines_ref, $filetype, $filename) = @_;

   # Find all the lines with the same identifier
   ENTITY:
   for ( my $i = 0; $i < @{$lines_ref}; $i++ ) {

      my $line = $lines_ref->[$i];

      # Is this a linetype we are interested in?
      if (ref $lines_ref->[$i] eq 'ARRAY' && ($line-isType('RACE') || $line-isType('TEMPLATE'))) {
         my $first_line   = $i;
         my $last_line    = $i;
         my $old_length;
         my $j            = $i + 1;
         my @newLines;

         #Find all the line with the same entity name
         ENTITY_LINE:
         for ( ; $j < @{$lines_ref}; $j++ ) {

            my $jLine = $lines_ref->[$j];

            # if this isn't a line
            if (! defined $jLine || ref $jLine ne 'TidyLst::Line' ) {
               next ENTITY_LINE
            }

            # Is this line blank or a comment?
            if ($jLine->type !~ $tokenlessRegex) {
               next ENTITY_LINE
            }

            # Is it an entity of the same name?
            if ($jLine->type eq $line->type
               && $jLine->entityName eq $line->entityName) {

               $last_line = $j;
               $line->mergeLines($jLine);

            } else {
               last ENTITY_LINE;
            }
         }

         # If there was only one line for the entity, we do nothing
         next ENTITY if $last_line == $i;

         # Number of lines included in the ENTITY
         $old_length = $last_line - $first_line + 1;

         # We prepare the replacement lines
         $j = 0;

         # The main line
         if (scalar @{$line->columns} > 1) {
            push @newLines, $line;
            $j++;
         }

         # We splice the new class lines in place
         splice @$lines_ref, $first_line, $old_length, @newLines;

         # Continue with the rest
         $i = $first_line + $j - 1;      # -1 because the $i++ happen right after

      }
   }
}


=head2 populateSpellType

   We must keep a list of all the SPELLTYPE for each class.  It is assumed that
   SPELLTYPE cannot be found more than once for the same class. It is also
   assumed that SPELLTYPE has only one value. SPELLTYPE:Any is ignored.

=cut

sub populateSpellType {

   my ($line) = @_;

   SPELLTYPE_TAG:
   for my $token (@{$line->column('SPELLTYPE')}) {

      if ($token->value eq "" or uc($token->value) eq "ANY") {
         next SPELLTYPE_TAG
      }

      $classSpellTypes{$line->entityName}{$token->value}++;
   }
}

=head2 reformatPreRace

   PRERACE now only accepts the format PRERACE:<number>,<race list>
   All the PRERACE tags must be reformated to use the default way.

=cut

sub reformatPreRace {

   my ($token) = @_;

   if ( $token->tag eq 'PRERACE' || $token->tag eq '!PRERACE' ) {

      if ( $token->value !~ / \A \d+ [,], /xms ) {

         $token->value('1,' . $token->value);
         reportReplacement($token);
      }

   } elsif ( index( $token->tag, 'BONUS' ) == 0 && $token->value =~ /PRERACE:([^]|]*)/ ) {
      ensureLeadingDigit($token, $1);
   } elsif ( ( $token->tag eq 'SA' || $token->tag eq 'PREMULT' ) && $token->value =~ / PRERACE: ( [^]|]* ) /xms) {
      ensureLeadingDigit($token, $1);
   }
}

=head2 removeFollowerAlign

=cut

sub removeFollowerAlign {

   my ($line) = @_;

   my $log = getLogger();

   my @valid = getValidSystemArr('alignments');
   my @alignments;

   for my $token (@{ $line->column('FOLLOWERALIGN') }) {

      for my $align (split //, $token->value) {

         # Is it a number in the range of the indices of @valid, i.e. a
         # valid alignment?
         if ($align =~ / \A (\d+) \z /xms && $1 >= 0 && $1 < scalar @valid) {

            push @alignments, $1;

         } else {
            $log->notice(
               qq{Invalid value "$align" for tag "$token"},
               $line->file,
               $line->num
            );
         }
      }
   }

   # join the distinct values with ,
   my $newprealign = join ",", map {$valid[$_]} sort
      do { my %seen; grep { !$seen{$_}++ } @alignments };

   $line->appendToValue('DOMAINS', "|PREALIGN:$newprealign");

   $log->notice(
      qq{Adding PREALIGN to domain information},
      $line->file,
      $line->num
   );

   $line->replaceTag('FOLLOWERALIGN');
}


=head2 removeMonsterTag

   Remove $tag if it appears on a line with MONSTERCLASS, otherwise,
   warn that they don't appear together

=cut

sub removeMonsterTag  {

   my ($line, $tag) = @_;

   if ( $line->hasColumn('MONSTERCLASS')) {

      # use the remove tag variant
      $line->replaceTag($tag);

   } else {

      getLogger()->warning(
         qq{MONSTERCLASS missing on same line as ${tag}, need to look at this line by hand.},
         $line->file,
         $line->num
      );
   }
}

=head2 removePreAlign

   Remove all the PREALIGN token from within BONUS, SA and VFEAT tags.

=cut

sub removePreAlign {

   my ($token) = @_;

   if ( $token->value =~ /PREALIGN/ ) {

      if ( $token->value =~ /PREMULT/ ) {
         getLogger()->warning(
            qq(PREALIGN found in PREMULT, you will have to remove it yourself ") . $token->origToken . q("),
            $token->file,
            $token->line
         );

      } elsif ($token->tag =~ /^BONUS/ || $token->tag eq 'SA' || $token->tag eq 'VFEAT' ) {

         # Remove all the PREALIGN token from within BONUS, SA and VFEAT tags.
         $token->value(join '|', grep { !/^(!?)PREALIGN/ } split '\|', $token->value);
         reportReplacement($token);

      } else {

         getLogger()->warning(
            qq(Found PREALIGN where I was not expecting it ") . $token->origToken . q("),
            $token->file,
            $token->line
         );
      }
   }
}

=head2 removePreDefaultMonster

   Bonuses associated with a PREDEFAULTMONSTER:Y need to be removed
   This should remove the whole token.

=cut

sub removePreDefaultMonster {

   my ($line) = @_;

   my $log = getLogger();

   for my $key ( $line->columns ) {
      my @column = @{ $line->column($key) };

      # delete the existing column
      $line->deleteColumn('ADD:SA');

      # put back the non-matching tags
      for my $token ( @column) {
         if ($token->value =~ /PREDEFAULTMONSTER:Y/) {
            $log->warning(
               qq{Removing "} . $token->fullToken . q{".},
               $line->file,
               $line->num
            )
         } else{
            $line->add($token);
         }
      }
   }
}

=head2 replaceAltCritical

   In EQUIPMENT files, take ALTCRITICAL and replace with ALTCRITMULT

=cut

sub replaceAltCritical {

   my ($line) = @_;

   # Give a warning if both ALTCRITICAL and ALTCRITMULT are on the same line,
   # then remove ALTCRITICAL.
   if ( $line->hasColumn('ALTCRITMULT') ) {
      getLogger()->warning(
         qq{Removing ALTCRITICAL, ALTCRITMULT is already present on this line.},
         $line->file,
         $line->num
      );

      $line->deleteColumn('ALTCRITICAL');

   } else {

      $line->replaceTag('ALTCRITICAL', 'ALTCRITMULT');
   }
}

=head2 replaceWithEqmod

   Replace the cost Tag in wands with an EQMOD and BASEITEM

=cut

sub replaceWithEqmod {

   my ($line, $name, $sl, $cl) = @_;

   my $tag   = "EQMOD";
   my $value = "SE_50TRIGGER|SPELLNAME[$name]SPELLLEVEL[$sl]"
      . "CASTERLEVEL[$cl]CHARGES[50]";

   my $token = $line->tokenFor(tag => $tag, value => $value);
   $line->add($token);

   if (! $line->hasColumn('BASEITEM')) {
      $line->add($line->tokenFor(tag => 'BASEITEM', value => 'Wand'));
   }

   if ($line->hasColumn('COST')) {
      $line->replaceTag('COST');
   }

   getLogger()->warning(
      qq($name: removing "COST" and adding ")
      . $token->fullToken . q("),
      $line->file,
      $line->num
   )
}



=head2 reportRaceCSkill

   In the RACE files, all the CSKILL must be replaced with MONCSKILL but only
   if MONSTERCLASS is present and there is not already a MONCSKILL present.

=cut

sub reportRaceCSkill {

   my ($token) = @_;

   if ($token->lineType eq "RACE" && $token->tag eq "CSKILL") {
      getLogger()->warning(
         qq{Found CSKILL in RACE file},
         $token->file,
         $token->line
      );
   }
}

=head2 reportReplacement

   Report the modification done by a convertoperation.

=cut

sub reportReplacement {

   my ($token, $suffix) = @_;
   my $output = (defined $suffix)
      ? qq(Replacing ") . $token->origToken  . q(" with ") . $token->fullToken . qq(" $suffix)
      : qq(Replacing ") . $token->origToken  . q(" with ") . $token->fullToken . q(");

   getLogger()->warning($output, $token->file, $token->line);
}

=head2 reportWillpower

   Find any tags that use the word Willpower

=cut

sub reportWillpower {

   my ($token) = @_;

   if ($token->value =~ m{ \b Willpower \b }xmsi && getOption('exportlist')) {

      # Write the token and related information to the willpower.csv file
      my $output = q{"} . $token->fullToken . q{","} . $token->line . q{","} . $token->file . qq{"\n};

      TidyLst::Report::printToExportList($output);
   }
}


=head2 sourceReplacement

   Replace the SOURCELONG:xxx|SOURCESHORT:xxx|SOURCEWEB:xxx
   with the values found in the .PCC of the same directory.

   Only the first SOURCE line found is replaced.

=cut

sub sourceReplacement {

   my ($line) = @_;

   my $inputpath = getOption('inputpath');
   my $file = $line->file;

   if (! dirHasSourceTags($line->file)) {
      $file = dirname $file;
   }

   if (dirHasSourceTags($file) ) {

      # Only the first SOURCE tag is replaced.
      $sourceCurrentFile = $line->file;

      # We replace the line with a concatanation of SOURCE tags found in
      # the directory .PCC
      $line->clearTokens;

      my %tokens = %{getDirSourceTags($file)};
      for my $token (values %tokens) {
         $line->add($token);
      }

   } elsif ( $line->file =~ / \A ${inputpath} /xmsi ) {

      # We give this notice only if the curent file is under getOption('inputpath').
      # If -basepath is used, there could be files loaded outside of the -inputpath
      # without their PCC.
      getLogger()->notice( "No PCC source information found", $line->file, $line->num );
   }
}


1;

__END__
