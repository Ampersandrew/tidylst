#!/usr/bin/perl

use strict;
use warnings;

# expand library path so we can find LstTidy modules
use File::Basename qw(dirname);
use Cwd  qw(abs_path);
use lib dirname(abs_path $0) . '/lib';

use LstTidy::Log;
use LstTidy::LogFactory;

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

###############################################################
# additionnal_tag_parsing
# -----------------------
#
# This function does additional parsing on each line once
# they have been seperated in tags.
#
# Most commun use is for addition, conversion or removal of tags.
#
# Paramter: $tag_name           Name of the tag (before the :)
#               $tag_value              Value of the tag (after the :)
#               $linetype               Type for the current file
#               $file_for_error   Name of the current file
#               $line_for_error   Number of the current line
                 
sub reportReplacement {

   my ($tag, $suffix) = @_;
   my $output = (defined $suffix) ? qq(Replacing ") . $tag->origTag  . q(" with ") . $tag->fullTag . qq(" $suffix)
                                  : qq(Replacing ") . $tag->origTag  . q(" with ") . $tag->fullTag . q(");

   LstTidy::LogFactory::getLogger->warning($output, $tag->file, $tag->line);
}

sub additionnal_tag_parsing {

   my ($tag) = @_;

   my ( $tag_name, $tag_value, $linetype, $file_for_error, $line_for_error ) = @_;

        ##################################################################
        # [ 1514765 ] Conversion to remove old defaultmonster tags
        # Gawaine42 (Richard Bowers)
        # Bonuses associated with a PREDEFAULTMONSTER:Y need to be removed
        # Bonuses associated with a PREDEFAULTMONSTER:N are retained without
        #               the PREDEFAULTMONSTER:N
        if ( LstTidy::Options::isConversionActive('RACE:Fix PREDEFAULTMONSTER bonuses') && $tag->id =~ /BONUS/ ) {
           if ($tag->value =~ /PREDEFAULTMONSTER:N/ ) {
              $_[1] =~ s/[|]PREDEFAULTMONSTER:N//;
              reportReplacement($tag);
           }
        }

        if ( LstTidy::Options::isConversionActive('ALL:Weaponauto simple conversion') && $tag->id =~ /WEAPONAUTO/) {
           $_[0] = 'AUTO';
           $_[1] =~ s/Simple/TYPE.Simple/;
           $_[1] =~ s/Martial/TYPE.Martial/;
           $_[1] =~ s/Exotic/TYPE.Exotic/;
           $_[1] =~ s/SIMPLE/TYPE.Simple/;
           $_[1] =~ s/MARTIAL/TYPE.Martial/;
           $_[1] =~ s/EXOTIC/TYPE.Exotic/;
           $_[1] = "WEAPONPROF|$_[1]";
           reportReplacement($tag);
        }

        ##################################################################
        # [ 1398237 ] ALL: Convert Willpower to Will
        #
        # The BONUS:CHECKS and PRECHECKBASE tags must be converted
        #
        # BONUS:CHECKS|<list of save types>|<other tag parameters>
        # PRECHECKBASE:<number>,<list of saves>

        if ( LstTidy::Options::isConversionActive('ALL:Willpower to Will') ) {
           if ( $tag->id eq 'BONUS:CHECKS' ) {
              # We split the tag parameters
              my @tag_params = split q{\|}, $tag->value;


              # The Willpower keyword must be replace only in parameter 1
              # (parameter 0 is empty since the tag_value begins by | )
              if ( $tag_params[1] =~ s{ \b Willpower \b }{Will}xmsg ) {
                 # We plug the new value in the calling parameter
                 $_[1] = join q{|}, @tag_params;
                 reportReplacement($tag);
              }

           } elsif ( $tag->id eq 'PRECHECKBASE' ) {
              # Since the first parameter is a number, no need to
              # split before replacing.

              # Yes, we change directly the calling parameter
              if ( $_[1] =~ s{ \b Willpower \b }{Will}xmsg ) {
                 reportReplacement($tag);
              }
           }
        }


        ##################################################################
        # We find the tags that use the word Willpower

        if ( LstTidy::Options::isConversionActive('ALL:Find Willpower') && getOption('exportlist') ) {
                if ( $tag->value
                        =~ m{ \b                # Word boundary
                                Willpower       # We need to find the word Willpower
                                \b              # Word boundary
                                }xmsi
                ) {
                # We write the tag and related information to the willpower.csv file
                my $tag_separator = $tag->id =~ / : /xms ? q{} : q{:};
                my $file_name = $tag->file;
                $file_name =~ tr{/}{\\};
                print { $filehandle_for{Willpower} }
                        qq{"$tag_name$tag_separator$tag_value","$tag->line","$file_name"\n};
                }
        }

        ##################################################################
        # PRERACE now only accepts the format PRERACE:<number>,<race list>
        # All the PRERACE tags must be reformated to use the default way.

        if ( LstTidy::Options::isConversionActive('ALL:PRERACE needs a ,') ) {

                if ( $tag->id eq 'PRERACE' || $tag->id eq '!PRERACE' ) {
                   if ( $tag->value !~ / \A \d+ [,], /xms ) {
                      $_[1] = '1,' . $_[1];
                      reportReplacement($tag);
                   }

                } elsif ( index( $tag->id, 'BONUS' ) == 0 && $tag->value =~ /PRERACE:([^]|]*)/ ) {
                   my $prerace_value = $1;
                   if ( $prerace_value !~ / \A \d+ [,] /xms ) {

                      # There is no ',', we need to add one
                      $_[1] =~ s/ PRERACE: (?!\d) /PRERACE:1,/xmsg;
                      reportReplacement($tag);
                   }

                } elsif ( ( $tag->id eq 'SA' || $tag->id eq 'PREMULT' ) && $tag->value =~ / PRERACE: ( [^]|]* ) /xms) {
                   my $prerace_value = $1;

                   if ( $prerace_value !~ / \A \d+ [,] /xms ) {

                      # There is no ',', we need to add one
                      $_[1] =~ s/ PRERACE: (?!\d) /PRERACE:1,/xmsg;
                      reportReplacement($tag);
                   }
                }
        }
        ##################################################################
        # [ 1173567 ] Convert old style PREALIGN to new style
        # PREALIGN now accept letters instead of numbers to specify alignments
        # All the PREALIGN tags must be reformated to the letters.

        if ( LstTidy::Options::isConversionActive('ALL:PREALIGN conversion') ) {

                if ( $tag->id eq 'PREALIGN' || $tag->id eq '!PREALIGN' ) {

                   my $new_value = join ',', map { $convertPreAlign{$_} || $_ } split ',', $tag->value;

                   if ( $tag->value ne $new_value ) {
                      $_[1] = $new_value;
                      reportReplacement($tag);
                   }

                } elsif (index( $tag->id, 'BONUS' ) == 0 || $tag->id eq 'SA' || $tag->id eq 'PREMULT' ) {

                   my $changed = 0;

                   while ( $tag->value =~ /PREALIGN:([^]|]*)/g ) {
                      my $old_value = $1;
                      my $new_value = join ',', map { $convertPreAlign{$_} || $_ } split ',',
                      $old_value;

                      if ( $new_value ne $old_value ) {

                         # There is no ',', we need to add one
                         $_[1] =~ s/PREALIGN:$old_value/PREALIGN:$new_value/;
                         $changed = 1;
                      }
                   }

                   if ($changed) {
                      reportReplacement($tag);
                   }
                }
        }

        ##################################################################
        # [ 1070344 ] HITDICESIZE to HITDIE in templates.lst
        #
        # HITDICESIZE:.* must become HITDIE:.* in the TEMPLATE line types.

        if (   LstTidy::Options::isConversionActive('TEMPLATE:HITDICESIZE to HITDIE') && $tag->id eq 'HITDICESIZE' && $tag->lineType eq 'TEMPLATE') {
                # We just change the tag name, the value remains the same.
                $_[0] = 'HITDIE';
                reportReplacement($tag);
        }

        ##################################################################
        # Remove all the PREALIGN tag from within BONUS, SA and
        # VFEAT tags.
        #
        # This is needed by my CMP friends .

        if ( LstTidy::Options::isConversionActive('ALL:CMP remove PREALIGN') ) {

               if ( $tag->value =~ /PREALIGN/ ) {

                  if ( $tag->value =~ /PREMULT/ ) {
                          LstTidy::LogFactory::getLogger->warning(
                             qq(PREALIGN found in PREMULT, you will have to remove it yourself ") . $tag->origTag . q("),
                             $tag->file,
                             $tag->line
                          );

                  } elsif ( $tag->id =~ /^BONUS/ || $tag->id eq 'SA' || $tag->id eq 'VFEAT' ) {

                          $_[1] = join( '|', grep { !/^(!?)PREALIGN/ } split '\|', $tag->value );
                          reportReplacement($tag);

                  } else {

                          LstTidy::LogFactory::getLogger->warning(
                             qq(Found PREALIGN where I was not expecting it ") . $tag->origTag . q("),
                             $tag->file,
                             $tag->line
                          );
                  }
               }
        }

        ##################################################################
        # [ 1006285 ] Conversion MOVE:<number> to MOVE:Walk,<Number>
        #
        # All the MOVE:<number> tags must be converted to
        # MOVE:Walk,<number>

        if (LstTidy::Options::isConversionActive('ALL:MOVE:nn to MOVE:Walk,nn') && $tag->id eq "MOVE") {
                if ( $tag->value =~ /^(\d+$)/ ) {
                   $_[1] = "Walk,$1";
                   reportReplacement($tag);
                }
        }

        ##################################################################
        # [ 892746 ] KEYS entries were changed in the main files
        #
        # All the EQMOD and PRETYPE:EQMOD tags must be scanned for
        # possible KEY replacement.

        if(LstTidy::Options::isConversionActive('ALL:EQMOD has new keys') &&
                ($tag->id eq "EQMOD" || $tag->id eq "REPLACES" || ($tag->id eq "PRETYPE" && $tag->value =~ /^(\d+,)?EQMOD/)))
        {
                for my $old_key (keys %convertEquipmodKey)
                {
                        if($tag->value =~ /\Q$old_key\E/)
                        {
                                $_[1] =~ s/\Q$old_key\E/$convertEquipmodKey{$old_key}/;
                                LstTidy::LogFactory::getLogger->notice(
                                        qq(=> Replacing "$old_key" with "$convertEquipmodKey{$old_key}" in ") . $tag->origTag . q("),
                                        $tag->file,
                                        $tag->line
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

        if (LstTidy::Options::isConversionActive('RACE:CSKILL to MONCSKILL') && $tag->lineType eq "RACE" && $tag->id eq "CSKILL") {
                LstTidy::LogFactory::getLogger->warning(
                   qq{Found CSKILL in RACE file},
                   $tag->file,
                   $tag->line
                );
        }

        ##################################################################
        # GAMEMODE DnD is now 3e

        if (LstTidy::Options::isConversionActive('PCC:GAMEMODE DnD to 3e') && $tag->id eq "GAMEMODE" && $tag->value eq "DnD") {
                $_[1] = "3e";
                reportReplacement($tag);
        }

        ##################################################################
        # Add 3e to GAMEMODE:DnD_v30e and 35e to GAMEMODE:DnD_v35e

        if (LstTidy::Options::isConversionActive('PCC:GAMEMODE Add to the CMP DnD_') && $tag->id eq "GAMEMODE" && $tag->value =~ /DnD_/) {
                my ( $has_3e, $has_35e, $has_DnD_v30e, $has_DnD_v35e );

                for my $game_mode (split q{\|}, $tag->value) {
                   $has_3e       = 1 if $_ eq "3e";
                   $has_DnD_v30e = 1 if $_ eq "DnD_v30e";
                   $has_35e      = 1 if $_ eq "35e";
                   $has_DnD_v35e = 1 if $_ eq "DnD_v35e";
                }

                $_[1] =~ s/(DnD_v30e)/3e\|$1/  if !$has_3e  && $has_DnD_v30e;
                $_[1] =~ s/(DnD_v35e)/35e\|$1/ if !$has_35e && $has_DnD_v35e;

                if ($tag->origTag ne $tag->fullRealTag) {
                   reportReplacement($tag);
                }
        }

        ##################################################################
        # [ 784363 ] Add TYPE=Base.REPLACE to most BONUS:COMBAT|BAB
        # The BONUS:COMBAT|BAB found in CLASS, CLASS Level,
        # SUBCLASS and SUBCLASSLEVEL lines must have a |TYPE=Base.REPLACE added to them.
        # The same BONUSes found in RACE files with PREDEFAULTMONSTER tags
        # must also have the TYPE added.
        # All the other BONUS:COMBAT|BAB should be reported since there
        # should not be any really.

        if (LstTidy::Options::isConversionActive('ALL:Add TYPE=Base.REPLACE') && $tag->id eq "BONUS:COMBAT" && $tag->value =~ /^\|(BAB)\|/i) {

                # Is the BAB in uppercase ?
                if ( $1 ne 'BAB' ) {
                   $_[1] =~ s/\|bab\|/\|BAB\|/i;
                   reportReplacement($tag, " (BAB must be in uppercase)");
                   $tag->value = $_[1];
                }

                # Is there already a TYPE= in the tag?
                my $is_type = $tag->value =~ /TYPE=/;

                # Is it the good one?
                my $is_type_base = $is_type && $tag->value =~ /TYPE=Base/;

                # Is there a .REPLACE at after the TYPE=Base?
                my $is_type_replace = $is_type_base && $tag->value =~ /TYPE=Base\.REPLACE/;

                # Is there a PREDEFAULTMONSTER tag embedded?
                my $is_predefaultmonster = $tag->value =~ /PREDEFAULTMONSTER/;

                # We must replace the CLASS, CLASS Level, SUBCLASS, SUBCLASSLEVEL
                # and PREDEFAULTMONSTER RACE lines
                if (   $tag->lineType eq 'CLASS'
                || $tag->lineType eq 'CLASS Level'
                || $tag->lineType eq 'SUBCLASS'
                || $tag->lineType eq 'SUBCLASSLEVEL'
                || ( ( $tag->lineType eq 'RACE' || $tag->lineType eq 'TEMPLATE' ) && $is_predefaultmonster ) )
                {
                if ( !$is_type ) {

                        # We add the TYPE= statement at the end
                        $_[1] .= '|TYPE=Base.REPLACE';
                        LstTidy::LogFactory::getLogger->warning(
                           q{Adding "|TYPE=Base.REPLACE" to "} . $tag->fullTag . q{"},
                           $tag->file,
                           $tag->line
                        );

                } else {

                        # The TYPE is already there but is it the correct one?
                        if ( !$is_type_replace && $is_type_base ) {

                                # We add the .REPLACE part
                                $_[1] =~ s/\|TYPE=Base/\|TYPE=Base.REPLACE/;
                                LstTidy::LogFactory::getLogger->warning(
                                qq{Adding ".REPLACE" to "$tag_name$tag_value"},
                                $tag->file,
                                $tag->line
                                );

                        } elsif ( !$is_type_base ) {

                                LstTidy::LogFactory::getLogger->info(
                                qq{Verify the TYPE of "$tag_name$tag_value"},
                                $tag->file,
                                $tag->line
                                );
                        }
                }

                } else {

                   # If there is a BONUS:COMBAT elsewhere, we report it for manual
                   # inspection.
                   LstTidy::LogFactory::getLogger->info( qq{Verify this tag "} . $tag->origTag . q{"}, $tag->file, $tag->line);
                }
        }

        ##################################################################
        # [ 737718 ] COUNT[FEATTYPE] data change
        # A ALL. must be added at the end of every COUNT[FEATTYPE=FooBar]
        # found in the DEFINE tags if not already there.

        if (LstTidy::Options::isConversionActive('ALL:COUNT[FEATTYPE=...') && $tag->id eq "DEFINE") {

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
                      $_[1] = $new_value;
                      reportReplacement($tag);
                   }
                }
        }

        ##################################################################
        # PRECLASS now only accepts the format PRECLASS:1,<class>=<n>
        # All the PRECLASS tags must be reformated to use the default way.

        if ( LstTidy::Options::isConversionActive('ALL:PRECLASS needs a ,') ) {

                if ( $tag->id eq 'PRECLASS' || $tag->id eq '!PRECLASS' ) {

                   if ( $tag->value !~ /^\d+,/ ) {
                      $_[1] = '1,' . $_[1];
                      reportReplacement($tag);
                   }

                } elsif ( index( $tag->id, 'BONUS' ) == 0 && $tag->value =~ /PRECLASS:([^]|]*)/ ) {

                   my $preclass_value = $1;

                   if ( $preclass_value !~ /^\d+,/ ) {

                      # There is no ',', we need to add one
                      $_[1] =~ s/PRECLASS:(?!\d)/PRECLASS:1,/g;
                      reportReplacement($tag);

                   }

                } elsif (($tag->id eq 'SA' || $tag->id eq 'PREMULT') && $tag->value =~ /PRECLASS:([^]|]*)/) {

                   my $preclass_value = $1;

                   if ( $preclass_value !~ /^\d+,/ ) {

                      # There is no ',', we need to add one
                      $_[1] =~ s/PRECLASS:(?!\d)/PRECLASS:1,/g;
                      reportReplacement($tag);

                   }
                }
        }

        ##################################################################
        # [ 711565 ] BONUS:MOVE replaced with BONUS:MOVEADD
        #
        # BONUS:MOVE must be replaced by BONUS:MOVEADD in all line types
        # except EQUIPMENT and EQUIPMOD where it most be replaced by
        # BONUS:POSTMOVEADD

        if (LstTidy::Options::isConversionActive('ALL:BONUS:MOVE conversion') && $tag->id eq 'BONUS:MOVE'){

                if ( $tag->lineType eq "EQUIPMENT" || $tag->lineType eq "EQUIPMOD" ) {
                   $_[0] = "BONUS:POSTMOVEADD";
                }
                else {
                   $_[0] = "BONUS:MOVEADD";
                }

                reportReplacement($tag);
        }

        ##################################################################
        # [ 699834 ] Incorrect loading of multiple vision types
        # All the , in the VISION tags must be converted to | except for the
        # VISION:.ADD (these will be converted later to BONUS:VISION)
        #
        # [ 728038 ] BONUS:VISION must replace VISION:.ADD
        # Now doing the VISION:.ADD conversion

        if (LstTidy::Options::isConversionActive('ALL: , to | in VISION') && $tag->id eq 'VISION') {
                if ($tag->value !~ /(\.ADD,|1,)/i) {
                        if ($_[1] =~ tr{,}{|}) {
                           reportReplacement($tag);
                        }
                }
        }

        ##################################################################
        # PRESTAT now only accepts the format PRESTAT:1,<stat>=<n>
        # All the PRESTAT tags must be reformated to use the default way.

        if (LstTidy::Options::isConversionActive('ALL:PRESTAT needs a ,') && $tag->id eq 'PRESTAT') {
                if ( index( $tag->value, ',' ) == -1 ) {
                        # There is no ',', we need to add one
                        $_[1] = '1,' . $_[1];
                        reportReplacement($tag);
                }
        }

        ##################################################################
        # [ 686169 ] remove ATTACKS: tag
        # ATTACKS:<attacks> must be replaced by BONUS:COMBAT|ATTACKS|<attacks>

        if (LstTidy::Options::isConversionActive('EQUIPMENT: remove ATTACKS') && $tag->id eq 'ATTACKS' && $tag->lineType eq 'EQUIPMENT') {

                my $number_attacks = $tag->value;
                $_[0] = 'BONUS:COMBAT';
                $_[1] = '|ATTACKS|' . $number_attacks;

                reportReplacement($tag);
        }

        ##################################################################
        # Name change for SRD compliance (PCGEN 4.3.3)

        if (LstTidy::Options::isConversionActive('ALL: 4.3.3 Weapon name change')
                && (   $tag->id eq 'WEAPONBONUS'
                || $tag->id eq 'WEAPONAUTO'
                || $tag->id eq 'PROF'
                || $tag->id eq 'GEAR'
                || $tag->id eq 'FEAT'
                || $tag->id eq 'PROFICIENCY'
                || $tag->id eq 'DEITYWEAP'
                || $tag->id eq 'MFEAT' )
        ) {
                for ( keys %convertWeaponName ) {
                        if ( $_[1] =~ s/\Q$_\E/$convertWeaponName{$_}/ig ) {
                                reportReplacement($tag);
                        }
                }
        }
}
