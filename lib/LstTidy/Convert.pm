package LstTidy::Convert;

use strict;
use warnings;

require Exporter;

our @ISA = qw(Exporter);
our @EXPORT_OK = qw(convertEntities doTagConversions);

# expand library path so we can find LstTidy modules
use File::Basename qw(dirname);
use Cwd  qw(abs_path);
use lib dirname(dirname abs_path $0);

use LstTidy::LogFactory qw(getLogger);
use LstTidy::Options qw(getOption isConversionActive);

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

=head2 addGenericDnDVersion

   Add 3e to GAMEMODE:DnD_v30e and 35e to GAMEMODE:DnD_v35e

=cut

sub addGenericDnDVersion {

   my ($tag) = @_;

   if ($tag->id eq "GAMEMODE" && $tag->value =~ /DnD_/) {
      my ( $has_3e, $has_35e, $has_DnD_v30e, $has_DnD_v35e );

      for my $gameMode (split q{\|}, $tag->value) {
         $has_3e       = 1 if $gameMode eq "3e";
         $has_DnD_v30e = 1 if $gameMode eq "DnD_v30e";
         $has_35e      = 1 if $gameMode eq "35e";
         $has_DnD_v35e = 1 if $gameMode eq "DnD_v35e";
      }

      if (!$has_3e && $has_DnD_v30e) { 
         $tag->value($tag->value =~ s/(DnD_v30e)/3e\|$1/r)
      }

      if (!$has_35e && $has_DnD_v35e) { 
         $tag->value($tag->value =~ s/(DnD_v35e)/35e\|$1/r) 
      }

      if ($tag->origTag ne $tag->fullRealTag) {
         reportReplacement($tag);
      }
   }
}

=head2 convertAddTags

   If the ADD tag parses as valid, the tag object is rewritten in standard
   form.   

=cut

sub convertAddTags {
   my ($tag) = @_;

   my ($type, $addTag, $theRest, $addCount) = LstTidy::Parse::parseAddTag( $tag->fullTag );
   # Return code 0 = no valid ADD tag found,
   #             1 = old format token ADD tag found,
   #             2 = old format adlib ADD tag found.
   #             3 = 5.12 format ADD tag, using known token.
   #             4 = 5.12 format ADD tag, not using token.

   if ($type) {

      # It's an ADD:token tag
      if ( $type == 1) {
         $tag->id($addTag);
         $tag->value("($theRest)$addCount");
      }

      if (isConversionActive('ALL:ADD Syntax Fix') && ($type == 1 || $type == 2)) {

         $tag->id("ADD:");
         $addTag =~ s/ADD://;
         $tag->value("$addTag|$addCount|$theRest");
      }

   } else {

      # the tag wasn't recognised as a valid ADD and is not a comment
      if ( index( $tag->fullTag, '#' ) != 0 ) {

         getLogger()->notice(
            qq{Invalid ADD tag "} . $tag->fullTag . q{" found in } . $tag->lineType,
            $tag->file,
            $tag->line
         );

         LstTidy::Report::incCountInvalidTags($tag->lineType, $addTag); 
         $tag->noMoreErrors(1);
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

   my ($tag) = @_;

   if ($tag->id eq "BONUS:COMBAT" && $tag->value =~ /^\|(BAB)\|/i) {

      # Is the BAB in uppercase ?
      if ( $1 ne 'BAB' ) {
         $tag->value($tag->value =~ s/\|bab\|/\|BAB\|/ir);
         reportReplacement($tag, " (BAB must be in uppercase)");
      }

      # Is there already a TYPE= in the tag?
      my $is_type = $tag->value =~ /TYPE=/;

      # Is it the good one?
      my $is_type_base = $is_type && $tag->value =~ /TYPE=Base/;

      # Is there a .REPLACE at after the TYPE=Base?
      my $is_type_replace = $is_type_base && $tag->value =~ /TYPE=Base\.REPLACE/;

      # Is there a PREDEFAULTMONSTER tag embedded?
      my $is_predefaultmonster = $tag->value =~ /PREDEFAULTMONSTER/;

      # We must replace the CLASS, CLASS Level, SUBCLASS, SUBCLASSLEVEL and
      # PREDEFAULTMONSTER RACE lines

      if (   $tag->lineType eq 'CLASS'
         || $tag->lineType eq 'CLASS Level'
         || $tag->lineType eq 'SUBCLASS'
         || $tag->lineType eq 'SUBCLASSLEVEL'
         || ( ( $tag->lineType eq 'RACE' || $tag->lineType eq 'TEMPLATE' ) && $is_predefaultmonster ) ) {

         if ( !$is_type ) {

            # We add the TYPE= statement at the end
            $tag->value($tag->value .= '|TYPE=Base.REPLACE');

            getLogger()->warning(
               q{Adding "|TYPE=Base.REPLACE" to "} . $tag->fullTag . q{"},
               $tag->file,
               $tag->line
            );

            # The TYPE is already there but is it the correct one?
         } elsif ( !$is_type_replace && $is_type_base ) {

            # We add the .REPLACE part
            $tag->value($tag->value =~ s/\|TYPE=Base/\|TYPE=Base.REPLACE/r);
            getLogger()->warning(
               qq{Adding ".REPLACE" to "} . $tag->fullTag . q{"},
               $tag->file,
               $tag->line
            );

         } elsif ( !$is_type_base ) {

            getLogger()->info(
               qq{Verify the TYPE of "} . $tag->fullTag . q{"},
               $tag->file,
               $tag->line
            );
         }

      } else {

         # If there is a BONUS:COMBAT elsewhere, we report it for manual
         # inspection.
         getLogger()->info(
            qq{Verify this tag "} . $tag->origTag . q{"}, 
            $tag->file, 
            $tag->line
         );
      }
   }
}

=head2 convertBonusMove

   BONUS:MOVE must be replaced by BONUS:MOVEADD in all line types except
   EQUIPMENT and EQUIPMOD where it must be replaced by BONUS:POSTMOVEADD

=cut

sub convertBonusMove {

   my ($tag) = @_;


   if ($tag->id eq 'BONUS:MOVE') {

      if ( $tag->lineType eq "EQUIPMENT" || $tag->lineType eq "EQUIPMOD" ) {
         $tag->id("BONUS:POSTMOVEADD");
      }
      else {
         $tag->id("BONUS:MOVEADD");
      }

      reportReplacement($tag);
   }
}

=head2 convertCountFeatType

   # [ 737718 ] COUNT[FEATTYPE] data change
   # A ALL. must be added at the end of every COUNT[FEATTYPE=FooBar]
   # found in the DEFINE tags if not already there.

=cut

sub convertCountFeatType {

   my ($tag) = @_;

   if ($tag->id eq "DEFINE") {

      if ( $tag->value =~ /COUNT\[FEATTYPE=/i ) {

         my $value = $tag->value;
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

         if ( $new_value ne $tag->value ) {
            $tag->value($new_value);
            reportReplacement($tag);
         }
      }
   }
}

=head2 convertDnD

   GAMEMODE DnD is now 3e

=cut

sub convertDnD {

   my ($tag) = @_;

   if ($tag->id eq "GAMEMODE" && $tag->value eq "DnD") {
      $tag->value("3e");
      reportReplacement($tag);
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
   $line =~ s-\x98-<sup>~</sup>-g;
   $line =~ s-\x99-<sup>TM</sup>-g;
   $line =~ s/\x9B/>/g;
   $line =~ s/\x9C/oe/g;

   return $line;
};

=head2 convertEquipmentAttacks

   ATTACKS:<attacks> must be replaced by BONUS:COMBAT|ATTACKS|<attacks>

=cut

sub convertEquipmentAttacks {

   my ($tag) = @_;


   if ($tag->id eq 'ATTACKS' && $tag->lineType eq 'EQUIPMENT') {

      $tag->id('BONUS:COMBAT');
      $tag->value('|ATTACKS|' . $tag->value);

      reportReplacement($tag);
   }
}

=head2 convertEqModKeys

   All the EQMOD and PRETYPE:EQMOD tags must be scanned for
   possible KEY replacement.

=cut

sub convertEqModKeys {

   my ($tag) = @_;

   if ($tag->id eq "EQMOD" || $tag->id eq "REPLACES" || ($tag->id eq "PRETYPE" && $tag->value =~ /^(\d+,)?EQMOD/)) {

      for my $old_key (keys %convertEquipmodKey) {

         if ($tag->value =~ /\Q$old_key\E/) {

            $tag->value($tag->value =~ s/\Q$old_key\E/$convertEquipmodKey{$old_key}/r);

            getLogger()->notice(
               qq(=> Replacing "$old_key" with "$convertEquipmodKey{$old_key}" in ") . $tag->origTag . q("),
               $tag->file,
               $tag->line
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

   my ($tag) = @_;

   if ($tag->id eq 'HITDICESIZE' && $tag->lineType eq 'TEMPLATE') {

      # We just change the tag name, the value remains the same.
      $tag->id('HITDIE');
      reportReplacement($tag);
   }
}

=head2 convertMove

   All the MOVE:<number> tags must be converted to MOVE:Walk,<number>

=cut

sub convertMove {

   my ($tag) = @_;

   if ($tag->id eq "MOVE" && $tag->value =~ /^(\d+$)/ ) {

      $tag->value("Walk,$1");
      reportReplacement($tag);
   }
}

=head2 convertPreAlign
        
   Convert old style PREALIGN to new style

   PREALIGN now accept text (two letters) instead of numbers to specify
   alignments.  All the PREALIGN tags must be reformated to use textual form.

=cut

sub convertPreAlign {

   my ($tag) = @_;

   if ( $tag->id eq 'PREALIGN' ) {

      my $new_value = join ',', map { $convertPreAlign{$_} || $_ } split ',', $tag->value;

      if ( $tag->value ne $new_value ) {
         $tag->value($new_value);
         reportReplacement($tag);
      }

   } elsif (index( $tag->id, 'BONUS' ) == 0 || $tag->id eq 'SA' || $tag->id eq 'PREMULT' ) {

      my $changed = 0;

      while ( $tag->value =~ /PREALIGN:([^]|]*)/g ) {

         my $old_value = $1;
         my $new_value = join ',', map { $convertPreAlign{$_} || $_ } split ',', $old_value;

         if ( $new_value ne $old_value ) {

            $tag->value($new_value);

            $tag->value($tag->value =~ s/PREALIGN:$old_value/PREALIGN:$new_value/r);
            $changed = 1;
         }
      }

      if ($changed) {
         reportReplacement($tag);
      }
   }
}

=head2 convertPreClass

   PRECLASS now only accepts the format PRECLASS:1,<class>=<n>
   All the PRECLASS tags must be reformated to use the default way.

=cut

sub convertPreClass {

   my ($tag) = @_;


   if ( $tag->id eq 'PRECLASS' || $tag->id eq '!PRECLASS' ) {

      if ( $tag->value !~ /^\d+,/ ) {
         $tag->value('1,' . $tag->value);
         reportReplacement($tag);
      }

   } elsif ( (index( $tag->id, 'BONUS' ) == 0 || $tag->id eq 'SA' || $tag->id eq 'PREMULT') && $tag->value =~ /PRECLASS:([^]|]*)/) {

      my $preclass_value = $1;

      if ( $preclass_value !~ /^\d+,/ ) {

         # There is no ',', we need to add one
         $tag->value($tag->value =~ s/PRECLASS:(?!\d)/PRECLASS:1,/gr);
         reportReplacement($tag);

      }
   }
}

=head2 convertPreDefaultMonster

   Remove the PREDEFAULTMONSTER tags where appropraite.

=cut

sub convertPreDefaultMonster {

   my ($tag) = @_;

   if ($tag->id =~ /BONUS/ && $tag->value =~ /PREDEFAULTMONSTER:N/) {
      $tag->value($tag->value =~ s/[|]PREDEFAULTMONSTER:N//r);
      reportReplacement($tag);
   }
}

=head2 convertPreSpellType

   PRESPELLTYPE was previously separated with commas, now uses =

   Takes the value (following the :), the line type, the file and the line
   number. It returns the modified value.

=cut

sub convertPreSpellType {

   my ($tag) = @_;

   if ($tag->id eq 'PRESPELLTYPE') {

      if ($tag->value =~ /^([^\d]+),(\d+),(\d+)/) {

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
            qq{Invalid standalone PRESPELLTYPE tag "PRESPELLTYPE:} . $tag->value . qq{" found and converted in } . $tag->lineType,
            $tag->file,
            $tag->line
         );

         $tag->value($value);
      }

      # Continuing the fix - fix it anywhere. This is meant to address PRE tags
      # that are on the end of other tags or in PREMULTS.
      # I'll leave out the pipe-delimited error here, since it's more likely
      # to end up with confusion when the tag isn't standalone.

   } elsif ($tag->value =~ /PRESPELLTYPE:([^\d]+),(\d+),(\d+)/) {

      $tag->value($tag->value =~ s/PRESPELLTYPE:([^\d,]+),(\d+),(\d+)/PRESPELLTYPE:$2,$1=$3/gr);

      getLogger()->notice(
         qq{Invalid embedded PRESPELLTYPE tag "} . $tag->fullTag . q{" found and converted } . $tag->lineType . q{.},
         $tag->file,
         $tag->line
      );
   }
}

=head2 convertPreStat

   PRESTAT now only accepts the format PRESTAT:1,<stat>=<n> All the PRESTAT
   tags must be reformated to use the default way.

=cut

sub convertPreStat {

   my ($tag) = @_;

   if ($tag->id eq 'PRESTAT' && index( $tag->value, ',' ) == -1 ) {
      # There is no ',', we need to add one
      $tag->value('1,' . $tag->value);
      reportReplacement($tag);
   }
}

=head2 convertToSRDName

   Name change for SRD compliance (PCGEN 4.3.3)

=cut

sub convertToSRDName {

   my ($tag) = @_;

   if (
          $tag->id eq 'WEAPONBONUS'
       || $tag->id eq 'WEAPONAUTO'
       || $tag->id eq 'PROF'
       || $tag->id eq 'GEAR'
       || $tag->id eq 'FEAT'
       || $tag->id eq 'PROFICIENCY'
       || $tag->id eq 'DEITYWEAP'
       || $tag->id eq 'MFEAT' 
    ) {

       WEAPONNAME:
       for my $name ( keys %convertWeaponName ) {

          my $value = $tag->value;

          if ($value =~ s/\Q$name\E/$convertWeaponName{$name}/ig ) {
             $tag->value($value);
             reportReplacement($tag);
             last WEAPONNAME;
          }
       }
    }
 }

=head2 convertVisionCommas

   [ 699834 ] Incorrect loading of multiple vision types All the , in the
   VISION tags must be converted to | except for the VISION:.ADD (these will be
   converted later to BONUS:VISION)

=cut

sub convertVisionCommas {

   my ($tag) = @_;

   if ($tag->id eq 'VISION' && $tag->value !~ /(\.ADD,|1,)/i) {

      my $value = $tag->value;

      if ($value =~ tr{,}{|}) {
         $tag->value($value);
         reportReplacement($tag);
      }
   }
}

=head2 convertWeaponAuto

   'ALL:Weaponauto simple conversion'

   WEAPONAUTO:Simple tag becomes AUTO:WEAPONPROF|TYPE.Simple etc.

=cut

sub convertWeaponAuto {

   my ($tag) = @_;

   if ($tag->id =~ /WEAPONAUTO/) {
      $tag->id('AUTO');

      my $value = $tag->value;
      $value =~ s/Simple/TYPE.Simple/;
      $value =~ s/Martial/TYPE.Martial/;
      $value =~ s/Exotic/TYPE.Exotic/;
      $value =~ s/SIMPLE/TYPE.Simple/;
      $value =~ s/MARTIAL/TYPE.Martial/;
      $value =~ s/EXOTIC/TYPE.Exotic/;
      $tag->value("WEAPONPROF|$value");

      reportReplacement($tag);
   }
}

=head2

   The BONUS:CHECKS and PRECHECKBASE tags must be converted

   BONUS:CHECKS|<list of save types>|<other tag parameters>
   PRECHECKBASE:<number>,<list of saves>

=cut

sub convertWillpower{
   my ($tag) = @_;

   if ( $tag->id eq 'BONUS:CHECKS' ) {
      # We split the tag parameters
      my @values = split q{\|}, $tag->value;

      # The Willpower keyword must be replaced only in parameter 1
      # (parameter 0 is empty since the value begins with | )
      if ( $values[1] =~ s{ \b Willpower \b }{Will}xmsg ) {
         $tag->value(join q{|}, @values);
         reportReplacement($tag);
      }

   } elsif ( $tag->id eq 'PRECHECKBASE' ) {

      # Since the first parameter is a number, no need to
      # split before replacing.
      my $value = $tag->value =~ s{ \b Willpower \b }{Will}xmsgr;

      if ( $value ne $tag->value ) {
         $tag->value($value);
         reportReplacement($tag);
      }
   }
}

=head2 doTagConversions

   This function does tag conversion. It is called on individual tags after they have been separated.
 
   Most commun use is for addition, conversion or removal of tags.

=cut

sub doTagConversions {

   my ($tag) = @_;

   if (isConversionActive('ALL: , to | in VISION'))               { convertVisionCommas($tag)      }
   if (isConversionActive('ALL: 4.3.3 Weapon name change'))       { convertToSRDName($tag)         }
   if (isConversionActive('ALL:Add TYPE=Base.REPLACE'))           { convertBonusCombatBAB($tag)    }
   if (isConversionActive('ALL:BONUS:MOVE conversion'))           { convertBonusMove($tag)         }
   if (isConversionActive('ALL:CMP remove PREALIGN'))             { removePreAlign($tag)           }
   if (isConversionActive('ALL:COUNT[FEATTYPE=...'))              { convertCountFeatType($tag)     }
   if (isConversionActive('ALL:EQMOD has new keys'))              { convertEqModKeys($tag)         }
   if (isConversionActive('ALL:Find Willpower'))                  { reportWillpower($tag)          }
   if (isConversionActive('ALL:MOVE:nn to MOVE:Walk,nn'))         { convertMove($tag)              }
   if (isConversionActive('ALL:PREALIGN conversion'))             { convertPreAlign($tag)          }
   if (isConversionActive('ALL:PRECLASS needs a ,'))              { convertPreClass($tag)          }
   if (isConversionActive('ALL:PRERACE needs a ,'))               { reformatPreRace($tag)          }
   if (isConversionActive('ALL:PRESPELLTYPE Syntax'))             { convertPreSpellType($tag)      }
   if (isConversionActive('ALL:PRESTAT needs a ,'))               { convertPreStat($tag)           }
   if (isConversionActive('ALL:Weaponauto simple conversion'))    { convertWeaponAuto($tag)        }
   if (isConversionActive('ALL:Willpower to Will') )              { convertWillpower($tag)         }
   if (isConversionActive('EQUIPMENT: remove ATTACKS'))           { convertEquipmentAttacks($tag)  }
   if (isConversionActive('PCC:GAMEMODE Add to the CMP DnD_'))    { addGenericDnDVersion($tag)     }
   if (isConversionActive('PCC:GAMEMODE DnD to 3e'))              { convertDnD($tag)               }
   if (isConversionActive('RACE:CSKILL to MONCSKILL'))            { reportRaceCSkill($tag)         }
   if (isConversionActive('RACE:Fix PREDEFAULTMONSTER bonuses'))  { convertPreDefaultMonster($tag) }
   if (isConversionActive('TEMPLATE:HITDICESIZE to HITDIE'))      { convertHitDieSize($tag)        }
}

=head2 ensureLeadingDigit

   We found a PRERACE, make sure it starts with a <digit>,

=cut

sub ensureLeadingDigit {

   my ($tag, $value) = @_;

   if ( $value !~ / \A \d+ [,] /xms ) {

      # There is no ',', we need to add one
      $tag->value($tag->value =~ s/ PRERACE: (?!\d) /PRERACE:1,/xmsgr);
      reportReplacement($tag);
   }
}

=head2 reformatPreRace

   PRERACE now only accepts the format PRERACE:<number>,<race list>
   All the PRERACE tags must be reformated to use the default way.

=cut

sub reformatPreRace {

   my ($tag) = @_;

   if ( $tag->id eq 'PRERACE' || $tag->id eq '!PRERACE' ) {

      if ( $tag->value !~ / \A \d+ [,], /xms ) {

         $tag->value('1,' . $tag->value);
         reportReplacement($tag);
      }

   } elsif ( index( $tag->id, 'BONUS' ) == 0 && $tag->value =~ /PRERACE:([^]|]*)/ ) {
      ensureLeadingDigit($tag, $1);
   } elsif ( ( $tag->id eq 'SA' || $tag->id eq 'PREMULT' ) && $tag->value =~ / PRERACE: ( [^]|]* ) /xms) {
      ensureLeadingDigit($tag, $1);
   }
}

=head2 removePreAlign

   Remove all the PREALIGN tag from within BONUS, SA and VFEAT tags.

=cut

sub removePreAlign {

   my ($tag) = @_;

   if ( $tag->value =~ /PREALIGN/ ) {

      if ( $tag->value =~ /PREMULT/ ) {
         getLogger()->warning(
            qq(PREALIGN found in PREMULT, you will have to remove it yourself ") . $tag->origTag . q("),
            $tag->file,
            $tag->line
         );

      } elsif ($tag->id =~ /^BONUS/ || $tag->id eq 'SA' || $tag->id eq 'VFEAT' ) {

         # Remove all the PREALIGN tag from within BONUS, SA and VFEAT tags.
         $tag->value(join '|', grep { !/^(!?)PREALIGN/ } split '\|', $tag->value);
         reportReplacement($tag);

      } else {

         getLogger()->warning(
            qq(Found PREALIGN where I was not expecting it ") . $tag->origTag . q("),
            $tag->file,
            $tag->line
         );
      }
   }
}

=head2 reportRaceCSkill

   In the RACE files, all the CSKILL must be replaced with MONCSKILL but only
   if MONSTERCLASS is present and there is not already a MONCSKILL present.

=cut

sub reportRaceCSkill {

   my ($tag) = @_;

   if ($tag->lineType eq "RACE" && $tag->id eq "CSKILL") {
      getLogger()->warning(
         qq{Found CSKILL in RACE file},
         $tag->file,
         $tag->line
      );
   }
}
 
=head2 reportReplacement

   Report the modification done by a convertoperation.

=cut

sub reportReplacement {

   my ($tag, $suffix) = @_;
   my $output = (defined $suffix) ? qq(Replacing ") . $tag->origTag  . q(" with ") . $tag->fullTag . qq(" $suffix)
                                  : qq(Replacing ") . $tag->origTag  . q(" with ") . $tag->fullTag . q(");

   getLogger()->warning($output, $tag->file, $tag->line);
}

=head2 reportWillpower

   Find any tags that use the word Willpower

=cut

sub reportWillpower {

   my ($tag) = @_;

   if ($tag->value =~ m{ \b Willpower \b }xmsi && getOption('exportlist')) {

      # Write the tag and related information to the willpower.csv file
      my $output = q{"} . $tag->fullTag . q{","} . $tag->line . q{","} . $tag->file . qq{"\n};

      LstTidy::Report::printToExportList($output);
   }
}


1;

__END__
