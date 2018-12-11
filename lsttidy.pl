#!/usr/bin/perl

use strict;
use warnings;
use Fatal qw( open close );             # Force some built-ins to die on error
use English qw( -no_match_vars );       # No more funky punctuation variables

my $VERSION        = "1.00.00";
my $VERSION_DATE   = "2018-12-2";
my ($PROGRAM_NAME) = "PCGen LstTidy";
my ($SCRIPTNAME)   = ( $PROGRAM_NAME =~ m{ ( [^/\\]* ) \z }xms );
my $VERSION_LONG   = "$SCRIPTNAME version: $VERSION -- $VERSION_DATE";

my $today = localtime;

use Carp;
use Getopt::Long;
use FileHandle;
use Pod::Html    ();     # We do not import any function for
use Pod::Text    ();     # the modules other than "system" modules
use Pod::Usage   ();
use File::Find   ();
use File::Basename ();
use Text::Balanced ();

# expand library path so we can find LstTidy modules
use File::Basename qw(dirname);
use Cwd  qw(abs_path);
use lib dirname(abs_path $0) . '/lib';

use LstTidy::Log;
use LstTidy::LogFactory;
use LstTidy::LogHeader;
use LstTidy::Options qw(getOption setOption isConversionActive);
use LstTidy::Parse;
use LstTidy::Reformat;
use LstTidy::Report;
use LstTidy::Validate;

# Subroutines
sub FILETYPE_parse;
sub parse_ADD_tag;
sub parse_tag;
sub validate_tag;
sub additionnal_tag_parsing;
sub validate_line;
sub additionnal_line_parsing;
sub additionnal_file_parsing;
sub check_clear_tag_order;
sub find_full_path;
sub create_dir;
sub embedded_coma_split;
sub record_bioset_tags;
sub generate_bioset_files;
sub generate_css;

# File handles for the Export Lists
my %filehandle_for;

# Print version information
print STDERR "$VERSION_LONG\n";

# -------------------------------------------------------------
# Parameter parsing
# -------------------------------------------------------------

# Parse the command line options and set the error message if there are any issues.
my $error_message = "\n" . LstTidy::Options::parseOptions(@ARGV);

# The command line has been processed, if conversions have been requested, make
# sure the tag validity data in Reformat.pm is updated. In order to convert a
# tag it must be recognised as valid. 

LstTidy::Reformat::addTagsForConversions(); 

# Test function or display variables
# or anything else I need.

if ( getOption('test') ) {

   print "No tests set\n";
   exit;
}

# Warning Level

# Check the warning level passed on the command line to ensure it is valid.
# Whether the check passes or fals, a valid level is returned. If the level we
# gave it was invalid, an error string is also returned. If it returned an
# error string it also set an options to ensure the error string is printed.

my ($level, $mess) = LstTidy::Log::checkWarningLevel(getOption('warninglevel'));

setOption('warninglevel', $level);
$error_message .= $mess if defined $mess;

# Create the singleton logging object using the warning level verified above.
my $log = LstTidy::LogFactory::getLogger();

# Path options

if (!getOption('inputpath') && !getOption('filetype') && !(getOption('man') || getOption('htmlhelp')))
{
   $error_message .= "\n-inputpath parameter is missing\n";
   setOption('help', 1);
}

#####################################
# Redirect STDERR if needed

if (getOption('outputerror')) {
   open STDERR, '>', getOption('outputerror');
   print STDERR "Error log for ", $VERSION_LONG, "\n";
   print STDERR "At ", $today, " on the data files in the \'", getOption('inputpath') , "\' directory\n";
}

#####################################
# -systempath option
#
# If present, call the function to
# generate the "game mode" variables.

if ( getOption('systempath') ne q{} ) {
   LstTidy::Parse::parseSystemFiles(getOption('systempath'), $log);
} 

LstTidy::Parse::updateValidity();

# Move these into Parse.pm, or Validate.pm whenever the code using them is moved.
my @valid_system_alignments  = LstTidy::Parse::getValidSystemArr('alignments');
my @valid_system_stats       = LstTidy::Parse::getValidSystemArr('stats');

# Limited choice tags
my %tag_fix_value = (
   ACHECK               => { YES => 1, NO => 1, WEIGHT => 1, PROFICIENT => 1, DOUBLE => 1 },
   ALIGN                => { map { $_ => 1 } @valid_system_alignments },
   APPLY                => { INSTANT => 1, PERMANENT => 1 },
   BONUSSPELLSTAT       => { map { $_ => 1 } ( @valid_system_stats, 'NONE' ) },
   DESCISIP             => { YES => 1, NO => 1 },
   EXCLUSIVE            => { YES => 1, NO => 1 },
   FORMATCAT            => { FRONT => 1, MIDDLE => 1, PARENS => 1 },       # [ 1594671 ] New tag: equipmod FORMATCAT
   FREE                 => { YES => 1, NO => 1 },
   KEYSTAT              => { map { $_ => 1 } @valid_system_stats },
   HASSUBCLASS          => { YES => 1, NO => 1 },
   ALLOWBASECLASS       => { YES => 1, NO => 1 },
   HASSUBSTITUTIONLEVEL => { YES => 1, NO => 1 },
   ISD20                => { YES => 1, NO => 1 },
   ISLICENSED           => { YES => 1, NO => 1 },
   ISOGL                => { YES => 1, NO => 1 },
   ISMATURE             => { YES => 1, NO => 1 },
   MEMORIZE             => { YES => 1, NO => 1 },
   MULT                 => { YES => 1, NO => 1 },
   MODS                 => { YES => 1, NO => 1, REQUIRED => 1 },
   MODTOSKILLS          => { YES => 1, NO => 1 },
   NAMEISPI             => { YES => 1, NO => 1 },
   RACIAL               => { YES => 1, NO => 1 },
   REMOVABLE            => { YES => 1, NO => 1 },
   RESIZE               => { YES => 1, NO => 1 },                          # [ 1956719 ] Add RESIZE tag to Equipment file
   PREALIGN             => { map { $_ => 1 } @valid_system_alignments }, 
   PRESPELLBOOK         => { YES => 1, NO => 1 },
   SHOWINMENU           => { YES => 1, NO => 1 },                          # [ 1718370 ] SHOWINMENU tag missing for PCC files
   STACK                => { YES => 1, NO => 1 },
   SPELLBOOK            => { YES => 1, NO => 1 },
   SPELLSTAT            => { map { $_ => 1 } ( @valid_system_stats, 'SPELL', 'NONE', 'OTHER' ) },
   TIMEUNIT             => { map { $_ => 1 } qw( Year Month Week Day Hour Minute Round Encounter Charges ) },
   USEUNTRAINED         => { YES => 1, NO => 1 },
   USEMASTERSKILL       => { YES => 1, NO => 1 },
   VISIBLE              => { map { $_ => 1 } qw( YES NO EXPORT DISPLAY QUALIFY CSHEET GUI ALWAYS ) },
);

# This hash is used to convert 1 character choices to proper fix values.
my %tag_proper_value_for = (
   'Y'     =>  'YES',
   'N'     =>  'NO',
   'W'     =>  'WEIGHT',
   'Q'     =>  'QUALIFY',
   'P'     =>  'PROFICIENT',
   'R'     =>  'REQUIRED',
   'true'  =>  'YES',
   'false' =>  'NO',
);

#####################################
# Diplay usage information

if ( getOption('help') or $LstTidy::Options::error ) {
   Pod::Usage::pod2usage(
      {   
         -msg     => $error_message,
         -exitval => 1,
         -output  => \*STDERR
      }
   );
   exit;
}

#####################################
# Display the man page

if (getOption('man')) {
   Pod::Usage::pod2usage(
      {
         -msg     => $error_message,
         -verbose => 2,
         -output  => \*STDERR
      }
   );
   exit;
}

#####################################
# Generate the HTML man page and display it

if ( getOption('htmlhelp') ) {
   if( !-e "$PROGRAM_NAME.css" ) {
      generate_css("$PROGRAM_NAME.css");
   }

   Pod::Html::pod2html(
      "--infile=$PROGRAM_NAME",
      "--outfile=$PROGRAM_NAME.html",
      "--css=$PROGRAM_NAME.css",
      "--title=$PROGRAM_NAME -- Reformat the PCGEN .lst files",
      '--header',
   );

   `start /max $PROGRAM_NAME.html`;

   exit;
}

my %source_tags        = ()  if LstTidy::Options::isConversionActive('SOURCE line replacement');
my $source_curent_file = q{} if LstTidy::Options::isConversionActive('SOURCE line replacement');

my %classskill_files   = ()  if LstTidy::Options::isConversionActive('CLASSSKILL conversion to CLASS');

my %classspell_files   = ()  if LstTidy::Options::isConversionActive('CLASSSPELL conversion to SPELL');

my %class_files        = ()  if LstTidy::Options::isConversionActive('SPELL:Add TYPE tags');
my %class_spelltypes   = ()  if LstTidy::Options::isConversionActive('SPELL:Add TYPE tags');

my %Spells_For_EQMOD   = ()  if LstTidy::Options::isConversionActive('EQUIPMENT: generate EQMOD');
my %Spell_Files        = ()  if LstTidy::Options::isConversionActive('EQUIPMENT: generate EQMOD')
                                || LstTidy::Options::isConversionActive('CLASS: SPELLLIST from Spell.MOD');

my %bonus_prexxx_tag_report = ()  if LstTidy::Options::isConversionActive('Generate BONUS and PRExxx report');

my %PREALIGN_conversion_5715 = qw(
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
) if LstTidy::Options::isConversionActive('ALL:PREALIGN conversion');

my %Key_conversion_56 = qw(
        BIND            BLIND
) if LstTidy::Options::isConversionActive('ALL:EQMOD has new keys');
#       ABENHABON       BNS_ENHC_AB
#       ABILITYMINUS    BNS_ENHC_AB
#       ABILITYPLUS     BNS_ENHC_AB
#       ACDEFLBON       BNS_AC_DEFL
#       ACENHABON       BNS_ENHC_AC
#       ACINSIBON       BNS_AC_INSI
#       ACLUCKBON       BNS_AC_LUCK
#       ACOTHEBON       BNS_AC_OTHE
#       ACPROFBON       BNS_AC_PROF
#       ACSACRBON       BNS_AC_SCRD
#       ADAARH          ADAM
#       ADAARH          ADAM
#       ADAARL          ADAM
#       ADAARM          ADAM
#       ADAWE           ADAM
#       AMINAT          ANMATD
#       AMMO+1          PLUS1W
#       AMMO+2          PLUS2W
#       AMMO+3          PLUS3W
#       AMMO+4          PLUS4W
#       AMMO+5          PLUS5W
#       AMMODARK        DARK
#       AMMOSLVR        SLVR
#       ARFORH          FRT_HVY
#       ARFORL          FRT_LGHT
#       ARFORM          FRT_MOD
#       ARMFOR          FRT_LGHT
#       ARMFORH         FRT_HVY
#       ARMFORM         FRT_MOD
#       ARMORENHANCE    BNS_ENHC_AC
#       ARMR+1          PLUS1A
#       ARMR+2          PLUS2A
#       ARMR+3          PLUS3A
#       ARMR+4          PLUS4A
#       ARMR+5          PLUS5A
#       ARMRADMH        ADAM
#       ARMRADML        ADAM
#       ARMRADMM        ADAM
#       ARMRMITH        MTHRL
#       ARMRMITL        MTHRL
#       ARMRMITM        MTHRL
#       ARWCAT          ARW_CAT
#       ARWDEF          ARW_DEF
#       BANEA           BANE_A
#       BANEM           BANE_M
#       BANER           BANE_R
#       BASHH           BASH_H
#       BASHL           BASH_L
#       BIND            BLIND
#       BONSPELL        BNS_SPELL
#       BONUSSPELL      BNS_SPELL
#       BRIENAI         BRI_EN_A
#       BRIENM          BRI_EN_M
#       BRIENT          BRI_EN_T
#       CHAOSA          CHAOS_A
#       CHAOSM          CHAOS_M
#       CHAOSR          CHAOS_R
#       CLDIRNAI        CIRON
#       CLDIRNW         CIRON
#       DAGSLVR         SLVR
#       DEFLECTBONUS    BNS_AC_DEFL
#       DRGNAR          DRACO
#       DRGNSH          DRACO
#       DRKAMI          DARK
#       DRKSH           DARK
#       DRKWE           DARK
#       ENBURM          EN_BUR_M
#       ENBURR          EN_BUR_R
#       ENERGM          ENERG_M
#       ENERGR          ENERG_R
#       FLAMA           FLM_A
#       FLAMM           FLM_M
#       FLAMR           FLM_R
#       FLBURA          FLM_BR_A
#       FLBURM          FLM_BR_M
#       FLBURR          FLM_BR_R
#       FROSA           FROST_A
#       FROSM           FROST_M
#       FROSR           FROST_R
#       GHTOUA          GHOST_A
#       GHTOUAM         GHOST_AM
#       GHTOUM          GHOST_M
#       GHTOUR          GHOST_R
#       HCLDIRNW        CIRON/2
#       HOLYA           HOLY_A
#       HOLYM           HOLY_M
#       HOLYR           HOLY_R
#       ICBURA          ICE_BR_A
#       ICBURM          ICE_BR_M
#       ICBURR          ICE_BR_R
#       LAWA            LAW_A
#       LAWM            LAW_M
#       LAWR            LAW_R
#       LUCKBONUS       BNS_SAV_LUC
#       LUCKBONUS2      BNS_SKL_LCK
#       MERCA           MERC_A
#       MERCM           MERC_M
#       MERCR           MERC_R
#       MICLE           MI_CLE
#       MITHAMI         MTHRL
#       MITHARH         MTHRL
#       MITHARL         MTHRL
#       MITHARM         MTHRL
#       MITHGO          MTHRL
#       MITHSH          MTHRL
#       MITHWE          MTHRL
#       NATENHA         BNS_ENHC_NAT
#       NATURALARMOR    BNS_ENHC_NAT
#       PLUS1AM         PLUS1W
#       PLUS1AMI        PLUS1W
#       PLUS1WI         PLUS1W
#       PLUS2AM         PLUS2W
#       PLUS2AMI        PLUS2W
#       PLUS2WI         PLUS2W
#       PLUS3AM         PLUS3W
#       PLUS3AMI        PLUS3W
#       PLUS3WI         PLUS3W
#       PLUS4AM         PLUS4W
#       PLUS4AMI        PLUS4W
#       PLUS4WI         PLUS4W
#       PLUS5AM         PLUS5W
#       PLUS5AMI        PLUS5W
#       PLUS5WI         PLUS5W
#       RESIMP          RST_IMP
#       RESIST          RST_IST
#       RESISTBONUS     BNS_SAV_RES
#       SAVINSBON       BNS_SAV_INS
#       SAVLUCBON       BNS_SAV_LUC
#       SAVOTHBON       BNS_SAV_OTH
#       SAVPROBON       BNS_SAV_PRO
#       SAVRESBON       BNS_SAV_RES
#       SAVSACBON       BNS_SAV_SAC
#       SE50CST         SPL_CHRG
#       SECW            SPL_CMD
#       SESUCAMA        A_1USEMI
#       SESUCAME        A_1USEMI
#       SESUCAMI        A_1USEMI
#       SESUCDMA        D_1USEMI
#       SESUCDME        D_1USEMI
#       SESUCDMI        D_1USEMI
#       SESUUA          SPL_1USE
#       SEUA            SPL_ACT
#       SE_1USEACT      SPL_1USE
#       SE_50TRIGGER    SPL_CHRG
#       SE_COMMANDWORD  SPL_CMD
#       SE_USEACT       SPL_ACT
#       SHBURA          SHK_BR_A
#       SHBURM          SHK_BR_M
#       SHBURR          SHK_BR_R
#       SHDGRT          SHDW_GRT
#       SHDIMP          SHDW_IMP
#       SHDOW           SHDW
#       SHFORH          FRT_HVY
#       SHFORL          FRT_LGHT
#       SHFORM          FRT_MOD
#       SHLDADAM        ADAM
#       SHLDDARK        DARK
#       SHLDMITH        MTHRL
#       SHOCA           SHOCK_A
#       SHOCM           SHOCK_M
#       SHOCR           SHOCK_R
#       SKILLBONUS      BNS_SKL_CIR
#       SKILLBONUS2     BNS_SKL_CMP
#       SKLCOMBON       BNS_SKL_CMP
#       SLICK           SLK
#       SLKGRT          SLK_GRT
#       SLKIMP          SLK_IMP
#       SLMV            SLNT_MV
#       SLMVGRT         SLNT_MV_GRT
#       SLMVIM          SLNT_MV_IM
#       SLVRAMI         ALCHM
#       SLVRWE1         ALCHM
#       SLVRWE2         ALCHM
#       SLVRWEF         ALCHM
#       SLVRWEH         ALCHM/2
#       SLVRWEL         ALCHM
#       SPELLRESI       BNS_SPL_RST
#       SPELLRESIST     BNS_SPL_RST
#       SPLRES          SPL_RST
#       SPLSTR          SPL_STR
#       THNDRA          THNDR_A
#       THNDRM          THNDR_M
#       THNDRR          THNDR_R
#       UNHLYA          UNHLY_A
#       UNHLYM          UNHLY_M
#       UNHLYR          UNHLY_R
#       WEAP+1          PLUS1W
#       WEAP+2          PLUS2W
#       WEAP+3          PLUS3W
#       WEAP+4          PLUS4W
#       WEAP+5          PLUS5W
#       WEAPADAM        ADAM
#       WEAPDARK        DARK
#       WEAPMITH        MTHRL
#       WILDA           WILD_A
#       WILDS           WILD_S
#       ) if LstTidy::Options::isConversionActive('ALL:EQMOD has new keys');

if(LstTidy::Options::isConversionActive('ALL:EQMOD has new keys'))
{
   my ($old_key,$new_key);
   while (($old_key,$new_key) = each %Key_conversion_56)
   {
      if($old_key eq $new_key) {
         print "==> $old_key\n";
         delete $Key_conversion_56{$old_key};
      }
   }
}

my %srd_weapon_name_conversion_433 = (
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
) if LstTidy::Options::isConversionActive('ALL: 4.3.3 Weapon name change');


# Constants for master_line_type

# Line importance (Mode)
use constant MAIN               => 1;      # Main line type for the file
use constant SUB                => 2;      # Sub line type, must be linked to a MAIN
use constant SINGLE     => 3;      # Idependant line type
use constant COMMENT    => 4;      # Comment or empty line.

# Line formatting option
use constant LINE                       => 1;   # Every line formatted by itself
use constant BLOCK              => 2;   # Lines formatted as a block
use constant FIRST_COLUMN       => 3;   # Only the first column of the block
                                                # gets aligned

# Line header option
use constant NO_HEADER          => 1;   # No header
use constant LINE_HEADER        => 2;   # One header before each line
use constant BLOCK_HEADER       => 3;   # One header for the block

# Standard YES NO constants
use constant NO  => 0;
use constant YES => 1;


my %double_PCC_tags = (
        'BONUS:ABILITYPOOL',    => 1,
        'BONUS:CASTERLEVEL',    => 1,
        'BONUS:CHECKS',         => 1,
        'BONUS:COMBAT',         => 1,
        'BONUS:DC',                     => 1,
        'BONUS:DOMAIN',         => 1,
        'BONUS:DR',                     => 1,
        'BONUS:FEAT',           => 1,
        'BONUS:FOLLOWERS',      => 1,
        'BONUS:HP',                     => 1,
        'BONUS:MISC',           => 1,
        'BONUS:MOVEADD',                => 1,
        'BONUS:MOVEMULT',               => 1,
        'BONUS:PCLEVEL',                => 1,
        'BONUS:POSTMOVEADD',    => 1,
        'BONUS:POSTRANGEADD',   => 1,
        'BONUS:RANGEADD',               => 1,
        'BONUS:RANGEMULT',      => 1,
        'BONUS:SITUATION',              => 1,
        'BONUS:SIZEMOD',                => 1,
        'BONUS:SKILL',          => 1,
        'BONUS:SKILLPOINTS',    => 1,
        'BONUS:SKILLPOOL',      => 1,
        'BONUS:SKILLRANK',      => 1,
        'BONUS:SLOTS',          => 1,
        'BONUS:SPECIALTYSPELLKNOWN',            => 1,
        'BONUS:SPELLCAST',      => 1,
        'BONUS:SPELLCASTMULT',  => 1,
        'BONUS:SPELLKNOWN',     => 1,
        'BONUS:STAT',           => 1,
        'BONUS:UDAM',           => 1,
        'BONUS:VAR',            => 1,
        'BONUS:VISION',         => 1,
        'BONUS:WEAPONPROF',     => 1,
        'BONUS:WIELDCATEGORY',  => 1,
 );


my @SOURCE_Tags = (
        'SOURCELONG',
        'SOURCESHORT',
        'SOURCEWEB',
        'SOURCEPAGE:.CLEAR',
        'SOURCEPAGE',
        'SOURCELINK',
);

my @QUALIFY_Tags = (
        'QUALIFY:ABILITY',
        'QUALIFY:CLASS',
        'QUALIFY:DEITY',
        'QUALIFY:DOMAIN',
        'QUALIFY:EQUIPMENT',
        'QUALIFY:EQMOD',
        'QUALIFY:FEAT',
        'QUALIFY:RACE',
        'QUALIFY:SPELL',
        'QUALIFY:SKILL',
        'QUALIFY:TEMPLATE',
        'QUALIFY:WEAPONPROF',
);

# [ 1956340 ] Centralize global BONUS tags
# The global BONUS:xxx tags. They are used in many of the line types.
# From now on, they are defined in only one place and every
# line type will get the same sort order.
# BONUSes only valid for specific line types are listed on those line types
my @Global_BONUS_Tags = (
        'BONUS:ABILITYPOOL:*',          # Global
        'BONUS:CASTERLEVEL:*',          # Global
        'BONUS:CHECKS:*',                       # Global        DEPRECATED
        'BONUS:COMBAT:*',                       # Global
        'BONUS:CONCENTRATION:*',                # Global
        'BONUS:DC:*',                   # Global
        'BONUS:DOMAIN:*',                       # Global
        'BONUS:DR:*',                   # Global
        'BONUS:FEAT:*',                 # Global
        'BONUS:FOLLOWERS',              # Global
        'BONUS:HP:*',                   # Global
        'BONUS:MISC:*',                 # Global
        'BONUS:MOVEADD:*',              # Global
        'BONUS:MOVEMULT:*',             # Global
        'BONUS:PCLEVEL:*',              # Global
        'BONUS:POSTMOVEADD:*',          # Global
        'BONUS:POSTRANGEADD:*',         # Global
        'BONUS:RANGEADD:*',             # Global
        'BONUS:RANGEMULT:*',            # Global
        'BONUS:SAVE:*',                         # Global        Replacement for CHECKS
        'BONUS:SITUATION:*',            # Global
        'BONUS:SIZEMOD:*',              # Global
        'BONUS:SKILL:*',                        # Global
        'BONUS:SKILLPOINTS:*',          # Global
        'BONUS:SKILLPOOL:*',            # Global
        'BONUS:SKILLRANK:*',            # Global
        'BONUS:SLOTS:*',                        # Global
        'BONUS:SPECIALTYSPELLKNOWN:*',                  # Global
        'BONUS:SPELLCAST:*',            # Global
        'BONUS:SPELLCASTMULT:*',        # Global
#       'BONUS:SPELLPOINTCOST:*',       # Global
        'BONUS:SPELLKNOWN:*',           # Global
        'BONUS:STAT:*',                 # Global
        'BONUS:UDAM:*',                 # Global
        'BONUS:VAR:*',                  # Global
        'BONUS:VISION:*',                       # Global
        'BONUS:WEAPONPROF:*',           # Global
        'BONUS:WIELDCATEGORY:*',        # Global
#       'BONUS:DAMAGE:*',                       # Deprecated
#       'BONUS:DEFINE:*',                       # Not listed in the Docs
#       'BONUS:EQM:*',                  # Equipment and EquipMod files only
#       'BONUS:EQMARMOR:*',             # Equipment and EquipMod files only
#       'BONUS:EQMWEAPON:*',            # Equipment and EquipMod files only
#       'BONUS:ESIZE:*',                        # Not listed in the Docs
#       'BONUS:HD',                             # Class Lines
#       'BONUS:LANGUAGES:*',            # Not listed in the Docs
#       'BONUS:LANG:*',                 # BONUS listed in the Code which is to be used instead of the deprecated BONUS:LANGNUM tag.
#       'BONUS:MONSKILLPTS',            # Templates
#       'BONUS:REPUTATION:*',           # Not listed in the Docs
#       'BONUS:RING:*',                 # Not listed in the Docs
#       'BONUS:SCHOOL:*',                       # Not listed in the Docs
#       'BONUS:SPELL:*',                        # Not listed in the Docs
#       'BONUS:TOHIT:*',                        # Deprecated
#       'BONUS:WEAPON:*',                       # Equipment and EquipMod files only
);

# Global tags allowed in PCC files.
my @double_PCC_tags = (
        'BONUS:ABILITYPOOL:*',          
        'BONUS:CASTERLEVEL:*',          
        'BONUS:CHECKS:*',                       
        'BONUS:COMBAT:*',                       
        'BONUS:CONCENTRATION:*',
        'BONUS:DC:*',                   
        'BONUS:DOMAIN:*',                       
        'BONUS:DR:*',                   
        'BONUS:FEAT:*',                 
        'BONUS:FOLLOWERS',              
        'BONUS:HP:*',                   
        'BONUS:MISC:*',                 
        'BONUS:MOVEADD:*',              
        'BONUS:MOVEMULT:*',             
        'BONUS:PCLEVEL:*',              
        'BONUS:POSTMOVEADD:*',          
        'BONUS:POSTRANGEADD:*',         
        'BONUS:RANGEADD:*',             
        'BONUS:RANGEMULT:*',            
        'BONUS:SAVE:*',                 
        'BONUS:SIZEMOD:*',              
        'BONUS:SKILL:*',                        
        'BONUS:SKILLPOINTS:*',          
        'BONUS:SKILLPOOL:*',            
        'BONUS:SKILLRANK:*',            
        'BONUS:SLOTS:*',                        
        'BONUS:SPECIALTYSPELLKNOWN:*',
        'BONUS:SPELLCAST:*',            
        'BONUS:SPELLCASTMULT:*',        
        'BONUS:SPELLKNOWN:*',           
        'BONUS:STAT:*',                 
        'BONUS:UDAM:*',                 
        'BONUS:VAR:*',                  
        'BONUS:VISION:*',                       
        'BONUS:WEAPONPROF:*',           
        'BONUS:WIELDCATEGORY:*',        
);      


# Order for the tags for each line type.
my %masterOrder = (

);

# Working variables
my %column_with_no_tag = (

        'ABILITY' => [
                '000AbilityName',
        ],

        'ABILITYCATEGORY' => [
                '000AbilityCategory',
        ],

        'ARMORPROF' => [
                '000ArmorName',
        ],

        'CLASS' => [
                '000ClassName',
        ],

        'CLASS Level' => [
                '000Level',
        ],

        'COMPANIONMOD' => [
                '000Follower',
        ],

        'DEITY' => [
                '000DeityName',
        ],

        'DOMAIN' => [
                '000DomainName',
        ],

        'EQUIPMENT' => [
                '000EquipmentName',
        ],

        'EQUIPMOD' => [
                '000ModifierName',
        ],

        'FEAT' => [
                '000FeatName',
        ],

        'LANGUAGE' => [
                '000LanguageName',
        ],

        'MASTERBONUSRACE' => [
                '000MasterBonusRace',
        ],

        'RACE' => [
                '000RaceName',
        ],

        'SHIELDPROF' => [
                '000ShieldName',
        ],

        'SKILL' => [
                '000SkillName',
        ],

        'SPELL' => [
                '000SpellName',
        ],

        'SUBCLASS' => [
                '000SubClassName',
        ],

        'SUBSTITUTIONCLASS' => [
                '000SubstitutionClassName',
        ],

        'TEMPLATE' => [
                '000TemplateName',
        ],

        'WEAPONPROF' => [
                '000WeaponName',
        ],

        'VARIABLE' => [
                '000VariableName',
        ],

        'DATACONTROL' => [
                '000DatacontrolName',
        ],

        'GLOBALMOD' => [
                '000GlobalmodName',
        ],

        'ALIGNMENT' => [
                '000AlignmentName',
        ],

        'SAVE' => [
                '000SaveName',
        ],

        'STAT' => [
                '000StatName',
        ],

);

# Added FACT:Basesize despite the fact that this appears to be unused arw - 20180830
my %token_FACT_tag = map { $_ => 1 } (
        'FACT:Abb',
        'FACT:AppliedName',
        'FACT:Basesize',
        'FACT:ClassType',
        'FACT:SpellType',
        'FACT:Symbol',
        'FACT:Worshippers',
        'FACT:Title',
        'FACT:Appearance',
        'FACT:RateOfFire',
);

my %token_FACTSET_tag = map { $_ => 1 } (
        'FACTSET:Pantheon',
        'FACTSET:Race',
);


my %token_ADD_tag = map { $_ => 1 } (
        'ADD:.CLEAR',
        'ADD:CLASSSKILLS',
        'ADD:DOMAIN',
        'ADD:EQUIP',
        'ADD:FAVOREDCLASS',
        'ADD:FEAT',                     # Deprecated
        'ADD:FORCEPOINT',               # Deprecated, never heard of this!
        'ADD:INIT',                     # Deprecated
        'ADD:LANGUAGE',
        'ADD:SAB',
        'ADD:SPECIAL',          # Deprecated - Remove 5.16 - Special abilities are now set using hidden feats or Abilities.
        'ADD:SPELLCASTER',
        'ADD:SKILL',
        'ADD:TEMPLATE',
        'ADD:WEAPONPROFS',
        'ADD:VFEAT',            # Deprecated
);

my %token_BONUS_tag = map { $_ => 1 } (
   'ABILITYPOOL',
   'CASTERLEVEL',
   'CHECKS',               # Deprecated
   'COMBAT',
   'CONCENTRATION',
   'DAMAGE',               # Deprecated 4.3.8 - Remove 5.16.0 - Use BONUS:COMBAT|DAMAGE.x|y
   'DC',
   'DOMAIN',
   'DR',
   'EQM',
   'EQMARMOR',
   'EQMWEAPON',
   'ESIZE',                # Not listed in the Docs
   'FEAT',         # Deprecated
   'FOLLOWERS',
   'HD',
   'HP',
   'ITEMCOST',
   'LANGUAGES',    # Not listed in the Docs
   'MISC',
   'MONSKILLPTS',
   'MOVE',         # Deprecated 4.3.8 - Remove 5.16.0 - Use BONUS:MOVEADD or BONUS:POSTMOVEADD
   'MOVEADD',
   'MOVEMULT',
   'POSTRANGEADD',
   'POSTMOVEADD',
   'PCLEVEL',
   'RANGEADD',
   'RANGEMULT',
   'REPUTATION',   # Not listed in the Docs
   'SIZEMOD',
   'SAVE',
   'SKILL',
   'SITUATION',
   'SKILLPOINTS',
   'SKILLPOOL',
   'SKILLRANK',
   'SLOTS',
   'SPELL',
   'SPECIALTYSPELLKNOWN',
   'SPELLCAST',
   'SPELLCASTMULT',
   'SPELLKNOWN',
   'VISION',
   'STAT',
   'TOHIT',                # Deprecated 5.3.12 - Remove 5.16.0 - Use BONUS:COMBAT|TOHIT|x
   'UDAM',
   'VAR',
   'WEAPON',
   'WEAPONPROF',
   'WIELDCATEGORY',
);

my %token_PROFICIENCY_tag = map { $_ => 1 } (
   'WEAPON',
   'ARMOR',
   'SHIELD',
);

my %token_QUALIFY_tag = map { $_ => 1 } (
   'ABILITY',
   'CLASS',
   'DEITY',
   'DOMAIN',
   'EQUIPMENT',
   'EQMOD',
   'FEAT',         # Deprecated
   'RACE',
   'SPELL',
   'SKILL',
   'TEMPLATE',
   'WEAPONPROF',
);

my %token_BONUS_MONSKILLPTS_types = map { $_ => 1 } (
        'LOCKNUMBER',
);

# List of types that are valid in BONUS:SLOTS
# 
my %token_BONUS_SLOTS_types = map { $_ => 1 } (
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

# [ 832171 ] AUTO:* needs to be separate tags
my @token_AUTO_tag = (
   'ARMORPROF',
   'EQUIP',
   'FEAT',         # Deprecated
   'LANG',
   'SHIELDPROF',
   'WEAPONPROF',
);

# Add the CHOOSE type.
# CHOOSE:xxx will not become separate tags but we need to be able to
# validate the different CHOOSE types.
my %token_CHOOSE_tag = map { $_ => 1 } (
        'ABILITY',
        'ABILITYSELECTION',
        'ALIGNMENT',
        'ARMORPROFICIENCY',
        'CHECK',
        'CLASS',
        'DEITY',
        'DOMAIN',
        'EQBUILDER.SPELL',              # EQUIPMENT ONLY
        'EQUIPMENT',
        'FEAT',
        'FEATSELECTION',
        'LANG',
        'LANGAUTO',             # Deprecated
        'NOCHOICE',
        'NUMBER',
        'NUMCHOICES',
        'PCSTAT',
        'RACE',
        'SCHOOLS',
        'SHIELDPROFICIENCY',
        'SIZE',
        'SKILL',
        'SKILLBONUS',
        'SPELLLEVEL',
        'SPELLS',
        'STATBONUS',            # EQUIPMENT ONLY
        'STRING',
        'TEMPLATE',
        'USERINPUT',
        'WEAPONFOCUS',
        'WEAPONPROFICIENCY',
        'STAT',                                 # Deprecated
        'WEAPONPROF',                   # Deprecated
        'WEAPONPROFS',                  # Deprecated
        'SPELLLIST',                    # Deprecated
        'SPELLCLASSES',                 # Deprecated
        'PROFICIENCY',                  # Deprecated
        'SHIELDPROF',                   # Deprecated
        'EQUIPTYPE',                    # Deprecated
        'CSKILLS',                              # Deprecated
        'HP',                                   # Deprecated 6.00 - Remove 6.02
        'CCSKILLLIST',                  # Deprecated 5.13.9 - Remove 5.16. Use CHOOSE:SKILLSNAMED instead.
        'ARMORTYPE',                    # Deprecated 
        'ARMORPROF',                    # Deprecated 5.15 - Remove 6.0
        'SKILLSNAMED',                  # Deprecated
        'SALIST',                               # Deprecated 6.00 - Remove 6.02
        'FEATADD',                              # Deprecated 5.15 - Remove 6.00
        'FEATLIST',                             # Deprecated 5.15 - Remove 6.00
        'FEATSELECT',                   # Deprecated 5.15 - Remove 6.00
);





################################################################################
# Global variables used by the validation code

# Will hold the portions of a race that have been matched with wildcards.
# For example, if Elf% has been matched (given no default Elf races).
my %race_partial_match; 

# Will hold the valid types for the TYPE. or TYPE= found in different tags.
# Format valid_types{$entitytype}{$typename}
my %valid_types;

# Will hold the valid categories for CATEGORY=
# found in abilities.
my %valid_categories;   

my %valid_sub_entities; # Will hold the entities that are allowed to include
                                # a sub-entity between () in their name.
                                # e.g. Skill Focus(Spellcraft)
                                # Format: $valid_sub_entities{$entity_type}{$entity_name}
                                #               = $sub_entity_type;
                                # e.g. :  $valid_sub_entities{'FEAT'}{'Skill Focus'} = 'SKILL';


# Add pre-defined valid entities
for my $var_name (LstTidy::Parse::getValidSystemArr('vars')) {
   LstTidy::Validate::setEntityValid('DEFINE Variable', $var_name);
}

for my $stat (@valid_system_stats) {
   LstTidy::Validate::setEntityValid('DEFINE Variable', $stat);
   LstTidy::Validate::setEntityValid('DEFINE Variable', $stat . 'SCORE');
}
# Add the magical values 'ATWILL' fot the SPELLS tag's TIMES= component.
LstTidy::Validate::setEntityValid('DEFINE Variable', 'ATWILL');

# Add the magical values 'UNLIM' fot the CONTAINS tag.
LstTidy::Validate::setEntityValid('DEFINE Variable', 'UNLIM');



# this is a temporary hack until we can move the actual parse routine into LstTidy Parse

INIT {
   
   # At this point everything is compiled, so we can pass a sub ref to
   # a helper module.

   LstTidy::Parse::setParseRoutine(\&FILETYPE_parse);

}

my $tablength = 6;      # Tabulation each 6 characters

my %files_to_parse;     # Will hold the file to parse (including path)
my @lines;                      # Will hold all the lines of the file
my @modified_files;     # Will hold the name of the modified files

#####################################
# Verify if the inputpath was given

if (getOption('inputpath')) {

   # Verify if the outputpath exist
   if ( getOption('outputpath') && !-d getOption('outputpath') ) {

      $error_message = "\nThe directory " . getOption('outputpath') . " does not exists.";

      Pod::Usage::pod2usage(
         {  -msg     => $error_message,
            -exitval => 1,
            -output  => \*STDERR,
         }
      );
      exit;
   }

   # Construct the valid tags for all file types
   LstTidy::Reformat::constructValidTags();

        ##########################################################
        # Files that needs to be open for special conversions

        if ( LstTidy::Options::isConversionActive('Export lists') ) {
                # The files should be opened in alpha order since they will
                # be closed in reverse alpha order.

                # Will hold the list of all classes found in CLASS filetypes
                open $filehandle_for{CLASS}, '>', 'class.csv';
                print { $filehandle_for{CLASS} } qq{"Class Name","Line","Filename"\n};

                # Will hold the list of all deities found in DEITY filetypes
                open $filehandle_for{DEITY}, '>', 'deity.csv';
                print { $filehandle_for{DEITY} } qq{"Deity Name","Line","Filename"\n};

                # Will hold the list of all domains found in DOMAIN filetypes
                open $filehandle_for{DOMAIN}, '>', 'domain.csv';
                print { $filehandle_for{DOMAIN} } qq{"Domain Name","Line","Filename"\n};

                # Will hold the list of all equipements found in EQUIPMENT filetypes
                open $filehandle_for{EQUIPMENT}, '>', 'equipment.csv';
                print { $filehandle_for{EQUIPMENT} } qq{"Equipment Name","Output Name","Line","Filename"\n};

                # Will hold the list of all equipmod entries found in EQUIPMOD filetypes
                open $filehandle_for{EQUIPMOD}, '>', 'equipmod.csv';
                print { $filehandle_for{EQUIPMOD} } qq{"Equipmod Name","Key","Type","Line","Filename"\n};

                # Will hold the list of all feats found in FEAT filetypes
                open $filehandle_for{FEAT}, '>', 'feat.csv';
                print { $filehandle_for{FEAT} } qq{"Feat Name","Line","Filename"\n};

                # Will hold the list of all kits found in KIT filetypes
                open $filehandle_for{KIT}, '>', 'kit.csv';
                print { $filehandle_for{KIT} } qq{"Kit Startpack Name","Line","Filename"\n};

                # Will hold the list of all kit Tables found in KIT filetypes
                open $filehandle_for{TABLE}, '>', 'kit-table.csv';
                print { $filehandle_for{TABLE} } qq{"Table Name","Line","Filename"\n};

                # Will hold the list of all language found in LANGUAGE linetypes
                open $filehandle_for{LANGUAGE}, '>', 'language.csv';
                print { $filehandle_for{LANGUAGE} } qq{"Language Name","Line","Filename"\n};

                # Will hold the list of all PCC files found
                open $filehandle_for{PCC}, '>', 'pcc.csv';
                print { $filehandle_for{PCC} } qq{"SOURCELONG","SOURCESHORT","GAMEMODE","Full Path"\n};

                # Will hold the list of all races and race types found in RACE filetypes
                open $filehandle_for{RACE}, '>', 'race.csv';
                print { $filehandle_for{RACE} } qq{"Race Name","Race Type","Race Subtype","Line","Filename"\n};

                # Will hold the list of all skills found in SKILL filetypes
                open $filehandle_for{SKILL}, '>', 'skill.csv';
                print { $filehandle_for{SKILL} } qq{"Skill Name","Line","Filename"\n};

                # Will hold the list of all spells found in SPELL filetypes
                open $filehandle_for{SPELL}, '>', 'spell.csv';
                print { $filehandle_for{SPELL} } qq{"Spell Name","Source Page","Line","Filename"\n};

                # Will hold the list of all templates found in TEMPLATE filetypes
                open $filehandle_for{TEMPLATE}, '>', 'template.csv';
                print { $filehandle_for{TEMPLATE} } qq{"Tempate Name","Line","Filename"\n};

                # Will hold the list of all variables found in DEFINE tags
                if ( getOption('xcheck') ) {
                open $filehandle_for{VARIABLE}, '>', 'variable.csv';
                print { $filehandle_for{VARIABLE} } qq{"Var Name","Line","Filename"\n};
                }

                # We need to list the tags that use Willpower
                if ( LstTidy::Options::isConversionActive('ALL:Find Willpower') ) {
                open $filehandle_for{Willpower}, '>', 'willpower.csv';
                print { $filehandle_for{Willpower} } qq{"Tag","Line","Filename"\n};
                }
        }

        ##########################################################
        # Cross-checking must be activated for the CLASSSPELL
        # conversion to work
        if ( LstTidy::Options::isConversionActive('CLASSSPELL conversion to SPELL') ) {
           setOption('xcheck', 1);
        }

        ##########################################################
        # Parse all the .pcc file to find the other file to parse

        # First, we list the .pcc files in the directory
        my @filelist;
        my %filelist_notpcc;
        my %filelist_missing;

        # Regular expressions for the files that must be skiped by mywanted.
        my @filetoskip = (
                qr(^\.\#),                      # Files begining with .# (CVS conflict and deleted files)
                qr(^custom),            # Customxxx files generated by PCGEN
                qr(placeholder\.txt$),  # The CMP directories are full of these
                qr(\.zip$)i,            # Archives present in the directories
                qr(\.rar$)i,
                qr(\.jpg$),                     # JPEG image files present in the directories
                qr(\.png$),                     # PNG image files present in the directories
#               gr(Thumbs\.db$),                # thumbnails image files used with Win32 OS
                qr(readme\.txt$),               # Readme files
#               qr(notes\.txt$),                # Notes files
                qr(\.bak$),                     # Backup files
                qr(\.java$),            # Java code files
                qr(\.htm$),                     # HTML files
                qr(\.xml$),
                qr(\.css$),

                qr(\.DS_Store$),                # Used with Mac OS
        );

        # Regular expressions for the directory that must be skiped by mywanted
        my @dirtoskip = (
                qr(cvs$)i,                      # /cvs directories
                qr([.]svn[/])i,         # All .svn directories
                qr([.]svn$)i,           # All .svn directories
                qr([.]git[/])i,         # All .git directories
                qr([.]git$)i,           # All .git directories
                qr(customsources$)i,    # /customsources (for files generated by PCGEN)
                qr(gamemodes)i,         # for the system gameModes directories
#               qr(alpha)i
        );

        sub mywanted {

                # We skip the files from directory matching the REGEX in @dirtoskip
                for my $regex (@dirtoskip) {
                        return if $File::Find::dir =~ $regex;
                }

                # We also skip the files that match the REGEX in @filetoskip
                for my $regex (@filetoskip) {
                        return if $_ =~ $regex;
                }

                if ( !-d && / [.] pcc \z /xmsi ) {
                        push @filelist, $File::Find::name;
                }

                if ( !-d && !/ [.] pcc \z /xmsi ) {
                        $filelist_notpcc{$File::Find::name} = lc $_;
                }
        }
        File::Find::find( \&mywanted, getOption('inputpath') );

        $log->header(LstTidy::LogHeader::get('PCC'));

        # Second we parse every .PCC and look for filetypes
        for my $pcc_file_name ( sort @filelist ) {
                open my $pcc_fh, '<', $pcc_file_name;

                # Needed to find the full path
                my $currentbasedir = File::Basename::dirname($pcc_file_name);

                my $must_write          = NO;
                my $BOOKTYPE_found      = NO;
                my $GAMEMODE_found      = q{};          # For the PCC export list
                my $SOURCELONG_found    = q{};          #
                my $SOURCESHORT_found   = q{};          #
                my $LST_found           = NO;
                my @pcc_lines           = ();
                my %found_filetype;
                my $continue            = YES;

                PCC_LINE:
                while ( <$pcc_fh> ) {
                last PCC_LINE if !$continue;

                chomp;
                $must_write += s/[\x0d\x0a]//g; # Remove the real and weird CR-LF
                $must_write += s/\s+$//;                # Remove the tralling white spaces

                push @pcc_lines, $_;

                my ( $tag, $value ) = parse_tag( $_, 'PCC', $pcc_file_name, $INPUT_LINE_NUMBER );

                if ( $tag && "$tag:$value" ne $pcc_lines[-1] ) {

                        # The parse_tag function modified the values.
                        $must_write = YES;
                        if ( $double_PCC_tags{$tag} ) {
                                $pcc_lines[-1] = "$tag$value";
                        }
                        else { 
                                $pcc_lines[-1] = "$tag:$value";
                        }
                }

                if ($tag) {
                        if (LstTidy::Parse::isParseableFileType($tag)) {

                                # Keep track of the filetypes found
                                $found_filetype{$tag}++;

                                $value =~ s/^([^|]*).*/$1/;
                                my $lstfile = find_full_path( $value, $currentbasedir, getOption('basepath') );
                                $files_to_parse{$lstfile} = $tag;

                                # Check to see if the file exists
                                if ( !-e $lstfile ) {
                                        $filelist_missing{$lstfile} = [ $pcc_file_name, $INPUT_LINE_NUMBER ];
                                        delete $files_to_parse{$lstfile};
                                }
                                elsif (LstTidy::Options::isConversionActive('SPELL:Add TYPE tags')
                                && $tag eq 'CLASS' )
                                {

                                        # [ 653596 ] Add a TYPE tag for all SPELLs
                                        #
                                        # The CLASS files must be read before any other
                                        $class_files{$lstfile} = 1;
                                }
                                elsif ( $tag eq 'SPELL' && ( LstTidy::Options::isConversionActive('EQUIPMENT: generate EQMOD')
                                        || LstTidy::Options::isConversionActive('CLASS: SPELLLIST from Spell.MOD') ) )
                                {

                                        #[ 677962 ] The DMG wands have no charge.
                                        #[ 779341 ] Spell Name.MOD to CLASS's SPELLLEVEL
                                        #
                                        # We keep a list of the SPELL files because they
                                        # need to be put in front of the others.

                                        $Spell_Files{$lstfile} = 1;
                                }
                                elsif ( LstTidy::Options::isConversionActive('CLASSSPELL conversion to SPELL')
                                && ( $tag eq 'CLASSSPELL' || $tag eq 'CLASS' || $tag eq 'DOMAIN' ) )
                                {

                                        # CLASSSPELL conversion
                                        # We keep the list of CLASSSPELL, CLASS and DOMAIN
                                        # since they must be parse before all the orthers.
                                        $classspell_files{$tag}{$lstfile} = 1;

                                        # We comment out the CLASSSPELL line
                                        if ( $tag eq 'CLASSSPELL' ) {
                                                push @pcc_lines, q{#} . pop @pcc_lines;
                                                $must_write = YES;

                                                $log->warning(
                                                        qq{Commenting out "$pcc_lines[$#pcc_lines]"},
                                                        $pcc_file_name,
                                                        $INPUT_LINE_NUMBER
                                                );
                                        }
                                }
                                elsif (LstTidy::Options::isConversionActive('CLASSSKILL conversion to CLASS')
                                && $tag eq 'CLASSSKILL' )
                                {

                                        # CLASSSKILL conversion
                                        # We keep the list of CLASSSKILL files
                                        $classskill_files{$lstfile} = 1;

                                        # Make a comment out of the line.
                                        push @pcc_lines, q{#} . pop @pcc_lines;
                                        $must_write = YES;

                                        $log->warning(
                                                qq{Commenting out "$pcc_lines[$#pcc_lines]"},
                                                $pcc_file_name,
                                                $INPUT_LINE_NUMBER
                                        );

                                }

                                #               ($lstfile) = ($lstfile =~ m{/([^/]+)$});
                                delete $filelist_notpcc{$lstfile} if exists $filelist_notpcc{$lstfile};
                                $LST_found = YES;

                        } elsif (LstTidy::Reformat::isValidTag('PCC', $tag)) {

                                # All the tags that do not have file should be cought here

                                # Get the SOURCExxx tags for future ref.
                                if (LstTidy::Options::isConversionActive('SOURCE line replacement')
                                && ( $tag eq 'SOURCELONG'
                                        || $tag eq 'SOURCESHORT'
                                        || $tag eq 'SOURCEWEB'
                                        || $tag eq 'SOURCEDATE' ) )
                                {
                                        my $path = File::Basename::dirname($pcc_file_name);
                                        if ( exists $source_tags{$path}{$tag}
                                                && $path !~ /custom|altpcc/i )
                                        {
                                                $log->notice(
                                                        "$tag already found for $path",
                                                        $pcc_file_name,
                                                        $INPUT_LINE_NUMBER
                                                );
                                        }
                                        else {
                                                $source_tags{$path}{$tag} = "$tag:$value";
                                        }

                                        # For the PCC report
                                        if ( $tag eq 'SOURCELONG' ) {
                                                $SOURCELONG_found = $value;
                                        }
                                        elsif ( $tag eq 'SOURCESHORT' ) {
                                                $SOURCESHORT_found = $value;
                                        }
                                }
                                elsif ( $tag eq 'GAMEMODE' ) {

                                        # Verify that the GAMEMODEs are valid
                                        # and match the filer.
                                        $GAMEMODE_found = $value;       # The GAMEMODE tag we found
                                        my @modes = split /[|]/, $value;

                                        my $gamemode = getOption('gamemode');
                                        my $gamemode_regex = $gamemode ? qr{ \A (?: $gamemode  ) \z }xmsi : qr{ . }xms;
                                        my $valid_game_mode = $gamemode ? 0 : 1;

                                        # First the filter is applied
                                        for my $mode (@modes) {
                                           if ( $mode =~ $gamemode_regex ) {
                                              $valid_game_mode = 1;
                                           }
                                        }

                                        # Then we check if the game mode is valid only if
                                        # the game modes have not been filtered out
                                        if ($valid_game_mode) {
                                           for my $mode (@modes) {
                                              if ( ! LstTidy::Parse::isValidGamemode($mode) ) {
                                                 $log->notice(
                                                    qq{Invalid GAMEMODE "$mode" in "$_"},
                                                    $pcc_file_name,
                                                    $INPUT_LINE_NUMBER
                                                 );
                                              }
                                           }
                                        }

                                        if ( !$valid_game_mode ) {
                                                # We set the variables that will kick us out of the
                                                # while loop that read the file and that will
                                                # prevent the file from being written.
                                                $continue               = NO;
                                                $must_write     = NO;
                                        }
                                }
                                elsif ( $tag eq 'BOOKTYPE' || $tag eq 'TYPE' ) {

                                        # Found a TYPE tag
                                        $BOOKTYPE_found = YES;
                                }
                                elsif ( $tag eq 'GAME' && LstTidy::Options::isConversionActive('PCC:GAME to GAMEMODE') ) {

                                        # [ 707325 ] PCC: GAME is now GAMEMODE
                                        $pcc_lines[-1] = "GAMEMODE:$value";
                                        $log->warning(
                                                qq{Replacing "$tag:$value" by "GAMEMODE:$value"},
                                                $pcc_file_name,
                                                $INPUT_LINE_NUMBER
                                        );
                                        $GAMEMODE_found = $value;
                                        $must_write     = YES;
                                }
                        }
                }
                elsif ( / <html> /xmsi ) {
                        $log->error(
                                "HTML file detected. Maybe you had a problem with your CSV checkout.\n",
                                $pcc_file_name
                        );
                        $must_write = NO;
                        last PCC_LINE;
                }
                }

                close $pcc_fh;

                if ( LstTidy::Options::isConversionActive('CLASSSPELL conversion to SPELL')
                        && $found_filetype{'CLASSSPELL'}
                        && !$found_filetype{'SPELL'} )
                {
                        $log->warning(
                                'No SPELL file found, create one.',
                                $pcc_file_name
                        );
                }

                if ( LstTidy::Options::isConversionActive('CLASSSKILL conversion to CLASS')
                        && $found_filetype{'CLASSSKILL'}
                        && !$found_filetype{'CLASS'} )
                {
                        $log->warning(
                                'No CLASS file found, create one.',
                                $pcc_file_name
                        );
                }

                if ( !$BOOKTYPE_found && $LST_found ) {
                        $log->notice( 'No BOOKTYPE tag found', $pcc_file_name );
                }

                if (!$GAMEMODE_found) {
                        $log->notice( 'No GAMEMODE tag found', $pcc_file_name );
                }

                if ( $GAMEMODE_found && getOption('exportlist') ) {
                        print { $filehandle_for{PCC} }
                                qq{"$SOURCELONG_found","$SOURCESHORT_found","$GAMEMODE_found","$pcc_file_name"\n};
                }

                # Do we copy the .PCC???
                if ( getOption('outputpath') && ( $must_write ) && LstTidy::Parse::isWriteableFileType("PCC") ) {
                        my $new_pcc_file = $pcc_file_name;
                        my $inputpath  = getOption('inputpath');
                        my $outputpath = getOption('outputpath');
                        $new_pcc_file =~ s/${inputpath}/${outputpath}/i;

                        # Create the subdirectory if needed
                        create_dir( File::Basename::dirname($new_pcc_file), getOption('outputpath') );

                        open my $new_pcc_fh, '>', $new_pcc_file;

                        # We keep track of the files we modify
                        push @modified_files, $pcc_file_name;

                        for my $line (@pcc_lines) {
                                print {$new_pcc_fh} "$line\n";
                        }

                        close $new_pcc_fh;
                }
        }

        # Is there anything to parse?
        if ( !keys %files_to_parse ) {
                $log->error(
                        qq{Could not find any .lst file to parse.},
                        getOption('inputpath')
                );
                $log->error(
                        qq{Is your -inputpath parameter valid? (} . getOption('inputpath') . ")",
                        getOption('inputpath')
                );
                if ( getOption('gamemode') ) {
                $log->error(
                        qq{Is your -gamemode parameter valid? (} . getOption('gamemode') . ")",
                        getOption('inputpath')
                );
                exit;
                }
        }

        # Missing .lst files must be printed
        if ( keys %filelist_missing ) {
           $log->header(LstTidy::LogHeader::get('Missing LST'));
           for my $lstfile ( sort keys %filelist_missing ) {
              $log->notice(
                 "Can't find the file: $lstfile",
                 $filelist_missing{$lstfile}[0],
                 $filelist_missing{$lstfile}[1]
              );
           }
        }

        # If the gamemode filter is active, we do not report files not refered to.
        if ( keys %filelist_notpcc && !getOption('gamemode') ) {
                $log->header(LstTidy::LogHeader::get('Unreferenced'));
                for my $file ( sort keys %filelist_notpcc ) {
                        my $basepath = getOption('basepath');
                        $file =~ s/${basepath}//i;
                        $file =~ tr{/}{\\} if $^O eq "MSWin32";
                        $log->notice(  "$file\n", "" );
                }
        }
}
else {
        $files_to_parse{'STDIN'} = getOption('filetype');
}

$log->header(LstTidy::LogHeader::get('LST'));

my @files_to_parse_sorted = ();
my %temp_files_to_parse   = %files_to_parse;

if ( LstTidy::Options::isConversionActive('SPELL:Add TYPE tags') ) {

        # The CLASS files must be put at the start of the
        # files_to_parse_sorted array in order for them
        # to be dealt with before the SPELL files.

        for my $class_file ( sort keys %class_files ) {
                push @files_to_parse_sorted, $class_file;
                delete $temp_files_to_parse{$class_file};
        }
}

if ( LstTidy::Options::isConversionActive('CLASSSPELL conversion to SPELL') ) {

        # The CLASS and DOMAIN files must be put at the start of the
        # files_to_parse_sorted array in order for them
        # to be dealt with before the CLASSSPELL files.
        # The CLASSSPELL needs to be processed before the SPELL files.

        # CLASS first
        for my $filetype (qw(CLASS DOMAIN CLASSSPELL)) {
                for my $file_name ( sort keys %{ $classspell_files{$filetype} } ) {
                push @files_to_parse_sorted, $file_name;
                delete $temp_files_to_parse{$file_name};
                }
        }
}

if ( keys %Spell_Files ) {

        # The SPELL file must be loaded before the EQUIPMENT
        # in order to properly generate the EQMOD tags or do
        # the Spell.MOD conversion to SPELLLEVEL.

        for my $file_name ( sort keys %Spell_Files ) {
                push @files_to_parse_sorted, $file_name;
                delete $temp_files_to_parse{$file_name};
        }
}

if ( LstTidy::Options::isConversionActive('CLASSSKILL conversion to CLASS') ) {

        # The CLASSSKILL files must be put at the start of the
        # files_to_parse_sorted array in order for them
        # to be dealt with before the CLASS files
        for my $file_name ( sort keys %classskill_files ) {
                push @files_to_parse_sorted, $file_name;
                delete $temp_files_to_parse{$file_name};
        }
}

# We sort the files that need to be parsed.
push @files_to_parse_sorted, sort keys %temp_files_to_parse;

FILE_TO_PARSE:
for my $file (@files_to_parse_sorted) {
        my $numberofcf = 0;     # Number of extra CF found in the file.

        my $filetype = "tab-based";   # can be either 'tab-based' or 'multi-line'

        if ( $file eq "STDIN" ) {

                # We read from STDIN
                # henkslaaf - Multiline parsing
                #       1) read all to a buffer (files are not so huge that it is a memory hog)
                #       2) send the buffer to a method that splits based on the type of file
                #       3) let the method return split and normalized entries
                #       4) let the method return a variable that says what kind of file it is (multi-line, tab-based)
                local $/ = undef; # read all from buffer
                my $buffer = <>;

                (my $lines, $filetype) = LstTidy::Parse::normaliseFile($buffer);
                @lines = @$lines;

        } else {

                # We read only what we know needs to be processed
                my $parseable = LstTidy::Parse::isParseableFileType($files_to_parse{$file});

                next FILE_TO_PARSE if ref( $parseable ) ne 'CODE';

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

                        (my $lines, $filetype) = LstTidy::Parse::normaliseFile($buffer);
                        @lines = @$lines;
                };

                if ( $EVAL_ERROR ) {
                # There was an error in the eval
                $log->error( $EVAL_ERROR, $file );
                next FILE_TO_PARSE;
                }
        }

        # If the file is empty, we skip it
        unless (@lines) {
                $log->notice(  "Empty file.", $file );
                next FILE_TO_PARSE;
        }

        # Check to see if we deal with a HTML file
        if ( grep /<html>/i, @lines ) {
                $log->error( "HTML file detected. Maybe you had a problem with your CSV checkout.\n", $file );
                next FILE_TO_PARSE;
        }

        # Read the full file into the @lines array
        chomp(@lines);

        # Remove and count the abnormal EOL character i.e. anything
        # that reminds after the chomp
        for my $line (@lines) {
                $numberofcf += $line =~ s/[\x0d\x0a]//g;
        }

        if($numberofcf) {
                $log->warning( "$numberofcf extra CF found and removed.", $file );
        }

        my $parser = LstTidy::Parse::isParseableFileType($files_to_parse{$file});

        if ( ref($parser) eq "CODE" ) {

                #       $file_for_error = $file;
                my ($newlines_ref) = &{ $parser }(
                                          $files_to_parse{$file},
                                          \@lines,
                                          $file
                                       );

                # Let's remove the tralling white spaces
                for my $line (@$newlines_ref) {
                $line =~ s/\s+$//;
                }

                # henkslaaf - we need to handle this in multi-line object files
                #       take the multi-line variable and use it to determine
                #       if we should skip writing this file

                # Some file types are never written
                warn "SKIP rewrite for $file because it is a multi-line file" if $filetype eq 'multi-line';
                next FILE_TO_PARSE if $filetype eq 'multi-line';                # we still need to implement rewriting for multi-line
                next FILE_TO_PARSE if ! LstTidy::Parse::isWriteableFileType( $files_to_parse{$file} );

                # We compare the result with the orginal file.
                # If there are no modification, we do not create the new files
                my $same  = NO;
                my $index = 0;

                # First, we check if there are obvious resons not to write the new file
                if (    !$numberofcf                                            # No extra CRLF char. were removed
                        && scalar(@lines) == scalar(@$newlines_ref)     # Same number of lines
                ) {
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

                next FILE_TO_PARSE if $same;

                my $write_fh;

                if (getOption('outputpath')) {
                        my $newfile = $file;
                        my $inputpath  =~ getOption('inputpath');
                        my $outputpath =~ getOption('outputpath');
                        $newfile =~ s/${inputpath}/${outputpath}/i;

                        # Create the subdirectory if needed
                        create_dir( File::Basename::dirname($newfile), getOption('outputpath') );

                        open $write_fh, '>', $newfile;

                        # We keep track of the files we modify
                        push @modified_files, $file;
                }
                else {
                        # Output to standard output
                        $write_fh = *STDOUT;
                }

                # The first line of the new file will be a comment line.
                print {$write_fh} "$today -- reformated by $SCRIPTNAME v$VERSION\n";

                # We print the result
                LINE:
                for my $line ( @{$newlines_ref} ) {
                        #$line =~ s/\s+$//;
                        print {$write_fh} "$line\n" if getOption('outputpath');
                }

                close $write_fh if getOption('outputpath');
        }
        else {
                warn "Didn't process filetype \"$files_to_parse{$file}\".\n";
        }
}

###########################################
# Generate the new BIOSET files

if ( LstTidy::Options::isConversionActive('BIOSET:generate the new files') ) {
        print STDERR "\n================================================================\n";
        print STDERR "List of new BIOSET files generated\n";
        print STDERR "----------------------------------------------------------------\n";

        generate_bioset_files();
}

###########################################
# Print a report with the modified files
if ( getOption('outputpath') && scalar(@modified_files) ) {
        my $outputpath = getOption('outputpath');
        $outputpath =~ tr{/}{\\} if $^O eq "MSWin32";

        $log->header(LstTidy::LogHeader::get('Created'), getOption('outputpath'));

        my $inputpath = getOption('inputpath');
        for my $file (@modified_files) {
                $file =~ s{ ${inputpath} }{}xmsi;
                $file =~ tr{/}{\\} if $^O eq "MSWin32";
                $log->notice( "$file\n", "" );
        }

        print STDERR "================================================================\n";
}

###########################################
# Print a report for the BONUS and PRExxx usage
if ( LstTidy::Options::isConversionActive('Generate BONUS and PRExxx report') ) {

        print STDERR "\n================================================================\n";
        print STDERR "List of BONUS and PRExxx tags by linetype\n";
        print STDERR "----------------------------------------------------------------\n";

        my $first = 1;
        for my $line_type ( sort keys %bonus_prexxx_tag_report ) {
                print STDERR "\n" unless $first;
                $first = 0;
                print STDERR "Line Type: $line_type\n";

                for my $tag ( sort keys %{ $bonus_prexxx_tag_report{$line_type} } ) {
                print STDERR "  $tag\n";
                }
        }

        print STDERR "================================================================\n";
}

if (getOption('report')) {
   LstTidy::Report::reportValid();
}

if (LstTidy::Report::foundInvalidTags()) {
   LstTidy::Report::reportValid();
}

if (getOption('xcheck')) {
   LstTidy::Report::doXCheck();
}

#########################################
# Close the files that were opened for
# special conversion

if ( LstTidy::Options::isConversionActive('Export lists') ) {
        # Close all the files in reverse order that they were opened
        for my $line_type ( reverse sort keys %filehandle_for ) {
                close $filehandle_for{$line_type};
        }
}

#########################################
# Close the redirected STDERR if needed

if (getOption('outputerror')) {
        close STDERR;
        print STDOUT "\cG";                     # An audible indication that PL has finished.
}

###############################################################################
###############################################################################
####                                                                       ####
####                            Subroutine Definitions                     ####
####                                                                       ####
###############################################################################
###############################################################################



###############################################################
# FILETYPE_parse
# --------------
#
# This function uses the information of LstTidy::Parse::parseControl to
# identify the curent line type and parse it.
#
# Parameters: $fileType       = The type of the file has defined by the .PCC file
#             $lines_ref      = Reference to an array containing all the lines of the file
#             $file = File name to use with ewarn

sub FILETYPE_parse {
   my ($fileType, $lines_ref, $file) = @_;

   ##################################################
   # Working variables

   my $curent_linetype = "";
   my $last_main_line  = -1;

   my $curent_entity;

   my @newlines;   # New line generated

   ##################################################
   ##################################################
   # Phase I - Split line in tokens and parse
   #               the tokens

   my $line = 1;
   LINE:
   for my $thisLine (@ {$lines_ref} ) {

      my $line_info;
     
      # Convert the line if that conversion is active, otherwise just copy it. 
      my $new_line = LstTidy::Options::isConversionActive('ALL:Fix Common Extended ASCII')
                        ? LstTidy::Convert::convertEntities($thisLine)
                        : $thisLine;

      # Remove spaces at the end of the line
      $new_line =~ s/\s+$//;

      # Remove spaces at the begining of the line
      $new_line =~ s/^\s+//;

      # Skip comments and empty lines
      if ( length($new_line) == 0 || $new_line =~ /^\#/ ) {

         # We push the line as is.
         push @newlines, [ $curent_linetype, $new_line, $last_main_line, undef, undef, ];
         next LINE;
      }
            
      ($line_info, $curent_entity) = LstTidy::Parse::matchLineType($new_line, $fileType); 

      # If we didn't find a record with info how to parse this line
      if ( ! defined $line_info ) {
         $log->warning(
            qq(Can\'t find the line type for "$new_line"),
            $file,
            $line
         );

         # We push the line as is.
         push @newlines, [ $curent_linetype, $new_line, $last_main_line, undef, undef, ];
         next LINE;
      }

      # What type of line is it?
      $curent_linetype = $line_info->{Linetype};
      if ( $line_info->{Mode} == MAIN ) {

         $last_main_line = $line - 1;

      } elsif ( $line_info->{Mode} == SUB ) {

         if ($last_main_line == -1) {
            $log->warning(
               qq{SUB line "$curent_linetype" is not preceded by a MAIN line},
               $file,
               $line
            )
         }

      } elsif ( $line_info->{Mode} == SINGLE ) {

         $last_main_line = -1;

      } else {

         die qq(Invalid type for $curent_linetype);
      }

      # Identify the deprecated tags.
      LstTidy::Parse::scanForDeprecatedTags( $new_line, $curent_linetype, $log, $file, $line );

      # Split the line in tokens
      my %line_tokens;

      # By default, the tab character is used
      my $sep = $line_info->{SepRegEx} || qr(\t+);

      # We split the tokens, strip the spaces and silently remove the empty tags
      # (empty tokens are the result of [tab][space][tab] type of chracter
      # sequences).
      # [ 975999 ] [tab][space][tab] breaks prettylst
      my @tokens = grep { $_ ne q{} } map { s{ \A \s* | \s* \z }{}xmsg; $_ } split $sep, $new_line;

      #First, we deal with the tag-less columns
      COLUMN:
      for my $column ( @{ $column_with_no_tag{$curent_linetype} } ) {

         # If the line has no tokens        
         if ( scalar @tokens == 0 ) {
            last COLUMN;
         }
         
         # Grab the token from the front of the line 
         my $token = shift @tokens;

         # We remove the enclosing quotes if any
         if ($current_token =~ s/^"(.*)"$/$1/) {
            $log->warning(
               qq{Removing quotes around the '$current_token' tag},
               $file,
               $line
            )
         }

         # and add it to line_tokens
         $line_tokens{$column} = [$token];

         # Statistic gathering
         LstTidy::Report::incCountValidTags($curent_linetype, $column);

         if ( index( $column, '000' ) == 0 && $line_info->{ValidateKeep} ) {
            LstTidy::Parse::process000($line_info, $token, $curent_linetype, $file, $line) = @_;
         }
      }

                #Second, let's parse the regular columns
                for my $token (@tokens) {
                        my $key = parse_tag($token, $curent_linetype, $file, $line);

                        if ($key) {
                                if ( exists $line_tokens{$key} && ! LstTidy::Reformat::isValidMultiTag($curent_linetype, $key) ) {
                                        $log->notice(
                                                qq{The tag "$key" should not be used more than once on the same $curent_linetype line.\n},
                                                $file,
                                                $line
                                        );
                                }

                        $line_tokens{$key}
                                = exists $line_tokens{$key} ? [ @{ $line_tokens{$key} }, $token ] : [$token];
                        }
                        else {
                                $log->warning( "No tags in \"$token\"\n", $file, $line );
                                $line_tokens{$token} = $token;
                        }
                }

                my $newline = [
                        $curent_linetype,
                        \%line_tokens,
                        $last_main_line,
                        $curent_entity,
                        $line_info,
                ];

                ############################################################
                ######################## Conversion ########################
                # We manipulate the tags for the line here
                # This function call will parse individual lines, which will
                # in turn parse the tags within the lines.

                additionnal_line_parsing(\%line_tokens, $curent_linetype, $file, $line, $newline);

                ############################################################
                # Validate the line
                validate_line(\%line_tokens, $curent_linetype, $file, $line)
                if getOption('xcheck');

                ############################################################
                # .CLEAR order verification
                check_clear_tag_order(\%line_tokens, $file, $line);

                #Last, we put the tokens and other line info in the @newlines array
                push @newlines, $newline;

        }
        continue { $line++ }

        #####################################################
        #####################################################
        # We find all the header lines
        for ( my $line_index = 0; $line_index < @newlines; $line_index++ ) {
                my $curent_linetype = $newlines[$line_index][0];
                my $line_tokens = $newlines[$line_index][1];
                my $next_linetype;
                $next_linetype = $newlines[ $line_index + 1 ][0]
                if $line_index + 1 < @newlines;

                # A header line either begins with the curent line_type header
                # or the next line header.
                #
                # Only comment -- $line_token is not a hash --  can be header lines
                if ( ref($line_tokens) ne 'HASH' ) {

                        # We are on a comment line, we need to find the
                        # curent and the next line header.



                        # Curent header
                        my $this_header =
                                $curent_linetype
                                ? LstTidy::Parse::getHeader( @{LstTidy::Reformat::getLineTypeOrder($curent_linetype)}[0], $curent_linetype )
                                : "";

                        # Next line header
                        my $next_header =
                                $next_linetype
                                ? LstTidy::Parse::getHeader( @{LstTidy::Reformat::getLineTypeOrder($next_linetype)}[0], $next_linetype )
                                : "";

                        if (   ( $this_header && index( $line_tokens, $this_header ) == 0 )
                                || ( $next_header && index( $line_tokens, $next_header ) == 0 ) )
                        {

                                # It is a header, let's tag it as such.
                                $newlines[$line_index] = [ 'HEADER', $line_tokens, ];
                        } else {

                                # It is just a comment, we won't botter with it ever again.
                                $newlines[$line_index] = $line_tokens;
                        }
                }
        }


        #################################################################
        ######################## Conversion #############################
        # We manipulate the tags for the whole file here

        additionnal_file_parsing(\@newlines, $fileType, $file);

        ##################################################
        ##################################################
        # Phase II - Reformating the lines

        # No reformating needed?
        return $lines_ref unless getOption('outputpath') && LstTidy::Parse::isWriteableFileType($fileType);

        # Now on to all the non header lines.
        CORE_LINE:
        for ( my $line_index = 0; $line_index < @newlines; $line_index++ ) {

                # We skip the text lines and the header lines
                next CORE_LINE
                if ref( $newlines[$line_index] ) ne 'ARRAY'
                || $newlines[$line_index][0] eq 'HEADER';

                my $line_ref = $newlines[$line_index];
                my ($curent_linetype, $line_tokens, $last_main_line,
                $curent_entity,   $line_info
                )
                = @$line_ref;
                my $newline = "";

                # If the separator is not a tab, with just join the
                # tag in order
                my $sep = $line_info->{Sep} || "\t";
                if ( $sep ne "\t" ) {

                # First, the tag known in masterOrder
                for my $tag ( @{LstTidy::Reformat::getLineTypeOrder($curent_linetype)} ) {
                        if ( exists $line_tokens->{$tag} ) {
                                $newline .= join $sep, @{ $line_tokens->{$tag} };
                                $newline .= $sep;
                                delete $line_tokens->{$tag};
                        }
                }

                # The remaining tag are not in the masterOrder list
                for my $tag ( sort keys %$line_tokens ) {
                        $newline .= join $sep, @{ $line_tokens->{$tag} };
                        $newline .= $sep;
                }

                # We remove the extra separator
                for ( my $i = 0; $i < length($sep); $i++ ) {
                        chop $newline;
                }

                # We replace line_ref with the new line
                $newlines[$line_index] = $newline;
                next CORE_LINE;
                }

                ##################################################
                # The line must be formatted according to its
                # TYPE, FORMAT and HEADER parameters.

                my $mode   = $line_info->{Mode};
                my $format = $line_info->{Format};
                my $header = $line_info->{Header};

                if ( $mode == SINGLE || $format == LINE ) {

                # LINE: the line if formatted independently.
                #               The FORMAT is ignored.
                if ( $header == NO_HEADER ) {

                        # Just put the line in order and with a single tab
                        # between the columns. If there is a header in the previous
                        # line, we remove it.

                        # First, the tag known in masterOrder
                        for my $tag ( @{LstTidy::Reformat::getLineTypeOrder($curent_linetype)} ) {
                                if ( exists $line_tokens->{$tag} ) {
                                $newline .= join $sep, @{ $line_tokens->{$tag} };
                                $newline .= $sep;
                                delete $line_tokens->{$tag};
                                }
                        }

                        # The remaining tag are not in the masterOrder list
                        for my $tag ( sort keys %$line_tokens ) {
                                $newline .= join $sep, @{ $line_tokens->{$tag} };
                                $newline .= $sep;
                        }

                        # We remove the extra separator
                        for ( my $i = 0; $i < length($sep); $i++ ) {
                                chop $newline;
                        }

                        # If there was an header before this line, we remove it
                        if ( ref( $newlines[ $line_index - 1 ] ) eq 'ARRAY'
                                && $newlines[ $line_index - 1 ][0] eq 'HEADER' )
                        {
                                splice( @newlines, $line_index - 1, 1 );
                                $line_index--;
                        }

                        # Replace the array with the new line
                        $newlines[$line_index] = $newline;
                        next CORE_LINE;
                }
                elsif ( $header == LINE_HEADER ) {

                        # Put the line with a header in front of it.
                        my %col_length  = ();
                        my $header_line = "";
                        my $line_entity = "";

                        # Find the length for each column
                        $col_length{$_} = mylength( $line_tokens->{$_} ) for ( keys %$line_tokens );

                        # Find the columns order and build the header and
                        # the curent line
                        TAG_NAME:
                        for my $tag ( @{LstTidy::Reformat::getLineTypeOrder($curent_linetype)} ) {

                                # We skip the tag is not present
                                next TAG_NAME if !exists $col_length{$tag};

                                # The first tag is the line entity and most be kept
                                $line_entity = $line_tokens->{$tag}[0] unless $line_entity;

                                # What is the length of the column?
                                my $header_text   = LstTidy::Parse::getHeader( $tag, $curent_linetype );
                                my $header_length = mylength($header_text);
                                my $col_length    = $header_length > $col_length{$tag}
                                                       ? $header_length
                                                       : $col_length{$tag};

                                # Round the col_length up to the next tab
                                $col_length = $tablength * ( int( $col_length / $tablength ) + 1 );

                                # The header
                                my $tab_to_add = int( ( $col_length - $header_length ) / $tablength )
                                + ( ( $col_length - $header_length ) % $tablength ? 1 : 0 );
                                $header_line .= $header_text . $sep x $tab_to_add;

                                # The line
                                $tab_to_add = int( ( $col_length - $col_length{$tag} ) / $tablength )
                                + ( ( $col_length - $col_length{$tag} ) % $tablength ? 1 : 0 );
                                $newline .= join $sep, @{ $line_tokens->{$tag} };
                                $newline .= $sep x $tab_to_add;

                                # Remove the tag we just dealt with
                                delete $line_tokens->{$tag};
                        }

                        # Add the tags that were not in the masterOrder
                        for my $tag ( sort keys %$line_tokens ) {

                                # What is the length of the column?
                                my $header_text   = LstTidy::Parse::getHeader( $tag, $curent_linetype );
                                my $header_length = mylength($header_text);
                                my $col_length  =
                                        $header_length > $col_length{$tag}
                                ? $header_length
                                : $col_length{$tag};

                                # Round the col_length up to the next tab
                                $col_length = $tablength * ( int( $col_length / $tablength ) + 1 );

                                # The header
                                my $tab_to_add = int( ( $col_length - $header_length ) / $tablength )
                                + ( ( $col_length - $header_length ) % $tablength ? 1 : 0 );
                                $header_line .= $header_text . $sep x $tab_to_add;

                                # The line
                                $tab_to_add = int( ( $col_length - $col_length{$tag} ) / $tablength )
                                + ( ( $col_length - $col_length{$tag} ) % $tablength ? 1 : 0 );
                                $newline .= join $sep, @{ $line_tokens->{$tag} };
                                $newline .= $sep x $tab_to_add;
                        }

                        # Remove the extra separators (tabs) at the end of both lines
                        $header_line =~ s/$sep$//g;
                        $newline        =~ s/$sep$//g;

                        # Put the header in place
                        if ( ref( $newlines[ $line_index - 1 ] ) eq 'ARRAY'
                                && $newlines[ $line_index - 1 ][0] eq 'HEADER' )
                        {

                                # We replace the existing header
                                $newlines[ $line_index - 1 ] = $header_line;
                        }
                        else {

                                # We add the header before the line
                                splice( @newlines, $line_index++, 0, $header_line );
                        }

                        # Add an empty line in front of the header unless
                        # there is already one or the previous line
                        # match the line entity.
                        if ( $newlines[ $line_index - 2 ] ne ''
                                && index( $newlines[ $line_index - 2 ], $line_entity ) != 0 )
                        {
                                splice( @newlines, $line_index - 1, 0, '' );
                                $line_index++;
                        }

                        # Replace the array with the new line
                        $newlines[$line_index] = $newline;
                        next CORE_LINE;
                }
                else {

                        # Invalid option
                        die "Invalid \%LstTidy::Parse::parseControl options: $fileType:$curent_linetype:$mode:$header";
                }
                }
                elsif ( $mode == MAIN ) {
                if ( $format == BLOCK ) {
                        #####################################
                        # All the main lines must be found
                        # up until a different main line type
                        # or a ###Block comment.
                        my @main_lines;
                        my $main_linetype = $curent_linetype;

                        BLOCK_LINE:
                        for ( my $index = $line_index; $index < @newlines; $index++ ) {

                                # If the line_type  change or
                                # if a '###Block' comment is found,
                                # we are out of the block
                                last BLOCK_LINE
                                if ( ref( $newlines[$index] ) eq 'ARRAY'
                                && ref $newlines[$index][4] eq 'HASH'
                                && $newlines[$index][4]{Mode} == MAIN
                                && $newlines[$index][0] ne $main_linetype )
                                || ( ref( $newlines[$index] ) ne 'ARRAY'
                                && index( lc( $newlines[$index] ), '###block' ) == 0 );

                                # Skip the lines already dealt with
                                next BLOCK_LINE
                                if ref( $newlines[$index] ) ne 'ARRAY'
                                || $newlines[$index][0] eq 'HEADER';

                                push @main_lines, $index
                                if $newlines[$index][4]{Mode} == MAIN;
                        }

                        #####################################
                        # We find the length of each tag for the block
                        my %col_length;
                        for my $block_line (@main_lines) {
                                for my $tag ( keys %{ $newlines[$block_line][1] } ) {
                                my $col_length = mylength( $newlines[$block_line][1]{$tag} );
                                $col_length{$tag} = $col_length
                                        if !exists $col_length{$tag} || $col_length > $col_length{$tag};
                                }
                        }

                        if ( $header != NO_HEADER ) {

                                # We add the length of the headers if needed.
                                for my $tag ( keys %col_length ) {
                                my $length = mylength( LstTidy::Parse::getHeader( $tag, $fileType ) );

                                $col_length{$tag} = $length if $length > $col_length{$tag};
                                }
                        }

                        #####################################
                        # Find the columns order
                        my %seen;
                        my @col_order;

                        # First, the columns included in masterOrder
                        for my $tag ( @{LstTidy::Reformat::getLineTypeOrder($curent_linetype)} ) {
                                push @col_order, $tag if exists $col_length{$tag};
                                $seen{$tag}++;
                        }

                        # Put the unknown columns at the end
                        for my $tag ( sort keys %col_length ) {
                                push @col_order, $tag unless $seen{$tag};
                        }

                        # Each of the block lines must be reformated
                        for my $block_line (@main_lines) {
                                my $newline;

                                for my $tag (@col_order) {
                                my $col_max_length
                                        = $tablength * ( int( $col_length{$tag} / $tablength ) + 1 );

                                # Is the tag present in this line?
                                if ( exists $newlines[$block_line][1]{$tag} ) {
                                        my $curent_length = mylength( $newlines[$block_line][1]{$tag} );

                                        my $tab_to_add
                                                = int( ( $col_max_length - $curent_length ) / $tablength )
                                                + ( ( $col_max_length - $curent_length ) % $tablength ? 1 : 0 );
                                        $newline .= join $sep, @{ $newlines[$block_line][1]{$tag} };
                                        $newline .= $sep x $tab_to_add;
                                }
                                else {

                                        # We pad with tabs
                                        $newline .= $sep x ( $col_max_length / $tablength );
                                }
                                }

                                # We remove the extra $sep at the end
                                $newline =~ s/$sep+$//;

                                # We replace the array with the new line
                                $newlines[$block_line] = $newline;
                        }

                        if ( $header == NO_HEADER ) {

                                # If there are header before any of the block line,
                                # we need to remove them
                                for my $block_line ( reverse @main_lines ) {
                                if ( ref( $newlines[ $block_line - 1 ] ) eq 'ARRAY'
                                        && $newlines[ $block_line - 1 ][0] eq 'HEADER' )
                                {
                                        splice( @newlines, $block_line - 1, 1 );
                                        $line_index--;
                                }
                                }
                        }
                        elsif ( $header == LINE_HEADER ) {
                                die "MAIN:BLOCK:LINE_HEADER not implemented yet";
                        }
                        elsif ( $header == BLOCK_HEADER ) {

                                # We must add the header line at the top of the block
                                # and anywhere else we find them whitin the block.

                                my $header_line;
                                for my $tag (@col_order) {

                                # Round the col_length up to the next tab
                                my $col_max_length
                                        = $tablength * ( int( $col_length{$tag} / $tablength ) + 1 );
                                my $curent_header = LstTidy::Parse::getHeader( $tag, $main_linetype );
                                my $curent_length = mylength($curent_header);
                                my $tab_to_add  = int( ( $col_max_length - $curent_length ) / $tablength )
                                        + ( ( $col_max_length - $curent_length ) % $tablength ? 1 : 0 );
                                $header_line .= $curent_header . $sep x $tab_to_add;
                                }

                                # We remove the extra $sep at the end
                                $header_line =~ s/$sep+$//;

                                # Before the top of the block
                                my $need_top_header = NO;
                                if ( ref( $newlines[ $main_lines[0] - 1 ] ) ne 'ARRAY'
                                || $newlines[ $main_lines[0] - 1 ][0] ne 'HEADER' )
                                {
                                $need_top_header = YES;
                                }

                                # Anywhere in the block
                                for my $block_line (@main_lines) {
                                if ( ref( $newlines[ $block_line - 1 ] ) eq 'ARRAY'
                                        && $newlines[ $block_line - 1 ][0] eq 'HEADER' )
                                {
                                        $newlines[ $block_line - 1 ] = $header_line;
                                }
                                }

                                # Add a header line at the top of the block
                                if ($need_top_header) {
                                splice( @newlines, $main_lines[0], 0, $header_line );
                                $line_index++;
                                }

                        }
                }
                else {
                        die "Invalid \%LstTidy::Parse::parseControl format: $fileType:$curent_linetype:$mode:$header";
                }
                }
                elsif ( $mode == SUB ) {
                if ( $format == LINE ) {
                        die "SUB:LINE not implemented yet";
                }
                elsif ( $format == BLOCK || $format == FIRST_COLUMN ) {
                        #####################################
                        # Need to find all the file in the SUB BLOCK i.e. same
                        # line type within two MAIN lines.
                        # If we encounter a ###Block comment, that's the end
                        # of the block
                        my @sub_lines;
                        my $begin_block  = $last_main_line;
                        my $sub_linetype = $curent_linetype;

                        BLOCK_LINE:
                        for ( my $index = $line_index; $index < @newlines; $index++ ) {

                                # If the last_main_line change or
                                # if a '###Block' comment is found,
                                # we are out of the block
                                last BLOCK_LINE
                                if ( ref( $newlines[$index] ) eq 'ARRAY'
                                && $newlines[$index][0] ne 'HEADER'
                                && $newlines[$index][2] != $begin_block )
                                || ( ref( $newlines[$index] ) ne 'ARRAY'
                                && index( lc( $newlines[$index] ), '###block' ) == 0 );

                                # Skip the lines already dealt with
                                next BLOCK_LINE
                                if ref( $newlines[$index] ) ne 'ARRAY'
                                || $newlines[$index][0] eq 'HEADER';

                                push @sub_lines, $index
                                if $newlines[$index][0] eq $curent_linetype;
                        }

                        #####################################
                        # We find the length of each tag for the block
                        my %col_length;
                        for my $block_line (@sub_lines) {
                                for my $tag ( keys %{ $newlines[$block_line][1] } ) {
                                my $col_length = mylength( $newlines[$block_line][1]{$tag} );
                                $col_length{$tag} = $col_length
                                        if !exists $col_length{$tag} || $col_length > $col_length{$tag};
                                }
                        }

                        if ( $header == BLOCK_HEADER ) {

                                # We add the length of the headers if needed.
                                for my $tag ( keys %col_length ) {
                                my $length = mylength( LstTidy::Parse::getHeader( $tag, $fileType ) );

                                $col_length{$tag} = $length if $length > $col_length{$tag};
                                }
                        }

                        #####################################
                        # Find the columns order
                        my %seen;
                        my @col_order;

                        # First, the columns included in masterOrder
                        for my $tag ( @{LstTidy::Reformat::getLineTypeOrder($curent_linetype)} ) {
                                push @col_order, $tag if exists $col_length{$tag};
                                $seen{$tag}++;
                        }

                        # Put the unknown columns at the end
                        for my $tag ( sort keys %col_length ) {
                                push @col_order, $tag unless $seen{$tag};
                        }

                        # Each of the block lines must be reformated
                        if ( $format == BLOCK ) {
                                for my $block_line (@sub_lines) {
                                my $newline;

                                for my $tag (@col_order) {
                                        my $col_max_length
                                                = $tablength * ( int( $col_length{$tag} / $tablength ) + 1 );

                                        # Is the tag present in this line?
                                        if ( exists $newlines[$block_line][1]{$tag} ) {
                                                my $curent_length = mylength( $newlines[$block_line][1]{$tag} );

                                                my $tab_to_add
                                                = int( ( $col_max_length - $curent_length ) / $tablength )
                                                + ( ( $col_max_length - $curent_length ) % $tablength ? 1 : 0 );
                                                $newline .= join $sep, @{ $newlines[$block_line][1]{$tag} };
                                                $newline .= $sep x $tab_to_add;
                                        }
                                        else {

                                                # We pad with tabs
                                                $newline .= $sep x ( $col_max_length / $tablength );
                                        }
                                }

                                # We replace the array with the new line
                                $newlines[$block_line] = $newline;
                                }
                        }
                        else {

                                # $format == FIRST_COLUMN

                                for my $block_line (@sub_lines) {
                                my $newline;
                                my $first_column = YES;
                                my $tab_to_add;

                                TAG:
                                for my $tag (@col_order) {

                                        # Is the tag present in this line?
                                        next TAG if !exists $newlines[$block_line][1]{$tag};

                                        if ($first_column) {
                                                my $col_max_length
                                                = $tablength * ( int( $col_length{$tag} / $tablength ) + 1 );
                                                my $curent_length = mylength( $newlines[$block_line][1]{$tag} );

                                                $tab_to_add
                                                = int( ( $col_max_length - $curent_length ) / $tablength )
                                                + ( ( $col_max_length - $curent_length ) % $tablength ? 1 : 0 );

                                                # It's no longer the first column
                                                $first_column = NO;
                                        }
                                        else {
                                                $tab_to_add = 1;
                                        }

                                        $newline .= join $sep, @{ $newlines[$block_line][1]{$tag} };
                                        $newline .= $sep x $tab_to_add;
                                }

                                # We replace the array with the new line
                                $newlines[$block_line] = $newline;
                                }
                        }

                        if ( $header == NO_HEADER ) {

                                # If there are header before any of the block line,
                                # we need to remove them
                                for my $block_line ( reverse @sub_lines ) {
                                if ( ref( $newlines[ $block_line - 1 ] ) eq 'ARRAY'
                                        && $newlines[ $block_line - 1 ][0] eq 'HEADER' )
                                {
                                        splice( @newlines, $block_line - 1, 1 );
                                        $line_index--;
                                }
                                }
                        }
                        elsif ( $header == LINE_HEADER ) {
                                die "SUB:BLOCK:LINE_HEADER not implemented yet";
                        }
                        elsif ( $header == BLOCK_HEADER ) {

                                # We must add the header line at the top of the block
                                # and anywhere else we find them whitin the block.

                                my $header_line;
                                for my $tag (@col_order) {

                                # Round the col_length up to the next tab
                                my $col_max_length
                                        = $tablength * ( int( $col_length{$tag} / $tablength ) + 1 );
                                my $curent_header = LstTidy::Parse::getHeader( $tag, $sub_linetype );
                                my $curent_length = mylength($curent_header);
                                my $tab_to_add  = int( ( $col_max_length - $curent_length ) / $tablength )
                                        + ( ( $col_max_length - $curent_length ) % $tablength ? 1 : 0 );
                                $header_line .= $header . $sep x $tab_to_add;
                                }

                                # Before the top of the block
                                my $need_top_header = NO;
                                if ( ref( $newlines[ $sub_lines[0] - 1 ] ) ne 'ARRAY'
                                || $newlines[ $sub_lines[0] - 1 ][0] ne 'HEADER' )
                                {
                                $need_top_header = YES;
                                }

                                # Anywhere in the block
                                for my $block_line (@sub_lines) {
                                if ( ref( $newlines[ $block_line - 1 ] ) eq 'ARRAY'
                                        && $newlines[ $block_line - 1 ][0] eq 'HEADER' )
                                {
                                        $newlines[ $block_line - 1 ] = $header_line;
                                }
                                }

                                # Add a header line at the top of the block
                                if ($need_top_header) {
                                splice( @newlines, $sub_lines[0], 0, $header_line );
                                $line_index++;
                                }

                        }
                        else {
                                die "Invalid \%LstTidy::Parse::parseControl $curent_linetype:$mode:$format:$header";
                        }
                }
                else {
                        die "Invalid \%LstTidy::Parse::parseControl $curent_linetype:$mode:$format:$header";
                }
                }
                else {
                die "Invalid \%LstTidy::Parse::parseControl mode: $fileType:$curent_linetype:$mode";
                }

        }

        # If there are header lines remaining, we keep the old value
        for (@newlines) {
                $_ = $_->[1] if ref($_) eq 'ARRAY' && $_->[0] eq 'HEADER';
        }

        return \@newlines;

}

###############################################################
# parse_ADD_tag
# -------------
#
# The ADD tag has a very adlib form. It can be many of the
# ADD:Token define in the master_list but is also can be
# of the form ADD:Any test whatsoever(...). And there is also
# the fact that the ':' is used in the name...
#
# In short, it's a pain.
#
# The above describes the pre 5.12 syntax
# For 5.12, the syntax has changed.
# It is now:
# ADD:subtoken[|number]|blah
#
# This function return a list of three elements.
#   The first one is a return code
#   The second one is the effective TAG if any
#   The third one is anything found after the tag if any
#   The fourth one is the count if one is detected
#
#   Return code 0 = no valid ADD tag found,
#                       1 = old format token ADD tag found,
#                       2 = old format adlib ADD tag found.
#                       3 = 5.12 format ADD tag, using known token.
#                       4 = 5.12 format ADD tag, not using token.

sub parse_ADD_tag {
   my $tag = shift;

   my ($token, $therest, $num_count, $optionlist) = ("", "", 0, "");

   # Old Format
   if ($tag =~ /\s*ADD:([^\(]+)\((.+)\)(\d*)/) {

      ($token, $therest, $num_count) = ($1, $2, $3);

      if (!$num_count) { 
         $num_count = 1; 
      }

      # Is it a known token?
      if ( exists $token_ADD_tag{"ADD:$token"} ) {
         return ( 1, "ADD:$token", $therest, $num_count );

      # Is it the right form? => ADD:any text(any text)
      # Note that no check is done to see if the () are balanced.
      # elsif ( $therest =~ /^\((.*)\)(\d*)\s*$/ ) {
      } else {
         return ( 2, "ADD:$token", $therest, $num_count);
      }
   }

   # New format ADD tag.
   if ($tag =~ /\s*ADD:([^\|]+)(\|\d+)?\|(.+)/) {

      ($token, $num_count, $optionlist) = ($1, $2, $3);

      if (!$num_count) { 
         $num_count = 1;
      }

      if ( exists $token_ADD_tag{"ADD:$token"}) {
         return ( 3, "ADD:$token", $optionlist, $num_count);
      } else {
         return ( 4, "ADD:$token", $optionlist, $num_count);
      }
   }

   # Not a good ADD tag.
   return ( 0, "", undef, 0 );
}

###############################################################
# parse_tag
# ---------
#
# This function
#
# Most commun use is for addition, conversion or removal of tags.
#
# Paramter: $tag_text           Text to parse
#               $linetype               Type for the current line
#               $file_for_error   Name of the current file
#               $line_for_error   Number of the current line
#
# Return:   in scallar context, return $tag
#               in array context, return ($tag,$value)

sub parse_tag {
        my ( $tag_text, $linetype, $file_for_error, $line_for_error ) = @_;
        my $no_more_error = 0;  # Set to 1 if no more error must be displayed.

        # We remove the enclosing quotes if any
        $log->warning( qq{Removing quotes around the '$tag_text' tag}, $file_for_error, $line_for_error)
                if $tag_text =~ s/^"(.*)"$/$1/;

        # Is this a pragma?
        if ( $tag_text =~ /^(\#.*?):(.*)/ ) {
           return wantarray ? ( $1, $2 ) : $1 if LstTidy::Reformat::isValidTag($linetype, $1);
        }

        # Return already if no text to parse (comment)
        return wantarray ? ( "", "" ) : ""
                if length $tag_text == 0 || $tag_text =~ /^\s*\#/;

        # Remove any spaces before and after the tag
        $tag_text =~ s/^\s+//;
        $tag_text =~ s/\s+$//;

        # Separate the tag name from its value
        my ( $tag, $value ) = split ':', $tag_text, 2;

        # All PCGen should at least have TAG_NAME:TAG_VALUE, anything else
        # is an anomaly. The only exception to this rule is LICENSE that
        # can be used without value to display empty line.
        if ( (!defined $value || $value eq q{})
                && $tag_text ne 'LICENSE:'
                ) {
                $log->warning(
                        qq(The tag "$tag_text" is missing a value (or you forgot a : somewhere)),
                        $file_for_error,
                        $line_for_error
                );

                # We set the value to prevent further errors
                $value = q{};
        }

        # If there is a ! in front of a PRExxx tag, we remove it
        my $negate_pre = $tag =~ s/^!(pre)/$1/i ? 1 : 0;

        # [ 1387361 ] No KIT STARTPACK entry for \"KIT:xxx\"
        # STARTPACK lines in Kit files weren't getting added to $valid_entities.
        # If they aren't added to valid_entities, since the verify flag is set,
        # each Kit will
        # cause a spurious error. I've added them to valid entities to prevent
        # that.
        if ($tag eq 'STARTPACK') {
           LstTidy::Validate::setEntityValid('KIT STARTPACK', "KIT:$value");
           LstTidy::Validate::setEntityValid('KIT STARTPACK', "$value");
        }

        # [ 1678570 ] Correct PRESPELLTYPE syntax
        # PRESPELLTYPE conversion
        if (LstTidy::Options::isConversionActive('ALL:PRESPELLTYPE Syntax') &&
                $tag eq 'PRESPELLTYPE' &&
                $tag_text =~ /^PRESPELLTYPE:([^\d]+),(\d+),(\d+)/)
        {
                my ($spelltype, $num_spells, $num_levels) = ($1, $2, $3);
                #$tag_text =~ /^PRESPELLTYPE:([^,\d]+),(\d+),(\d+)/;
                $value = "$num_spells,";
                # Common homebrew mistake is to include Arcade|Divine, since the
                # 5.8 documentation had an example that showed this. Might
                # as well handle it while I'm here.
                my @spelltypes = split(/\|/,$spelltype);
                foreach my $st (@spelltypes) {
                        $value .= "$st=$num_levels";
                }
                $log->notice(
                                qq{Invalid standalone PRESPELLTYPE tag "$tag_text" found and converted in $linetype.},
                                $file_for_error,
                                $line_for_error
                                );
        }
        # Continuing the fix - fix it anywhere. This is meant to address PRE tags
        # that are on the end of other tags or in PREMULTS.
        # I'll leave out the pipe-delimited error here, since it's more likely
        # to end up with confusion when the tag isn't standalone.
        elsif (LstTidy::Options::isConversionActive('ALL:PRESPELLTYPE Syntax')
                && $tag_text =~ /PRESPELLTYPE:([^\d]+),(\d+),(\d+)/)
        {
                $value =~ s/PRESPELLTYPE:([^\d,]+),(\d+),(\d+)/PRESPELLTYPE:$2,$1=$3/g;
                                $log->notice(
                                        qq{Invalid embedded PRESPELLTYPE tag "$tag_text" found and converted $linetype.},
                                        $file_for_error,
                                        $line_for_error
                                );
        }

        # Special cases like ADD:... and BONUS:...
        if ( $tag eq 'ADD' ) {
                my ( $type, $addtag, $therest, $add_count )
                = parse_ADD_tag( $tag_text );
                #       Return code     0 = no valid ADD tag found,
                #                       1 = old format token ADD tag found,
                #                       2 = old format adlib ADD tag found.
                #                       3 = 5.12 format ADD tag, using known token.
                #                       4 = 5.12 format ADD tag, not using token.

                if ($type) {
                # It's a ADD:token tag
                if ( $type == 1) {
                        $tag   = $addtag;
                        $value = "($therest)$add_count";
                }
                        if ((($type == 1) || ($type == 2)) && (LstTidy::Options::isConversionActive('ALL:ADD Syntax Fix')))
                        {
                                $tag = "ADD:";
                                $addtag =~ s/ADD://;
                                $value = "$addtag|$add_count|$therest";
                        }
                }
                else {
                        unless ( index( $tag_text, '#' ) == 0 ) {
                                $log->notice(
                                        qq{Invalid ADD tag "$tag_text" found in $linetype.},
                                        $file_for_error,
                                        $line_for_error
                                );
                                LstTidy::Report::incCountInvalidTags($linetype, $addtag); 
                                $no_more_error = 1;
                        }
                }
        }

        if ( $tag eq 'QUALIFY' ) {
                my ($qualify_type) = ($value =~ /^([^=:|]+)/ );
                if ($qualify_type && exists $token_QUALIFY_tag{$qualify_type} ) {
                        $tag .= ':' . $qualify_type;
                        $value =~ s/^$qualify_type(.*)/$1/;
                }
                elsif ($qualify_type) {
                        # No valid Qualify type found
                        LstTidy::Report::incCountInvalidTags($linetype, "$tag:$qualify_type"); 
                        $log->notice(
                                qq{Invalid QUALIFY:$qualify_type tag "$tag_text" found in $linetype.},
                                $file_for_error,
                                $line_for_error
                        );
                        $no_more_error = 1;
                }
                else {
                        LstTidy::Report::incCountInvalidTags($linetype, "QUALIFY"); 
                        $log->notice(
                                qq{Invalid QUALIFY tag "$tag_text" found in $linetype},
                                $file_for_error,
                                $line_for_error
                        );
                        $no_more_error = 1;
                }
        }

        if ( $tag eq 'BONUS' ) {
                my ($bonus_type) = ( $value =~ /^([^=:|]+)/ );

                if ( $bonus_type && exists $token_BONUS_tag{$bonus_type} ) {

                        # Is it valid for the curent file type?
                        $tag .= ':' . $bonus_type;
                        $value =~ s/^$bonus_type(.*)/$1/;
                }
                elsif ($bonus_type) {

                        # No valid bonus type was found
                        LstTidy::Report::incCountInvalidTags($linetype, "$tag:$bonus_type"); 
                        $log->notice(
                                qq{Invalid BONUS:$bonus_type tag "$tag_text" found in $linetype.},
                                $file_for_error,
                                $line_for_error
                        );
                        $no_more_error = 1;
                }
                else {
                        LstTidy::Report::incCountInvalidTags($linetype, "BONUS"); 
                        $log->notice(
                                qq{Invalid BONUS tag "$tag_text" found in $linetype},
                                $file_for_error,
                                $line_for_error
                        );
                        $no_more_error = 1;
                }
        }

        if ( $tag eq 'PROFICIENCY' ) {
                my ($prof_type) = ( $value =~ /^([^=:|]+)/ );

                if ( $prof_type && exists $token_PROFICIENCY_tag{$prof_type} ) {

                        # Is it valid for the curent file type?
                        $tag .= ':' . $prof_type;
                        $value =~ s/^$prof_type(.*)/$1/;
                }
                elsif ($prof_type) {

                        # No valid bonus type was found
                        LstTidy::Report::incCountInvalidTags($linetype, "$tag:$prof_type"); 
                        $log->notice(
                                qq{Invalid PROFICIENCY:$prof_type tag "$tag_text" found in $linetype.},
                                $file_for_error,
                                $line_for_error
                        );
                        $no_more_error = 1;
                }
                else {
                        LstTidy::Report::incCountInvalidTags($linetype, "PROFICIENCY"); 
                        $log->notice(
                                qq{Invalid PROFICIENCY tag "$tag_text" found in $linetype},
                                $file_for_error,
                                $line_for_error
                        );
                        $no_more_error = 1;
                }
        }


        # [ 832171 ] AUTO:* needs to be separate tags
        if ( $tag eq 'AUTO' ) {
                my $found_auto_type;
                AUTO_TYPE:
                for my $auto_type ( sort { length($b) <=> length($a) || $a cmp $b } @token_AUTO_tag ) {
                        if ( $value =~ s/^$auto_type// ) {
                                # We found what we were looking for
                                $found_auto_type = $auto_type;
                                last AUTO_TYPE;
                        }
                }

                if ($found_auto_type) {
                        $tag .= ':' . $found_auto_type;
                }
                else {

                        # No valid auto type was found
                        if ( $value =~ /^([^=:|]+)/ ) {
                           LstTidy::Report::incCountInvalidTags($linetype, "$tag:$1"); 
                                $log->notice(
                                        qq{Invalid $tag:$1 tag "$tag_text" found in $linetype.},
                                        $file_for_error,
                                        $line_for_error
                                );
                        }
                        else {
                                LstTidy::Report::incCountInvalidTags($linetype, "AUTO"); 
                                $log->notice(
                                        qq{Invalid AUTO tag "$tag_text" found in $linetype},
                                        $file_for_error,
                                        $line_for_error
                                );
                        }
                        $no_more_error = 1;

                }
        }

        # [ 813504 ] SPELLLEVEL:DOMAIN in domains.lst
        # SPELLLEVEL is now a multiple level tag like ADD and BONUS

        if ( $tag eq 'SPELLLEVEL' ) {
                if ( $value =~ s/^CLASS(?=\|)// ) {
                        # It's a SPELLLEVEL:CLASS tag
                        $tag = "SPELLLEVEL:CLASS";
                }
                elsif ( $value =~ s/^DOMAIN(?=\|)// ) {
                        # It's a SPELLLEVEL:DOMAIN tag
                        $tag = "SPELLLEVEL:DOMAIN";
                }
                else {
                        # No valid SPELLLEVEL subtag was found
                        if ( $value =~ /^([^=:|]+)/ ) {
                                LstTidy::Report::incCountInvalidTags($linetype, "$tag:$1"); 
                                $log->notice(
                                        qq{Invalid SPELLLEVEL:$1 tag "$tag_text" found in $linetype.},
                                        $file_for_error,
                                        $line_for_error
                                );
                        }
                        else {
                                LstTidy::Report::incCountInvalidTags($linetype, "SPELLLEVEL"); 
                                $log->notice(
                                        qq{Invalid SPELLLEVEL tag "$tag_text" found in $linetype},
                                        $file_for_error,
                                        $line_for_error
                                );
                        }
                        $no_more_error = 1;
                }
        }

        # [ 2544134 ] New Token - SPELLKNOWN

        if ( $tag eq 'SPELLKNOWN' ) {
                if ( $value =~ s/^CLASS(?=\|)// ) {
                        # It's a SPELLKNOWN:CLASS tag
                        $tag = "SPELLKNOWN:CLASS";
                }
                elsif ( $value =~ s/^DOMAIN(?=\|)// ) {
                        # It's a SPELLKNOWN:DOMAIN tag
                        $tag = "SPELLKNOWN:DOMAIN";
                }
                else {
                        # No valid SPELLKNOWN subtag was found
                        if ( $value =~ /^([^=:|]+)/ ) {
                                LstTidy::Report::incCountInvalidTags($linetype, "$tag:$1"); 
                                $log->notice(
                                        qq{Invalid SPELLKNOWN:$1 tag "$tag_text" found in $linetype.},
                                        $file_for_error,
                                        $line_for_error
                                );
                        }
                        else {
                                LstTidy::Report::incCountInvalidTags($linetype, "SPELLKNOWN"); 
                                $log->notice(
                                        qq{Invalid SPELLKNOWN tag "$tag_text" found in $linetype},
                                        $file_for_error,
                                        $line_for_error
                                );
                        }
                        $no_more_error = 1;
                }
        }

        # All the .CLEAR must be separated tags to help with the
        # tag ordering. That is, we need to make sure the .CLEAR
        # is ordered before the normal tag.
        # If the .CLEAR version of the tag doesn't exists, we do not
        # change the tag name but we give a warning.
        if ( defined $value && $value =~ /^.CLEAR/i ) {
                if ( LstTidy::Reformat::isValidTag($linetype, "$tag:.CLEARALL")) {
                        # Nothing to see here. Move on.
                } elsif ( ! LstTidy::Reformat::isValidTag($linetype, "$tag:.CLEAR")) {
                        $log->notice(
                                qq{The tag "$tag:.CLEAR" from "$tag_text" is not in the $linetype tag list\n},
                                $file_for_error,
                                $line_for_error
                        );
                        LstTidy::Report::incCountInvalidTags($linetype, "$tag:.CLEAR"); 
                        $no_more_error = 1;
                }
                else {
                        $value =~ s/^.CLEAR//i;
                        $tag .= ':.CLEAR';
                }
        }

        # Verify if the tag is valid for the line type
        my $real_tag = ( $negate_pre ? "!" : "" ) . $tag;



        if ( !$no_more_error && !  LstTidy::Reformat::isValidTag($linetype, $tag) && index( $tag_text, '#' ) != 0 ) {
                my $do_warn = 1;
                if ($tag_text =~ /^ADD:([^\(\|]+)[\|\(]+/) {
                        my $tag_text = ($1);
                        if (LstTidy::Reformat::isValidTag($linetype, "ADD:$tag_text")) {
                                $do_warn = 0;
                        }
                }
                if ($do_warn) {
                        $log->notice(
                                qq{The tag "$tag" from "$tag_text" is not in the $linetype tag list\n},
                                $file_for_error,
                                $line_for_error
                                );
                        LstTidy::Report::incCountInvalidTags($linetype, $real_tag); 
                }
        }


        elsif (LstTidy::Reformat::isValidTag($linetype, $tag)) {

           # Statistic gathering
           LstTidy::Report::incCountValidTags($linetype, $real_tag);
        }

        # Check and reformat the values for the tags with
        # only a limited number of values.

        if ( exists $tag_fix_value{$tag} ) {

                # All the limited value are uppercase except the alignment value 'Deity'
                my $newvalue = uc($value);
                my $is_valid = 1;

                # Special treament for the ALIGN tag
                if ( $tag eq 'ALIGN' || $tag eq 'PREALIGN' ) {
                # It is possible for the ALIGN and PREALIGN tags to have more then
                # one value

                # ALIGN use | for separator, PREALIGN use ,
                my $slip_patern = $tag eq 'PREALIGN' ? qr{[,]}xms : qr{[|]}xms;

                for my $align (split $slip_patern, $newvalue) {
                        if ( $align eq 'DEITY' ) { $align = 'Deity'; }
                        # Is it a number?
                        my $number;
                        if ( (($number) = ($align =~ / \A (\d+) \z /xms))
                                && $number >= 0
                                && $number < scalar @valid_system_alignments
                        ) {
                                $align = $valid_system_alignments[$number];
                                $newvalue =~ s{ (?<! \d ) ($number) (?! \d ) }{$align}xms;
                        }

                        # Is it a valid alignment?
                        if (!exists $tag_fix_value{$tag}{$align}) {
                                $log->notice(
                                        qq{Invalid value "$align" for tag "$real_tag"},
                                        $file_for_error,
                                        $line_for_error
                                );
                                $is_valid = 0;
                        }
                }
                }
                else {
                # Standerdize the YES NO and other such tags
                if ( exists $tag_proper_value_for{$newvalue} ) {
                        $newvalue = $tag_proper_value_for{$newvalue};
                }

                # Is this a proper value for the tag?
                if ( !exists $tag_fix_value{$tag}{$newvalue} ) {
                        $log->notice(
                                qq{Invalid value "$value" for tag "$real_tag"},
                                $file_for_error,
                                $line_for_error
                        );
                        $is_valid = 0;
                }
                }



                # Was the tag changed ?
                if ( $is_valid && $value ne $newvalue && !( $tag eq 'ALIGN' || $tag eq 'PREALIGN' )) {
                $log->warning(
                        qq{Replaced "$real_tag:$value" by "$real_tag:$newvalue"},
                        $file_for_error,
                        $line_for_error
                );
                $value = $newvalue;
                }
        }

        ############################################################
        ######################## Conversion ########################
        # We manipulate the tag here
        additionnal_tag_parsing( $real_tag, $value, $linetype, $file_for_error, $line_for_error );

        ############################################################
        # We call the validating function if needed
        if getOption('xcheck') {
           validate_tag($real_tag, $value, $linetype, $file_for_error, $line_for_error);
        }

        # If there is already a :  in the tag name, no need to add one more
        my $need_sep = index( $real_tag, ':' ) == -1 ? q{:} : q{};

        if $value eq q{} {
           $log->debug(qq{parse_tag: $tag_text}, $file_for_error, $line_for_error);
        }

        # We change the tag_text value from the caller
        # This is very ugly but it gets th job done
        $_[0] = $real_tag;
        $_[0] .= $need_sep . $value if defined $value;

        # Return the tag
        wantarray ? ( $real_tag, $value ) : $real_tag;

}

BEGIN {

   # EQUIPMENT types that are valid in NATURALATTACKS tags
   my %valid_NATURALATTACKS_type = map { $_ => 1 } (

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

   my %valid_WIELDCATEGORY = map { $_ => 1 } (

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

###############################################################
# validate_tag
# ------------
#
# This function stores data for later validation. It also checks
# the syntax of certain tags and detects common errors and
# deprecations.
#
# The %referrer hash must be populated following this format
# $referrer{$lintype}{$name} = [ $err_desc, $file_for_error, $line_for_error ]
#
# Paramter: $tag_name           Name of the tag (before the :)
#           $tag_value              Value of the tag (after the :)
#           $linetype               Type for the current file
#           $file_for_error   Name of the current file
#           $line_for_error   Number of the current line

   sub validate_tag {
      my ( $tag_name, $tag_value, $linetype, $file_for_error, $line_for_error ) = @_;
      study $tag_value;

      if ($tag_name eq 'STARTPACK')
      {
         LstTidy::Validate::setEntityValid('KIT STARTPACK', "KIT:$tag_value");
         LstTidy::Validate::setEntityValid('KIT', "KIT:$tag_value"          );

      } elsif ( $tag_name =~ /^\!?PRE/ ) {

         # It's a PRExxx tag, we delegate
         return LstTidy::Validate::validatePreTag( $tag_name,
            $tag_value,
            "",
            $linetype,
            $file_for_error,
            $line_for_error
         );

      } elsif (index( $tag_name, 'PROFICIENCY' ) == 0 ) {

      } elsif ( index( $tag_name, 'BONUS' ) == 0 ) {

         # Are there any PRE tags in the BONUS tag.
         if ( $tag_value =~ /(!?PRE[A-Z]*):([^|]*)/ ) {

            # A PRExxx tag is present
            LstTidy::Validate::validatePreTag(
               $1,
               $2,
               "$tag_name$tag_value",
               $linetype,
               $file_for_error,
               $line_for_error
            );
         }

         if ( $tag_name eq 'BONUS:CHECKS' ) {
                        # BONUS:CHECKS|<check list>|<jep> {|TYPE=<bonus type>} {|<pre tags>}
                        # BONUS:CHECKS|ALL|<jep>                {|TYPE=<bonus type>} {|<pre tags>}
                        # <check list> :=   ( <check name 1> { | <check name 2> } { | <check name 3>} )
                        #                       | ( BASE.<check name 1> { | BASE.<check name 2> } { | BASE.<check name 3>} )

                        # We get parameter 1 and 2 (0 is empty since $tag_value begins with a |)
                        my ($check_names,$jep) = ( split /[|]/, $tag_value ) [1,2];

                        # The checkname part
                        if ( $check_names ne 'ALL' ) {
                                # We skip ALL as it is a special value that must be used alone

                                # $check_name => YES or NO to indicates if BASE. is used
                                my ($found_base, $found_non_base) = ( NO, NO );

                                for my $check_name ( split q{,}, $check_names ) {
                                   # We keep the original name for error messages
                                   my $clean_check_name = $check_name;

                                   # Did we use BASE.? is yes, we remove it
                                   if ( $clean_check_name =~ s/ \A BASE [.] //xms ) {
                                      $found_base = YES;
                                   } else {
                                      $found_non_base = YES;
                                   }

                                   # Is the check name valid
                                   if ( ! LstTidy::Parse::isValidCheck($clean_check_name) ) {
                                      $log->notice(
                                         qq{Invalid save check name "$clean_check_name" found in "$tag_name$tag_value"},
                                         $file_for_error,
                                         $line_for_error
                                      );
                                   }
                                }

                                # Verify if there is a mix of BASE and non BASE
                                if ( $found_base && $found_non_base ) {
                                $log->info(
                                        qq{Are you sure you want to mix BASE and non-BASE in "$tag_name$tag_value"},
                                        $file_for_error,
                                        $line_for_error
                                );
                                }
                        }

                        # The formula part
                        push @LstTidy::Report::xcheck_to_process,
                                [
                                'DEFINE Variable',
                                qq{@@" in "$tag_name$tag_value},
                                $file_for_error,
                                $line_for_error,
                                LstTidy::Parse::parseJep(
                                        $jep,
                                        "$tag_name$tag_value",
                                        $file_for_error,
                                        $line_for_error
                                )
                                ];

                }
                elsif ( $tag_name eq 'BONUS:FEAT' ) {

                        # BONUS:FEAT|POOL|<formula>|<prereq list>|<bonus type>

                        # @list_of_param will contains all the non-empty parameters
                        # included in $tag_value. The first one should always be
                        # POOL.
                        my @list_of_param = grep {/./} split '\|', $tag_value;

                        if ( ( shift @list_of_param ) ne 'POOL' ) {

                                # For now, only POOL is valid here
                                $log->notice(
                                qq{Only POOL is valid as second paramater for BONUS:FEAT "$tag_name$tag_value"},
                                $file_for_error,
                                $line_for_error
                                );
                        }

                        # The next parameter is the formula
                        push @LstTidy::Report::xcheck_to_process,
                                [
                                'DEFINE Variable',
                                qq(@@" in "$tag_name$tag_value),
                                $file_for_error,
                                $line_for_error,
                                LstTidy::Parse::parseJep(
                                        ( shift @list_of_param ),
                                        "$tag_name$tag_value",
                                        $file_for_error,
                                        $line_for_error
                                )
                                ];

                        # For the rest, we need to check if it is a PRExxx tag or a TYPE=
                        my $type_present = 0;
                        for my $param (@list_of_param) {
                                if ( $param =~ /^(!?PRE[A-Z]+):(.*)/ ) {

                                # It's a PRExxx tag, we delegate the validation
                                LstTidy::Validate::validatePreTag($1,
                                                        $2,
                                                        "$tag_name$tag_value",
                                                        $linetype,
                                                        $file_for_error,
                                                        $line_for_error
                                );
                                }
                                elsif ( $param =~ /^TYPE=(.*)/ ) {
                                $type_present++;
                                }
                                else {
                                $log->notice(
                                        qq{Invalid parameter "$param" found in "$tag_name$tag_value"},
                                        $file_for_error,
                                        $line_for_error
                                );
                                }
                        }

                        if ( $type_present > 1 ) {
                                $log->notice(
                                qq{There should be only one "TYPE=" in "$tag_name$tag_value"},
                                $file_for_error,
                                $line_for_error
                                );
                        }
                }
                if (   $tag_name eq 'BONUS:MOVEADD'
                        || $tag_name eq 'BONUS:MOVEMULT'
                        || $tag_name eq 'BONUS:POSTMOVEADD' )
                {

                        # BONUS:MOVEMULT|<list of move types>|<number to add or mult>
                        # <list of move types> is a comma separated list of a weird TYPE=<move>.
                        # The <move> are found in the MOVE tags.
                        # <number to add or mult> can be a formula

                        my ( $type_list, $formula ) = ( split '\|', $tag_value )[ 1, 2 ];

                        # We keep the move types for validation
                        for my $type ( split ',', $type_list ) {
                                if ( $type =~ /^TYPE(=|\.)(.*)/ ) {
                                push @LstTidy::Report::xcheck_to_process,
                                        [
                                        'MOVE Type',    qq(TYPE$1@@" in "$tag_name$tag_value),
                                        $file_for_error, $line_for_error,
                                        $2
                                        ];
                                }
                                else {
                                $log->notice(
                                        qq(Missing "TYPE=" for "$type" in "$tag_name$tag_value"),
                                        $file_for_error,
                                        $line_for_error
                                );
                                }
                        }

                        # Then we deal with the var in formula
                        push @LstTidy::Report::xcheck_to_process,
                                [
                                'DEFINE Variable',
                                qq(@@" in "$tag_name$tag_value),
                                $file_for_error,
                                $line_for_error,
                                LstTidy::Parse::parseJep(
                                        $formula,
                                        "$tag_name$tag_value",
                                        $file_for_error,
                                        $line_for_error
                                )
                                ];
                }
                elsif ( $tag_name eq 'BONUS:SLOTS' ) {

                        # BONUS:SLOTS|<slot types>|<number of slots>
                        # <slot types> is a comma separated list.
                        # The valid types are defined in %token_BONUS_SLOTS_types
                        # <number of slots> could be a formula.

                        my ( $type_list, $formula ) = ( split '\|', $tag_value )[ 1, 2 ];

                        # We first check the slot types
                        for my $type ( split ',', $type_list ) {
                                unless ( exists $token_BONUS_SLOTS_types{$type} ) {
                                $log->notice(
                                        qq{Invalid slot type "$type" in "$tag_name$tag_value"},
                                        $file_for_error,
                                        $line_for_error
                                );
                                }
                        }

                        # Then we deal with the var in formula
                        push @LstTidy::Report::xcheck_to_process,
                                [
                                'DEFINE Variable',
                                qq(@@" in "$tag_name$tag_value),
                                $file_for_error,
                                $line_for_error,
                                LstTidy::Parse::parseJep(
                                        $formula,
                                        "$tag_name$tag_value",
                                        $file_for_error,
                                        $line_for_error
                                )
                                ];
                }
                elsif ( $tag_name eq 'BONUS:VAR' ) {

                        # BONUS:VAR|List of Names|Formula|... only the first two values are variable related.
                        my ( $var_name_list, @formulas )
                                = ( split '\|', $tag_value )[ 1, 2 ];

                        # First we store the DEFINE variable name
                        for my $var_name ( split ',', $var_name_list ) {
                                if ( $var_name =~ /^[a-z][a-z0-9_\s]*$/i ) {
                                # LIST is filtered out as it may not be valid for the
                                # other places were a variable name is used.
                                if ( $var_name ne 'LIST' ) {
                                        push @LstTidy::Report::xcheck_to_process,
                                                [
                                                'DEFINE Variable',
                                                qq(@@" in "$tag_name$tag_value),
                                                $file_for_error,
                                                $line_for_error,
                                                $var_name,
                                                ];
                                }
                                }
                                else {
                                $log->notice(
                                        qq{Invalid variable name "$var_name" in "$tag_name$tag_value"},
                                        $file_for_error,
                                        $line_for_error
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
                                        qq(@@" in "$tag_name$tag_value),
                                        $file_for_error,
                                        $line_for_error,
                                        LstTidy::Parse::parseJep(
                                                $formula,
                                                "$tag_name$tag_value",
                                                $file_for_error,
                                                $line_for_error
                                        )
                                        ];
                        }
                }
                elsif ( $tag_name eq 'BONUS:WIELDCATEGORY' ) {

                        # BONUS:WIELDCATEGORY|<List of category>|<formula>
                        my ( $category_list, $formula ) = ( split '\|', $tag_value )[ 1, 2 ];

                        # Validate the category to see if valid
                        for my $category ( split ',', $category_list ) {
                                if ( !exists $valid_WIELDCATEGORY{$category} ) {
                                $log->notice(
                                        qq{Invalid category "$category" in "$tag_name$tag_value"},
                                        $file_for_error,
                                        $line_for_error
                                );
                                }
                        }

                        # Second, we deal with the formula
                        push @LstTidy::Report::xcheck_to_process,
                                [
                                'DEFINE Variable',
                                qq(@@" in "$tag_name$tag_value),
                                $file_for_error,
                                $line_for_error,
                                LstTidy::Parse::parseJep(
                                        $formula,
                                        "$tag_name$tag_value",
                                        $file_for_error,
                                        $line_for_error
                                )
                                ];

                }
                }
                elsif ( $tag_name eq 'CLASSES' || $tag_name eq 'DOMAINS' ) {
                if ( $linetype eq 'SPELL' ) {
                        my %seen;
                        my $tag_to_check = $tag_name eq 'CLASSES' ? 'CLASS' : 'DOMAIN';

                        # First we find all the classes used
                        for my $level ( split '\|', $tag_value ) {
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
                                                $tag_to_check,   $tag_name,
                                                $file_for_error, $line_for_error,
                                                $entity
                                                ];

                                                if ( $seen{$entity}++ ) {
                                                $log->notice(
                                                        qq{"$entity" found more then once in $tag_name},
                                                        $file_for_error,
                                                        $line_for_error
                                                );
                                                }
                                        }
                                }
                                }
                                else {
                                        if ( "$tag_name:$level" eq 'CLASSES:.CLEARALL' ) {
                                                # Nothing to see here. Move on.
                                        }
                                        else {
                                                $log->warning(
                                                        qq{Missing "=level" after "$tag_name:$level"},
                                                        $file_for_error,
                                                        $line_for_error
                                                );
                                        }
                                }
                        }
                }
                elsif ( $linetype eq 'SKILL' ) {

                        # Only CLASSES in SKILL
                        CLASS_FOR_SKILL:
                        for my $class ( split '\|', $tag_value ) {

                                # ALL is valid here
                                next CLASS_FOR_SKILL if $class eq 'ALL';

                                push @LstTidy::Report::xcheck_to_process,
                                [
                                'CLASS',                $tag_name,
                                $file_for_error, $line_for_error,
                                $class
                                ];
                        }
                }
                elsif (   $linetype eq 'DEITY' ) {
                        # Only DOMAINS in DEITY
                        if ($tag_value =~ /\|/ ) {
                        $tag_value = substr($tag_value, 0, rindex($tag_value, "\|"));
                        }
                        DOMAIN_FOR_DEITY:
                        for my $domain ( split ',', $tag_value ) {

                                # ALL is valid here
                                next DOMAIN_FOR_DEITY if $domain eq 'ALL';

                                push @LstTidy::Report::xcheck_to_process,
                                [
                                'DOMAIN',               $tag_name,
                                $file_for_error, $line_for_error,
                                $domain
                                ];
                        }
                }
                }
                elsif ( $tag_name eq 'CLASS'
                        && $linetype ne 'PCC'
                ) {
                # Note: The CLASS linetype doesn't have any CLASS tag, it's
                #               called 000ClassName internaly. CLASS is a tag used
                #               in other line types like KIT CLASS.
                # CLASS:<class name>,<class name>,...[BASEAGEADD:<dice expression>]

                # We remove and ignore [BASEAGEADD:xxx] if present
                my $list_of_class = $tag_value;
                $list_of_class =~ s{ \[ BASEAGEADD: [^]]* \] }{}xmsg;

                push @LstTidy::Report::xcheck_to_process,
                        [
                                'CLASS',
                                $tag_name,
                                $file_for_error,
                                $line_for_error,
                                (split /[|,]/, $list_of_class),
                        ];
                }
                elsif ( $tag_name eq 'DEITY'
                        && $linetype ne 'PCC'
                ) {
                # DEITY:<deity name>|<deity name>|etc.
                push @LstTidy::Report::xcheck_to_process,
                        [
                                'DEITY',
                                $tag_name,
                                $file_for_error,
                                $line_for_error,
                                (split /[|]/, $tag_value),
                        ];
                }
                elsif ( $tag_name eq 'DOMAIN'
                        && $linetype ne 'PCC'
                ) {
                # DOMAIN:<domain name>|<domain name>|etc.
                push @LstTidy::Report::xcheck_to_process,
                        [
                                'DOMAIN',
                                $tag_name,
                                $file_for_error,
                                $line_for_error,
                                (split /[|]/, $tag_value),
                        ];
                }
                elsif ( $tag_name eq 'ADDDOMAINS' ) {

                # ADDDOMAINS:<domain1>.<domain2>.<domain3>. etc.
                push @LstTidy::Report::xcheck_to_process,
                        [
                        'DOMAIN',               $tag_name,
                        $file_for_error, $line_for_error,
                        split '\.',     $tag_value
                        ];
                }
                elsif ( $tag_name eq 'ADD:SPELLCASTER' ) {

                # ADD:SPELLCASTER(<list of classes>)<formula>
                if ( $tag_value =~ /\((.*)\)(.*)/ ) {
                        my ( $list, $formula ) = ( $1, $2 );

                        # First the list of classes
                        # ANY, ARCANA, DIVINE and PSIONIC are spcial hardcoded cases for
                        # the ADD:SPELLCASTER tag.
                        push @LstTidy::Report::xcheck_to_process, [
                                'CLASS',
                                qq(@@" in "$tag_name$tag_value),
                                $file_for_error,
                                $line_for_error,
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
                                qq(@@" from "$formula" in "$tag_name$tag_value),
                                $file_for_error,
                                $line_for_error,
                                LstTidy::Parse::parseJep(
                                        $formula,
                                        "$tag_name$tag_value",
                                        $file_for_error,
                                        $line_for_error
                                )
                                ];
                }
                else {
                        $log->notice(
                                qq{Invalid syntax: "$tag_name$tag_value"},
                                $file_for_error,
                                $line_for_error
                        );
                }
                }
                elsif ( $tag_name eq 'ADD:EQUIP' ) {

                # ADD:EQUIP(<list of equipments>)<formula>
                if ( $tag_value =~ m{ [(]   # Opening brace
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
                                qq(@@" in "$tag_name$tag_value),
                                $file_for_error,
                                $line_for_error,
                                grep { uc($_) ne 'ANY' }
                                        split ',', $list
                                ];

                        # Second, we deal with the formula
                        push @LstTidy::Report::xcheck_to_process,
                                [
                                'DEFINE Variable',
                                qq(@@" from "$formula" in "$tag_name$tag_value),
                                $file_for_error,
                                $line_for_error,
                                LstTidy::Parse::parseJep(
                                        $formula,
                                        "$tag_name$tag_value",
                                        $file_for_error,
                                        $line_for_error
                                )
                                ];
                }
                else {
                        $log->notice(
                                qq{Invalid syntax: "$tag_name$tag_value"},
                                $file_for_error,
                                $line_for_error
                        );
                }
                }
                elsif ($tag_name eq 'EQMOD'
                || $tag_name eq 'IGNORES'
                || $tag_name eq 'REPLACES'
                || ( $tag_name =~ /!?PRETYPE/ && $tag_value =~ /(\d+,)?EQMOD=/ )
                ) {

                # This section check for any reference to an EQUIPMOD key
                if ( $tag_name eq 'EQMOD' ) {

                        # The higher level for the EQMOD is the . (who's the genius who
                        # dreamed that up...
                        my @key_list = split '\.', $tag_value;

                        # The key name is everything found before the first |
                        for $_ (@key_list) {
                                my ($key) = (/^([^|]*)/);
                                if ($key) {

                                # To be processed later
                                push @LstTidy::Report::xcheck_to_process,
                                        [
                                        'EQUIPMOD Key',  qq(@@" in "$tag_name:$tag_value),
                                        $file_for_error, $line_for_error,
                                        $key
                                        ];
                                }
                                else {
                                $log->warning(
                                        qq(Cannot find the key for "$_" in "$tag_name:$tag_value"),
                                        $file_for_error,
                                        $line_for_error
                                );
                                }
                        }
                }
                elsif ( $tag_name eq "IGNORES" || $tag_name eq "REPLACES" ) {

                        # Comma separated list of KEYs
                        # To be processed later
                        push @LstTidy::Report::xcheck_to_process,
                                [
                                'EQUIPMOD Key',  qq(@@" in "$tag_name:$tag_value),
                                $file_for_error, $line_for_error,
                                split ',',              $tag_value
                                ];
                }
                }
                elsif (
                $linetype ne 'PCC'
                && (   $tag_name eq 'ADD:FEAT'
                        || $tag_name eq 'AUTO:FEAT'
                        || $tag_name eq 'FEAT'
                        || $tag_name eq 'FEATAUTO'
                        || $tag_name eq 'VFEAT'
                        || $tag_name eq 'MFEAT' )
                )
                {
                my @feats;
                my $parent = NO;

                # ADD:FEAT(feat,feat,TYPE=type)formula
                # FEAT:feat|feat|feat(xxx)
                # FEAT:feat,feat,feat(xxx)  in the TEMPLATE and DOMAIN
                # FEATAUTO:feat|feat|...
                # VFEAT:feat|feat|feat(xxx)|PRExxx:yyy
                # MFEAT:feat|feat|feat(xxx)|...
                # All these type may have embeded [PRExxx tags]
                if ( $tag_name eq 'ADD:FEAT' ) {
                        if ( $tag_value =~ /^\((.*)\)(.*)?$/ ) {
                                $parent = YES;
                                my $formula = $2;

                                # The ADD:FEAT list may contains list elements that
                                # have () and will need the special split.
                                # The LIST special feat name is valid in ADD:FEAT
                                # So is ALL now.
                                @feats = grep { $_ ne 'LIST' } grep { $_ ne 'ALL' } embedded_coma_split($1);

                                #               # We put the , back in place
                                #               s/&comma;/,/g for @feats;

                                # Here we deal with the formula part
                                push @LstTidy::Report::xcheck_to_process,
                                        [
                                        'DEFINE Variable',
                                        qq(@@" in "$tag_name$tag_value),
                                        $file_for_error,
                                        $line_for_error,
                                        LstTidy::Parse::parseJep(
                                                $formula,
                                                "$tag_name$tag_value",
                                                $file_for_error,
                                                $line_for_error
                                        )
                                        ] if $formula;
                        }
                        else {
                                $log->notice(
                                qq{Invalid systax: "$tag_name$tag_value"},
                                $file_for_error,
                                $line_for_error
                                ) if $tag_value;
                        }
                }
                elsif ( $tag_name eq 'FEAT' ) {

                        # FEAT tags sometime use , and sometime use | as separator.

                        # We can now safely split on the ,
                        @feats = embedded_coma_split( $tag_value, qr{,|\|} );

                        #       # We put the , back in place
                        #       s/&coma;/,/g for @feats;
                }
                else {
                        @feats = split '\|', $tag_value;
                }

                FEAT:
                for my $feat (@feats) {

                        # If it is a PRExxx tag section, we validate teh PRExxx tag.
                        if ( $tag_name eq 'VFEAT' && $feat =~ /^(!?PRE[A-Z]+):(.*)/ ) {
                                LstTidy::Validate::validatePreTag($1,
                                                        $2,
                                                        "$tag_name:$tag_value",
                                                        $linetype,
                                                        $file_for_error,
                                                        $line_for_error
                                );
                                $feat = "";
                                next FEAT;
                        }

                        # We strip the embeded [PRExxx ...] tags
                        if ( $feat =~ /([^[]+)\[(!?PRE[A-Z]*):(.*)\]$/ ) {
                                $feat = $1;
                                LstTidy::Validate::validatePreTag($2,
                                                        $3,
                                                        "$tag_name:$tag_value",
                                                        $linetype,
                                                        $file_for_error,
                                                        $line_for_error
                                );
                        }

                }

                my $message_format = $tag_name;
                if ($parent) {
                        $message_format = "$tag_name(@@)";
                }

                # To be processed later
                push @LstTidy::Report::xcheck_to_process,
                        [ 'FEAT', $message_format, $file_for_error, $line_for_error, @feats ];
                }
                elsif ( $tag_name eq 'KIT' && $linetype ne 'PCC' ) {
                # KIT:<number of choice>|<kit name>|<kit name>|etc.
                # KIT:<kit name>
                my @kit_list = split /[|]/, $tag_value;

                # The first item might be a number
                if ( $kit_list[0] =~ / \A \d+ \z /xms ) {
                        # We discard the number
                        shift @kit_list;
                }

                push @LstTidy::Report::xcheck_to_process,
                        [
                                'KIT STARTPACK',
                                $tag_name,
                                $file_for_error,
                                $line_for_error,
                                @kit_list,
                        ];
                }
                elsif ( $tag_name eq 'LANGAUTOxxx' || $tag_name eq 'LANGBONUS' ) {

                # To be processed later
                # The ALL keyword is removed here since it is not usable everywhere there are language
                # used.
                push @LstTidy::Report::xcheck_to_process,
                        [
                        'LANGUAGE', $tag_name, $file_for_error, $line_for_error,
                        grep { $_ ne 'ALL' } split ',', $tag_value
                        ];
                }
                elsif ( $tag_name eq 'ADD:LANGUAGE' ) {

                        # Syntax: ADD:LANGUAGE(<coma separated list of languages)<number>
                        if ( $tag_value =~ /\((.*)\)/ ) {
                                push @LstTidy::Report::xcheck_to_process,
                                        [
                                        'LANGUAGE', 'ADD:LANGUAGE(@@)', $file_for_error, $line_for_error,
                                        split ',',  $1
                                        ];
                        }
                        else {
                                $log->notice(
                                        qq{Invalid syntax for "$tag_name$tag_value"},
                                        $file_for_error,
                                        $line_for_error
                                );
                        }
                }
                elsif ( $tag_name eq 'MOVE' ) {

                        # MOVE:<move type>,<value>
                        # ex. MOVE:Walk,30,Fly,20,Climb,10,Swim,10

                        my @list = split ',', $tag_value;

                        MOVE_PAIR:
                        while (@list) {
                                my ( $type, $value ) = ( splice @list, 0, 2 );
                                $value = "" if !defined $value;

                                # $type should be a word and $value should be a number
                                if ( $type =~ /^\d+$/ ) {
                                        $log->notice(
                                        qq{I was expecting a move type where I found "$type" in "$tag_name:$tag_value"},
                                        $file_for_error,
                                        $line_for_error
                                        );
                                        last;
                                }
                                else {

                                        # We keep the move type for future validation
                                        LstTidy::Validate::setEntityValid('MOVE Type', $type);
                                }

                                unless ( $value =~ /^\d+$/ ) {
                                        $log->notice(
                                        qq{I was expecting a number after "$type" and found "$value" in "$tag_name:$tag_value"},
                                        $file_for_error,
                                        $line_for_error
                                        );
                                        last MOVE_PAIR;
                                }
                        }
                } 
                elsif ( $tag_name eq 'MOVECLONE' ) {
                # MOVECLONE:A,B,formula  A and B must be valid move types.
                        if ( $tag_value =~ /^(.*),(.*),(.*)/ ) {
                                # Error if more parameters (Which will show in the first group)
                                if ( $1 =~ /,/ ) {
                                        $log->warning(
                                        qq{Found too many parameters in "$tag_name:$tag_value"},
                                        $file_for_error,
                                        $line_for_error
                                        );
                                } 
                                else {
                                        # Cross check for used MOVE Types.
                                        push @LstTidy::Report::xcheck_to_process,
                                                [
                                                'MOVE Type', $tag_name, 
                                                $file_for_error, $line_for_error,
                                                $1, $2
                                                ];
                                }
                        }
                        else {
                                # Report missing requisite parameters.
                                $log->warning(
                                qq{Missing a parameter in in "$tag_name:$tag_value"},
                                $file_for_error,
                                $line_for_error
                                );
                        }


                }
                elsif ( $tag_name eq 'RACE' && $linetype ne 'PCC' ) {
                # There is only one race per RACE tag
                push @LstTidy::Report::xcheck_to_process,
                        [  'RACE',
                                $tag_name,
                                $file_for_error,
                                $line_for_error,
                                $tag_value,
                        ];
                }
                elsif ( $tag_name eq 'SWITCHRACE' ) {

                # To be processed later
                # Note: SWITCHRACE actually switch the race TYPE
                push @LstTidy::Report::xcheck_to_process,
                        [   'RACE TYPE',
                                $tag_name,
                                $file_for_error,
                                $line_for_error,
                                (split '\|',  $tag_value),
                        ];
                }
                elsif ( $tag_name eq 'CSKILL'
                        || $tag_name eq 'CCSKILL'
                        || $tag_name eq 'MONCSKILL'
                        || $tag_name eq 'MONCCSKILL'
                        || ($tag_name eq 'SKILL' && $linetype ne 'PCC')
                ) {
                my @skills = split /[|]/, $tag_value;

                # ALL is a valid use in BONUS:SKILL, xCSKILL  - [ 1593872 ] False warning: No SKILL entry for CSKILL:ALL
                @skills = grep { $_ ne 'ALL' } @skills;

                # We need to filter out %CHOICE for the SKILL tag
                if ( $tag_name eq 'SKILL' ) {
                        @skills = grep { $_ ne '%CHOICE' } @skills;
                }

                # To be processed later
                push @LstTidy::Report::xcheck_to_process,
                        [   'SKILL',
                                $tag_name,
                                $file_for_error,
                                $line_for_error,
                                @skills,
                        ];
                }
                elsif ( $tag_name eq 'ADD:SKILL' ) {

                # ADD:SKILL(<list of skills>)<formula>
                if ( $tag_value =~ /\((.*)\)(.*)/ ) {
                        my ( $list, $formula ) = ( $1, $2 );

                        # First the list of skills
                        # ANY is a spcial hardcoded cases for ADD:EQUIP
                        push @LstTidy::Report::xcheck_to_process,
                                [
                                'SKILL',
                                qq(@@" in "$tag_name$tag_value),
                                $file_for_error,
                                $line_for_error,
                                grep { uc($_) ne 'ANY' } split ',', $list
                                ];

                        # Second, we deal with the formula
                        push @LstTidy::Report::xcheck_to_process,
                                [
                                'DEFINE Variable',
                                qq(@@" from "$formula" in "$tag_name$tag_value),
                                $file_for_error,
                                $line_for_error,
                                LstTidy::Parse::parseJep(
                                        $formula,
                                        "$tag_name$tag_value",
                                        $file_for_error,
                                        $line_for_error
                                ),
                                ];
                }
                else {
                        $log->notice(
                                qq{Invalid syntax: "$tag_name$tag_value"},
                                $file_for_error,
                                $line_for_error
                        );
                }
                }
                elsif ( $tag_name eq 'SPELLS' ) {
                if ( $linetype ne 'KIT SPELLS' ) {
 # Syntax: SPELLS:<spellbook>|[TIMES=<times per day>|][TIMEUNIT=<unit of time>|][CASTERLEVEL=<CL>|]<Spell list>[|<prexxx tags>]
 # <Spell list> = <Spell name>,<DC> [|<Spell list>]
                        my @list_of_param = split '\|', $tag_value;
                        my @spells;

                        # We drop the Spell book name
                        shift @list_of_param;

                        my $nb_times            = 0;
                        my $nb_timeunit         = 0;
                        my $nb_casterlevel      = 0;
                        my $AtWill_Flag         = NO;
                        for my $param (@list_of_param) {
                                if ( $param =~ /^(TIMES)=(.*)/ || $param =~ /^(TIMEUNIT)=(.*)/ || $param =~ /^(CASTERLEVEL)=(.*)/ ) {
                                        if ( $1 eq 'TIMES' ) {
#                                               $param =~ s/TIMES=-1/TIMES=ATWILL/g;   # SPELLS:xxx|TIMES=-1 to SPELLS:xxx|TIMES=ATWILL conversion
                                                $AtWill_Flag = $param =~ /TIMES=ATWILL/;
                                                $nb_times++;
                                                push @LstTidy::Report::xcheck_to_process,
                                                        [
                                                                'DEFINE Variable',
                                                                qq(@@" in "$tag_name:$tag_value),
                                                                $file_for_error,
                                                                $line_for_error,
                                                                LstTidy::Parse::parseJep(
                                                                        $2,
                                                                        "$tag_name:$tag_value",
                                                                        $file_for_error,
                                                                        $line_for_error
                                                                )
                                                        ];
                                        }
                                        elsif ( $1 eq 'TIMEUNIT' ) {
                                                $nb_timeunit++;
                                                # Is it a valid alignment?
                                                if (!exists $tag_fix_value{$1}{$2}) {
                                                        $log->notice(
                                                                qq{Invalid value "$2" for tag "$1"},
                                                                $file_for_error,
                                                                $line_for_error
                                                        );
#                                                       $is_valid = 0;
                                                }
                                        }
                                        else {
                                                $nb_casterlevel++;
                                                                                                push @LstTidy::Report::xcheck_to_process,
                                                        [
                                                                'DEFINE Variable',
                                                                qq(@@" in "$tag_name:$tag_value),
                                                                $file_for_error,
                                                                $line_for_error,
                                                                LstTidy::Parse::parseJep(
                                                                        $2,
                                                                        "$tag_name:$tag_value",
                                                                        $file_for_error,
                                                                        $line_for_error
                                                                )
                                                        ];
                                        }
                                }
                                elsif ( $param =~ /^(PRE[A-Z]+):(.*)/ ) {

                                # Embeded PRExxx tags
                                LstTidy::Validate::validatePreTag($1,
                                                        $2,
                                                        "$tag_name:$tag_value",
                                                        $linetype,
                                                        $file_for_error,
                                                        $line_for_error
                                );
                                }
                                else {
                                my ( $spellname, $dc ) = ( $param =~ /([^,]+),(.*)/ );

                                if ($dc) {

                                        # Spell name must be validated with the list of spells and DC is a formula
                                        push @spells, $spellname;

                                        push @LstTidy::Report::xcheck_to_process,
                                                [
                                                'DEFINE Variable',
                                                qq(@@" in "$tag_name:$tag_value),
                                                $file_for_error,
                                                $line_for_error,
                                                LstTidy::Parse::parseJep(
                                                        $dc,
                                                        "$tag_name:$tag_value",
                                                        $file_for_error,
                                                        $line_for_error
                                                )
                                                ];
                                }
                                else {

                                        # No DC present, the whole param is the spell name
                                        push @spells, $param;

                                        $log->info(
                                                qq(the DC value is missing for "$param" in "$tag_name:$tag_value"),
                                                $file_for_error,
                                                $line_for_error
                                        );
                                }
                                }
                        }

                        push @LstTidy::Report::xcheck_to_process,
                                [
                                'SPELL',                $tag_name,
                                $file_for_error, $line_for_error,
                                @spells
                                ];

                        # Validate the number of TIMES, TIMEUNIT, and CASTERLEVEL parameters
                        if ( $nb_times != 1 ) {
                                if ($nb_times) {
                                        $log->notice(
                                                qq{TIMES= should not be used more then once in "$tag_name:$tag_value"},
                                                $file_for_error,
                                                $line_for_error
                                        );
                                }
                                else {
                                        $log->info(
                                                qq(the TIMES= parameter is missing in "$tag_name:$tag_value"),
                                                $file_for_error,
                                                $line_for_error
                                        );
                                }
                        }

                        if ( $nb_timeunit != 1 ) {
                                if ($nb_timeunit) {
                                        $log->notice(
                                                qq{TIMEUNIT= should not be used more then once in "$tag_name:$tag_value"},
                                                $file_for_error,
                                                $line_for_error
                                        );
                                }
                                else {
                                        if ( $AtWill_Flag ) {
                                                # Do not need a TIMEUNIT tag if the TIMES tag equals AtWill
                                                # Nothing to see here. Move along.
                                        }
                                        else {
                                                # [ 1997408 ] False positive: TIMEUNIT= parameter is missing
                                                # $log->info(
                                                #       qq(the TIMEUNIT= parameter is missing in "$tag_name:$tag_value"),
                                                #       $file_for_error,
                                                #       $line_for_error
                                                # );
                                        }
                                }
                        }

                        if ( $nb_casterlevel != 1 ) {
                                if ($nb_casterlevel) {
                                $log->notice(
                                        qq{CASTERLEVEL= should not be used more then once in "$tag_name:$tag_value"},
                                        $file_for_error,
                                        $line_for_error
                                );
                                }
                                else {
                                $log->info(
                                        qq(the CASTERLEVEL= parameter is missing in "$tag_name:$tag_value"),
                                        $file_for_error,
                                        $line_for_error
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

                        for my $spell_or_param (split q{\|}, $tag_value) {
                                # Is it a parameter?
                                if ( $spell_or_param =~ / \A ([^=]*) = (.*) \z/xms ) {
                                my ($param_id,$param_value) = ($1,$2);

                                if ( $param_id eq 'CLASS' ) {
                                        push @LstTidy::Report::xcheck_to_process,
                                                [
                                                'CLASS',
                                                qq{@@" in "$tag_name:$tag_value},
                                                $file_for_error,
                                                $line_for_error,
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
                                        $log->notice(
                                                qq{Invalide SPELLS parameter: "$spell_or_param" found in "$tag_name:$tag_value"},
                                                $file_for_error,
                                                $line_for_error
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
                                        $tag_name,
                                        $file_for_error,
                                        $line_for_error,
                                        @spells,
                                        ];
                        }
                }
                }
                elsif ( index( $tag_name, 'SPELLLEVEL:' ) == 0 
                        || index( $tag_name, 'SPELLKNOWN:' ) == 0
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

                if ( $tag_name eq "SPELLLEVEL:CLASS" 
                        || $tag_name eq "SPELLKNOWN:CLASS"
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
                        my $tag_line = $tag_value;
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
                                                        push @LstTidy::Report::xcheck_to_process, [
                                                                'CLASS', qq(@@" in "$tag_name$tag_value),
                                                                $file_for_error, $line_for_error, $1
                                                        ];
                                                }
                                                else {
                                                        $log->notice(
                                                                qq{Invalid syntax for "$class" in "$tag_name$tag_value"},
                                                                $file_for_error,
                                                                $line_for_error
                                                        );
                                                }

                                                # The SPELL names
                                                # To be processed later
                                                push @LstTidy::Report::xcheck_to_process,
                                                        [
                                                                'SPELL',                qq(@@" in "$tag_name$tag_value),
                                                                $file_for_error, $line_for_error,
                                                                split ',',              $spells
                                                        ];
                                        }
                                        else {
                                                $log->notice(
                                                        qq{Invalid class/spell list paring in "$tag_name$tag_value"},
                                                        $file_for_error,
                                                        $line_for_error
                                                );
                                                $working_value = "";
                                        }
                                }
                        }
                        else {
                                $log->notice(
                                qq{No value found for "$tag_name"},
                                $file_for_error,
                                $line_for_error
                                );
                        }
                }
                if ( $tag_name eq "SPELLLEVEL:DOMAIN" 
                        || $tag_name eq "SPELLKNOWN:DOMAIN"
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
                        if ( my $working_value = $tag_value ) {
                                while ($working_value) {
                                if ( $working_value =~ s/\|([^|]+)\|([^|]+)// ) {
                                        my $domain = $1;
                                        my $spells = $2;

                                        # The DOMAIN
                                        if ( $domain =~ /([^=]+)\=(\d+)/ ) {
                                                push @LstTidy::Report::xcheck_to_process,
                                                [
                                                'DOMAIN', qq(@@" in "$tag_name$tag_value),
                                                $file_for_error, $line_for_error, $1
                                                ];
                                        }
                                        else {
                                                $log->notice(
                                                qq{Invalid syntax for "$domain" in "$tag_name$tag_value"},
                                                $file_for_error,
                                                $line_for_error
                                                );
                                        }

                                        # The SPELL names
                                        # To be processed later
                                        push @LstTidy::Report::xcheck_to_process,
                                                [
                                                'SPELL',                qq(@@" in "$tag_name$tag_value),
                                                $file_for_error, $line_for_error,
                                                split ',',              $spells
                                                ];
                                }
                                else {
                                        $log->notice(
                                                qq{Invalid domain/spell list paring in "$tag_name$tag_value"},
                                                $file_for_error,
                                                $line_for_error
                                        );
                                        $working_value = "";
                                }
                                }
                        }
                        else {
                                $log->notice(
                                qq{No value found for "$tag_name"},
                                $file_for_error,
                                $line_for_error
                                );
                        }
                }
                }
                elsif ( $tag_name eq 'STAT' ) {
                if ( $linetype eq 'KIT STAT' ) {
                        # STAT:STR=17|DEX=10|CON=14|INT=8|WIS=12|CHA=14
                        my %stat_count_for = map { $_ => 0 } @valid_system_stats;

                        STAT:
                        for my $stat_expression (split /[|]/, $tag_value) {
                                my ($stat) = ( $stat_expression =~ / \A ([A-Z]{3}) [=] (\d+|roll\(\"\w+\"\)((\+|\-)var\(\"STAT.*\"\))*) \z /xms );
                                if ( !defined $stat ) {
                                # Syntax error
                                $log->notice(
                                        qq{Invalid syntax for "$stat_expression" in "$tag_name:$tag_value"},
                                        $file_for_error,
                                        $line_for_error
                                );

                                next STAT;
                                }

                                if ( !exists $stat_count_for{$stat} ) {
                                # The stat is not part of the official list
                                $log->notice(
                                        qq{Invalid attribute name "$stat" in "$tag_name:$tag_value"},
                                        $file_for_error,
                                        $line_for_error
                                );
                                }
                                else {
                                $stat_count_for{$stat}++;
                                }
                        }

                        # We check to see if some stat are repeated
                        for my $stat (@valid_system_stats) {
                                if ( $stat_count_for{$stat} > 1 ) {
                                $log->notice(
                                        qq{Found $stat more then once in "$tag_name:$tag_value"},
                                        $file_for_error,
                                        $line_for_error
                                );
                                }
                        }
                }
                }
                elsif ( $tag_name eq 'TEMPLATE' && $linetype ne 'PCC' ) {
                # TEMPLATE:<template name>|<template name>|etc.
                push @LstTidy::Report::xcheck_to_process,
                        [  'TEMPLATE',
                                $tag_name,
                                $file_for_error,
                                $line_for_error,
                                (split /[|]/, $tag_value),
                        ];
                }
                ######################################################################
                # Here we capture data for later validation
                elsif ( $tag_name eq 'RACESUBTYPE' ) {
                for my $race_subtype (split /[|]/, $tag_value) {
                        my $new_race_subtype = $race_subtype;
                        if ( $linetype eq 'RACE' ) {
                                # The RACE sub-type are created in the RACE file
                                if ( $race_subtype =~ m{ \A [.] REMOVE [.] }xmsi ) {
                                # The presence of a remove means that we are trying
                                # to modify existing data and not create new one
                                push @LstTidy::Report::xcheck_to_process,
                                        [  'RACESUBTYPE',
                                                $tag_name,
                                                $file_for_error,
                                                $line_for_error,
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
                                        $tag_name,
                                        $file_for_error,
                                        $line_for_error,
                                        $race_subtype,
                                ];
                        }
                }
                }
                elsif ( $tag_name eq 'RACETYPE' ) {
                for my $race_type (split /[|]/, $tag_value) {
                        if ( $linetype eq 'RACE' ) {
                                # The RACE type are created in the RACE file
                                if ( $race_type =~ m{ \A [.] REMOVE [.] }xmsi ) {
                                # The presence of a remove means that we are trying
                                # to modify existing data and not create new one
                                push @LstTidy::Report::xcheck_to_process,
                                        [  'RACETYPE',
                                                $tag_name,
                                                $file_for_error,
                                                $line_for_error,
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
                                        $tag_name,
                                        $file_for_error,
                                        $line_for_error,
                                        $race_type,
                                ];
                        }
                }
                }
                elsif ( $tag_name eq 'TYPE' ) {
                        # The types go into valid_types
                        $valid_types{$linetype}{$_}++ for ( split '\.', $tag_value );
                }
                elsif ( $tag_name eq 'CATEGORY' ) {
                        # The categories go into valid_categories
                        $valid_categories{$linetype}{$_}++ for ( split '\.', $tag_value );
                }
                ######################################################################
                # Tag with numerical values
                elsif ( $tag_name eq 'STARTSKILLPTS'
                        || $tag_name eq 'SR'
                        ) {

                # These tags should only have a numeribal value
                push @LstTidy::Report::xcheck_to_process,
                        [
                                'DEFINE Variable',
                                qq(@@" in "$tag_name:$tag_value),
                                $file_for_error,
                                $line_for_error,
                                LstTidy::Parse::parseJep(
                                $tag_value,
                                "$tag_name:$tag_value",
                                $file_for_error,
                                $line_for_error
                                ),
                        ];
                }
                elsif ( $tag_name eq 'DEFINE' ) {
                        my ( $var_name, @formulas ) = split '\|', $tag_value;

                        # First we store the DEFINE variable name
                        if ($var_name) {
                                if ( $var_name =~ /^[a-z][a-z0-9_]*$/i ) {
                                   LstTidy::Validate::setEntityValid('DEFINE Variable', $var_name);

                                        #####################################################
                                        # Export a list of variable names if requested
                                        if ( LstTidy::Options::isConversionActive('Export lists') ) {
                                                my $file = $file_for_error;
                                                $file =~ tr{/}{\\};
                                                print { $filehandle_for{VARIABLE} }
                                                        qq{"$var_name","$line_for_error","$file"\n};
                                        }

                                }

                                # LOCK.xxx and BASE.xxx are not error (even if they are very ugly)
                                elsif ( $var_name !~ /(BASE|LOCK)\.(STR|DEX|CON|INT|WIS|CHA|DVR)/ ) {
                                        $log->notice(
                                                qq{Invalid variable name "$var_name" in "$tag_name:$tag_value"},
                                                $file_for_error,
                                                $line_for_error
                                        );
                                }
                        }
                        else {
                                $log->notice(
                                        qq{I was not able to find a proper variable name in "$tag_name:$tag_value"},
                                        $file_for_error,
                                        $line_for_error
                                );
                        }

                        # Second we deal with the formula
                        for my $formula (@formulas) {
                                push @LstTidy::Report::xcheck_to_process,
                                        [
                                                'DEFINE Variable',
                                                qq(@@" in "$tag_name:$tag_value),
                                                $file_for_error,
                                                $line_for_error,
                                                LstTidy::Parse::parseJep(
                                                        $formula,
                                                        "$tag_name:$tag_value",
                                                        $file_for_error,
                                                        $line_for_error
                                                )
                                        ];
                        }
                }
                elsif ( $tag_name eq 'SA' ) {
                        my ($var_string) = ( $tag_value =~ /[^|]\|(.*)/ );
                        if ($var_string) {
                                FORMULA:
                                for my $formula ( split '\|', $var_string ) {

                                        # Are there any PRE tags in the SA tag.
                                        if ( $formula =~ /(^!?PRE[A-Z]*):(.*)/ ) {

                                                # A PRExxx tag is present
                                                LstTidy::Validate::validatePreTag($1,
                                                        $2,
                                                        "$tag_name:$tag_value",
                                                        $linetype,
                                                        $file_for_error,
                                                        $line_for_error
                                                );
                                                next FORMULA;
                                        }

                                        push @LstTidy::Report::xcheck_to_process,
                                                [
                                                        'DEFINE Variable',
                                                        qq(@@" in "$tag_name:$tag_value),
                                                        $file_for_error,
                                                        $line_for_error,
                                                        LstTidy::Parse::parseJep(
                                                                $formula,
                                                                "$tag_name:$tag_value",
                                                                $file_for_error,
                                                                $line_for_error
                                                        )
                                                ];
                                }
                        }
                }
                elsif ( $linetype eq 'SPELL'
                        && ( $tag_name eq 'TARGETAREA' || $tag_name eq 'DURATION' || $tag_name eq 'DESC' ) )
                {

                        # Inline f*#king tags.
                        # We need to find CASTERLEVEL between ()
                        my $value = $tag_value;
                        pos $value = 0;

                        FIND_BRACKETS:
                        while ( pos $value < length $value ) {
                                my $result;
                                # Find the first set of ()
                                if ( (($result) = Text::Balanced::extract_bracketed( $value, '()' ))
                                        && $result
                                ) {
                                        # Is there a CASTERLEVEL inside?
                                        if ( $result =~ / CASTERLEVEL /xmsi ) {
                                        push @LstTidy::Report::xcheck_to_process,
                                                [
                                                        'DEFINE Variable',
                                                        qq(@@" in "$tag_name:$tag_value),
                                                        $file_for_error,
                                                        $line_for_error,
                                                        LstTidy::Parse::parseJep(
                                                        $result,
                                                        "$tag_name:$tag_value",
                                                        $file_for_error,
                                                        $line_for_error
                                                        )
                                                ];
                                        }
                                }
                                else {
                                        last FIND_BRACKETS;
                                }
                        }
                }
                elsif ( $tag_name eq 'NATURALATTACKS' ) {

                        # NATURALATTACKS:<Natural weapon name>,<List of type>,<attacks>,<damage>|...
                        #
                        # We must make sure that there are always four , separated parameters
                        # between the |.

                        for my $entry ( split '\|', $tag_value ) {
                                my @parameters = split ',', $entry;

                                my $NumberOfParams = scalar @parameters;

                                # must have 4 or 5 parameters
                                if ($NumberOfParams == 5 or $NumberOfParams == 4) { 
                                
                                        # If Parameter 5 exists, it must be an SPROP
                                        if (defined $parameters[4]) {
                                                $log->notice(
                                                        qq{5th parameter should be an SPROP in "NATURALATTACKS:$entry"},
                                                        $file_for_error,
                                                        $line_for_error
                                                ) unless $parameters[4] =~ /^SPROP=/;
                                        }

                                        # Parameter 3 is a number
                                        $log->notice(
                                                qq{3rd parameter should be a number in "NATURALATTACKS:$entry"},
                                                $file_for_error,
                                                $line_for_error
                                        ) unless $parameters[2] =~ /^\*?\d+$/;

                                        # Are the types valid EQUIPMENT types?
                                        push @LstTidy::Report::xcheck_to_process,
                                                [
                                                        'EQUIPMENT TYPE', qq(@@" in "$tag_name:$entry),
                                                        $file_for_error,  $line_for_error,
                                                        grep { !$valid_NATURALATTACKS_type{$_} } split '\.', $parameters[1]
                                                ];
                                }
                                else {
                                        $log->notice(
                                                qq{Wrong number of parameter for "NATURALATTACKS:$entry"},
                                                $file_for_error,
                                        $line_for_error
                                        );
                                }
                        }
                }
                elsif ( $tag_name eq 'CHANGEPROF' ) {

                # "CHANGEPROF:" <list of weapons> "=" <new prof> { "|"  <list of weapons> "=" <new prof> }*
                # <list of weapons> := ( <weapon> | "TYPE=" <weapon type> ) { "," ( <weapon> | "TYPE=" <weapon type> ) }*

                        for my $entry ( split '\|', $tag_value ) {
                                if ( $entry =~ /^([^=]+)=([^=]+)$/ ) {
                                        my ( $list_of_weapons, $new_prof ) = ( $1, $2 );

                                        # First, the weapons (equipment)
                                        push @LstTidy::Report::xcheck_to_process,
                                                [
                                                        'EQUIPMENT', $tag_name, $file_for_error, $line_for_error,
                                                        split ',',   $list_of_weapons
                                                ];

                                        # Second, the weapon prof.
                                        push @LstTidy::Report::xcheck_to_process,
                                                [
                                                        'WEAPONPROF', $tag_name, $file_for_error, $line_for_error,
                                                        $new_prof
                                                ];

                                }
                                else {
                                }
                        }
                }

##  elsif($tag_name eq 'CHOOSE')
##  {
##      # Is the CHOOSE type valid?
##      my ($choose_type) = ($tag_value =~ /^([^=|]+)/);
##
##      if($choose_type && !exists $token_CHOOSE_tag{$choose_type})
##      {
##      if(index($choose_type,' ') != -1)
##      {
##              # There is a space in the choose type, it must be a
##              # typeless CHOOSE (darn).
##              $log->notice(  "** Typeless CHOOSE found: \"$tag_name:$tag_value\" in $linetype.",
##                      $file_for_error, $line_for_error );
##      }
##      else
##      {
##              LstTidy::Report::incCountInvalidTags($linetype, "$tag_name:$choose_type"); 
##              $log->notice(  "Invalid CHOOSE:$choose_type tag \"$tag_name:$tag_value\" found in $linetype.",
##                      $file_for_error, $line_for_error );
##      }
##      }
##      elsif(!$choose_type)
##      {
##      LstTidy::Report::incCountInvalidTags($linetype, "CHOOSE"); 
##      $log->notice(  "Invalid CHOOSE tag \"$tag_name:$tag_value\" found in $linetype",
##              $file_for_error, $line_for_error );
##      }
##  }

        }

}       # BEGIN End



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

sub additionnal_tag_parsing {
        my ( $tag_name, $tag_value, $linetype, $file_for_error, $line_for_error ) = @_;

        ##################################################################
        # [ 1514765 ] Conversion to remove old defaultmonster tags
        # Gawaine42 (Richard Bowers)
        # Bonuses associated with a PREDEFAULTMONSTER:Y need to be removed
        # Bonuses associated with a PREDEFAULTMONSTER:N are retained without
        #               the PREDEFAULTMONSTER:N
        if ( LstTidy::Options::isConversionActive('RACE:Fix PREDEFAULTMONSTER bonuses')
                && $tag_name =~ /BONUS/ ) {
        if ($tag_value =~ /PREDEFAULTMONSTER:N/ ) {
                $_[1] =~ s/[|]PREDEFAULTMONSTER:N//;
                $log->warning(
                        qq(Replacing "$tag_name:$tag_value" by "$_[0]:$_[1]"),
                        $file_for_error,
                        $line_for_error
                        );
        }
        }

        if ( LstTidy::Options::isConversionActive('ALL:Weaponauto simple conversion')
                && $tag_name =~ /WEAPONAUTO/)
                {
                $_[0] = 'AUTO';
                $_[1] =~ s/Simple/TYPE.Simple/;
                $_[1] =~ s/Martial/TYPE.Martial/;
                $_[1] =~ s/Exotic/TYPE.Exotic/;
                $_[1] =~ s/SIMPLE/TYPE.Simple/;
                $_[1] =~ s/MARTIAL/TYPE.Martial/;
                $_[1] =~ s/EXOTIC/TYPE.Exotic/;
                $_[1] = "WEAPONPROF|$_[1]";
                $log->warning(
                        qq(Replacing "$tag_name:$tag_value" by "$_[0]:$_[1]"),
                        $file_for_error,
                        $line_for_error
                        );
                }

        ##################################################################
        # [ 1398237 ] ALL: Convert Willpower to Will
        #
        # The BONUS:CHECKS and PRECHECKBASE tags must be converted
        #
        # BONUS:CHECKS|<list of save types>|<other tag parameters>
        # PRECHECKBASE:<number>,<list of saves>

        if ( LstTidy::Options::isConversionActive('ALL:Willpower to Will') ) {
                if ( $tag_name eq 'BONUS:CHECKS' ) {
                # We split the tag parameters
                my @tag_params = split q{\|}, $tag_value;


                # The Willpower keyword must be replace only in parameter 1
                # (parameter 0 is empty since the tag_value begins by | )
                if ( $tag_params[1] =~ s{ \b Willpower \b }{Will}xmsg ) {
                        # We plug the new value in the calling parameter
                        $_[1] = join q{|}, @tag_params;

                        $log->warning(
                                qq{Replacing "$tag_name$tag_value" by "$_[0]$_[1]"},
                                $file_for_error,
                                $line_for_error
                        );

                }

                }
                elsif ( $tag_name eq 'PRECHECKBASE' ){
                # Since the first parameter is a number, no need to
                # split before replacing.

                # Yes, we change directly the calling parameter
                if ( $_[1] =~ s{ \b Willpower \b }{Will}xmsg ) {
                        $log->warning(
                                qq{Replacing "$tag_name:$tag_value" by "$_[0]:$_[1]"},
                                $file_for_error,
                                $line_for_error
                        );
                }
                }
        }


        ##################################################################
        # We find the tags that use the word Willpower

        if ( LstTidy::Options::isConversionActive('ALL:Find Willpower') && getOption('exportlist') ) {
                if ( $tag_value
                        =~ m{ \b                # Word boundary
                                Willpower       # We need to find the word Willpower
                                \b              # Word boundary
                                }xmsi
                ) {
                # We write the tag and related information to the willpower.csv file
                my $tag_separator = $tag_name =~ / : /xms ? q{} : q{:};
                my $file_name = $file_for_error;
                $file_name =~ tr{/}{\\};
                print { $filehandle_for{Willpower} }
                        qq{"$tag_name$tag_separator$tag_value","$line_for_error","$file_name"\n};
                }
        }

        ##################################################################
        # PRERACE now only accepts the format PRERACE:<number>,<race list>
        # All the PRERACE tags must be reformated to use the default way.

        if ( LstTidy::Options::isConversionActive('ALL:PRERACE needs a ,') ) {
                if ( $tag_name eq 'PRERACE' || $tag_name eq '!PRERACE' ) {
                if ( $tag_value !~ / \A \d+ [,], /xms ) {
                        $_[1] = '1,' . $_[1];
                        $log->warning(
                                qq{Replacing "$tag_name:$tag_value" by "$_[0]:$_[1]"},
                                $file_for_error,
                                $line_for_error
                        );
                }
                }
                elsif ( index( $tag_name, 'BONUS' ) == 0 && $tag_value =~ /PRERACE:([^]|]*)/ ) {
                my $prerace_value = $1;
                if ( $prerace_value !~ / \A \d+ [,] /xms ) {

                        # There is no ',', we need to add one
                        $_[1] =~ s/ PRERACE: (?!\d) /PRERACE:1,/xmsg;

                        $log->warning(
                                qq{Replacing "$tag_name$tag_value" by "$_[0]$_[1]"},
                                $file_for_error,
                                $line_for_error
                        );
                }
                }
                elsif ( ( $tag_name eq 'SA' || $tag_name eq 'PREMULT' )
                && $tag_value =~ / PRERACE: ( [^]|]* ) /xms
                ) {
                my $prerace_value = $1;
                if ( $prerace_value !~ / \A \d+ [,] /xms ) {

                        # There is no ',', we need to add one
                        $_[1] =~ s/ PRERACE: (?!\d) /PRERACE:1,/xmsg;

                        $log->warning(
                                qq{Replacing "$tag_name:$tag_value" by "$_[0]:$_[1]"},
                                $file_for_error,
                                $line_for_error
                        );
                }
                }
        }
        ##################################################################
        # [ 1173567 ] Convert old style PREALIGN to new style
        # PREALIGN now accept letters instead of numbers to specify alignments
        # All the PREALIGN tags must be reformated to the letters.

        if ( LstTidy::Options::isConversionActive('ALL:PREALIGN conversion') ) {
                if ( $tag_name eq 'PREALIGN' || $tag_name eq '!PREALIGN' ) {
                my $new_value = join ',', map { $PREALIGN_conversion_5715{$_} || $_ } split ',',
                        $tag_value;

                if ( $tag_value ne $new_value ) {
                        $_[1] = $new_value;
                        $log->warning(
                                qq{Replacing "$tag_name:$tag_value" by "$_[0]:$_[1]"},
                                $file_for_error,
                                $line_for_error
                        );
                }
                }
                elsif (index( $tag_name, 'BONUS' ) == 0
                || $tag_name eq 'SA'
                || $tag_name eq 'PREMULT' )
                {
                while ( $tag_value =~ /PREALIGN:([^]|]*)/g ) {
                        my $old_value = $1;
                        my $new_value = join ',', map { $PREALIGN_conversion_5715{$_} || $_ } split ',',
                                $old_value;

                        if ( $new_value ne $old_value ) {

                                # There is no ',', we need to add one
                                $_[1] =~ s/PREALIGN:$old_value/PREALIGN:$new_value/;
                        }
                }

                $log->warning(
                        qq{Replacing "$tag_name$tag_value" by "$_[0]$_[1]"},
                        $file_for_error,
                        $line_for_error
                ) if $_[1] ne $tag_value;
                }
        }

        ##################################################################
        # [ 1070344 ] HITDICESIZE to HITDIE in templates.lst
        #
        # HITDICESIZE:.* must become HITDIE:.* in the TEMPLATE line types.

        if (   LstTidy::Options::isConversionActive('TEMPLATE:HITDICESIZE to HITDIE')
                && $tag_name eq 'HITDICESIZE'
                && $linetype eq 'TEMPLATE'
        ) {
                # We just change the tag name, the value remains the same.
                $_[0] = 'HITDIE';
                $log->warning(
                qq{Changing "$tag_name:$tag_value" to "$_[0]:$_[1]"},
                $file_for_error,
                $line_for_error
                );
        }

        ##################################################################
        # Remove all the PREALIGN tag from within BONUS, SA and
        # VFEAT tags.
        #
        # This is needed by my CMP friends .

        if ( LstTidy::Options::isConversionActive('ALL:CMP remove PREALIGN') ) {
                if ( $tag_value =~ /PREALIGN/ ) {
                my $ponc = $tag_name =~ /:/ ? "" : ":";

                if ( $tag_value =~ /PREMULT/ ) {
                        $log->warning(
                                qq(PREALIGN found in PREMULT, you will have to remove it yourself "$tag_name$ponc$tag_value"),
                                $file_for_error,
                                $line_for_error
                        );
                }
                elsif ( $tag_name =~ /^BONUS/ || $tag_name eq 'SA' || $tag_name eq 'VFEAT' ) {
                        $_[1] = join( '|', grep { !/^(!?)PREALIGN/ } split '\|', $tag_value );
                        $log->warning(
                                qq{Replacing "$tag_name$ponc$tag_value" with "$_[0]$ponc$_[1]"},
                                $file_for_error,
                                $line_for_error
                        );
                }
                else {
                        $log->warning(
                                qq(Found PREALIGN where I was not expecting it "$tag_name$ponc$tag_value"),
                                $file_for_error,
                                $line_for_error
                        );
                }
                }
        }

        ##################################################################
        # [ 1006285 ] Conversion MOVE:<number> to MOVE:Walk,<Number>
        #
        # All the MOVE:<number> tags must be converted to
        # MOVE:Walk,<number>

        if (   LstTidy::Options::isConversionActive('ALL:MOVE:nn to MOVE:Walk,nn')
                && $tag_name eq "MOVE"
        ) {
                if ( $tag_value =~ /^(\d+$)/ ) {
                $_[1] = "Walk,$1";
                $log->warning(
                        qq{Changing "$tag_name:$tag_value" to "$_[0]:$_[1]"},
                        $file_for_error,
                        $line_for_error
                );
                }
        }

        ##################################################################
        # [ 892746 ] KEYS entries were changed in the main files
        #
        # All the EQMOD and PRETYPE:EQMOD tags must be scanned for
        # possible KEY replacement.

        if(LstTidy::Options::isConversionActive('ALL:EQMOD has new keys') &&
                ($tag_name eq "EQMOD" || $tag_name eq "REPLACES" || ($tag_name eq "PRETYPE" && $tag_value =~ /^(\d+,)?EQMOD/)))
        {
                for my $old_key (keys %Key_conversion_56)
                {
                        if($tag_value =~ /\Q$old_key\E/)
                        {
                                $_[1] =~ s/\Q$old_key\E/$Key_conversion_56{$old_key}/;
                                $log->notice(
                                        qq(=> Replacing "$old_key" with "$Key_conversion_56{$old_key}" in "$tag_name:$tag_value"),
                                        $file_for_error,
                                        $line_for_error
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

        if (   LstTidy::Options::isConversionActive('RACE:CSKILL to MONCSKILL')
                && $linetype eq "RACE"
                && $tag_name eq "CSKILL"
        ) {
                $log->warning(
                qq{Found CSKILL in RACE file},
                $file_for_error,
                $line_for_error
                );
        }

        ##################################################################
        # GAMEMODE DnD is now 3e

        if (   LstTidy::Options::isConversionActive('PCC:GAMEMODE DnD to 3e')
                && $tag_name  eq "GAMEMODE"
                && $tag_value eq "DnD"
        ) {
                $_[1] = "3e";
                $log->warning(
                qq{Changing "$tag_name:$tag_value" to "$_[0]:$_[1]"},
                $file_for_error,
                $line_for_error
                );
        }

        ##################################################################
        # Add 3e to GAMEMODE:DnD_v30e and 35e to GAMEMODE:DnD_v35e

        if (   LstTidy::Options::isConversionActive('PCC:GAMEMODE Add to the CMP DnD_')
                && $tag_name eq "GAMEMODE"
                && $tag_value =~ /DnD_/
        ) {
                my ( $has_3e, $has_35e, $has_DnD_v30e, $has_DnD_v35e );

#               map {
#               $has_3e = 1
#                       if $_ eq "3e";
#               $has_DnD_v30e = 1 if $_ eq "DnD_v30e";
#               $has_35e        = 1 if $_ eq "35e";
#               $has_DnD_v35e = 1 if $_ eq "DnD_v35e";
#               } split '\|', $tag_value;

                for my $game_mode (split q{\|}, $tag_value) {
                $has_3e         = 1 if $_ eq "3e";
                $has_DnD_v30e = 1 if $_ eq "DnD_v30e";
                $has_35e        = 1 if $_ eq "35e";
                $has_DnD_v35e = 1 if $_ eq "DnD_v35e";
                }

                $_[1] =~ s/(DnD_v30e)/3e\|$1/  if !$has_3e  && $has_DnD_v30e;
                $_[1] =~ s/(DnD_v35e)/35e\|$1/ if !$has_35e && $has_DnD_v35e;

                #$_[1] =~ s/(DnD_v30e)\|(3e)/$2\|$1/;
                #$_[1] =~ s/(DnD_v35e)\|(35e)/$2\|$1/;
                $log->warning(
                qq{Changing "$tag_name:$tag_value" to "$_[0]:$_[1]"},
                $file_for_error,
                $line_for_error
                ) if "$tag_name:$tag_value" ne "$_[0]:$_[1]";
        }

        ##################################################################
        # [ 784363 ] Add TYPE=Base.REPLACE to most BONUS:COMBAT|BAB
        # The BONUS:COMBAT|BAB found in CLASS, CLASS Level,
        # SUBCLASS and SUBCLASSLEVEL lines must have a |TYPE=Base.REPLACE added to them.
        # The same BONUSes found in RACE files with PREDEFAULTMONSTER tags
        # must also have the TYPE added.
        # All the other BONUS:COMBAT|BAB should be reported since there
        # should not be any really.

        if (   LstTidy::Options::isConversionActive('ALL:Add TYPE=Base.REPLACE')
                && $tag_name eq "BONUS:COMBAT"
                && $tag_value =~ /^\|(BAB)\|/i
        ) {

                # Is the BAB in uppercase ?
                if ( $1 ne 'BAB' ) {
                $_[1] =~ s/\|bab\|/\|BAB\|/i;
                $log->warning(
                        qq{Changing "$tag_name$tag_value" to "$_[0]$_[1]" (BAB must be in uppercase)},
                        $file_for_error,
                        $line_for_error
                );
                $tag_value = $_[1];
                }

                # Is there already a TYPE= in the tag?
                my $is_type = $tag_value =~ /TYPE=/;

                # Is it the good one?
                my $is_type_base = $is_type && $tag_value =~ /TYPE=Base/;

                # Is there a .REPLACE at after the TYPE=Base?
                my $is_type_replace = $is_type_base && $tag_value =~ /TYPE=Base\.REPLACE/;

                # Is there a PREDEFAULTMONSTER tag embedded?
                my $is_predefaultmonster = $tag_value =~ /PREDEFAULTMONSTER/;

                # We must replace the CLASS, CLASS Level, SUBCLASS, SUBCLASSLEVEL
                # and PREDEFAULTMONSTER RACE lines
                if (   $linetype eq 'CLASS'
                || $linetype eq 'CLASS Level'
                || $linetype eq 'SUBCLASS'
                || $linetype eq 'SUBCLASSLEVEL'
                || ( ( $linetype eq 'RACE' || $linetype eq 'TEMPLATE' ) && $is_predefaultmonster ) )
                {
                if ( !$is_type ) {

                        # We add the TYPE= statement at the end
                        $_[1] .= '|TYPE=Base.REPLACE';
                        $log->warning(
                                qq{Adding "|TYPE=Base.REPLACE" to "$tag_name$tag_value"},
                                $file_for_error,
                                $line_for_error
                        );
                }
                else {

                        # The TYPE is already there but is it the correct one?
                        if ( !$is_type_replace && $is_type_base ) {

                                # We add the .REPLACE part
                                $_[1] =~ s/\|TYPE=Base/\|TYPE=Base.REPLACE/;
                                $log->warning(
                                qq{Adding ".REPLACE" to "$tag_name$tag_value"},
                                $file_for_error,
                                $line_for_error
                                );
                        }
                        elsif ( !$is_type_base ) {
                                $log->info(
                                qq{Verify the TYPE of "$tag_name$tag_value"},
                                $file_for_error,
                                $line_for_error
                                );
                        }
                }
                }
                else {

                # If there is a BONUS:COMBAT elsewhere, we report it for manual
                # inspection.
                $log->info( qq{Verify this tag "$tag_name$tag_value"}, $file_for_error, $line_for_error);
                }
        }

        ##################################################################
        # [ 737718 ] COUNT[FEATTYPE] data change
        # A ALL. must be added at the end of every COUNT[FEATTYPE=FooBar]
        # found in the DEFINE tags if not already there.

        if (   LstTidy::Options::isConversionActive('ALL:COUNT[FEATTYPE=...')
                && $tag_name eq "DEFINE"
        ) {
                if ( $tag_value =~ /COUNT\[FEATTYPE=/i ) {
                my $value = $tag_value;
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

                if ( $new_value ne $tag_value ) {
                        $_[1] = $new_value;
                        $log->warning(
                                qq{Replacing "$tag_name:$tag_value" with "$_[0]:$_[1]"},
                                $file_for_error,
                                $line_for_error
                        );
                }
                }
        }

        ##################################################################
        # PRECLASS now only accepts the format PRECLASS:1,<class>=<n>
        # All the PRECLASS tags must be reformated to use the default way.

        if ( LstTidy::Options::isConversionActive('ALL:PRECLASS needs a ,') ) {
                if ( $tag_name eq 'PRECLASS' || $tag_name eq '!PRECLASS' ) {
                unless ( $tag_value =~ /^\d+,/ ) {
                        $_[1] = '1,' . $_[1];
                        $log->warning(
                                qq{Replacing "$tag_name:$tag_value" with "$_[0]:$_[1]"},
                                $file_for_error,
                                $line_for_error
                        );
                }
                }
                elsif ( index( $tag_name, 'BONUS' ) == 0 && $tag_value =~ /PRECLASS:([^]|]*)/ ) {
                my $preclass_value = $1;
                unless ( $preclass_value =~ /^\d+,/ ) {

                        # There is no ',', we need to add one
                        $_[1] =~ s/PRECLASS:(?!\d)/PRECLASS:1,/g;

                        $log->warning(
                                qq{Replacing "$tag_name$tag_value" with "$_[0]$_[1]"},
                                $file_for_error,
                                $line_for_error
                        );
                }
                }
                elsif ( ( $tag_name eq 'SA' || $tag_name eq 'PREMULT' )
                && $tag_value =~ /PRECLASS:([^]|]*)/
                ) {
                my $preclass_value = $1;
                unless ( $preclass_value =~ /^\d+,/ ) {

                        # There is no ',', we need to add one
                        $_[1] =~ s/PRECLASS:(?!\d)/PRECLASS:1,/g;

                        $log->warning(
                                qq{Replacing "$tag_name:$tag_value" with "$_[0]:$_[1]"},
                                $file_for_error,
                                $line_for_error
                        );
                }
                }
        }

        ##################################################################
        # [ 711565 ] BONUS:MOVE replaced with BONUS:MOVEADD
        #
        # BONUS:MOVE must be replaced by BONUS:MOVEADD in all line types
        # except EQUIPMENT and EQUIPMOD where it most be replaced by
        # BONUS:POSTMOVEADD

        if (   LstTidy::Options::isConversionActive('ALL:BONUS:MOVE conversion') && $tag_name eq 'BONUS:MOVE' ){
                if ( $linetype eq "EQUIPMENT" || $linetype eq "EQUIPMOD" ) {
                        $_[0] = "BONUS:POSTMOVEADD";
                }
                else {
                        $_[0] = "BONUS:MOVEADD";
                }

                $log->warning(
                qq{Replacing "$tag_name$tag_value" with "$_[0]$_[1]"},
                $file_for_error,
                $line_for_error
                );
        }

        ##################################################################
        # [ 699834 ] Incorrect loading of multiple vision types
        # All the , in the VISION tags must be converted to | except for the
        # VISION:.ADD (these will be converted later to BONUS:VISION)
        #
        # [ 728038 ] BONUS:VISION must replace VISION:.ADD
        # Now doing the VISION:.ADD conversion

        if (   LstTidy::Options::isConversionActive('ALL: , to | in VISION') && $tag_name eq 'VISION' ) {
                unless ( $tag_value =~ /(\.ADD,|1,)/i ) {
                        if ( $_[1] =~ tr{,}{|} ) {
                                $log->warning(
                                        qq{Replacing "$tag_name:$tag_value" with "$_[0]:$_[1]"},
                                        $file_for_error,
                                        $line_for_error
                                );
                        }
                }
        }

        ##################################################################
        # PRESTAT now only accepts the format PRESTAT:1,<stat>=<n>
        # All the PRESTAT tags must be reformated to use the default way.

        if ( LstTidy::Options::isConversionActive('ALL:PRESTAT needs a ,') && $tag_name eq 'PRESTAT' ) {
                if ( index( $tag_value, ',' ) == -1 ) {
                        # There is no ',', we need to add one
                        $_[1] = '1,' . $_[1];
                        $log->warning(
                                qq{Replacing "$tag_name:$tag_value" with "$_[0]:$_[1]"},
                                $file_for_error,
                                $line_for_error
                        );
                }
        }

        ##################################################################
        # [ 686169 ] remove ATTACKS: tag
        # ATTACKS:<attacks> must be replaced by BONUS:COMBAT|ATTACKS|<attacks>

        if ( LstTidy::Options::isConversionActive('EQUIPMENT: remove ATTACKS')
                && $tag_name eq 'ATTACKS'
                && $linetype eq 'EQUIPMENT' ) {
                my $number_attacks = $tag_value;
                $_[0] = 'BONUS:COMBAT';
                $_[1] = '|ATTACKS|' . $number_attacks;

                $log->warning(
                        qq{Replacing "$tag_name:$tag_value" with "$_[0]$_[1]"},
                        $file_for_error,
                        $line_for_error
                );
        }

        ##################################################################
        # Name change for SRD compliance (PCGEN 4.3.3)

        if (LstTidy::Options::isConversionActive('ALL: 4.3.3 Weapon name change')
                && (   $tag_name eq 'WEAPONBONUS'
                || $tag_name eq 'WEAPONAUTO'
                || $tag_name eq 'PROF'
                || $tag_name eq 'GEAR'
                || $tag_name eq 'FEAT'
                || $tag_name eq 'PROFICIENCY'
                || $tag_name eq 'DEITYWEAP'
                || $tag_name eq 'MFEAT' )
        ) {
                for ( keys %srd_weapon_name_conversion_433 ) {
                        if ( $_[1] =~ s/\Q$_\E/$srd_weapon_name_conversion_433{$_}/ig ) {
                                $log->warning(
                                        qq{Replacing "$tag_name:$tag_value" with "$_[0]:$_[1]"},
                                        $file_for_error,
                                        $line_for_error
                                );
                        }
                }
        }
}

###############################################################
# validate_line
# -------------
#
# This function perform validation that must be done on a
# whole line at a time.
#
# Paramter: $line_ref           Ref to a hash containing the tags of the line
#               $linetype               Type for the current line
#               $file_for_error   Name of the current file
#               $line_for_error   Number of the current line

sub validate_line {
        my ( $line_ref, $linetype, $file_for_error, $line_for_error ) = @_;

        ########################################################
        # Validation for the line identifier
        ########################################################

        if ( !($linetype eq 'SOURCE'
                || $linetype eq 'KIT LANGAUTO'
                || $linetype eq 'KIT NAME'
                || $linetype eq 'KIT FEAT'
                || $file_for_error =~ m{ [.] PCC \z }xmsi
                || $linetype eq 'COMPANIONMOD') # FOLLOWER:Class1,Class2=level
        ) {

                # We get the line identifier.
                my $identifier = $line_ref->{ @{LstTidy::Reformat::getLineTypeOrder($linetype)}[0] }[0];

                # We hunt for the bad comma.
                if($identifier =~ /,/) {
                        $log->notice(
                                qq{"," (comma) should not be used in line identifier name: $identifier},
                                $file_for_error,
                                $line_for_error
                        );
                }
        }

        ########################################################
        # Special validation for specific tags
        ########################################################

        if ( 0 && $linetype eq 'SPELL' )        # disabled for now.
        {

                # Either or both CLASSES and DOMAINS tags must be
                # present in a normal SPELL line

                if (  exists $line_ref->{'000SpellName'}
                        && $line_ref->{'000SpellName'}[0] !~ /\.MOD$/
                        && exists $line_ref->{'TYPE'}
                        && $line_ref->{'TYPE'}[0] ne 'TYPE:Psionic.Attack Mode'
                        && $line_ref->{'TYPE'}[0] ne 'TYPE:Psionic.Defense Mode' )
                {
                        $log->info(
                                qq(No CLASSES or DOMAINS tag found for SPELL "$line_ref->{'000SpellName'}[0]"),
                                $file_for_error,
                                $line_for_error
                        ) if !( exists $line_ref->{'CLASSES'} || exists $line_ref->{'DOMAINS'} );
                }
        }
        elsif ( $linetype eq "ABILITY" ) {

                # On an ABILITY line type:
                # 0) MUST contain CATEGORY tag
                # 1) if it has MULT:YES, it  _has_ to have CHOOSE
                # 2) if it has CHOOSE, it _has_ to have MULT:YES
                # 3) if it has STACK:YES, it _has_ to have MULT:YES (and CHOOSE)

                # Find lines that modify or remove Categories of Abilityies without naming the Abilities
                my $MOD_Line = $line_ref->{'000AbilityName'}[0];
                study $MOD_Line;

                if ( $MOD_Line =~ /\.(MOD|FORGET|COPY=)/ ) {
                        # Nothing to see here. Move on.
                }
                # Find the Abilities lines without Categories
                elsif ( !$line_ref->{'CATEGORY'} ) {
                        $log->warning(
                                qq(The CATEGORY tag is required in ABILITY "$line_ref->{'000AbilityName'}[0]"),
                                $file_for_error,
                                $line_for_error
                        );
                }
                my ( $hasCHOOSE, $hasMULT, $hasSTACK );

                $hasCHOOSE = 1 if exists $line_ref->{'CHOOSE'};
                $hasMULT   = 1 if exists $line_ref->{'MULT'} && $line_ref->{'MULT'}[0] =~ /^MULT:Y/i;
                $hasSTACK  = 1 if exists $line_ref->{'STACK'} && $line_ref->{'STACK'}[0] =~ /^STACK:Y/i;

                if ( $hasMULT && !$hasCHOOSE ) {
                        $log->info(
                                qq(The CHOOSE tag is mandantory when MULT:YES is present in ABILITY "$line_ref->{'000AbilityName'}[0]"),
                                $file_for_error,
                                $line_for_error
                        );
                }
                elsif ( $hasCHOOSE && !$hasMULT && $line_ref->{'CHOOSE'}[0] !~ /CHOOSE:SPELLLEVEL/i ) {
                        # The CHOOSE:SPELLLEVEL is exempted from this particular rule.
                        $log->info(
                                qq(The MULT:YES tag is mandatory when CHOOSE is present in ABILITY "$line_ref->{'000AbilityName'}[0]"),
                                $file_for_error,
                                $line_for_error
                        );
                }
                elsif ( $hasCHOOSE && !$hasMULT && $line_ref->{'CHOOSE'}[0] !~ /CHOOSE:NUMBER/i ) {
                        # The CHOOSE:NUMBER is exempted from this particular rule.
                        $log->info(
                                qq(The MULT:YES tag is mandatory when CHOOSE is present in ABILITY "$line_ref->{'000AbilityName'}[0]"),
                                $file_for_error,
                                $line_for_error
                        );
                }

                if ( $hasSTACK && !$hasMULT ) {
                        $log->info(
                                qq(The MULT:YES tag is mandatory when STACK:YES is present in ABILITY "$line_ref->{'000AbilityName'}[0]"),
                                $file_for_error,
                                $line_for_error
                        );
                }

                # We identify the feats that can have sub-entities. e.g. Spell Focus(Spellcraft)
                if ($hasCHOOSE) {

                        # The CHOSE type tells us the type of sub-entities
                        my $choose      = $line_ref->{'CHOOSE'}[0];
                        my $ability_name = $line_ref->{'000AbilityName'}[0];
                        $ability_name =~ s/.MOD$//;

                        if ( $choose =~ /^CHOOSE:(?:NUMCHOICES=\d+\|)?(FEAT=[^|]*)/ ) {
                                $valid_sub_entities{'ABILITY'}{$ability_name} = $1;
                        }
                        elsif ( $choose =~ /^CHOOSE:(?:NUMCHOICES=\d+\|)?FEATLIST/ ) {
                                $valid_sub_entities{'ABILITY'}{$ability_name} = 'FEAT';
                        }
                        elsif ( $choose =~ /^CHOOSE:(?:NUMCHOICES=\d+\|)?(?:WEAPONPROFS|Exotic|Martial)/ ) {
                                $valid_sub_entities{'ABILITY'}{$ability_name} = 'WEAPONPROF';
                        }
                        elsif ( $choose =~ /^CHOOSE:(?:NUMCHOICES=\d+\|)?SKILLSNAMED/ ) {
                                $valid_sub_entities{'ABILITY'}{$ability_name} = 'SKILL';
                        }
                        elsif ( $choose =~ /^CHOOSE:(?:NUMCHOICES=\d+\|)?SCHOOLS/ ) {
                                $valid_sub_entities{'ABILITY'}{$ability_name} = 'SPELL_SCHOOL';
                        }
                        elsif ( $choose =~ /^CHOOSE:(?:NUMCHOICES=\d+\|)?SPELLLIST/ ) {
                                $valid_sub_entities{'ABILITY'}{$ability_name} = 'SPELL';
                        }
                        elsif ($choose =~ /^CHOOSE:(?:NUMCHOICES=\d+\|)?SPELLLEVEL/
                                || $choose =~ /^CHOOSE:(?:NUMCHOICES=\d+\|)?HP/ )
                        {

                                # Ad-Lib is a special case that means "Don't look for
                                # anything else".
                                $valid_sub_entities{'ABILITY'}{$ability_name} = 'Ad-Lib';
                        }
                        elsif ( $choose =~ /^CHOOSE:(?:COUNT=\d+\|)?(.*)/ ) {

                                # ad-hod/special list of thingy
                                # It adds to the valid entities instead of the
                                # valid sub-entities.
                                # We do this when we find a CHOOSE but we do not
                                # know what it is for.

                                LstTidy::Validate::splitAndAddToValidEntities('ABILITY', $ability_name, $1);
                        }
                }
        }

        elsif ( $linetype eq "FEAT" ) {

                # [ 1671410 ] xcheck CATEGORY:Feat in Feat object.
                my $hasCategory = 0;
                $hasCategory = 1 if exists $line_ref->{'CATEGORY'};
                if ($hasCategory) {
                        if ($line_ref->{'CATEGORY'}[0] eq "CATEGORY:Feat" ||
                            $line_ref->{'CATEGORY'}[0] eq "CATEGORY:Special Ability") {
                                # Good
                        }
                        else {
                                $log->info(
                                        qq(The CATEGORY tag must have the value of Feat or Special Ability when present on a FEAT. Remove or replace "$line_ref->{'CATEGORY'}[0]"),
                                        $file_for_error,
                                        $line_for_error
                                );
                        }
                }

                # On a FEAT line type:
                # 1) if it has MULT:YES, it  _has_ to have CHOOSE
                # 2) if it has CHOOSE, it _has_ to have MULT:YES
                # 3) if it has STACK:YES, it _has_ to have MULT:YES (and CHOOSE)
                my ( $hasCHOOSE, $hasMULT, $hasSTACK );

                $hasCHOOSE = 1 if exists $line_ref->{'CHOOSE'};
                $hasMULT   = 1 if exists $line_ref->{'MULT'} && $line_ref->{'MULT'}[0] =~ /^MULT:Y/i;
                $hasSTACK  = 1 if exists $line_ref->{'STACK'} && $line_ref->{'STACK'}[0] =~ /^STACK:Y/i;

                if ( $hasMULT && !$hasCHOOSE ) {
                        $log->info(
                                qq(The CHOOSE tag is mandatory when MULT:YES is present in FEAT "$line_ref->{'000FeatName'}[0]"),
                                $file_for_error,
                                $line_for_error
                        );
                }
                elsif ( $hasCHOOSE && !$hasMULT && $line_ref->{'CHOOSE'}[0] !~ /CHOOSE:SPELLLEVEL/i ) {

                        # The CHOOSE:SPELLLEVEL is exampted from this particular rule.
                        $log->info(
                                qq(The MULT:YES tag is mandatory when CHOOSE is present in FEAT "$line_ref->{'000FeatName'}[0]"),
                                $file_for_error,
                                $line_for_error
                        );
                }
                elsif ( $hasCHOOSE && !$hasMULT && $line_ref->{'CHOOSE'}[0] !~ /CHOOSE:NUMBER/i ) {

                        # The CHOOSE:NUMBER is exampted from this particular rule.
                        $log->info(
                                qq(The MULT:YES tag is mandatory when CHOOSE is present in FEAT "$line_ref->{'000FeatName'}[0]"),
                                $file_for_error,
                                $line_for_error
                        );
                }

                if ( $hasSTACK && !$hasMULT ) {
                        $log->info(
                                qq(The MULT:YES tag is mandatory when STACK:YES is present in FEAT "$line_ref->{'000FeatName'}[0]"),
                                $file_for_error,
                                $line_for_error
                        );
                }

                # We identify the feats that can have sub-entities. e.g. Spell Focus(Spellcraft)
                if ($hasCHOOSE) {

                        # The CHOSE type tells us the type of sub-entities
                        my $choose      = $line_ref->{'CHOOSE'}[0];
                        my $feat_name = $line_ref->{'000FeatName'}[0];
                        $feat_name =~ s/.MOD$//;

                        if ( $choose =~ /^CHOOSE:(?:NUMCHOICES=\d+\|)?(FEAT=[^|]*)/ ) {
                                $valid_sub_entities{'FEAT'}{$feat_name} = $1;
                        }
                        elsif ( $choose =~ /^CHOOSE:(?:NUMCHOICES=\d+\|)?FEATLIST/ ) {
                                $valid_sub_entities{'FEAT'}{$feat_name} = 'FEAT';
                        }
                        elsif ( $choose =~ /^CHOOSE:(?:NUMCHOICES=\d+\|)?(?:WEAPONPROFS|Exotic|Martial)/ ) {
                                $valid_sub_entities{'FEAT'}{$feat_name} = 'WEAPONPROF';
                        }
                        elsif ( $choose =~ /^CHOOSE:(?:NUMCHOICES=\d+\|)?SKILLSNAMED/ ) {
                                $valid_sub_entities{'FEAT'}{$feat_name} = 'SKILL';
                        }
                        elsif ( $choose =~ /^CHOOSE:(?:NUMCHOICES=\d+\|)?SCHOOLS/ ) {
                                $valid_sub_entities{'FEAT'}{$feat_name} = 'SPELL_SCHOOL';
                        }
                        elsif ( $choose =~ /^CHOOSE:(?:NUMCHOICES=\d+\|)?SPELLLIST/ ) {
                                $valid_sub_entities{'FEAT'}{$feat_name} = 'SPELL';
                        }
                        elsif ($choose =~ /^CHOOSE:(?:NUMCHOICES=\d+\|)?SPELLLEVEL/
                                || $choose =~ /^CHOOSE:(?:NUMCHOICES=\d+\|)?HP/ )
                        {

                                # Ad-Lib is a special case that means "Don't look for
                                # anything else".
                                $valid_sub_entities{'FEAT'}{$feat_name} = 'Ad-Lib';
                        }
                        elsif ( $choose =~ /^CHOOSE:(?:COUNT=\d+\|)?(.*)/ ) {

                           LstTidy::Validate::splitAndAddToValidEntities('FEAT', $feat_name, $1);
                        }
                }
        }
        elsif ( $linetype eq "EQUIPMOD" ) {

                # We keep track of the KEYs for the equipmods.
                if ( exists $line_ref->{'KEY'} ) {

                        # The KEY tag should only have one value and there should always be only
                        # one KEY tag by EQUIPMOD line.

                        # We extract the key name
                        my ($key) = ( $line_ref->{'KEY'}[0] =~ /KEY:(.*)/ );

                        if ($key) {
                           LstTidy::Validate::setEntityValid("EQUIPMOD Key", $key);
                        }
                        else {
                                $log->warning(
                                        qq(Could not parse the KEY in "$line_ref->{'KEY'}[0]"),
                                        $file_for_error,
                                        $line_for_error
                                );
                        }
                }
                else {
                        # [ 1368562 ] .FORGET / .MOD don\'t need KEY entries
                        my $report_tag = $line_ref->{$column_with_no_tag{'EQUIPMOD'}[0]}[0];
                        if ($report_tag =~ /.FORGET$|.MOD$/) {
                        }
                        else {
                                $log->info(
                                qq(No KEY tag found for "$report_tag"),
                                $file_for_error,
                                $line_for_error
                                );
                        }
                }
                if ( exists $line_ref->{'CHOOSE'} ) {               # [ 1870825 ] EqMod CHOOSE Changes
                        my $choose = $line_ref->{'CHOOSE'}[0];
                        my $eqmod_name = $line_ref->{'000ModifierName'}[0];
                        $eqmod_name =~ s/.MOD$//;
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
                                        $file_for_error,
                                        $line_for_error
                                        );
                                }
                        }
                        # Only CHOOSE:NOCHOICE is Valid
                        elsif ( $choose =~ /^CHOOSE:NOCHOICE/ ) {
                        }
                        # CHOOSE:STRING|Foo|Bar|Monkey|Poo|TITLE=these are choices
                        elsif ( $choose =~ /^CHOOSE:?(STRING)[^|]*/ ) {
                                # Test for TITLE= and warn if not present.
                                if ( $choose !~ /(TITLE[=])/ ) {
                                        $log->info(
                                        qq(TITLE= is missing in CHOOSE:STRING for "$choose"),
                                        $file_for_error,
                                        $line_for_error
                                        );
                                }
                        }
                        # CHOOSE:STATBONUS|statname|MIN=2|MAX=5|TITLE=Enhancement Bonus
                        # Statname is what I'd want to check to verify against the defined stats, but since it is optional....
                        elsif ( $choose =~ /^CHOOSE:?(STATBONUS)[^|]*/ ) {
#                               my $checkstat = $choose;
#                               $checkstat =~ s/(CHOOSE:STATBONUS)// ;
#                               $checkstat =~ s/[|]MIN=[-]?\d+\|MAX=\d+\|TITLE=.*//;
                        }
                        elsif ( $choose =~ /^CHOOSE:?(SKILLBONUS)[^|]*/ ) {
                        }
                        elsif ( $choose =~ /^CHOOSE:?(SKILL)[^|]*/ ) {
                                if ( $choose !~ /(TITLE[=])/ ) {
                                        $log->info(
                                        qq(TITLE= is missing in CHOOSE:SKILL for "$choose"),
                                        $file_for_error,
                                        $line_for_error
                                        );
                                }
                        }
                        elsif ( $choose =~ /^CHOOSE:?(EQBUILDER.SPELL)[^|]*/ ) {
                        }
                        elsif ( $choose =~ /^CHOOSE:?(EQBUILDER.EQTYPE)[^|]*/ ) {
                        }
                        # If not above, invaild CHOOSE for equipmod files.
                        else {
                                        $log->warning(
                                        qq(Invalid CHOOSE for Equipmod spells for "$choose"),
                                        $file_for_error,
                                        $line_for_error
                                        );
                        }
                }
        }
        elsif ( $linetype eq "CLASS" ) {

                # [ 876536 ] All spell casting classes need CASTERLEVEL
                #
                # If SPELLTYPE is present and BONUS:CASTERLEVEL is not present,
                # we warn the user.

                if ( exists $line_ref->{'SPELLTYPE'} && !exists $line_ref->{'BONUS:CASTERLEVEL'} ) {
                        $log->info(
                                qq{Missing BONUS:CASTERLEVEL for "$line_ref->{$column_with_no_tag{'CLASS'}[0]}[0]"},
                                $file_for_error,
                                $line_for_error
                        );
                }
        }
                elsif ( $linetype eq "CLASS" ) {

                # [ 876536 ] All spell casting classes need CASTERLEVEL
                #
                # If SPELLTYPE is present and BONUS:CASTERLEVEL is not present,
                # we warn the user.

                if ( exists $line_ref->{'FACT:SPELLTYPE'} && !exists $line_ref->{'BONUS:CASTERLEVEL'} ) {
                        $log->info(
                                qq{Missing BONUS:CASTERLEVEL for "$line_ref->{$column_with_no_tag{'CLASS'}[0]}[0]"},
                                $file_for_error,
                                $line_for_error
                        );
                }
        }

        elsif ( $linetype eq 'SKILL' ) {

                # We must identify the skills that have sub-entity e.g. Speak Language (Infernal)

                if ( exists $line_ref->{'CHOOSE'} ) {

                        # The CHOSE type tells us the type of sub-entities
                        my $choose      = $line_ref->{'CHOOSE'}[0];
                        my $skill_name = $line_ref->{'000SkillName'}[0];
                        $skill_name =~ s/.MOD$//;

                        if ( $choose =~ /^CHOOSE:(?:NUMCHOICES=\d+\|)?Language/ ) {
                                $valid_sub_entities{'SKILL'}{$skill_name} = 'LANGUAGE';
                        }
                }
        }
}

###############################################################
# additionnal_line_parsing
# ------------------------
#
# This function does additional parsing on each line once
# they have been seperated in tags.
#
# Most commun use is for addition, conversion or removal of tags.
#
# Paramter: $line_ref         Ref to a hash containing the tags of the line
#           $filetype         Type for the current file
#           $file_for_error   Name of the current file
#           $line_for_error   Number of the current line
#           $line_info        (Optional) structure generated by FILETYPE_parse
#

BEGIN {

        my $class_name = "";

        sub additionnal_line_parsing {
                my ( $line_ref, $filetype, $file_for_error, $line_for_error, $line_info ) = @_;

        ##################################################################
        # [ 1596310 ] xcheck: TYPE:Spellbook for equip w/ NUMPAGES and PAGEUSAGE
        # Gawaine42 (Richard)
        # Check to see if the TYPE contains Spellbook, if so, warn if
        # NUMUSES or PAGEUSAGE aren't there.
        # Then check to see if NUMPAGES or PAGEUSAGE are there, and if they
        # are there, but the TYPE doesn't contain Spellbook, warn.

        if ($filetype eq 'EQUIPMENT') {
                if (exists $line_ref->{'TYPE'}
                && $line_ref->{'TYPE'}[0] =~ /Spellbook/)
                {
                if (exists $line_ref->{'NUMPAGES'}
                        && exists $line_ref->{'PAGEUSAGE'}) {
                        #Nothing to see here, move along.
                }
                else {
                        $log->info(
                        qq{You have a Spellbook defined without providing NUMPAGES or PAGEUSAGE. If you want a spellbook of finite capacity, consider adding these tags.},
                        $file_for_error,
                        $line_for_error
                        );
                }
                }
                else {

                if (exists $line_ref->{'NUMPAGES'} )
                {
                        $log->warning(
                        qq{Invalid use of NUMPAGES tag in a non-spellbook. Remove this tag, or correct the TYPE.},
                        $file_for_error,
                        $line_for_error
                        );
                }
                if  (exists $line_ref->{'PAGEUSAGE'})
                {
                        $log->warning(
                        qq{Invalid use of PAGEUSAGE tag in a non-spellbook. Remove this tag, or correct the TYPE.},
                        $file_for_error,
                        $line_for_error
                        );
                }
                }
        #################################################################
        #  Do the same for Type Container with and without CONTAINS
                if (exists $line_ref->{'TYPE'}
                && $line_ref->{'TYPE'}[0] =~ /Container/)
                {
                if (exists $line_ref->{'CONTAINS'}) {
#                       $line_ref =~ s/'CONTAINS:-1'/'CONTAINS:UNLIM'/g;   # [ 1777282 ] CONTAINS Unlimited Weight is UNLIM, not -1
                }
                else {
                        $log->warning(
                        qq{Any object with TYPE:Container must also have a CONTAINS tag to be activated.},
                        $file_for_error,
                        $line_for_error
                        );
                }
                }
                elsif (exists $line_ref->{'CONTAINS'})
                {
                $log->warning(
                        qq{Any object with CONTAINS must also be TYPE:Container for the CONTAINS tag to be activated.},
                        $file_for_error,
                        $line_for_error
                        );
                }

   }

        ##################################################################
        # [ 1864711 ] Convert ADD:SA to ADD:SAB
        #
        # In most files, take ADD:SA and replace with ADD:SAB

        if (   LstTidy::Options::isConversionActive('ALL:Convert ADD:SA to ADD:SAB')
                && exists $line_ref->{'ADD:SA'}
        ) {
                $log->warning(
                        qq{Change ADD:SA for ADD:SAB in "$line_ref->{'ADD:SA'}[0]"},
                        $file_for_error,
                        $line_for_error
                );
                my $satag;
                $satag = $line_ref->{'ADD:SA'}[0];
                $satag =~ s/ADD:SA/ADD:SAB/;
                $line_ref->{'ADD:SAB'}[0] = $satag;
                delete $line_ref->{'ADD:SA'};
        }



        ##################################################################
        # [ 1514765 ] Conversion to remove old defaultmonster tags
        # Gawaine42 (Richard Bowers)
        # Bonuses associated with a PREDEFAULTMONSTER:Y need to be removed
        # This should remove the whole tag.
        if (LstTidy::Options::isConversionActive('RACE:Fix PREDEFAULTMONSTER bonuses')
                        && $filetype eq "RACE"
        ) {
        for my $key ( keys %$line_ref ) {
                my $ary = $line_ref->{$key};
                my $iCount = 0;
                foreach (@$ary) {
                my $ttag = $$ary[$iCount];
                if ($ttag =~ /PREDEFAULTMONSTER:Y/) {
                        $$ary[$iCount] = "";
                        $log->warning(
                                qq{Removing "$ttag".},
                                $file_for_error,
                                $line_for_error
                                );
                }
                $iCount++;
                }
        }
        }



        ##################################################################
        # [ 1615457 ] Replace ALTCRITICAL with ALTCRITMULT'
        #
        # In EQUIPMENT files, take ALTCRITICAL and replace with ALTCRITMULT'

        if (   LstTidy::Options::isConversionActive('EQUIP: ALTCRITICAL to ALTCRITMULT')
                && $filetype eq "EQUIPMENT"
                && exists $line_ref->{'ALTCRITICAL'}
        ) {
        # Throw warning if both ALTCRITICAL and ALTCRITMULT are on the same line,
        #   then remove ALTCRITICAL.
        if ( exists $line_ref->{ALTCRITMULT} ) {
                $log->warning(
                        qq{Removing ALTCRITICAL, ALTCRITMULT already present on same line.},
                        $file_for_error,
                        $line_for_error
                );
                delete $line_ref->{'ALTCRITICAL'};
        } else {
                $log->warning(
                        qq{Change ALTCRITICAL for ALTCRITMULT in "$line_ref->{'ALTCRITICAL'}[0]"},
                        $file_for_error,
                        $line_for_error
                );
                my $ttag;
                $ttag = $line_ref->{'ALTCRITICAL'}[0];
                $ttag =~ s/ALTCRITICAL/ALTCRITMULT/;
                $line_ref->{'ALTCRITMULT'}[0] = $ttag;
                delete $line_ref->{'ALTCRITICAL'};
                }
        }


        ##################################################################
        # [ 1514765 ] Conversion to remove old defaultmonster tags
        #
        # In RACE files, remove all MFEAT and HITDICE tags, but only if
        # there is a MONSTERCLASS present.

        # We remove MFEAT or warn of missing MONSTERCLASS tag.
        if (   LstTidy::Options::isConversionActive('RACE:Remove MFEAT and HITDICE')
                && $filetype eq "RACE"
                && exists $line_ref->{'MFEAT'}
                ) { if ( exists $line_ref->{'MONSTERCLASS'}
                        ) { for my $tag ( @{ $line_ref->{'MFEAT'} } ) {
                                $log->warning(
                                qq{Removing "$tag".},
                                $file_for_error,
                                $line_for_error
                                );
                        }
                        delete $line_ref->{'MFEAT'};
                        }
                else {$log->warning(
                        qq{MONSTERCLASS missing on same line as MFEAT, need to look at by hand.},
                                $file_for_error,
                                $line_for_error
                                );
                        }
        }

        # We remove HITDICE or warn of missing MONSTERCLASS tag.
        if (   LstTidy::Options::isConversionActive('RACE:Remove MFEAT and HITDICE')
                && $filetype eq "RACE"
                && exists $line_ref->{'HITDICE'}
                ) { if ( exists $line_ref->{'MONSTERCLASS'}
                        ) { for my $tag ( @{ $line_ref->{'HITDICE'} } ) {
                                $log->warning(
                                qq{Removing "$tag".},
                                $file_for_error,
                                $line_for_error
                                );
                        }
                        delete $line_ref->{'HITDICE'};
                        }
                else {$log->warning(
                        qq{MONSTERCLASS missing on same line as HITDICE, need to look at by hand.},
                                $file_for_error,
                                $line_for_error
                                );
                        }
                }

        #######################################################
        ## [ 1689538 ] Conversion: Deprecation of FOLLOWERALIGN
        ## Gawaine42
        ## Note: Makes simplifying assumption that FOLLOWERALIGN
        ## will occur only once in a given line, although DOMAINS may
        ## occur multiple times.
        if ((LstTidy::Options::isConversionActive('DEITY:Followeralign conversion'))
                && $filetype eq "DEITY"
                && (exists $line_ref->{'FOLLOWERALIGN'}))
        {
                my $followeralign = $line_ref->{'FOLLOWERALIGN'}[0];
                $followeralign =~ s/^FOLLOWERALIGN://;
                my $newprealign = "";
                my $aligncount = 0;

                for my $align (split //, $followeralign) {
                        # Is it a number?
                        my $number;
                        if ( (($number) = ($align =~ / \A (\d+) \z /xms))
                        && $number >= 0
                        && $number < scalar @valid_system_alignments)
                {
                                my $newalign = $valid_system_alignments[$number];
                        if ($aligncount > 0) {
                        $newprealign .= ',';
                        }
                        $aligncount++;
                        $newprealign .= "$newalign";
                        }
                else {
                                $log->notice(
                                qq{Invalid value "$align" for tag "$line_ref->{'FOLLOWERALIGN'}[0]"},
                                $file_for_error,
                                $line_for_error
                                );

                }
                }
                my $dom_count=0;

                if (exists $line_ref->{'DOMAINS'}) {
                for my $line ($line_ref->{'DOMAINS'})
                {
                        $line_ref->{'DOMAINS'}[$dom_count] .= "|PREALIGN:$newprealign";
                        $dom_count++;
                }
                $log->notice(
                                qq{Adding PREALIGN to domain information and removing "$line_ref->{'FOLLOWERALIGN'}[0]"},
                                $file_for_error,
                                $line_for_error
                                );

                delete $line_ref->{'FOLLOWERALIGN'};
                }
        }

                ##################################################################
                # [ 1353255 ] TYPE to RACETYPE conversion
                #
                # Checking race files for TYPE and if no RACETYPE,
                # convert TYPE to RACETYPE.
                # if Race file has no TYPE or RACETYPE, report as 'Info'

                # Do this check no matter what - valid any time
                if ( $filetype eq "RACE"
                && not ( exists $line_ref->{'RACETYPE'} )
                && not ( exists $line_ref->{'TYPE'}  )
                ) {
                # .MOD / .FORGET / .COPY don't need RACETYPE or TYPE'
                my $race_name = $line_ref->{'000RaceName'}[0];
                if ($race_name =~ /\.(FORGET|MOD|COPY=.+)$/) {
                } else { $log->warning(
                        qq{Race entry missing both TYPE and RACETYPE.},
                        $file_for_error,
                        $line_for_error
                        );
                }
                };

                if (   LstTidy::Options::isConversionActive('RACE:TYPE to RACETYPE')
                && ( $filetype eq "RACE"
                        || $filetype eq "TEMPLATE" )
                && not (exists $line_ref->{'RACETYPE'})
                && exists $line_ref->{'TYPE'}
                ) { $log->warning(
                        qq{Changing TYPE for RACETYPE in "$line_ref->{'TYPE'}[0]".},
                        $file_for_error,
                        $line_for_error
                        );
                        $line_ref->{'RACETYPE'} = [ "RACE" . $line_ref->{'TYPE'}[0] ];
                        delete $line_ref->{'TYPE'};
                };

#                       $line_ref->{'MONCSKILL'} = [ "MON" . $line_ref->{'CSKILL'}[0] ];
#                       delete $line_ref->{'CSKILL'};


                ##################################################################
                # [ 1444527 ] New SOURCE tag format
                #
                # The SOURCELONG tags found on any linetype but the SOURCE line type must
                # be converted to use tab if | are found.

                if (   LstTidy::Options::isConversionActive('ALL:New SOURCExxx tag format')
                && exists $line_ref->{'SOURCELONG'} ) {
                my @new_tags;

                for my $tag ( @{ $line_ref->{'SOURCELONG'} } ) {
                        if( $tag =~ / [|] /xms ) {
                                push @new_tags, split '\|', $tag;
                                $log->warning(
                                qq{Spliting "$tag"},
                                $file_for_error,
                                $line_for_error
                                );
                        }
                }

                if( @new_tags ) {
                        delete $line_ref->{'SOURCELONG'};

                        for my $new_tag (@new_tags) {
                                my ($tag_name) = ( $new_tag =~ / ( [^:]* ) [:] /xms );
                                push @{ $line_ref->{$tag_name} }, $new_tag;
                        }
                }
                }

                ##################################################################
                # [ 1070084 ] Convert SPELL to SPELLS
                #
                # Convert the old SPELL tags to the new SPELLS format.
                #
                # Old SPELL:<spellname>|<nb per day>|<spellbook>|...|PRExxx|PRExxx|...
                # New SPELLS:<spellbook>|TIMES=<nb per day>|<spellname>|<spellname>|PRExxx...

                if ( LstTidy::Options::isConversionActive('ALL:Convert SPELL to SPELLS')
                && exists $line_ref->{'SPELL'} )
                {
                my %spellbooks;

                # We parse all the existing SPELL tags
                for my $tag ( @{ $line_ref->{'SPELL'} } ) {
                        my ( $tag_name, $tag_value ) = ( $tag =~ /^([^:]*):(.*)/ );
                        my @elements = split '\|', $tag_value;
                        my @pretags;

                        while ( $elements[ +@elements - 1 ] =~ /^!?PRE\w*:/ ) {

                                # We keep the PRE tags separated
                                unshift @pretags, pop @elements;
                        }

                        # We classify each triple <spellname>|<nb per day>|<spellbook>
                        while (@elements) {
                                if ( +@elements < 3 ) {
                                $log->warning(
                                        qq(Wrong number of elements for "$tag_name:$tag_value"),
                                        $file_for_error,
                                        $line_for_error
                                );
                                }

                                my $spellname = shift @elements;
                                my $times       = +@elements ? shift @elements : 99999;
                                my $pretags   = join '|', @pretags;
                                $pretags = "NONE" unless $pretags;
                                my $spellbook = +@elements ? shift @elements : "MISSING SPELLBOOK";

                                push @{ $spellbooks{$spellbook}{$times}{$pretags} }, $spellname;
                        }

                        $log->warning(
                                qq{Removing "$tag_name:$tag_value"},
                                $file_for_error,
                                $line_for_error
                        );
                }

                # We delete the SPELL tags
                delete $line_ref->{'SPELL'};

                # We add the new SPELLS tags
                for my $spellbook ( sort keys %spellbooks ) {
                        for my $times ( sort keys %{ $spellbooks{$spellbook} } ) {
                                for my $pretags ( sort keys %{ $spellbooks{$spellbook}{$times} } ) {
                                my $spells = "SPELLS:$spellbook|TIMES=$times";

                                for my $spellname ( sort @{ $spellbooks{$spellbook}{$times}{$pretags} } ) {
                                        $spells .= "|$spellname";
                                }

                                $spells .= "|$pretags" unless $pretags eq "NONE";

                                $log->warning( qq{Adding   "$spells"}, $file_for_error, $line_for_error );

                                push @{ $line_ref->{'SPELLS'} }, $spells;
                                }
                        }
                }
                }

                ##################################################################
                # We get rid of all the PREALIGN tags.
                #
                # This is needed by my good CMP friends.

                if ( LstTidy::Options::isConversionActive('ALL:CMP remove PREALIGN') ) {
                if ( exists $line_ref->{'PREALIGN'} ) {
                        my $number = +@{ $line_ref->{'PREALIGN'} };
                        delete $line_ref->{'PREALIGN'};
                        $log->warning(
                                qq{Removing $number PREALIGN tags},
                                $file_for_error,
                                $line_for_error
                        );
                }

                if ( exists $line_ref->{'!PREALIGN'} ) {
                        my $number = +@{ $line_ref->{'!PREALIGN'} };
                        delete $line_ref->{'!PREALIGN'};
                        $log->warning(
                                qq{Removing $number !PREALIGN tags},
                                $file_for_error,
                                $line_for_error
                        );
                }
                }

                ##################################################################
                # Need to fix the STR bonus when the monster have only one
                # Natural Attack (STR bonus is then 1.5 * STR).
                # We add it if there is only one Melee attack and the
                # bonus is not already present.

                if ( LstTidy::Options::isConversionActive('ALL:CMP NatAttack fix')
                && exists $line_ref->{'NATURALATTACKS'} )
                {

                # First we verify if if there is only one melee attack.
                if ( @{ $line_ref->{'NATURALATTACKS'} } == 1 ) {
                        my @NatAttacks = split '\|', $line_ref->{'NATURALATTACKS'}[0];
                        if ( @NatAttacks == 1 ) {
                                my ( $NatAttackName, $Types, $NbAttacks, $Damage ) = split ',', $NatAttacks[0];
                                if ( $NbAttacks eq '*1' && $Damage ) {

                                # Now, at last, we know there is only one Natural Attack
                                # Is it a Melee attack?
                                my @Types       = split '\.', $Types;
                                my $IsMelee  = 0;
                                my $IsRanged = 0;
                                for my $type (@Types) {
                                        $IsMelee  = 1 if uc($type) eq 'MELEE';
                                        $IsRanged = 1 if uc($type) eq 'RANGED';
                                }

                                if ( $IsMelee && !$IsRanged ) {

                                        # We have a winner!!!
                                        ($NatAttackName) = ( $NatAttackName =~ /:(.*)/ );

                                        # Well, maybe the BONUS:WEAPONPROF is already there.
                                        if ( exists $line_ref->{'BONUS:WEAPONPROF'} ) {
                                                my $AlreadyThere = 0;
                                                FIND_BONUS:
                                                for my $bonus ( @{ $line_ref->{'BONUS:WEAPONPROF'} } ) {
                                                if ( $bonus eq "BONUS:WEAPONPROF=$NatAttackName|DAMAGE|STR/2" )
                                                {
                                                        $AlreadyThere = 1;
                                                        last FIND_BONUS;
                                                }
                                                }

                                                unless ($AlreadyThere) {
                                                push @{ $line_ref->{'BONUS:WEAPONPROF'} },
                                                        "BONUS:WEAPONPROF=$NatAttackName|DAMAGE|STR/2";
                                                $log->warning(
                                                        qq{Added "$line_ref->{'BONUS:WEAPONPROF'}[0]"}
                                                                . qq{ to go with "$line_ref->{'NATURALATTACKS'}[0]"},
                                                        $file_for_error,
                                                        $line_for_error
                                                );
                                                }
                                        }
                                        else {
                                                $line_ref->{'BONUS:WEAPONPROF'}
                                                = ["BONUS:WEAPONPROF=$NatAttackName|DAMAGE|STR/2"];
                                                $log->warning(
                                                qq{Added "$line_ref->{'BONUS:WEAPONPROF'}[0]"}
                                                        . qq{to go with "$line_ref->{'NATURALATTACKS'}[0]"},
                                                $file_for_error,
                                                $line_for_error
                                                );
                                        }
                                }
                                elsif ( $IsMelee && $IsRanged ) {
                                        $log->warning(
                                                qq{This natural attack is both Melee and Ranged}
                                                . qq{"$line_ref->{'NATURALATTACKS'}[0]"},
                                                $file_for_error,
                                                $line_for_error
                                        );
                                }
                                }
                        }
                }
                }

                ##################################################################
                # [ 865826 ] Remove the deprecated MOVE tag in EQUIPMENT files
                # No conversion needed. We just have to remove the MOVE tags that
                # are doing nothing anyway.

                if (   LstTidy::Options::isConversionActive('EQUIP:no more MOVE')
                && $filetype eq "EQUIPMENT"
                && exists $line_ref->{'MOVE'} )
                {
                $log->warning( qq{Removed MOVE tags}, $file_for_error, $line_for_error );
                delete $line_ref->{'MOVE'};
                }

                if (   LstTidy::Options::isConversionActive('CLASS:no more HASSPELLFORMULA')
                && $filetype eq "CLASS"
                && exists $line_ref->{'HASSPELLFORMULA'} )
                {
                $log->warning( qq{Removed deprecated HASSPELLFORMULA tags}, $file_for_error, $line_for_error );
                delete $line_ref->{'HASSPELLFORMULA'};
                }


                ##################################################################
                # Every RACE that has a Climb or a Swim MOVE must have a
                # BONUS:SKILL|Climb|8|TYPE=Racial. If there is a
                # BONUS:SKILLRANK|Swim|8|PREDEFAULTMONSTER:Y present, it must be
                # removed or lowered by 8.

                if (   LstTidy::Options::isConversionActive('RACE:BONUS SKILL Climb and Swim')
                && $filetype eq "RACE"
                && exists $line_ref->{'MOVE'} )
                {
                my $swim  = $line_ref->{'MOVE'}[0] =~ /swim/i;
                my $climb = $line_ref->{'MOVE'}[0] =~ /climb/i;

                if ( $swim || $climb ) {
                        my $need_swim  = 1;
                        my $need_climb = 1;

                        # Is there already a BONUS:SKILL|Swim of at least 8 rank?
                        if ( exists $line_ref->{'BONUS:SKILL'} ) {
                                for my $skill ( @{ $line_ref->{'BONUS:SKILL'} } ) {
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
                                                $file_for_error,
                                                $line_for_error
                                                );
                                        }

                                        if ( $need_climb && $skill_rank == 8 ) {
                                                $skill_list
                                                = join( ',', sort( split ( ',', $skill_list ), 'Climb' ) );
                                                $skill = "BONUS:SKILL|$skill_list|8|TYPE=Racial";
                                                $log->warning(
                                                qq{Added Climb to "$skill"},
                                                $file_for_error,
                                                $line_for_error
                                                );
                                        }

                                        if ( ( $need_climb || $need_swim ) && $skill_rank != 8 ) {
                                                $log->info(
                                                qq{You\'ll have to deal with this one yourself "$skill"},
                                                $file_for_error,
                                                $line_for_error
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
                        if ( exists $line_ref->{'BONUS:SKILLRANK'} ) {
                                for ( my $index = 0; $index < @{ $line_ref->{'BONUS:SKILLRANK'} }; $index++ ) {
                                my $skillrank = $line_ref->{'BONUS:SKILLRANK'}[$index];

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
                                                                $file_for_error,
                                                                $line_for_error
                                                        );
                                                }
                                                else {
                                                        $log->warning(
                                                                qq{Removing "$skillrank"},
                                                                $file_for_error,
                                                                $line_for_error
                                                        );
                                                        delete $line_ref->{'BONUS:SKILLRANK'}[$index];
                                                        $index--;
                                                }
                                                }
                                                else {
                                                $log->info(
                                                        qq{You\'ll have to deal with this one yourself "$skillrank"},
                                                        $file_for_error,
                                                        $line_for_error
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
                                                                $file_for_error,
                                                                $line_for_error
                                                        );
                                                }
                                                else {
                                                        $log->warning(
                                                                qq{Removing "$skillrank"},
                                                                $file_for_error,
                                                                $line_for_error
                                                        );
                                                        delete $line_ref->{'BONUS:SKILLRANK'}[$index];
                                                        $index--;
                                                }
                                                }
                                                else {
                                                $log->info(
                                                        qq{You\'ll have to deal with this one yourself "$skillrank"},
                                                        $file_for_error,
                                                        $line_for_error
                                                );
                                                }
                                        }
                                }
                                }

                                # If there are no more BONUS:SKILLRANK, we remove the tag entry
                                delete $line_ref->{'BONUS:SKILLRANK'}
                                unless @{ $line_ref->{'BONUS:SKILLRANK'} };
                        }
                }
                }

                ##################################################################
                # [ 845853 ] SIZE is no longer valid in the weaponprof files
                #
                # The SIZE tag must be removed from all WEAPONPROF files since it
                # cause loading problems with the latest versio of PCGEN.

                if (   LstTidy::Options::isConversionActive('WEAPONPROF:No more SIZE')
                && $filetype eq "WEAPONPROF"
                && exists $line_ref->{'SIZE'} )
                {
                   my $tagLookup = @{LstTidy::Reformat::getLineTypeOrder('WEAPONPROF')}[0];

                   $log->warning(
                      qq{Removing the SIZE tag in line "$line_ref->{$tagLookup}[0]"},
                      $file_for_error,
                      $line_for_error
                   );
                   delete $line_ref->{'SIZE'};
                }

                ##################################################################
                # [ 832164 ] Adding NoProfReq to AUTO:WEAPONPROF for most races
                #
                # NoProfReq must be added to AUTO:WEAPONPROF if the race has
                # at least one hand and if NoProfReq is not already there.

                if (   LstTidy::Options::isConversionActive('RACE:NoProfReq')
                && $filetype eq "RACE" )
                {
                my $needNoProfReq = 1;

                # Is NoProfReq already present?
                if ( exists $line_ref->{'AUTO:WEAPONPROF'} ) {
                        $needNoProfReq = 0 if $line_ref->{'AUTO:WEAPONPROF'}[0] =~ /NoProfReq/;
                }

                my $nbHands = 2;        # Default when no HANDS tag is present

                # How many hands?
                if ( exists $line_ref->{'HANDS'} ) {
                        if ( $line_ref->{'HANDS'}[0] =~ /HANDS:(\d+)/ ) {
                                $nbHands = $1;
                        }
                        else {
                                $log->info(
                                        qq(Invalid value in tag "$line_ref->{'HANDS'}[0]"),
                                        $file_for_error,
                                        $line_for_error
                                );
                                $needNoProfReq = 0;
                        }
                }

                if ( $needNoProfReq && $nbHands ) {
                        if ( exists $line_ref->{'AUTO:WEAPONPROF'} ) {
                                $log->warning(
                                qq{Adding "TYPE=NoProfReq" to tag "$line_ref->{'AUTO:WEAPONPROF'}[0]"},
                                $file_for_error,
                                $line_for_error
                                );
                                $line_ref->{'AUTO:WEAPONPROF'}[0] .= "|TYPE=NoProfReq";
                        }
                        else {
                                $line_ref->{'AUTO:WEAPONPROF'} = ["AUTO:WEAPONPROF|TYPE=NoProfReq"];
                                $log->warning(
                                qq{Creating new tag "AUTO:WEAPONPROF|TYPE=NoProfReq"},
                                $file_for_error,
                                $line_for_error
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

                if (   LstTidy::Options::isConversionActive('RACE:CSKILL to MONCSKILL')
                && $filetype eq "RACE"
                && exists $line_ref->{'CSKILL'}
                && exists $line_ref->{'MONSTERCLASS'}
                && !exists $line_ref->{'MONCSKILL'} )
                {
                $log->warning(
                        qq{Change CSKILL for MONSKILL in "$line_ref->{'CSKILL'}[0]"},
                        $file_for_error,
                        $line_for_error
                );

                $line_ref->{'MONCSKILL'} = [ "MON" . $line_ref->{'CSKILL'}[0] ];
                delete $line_ref->{'CSKILL'};
                }

                ##################################################################
                # [ 728038 ] BONUS:VISION must replace VISION:.ADD
                #
                # VISION:.ADD must be converted to BONUS:VISION
                # Some exemple of VISION:.ADD tags:
                #   VISION:.ADD,Darkvision (60')
                #   VISION:1,Darkvision (60')
                #   VISION:.ADD,See Invisibility (120'),See Etheral (120'),Darkvision (120')

                if (   LstTidy::Options::isConversionActive('ALL: , to | in VISION')
                && exists $line_ref->{'VISION'}
                && $line_ref->{'VISION'}[0] =~ /(\.ADD,|1,)(.*)/i )
                {
                $log->warning(
                        qq{Removing "$line_ref->{'VISION'}[0]"},
                        $file_for_error,
                        $line_for_error
                );

                my $newvision = "VISION:";
                my $coma;

                for my $vision_bonus ( split ',', $2 ) {
                        if ( $vision_bonus =~ /(\w+)\s*\((\d+)\'\)/ ) {
                                my ( $type, $bonus ) = ( $1, $2 );
                                push @{ $line_ref->{'BONUS:VISION'} }, "BONUS:VISION|$type|$bonus";
                                $log->warning(
                                qq{Adding "BONUS:VISION|$type|$bonus"},
                                $file_for_error,
                                $line_for_error
                                );
                                $newvision .= "$coma$type (0')";
                                $coma = ',';
                        }
                        else {
                                $log->error(
                                qq(Do not know how to convert "VISION:.ADD,$vision_bonus"),
                                $file_for_error,
                                $line_for_error
                                );
                        }
                }

                $log->warning( qq{Adding "$newvision"}, $file_for_error, $line_for_error );

                $line_ref->{'VISION'} = [$newvision];
                }

                ##################################################################
                #
                #
                # For items with TYPE:Boot, Glove, Bracer, we must check for plural
                # form and add a SLOTS:2 tag is the item is plural.

                if (   LstTidy::Options::isConversionActive('EQUIPMENT: SLOTS:2 for plurals')
                && $filetype            eq 'EQUIPMENT'
                && $line_info->[0] eq 'EQUIPMENT'
                && !exists $line_ref->{'SLOTS'} )
                {
                   my $tagLookup = @{LstTidy::Reformat::getLineTypeOrder('EQUIPMENT')}[0];
                   my $equipment_name = $line_ref->{ $tagLookup }[0];

                if ( exists $line_ref->{'TYPE'} ) {
                        my $type = $line_ref->{'TYPE'}[0];
                        if ( $type =~ /(Boot|Glove|Bracer)/ ) {
                                if (   $1 eq 'Boot' && $equipment_name =~ /boots|sandals/i
                                || $1 eq 'Glove'  && $equipment_name =~ /gloves|gauntlets|straps/i
                                || $1 eq 'Bracer' && $equipment_name =~ /bracers|bracelets/i )
                                {
                                $line_ref->{'SLOTS'} = ['SLOTS:2'];
                                $log->warning(
                                        qq{"SLOTS:2" added to "$equipment_name"},
                                        $file_for_error,
                                        $line_for_error
                                );
                                }
                                else {
                                $log->error( qq{"$equipment_name" is a $1}, $file_for_error, $line_for_error );
                                }
                        }
                }
                else {
                        $log->warning(
                                qq{$equipment_name has no TYPE.},
                                $file_for_error,
                                $line_for_error
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

                if ( LstTidy::Options::isConversionActive('EQUIPMENT: generate EQMOD') ) {
                if (   $filetype eq 'SPELL'
                        && $line_info->[0] eq 'SPELL'
                        && ( exists $line_ref->{'CLASSES'} ) )
                {
                        my $spell_name  = $line_ref->{'000SpellName'}[0];
                        my $spell_level = -1;

                        CLASS:
                        for ( split '\|', $line_ref->{'CLASSES'}[0] ) {
                                if ( index( $_, 'Wizard' ) != -1 || index( $_, 'Cleric' ) != -1 ) {
                                $spell_level = (/=(\d+)$/)[0];
                                last CLASS;
                                }
                        }

                        $Spells_For_EQMOD{$spell_name} = $spell_level
                                if $spell_level > -1;

                }
                elsif ($filetype eq 'EQUIPMENT'
                        && $line_info->[0] eq 'EQUIPMENT'
                        && ( !exists $line_ref->{'EQMOD'} ) )
                {
                        my $equip_name = $line_ref->{'000EquipmentName'}[0];
                        my $spell_name;

                        if ( $equip_name =~ m{^Wand \((.*)/(\d\d?)(st|rd|th) level caster\)} ) {
                                $spell_name = $1;
                                my $caster_level = $2;

                                if ( exists $Spells_For_EQMOD{$spell_name} ) {
                                my $spell_level = $Spells_For_EQMOD{$spell_name};
                                my $eqmod_tag   = "EQMOD:SE_50TRIGGER|SPELLNAME[$spell_name]"
                                        . "SPELLLEVEL[$spell_level]"
                                        . "CASTERLEVEL[$caster_level]CHARGES[50]";
                                $line_ref->{'EQMOD'}    = [$eqmod_tag];
                                $line_ref->{'BASEITEM'} = ['BASEITEM:Wand']
                                        unless exists $line_ref->{'BASEITEM'};
                                delete $line_ref->{'COST'} if exists $line_ref->{'COST'};
                                $log->warning(
                                        qq{$equip_name: removing "COST" and adding "$eqmod_tag"},
                                        $file_for_error,
                                        $line_for_error
                                );
                                }
                                else {
                                $log->warning(
                                        qq($equip_name: not enough information to add charges),
                                        $file_for_error,
                                        $line_for_error
                                );
                                }
                        }
                        elsif ( $equip_name =~ /^Wand \((.*)\)/ ) {
                                $spell_name = $1;
                                if ( exists $Spells_For_EQMOD{$spell_name} ) {
                                my $spell_level  = $Spells_For_EQMOD{$spell_name};
                                my $caster_level = $spell_level * 2 - 1;
                                my $eqmod_tag   = "EQMOD:SE_50TRIGGER|SPELLNAME[$spell_name]"
                                        . "SPELLLEVEL[$spell_level]"
                                        . "CASTERLEVEL[$caster_level]CHARGES[50]";
                                $line_ref->{'EQMOD'} = [$eqmod_tag];
                                delete $line_ref->{'COST'} if exists $line_ref->{'COST'};
                                $log->warning(
                                        qq{$equip_name: removing "COST" and adding "$eqmod_tag"},
                                        $file_for_error,
                                        $line_for_error
                                );
                                }
                                else {
                                $log->warning(
                                        qq{$equip_name: not enough information to add charges},
                                        $file_for_error,
                                        $line_for_error
                                );
                                }
                        }
                        elsif ( $equip_name =~ /^Wand/ ) {
                                $log->warning(
                                qq{$equip_name: not enough information to add charges},
                                $file_for_error,
                                $line_for_error
                                );
                        }
                }
                }

                ##################################################################
                # [ 663491 ] RACE: Convert AGE, HEIGHT and WEIGHT tags
                #
                # For each HEIGHT, WEIGHT or AGE tags found in a RACE file,
                # we must call record_bioset_tags to record the AGE, HEIGHT and
                # WEIGHT tags.

                if (   LstTidy::Options::isConversionActive('BIOSET:generate the new files')
                && $filetype            eq 'RACE'
                && $line_info->[0] eq 'RACE'
                && (   exists $line_ref->{'AGE'}
                        || exists $line_ref->{'HEIGHT'}
                        || exists $line_ref->{'WEIGHT'} )
                ) {
                my ( $tagLookup, $dir, $race, $age, $height, $weight );

                   $tagLookup = @{LstTidy::Reformat::getLineTypeOrder('RACE')}[0];
                   $dir       = File::Basename::dirname($file_for_error);
                   $race      = $line_ref->{ $tagLookup }[0];

                if ( $line_ref->{'AGE'} ) {
                        $age = $line_ref->{'AGE'}[0];
                        $log->warning( qq{Removing "$line_ref->{'AGE'}[0]"}, $file_for_error, $line_for_error );
                        delete $line_ref->{'AGE'};
                }
                if ( $line_ref->{'HEIGHT'} ) {
                        $height = $line_ref->{'HEIGHT'}[0];
                        $log->warning( qq{Removing "$line_ref->{'HEIGHT'}[0]"}, $file_for_error, $line_for_error );
                        delete $line_ref->{'HEIGHT'};
                }
                if ( $line_ref->{'WEIGHT'} ) {
                        $weight = $line_ref->{'WEIGHT'}[0];
                        $log->warning( qq{Removing "$line_ref->{'WEIGHT'}[0]"}, $file_for_error, $line_for_error );
                        delete $line_ref->{'WEIGHT'};
                }

                record_bioset_tags( $dir, $race, $age, $height, $weight, $file_for_error,
                        $line_for_error );
                }

                ##################################################################
                # [ 653596 ] Add a TYPE tag for all SPELLs
                # .

                if (   LstTidy::Options::isConversionActive('SPELL:Add TYPE tags')
                && exists $line_ref->{'SPELLTYPE'}
                && $filetype            eq 'CLASS'
                && $line_info->[0] eq 'CLASS'
                ) {

                # We must keep a list of all the SPELLTYPE for each class.
                # It is assumed that SPELLTYPE cannot be found more than once
                # for the same class. It is also assumed that SPELLTYPE has only
                # one value. SPELLTYPE:Any is ignored.

                   my $tagLookup = @{LstTidy::Reformat::getLineTypeOrder('CLASS')}[0];
                my $class_name = $line_ref->{ $tagLookup }[0];
                SPELLTYPE_TAG:
                for my $spelltype_tag ( values %{ $line_ref->{'SPELLTYPE'} } ) {
                        my $spelltype = "";
                        ($spelltype) = ($spelltype_tag =~ /SPELLTYPE:(.*)/);
                        next SPELLTYPE_TAG if $spelltype eq "" or uc($spelltype) eq "ANY";
                        $class_spelltypes{$class_name}{$spelltype}++;
                }
                }

                if (   LstTidy::Options::isConversionActive('SPELL:Add TYPE tags')
                && $filetype                    eq 'SPELL'
                && $line_info->{Linetype} eq 'SPELL' )
                {

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

                if (   LstTidy::Options::isConversionActive('SOURCE line replacement')
                && defined $line_info
                && $line_info->[0] eq 'SOURCE'
                && $source_curent_file ne $file_for_error )
                {

                my $inputpath =  getOption('inputpath');
                # Only the first SOURCE tag is replace.
                if ( exists $source_tags{ File::Basename::dirname($file_for_error) } ) {

                        # We replace the line with a concatanation of SOURCE tags found in
                        # the directory .PCC
                        my %line_tokens;
                        while ( my ( $tag, $value )
                                = each %{ $source_tags{ File::Basename::dirname($file_for_error) } } )
                        {
                                $line_tokens{$tag} = [$value];
                                $source_curent_file = $file_for_error;
                        }

                        $line_info->[1] = \%line_tokens;
                }
                elsif ( $file_for_error =~ / \A ${inputpath} /xmsi ) {
                        # We give this notice only if the curent file is under getOption('inputpath').
                        # If -basepath is used, there could be files loaded outside of the -inputpath
                        # without their PCC.
                        $log->notice( "No PCC source information found", $file_for_error, $line_for_error );
                }
                }

                # Extract lists
                # ====================
                # Export each file name and log them with the filename and the
                # line number

                if ( LstTidy::Options::isConversionActive('Export lists') ) {
                my $filename = $file_for_error;
                $filename =~ tr{/}{\\};

                if ( $filetype eq 'SPELL' ) {

                        # Get the spell name
                        my $spellname  = $line_ref->{'000SpellName'}[0];
                        my $sourcepage = "";
                        $sourcepage = $line_ref->{'SOURCEPAGE'}[0] if exists $line_ref->{'SOURCEPAGE'};

                        # Write to file
                        print { $filehandle_for{SPELL} }
                                qq{"$spellname","$sourcepage","$line_for_error","$filename"\n};
                }
                if ( $filetype eq 'CLASS' ) {
                        my $class = ( $line_ref->{'000ClassName'}[0] =~ /^CLASS:(.*)/ )[0];
                        print { $filehandle_for{CLASS} } qq{"$class","$line_for_error","$filename"\n}
                                if $class_name ne $class;
                        $class_name = $class;
                }

                if ( $filetype eq 'DEITY' ) {
                        print { $filehandle_for{DEITY} }
                                qq{"$line_ref->{'000DeityName'}[0]","$line_for_error","$filename"\n};
                }

                if ( $filetype eq 'DOMAIN' ) {
                        print { $filehandle_for{DOMAIN} }
                                qq{"$line_ref->{'000DomainName'}[0]","$line_for_error","$filename"\n};
                }

                if ( $filetype eq 'EQUIPMENT' ) {
                   my $tagLookup = @{LstTidy::Reformat::getLineTypeOrder($filetype)}[0];
                        my $equipname  = $line_ref->{ $tagLookup }[0];
                        my $outputname = "";
                        $outputname = substr( $line_ref->{'OUTPUTNAME'}[0], 11 )
                                if exists $line_ref->{'OUTPUTNAME'};
                        my $replacementname = $equipname;
                        if ( $outputname && $equipname =~ /\((.*)\)/ ) {
                                $replacementname = $1;
                        }
                        $outputname =~ s/\[NAME\]/$replacementname/;
                        print { $filehandle_for{EQUIPMENT} }
                                qq{"$equipname","$outputname","$line_for_error","$filename"\n};
                }

                if ( $filetype eq 'EQUIPMOD' ) {
                   my $tagLookup = @{LstTidy::Reformat::getLineTypeOrder($filetype)}[0];
                        my $equipmodname = $line_ref->{ $tagLookup }[0];
                        my ( $key, $type ) = ( "", "" );
                        $key  = substr( $line_ref->{'KEY'}[0],  4 ) if exists $line_ref->{'KEY'};
                        $type = substr( $line_ref->{'TYPE'}[0], 5 ) if exists $line_ref->{'TYPE'};
                        print { $filehandle_for{EQUIPMOD} }
                                qq{"$equipmodname","$key","$type","$line_for_error","$filename"\n};
                }

                if ( $filetype eq 'FEAT' ) {
                   my $tagLookup = @{LstTidy::Reformat::getLineTypeOrder($filetype)}[0];
                        my $featname = $line_ref->{ $tagLookup }[0];
                        print { $filehandle_for{FEAT} } qq{"$featname","$line_for_error","$filename"\n};
                }

                if ( $filetype eq 'KIT STARTPACK' ) {
                   my $tagLookup = @{LstTidy::Reformat::getLineTypeOrder($filetype)}[0];
                   my ($kitname) = ( $line_ref->{ $tagLookup }[0] =~ /\A STARTPACK: (.*) \z/xms );
                        print { $filehandle_for{KIT} } qq{"$kitname","$line_for_error","$filename"\n};
                }

                if ( $filetype eq 'KIT TABLE' ) {
                   my $tagLookup = @{LstTidy::Reformat::getLineTypeOrder($filetype)}[0];
                        my ($tablename)
                                = ( $line_ref->{ $tagLookup }[0] =~ /\A TABLE: (.*) \z/xms );
                        print { $filehandle_for{TABLE} } qq{"$tablename","$line_for_error","$filename"\n};
                }

                if ( $filetype eq 'LANGUAGE' ) {
                   my $tagLookup = @{LstTidy::Reformat::getLineTypeOrder($filetype)}[0];
                        my $languagename = $line_ref->{ $tagLookup }[0];
                        print { $filehandle_for{LANGUAGE} } qq{"$languagename","$line_for_error","$filename"\n};
                }

                if ( $filetype eq 'RACE' ) {
                   my $tagLookup = @{LstTidy::Reformat::getLineTypeOrder($filetype)}[0];
                        my $racename            = $line_ref->{ $tagLookup }[0];

                        my $race_type = q{};
                        $race_type = $line_ref->{'RACETYPE'}[0] if exists $line_ref->{'RACETYPE'};
                        $race_type =~ s{ \A RACETYPE: }{}xms;

                        my $race_sub_type = q{};
                        $race_sub_type = $line_ref->{'RACESUBTYPE'}[0] if exists $line_ref->{'RACESUBTYPE'};
                        $race_sub_type =~ s{ \A RACESUBTYPE: }{}xms;

                        print { $filehandle_for{RACE} }
                                qq{"$racename","$race_type","$race_sub_type","$line_for_error","$filename"\n};
                }

                if ( $filetype eq 'SKILL' ) {
                   my $tagLookup = @{LstTidy::Reformat::getLineTypeOrder($filetype)}[0];
                        my $skillname = $line_ref->{ $tagLookup }[0];
                        print { $filehandle_for{SKILL} } qq{"$skillname","$line_for_error","$filename"\n};
                }

                if ( $filetype eq 'TEMPLATE' ) {
                   my $tagLookup = @{LstTidy::Reformat::getLineTypeOrder($filetype)}[0];
                        my $template_name = $line_ref->{ $tagLookup }[0];
                        print { $filehandle_for{TEMPLATE} } qq{"$template_name","$line_for_error","$filename"\n};
                }
                }

                ############################################################
                ######################## Conversion ########################
                # We manipulate the tags for the line here

                if ( LstTidy::Options::isConversionActive('Generate BONUS and PRExxx report') ) {
                for my $tag_type ( sort keys %$line_ref ) {
                        if ( $tag_type =~ /^BONUS|^!?PRE/ ) {
                                $bonus_prexxx_tag_report{$filetype}{$_} = 1 for ( @{ $line_ref->{$tag_type} } );
                        }
                }
                }

                1;
        }

}       # End of BEGIN

###############################################################
# additionnal_file_parsing
# ------------------------
#
# This function does additional parsing on each file once
# they have been seperated in lines of tags.
#
# Most commun use is for addition, conversion or removal of tags.
#
# Paramter: $lines_ref  Ref to an array containing lines of tags
#               $filetype   Type for the current file
#               $filename   Name of the current file
#
#               The $line_ref entries may now be in a new format, we need to find out
#               before using it. ref($line_ref) eq 'ARRAY'means new format.
#
#               The format is: [ $curent_linetype,
#                                       \%line_tokens,
#                                       $last_main_line,
#                                       $curent_entity,
#                                       $line_info,
#                                       ];
#

{

        my %class_skill;
        my %class_spell;
        my %domain_spell;

        sub additionnal_file_parsing {
                my ( $lines_ref, $filetype, $filename ) = @_;

                ##################################################################
                # [ 779341 ] Spell Name.MOD to CLASS's SPELLLEVEL
                #

#  if(LstTidy::Options::isConversionActive('CLASS: SPELLLIST from Spell.MOD'))
#  {
#       if($filetype eq 'SPELL')
#       {
#       # All the Spell Name.MOD entries must be parsed to find the
#       # CLASSES and DOMAINS tags.
#       #
#       # The .MOD lines that have no other tags then CLASSES or DOMAINS
#       # will be removed entirely.
#
#       my ($directory,$spellfile) = File::Basename::dirname($filename);
#
#       for(my $i = 0; $i < @$lines_ref; $i++)
#       {
#               # Is this a .MOD line?
#               next unless ref($lines_ref->[$i]) eq 'ARRAY' &&
#                               $lines_ref->[$i][0] eq 'SPELL';
#
#               my $is_mod = $lines_ref->[$i][3] =~ /(.*)\.MOD$/;
#               my $spellname = $is_mod ? $1 : $lines_ref->[$i][3];
#
#               # Is there a CLASSES tag?
#               if(exists $lines_ref->[$i][1]{'CLASSES'})
#               {
#               my $tag = substr($lines_ref->[$i][1]{'CLASSES'}[0],8);
#
#               # We find each group of classes of the same level
#               for (split /\|/, $tag)
#               {
#               if(/(.*)=(\d+)$/)
#               {
#                       my $level = $2;
#                       my $classes = $1;
#
#                       for my $class (split /,/, $classes)
#                       {
#                       #push @{$class_spell{
#                       }
#               }
#               else
#               {
#                       ewarn( NOTICE,  qq(!! No level were given for "$_" found in "$lines_ref->[$i][1]{'CLASSES'}[0]"),
#                       $filename,$i );
#               }
#               }
#
##              ewarn( NOTICE,  qq(**** $spellname: $_),$filename,$i for @classes_by_level );
                #               }
                #
                #               if(exists $lines_ref->[$i][1]{'DOMAINS'})
                #               {
                #               my $tag = substr($lines_ref->[$i][1]{'DOMAINS'}[0],8);
                #               my @domains_by_level = split /\|/, $tag;
                #
                #               ewarn( NOTICE,  qq(**** $spellname: $_),$filename,$i for @domains_by_level );
                #               }
                #       }
                #       }
                #  }

                ###############################################################
                # Reformat multiple lines to one line for RACE and TEMPLATE.
                #
                # This is only useful for those who like to start new entries
                # with multiple lines (for clarity) and then want them formatted
                # properly for submission.

                if ( LstTidy::Options::isConversionActive('ALL:Multiple lines to one') ) {
                my %valid_line_type = (
                        'RACE'  => 1,
                        'TEMPLATE' => 1,
                );

                if ( exists $valid_line_type{$filetype} ) {
                        my $last_main_line = -1;

                        # Find all the lines with the same identifier
                        ENTITY:
                        for ( my $i = 0; $i < @{$lines_ref}; $i++ ) {

                                # Is this a linetype we are interested in?
                                if ( ref $lines_ref->[$i] eq 'ARRAY'
                                && exists $valid_line_type{ $lines_ref->[$i][0] } )
                                {
                                my $first_line = $i;
                                my $last_line  = $i;
                                my $old_length;
                                my $curent_linetype = $lines_ref->[$i][0];
                                my %new_line            = %{ $lines_ref->[$i][1] };
                                $last_main_line = $i;
                                my $entity_name  = $lines_ref->[$i][3];
                                my $line_info   = $lines_ref->[$i][4];
                                my $j           = $i + 1;
                                my $extra_entity = 0;
                                my @new_lines;

                                #Find all the line with the same entity name
                                ENTITY_LINE:
                                for ( ; $j < @{$lines_ref}; $j++ ) {

                                        # Skip empty and comment lines
                                        next ENTITY_LINE
                                                if ref( $lines_ref->[$j] ) ne 'ARRAY'
                                                || $lines_ref->[$j][0] eq 'HEADER'
                                                || ref( $lines_ref->[$j][1] ) ne 'HASH';

                                        # Is it an entity of the same name?
                                        if (   $lines_ref->[$j][0] eq $curent_linetype
                                                && $entity_name eq $lines_ref->[$j][3] )
                                        {
                                                $last_line = $j;
                                                $extra_entity++;
                                                for ( keys %{ $lines_ref->[$j][1] } ) {

                                                # We add the tags except for the first one (the entity tag)
                                                # that is already there.
                                                push @{ $new_line{$_} }, @{ $lines_ref->[$j][1]{$_} }
                                                        if $_ ne @{LstTidy::Reformat::getLineTypeOrder($curent_linetype)}[0];
                                                     }
                                        }
                                        else {
                                                last ENTITY_LINE;
                                        }
                                }

                                # If there was only one line for the entity, we do nothing
                                next ENTITY if !$extra_entity;

                                # Number of lines included in the CLASS
                                $old_length = $last_line - $first_line + 1;

                                # We prepare the replacement lines
                                $j = 0;

                                # The main line
                                if ( keys %new_line > 1 ) {
                                        push @new_lines,
                                                [
                                                $curent_linetype,
                                                \%new_line,
                                                $last_main_line,
                                                $entity_name,
                                                $line_info,
                                                ];
                                        $j++;
                                }

                                # We splice the new class lines in place
                                splice @$lines_ref, $first_line, $old_length, @new_lines;

                                # Continue with the rest
                                $i = $first_line + $j - 1;      # -1 because the $i++ happen right after
                                }
                                elsif (ref $lines_ref->[$i] eq 'ARRAY'
                                && $lines_ref->[$i][0] ne 'HEADER'
                                && defined $lines_ref->[$i][4]
                                && $lines_ref->[$i][4]{Mode} == SUB )
                                {

                                # We must replace the last_main_line with the correct value
                                $lines_ref->[$i][2] = $last_main_line;
                                }
                                elsif (ref $lines_ref->[$i] eq 'ARRAY'
                                && $lines_ref->[$i][0] ne 'HEADER'
                                && defined $lines_ref->[$i][4]
                                && $lines_ref->[$i][4]{Mode} == MAIN )
                                {

                                # We update the last_main_line value and
                                # put the correct value in the curent line
                                $lines_ref->[$i][2] = $last_main_line = $i;
                                }
                        }
                }
                }

                ###############################################################
                # [ 641912 ] Convert CLASSSPELL to SPELL
                #
                #
                # "CLASSSPELL"  => [
                #   'CLASS',
                #   'SOURCEPAGE',
                #   '#HEADER#SOURCE',
                #   '#HEADER#SOURCELONG',
                #   '#HEADER#SOURCESHORT',
                #   '#HEADER#SOURCEWEB',
                # ],
                #
                # "CLASSSPELL Level"    => [
                #   '000ClassSpellLevel',
                #   '001ClassSpells'

                if ( LstTidy::Options::isConversionActive('CLASSSPELL conversion to SPELL') ) {
                if ( $filetype eq 'CLASSSPELL' ) {

                        # Here we will put aside all the CLASSSPELL that
                        # we find for later use.

                        my $dir = File::Basename::dirname($filename);

                        $log->warning(
                                qq(Already found a CLASSSPELL file in $dir),
                                $filename
                        ) if exists $class_spell{$dir};

                        my $curent_name;
                        my $curent_type = 2;    # 0 = CLASS, 1 = DOMAIN, 2 = invalid
                        my $line_number = 1;

                        LINE:
                        for my $line (@$lines_ref) {

                                # We skip all the lines that do not begin by CLASS or a number
                                next LINE
                                if ref($line) ne 'HASH'
                                || ( !exists $line->{'CLASS'} && !exists $line->{'000ClassSpellLevel'} );

                                if ( exists $line->{'CLASS'} ) {

                                # We keep the name
                                $curent_name = ( $line->{'CLASS'}[0] =~ /CLASS:(.*)/ )[0];

                                # Is it a CLASS or a DOMAIN ?


                                if (LstTidy::Validate::isEntityValid('CLASS', $curent_name)) {
                                        $curent_type = 0;
                                }
                                elsif (LstTidy::Validate::isEntityValid('DOMAIN', $curent_name)) {
                                        $curent_type = 1;
                                }
                                else {
                                        $curent_type = 2;
                                        $log->warning(
                                                qq(Don\'t know if "$curent_name" is a CLASS or a DOMAIN),
                                                $filename,
                                                $line_number
                                        );
                                }
                                }
                                else {
                                next LINE if $curent_type == 2 || !exists $line->{'001ClassSpells'};

                                # We store the CLASS name and Level

                                for my $spellname ( split '\|', $line->{'001ClassSpells'}[0] ) {
                                        push @{ $class_spell{$dir}{$spellname}[$curent_type]
                                                { $line->{'000ClassSpellLevel'}[0] } }, $curent_name;

                                }
                                }
                        }
                        continue { $line_number++; }
                }
                elsif ( $filetype eq 'SPELL' ) {
                        my $dir = File::Basename::dirname($filename);

                        if ( exists $class_spell{$dir} ) {

                                # There was a CLASSSPELL in the directory, we need to add
                                # the CLASSES and DOMAINS tag for it.

                                # First we find all the SPELL lines and add the CLASSES
                                # and DOMAINS tags if needed
                                my $line_number = 1;
                                LINE:
                                for my $line (@$lines_ref) {
                                next LINE if ref($line) ne 'ARRAY' || $line->[0] ne 'SPELL';
                                $_ = $line->[1];

                                next LINE if ref ne 'HASH' || !exists $_->{'000SpellName'};
                                my $spellname = $_->{'000SpellName'}[0];

                                if ( exists $class_spell{$dir}{$spellname} ) {
                                        if ( defined $class_spell{$dir}{$spellname}[0] ) {

                                                # We have classes
                                                # Is there already a CLASSES tag?
                                                if ( exists $_->{'CLASSES'} ) {
                                                $log->warning(
                                                        qq(The is already a CLASSES tag for "$spellname"),
                                                        $filename,
                                                        $line_number
                                                );
                                                }
                                                else {
                                                my @new_levels;
                                                for my $level ( sort { $a <=> $b }
                                                        keys %{ $class_spell{$dir}{$spellname}[0] } )
                                                {
                                                        my $new_level = join ',',
                                                                @{ $class_spell{$dir}{$spellname}[0]{$level} };
                                                        push @new_levels, "$new_level=$level";
                                                }
                                                my $new_classes = 'CLASSES:' . join '|', @new_levels;
                                                $_->{'CLASSES'} = [$new_classes];

                                                $log->warning(
                                                        qq{SPELL $spellname: adding "$new_classes"},
                                                        $filename,
                                                        $line_number
                                                );
                                                }
                                        }

                                        if ( defined $class_spell{$dir}{$spellname}[1] ) {

                                                # We have domains
                                                # Is there already a CLASSES tag?
                                                if ( exists $_->{'DOMAINS'} ) {
                                                $log->warning(
                                                        qq(The is already a DOMAINS tag for "$spellname"),
                                                        $filename,
                                                        $line_number
                                                );
                                                }
                                                else {
                                                my @new_levels;
                                                for my $level ( sort { $a <=> $b }
                                                        keys %{ $class_spell{$dir}{$spellname}[1] } )
                                                {
                                                        my $new_level = join ',',
                                                                @{ $class_spell{$dir}{$spellname}[1]{$level} };
                                                        push @new_levels, "$new_level=$level";
                                                }
                                                my $new_domains = 'DOMAINS:' . join '|', @new_levels;
                                                $_->{'DOMAINS'} = [$new_domains];

                                                $log->warning(
                                                        qq{SPELL $spellname: adding "$new_domains"},
                                                        $filename,
                                                        $line_number
                                                );
                                                }
                                        }

                                        # We remove the curent spell from the list.
                                        delete $class_spell{$dir}{$spellname};
                                }
                                }
                                continue { $line_number++; }

                                # Second, we add .MOD line for the SPELL that were not present.
                                if ( keys %{ $class_spell{$dir} } ) {

                                # Put a comment line and a new header line
                                push @$lines_ref, "",
                                        "###Block:SPELL.MOD generated from the old CLASSSPELL files";

                                for my $spellname ( sort keys %{ $class_spell{$dir} } ) {
                                        my %newline = ( '000SpellName' => ["$spellname.MOD"] );
                                        $line_number++;

                                        if ( defined $class_spell{$dir}{$spellname}[0] ) {

                                                # New CLASSES
                                                my @new_levels;
                                                for my $level ( sort { $a <=> $b }
                                                keys %{ $class_spell{$dir}{$spellname}[0] } )
                                                {
                                                my $new_level = join ',',
                                                        @{ $class_spell{$dir}{$spellname}[0]{$level} };
                                                push @new_levels, "$new_level=$level";
                                                }
                                                my $new_classes = 'CLASSES:' . join '|', @new_levels;
                                                $newline{'CLASSES'} = [$new_classes];

                                                $log->warning(
                                                qq{SPELL $spellname.MOD: adding "$new_classes"},
                                                $filename,
                                                $line_number
                                                );
                                        }

                                        if ( defined $class_spell{$dir}{$spellname}[1] ) {

                                                # New DOMAINS
                                                my @new_levels;
                                                for my $level ( sort { $a <=> $b }
                                                keys %{ $class_spell{$dir}{$spellname}[1] } )
                                                {
                                                my $new_level = join ',',
                                                        @{ $class_spell{$dir}{$spellname}[1]{$level} };
                                                push @new_levels, "$new_level=$level";
                                                }

                                                my $new_domains = 'DOMAINS:' . join '|', @new_levels;
                                                $newline{'DOMAINS'} = [$new_domains];

                                                $log->warning(
                                                qq{SPELL $spellname.MOD: adding "$new_domains"},
                                                $filename,
                                                $line_number
                                                );
                                        }

                                        push @$lines_ref, [
                                                'SPELL',
                                                \%newline,
                                                1 + @$lines_ref,
                                                $spellname,
                                                LstTidy::Parse::getParseControl('SPELL'),
                                        ];

                                }
                                }
                        }
                }
                }

                ###############################################################
                # [ 626133 ] Convert CLASS lines into 4 lines
                #
                # The 3 lines are:
                #
                # General (all tags not put in the two other lines)
                # Prereq. (all the PRExxx tags)
                # Class skills (the STARTSKILLPTS, the CKSILL and the CCSKILL tags)
                #
                # 2003.07.11: a fourth line was added for the SPELL related tags

                if (   LstTidy::Options::isConversionActive('CLASS:Four lines')
                && $filetype eq 'CLASS' )
                {
                my $last_main_line = -1;

                # Find all the CLASS lines
                for ( my $i = 0; $i < @{$lines_ref}; $i++ ) {

                        # Is this a CLASS line?
                        if ( ref $lines_ref->[$i] eq 'ARRAY' && $lines_ref->[$i][0] eq 'CLASS' ) {
                                my $first_line = $i;
                                my $last_line  = $i;
                                my $old_length;
                                my %new_class_line = %{ $lines_ref->[$i][1] };
                                my %new_pre_line;
                                my %new_skill_line;
                                my %new_spell_line;
                                my %skill_tags = (
                                'CSKILL:.CLEAR' => 1,
                                CCSKILL         => 1,
                                CSKILL          => 1,
                                MODTOSKILLS             => 1,   #
                                MONSKILL                => 1,   # [ 1097487 ] MONSKILL in class.lst
                                MONNONSKILLHD   => 1,
                                SKILLLIST                       => 1,   # [ 1580059 ] SKILLLIST tag
                                STARTSKILLPTS   => 1,
                                );
                                my %spell_tags = (
                                BONUSSPELLSTAT                  => 1,
                                'BONUS:CASTERLEVEL'             => 1,
                                'BONUS:DC'                              => 1,  #[ 1037456 ] Move BONUS:DC on class line to the spellcasting portion
                                'BONUS:SCHOOL'                  => 1,
                                'BONUS:SPELL'                   => 1,
                                'BONUS:SPECIALTYSPELLKNOWN'     => 1,
                                'BONUS:SPELLCAST'                       => 1,
                                'BONUS:SPELLCASTMULT'           => 1,
                                'BONUS:SPELLKNOWN'              => 1,
                                CASTAS                          => 1,
                                ITEMCREATE                              => 1,
                                KNOWNSPELLS                             => 1,
                                KNOWNSPELLSFROMSPECIALTY        => 1,
                                MEMORIZE                                => 1,
                                HASSPELLFORMULA                 => 1, # [ 1893279 ] HASSPELLFORMULA Class Line tag
                                PROHIBITED                              => 1,
                                SPELLBOOK                               => 1,
                                SPELLKNOWN                              => 1,
                                SPELLLEVEL                              => 1,
                                SPELLLIST                               => 1,
                                SPELLSTAT                               => 1,
                                SPELLTYPE                               => 1,
                                );
                                $last_main_line = $i;
                                my $class               = $lines_ref->[$i][3];
                                my $line_info   = $lines_ref->[$i][4];
                                my $j                   = $i + 1;
                                my @new_class_lines;

                                #Find the next line that is not empty or of the same CLASS
                                CLASS_LINE:
                                for ( ; $j < @{$lines_ref}; $j++ ) {

                                # Skip empty and comment lines
                                next CLASS_LINE
                                        if ref( $lines_ref->[$j] ) ne 'ARRAY'
                                        || $lines_ref->[$j][0] eq 'HEADER'
                                        || ref( $lines_ref->[$j][1] ) ne 'HASH';

                                # Is it a CLASS line of the same CLASS?
                                if ( $lines_ref->[$j][0] eq 'CLASS' && $class eq $lines_ref->[$j][3] ) {
                                        $last_line = $j;
                                        for ( keys %{ $lines_ref->[$j][1] } ) {
                                                push @{ $new_class_line{$_} }, @{ $lines_ref->[$j][1]{$_} }
                                                if $_ ne @{LstTidy::Reformat::getLineTypeOrder('CLASS')}[0];
                                        }
                                }
                                else {
                                        last CLASS_LINE;
                                }
                                }

                                # Number of lines included in the CLASS
                                $old_length = $last_line - $first_line + 1;

                                # We build the two other lines.
                                for ( keys %new_class_line ) {

                                # Is it a SKILL tag?
                                if ( exists $skill_tags{$_} ) {
                                        $new_skill_line{$_} = delete $new_class_line{$_};
                                }

                                # Is it a PRExxx tag?
                                elsif (/^\!?PRE/
                                        || /^DEITY/ ) {
                                        $new_pre_line{$_} = delete $new_class_line{$_};
                                }

                                # Is it a SPELL tag?
                                elsif ( exists $spell_tags{$_} ) {
                                        $new_spell_line{$_} = delete $new_class_line{$_};
                                }
                                }

                                # We prepare the replacement lines
                                $j = 0;

                                # The main line
                                if ( keys %new_class_line > 1
                                || ( !keys %new_pre_line && !keys %new_skill_line && !keys %new_spell_line )
                                )
                                {
                                push @new_class_lines,
                                        [
                                        'CLASS',
                                        \%new_class_line,
                                        $last_main_line,
                                        $class,
                                        $line_info,
                                        ];
                                $j++;
                                }

                                # The PRExxx line
                                if ( keys %new_pre_line ) {

                                # Need to tell what CLASS we are dealing with
                                my $tagLookup = @{LstTidy::Reformat::getLineTypeOrder('CLASS')}[0];
                                $new_pre_line{ $tagLookup }
                                        = $new_class_line{ $tagLookup };
                                push @new_class_lines,
                                        [
                                        'CLASS',
                                        \%new_pre_line,
                                        ++$last_main_line,
                                        $class,
                                        $line_info,
                                        ];
                                $j++;
                                }

                                # The skills line
                                if ( keys %new_skill_line ) {

                                # Need to tell what CLASS we are dealing with
                                my $tagLookup = @{LstTidy::Reformat::getLineTypeOrder('CLASS')}[0];
                                $new_skill_line{ $tagLookup }
                                        = $new_class_line{ $tagLookup };
                                push @new_class_lines,
                                        [
                                        'CLASS',
                                        \%new_skill_line,
                                        ++$last_main_line,
                                        $class,
                                        $line_info,
                                        ];
                                $j++;
                                }

                                # The spell line
                                if ( keys %new_spell_line ) {

                                # Need to tell what CLASS we are dealing with
                                my $tagLookup = @{LstTidy::Reformat::getLineTypeOrder('CLASS')}[0];
                                $new_spell_line{ $tagLookup }
                                        = $new_class_line{ $tagLookup };

                                ##################################################################
                                # [ 876536 ] All spell casting classes need CASTERLEVEL
                                #
                                # BONUS:CASTERLEVEL|<class name>|CL will be added to all classes
                                # that have a SPELLTYPE tag except if there is also an
                                # ITEMCREATE tag present.

                                if (   LstTidy::Options::isConversionActive('CLASS:CASTERLEVEL for all casters')
                                        && exists $new_spell_line{'SPELLTYPE'}
                                        && !exists $new_spell_line{'BONUS:CASTERLEVEL'} )
                                {
                                        my $tagLookup = @{LstTidy::Reformat::getLineTypeOrder('CLASS')}[0];
                                        my $class = $new_spell_line{ $tagLookup }[0];

                                        if ( exists $new_spell_line{'ITEMCREATE'} ) {

                                                # ITEMCREATE is present, we do not convert but we warn.
                                                $log->warning(
                                                        "Can't add BONUS:CASTERLEVEL for class \"$class\", "
                                                        . "\"$new_spell_line{'ITEMCREATE'}[0]\" was found.",
                                                        $filename
                                                );
                                        }
                                        else {

                                                # We add the missing BONUS:CASTERLEVEL
                                                $class =~ s/^CLASS:(.*)/$1/;
                                                $new_spell_line{'BONUS:CASTERLEVEL'}
                                                = ["BONUS:CASTERLEVEL|$class|CL"];
                                                $log->warning(
                                                qq{Adding missing "BONUS:CASTERLEVEL|$class|CL"},
                                                $filename
                                                );
                                        }
                                }

                                push @new_class_lines,
                                        [
                                        'CLASS',
                                        \%new_spell_line,
                                        ++$last_main_line,
                                        $class,
                                        $line_info,
                                        ];
                                $j++;
                                }

                                # We splice the new class lines in place
                                splice @{$lines_ref}, $first_line, $old_length, @new_class_lines;

                                # Continue with the rest
                                $i = $first_line + $j - 1;      # -1 because the $i++ happen right after
                        }
                        elsif (ref $lines_ref->[$i] eq 'ARRAY'
                                && $lines_ref->[$i][0] ne 'HEADER'
                                && defined $lines_ref->[$i][4]
                                && $lines_ref->[$i][4]{Mode} == SUB )
                        {

                                # We must replace the last_main_line with the correct value
                                $lines_ref->[$i][2] = $last_main_line;
                        }
                        elsif (ref $lines_ref->[$i] eq 'ARRAY'
                                && $lines_ref->[$i][0] ne 'HEADER'
                                && defined $lines_ref->[$i][4]
                                && $lines_ref->[$i][4]{Mode} == MAIN )
                        {

                                # We update the last_main_line value and
                                # put the correct value in the curent line
                                $lines_ref->[$i][2] = $last_main_line = $i;
                        }
                }
                }

                ###############################################################
                # The CLASSSKILL files must be deprecated in favor of extra
                # CSKILL in the CLASS files.
                #
                # For every CLASSSKILL found, an extra line must be added after
                # the CLASS line with the class name and the list of
                # CSKILL in the first CLASS file on the same directory as the
                # CLASSSKILL.
                #
                # If no CLASS with the same name can be found in the same
                # directory, entries with class name.MOD must be generated
                # at the end of the first CLASS file in the same directory.

                if ( LstTidy::Options::isConversionActive('CLASSSKILL conversion to CLASS') ) {
                if ( $filetype eq 'CLASSSKILL' ) {

                        # Here we will put aside all the CLASSSKILL that
                        # we find for later use.

                        my $dir = File::Basename::dirname($filename);
                        LINE:
                        for ( @{ $lines_ref } ) {

                                # Only the 000ClassName are of interest to us
                                next LINE
                                if ref ne 'HASH'
                                || !exists $_->{'000ClassName'}
                                || !exists $_->{'001SkillName'};

                                # We preserve the list of skills for the class
                                $class_skill{$dir}{ $_->{'000ClassName'} } = $_->{'001SkillName'};
                        }
                }
                elsif ( $filetype eq 'CLASS' ) {
                        my $dir = File::Basename::dirname($filename);
                        my $skipnext = 0;
                        if ( exists $class_skill{$dir} ) {

                                # There was a CLASSSKILL file in this directory
                                # We need to incorporate it

                                # First, we find all of the existing CLASS and
                                # add an extra line to them
                                my $index = 0;
                                LINE:
                                for (@$lines_ref) {

                                # If the line is text only, skip
                                next LINE if ref ne 'ARRAY';

                                my $line_tokens = $_->[1];

                                # If it is not a CLASS line, we skip it
                                next LINE
                                        if ref($line_tokens) ne 'HASH'
                                        || !exists $line_tokens->{'000ClassName'};

                                my $class = ( $line_tokens->{'000ClassName'}[0] =~ /CLASS:(.*)/ )[0];

                                if ( exists $class_skill{$dir}{$class} ) {
                                        my $line_no = $- > [2];

                                        # We build a new CLASS, CSKILL line to add.
                                        my $newskills = join '|',
                                                sort split( '\|', $class_skill{$dir}{$class} );
                                        $newskills =~ s/Craft[ %]\|/TYPE.Craft\|/;
                                        $newskills =~ s/Knowledge[ %]\|/TYPE.Knowledge\|/;
                                        $newskills =~ s/Profession[ %]\|/TYPE.Profession\|/;
                                        splice @$lines_ref, $index + 1, 0,
                                                [
                                                'CLASS',
                                                {   '000ClassName' => ["CLASS:$class"],
                                                'CSKILL'                => ["CSKILL:$newskills"]
                                                },
                                                $line_no, $class,
                                                LstTidy::Parse::getParseControl('CLASS'),
                                                ];
                                        delete $class_skill{$dir}{$class};

                                        $log->warning( qq{Adding line "CLASS:$class\tCSKILL:$newskills"}, $filename );
                                }
                                }
                                continue { $index++ }

                                # If there are any CLASSSKILL remaining for the directory,
                                # we have to create .MOD entries

                                if ( exists $class_skill{$dir} ) {
                                for ( sort keys %{ $class_skill{$dir} } ) {
                                        my $newskills = join '|', sort split( '\|', $class_skill{$dir}{$_} );
                                        $newskills =~ s/Craft \|/TYPE.Craft\|/;
                                        $newskills =~ s/Knowledge \|/TYPE.Knowledge\|/;
                                        $newskills =~ s/Profession \|/TYPE.Profession\|/;
                                        push @$lines_ref,
                                                [
                                                'CLASS',
                                                {   '000ClassName' => ["CLASS:$_.MOD"],
                                                'CSKILL'                => ["CSKILL:$newskills"]
                                                },
                                                scalar(@$lines_ref),
                                                "$_.MOD",
                                                LstTidy::Parse::getParseControl('CLASS'),
                                                ];

                                        delete $class_skill{$dir}{$_};

                                        $log->warning( qq{Adding line "CLASS:$_.MOD\tCSKILL:$newskills"}, $filename );
                                }
                                }
                        }
                }
                }

                1;
        }

}

###############################################################
# mylength
# --------
#
# Find the number of characters for a string or a list of strings
# that would be separated by tabs.

sub mylength {
        return 0 unless defined $_[0];

        my @list;

        if ( ref( $_[0] ) eq 'ARRAY' ) {
                @list = @{ $_[0] };
        }
        else {
                @list = @_;
        }

        my $Length      = 0;
        my $beforelast = scalar(@list) - 2;

        if ( $beforelast > -1 ) {

                # All the elements except the last must be rounded to the next tab
                for my $subtag ( @list[ 0 .. $beforelast ] ) {
                $Length += ( int( length($subtag) / $tablength ) + 1 ) * $tablength;
                }
        }

        # The last item is not rounded to the tab length
        $Length += length( $list[-1] );

}

###############################################################
# check_clear_tag_order
# ---------------------
#
# Verify that the .CLEAR tags are put correctly before the
# tags that they clear.
#
# Parameter:  $line_ref         : Hash reference to the line
#                       $file_for_error
#                       $line_for_error

sub check_clear_tag_order {
        my ( $line_ref, $file_for_error, $line_for_error ) = @_;

        TAG:
        for my $tag ( keys %$line_ref ) {

                # if the current value is not an array, there is only one
                # tag and no order to check.
                next unless ref( $line_ref->{$tag} );

                # if only one of a kind, skip the rest
                next TAG if scalar @{ $line_ref->{$tag} } <= 1;

                my %value_found;

                if ( $tag eq "SA" ) {

                # The SA tag is special because it is only checked
                # up to the first (
                for ( @{ $line_ref->{$tag} } ) {
                        if (/:\.?CLEAR.?([^(]*)/) {

                                # clear tag either clear the whole thing,
                                # in which case it must be the very beginning,
                                # or it clear a particular value, in which case
                                # it must be before any such value.
                                if ( $1 ne "" ) {

                                # Let's check if the value was found before
                                $log->notice(  qq{"$tag:$1" found before "$_"}, $file_for_error, $line_for_error )
                                        if exists $value_found{$1};
                                }
                                else {

                                # Let's check if any value was found before
                                $log->notice(  qq{"$tag" tag found before "$_"}, $file_for_error, $line_for_error )
                                        if keys %value_found;
                                }
                        }
                        elsif ( / : ([^(]*) /xms ) {

                                # Let's store the value
                                $value_found{$1} = 1;
                        }
                        else {
                                $log->error(
                                "Didn't anticipate this tag: $_",
                                $file_for_error,
                                $line_for_error
                                );
                        }
                }
                }
                else {
                for ( @{ $line_ref->{$tag} } ) {
                        if (/:\.?CLEAR.?(.*)/) {

                                # clear tag either clear the whole thing,
                                # in which case it must be the very beginning,
                                # or it clear a particular value, in which case
                                # it must be before any such value.
                                if ( $1 ne "" ) {

                                # Let's check if the value was found before
                                $log->notice( qq{"$tag:$1" found before "$_"}, $file_for_error, $line_for_error )
                                        if exists $value_found{$1};
                                }
                                else {

                                # Let's check if any value was found before
                                $log->notice( qq{"$tag" tag found before "$_"}, $file_for_error, $line_for_error )
                                        if keys %value_found;
                                }
                        }
                        elsif (/:(.*)/) {

                                # Let's store the value
                                $value_found{$1} = 1;
                        }
                        else {
                                $log->error(
                                        "Didn't anticipate this tag: $_",
                                        $file_for_error,
                                        $line_for_error
                                );
                        }
                }
                }
        }
}

###############################################################
# find_full_path
# --------------
#
# Change the @ and relative paths found in the .lst for
# the real thing.
#
# Parameters: $file_name                File name
#                       $current_base_dir       Current directory
#                       $base_path              Origin for the @ replacement

sub find_full_path {
        my ( $file_name, $current_base_dir, $base_path ) = @_;

        # Change all the \ for / in the file name
        $file_name =~ tr{\\}{/};

        # Replace @ by the base dir or add the current base dir to the file name.
        if( $file_name !~ s{ ^[@] }{$base_path}xmsi )
        {
                $file_name = "$current_base_dir/$file_name";
        }

        # Remove the /xxx/../ for the directory
        if ($file_name =~ / [.][.] /xms ) {
                if( $file_name !~ s{ [/] [^/]+ [/] [.][.] [/] }{/}xmsg ) {
                die qq{Cannot des with the .. directory in "$file_name"};
                }
        }

        return $file_name;
}

###############################################################
# create_dir
# ----------
#
# Create any part of a subdirectory structure that is not
# already there.

sub create_dir {
        my ( $dir, $outputdir ) = @_;

        # Only if the directory doesn't already exist
        if ( !-d $dir ) {
                my $parentdir = File::Basename::dirname($dir);

                # If the $parentdir doesn't exist, we create it
                if ( $parentdir ne $outputdir && !-d $parentdir ) {
                create_dir( $parentdir, $outputdir );
                }

                # Create the curent level directory
                mkdir $dir, oct(755) or die "Cannot create directory $dir: $OS_ERROR";
        }
}

###############################################################
# embedded_coma_split
# -------------------
#
# split a list using the comma but part of the list may be
# between brackets and the comma must be ignored there.
#
# Parameter: $list      List that need to be splited
#               $separator      optionnal expression used for the
#                               split, ',' is the default.
#
# Return the splited list.

sub embedded_coma_split {

        # The list may contain other lists between brackets.
        # We will first change all the , in within brackets
        # before doing our split.
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





###############################################################
###############################################################
###
### Start of closure for BIOSET generation functions
### [ 663491 ] RACE: Convert AGE, HEIGHT and WEIGHT tags
###

{

        # Moving this out of the BEGIN as a workaround for bug
        # [perl #30058] Perl 5.8.4 chokes on perl -e 'BEGIN { my %x=(); }'

        my %RecordedBiosetTags;

        BEGIN {

                my %DefaultBioset = (

                # Race          AGE                             HEIGHT                                  WEIGHT
                'Human' =>      [ 'AGE:15:1:4:1:6:2:6',   'HEIGHT:M:58:2:10:0:F:53:2:10:0',   'WEIGHT:M:120:2:4:F:85:2:4'       ],
                'Dwarf' =>      [ 'AGE:40:3:6:5:6:7:6',   'HEIGHT:M:45:2:4:0:F:43:2:4:0',       'WEIGHT:M:130:2:6:F:100:2:6'    ],
                'Elf' =>        [ 'AGE:110:4:6:6:6:10:6', 'HEIGHT:M:53:2:6:0:F:53:2:6:0',       'WEIGHT:M:85:1:6:F:80:1:6'      ],
                'Gnome' =>      [ 'AGE:40:4:6:6:6:9:6',   'HEIGHT:M:36:2:4:0:F:34:2:4:0',       'WEIGHT:M:40:1:1:F:35:1:1'      ],
                'Half-Elf' => [ 'AGE:20:1:6:2:6:3:6',   'HEIGHT:M:55:2:8:0:F:53:2:8:0', 'WEIGHT:M:100:2:4:F:80:2:4'     ],
                'Half-Orc' => [ 'AGE:14:1:4:1:6:2:6',   'HEIGHT:M:58:2:10:0:F:52:2:10:0',   'WEIGHT:M:130:2:4:F:90:2:4' ],
                'Halfling' => [ 'AGE:20:2:4:3:6:4:6',   'HEIGHT:M:32:2:4:0:F:30:2:4:0', 'WEIGHT:M:30:1:1:F:25:1:1'      ],
                );

                ###############################################################
                # record_bioset_tags
                # ------------------
                #
                # This function record the BIOSET information found in the
                # RACE files so that the BIOSET files can later be generated.
                #
                # If the value are equal to the default, they are not generated
                # since the default apply.
                #
                # Parameters: $dir              Directory where the RACE file was found
                #                       $race           Name of the race
                #                       $age                    AGE tag
                #                       $height         HEIGHT tag
                #                       $weight         WEIGHT tag
                #                       $file_for_error To use with ewarn
                #                       $line_for_error To use with ewarn

                sub record_bioset_tags {
                my ($dir,
                        $race,
                        $age,
                        $height,
                        $weight,
                        $file_for_error,
                        $line_for_error
                ) = @_;

                # Check to see if default apply
                RACE:
                for my $master_race ( keys %DefaultBioset ) {
                        if ( index( $race, $master_race ) == 0 ) {

                                # The race name is included in the default
                                # We now verify the values
                                $age    = "" if $DefaultBioset{$master_race}[0] eq $age;
                                $height = "" if $DefaultBioset{$master_race}[1] eq $height;
                                $weight = "" if $DefaultBioset{$master_race}[2] eq $weight;
                                last RACE;
                        }
                }

                # Everything that is not blank must be kept
                if ($age) {
                        if ( exists $RecordedBiosetTags{$dir}{$race}{AGE} ) {
                                $log->notice(
                                qq{BIOSET generation: There is already a AGE tag recorded}
                                        . qq{ for a race named "$race" in this directory.},
                                $file_for_error,
                                $line_for_error
                                );
                        }
                        else {
                                $RecordedBiosetTags{$dir}{$race}{AGE} = $age;
                        }
                }

                if ($height) {
                        if ( exists $RecordedBiosetTags{$dir}{$race}{HEIGHT} ) {
                                $log->notice(
                                qq{BIOSET generation: There is already a HEIGHT tag recorded}
                                        . qq{ for a race named "$race" in this directory.},
                                $file_for_error,
                                $line_for_error
                                );
                        }
                        else {
                                $RecordedBiosetTags{$dir}{$race}{HEIGHT} = $height;
                        }
                }

                if ($weight) {
                        if ( exists $RecordedBiosetTags{$dir}{$race}{WEIGHT} ) {
                                $log->notice(
                                qq{BIOSET generation: There is already a WEIGHT tag recorded}
                                        . qq{ for a race named "$race" in this directory.},
                                $file_for_error,
                                $line_for_error
                                );
                        }
                        else {
                                $RecordedBiosetTags{$dir}{$race}{WEIGHT} = $weight;
                        }
                }
                }

                ###############################################################
                # generate_bioset_files
                # ---------------------
                #
                # Generate the new BIOSET files from the data included in the
                # %RecordedBiosetTags hash.
                #
                # The new files will all be named bioset.lst and will required
                # to be renames and included in the .PCC manualy.
                #
                # No parameter

                sub generate_bioset_files {
                for my $dir ( sort keys %RecordedBiosetTags ) {
                        my $filename = $dir . '/biosettings.lst';
                        my $inputpath  = getOption('inputpath');
                        my $outputpath = getOption('outputpath');
                        $filename =~ s/${inputpath}/${outputpath}/i;

                        open my $bioset_fh, '>', $filename;

                        # Printing the name of the new file generated
                        print STDERR $filename, "\n";

                        # Header part.
                        print {$bioset_fh} << "END_OF_HEADER";
AGESET:0|Adulthood
END_OF_HEADER

                        # Let's find the longest race name
                        my $racename_length = 0;
                        for my $racename ( keys %{ $RecordedBiosetTags{$dir} } ) {
                                $racename_length = length($racename) if length($racename) > $racename_length;
                        }

                        # Add the length for RACENAME:
                        $racename_length += 9;

                        # Bring the length to the next tab
                        if ( $racename_length % $tablength ) {

                                # We add the remaining spaces to get to the tab
                                $racename_length += $tablength - ( $racename_length % $tablength );
                        }
                        else {

                                # Already on a tab length, we add an extra tab
                                $racename_length += $tablength;
                        }

                        # We now format and print the lines for each race
                        for my $racename ( sort keys %{ $RecordedBiosetTags{$dir} } ) {
                                my $height_weight_line = "";
                                my $age_line            = "";

                                if (   exists $RecordedBiosetTags{$dir}{$racename}{HEIGHT}
                                && exists $RecordedBiosetTags{$dir}{$racename}{WEIGHT} )
                                {
                                my $space_to_add = $racename_length - length($racename) - 9;
                                my $tab_to_add   = int( $space_to_add / $tablength )
                                        + ( $space_to_add % $tablength ? 1 : 0 );
                                $height_weight_line = 'RACENAME:' . $racename . "\t" x $tab_to_add;

                                my ($m_ht_min, $m_ht_dice, $m_ht_sides, $m_ht_bonus,
                                        $f_ht_min, $f_ht_dice, $f_ht_sides, $f_ht_bonus
                                        )
                                        = ( split ':', $RecordedBiosetTags{$dir}{$racename}{HEIGHT} )
                                        [ 2, 3, 4, 5, 7, 8, 9, 10 ];

                                my ($m_wt_min, $m_wt_dice, $m_wt_sides,
                                        $f_wt_min, $f_wt_dice, $f_wt_sides
                                        )
                                        = ( split ':', $RecordedBiosetTags{$dir}{$racename}{WEIGHT} )
                                                [ 2, 3, 4, 6, 7, 8 ];

# 'HEIGHT:M:58:2:10:0:F:53:2:10:0'
# 'WEIGHT:M:120:2:4:F:85:2:4'
#
# SEX:Male[BASEHT:58|HTDIEROLL:2d10|BASEWT:120|WTDIEROLL:2d4|TOTALWT:BASEWT+(HTDIEROLL*WTDIEROLL)]Female[BASEHT:53|HTDIEROLL:2d10|BASEWT:85|WTDIEROLL:2d4|TOTALWT:BASEWT+(HTDIEROLL*WTDIEROLL)]

                                # Male height caculation
                                $height_weight_line .= 'SEX:Male[BASEHT:'
                                        . $m_ht_min
                                        . '|HTDIEROLL:'
                                        . $m_ht_dice . 'd'
                                        . $m_ht_sides;
                                $height_weight_line .= '+' . $m_ht_bonus if $m_ht_bonus > 0;
                                $height_weight_line .= $m_ht_bonus              if $m_ht_bonus < 0;

                                # Male weight caculation
                                $height_weight_line .= '|BASEWT:'
                                        . $m_wt_min
                                        . '|WTDIEROLL:'
                                        . $m_wt_dice . 'd'
                                        . $m_wt_sides;
                                $height_weight_line .= '|TOTALWT:BASEWT+(HTDIEROLL*WTDIEROLL)]';

                                # Female height caculation
                                $height_weight_line .= 'Female[BASEHT:'
                                        . $f_ht_min
                                        . '|HTDIEROLL:'
                                        . $f_ht_dice . 'd'
                                        . $f_ht_sides;
                                $height_weight_line .= '+' . $f_ht_bonus if $f_ht_bonus > 0;
                                $height_weight_line .= $f_ht_bonus              if $f_ht_bonus < 0;

                                # Female weight caculation
                                $height_weight_line .= '|BASEWT:'
                                        . $f_wt_min
                                        . '|WTDIEROLL:'
                                        . $f_wt_dice . 'd'
                                        . $f_wt_sides;
                                $height_weight_line .= '|TOTALWT:BASEWT+(HTDIEROLL*WTDIEROLL)]';
                                }

                                if ( exists $RecordedBiosetTags{$dir}{$racename}{AGE} ) {

                                # We only generate a comment from the AGE tag
                                $age_line = '### Old tag for race '
                                        . $racename . '=> '
                                        . $RecordedBiosetTags{$dir}{$racename}{AGE};
                                }

                                print {$bioset_fh} $height_weight_line, "\n" if $height_weight_line;
                                print {$bioset_fh} $age_line,           "\n" if $age_line;

                                #       print BIOSET "\n";
                        }

                        close $bioset_fh;
                }
                }

        }       # BEGIN

}       # The entra encapsulation is a workaround for the bug
        # [perl #30058] Perl 5.8.4 chokes on perl -e 'BEGIN { my %x=(); }'

###
### End of  closure for BIOSET generation funcitons
###
###############################################################
###############################################################

###############################################################
# generate_css
# ------------
#
# Generate a new .css file for the .html help file.

sub generate_css {
        my ($newfile) = shift;

        open my $css_fh, '>', $newfile;

        print {$css_fh} << 'END_CSS';
BODY {
        font: small verdana, arial, helvetica, sans-serif;
        color: black;
        background-color: white;
}

A:link  {color: #0000FF}
A:visited   {color: #666666}
A:active        {color: #FF0000}


H1 {
        font: bold large verdana, arial, helvetica, sans-serif;
        color: black;
}


H2 {
        font: bold large verdana, arial, helvetica, sans-serif;
        color: maroon;
}


H3 {
        font: bold medium verdana, arial, helvetica, sans-serif;
                color: blue;
}


H4 {
        font: bold small verdana, arial, helvetica, sans-serif;
                color: maroon;
}


H5 {
        font: bold small verdana, arial, helvetica, sans-serif;
                color: blue;
}


H6 {
        font: bold small verdana, arial, helvetica, sans-serif;
                color: black;
}


UL {
        font: small verdana, arial, helvetica, sans-serif;
                color: black;
}


OL {
        font: small verdana, arial, helvetica, sans-serif;
                color: black;
}


LI
{
        font: small verdana, arial, helvetica, sans-serif;
        color: black;
}

TH {
        font: small verdana, arial, helvetica, sans-serif;
        color: blue;
}


TD {
        font: small verdana, arial, helvetica, sans-serif;
        color: black;
}

TD.foot {
        font: medium sans-serif;
        color: #eeeeee;
        background-color="#cc0066"
}

DL {
        font: small verdana, arial, helvetica, sans-serif;
        color: black;
}


DD {
        font: small verdana, arial, helvetica, sans-serif;
        color: black;
}


DT {
        font: small verdana, arial, helvetica, sans-serif;
                color: black;
}


CODE {
        font: small Courier, monospace;
}


PRE {
        font: small Courier, monospace;
}


P.indent {
        font: small verdana, arial, helvetica, sans-serif;
        color: black;
        background-color: white;
        list-style-type : circle;
        list-style-position : inside;
        margin-left : 16.0pt;
}

PRE.programlisting
{
        list-style-type : disc;
        margin-left : 16.0pt;
        margin-top : -14.0pt;
}


INPUT {
        font: bold small verdana, arial, helvetica, sans-serif;
        color: black;
        background-color: white;
}


TEXTAREA {
        font: bold small verdana, arial, helvetica, sans-serif;
        color: black;
        background-color: white;
}

.BANNER {
        background-color: "#cccccc";
        font: bold medium verdana, arial, helvetica, sans-serif;

}
END_CSS

        close $css_fh;
}

__END__

=head1 NAME

prettylst.pl -- Reformat the PCGEN .lst files

Version: 1.38

=head1 DESCRIPTION

B<prettylst.pl> is a script that parse a PCGEN .lst files and generate
new ones with the proper ordering of the fields. The original order was
given by Mynex. Nowadays, it's Tir-Gwait that is the
head-honcho-master-lst-monkey (well, he decide the order anyway :-).

The script is also able to do some conversions of the .lst so that old
versions are compatibled with the latest release of PCGEN.

=head1 INSTALLATION

=head2 Get Perl

I'm using ActivePerl v5.8.6 (build 811) but any standard distribution with version 5.5 and
over should work. The script has been tested on Windows 98, Windows 2000, Windows XP and FreeBSD.

To my knowledge, I'm using only one module that is not included in the standard distribution: Text::Balanced
(this module is included in the 5.8 standard distribution and maybe with some others).

To get Perl use <L<http://www.activestate.com/Products/ActivePerl/>> or <L<http://www.cpan.org/ports/index.html>>
To get Text::Balanced use <L<http://search.cpan.org/author/DCONWAY/Text-Balanced-1.89/lib/Text/Balanced.pm>> or
use the following command if you use the ActivePerl distribution:

  ppm install text-balanced

=head2 Put the script somewhere

Once Perl is installed on your computer, you just have to find a home for the script. After that,
all you have to do is type B<perl prettylst.pl> with the proper parameters to make it
work.

=head1 SYNOPSIS

  # parse all the files in PATH, create the new ones in NEWPATH
  # and produce a report of the TAG in usage
  perl prettylst.pl -inputpath=<PATH> -outputpath=<NEWPATH> -report
  perl prettylst.pl -i=<PATH> -o=<NEWPATH> -r

  # parse all the files in PATH and write the error messages in ERROR_FILE
  # without creating any new files
  perl prettylst.pl -inputpath=<PATH> -outputerror=<ERROR_FILE>
  perl prettylst.pl -i=<PATH> -e=<ERROR_FILE>

  # parse all the files in PATH and write the error messages in ERROR_FILE
  # without creating any new files
  # A compilation of cross-checking (xcheck) errors will not be displayed and
  # only the messages of warning level notice or worst will be outputed.
  perl prettylst.pl -noxcheck -warninglevel=notice -inputpath=<PATH> -outputerror=<ERROR_FILE>
  perl prettylst.pl -nx -wl=notice -i=<PATH> -e=<ERROR_FILE>

  # parse all the files in PATH and created new ones in NEWPATH
  # by applaying the conversion pcgen5713. The output is redirected
  # to ERROR_FILE
  perl prettylst.pl -inputpath=<PATH> -outputpath=<NEWPATH> \
                                -outputerror=<ERROR_FILE> -convert=pcgen5713
  perl prettylst.pl -i=<PATH> -o=<NEWPATH> -e=<ERROR_FILE> -c=pcgen5713

  # display the usage guide lines
  perl prettylst.pl -help
  perl prettylst.pl -h
  perl prettylst.pl -?

  # display the complete documentation
  perl prettylst.pl -man

  # generate and attemp to display a html file for
  # the complete documentation
  perl prettylst.pl -htmlhelp

=head1 PARAMETERS

=head2 B<-inputpath> or B<-i>

Path to an input directory that will be scanned for .pcc files. A list of
files to parse will be built from the .pcc files found. Only the known filetypes will
be parsed.

If B<-inputpath> is given without any B<-outputpath>, the script parse the files, produce the
warning messages but doesn't write any new files.

=head2 B<-basepath> or B<-b>

Path to the base directory use to replace the @ character in the .PCC files. If no B<-basepath> option is given,
the value of B<-inputpath> is used to replace the @ character.

=head2 B<-systempath> or B<-s>

Path to the B<pcgen/system> used for the .lst files in B<-inputpath>. This directory should contain the
game mode files. These files will be parse to get a list of valid alignment abbreviations, valid statistic
abbriviations, valid game modes and globaly defined variables.

If the B<-gamemode> parameter is used, only the system files found in the proper game mode directory will
be parsed.

=head2 B<-outputpath> or B<-o>

Only used when B<-inputpath> is defined. B<-outputpath> define where the new files will
be writen. The directory tree from the B<-inputpath> will be reproduce as well.

Note: the output directory must be created before calling the script.

=head2 B<-outputerror> or B<-e>

Redirect STDERR to a file. All the warning and errors found by this script are printed
to STDERR.

=head2 B<-gamemode> or B<-gm>

Apply a filter on the GAMEMODE values and only read and/or reformat the files that
meet the filter.

e.g. -gamemode=35e

=head2 B<-convert> or B<-c>

Activate some conversions on the files. The converted files are written in the directory specified
by B<-outputpath>. If no B<-outputpath> is provided, the conversions messages are displayed but
no actual conversions are done.

Only one conversion may be activate at a time.

Here are the list of the valid conversions so far:

=over 12

=item B<pcgen60>

=over 16

Use to change a number of conversions needed for stable 6.0

=item * [ 1973497 ] HASSPELLFORMULA is deprecated

=over 12

=item B<pcgen5120>

=over 16

Use to change a number of conversions for stable 5.12.0.

B<This has a small issue:> if ADD:blah| syntax items that contain ( ) in the elements, it will attempt to convert again.  This has only caused a few problems in the srds, but it is something to be aware of on homebrews.

=item * [ 1678570 ] Correct PRESPELLTYPE syntax

- changes PRESPELLTYPE format from PRESPELLTYPE:<A>,<x>,<y> to standard PRExxx:<x>,<A>=<y>

<L<http://sourceforge.net/tracker/index.php?func=detail&aid=1678570&group_id=25576&atid=750093>>

=item * [ 1678577 ] ADD: syntax no longer uses parens

- Converts ADD:xxx(choice)y to ADD:xxx|y|choice.

<L<http://sourceforge.net/tracker/index.php?func=detail&aid=1678577&group_id=25576&atid=750093>>

=item * [ 1689538 ] Conversion: Deprecation of FOLLOWERALIGN

- Changes the FOLLOWERALIGN tag to new DOMAINS tag imbedded PREALIGN tags.
This can also be done on its own with conversion 'followeralign'.

=item * [ 1353255 ] TYPE to RACETYPE conversion

Use to change the TYPE entry in race.lst to RACETYPE if no RACETYPE is present.

<L<http://sourceforge.net/tracker/index.php?func=detail&aid=1353255&group_id=25576&atid=750093>>


=item * [ 1324519 ] ASCII characters

- Converts a few known upper level characters to ASCII standard output
characters to prevent crashes and bad output when exporting from PCGen.

<L<http://sourceforge.net/tracker/index.php?func=detail&aid=1324519&group_id=25576&atid=750093>>

=back

=item B<followeralign>

Use to change the FOLLOWERALIGN tag to the new DOMAINS tag imbedded PREALIGN tags.  This is included in conversion 5120

<L<http://sourceforge.net/tracker/index.php?func=detail&aid=1689538&group_id=25576&atid=750093>>

=item B<racetype>

Use to change the TYPE entry in race.lst to RACETYPE if no RACETYPE is present.

<L<http://sourceforge.net/tracker/index.php?func=detail&aid=1353255&group_id=25576&atid=750093>>

=item B<pcgen5713>

Use to apply the conversions that bring the .lst files from v5.7.4 of PCGEN
to vertion 5.7.13.

=over 16

=item * [ 1070084 ] Convert SPELL to SPELLS

The old SPELL tags have been deprecated and must be replaced by SPELLS. This conversion
does only part of the job since not all the information needed by the new SPELLS tags
is present in the old SPELL tags.

<L<http://sourceforge.net/tracker/index.php?func=detail&aid=1070084&group_id=36698&atid=450221>>

=item * [ 1070344 ] HITDICESIZE to HITDIE in templates.lst

The old HITDICESIZE tag has been deprecated and my be replaced by the new HITDIE. HITDICESIZE
was only present in the TEMPLATE files.

<L<http://sourceforge.net/tracker/?func=detail&atid=578825&aid=1070344&group_id=36698>>

=item * [ 731973 ] ALL: new PRECLASS syntax

All the PRECLASS tags -- including the ones found within BONUS tags -- are converted to the new
syntax -- B<PRECLASS:E<lt>number of classesE<gt>,E<lt>list of classesE<gt>=E<lt>levelE<gt>>.

Note: this conversion was done a long time ago (pcgen511) but I've reactivated it since
a lot of old PRECLASS formats have reaappeared in the data sets resently.

<L<http://sourceforge.net/tracker/index.php?func=detail&aid=731973&group_id=36698&atid=450221>>

=back

=item B<pcgen574>


Use to apply the conversions that bring the .lst files from v5.6.x or v5.7.x of PCGEN
to vertion 5.7.4.

=over 16

=item * [ 876536 ] All spell casting classes need CASTERLEVEL

Add BONUS:CASTERLEVEL tags to casting classes that do not already have it.

<L<http://sourceforge.net/tracker/index.php?func=detail&aid=876536&group_id=36698&atid=417816>>

=item * [ 1006285 ] Conversion MOVE:<number> to MOVE:Walk,<Number>

The old MOVE tags are changed to the proper syntax i.e. the syntax that
identify the type of move. In this case, we assume that if no move
type was given, the move type is Walk.

<L<http://sourceforge.net/tracker/?func=detail&atid=450221&aid=1006285&group_id=36698>>

=back

=item B<pcgen56>

Use to apply the conversions that bring the .lst files from v5.4.x of PCGEN
to vertion 5.6.

=over 16

=item * [ 892746 ] KEYS entries were changed in the main files

Attempt at automatically conerting the KEYS entries that were changed in the
main xSRD files. Not all the changes were covered though.

<L<http://sourceforge.net/tracker/index.php?func=detail&aid=892746&group_id=36698&atid=578825>>

=back

=item B<pcgen555>

Use to apply the conversions that bring the .lst files from v5.4.x of PCGEN
to vertion 5.5.5.

=over 16

=item * [ 865826 ] Remove the deprecated MOVE tag in EQUIPMENT files

The MOVE tags are removed from the equipments files since they are now useless there.

<L<http://sourceforge.net/tracker/?func=detail&atid=450221&aid=865826&group_id=36698>>

=back

=item B<pcgen541>

Use to apply the conversions that bring the .lst files from v5.4 of PCGEN
to vertion 5.4.1.

=over 16

=item * [ 845853 ] SIZE is no longer valid in the weaponprof files

SIZE is removed from WEAPONPROF files and is not replaced.

<L<http://sourceforge.net/tracker/index.php?func=detail&aid=845853&group_id=36698&atid=578825>>

=back

=item B<pcgen54>

Use this switch to convert from PCGEN 5.2 files to PCGGEN 5.4.

B<WARNING>: Do B<not> use this switch with B<CMP> files! You will break them.

=over 16

=item * [ 707325 ] PCC: GAME is now GAMEMODE

Straight change from one tag to the other. Why? Beats me but it sure helps the conversion script
buisiness to prosper :-).

<L<http://sourceforge.net/tracker/?func=detail&atid=450221&aid=707325&group_id=36698>>

=item * [ 784363 ] Add TYPE=Base.REPLACE to most BONUS:COMBAT|BAB

This change is needed to allow users to completely replace the BAB formulas with something
of their choice. For example, users can now have a customized class with
B<BONUS:COMBAT|BAB|TL|TYPE=Base> that would replace all the other Base bonus to BAB
(because it is greater).

<L<http://sourceforge.net/tracker/?func=detail&atid=450221&aid=784363&group_id=36698>>

=item * [ 825005 ] convert GAMEMODE:DnD to GAMEMODE:3e

PCGEN is droping the d20 licence. Because of that, the DnD keyword can no longer be used
as a game mode. As of PCGEN 5.4, the change to the system files were done and all the
.PCC files that linked to B<GAMEMODE:DnD> must now link to B<GAMEMODE:3e>.

<L<http://sourceforge.net/tracker/?func=detail&atid=578825&aid=825005&group_id=36698>>

B<WARNING>: Do B<not> use this conversion with B<CMP> files! You will break them.

=item * [ 831569 ] RACE:CSKILL to MONCSKILL

The new MONCSKILL tag along with the MFEAT and MONSTERCLASS are used when the default monsters
opotion is enabled in the PCGEN pref. Otherwise, the FEAT and CSKILL tags are used.

<L<http://sourceforge.net/tracker/?func=detail&atid=578825&aid=831569&group_id=36698>>

=back

=item B<pcgen534>

The following conversions were done on the .lst files between version 5.1.1 and 5.3.4 of PCGEN. See
the links for more information about the conversions in question.

=over 16

=item * [ 707325 ] PCC: GAME is now GAMEMODE

All the B<GAME> tags in the B<.PCC> files are converted to B<GAMEMODE> tags.

<L<https://sourceforge.net/tracker/?func=detail&atid=450221&aid=707325&group_id=36698>>

=item * [ 784363 ] Add TYPE=Base.REPLACE to most BONUS:COMBAT|BAB

All the B<BONUS:COMBAT|BAB> related to classes now have a B<TYPE=Base.REPLACE> added to them. This is
an important conversion if you want to mix files with the files included with PCGEN. If this is not done,
the BAB calculation will be all out of wack and you won't really know why.

<L<https://sourceforge.net/tracker/?func=detail&atid=450221&aid=784363&group_id=36698>>

=back

=item B<pcgen511>

The following conversions were done on the .lst files between version 4.3.4 and 5.1.1 of PCGEN. See
the links for more information about the conversions in question.

=over 16

=item * [ 699834 ] Incorrect loading of multiple vision types

=item * [ 728038 ] BONUS:VISION must replace VISION:.ADD

The B<VISION> tag used to allow the B<,> as a separator. This is no longer the case. Only the B<|>
can now be used as a separator. This conversion will replace all the B<,> by B<|> in the B<VISION>
tags except for those using the B<VISION:.ADD> syntax. The B<VISION:.ADD> tags are replaced by
B<BONUS:VISION> tags.

<L<https://sourceforge.net/tracker/?func=detail&atid=417816&aid=699834&group_id=36698>>
<L<https://sourceforge.net/tracker/?func=detail&atid=450221&aid=728038&group_id=36698>>

=item * [ 731973 ] ALL: new PRECLASS syntax

All the PRECLASS tags -- including the ones found within BONUS tags -- are converted to the new
syntax -- B<PRECLASS:E<lt>number of classesE<gt>,E<lt>list of classesE<gt>=E<lt>levelE<gt>>.

<L<http://sourceforge.net/tracker/index.php?func=detail&aid=731973&group_id=36698&atid=450221>>

=back

=item B<pcgen438>

The following conversions were done on the .lst files between version 4.3.3 and 4.3.4 of PCGEN. See
the links for more information about the conversions in question.

=over 16

=item * [ 686169 ] remove ATTACKS: tag

The B<ATTACKS> tags in the EQUIPMENT line types are replaced by B<BONUS:COMBAT|ATTACKS|> tags.

<L<https://sourceforge.net/tracker/?func=detail&atid=450221&aid=686169&group_id=36698>>

=item * [ 695677 ] EQUIPMENT: SLOTS for gloves, bracers and boots

The equipment of type Glove, Bracer and Boot needs a B<SLOTS:2> tag if the pair must
be equiped to give the bonus. The conversion looks at the equipement name and adds
the B<SLOTS:2> tag if the item is in the plural form. If the equipment name is in the
singular, a message is printed to show that fact but the SLOTS:2 tag is not added.

<L<https://sourceforge.net/tracker/?func=detail&atid=450221&aid=695677&group_id=36698>>

=item * PRESTAT now only accepts the format PRESTAT:1,<stat>=<n>

The B<PRESTAT> no longer accepts the old syntax. Now, every B<PRESTAT> tag needs a leading
number and coma before the stats enumaration. e.g. B<PRESTAT:STR=13> becaumes B<PRESTAT:1,STR=13>.

No tracker found.

=back

=item B<pcgen433>

This convert the references to equipement names and path that were changed with the release 4.3.3 of
PCGEN. This only changes the path values in the .PCC, the files stay in the directories they are found.

=back

=head2 B<-oldsourcetag>

From PCGen version 5.9.6, there is a new format for the SOURCExxx tag that use the tab instead of the |. prettylst.pl
automatically converts the SOURCExxx tags to the new format. The B<-oldsourcetag> option must be used if
you want to keep the old format in place.

=head2 B<-report> or B<-r>

Produce a report of the valid tags found in all the .lst and .pcc files. The report for
the invalid tags is always printed.

=head2 B<-xcheck> or B<-x>

B<This option is now on by default>

Verify the existance of values refered by other tags and produce a report of the
missing/inconsistant values.

=head2 B<-nojep>

Disable the new LstTidy::Parse::parseJep function for the formula. This makes the script use the
old style formula parser.

=head2 B<-noxcheck> or B<-nx>

Disable the cross-check validations.

=head2 B<-warninglevel> or B<-wl>

Select the level of warning that should be displayed. The more critical levels include
the less critical ones. ex. B<-wl=informational> will output messages of level
informational, notice, warning and error but will not output the debug level messages.

The possible levels are:

=over 12

=item B<error>, B<err> or B<3>

Critical errors that need to be checked otherwise the resulting .lst files will not
work properly with PCGen.

=item B<warning>, B<warn> or B<4>

Important messages that should be verified. All the conversion messages are
at this level.

=item B<notice> or B<5>

The normal messages including common syntax mistakes and unknown tags.

=item B<informational>, B<info> or B<6> (default)

Can be very noisy. Include messages that warn about style, best practice and deprecated tags.

=item B<debug> or B<7>

Messages used by the programmer to debug the script.

=back

=head2 B<-exportlist>

Generate files which list objects with a reference on the file and line where they are located.
This is very useful when correcting the problems found by the -x options.

The files generated are:

=over 12

=item * class.csv

=item * domain.csv

=item * equipment.csv

=item * equipmod.csv

=item * feat.csv

=item * language.csv

=item * pcc.csv

=item * skill.csv

=item * spell.csv

=item * variable.csv

=back

=head2 B<-missingheader> or B<-mh>

List all the requested headers (with the getHeader function) that are not
defined in the %tagheader hash. When a header is not defined, the tag name
is used as is in the generated header lines.

=head2 B<-help>, B<-h> or B<-?>

Print a brief help message and exits.

=head2 B<-man>

Prints the manual page and exits. You might want to pipe the output to your favorite pager
(e.g. more).

=head2 B<-htmlhelp>

Generate a .html file with the complete documentation (as it is)
for the script and tries to display it in a browser. The display portion only
works on the Windows platform.


=head1 MANIFEST

The distribution of this script includes the following files:

=over 8

=item * prettylst.pl

The script itself.

=item * prettylst.pl.html

HMTL version of the perldoc for the script. You can generate this file
by typing C<perl prettylst.pl -htmlhelp>.

=item * prettylst.pl.css

Style sheet files for prettylst.pl.html

=item * prettylst-release-notes-135.html

The release notes for the curent version.

=item * prettylst.pl.sig

PGP signature for the script. You can get a copy of my
key here: <L<http://pgp.mit.edu:11371/pks/lookup?op=get&search=0x5187D5D2>>

=back

=head1 COPYRIGHT

Copyright 2002 to 2006 by E<Eacute>ric E<quot>Space MonkeyE<quot> Beaudoin -- <mailto:beaudoer@videotron.ca>

Copyright 2006 to 2010 by Andrew E<quot>Tir GwaithE<quot> McDougall -- <mailto:tir.gwaith@gmail.com>

Copyright 2007 by Richard Bowers

Copyright 2008 Phillip Ryan

All rights reserved.  You can redistribute and/or modify
this program under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>.

=head1 TO DO

=over 8

=item * Default monster race conversion to KITs

=item * Add better examples

=item * Add more cross-reference checks

=item * Add more Ability object checks

=back

=head1 KNOWN BUGS

=over 8

=item * When running conversions pcgen5120 on a file with ADD:xxx|, and the sub-elements contain ( ), prettylst will run the conversion script on that tag again, resulting in too many | in the tag, and no loading in pcgen.  Please be careful and make backups before running the script conversion (as usual)

=item * When running coversions pcgen5120, lots of duplicate item warnings when replacing the ADD:xxx syntax.  running the script after that will show better accuracy, but remove the replacement statements in the report.

=item * The script is still unwilling to do the coffee...

=back

=head1 VERSION HISTORY

=head2 v1.40 -- -- NOT YET RELEASED

[ 1973497 ] HASSPELLFORMULA is deprecated

[ 1778050 ] MOVECLONE now only has 3 args

[ 1870825 ] EqMod CHOOSE Changes

[ 2946558 ] TEMPLATE can be used in COMPANIONMOD lines

[ 2596967 ] ABILITY not recognized for MASTERBONUSRACE

[ 2946552 ] New SELECTION Kit Tag

[ 2946555 ] BENEFIT can be used more than once per line

[ 2946551 ] New LANGBONUS Kit tag

[ 1864706 ] PROFICIENCY: requires a subtoken

[ 2577370 ] New Token - ABILITYLIST

[ 2387200 ] New Token - PREPROFWITHARMOR

[ 2577310 ] New Token - PREPROFWITHSHIELD

[ 2186450 ] New Ability/Feat Token - ASPECT

[ 2544134 ] New Token - SPELLKNOWN

=head2 v1.39 -- 2000.01.28

[ 2022217 ] UMULT is valid in Abillities

[ 2016715 ] ADD tags are not as globally applied as they should be

[ 2016696 ] PRECAMPAIGN tag for .pcc and lst files

[ 2012989 ] Kit TYPE tag

Added an audible notification {beep} when processing completes

[ 1941853 ] Allow , in Spell Knowledge feat

[ 1998298 ] SPELLS TIMEUNIT checking bug

[ 1997408 ] False positive: TIMEUNIT= parameter is missing

[ 1958876 ] PL not dealing with JEP syntax correctly

[ 1958872 ] trim PREXXX before checking SPELLLEVEL

[ 1995252 ] Header for the Error Log

[ 1994059 ] Convert EQMOD "BIND" to "BLIND"

[ 1938933 ] BONUS:DAMAGE and BONUS:TOHIT should be Deprecated

[ 1905481 ] Deprecate CompanionMod SWITCHRACE

[ 1888288 ] CHOOSE:COUNT= is deprecated

[ 1870482 ] AUTO:SHIELDPROF changes

[ 1864704 ] AUTO:ARMORPROF|TYPE=x is deprecated

[ 1804786 ] Deprecate SA: replace with SAB:

[ 1804780 ] Deprecate CHOOSE:EQBUILDER|1

[ 1992156 ] CHANGEPROF may be used more than once on a line

[ 1991974 ] PL incorectly reports CLEARALL as CLEAR

[ 1991300 ] Allow %LIST as a substitution value on BONUS:CHECKS

[ 1973526 ] DOMAIN is supported on Class line

[ 1973660 ] ADDDOMAINS is supported on Class lines

[ 1956721 ] Add SERVESAS tag to Ability, Class, Feat, Race, Skill files

[ 1956719 ] Add RESIZE tag to Equipment file

[ 1956220 ] REPEATLEVEL not recognized as a ClassLevel line

[ 1956204 ] Check for both TYPE:Container and CONTAINS in Equipment files

[ 1777282 ] CONTAINS Unlimited Weight is UNLIM, not -1

[ 1946006 ] Add BONUS:MISC to Spell

[ 1943226 ] Add UDAM to EQUIPMENT tag list

[ 1942824 ] LANGAUTO .CLEARALL and .CLEAR

[ 1941843 ] Reduce Spellbook warning to info

[ 1941836 ] NONE is valid for SPELLSTAT

[ 1941831 ] PREMULT can be used multiple times

[ 1941829 ] AUTO:FEAT can be used multiple times

[ 1941208 ] Preliminary work toward supporting the processing of the AbilityCategory lst files.

[ 1941207 ] Add the Global tag GENDER to the CLASS, RACE, and TEMPLATE tag lists

[ 1757241 ] CAMPAIGN not a recognized *.pcc tag -- Could not duplicate this issue

Added several new column headers

[ 1937985 ] Add TIMEUNIT=<text> parameter to the SPELLS tag

[ 1937852 ] Kit GENDER Support

[ 1937680 ] KIT FUNDS lines in Kit file

[ 1750238 ] ABILITY warnings

[ 1912505 ] Stop Reporting missing TYPE and RACETYPE in racial .MOD

[ 1729758 ][BUG]DOMAIN tags with PREALIGN cause false positive xcheck

[ 1935376 ] New files: Armorprof and Shieldprof

[ 1774985 ] Exchange cl() with classlevel()

[ 1864711 ] Convert ADD:SA to ADD:SAB

[ 1893278 ] UNENCUMBEREDMOVE is a global tag

[ 1893279 ] HASSPELLFORMULA Class Line tag

[ 1805245 ] NATURALATTACKS allowed more than once in RACE

[ 1776500 ] PREDEITY needs updated

[ 1814797 ] PPCOST needs to be added as valid tag in SPELLS

[ 1786966 ] Global tags throwing false warnings

[ 1784583 ] .MOD .FORGET .COPY race lines don't need RACETYPE or TYPE

[ 1718370 ] SHOWINMENU tag missing for PCC files

[ 1722300 ] ABILITY tag in different locations

[ 1722847 ] AUTO:WEAPONPROF in equipment.lst

=head2 v1.38 -- 2007.04.26

=over 3

=item Additional Conversions:

[ 1678570 ] Correct PRESPELLTYPE syntax

[ 1678577 ] ADD: syntax no longer uses parens

[ 1689538 ] Conversion: Deprecation of FOLLOWERALIGN
- Use "Followeralign" as the option to convert to invoke this.

[ 1514765 ] Conversion to remove old defaultmonster tags

[ 1324519 ] ASCII characters

=back

=over 3

=item Additional Warnings and notices:

[ 1671407 ] xcheck PREABILITY tag

[ 1683231 ] CHOOSE:SCHOOLS does not have arguments

[ 1695877 ] KEY tag is global

[ 1596310 ] xcheck: TYPE:Spellbook for equip w/ NUMPAGES and PAGEUSAGE

[ 1368562 ] .FORGET / .MOD don\'t need KEY entries

[ 1671410 ] xcheck CATEGORY:Feat in Feat object.

[ 1690990 ] Add APPEARANCE to Deities LST

[ 1223873 ] WEAPONAUTO is no longer valid

[ 1678573 ] ADD: deprecation

[ 1678576 ] ADD:FEAT supports ALL

[ 1387361 ] No KIT STARTPACK entry for \"KIT:xxx\"

Race entry references with % now produce _much_ fewer errors lines.

=back

=head2 v1.37 -- 2007.03.01

[ 1353255 ] TYPE to RACETYPE conversion
- Use convert 'racetype' to invoke this.

[ 1672551 ] PCC tag COMPANIONLIST

[ 1672547 ] Support for Substitution Classes

[ 1683839 ] Sort KEY tags next to names

=head2 v1.37 -- 2007.03.01

[ 1623708 ] Invalid value "DEITY" for tag "PREALIGN" - should be allowed

[ 1374892 ] DEITY tag

Ability file now supported, including LEVELABLITY in Kits.  No real checking yet.

[ 1671827 ] PRESRxx enhancement

[ 1666665 ] Add support for ABILITY files

[ 1658571 ] KIT in feats and prettylst

[ 1671364 ] missing valid TEMPLATE tags

[ 1671363 ] missing SPELL line tags

[ 1671361 ] new PCC tag; ISMATURE:<YES/NO>

[ 1671356 ] Missing valid tags for Companion support

[ 1671353 ] add missing BONUS:SLOTS parameters

[ 1326023 ] New tag: BONUS:MONSKILLPTS|LOCKNUMBER|x

[ 1661050 ] New PREAGESET tag

=head2 v1.36 -- 2007.01.26

[ 1637309 ] REACH, FACE & LEGS are now Template tags

[ 1630261 ] Change syntax for QUALIFY tag

[ 1615457 ] Replace ALTCRITICAL with ALTCRITMULT

Add PREREACH tag

[ 1625250 ] New tag REACHMULT:x

=head2 v1.35

[ 1593904 ] KIT lines can have any standard PRE tag

[ 1596402 ] New Kit GEAR tag: LOOKUP

[ 1596400 ] New Kit line_type: TABLE, with VALUES tag

[ 1593894 ] New Kit tag: OPTION

[ 1593885 ] New Kit line_type tag: SELECT

[ 1593872 ] False warning: No SKILL entry for CSKILL:ALL

[ 1594671 ] New tag: equipmod FORMATCAT

[ 1594651 ] New Tag: Feat.lst: DESC:.CLEAR and multiple DESC tags

[ 1593868 ] New equipment tag "QUALITY"

[ 1593879 ] New Kit tag: APPLY

[ 1593907 ] False warning: Invalid value "CSHEET" for tag "VISIBLE"

Moved SOURCExxx tag info into array - all lines use same tag order for SOURCE tags now.

[ 1584007 ] New Tag: SOURCEDATE in PCC

[ 1450980 ] New Spellbook tags

[ 1335912 ] New tag: TEMPLATE:.CLEAR

[ 1580059 ] SKILLLIST tag

[ 1173567 ] Convert old style PREALIGN to new style

[ 1105603 ] New VARs in gameMode files

[ 1117152 ] VFEAT and TEMPLATE use

[ 1119767 ] Invalid value "R" for tag "MODS"

[ 1123650 ] HITDIE tag in class lines

[ 1152687 ] SPELLLEVEL:CLASS in feats.lst

[ 1153255 ] FUMBLERANGE new tag

[ 1156423 ] BONUS:WIELDCATEGORY

[ 1173534 ] .CLEAR syntax issue

[ 1173794 ] BONUS:WEAPONPROF order in race file

Eliminated a lot of false positive with references to SUBCLASS

Psionic is now valid in ADD:SPELLCASTER

Clean up the valid game modes

[ 1326008 ] Add tag: HIDETYPE to the PCC tag list

[ 1326016 ] New tag: PRERULE

[ 1325996 ] Add tag: ADD:EQUIP(y,y)z

[ 1325943 ] ADD:SKILL(Speak Language)1" found in FEAT

[ 1238595 ] New tag: PRECSKILL

[ 1326349 ] Missing TYPE:.CLEAR tag in FEAT

[ 1223873 ] WEAPONAUTO is no longer valid

[ 1326374 ] Add JEP operators

[ 1224428 ] No RACE entry for "SWITCHRACE:xxx"

[ 1282532 ] ClassDefense and Reputation

[ 1292967 ] TITLE and WORSHIPPERS in deity.lst

[ 1327238 ] Add CHANGEPROF to TEMPLATE tag list

[ 1324532 ] Biosettings.lst

[ 1309116 ] LANGAUTO missing in CLASS Level

Removed all the sub prototypes [Perl Best Practices]

mywarn has been completely replaced with ewarn

[ 1324512 ] BONUSSPELLSTAT is not in the CLASS tag list

[ 1355958 ] New tag: SCHOOL:.CLEAR

[ 1353231 ] New tag: RACETYPE

[ 1353233 ] New tag: RACESUBTYPE

[ 1355994 ] KIT file refinements

[ 1356139 ] UDAM missing in FEAT tag list

[ 1356143 ] ADD:Language missing in TEMPLATE tag

[ 1356158 ] SPELL is invalid as value for SPELLSTAT in CLASS

[ 1356999 ] Use of uninitialized value in string eq

[ 1359467 ] .COPY=<name> not used for validation

[ 1361057 ] Missing variables for the Modern game mode

[ 1361066 ] Do not x-check outside the -inputpath

Added system files parsing to find the variables names, game moes, and
abbreviations for stats and alignments

[ 1362206 ] [CLASS Level]Missing TEMPDESC tag

[ 1362222 ] [RACE]Missing KIT tag

[ 1362223 ] [CLASS Level]Missing BONUS:SLOTS

prettylst.pl no longer tolerate old style formula parser

[ 1364343 ] Multiple PRESPELLCAST tags

PRERACE:<number>,<list of races> is officialy the way to go

PRERACE:<list of races> to PRERACE:1,<list of races> conversion

[ 1367569 ] SYSTEM: Validate BONUS:CHECK with statsandchecks.lst values

[ 1366753 ] [KIT] The tag FREE is missing in the KIT FEAT tag list

[ 1398237 ] ALL: Convert Willpower to Will

Filter out the Subversion system directories

The SOURCExxx tags are now separated by tabs instead of |

The -oldsourcetag option has been added to use | instead of tab in the SOURCExxx lines

Implemented a "fix" for the /../ in directories

[ 1440104 ] Ignore specific hidden files and directories

[ 1444527 ] New SOURCE tag format

[ 1483739 ] [CMP] SOURCEx changes for 5.10 compatibility

[ 1418243 ] RANGE:.CLEAR is missing in SPELL tag list

[ 1461407 ] ITEM: spell tag order

=head2 v1.34 -- 2005.01.19

[ 1028284 ] Verified if , are present in object names

[ 1028919 ] Report with GAMEMODE

[ 1028285 ] Convert old style PRExxx tags to new style

[ 1039028 ] [PCC]New Xcrawl Game Mode

[ 1070084 ] Convert SPELL to SPELLS

[ 1037456 ] Move BONUS:DC on class line to the spellcasting portion

[ 1027589 ] TEMPDESC (tag from 5.5.1) in skills.lst

[ 1066352 ] BONUS:COMBAT|INITIATIVE on MASTERBONUSRACE line

[ 1066355 ] BONUS tags in spells.lst

[ 1066359 ] BONUS:UDAM in class.lst

[ 1048297 ] New Tag: MONNONSKILLHD

[ 1077285 ] ALTCRITRANGE tag

[ 1079504 ] PREWIELD in eqmod file

[ 1083339 ] RATEOFFIRE in equip.lst

[ 1080142 ] natural attacks with TYPE:Natural

[ 1093382 ] Warning for missing param. in SPELLS

Added x-ref check for FOLLOWER and MASTERBONUSRACE in COMPANIONMODE file type

Added x-ref check for RACE with the PRERACE and !PRERACE tags

[ 1093134 ] BONUS:FEAT|POOL|x

[ 1094126 ] Make -xcheck option on by default

[ 1097487 ] MONSKILL in class.lst

[ 1104117 ] BL is a valid variable, like CL

[ 1104126 ] SPELLCASTER.Psionic is valid spellcasting class type

General work on KIT support

Three new file types added to exportlist: DEITY, KIT and TEMPLATE

DEITY, STARTPACK KIT and TEMPLATE are now validated by the x-check code

[ 1355926 ] DESC on equipment files

=head2 v1.33 -- 2004.08.29

[ 876536 ] All spell casting classes need CASTERLEVEL

[ 1003585 ] PCC: The script should not remove INCLUDE and EXCLUDE

The script can no longer read CLASSSPELL and CLASSSKILL files.

The functions CLASS_parse, CLASSSPELL_parse and GENERIC_parse have been removed since
they were no longer used.

[ 1004050 ] Spycrat is a new valid GAMEMODE

[ 971744 ] 5.7+ TEMPLATE in feats.lst

[ 976475 ] Missing LANGBONUS tag in CLASS Level

[ 1004081 ] Missing global BONUS:CASTERLEVEL

Major code reengeering to allow a better PRExxx tag validation

[ 1004893 ] ADD:SPELLCASTER is valid in RACE

[ 1005363 ] Validate NATURALATTACKS tag

[ 1005651 ] ADD:Language in a feat file

[ 1005653 ] Multiple variable names in a BONUS:VAR tag

[ 1005655 ] BONUS:SLOTS in race files

[ 1005658 ] BONUS:MOVEMULT

[ 1006285 ] Conversion MOVE:<number> to MOVE:Walk,<Number>

[ 1005661 ] ADD:SPELLCASTER in feat .lst

[ 1006985 ] Spycraft gameMode DEFINEd VARiables

[ 1006371 ] SA tag in Skill .lst

[ 976474 ] DEITY tag is missing from CLASS Level

Added the -gamemode parameter

=head2 v1.32 -- 2004.07.06

[ 832164 ] Adding NoProfReq to AUTO:WEAPONPROF for most races

[ 832171 ] AUTO:* needs to be separate tags

Added the -c=skillbonusfix to add BONUS:SKILL|Climb|8|TYPE=Racial if it is not already
present and the race has a MOVE:Climb entry. Same thing with Swim.

[ 845853 ] SIZE is no longer valid in the weaponprof files

[ 833509 ] All the PRExxx tags missing must be added

[ 849366 ] VFEAT with inline PRExxx

Added the ability to export the LANGUAGE entities when using the -exportlist option

[ 865826 ] Remove the deprecated MOVE tag in EQUIPMENT files

[ 865948 ] Properly check files with same name but different directory

[ 849365 ] CLASSES:ALL

[ 849369 ] SPELLCASTER.Arcane=1

[ 879467 ] AUTO:EQUIP in equipment files

[ 882797 ] SUBCLASS -- NAMEISPI: tag

[ 882799 ] SUBCLASSLEVEL -- add SPELLLEVEL:CLASS tag

[ 892746 ] KEYS entries were changed in the main files

[ 892748 ] Track the EQMOD keys with -x flag

Track the variable names with the -x flag (phase 1)

Put BONUS:CASTERLEVEL on the spell CLASS line

Removed a bunch of old conversion code that is no longer used

[ 971746 ] "PREVARGTEQ" can be used more than once in feats.lst

[ 971778 ] BONUS:UDAM| tag

Implemetend a workaroud for a perl bug => [perl #30058] Perl 5.8.4 chokes on perl -e 'BEGIN { my %x=(); }'

[ 902439 ] PREVISION not in FEAT tag list

[ 975999 ] [tab][space][tab] breaks prettylst

[ 974710 ] AUTO:WEAPONPROF usable multiple times

[ 971782 ] FACE tag in races.lst

Removed a warning message for CHOOSE:SPELLLEVEL

Add the B<-nowarning> option to suppress the warning messages

[ 974693 ] PROHIBITED class tag

=head2 v1.31 -- 2003.10.29

[ 823221 ] SPELL multiple time on equipment

[ 823763 ] BONUS:DC in class level

[ 823764 ] ADD:FEAT in domain list

[ 824975 ] spells.lst - DESCISPI:[YES/NO]

[ 825005 ] convert GAMEMODE:DnD to GAMEMODE:3e

[ 829329 ] Lines get deleted when the line type is not know

[ 829335 ] New LANGAUTO line type for KIT files

[ 829380 ] New Game Mode

[ 831569 ] RACE:CSKILL to MONCSKILL

[ 832139 ] CLASS Level: missing NATURALATTACKS

=head2 v1.30 -- 2003.10.14

[ 804091 ] ADD:FEAT warning

[ 807329 ] PRESIZE warning (for template.lst)

[ 813333 ] MONCSKILL and MONCCSKILL in race.lst

[ 813334 ] PREMULT

[ 813335 ] ACHECK:DOUBLE

[ 813337 ] BONUS:DC

[ 813504 ] SPELLLEVEL:DOMAIN in domains.lst

[ 814200 ] PRESKILL in SPELL files

[ 817399 ] Tags usable in SUBCLASS

[ 823042 ] not finding files issue

A new B<-baspath> option was added to specify the path that must replace the @ characters in
the .PCC files when that path is different from B<-inputpath>.

[ 823166 ] Missing PREVARNEQ tag

[ 823194 ] PREBASESIZExxx tags

=head2 v1.29 -- 2003.08.23

New tags were added as a result of the big CMP push.

The script now detect the tags that have no values (with the -x option).

PRECLASS:Spellcaster, Spellcaster.Arcane and Spellcaster.Devine are now understood.

Removed the 4.3.3 dir restructure conversion code.

I've activated the KIT files reformating.

The CLASS lines are now reformated in four lines. A new line with all the spell related
tags follow the skill tags.

[ 707325 ] PCC: GAME is now GAMEMODE L<https://sourceforge.net/tracker/?func=detail&atid=450221&aid=707325&group_id=36698>

New set_ewarn_header function

New function to take RACE and TEMPLATE that are on multiple lines and bring them back to one line

[ 779821 ] Add quote removal L<https://sourceforge.net/tracker/?func=detail&atid=578825&aid=779821&group_id=36698>

[ 784363 ] Add TYPE=Base.REPLACE to most BONUS:COMBAT|BAB L<https://sourceforge.net/tracker/?func=detail&atid=450221&aid=784363&group_id=36698>

=head2 v1.28 -- 2003.05.04

New line type MASTERBONUSRACE

New validation for the FEAT line type (CHOSE <=> MULT <=> STACK)

[ 728038 ] BONUS:VISION must replace VISION:.ADD

[ 711565 ] BONUS:MOVE replaced with BONUS:MOVEADD (Not definitive yet)

New validation for PRECLASS (make sure the number is there and the class exists)

[ 731973 ] ALL: new PRECLASS syntax

=head2 v1.27 -- 2003.04.03

The B<-inputpath> option is now mandatory

[ 686169 ] remove ATTACKS: tag

[ 695677 ] EQUIPMENT: SLOTS for gloves, bracers and boots

[ 707325 ] PCC: GAME is now GAMEMODE

[ 699834 ] Incorrect loading of multiple vision types

PRESTAT now only accepts the format PRESTAT:1,<stat>=<n>

=head2 v1.26 -- 2002.02.27

[ 677962 ] The DMG wands have no charge

Removed the invalid PREBAB tag

Change the order for the FEAT line type

Dir path conversion for the new SRD files

Upgraded to ActivePerl 635

New EQUIPMENT tag order

Weapon name conversion for PCGEN 4.3.3 for SRD compliance

New B<-convert> parameter

=head2 v1.25 -- 2003.01.27

[ 670554 ] SYNERGY to BONUS:SKILL format

Fixed the CLASSSPELL conversion that was not working with the new parser

Fixed a problem with the Export Lists function (for DOMAIN)

Change the BIOSET conversion code so that the new bioset files are
generated in the output directory

New SKILL line tags order

=head2 v1.24 -- 2003.01.14

BIOSET generation from the AGE, HEIGHT and WEIGHT tags

Added the BIOSET file definition for FILETYPE_parse

New order for SPELL tags

=head2 v1.23 -- 2003.01.06

I'm removed the useles -debug option

Add a bunch of new tags in the SUBCLASSLEVEL (everything in CLASS Level)

I'm now running Perl Dev Kit 5

=head2 v1.22 -- 2002.12.31

The FEAT validation code now deal with |CHECKMULT properly

The FEAT validation code now ignores , between () for ADD:FEAT and PREFEAT

Fixed remaining tr!/!\\! so that they are used only on MSWin32 systems

The new set_mywan_filename is called after each section header to empty the $previousfile
variable within the mywarn closure

=head2 v1.21 -- 2002.12.28

FEAT validation added for the tags FEAT, MFEAT, VFEAT, PREFEAT and ADD:FEAT

[ 657059 ] Verify pipe is the only delimiter:VISION

The tr!/!\\! on the file names printed by mywarn is done only for MSWin32 OS

=head2 v1.20 -- 2002.12.19

[ 653596 ] Add a TYPE tag for all SPELLs (first part, change on hold)

Added the -missingheader command line option to list all the header that do not
have definitions in the %tagheader hash

Only the first SOURCExxx line is replaced when the SOURCE line replacement option
is active

All the filetypes except CLASSSKILL and CLASSSPELL have been
migrated to FILETYPE_parse (KIT is only validated for now)

New .CLEAR code (TAG:.CLEAR are all different tags now)

=head2 v1.19 -- 2002.12.12

[ 602874 ] SAVES tag deprecated, replaced by 3 BONUS:CHECKS|BASE.savename|x|PREDEFAULTMONSTER:Y

The CVS files beginning with .# are now ignored by prettylst

Code to correct the BONUS:STAT|WIL typo (should be BONUS:STAT|WIS)

New NAMEISPI tag in every files

New getHeader function

The BONUS:xxx are now considered differents tags (like the ADD:xxx)

[ 609763 ] Convert the old PRECHECKxxx

Added coded to check and standerdize tags with limited possible values

SA:.CLEAR is now a sperate tag than SA: in order to facilitate the sorting

Got rid of the old %validpcctag (replaced by the generic %valid_tags)

[ 619312 ] RACENAME deprecated, convert to OUTPUTNAME

[ 613604 ] CASTAS:name to SPELLLIST:x|name

Added code to standardise the SOURCExxx line in the .lst files
based of the SOURCExxx tags found in the same directory.

Added code to convert the CLASSSKILL files into CLASS CSKILL

[ 620419 ] Added code to flag and display the SA entries that include ','

[ 624885 ] CLASS: remove AGESET tag

[ 626133 ] Convert CLASS lines into 3 lines

Changed the report sort order so that !PRExxx entries are now sorted
right after the corresponding PRExxx.

Added code for CSKILL, LANGAUTO and LANGBONUS tag validation

[ 641912 ] Convert CLASSSPELL to SPELL

New FILETYPE_parser

Removed the now useless -taginfixed option.

New ###Block pragma. It forces a new block for the entities that have
block formatting (FILETYPE_parse only)

Added the KIT filetype

Conversion code for EFFECTS to DESC and EFFECTTYPE to TARGETAREA in the SPELL files

=head2 v1.18 -- 2002.08.31

Conversion of the stat tags in TEMPLATE (STR, DEX, etc.) by BONUS:STAT|...

Removing TYPE=Ability from BONUS:STAT|xxx|y|TYPE=Ability in RACE

Added the COPYRIGHT tags for the PCC files

Conversion of nameCHECK to BONUS:CHECKS|BASE.name in CLASS

Conversion of BAB to BONUS:COMBAT|BAB in CLASS

Remove the GOLD tag from CLASS and TEMPLATE for OGL compliance

New tag MODTOSKILLS

Deprecated INTMODTOSKILLS

Fixed a bug with #EXTRAFILE that was introduced in parse_tag

=head2 v1.17 -- 2002.08.17

New file type COMPANIONMOD

New tag INFOTEXT

Added conversion code for the STATADJx tags

Add a few of the missing GLOBAL tags

Removed a few illigal BONUS type

[ 571276 ] "PRESKILL:1,Knowledge %" replace by "PRESKILL:1,TYPE.Knowledge" in the CLASS lines

[ xxx ] "SUBSA:blah" must become "SA:.CLEAR.blah". The new SA tags
must be put before the existing SA tags.


=head2 v1.16 -- 2002.06.28

Add code to correct the conversion mistake and also corrected the conversion matrice
for the new SKILL tags.

First phase of cross-check validation.

Corrected a bug with the line number.

Add conversion for PRETYPE:Magic to PRETYPE:EQMODTYPE=MagicalEnhancement in the
EQUIPMOD files.

Add -x option to do x-check validation.

Add validation for the .MOD entries.

Add conversion for SR to SPELLRES in SPELL files.

=head2 v1.15 -- 2002.06.20

New option B<-outputerror> to redirect STDERR in a file

Preserve the leading spaces on the first column when the pragma #prettylst:leadingspaces:ignore
is used. The pragma #prettylst:leadingspaces:trim restore normal space triming.

Replace the deprecated PREVAR for PREVARGT.

Add new DOMAIN tags

Add new DEITY tags

Add new RACE tags

PCGEN now check to see if existing comment line exists before adding a new one. Existing
header lines are genereted to reflect the curent TAGs in used.

Add new SKILL tags

Add new SPELL tags

Add new CLASS tags

=head2 v1.14 -- 2002.06.08

The files are now written if there is no other change then the CF corrections

Add the internal WriteLog function

Change the order for the RACE filetype as requested by Andrew McDougall (tir-gwaith)

RACE filetype: convert INIT:xx to BONUS:COMBAT|Initiative|xx and deprecate INIT

CLASS filetype: convert ADD:INIT|xx to BONUS:COMBAT|Initiative|xx and deprecate ADD:INIT

RACE filetype: added code to remove AC and replace it by BONUS:COMBAT|AC|xx|TYPE=NaturalArmor
when needed

EQUIPMENT filetype: added code to replace all the Cost by COST

Add code to deal with .MOD in all the files except CLASS and CLASSSPELL

=head2 v1.13 -- 2002.05.11

Now parse the BONUS tags.

Change the sort of the CLASS Level lines. Multiple tags on the same type are no
longer on the same column.

Skip empty files.

=head2 v1.12 -- 2002.03.23

Add code to replace the BONUS:FEAT, BONUS:VFEAT and FEAT in the EQUIPMENT by
VFEAT.

Remove the empty columns for the CLASS lines.

Added the parse_tag function for all the tags.

Deprecate the NATURALARMOR tag and added code to convert to
BONUS:COMBAT|AC|x|Type=Natural

=head2 v1.11 -- 2002.03.07

Add code to deal with the CR-CR-LF stuff in the .lst files

The comment generated by PCGEN now contains the CVS Revision and Author tags

The CLASS level lines have a new sort order.

Remove CCOST and RREPLACE from tags (these were typos)

Change findfullpath for the new behavior of the @ character in file paths.

Added code to check the GAME and TYPE tags in the .PCC files

Added code to verify the existance of every file for each .PCC

=head2 v1.10 -- 2002.02.27

Bug fixes

=head2 v1.09 -- 2002.02.20

Add a optional check to see if a TAG has been put in a fixed column. If such ':' is
found in one of the fixed column, a warning is printed.

Check for all file extention to find the unlinked files that are not .lst

Add support fot the E<quot>pragmaE<quot> tag #EXTRAFILE

Add code to convert SKILL to BONUS:SKILL in RACE files

The DEITY tag in the CLASS files was deprecated

=head2 v1.08 -- 2002.02.17

Only write the .pcc files that have an extra 0x0d character or white spaces at the
end of the line.

Add support for the new SOURCEPAGE, SOURCEWEB, SOURCELONG and SOURCESHORT tags.

Add conversion code that replace the SOURCE:p. tags by SOURCEPAGE:p. tags.

Add conversion code that remove the ROOT tags in the SKILL files and add the
new format of the TYPE tag.

Remove the ROOT tag from the SKILL filetype. This tag is now deprecate.

Romove any quote found.

=head2 v1.07 -- 2002.02.08

Bug with the WEAPONBONUS tag being there twice for the RACE filetype

Add code to detect if one of the tags is there more then once for
a particular filetype

The odd end of lines (CR-CR-LF) are striped when the files that get rewriten

Produce a list of files not found in the .PCC files

=head2 v1.06 -- 2002.02.07

Add support for CLASSSPELL

Add support for TEMPLATE

Add support for WEAPONPROF

The script now adds a dummy SOURCE:p. tag in some files when none are found.

=head2 v1.05 -- 2002.02.06

Add support for CLASSSKILL files (OK, this one was not very hard...)

Add support for DIETY files

Add support for DOMAIN files

Add support for FEAT files

Add support for LANGUAGE files

Add support for SKILL files

Add support for SPELL files

Unknown tags are kept (including duplicates)

=head2 v1.04 -- 2002.02.05

Add support for RACE files

Add support for EQUIMOD files

Most files are now parse by a Generic parser

Unknown tags are kept (including duplicates)

=head2 v1.03 -- 2002.02.03

Change the sort order for the additionnal lines

=head2 v1.02 -- 2002.02.03

No more empty white spaces between the columns in for the level advancement lines


=head2 v1.01 -- 2002.02.02

Add support for the CLASS files

Check and remove extra space at the end of each tab separated TAG

Add special case for the ADD:adlib tags

=head2 v1.00 -- 2002.01.27

First working version. Only the EQUIPMENT file are supported.
