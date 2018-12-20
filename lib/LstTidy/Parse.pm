package LstTidy::Parse;

use strict;
use warnings;
use English;

use Carp;


# expand library path so we can find LstTidy modules
use File::Basename qw(dirname);
use Cwd  qw(abs_path);
use lib dirname(dirname abs_path $0);

use LstTidy::Convert qw(doTagConversions);
use LstTidy::LogFactory qw(getLogger);
use LstTidy::Options qw(getOption);
use LstTidy::Tag;

# Constants for the master_line_type
use constant {
   # Line importance (Mode)
   MAIN           => 1, # Main line type for the file
   SUB            => 2, # Sub line type, must be linked to a MAIN
   SINGLE         => 3, # Idependant line type
   COMMENT        => 4, # Comment or empty line.

   # Line formatting option (Format)
   LINE           => 1, # Every line formatted by itself
   BLOCK          => 2, # Lines formatted as a block
   FIRST_COLUMN   => 3, # Only the first column of the block gets aligned

   # Line header option (Header)
   NO_HEADER      => 1, # No header
   LINE_HEADER    => 2, # One header before each line
   BLOCK_HEADER   => 3, # One header for the block

   # Standard YES NO constants
   NO             => 0,
   YES            => 1,

   # The defined (non-standard) size of a tab
   TABSIZE        => 6,
};

# List of keywords Jep functions names. The fourth and fifth rows are for
# functions defined by the PCGen libraries that do not exists in
# the standard Jep library.
my %isJepFunction = map { $_ => 1 } qw(
   sin     cos     tan     asin    acos    atan    atan2   sinh
   cosh    tanh    asinh   acosh   atanh   ln      log     exp
   abs     rand    mod     sqrt    sum     if      str

   ceil    cl      classlevel      count   floor   min
   max     roll    skillinfo       var     mastervar       APPLIEDAS
);

# Definition of a valid Jep identifiers. Note that all functions are
# identifiers followed by a parentesis.
my $isIdentRegex = qr{ [a-z_][a-z_0-9]* }xmsi;

# Valid Jep operators
my $isOperatorsText = join( '|', map { quotemeta } (
      '^', '%',  '/',  '*',  '+',  '-', '<=', '>=', '<', '>', '!=', '==', '&&', '||', '=',  '!', '.',
   )
);

my $isOperatorRegex = qr{ $isOperatorsText }xms;

my $isNumberRegex = qr{ (?: \d+ (?: [.] \d* )? ) | (?: [.] \d+ ) }xms;

# Will hold the tags that do not have defined headers for each linetype.
my %missing_headers;

# Limited choice tags
my %tagFixValue = (

   ALLOWBASECLASS       => { YES => 1, NO => 1 },
   DESCISIP             => { YES => 1, NO => 1 },
   EXCLUSIVE            => { YES => 1, NO => 1 },
   FREE                 => { YES => 1, NO => 1 },
   HASSUBCLASS          => { YES => 1, NO => 1 },
   HASSUBSTITUTIONLEVEL => { YES => 1, NO => 1 },
   ISD20                => { YES => 1, NO => 1 },
   ISLICENSED           => { YES => 1, NO => 1 },
   ISMATURE             => { YES => 1, NO => 1 },
   ISOGL                => { YES => 1, NO => 1 },
   MEMORIZE             => { YES => 1, NO => 1 },
   MODTOSKILLS          => { YES => 1, NO => 1 },
   MULT                 => { YES => 1, NO => 1 },
   NAMEISPI             => { YES => 1, NO => 1 },
   PRESPELLBOOK         => { YES => 1, NO => 1 },
   RACIAL               => { YES => 1, NO => 1 },
   REMOVABLE            => { YES => 1, NO => 1 },
   RESIZE               => { YES => 1, NO => 1 },
   SHOWINMENU           => { YES => 1, NO => 1 },
   SPELLBOOK            => { YES => 1, NO => 1 },
   STACK                => { YES => 1, NO => 1 },
   USEMASTERSKILL       => { YES => 1, NO => 1 },
   USEUNTRAINED         => { YES => 1, NO => 1 },

   ACHECK               => { map { $_ => 1 } qw( YES NO WEIGHT PROFICIENT DOUBLE ) },
   APPLY                => { map { $_ => 1 } qw( INSTANT PERMANENT ) },
   FORMATCAT            => { map { $_ => 1 } qw( FRONT MIDDLE PARENS ) },
   MODS                 => { map { $_ => 1 } qw( YES NO REQUIRED ) },
   TIMEUNIT             => { map { $_ => 1 } qw( Year Month Week Day Hour Minute Round Encounter Charges ) },
   VISIBLE              => { map { $_ => 1 } qw( YES NO EXPORT DISPLAY QUALIFY CSHEET GUI ALWAYS ) },

   # See updateValidity for the values of these keys
   # BONUSSPELLSTAT       
   # SPELLSTAT            
   # ALIGN                
   # PREALIGN             
   # KEYSTAT              

);

# These operations convert the id of tags with subTags to contain the embeded :
my %tagProcessor = (
   ADD         => \&LstTidy::Convert::convertAddTags,
   AUTO        => \&LstTidy::Parse::parseAutoTag,
   BONUS       => \&LstTidy::Parse::parseSubTag,
   PROFICIENCY => \&LstTidy::Parse::parseSubTag,
   QUALIFY     => \&LstTidy::Parse::parseSubTag,
   SPELLLEVEL  => \&LstTidy::Parse::parseSubTag,
   SPELLKNOWN  => \&LstTidy::Parse::parseSubTag,
);

# This hash is used to convert 1 character choices to proper fix values.
my %tagProperValue = (
   'Y'     =>  'YES',
   'N'     =>  'NO',
   'W'     =>  'WEIGHT',
   'Q'     =>  'QUALIFY',
   'P'     =>  'PROFICIENT',
   'R'     =>  'REQUIRED',
   'true'  =>  'YES',
   'false' =>  'NO',
);

# List of default for values defined in system files
my @validSystemAlignments = qw(LG LN LE NG TN NE CG CN CE NONE Deity);

my @validSystemCheckNames = qw(Fortitude Reflex Will);

my @validSystemGameModes = (
   # Main PCGen Release
   qw(35e 3e Deadlands Darwins_World_2 FantasyCraft Gaslight Killshot LoE Modern
   Pathfinder Pathfinder_PFS Sidewinder Spycraft Xcrawl OSRIC),

   # Third Party/Homebrew Support
   qw(DnD CMP_D20_Fantasy_v30e CMP_D20_Fantasy_v35e CMP_D20_Fantasy_v35e_Kalamar
   CMP_D20_Modern CMP_DnD_Blackmoor CMP_DnD_Dragonlance CMP_DnD_Eberron
   CMP_DnD_Forgotten_Realms_v30e CMP_DnD_Forgotten_Realms_v35e
   CMP_DnD_Oriental_Adventures_v30e CMP_DnD_Oriental_Adventures_v35e CMP_HARP
   SovereignStoneD20) );

# This meeds replaced, we should be getting this information from the STATS file.
my @validSystemStats = qw(
   STR DEX CON INT WIS CHA NOB FAM PFM

   DVR WEA AGI QUI SDI REA INS PRE
);

my @validSystemVarNames = qw(
   ACTIONDICE                    ACTIONDIEBONUS          ACTIONDIETYPE
   Action                        ActionLVL               BUDGETPOINTS
   CURRENTVEHICLEMODS            ClassDefense            DamageThreshold
   EDUCATION                     EDUCATIONMISC           FAVORCHECK
   FIGHTINGDEFENSIVELYAC         FightingDefensivelyAC   FightingDefensivelyACBonus
   GADGETPOINTS                  INITCOMP                INSPIRATION
   INSPIRATIONMISC               LOADSCORE               MAXLEVELSTAT
   MAXVEHICLEMODS                MISSIONBUDGET           MUSCLE
   MXDXEN                        NATIVELANGUAGES         NORMALMOUNT
   OFFHANDLIGHTBONUS             PSIONLEVEL              Reputation
   TWOHANDDAMAGEDIVISOR          TotalDefenseAC          TotalDefenseACBonus
   UseAlternateDamage            VEHICLECRUISINGMPH      VEHICLEDEFENSE
   VEHICLEHANDLING               VEHICLEHARDNESS         VEHICLESPEED
   VEHICLETOPMPH                 VEHICLEWOUNDPOINTS      Wealth
   CR                            CL                      ECL
   SynergyBonus                  NoTypeProficiencies     NormalMount
   CHOICE                        BAB                     NormalFollower

   Action                        ActionLVL               ArmorQui
   ClassDefense                  DamageThreshold         DenseMuscle
   FIGHTINGDEFENSIVELYACBONUS    Giantism                INITCOMP
   LOADSCORE                     MAXLEVELSTAT            MUSCLE
   MXDXEN                        Mount                   OFFHANDLIGHTBONUS
   TOTALDEFENSEACBONUS           TWOHANDDAMAGEDIVISOR

   ACCHECK                       ARMORACCHECK            BASESPELLSTAT
   CASTERLEVEL                   INITIATIVEMISC          INITIATIVEMOD
   MOVEBASE                      SHIELDACCHECK           SIZE
   SKILLRANK                     SKILLTOTAL              SPELLFAILURE
   SR                            TL                      LIST
   MASTERVAR                     APPLIEDAS
);


# Valid filetype are the only ones that will be parsed Some filetype are valid
# but not parsed yet (no function name)
my %parsableFileType = (
   'ABILITY'         => \&parseFile,
   'ABILITYCATEGORY' => \&parseFile,
   'BIOSET'          => \&parseFile,
   'CLASS'           => \&parseFile,
   'COMPANIONMOD'    => \&parseFile,
   'DEITY'           => \&parseFile,
   'DOMAIN'          => \&parseFile,
   'EQUIPMENT'       => \&parseFile,
   'EQUIPMOD'        => \&parseFile,
   'FEAT'            => \&parseFile,
   'INFOTEXT'        => 0,
   'KIT'             => \&parseFile,
   'LANGUAGE'        => \&parseFile,
   'LSTEXCLUDE'      => 0,
   'PCC'             => 1,
   'RACE'            => \&parseFile,
   'SKILL'           => \&parseFile,
   'SOURCELONG'      => 0,
   'SOURCESHORT'     => 0,
   'SOURCEWEB'       => 0,
   'SOURCEDATE'      => 0,
   'SOURCELINK'      => 0,
   'SPELL'           => \&parseFile,
   'TEMPLATE'        => \&parseFile,
   'WEAPONPROF'      => \&parseFile,
   'ARMORPROF'       => \&parseFile,
   'SHIELDPROF'      => \&parseFile,
   'VARIABLE'        => \&parseFile,
   'DATACONTROL'     => \&parseFile,
   'GLOBALMOD'       => \&parseFile,
   '#EXTRAFILE'      => 1,
   'SAVE'            => \&parseFile,
   'STAT'            => \&parseFile,
   'ALIGNMENT'       => \&parseFile,
);

# Header use for the comment for each of the tag used in the script
my %tagheader = (
   default => {
      '000ClassName'                => '# Class Name',
      '001SkillName'                => 'Class Skills (All skills are seperated by a pipe delimiter \'|\')',

      '000DomainName'               => '# Domain Name',
      '001DomainEffect'             => 'Description',

      'DESC'                        => 'Description',

      '000AbilityName'              => '# Ability Name',
      '000FeatName'                 => '# Feat Name',

      '000AbilityCategory',         => '# Ability Category Name',

      '000LanguageName'             => '# Language',

      'FAVCLASS'                    => 'Favored Class',
      'XTRASKILLPTSPERLVL'          => 'Skills/Level',
      'STARTFEATS'                  => 'Starting Feats',

      '000SkillName'                => '# Skill Name',

      'KEYSTAT'                     => 'Key Stat',
      'EXCLUSIVE'                   => 'Exclusive?',
      'USEUNTRAINED'                => 'Untrained?',
      'SITUATION'                   => 'Situational Skill',

      '000TemplateName'             => '# Template Name',

      '000WeaponName'               => '# Weapon Name',
      '000ArmorName'                => '# Armor Name',
      '000ShieldName'               => '# Shield Name',

      '000VariableName'             => '# Name',
      '000GlobalmodName'            => '# Name',
      '000DatacontrolName'          => '# Name',
      '000SaveName'                 => '# Name',
      '000StatName'                 => '# Name',
      '000AlignmentName'            => '# Name',
      'DATAFORMAT'                  => 'Dataformat',
      'REQUIRED'                    => 'Required',
      'SELECTABLE'                  => 'Selectable',
      'DISPLAYNAME'                 => 'Displayname',

      'ABILITY'                     => 'Ability',
      'ACCHECK'                     => 'AC Penalty Check',
      'ACHECK'                      => 'Skill Penalty?',
      'ADD'                         => 'Add',
      'ADD:EQUIP'                   => 'Add Equipment',
      'ADD:FEAT'                    => 'Add Feat',
      'ADD:SAB'                     => 'Add Special Ability',
      'ADD:SKILL'                   => 'Add Skill',
      'ADD:TEMPLATE'                => 'Add Template',
      'ADDDOMAINS'                  => 'Add Divine Domain',
      'ADDSPELLLEVEL'               => 'Add Spell Lvl',
      'APPLIEDNAME'                 => 'Applied Name',
      'AGE'                         => 'Age',
      'AGESET'                      => 'Age Set',
      'ALIGN'                       => 'Align',
      'ALTCRITMULT'                 => 'Alt Crit Mult',
      'ALTCRITRANGE'                => 'Alt Crit Range',
      'ALTDAMAGE'                   => 'Alt Damage',
      'ALTEQMOD'                    => 'Alt EQModifier',
      'ALTTYPE'                     => 'Alt Type',
      'ATTACKCYCLE'                 => 'Attack Cycle',
      'ASPECT'                      => 'Aspects',
      'AUTO'                        => 'Auto',
      'AUTO:ARMORPROF'              => 'Auto Armor Prof',
      'AUTO:EQUIP'                  => 'Auto Equip',
      'AUTO:FEAT'                   => 'Auto Feat',
      'AUTO:LANG'                   => 'Auto Language',
      'AUTO:SHIELDPROF'             => 'Auto Shield Prof',
      'AUTO:WEAPONPROF'             => 'Auto Weapon Prof',
      'BASEQTY'                     => 'Base Quantity',
      'BENEFIT'                     => 'Benefits',
      'BONUS'                       => 'Bonus',
      'BONUSSPELLSTAT'              => 'Spell Stat Bonus',
      'BONUS:ABILITYPOOL'           => 'Bonus Ability Pool',
      'BONUS:CASTERLEVEL'           => 'Caster level',
      'BONUS:CHECKS'                => 'Save checks bonus',
      'BONUS:CONCENTRATION'         => 'Concentration bonus',
      'BONUS:SAVE'                  => 'Save bonus',
      'BONUS:COMBAT'                => 'Combat bonus',
      'BONUS:DAMAGE'                => 'Weapon damage bonus',
      'BONUS:DOMAIN'                => 'Add domain number',
      'BONUS:DC'                    => 'Bonus DC',
      'BONUS:DR'                    => 'Bonus DR',
      'BONUS:EQMARMOR'              => 'Bonus Armor Mods',
      'BONUS:EQM'                   => 'Bonus Equip Mods',
      'BONUS:EQMWEAPON'             => 'Bonus Weapon Mods',
      'BONUS:ESIZE'                 => 'Modify size',
      'BONUS:FEAT'                  => 'Number of Feats',
      'BONUS:FOLLOWERS'             => 'Number of Followers',
      'BONUS:HD'                    => 'Modify HD type',
      'BONUS:HP'                    => 'Bonus to HP',
      'BONUS:ITEMCOST'              => 'Modify the item cost',
      'BONUS:LANGUAGES'             => 'Bonus language',
      'BONUS:MISC'                  => 'Misc bonus',
      'BONUS:MOVEADD'               => 'Add to base move',
      'BONUS:MOVEMULT'              => 'Multiply base move',
      'BONUS:POSTMOVEADD'           => 'Add to magical move',
      'BONUS:PCLEVEL'               => 'Caster level bonus',
      'BONUS:POSTRANGEADD'          => 'Bonus to Range',
      'BONUS:RANGEADD'              => 'Bonus to base range',
      'BONUS:RANGEMULT'             => '% bonus to range',
      'BONUS:REPUTATION'            => 'Bonus to Reputation',
      'BONUS:SIZEMOD'               => 'Adjust PC Size',
      'BONUS:SKILL'                 => 'Bonus to skill',
      'BONUS:SITUATION'             => 'Bonus to Situation',
      'BONUS:SKILLPOINTS'           => 'Bonus to skill point/L',
      'BONUS:SKILLPOOL'             => 'Bonus to skill point for a level',
      'BONUS:SKILLRANK'             => 'Bonus to skill rank',
      'BONUS:SLOTS'                 => 'Bonus to nb of slots',
      'BONUS:SPELL'                 => 'Bonus to spell attribute',
      'BONUS:SPECIALTYSPELLKNOWN'   => 'Bonus Specialty spells',
      'BONUS:SPELLCAST'             => 'Bonus to spell cast/day',
      'BONUS:SPELLCASTMULT'         => 'Multiply spell cast/day',
      'BONUS:SPELLKNOWN'            => 'Bonus to spell known/L',
      'BONUS:STAT'                  => 'Stat bonus',
      'BONUS:TOHIT'                 => 'Attack roll bonus',
      'BONUS:UDAM'                  => 'Unarmed Damage Level bonus',
      'BONUS:VAR'                   => 'Modify VAR',
      'BONUS:VISION'                => 'Add to vision',
      'BONUS:WEAPON'                => 'Weapon prop. bonus',
      'BONUS:WEAPONPROF'            => 'Weapon prof. bonus',
      'BONUS:WIELDCATEGORY'         => 'Wield Category bonus',
      'TEMPBONUS'                   => 'Temporary Bonus',
      'CAST'                        => 'Cast',
      'CASTAS'                      => 'Cast As',
      'CASTTIME:.CLEAR'             => 'Clear Casting Time',
      'CASTTIME'                    => 'Casting Time',
      'CATEGORY'                    => 'Category of Ability',
      'CCSKILL:.CLEAR'              => 'Remove Cross-Class Skill',
      'CCSKILL'                     => 'Cross-Class Skill',
      'CHANGEPROF'                  => 'Change Weapon Prof. Category',
      'CHOOSE'                      => 'Choose',
      'CLASSES'                     => 'Classes',
      'COMPANIONLIST'               => 'Allowed Companions',
      'COMPS'                       => 'Components',
      'CONTAINS'                    => 'Contains',
      'COST'                        => 'Cost',
      'CR'                          => 'Challenge Rating',
      'CRMOD'                       => 'CR Modifier',
      'CRITMULT'                    => 'Crit Mult',
      'CRITRANGE'                   => 'Crit Range',
      'CSKILL:.CLEAR'               => 'Remove Class Skill',
      'CSKILL'                      => 'Class Skill',
      'CT'                          => 'Casting Threshold',
      'DAMAGE'                      => 'Damage',
      'DEF'                         => 'Def',
      'DEFINE'                      => 'Define',
      'DEFINESTAT'                  => 'Define Stat',
      'DEITY'                       => 'Deity',
      'DESC'                        => 'Description',
      'DESC:.CLEAR'                 => 'Clear Description',
      'DESCISPI'                    => 'Desc is PI?',
      'DESCRIPTOR:.CLEAR'           => 'Clear Spell Descriptors',
      'DESCRIPTOR'                  => 'Descriptor',
      'DOMAIN'                      => 'Domain',
      'DOMAINS'                     => 'Domains',
      'DONOTADD'                    => 'Do Not Add',
      'DR:.CLEAR'                   => 'Remove Damage Reduction',
      'DR'                          => 'Damage Reduction',
      'DURATION:.CLEAR'             => 'Clear Duration',
      'DURATION'                    => 'Duration',
      'EQMOD'                       => 'Modifier',
      'EXCLASS'                     => 'Ex Class',
      'EXPLANATION'                 => 'Explanation',
      'FACE'                        => 'Face/Space',
      'FACT:Abb'                    => 'Abbreviation',
      'FACT:SpellType'              => 'Spell Type',
      'FEAT'                        => 'Feat',
      'FEATAUTO'                    => 'Feat Auto',
      'FOLLOWERS'                   => 'Allow Follower',
      'FREE'                        => 'Free',
      'FUMBLERANGE'                 => 'Fumble Range',
      'GENDER'                      => 'Gender',
      'HANDS'                       => 'Nb Hands',
      'HASSUBCLASS'                 => 'Subclass?',
      'ALLOWBASECLASS'              => 'Base class as subclass?',
      'HD'                          => 'Hit Dice',
      'HEIGHT'                      => 'Height',
      'HITDIE'                      => 'Hit Dice Size',
      'HITDICEADVANCEMENT'          => 'Hit Dice Advancement',
      'HITDICESIZE'                 => 'Hit Dice Size',
      'ITEM'                        => 'Item',
      'KEY'                         => 'Unique Key',
      'KIT'                         => 'Apply Kit',
      'KNOWN'                       => 'Known',
      'KNOWNSPELLS'                 => 'Automatically Known Spell Levels',
      'LANGBONUS'                   => 'Bonus Languages',
      'LANGBONUS:.CLEAR'            => 'Clear Bonus Languages',
      'LEGS'                        => 'Nb Legs',
      'LEVEL'                       => 'Level',
      'LEVELADJUSTMENT'             => 'Level Adjustment',
      'MAXCOST'                     => 'Maximum Cost',
      'MAXDEX'                      => 'Maximum DEX Bonus',
      'MAXLEVEL'                    => 'Max Level',
      'MEMORIZE'                    => 'Memorize',
      'MFEAT'                       => 'Default Monster Feat',
      'MONSKILL'                    => 'Monster Initial Skill Points',
      'MOVE'                        => 'Move',
      'MOVECLONE'                   => 'Clone Movement',
      'MULT'                        => 'Multiple?',
      'NAMEISPI'                    => 'Product Identity?',
      'NATURALARMOR'                => 'Natural Armor',
      'NATURALATTACKS'              => 'Natural Attacks',
      'NUMPAGES'                    => 'Number of Pages',
      'OUTPUTNAME'                  => 'Output Name',
      'PAGEUSAGE'                   => 'Page Usage',
      'PANTHEON'                    => 'Pantheon',
      'PPCOST'                      => 'Power Points',
      'PRE:.CLEAR'                  => 'Clear Prereq.',
      'PREABILITY'                  => 'Required Ability',
      '!PREABILITY'                 => 'Restricted Ability',
      'PREAGESET'                   => 'Minimum Age',
      '!PREAGESET'                  => 'Maximum Age',
      'PREALIGN'                    => 'Required AL',
      '!PREALIGN'                   => 'Restricted AL',
      'PREATT'                      => 'Req. Att.',
      'PREARMORPROF'                => 'Req. Armor Prof.',
      '!PREARMORPROF'               => 'Prohibited Armor Prof.',
      'PREBASESIZEEQ'               => 'Required Base Size',
      '!PREBASESIZEEQ'              => 'Prohibited Base Size',
      'PREBASESIZEGT'               => 'Minimum Base Size',
      'PREBASESIZEGTEQ'             => 'Minimum Size',
      'PREBASESIZELT'               => 'Maximum Base Size',
      'PREBASESIZELTEQ'             => 'Maximum Size',
      'PREBASESIZENEQ'              => 'Prohibited Base Size',
      'PRECAMPAIGN'                 => 'Required Campaign(s)',
      '!PRECAMPAIGN'                => 'Prohibited Campaign(s)',
      'PRECHECK'                    => 'Required Check',
      '!PRECHECK'                   => 'Prohibited Check',
      'PRECHECKBASE'                => 'Required Check Base',
      'PRECITY'                     => 'Required City',
      '!PRECITY'                    => 'Prohibited City',
      'PRECLASS'                    => 'Required Class',
      '!PRECLASS'                   => 'Prohibited Class',
      'PRECLASSLEVELMAX'            => 'Maximum Level Allowed',
      '!PRECLASSLEVELMAX'           => 'Should use PRECLASS',
      'PRECSKILL'                   => 'Required Class Skill',
      '!PRECSKILL'                  => 'Prohibited Class SKill',
      'PREDEITY'                    => 'Required Deity',
      '!PREDEITY'                   => 'Prohibited Deity',
      'PREDEITYDOMAIN'              => 'Required Deitys Domain',
      'PREDOMAIN'                   => 'Required Domain',
      '!PREDOMAIN'                  => 'Prohibited Domain',
      'PREDSIDEPTS'                 => 'Req. Dark Side',
      'PREDR'                       => 'Req. Damage Resistance',
      '!PREDR'                      => 'Prohibited Damage Resistance',
      'PREEQUIP'                    => 'Req. Equipement',
      'PREEQMOD'                    => 'Req. Equipment Mod.',
      '!PREEQMOD'                   => 'Prohibited Equipment Mod.',
      'PREFEAT'                     => 'Required Feat',
      '!PREFEAT'                    => 'Prohibited Feat',
      'PREGENDER'                   => 'Required Gender',
      '!PREGENDER'                  => 'Prohibited Gender',
      'PREHANDSEQ'                  => 'Req. nb of Hands',
      'PREHANDSGT'                  => 'Min. nb of Hands',
      'PREHANDSGTEQ'                => 'Min. nb of Hands',
      'PREHD'                       => 'Required Hit Dice',
      'PREHP'                       => 'Required Hit Points',
      'PREITEM'                     => 'Required Item',
      'PRELANG'                     => 'Required Language',
      'PRELEVEL'                    => 'Required Lvl',
      'PRELEVELMAX'                 => 'Maximum Level',
      'PREKIT'                      => 'Required Kit',
      '!PREKIT'                     => 'Prohibited Kit',
      'PREMOVE'                     => 'Required Movement Rate',
      '!PREMOVE'                    => 'Prohibited Movement Rate',
      'PREMULT'                     => 'Multiple Requirements',
      '!PREMULT'                    => 'Multiple Prohibitions',
      'PREPCLEVEL'                  => 'Required Non-Monster Lvl',
      'PREPROFWITHARMOR'            => 'Required Armor Proficiencies',
      '!PREPROFWITHARMOR'           => 'Prohibited Armor Proficiencies',
      'PREPROFWITHSHIELD'           => 'Required Shield Proficiencies',
      '!PREPROFWITHSHIELD'          => 'Prohbited Shield Proficiencies',
      'PRERACE'                     => 'Required Race',
      '!PRERACE'                    => 'Prohibited Race',
      'PRERACETYPE'                 => 'Reg. Race Type',
      'PREREACH'                    => 'Minimum Reach',
      'PREREACHEQ'                  => 'Required Reach',
      'PREREACHGT'                  => 'Minimum Reach',
      'PREREGION'                   => 'Required Region',
      '!PREREGION'                  => 'Prohibited Region',
      'PRERULE'                     => 'Req. Rule (in options)',
      'PRESA'                       => 'Req. Special Ability',
      '!PRESA'                      => 'Prohibite Special Ability',
      'PRESHIELDPROF'               => 'Req. Shield Prof.',
      '!PRESHIELDPROF'              => 'Prohibited Shield Prof.',
      'PRESIZEEQ'                   => 'Required Size',
      'PRESIZEGT'                   => 'Must be Larger',
      'PRESIZEGTEQ'                 => 'Minimum Size',
      'PRESIZELT'                   => 'Must be Smaller',
      'PRESIZELTEQ'                 => 'Maximum Size',
      'PRESKILL'                    => 'Required Skill',
      '!PRESITUATION'               => 'Prohibited Situation',
      'PRESITUATION'                => 'Required Situation',
      '!PRESKILL'                   => 'Prohibited Skill',
      'PRESKILLMULT'                => 'Special Required Skill',
      'PRESKILLTOT'                 => 'Total Skill Points Req.',
      'PRESPELL'                    => 'Req. Known Spell',
      'PRESPELLBOOK'                => 'Req. Spellbook',
      'PRESPELLBOOK'                => 'Req. Spellbook',
      'PRESPELLCAST'                => 'Required Casting Type',
      '!PRESPELLCAST'               => 'Prohibited Casting Type',
      'PRESPELLDESCRIPTOR'          => 'Required Spell Descriptor',
      '!PRESPELLDESCRIPTOR'         => 'Prohibited Spell Descriptor',
      'PRESPELLSCHOOL'              => 'Required Spell School',
      'PRESPELLSCHOOLSUB'           => 'Required Sub-school',
      '!PRESPELLSCHOOLSUB'          => 'Prohibited Sub-school',
      'PRESPELLTYPE'                => 'Req. Spell Type',
      'PRESREQ'                     => 'Req. Spell Resist',
      'PRESRGT'                     => 'SR Must be Greater',
      'PRESRGTEQ'                   => 'SR Min. Value',
      'PRESRLT'                     => 'SR Must be Lower',
      'PRESRLTEQ'                   => 'SR Max. Value',
      'PRESRNEQ'                    => 'Prohibited SR Value',
      'PRESTAT'                     => 'Required Stat',
      '!PRESTAT',                   => 'Prohibited Stat',
      'PRESUBCLASS'                 => 'Required Subclass',
      '!PRESUBCLASS'                => 'Prohibited Subclass',
      'PRETEMPLATE'                 => 'Required Template',
      '!PRETEMPLATE'                => 'Prohibited Template',
      'PRETEXT'                     => 'Required Text',
      'PRETYPE'                     => 'Required Type',
      '!PRETYPE'                    => 'Prohibited Type',
      'PREVAREQ'                    => 'Required Var. value',
      '!PREVAREQ'                   => 'Prohibited Var. Value',
      'PREVARGT'                    => 'Var. Must Be Grater',
      'PREVARGTEQ'                  => 'Var. Min. Value',
      'PREVARLT'                    => 'Var. Must Be Lower',
      'PREVARLTEQ'                  => 'Var. Max. Value',
      'PREVARNEQ'                   => 'Prohibited Var. Value',
      'PREVISION'                   => 'Required Vision',
      '!PREVISION'                  => 'Prohibited Vision',
      'PREWEAPONPROF'               => 'Req. Weapond Prof.',
      '!PREWEAPONPROF'              => 'Prohibited Weapond Prof.',
      'PREWIELD'                    => 'Required Wield Category',
      '!PREWIELD'                   => 'Prohibited Wield Category',
      'PROFICIENCY:WEAPON'          => 'Required Weapon Proficiency',
      'PROFICIENCY:ARMOR'           => 'Required Armor Proficiency',
      'PROFICIENCY:SHIELD'          => 'Required Shield Proficiency',
      'PROHIBITED'                  => 'Spell Scoll Prohibited',
      'PROHIBITSPELL'               => 'Group of Prohibited Spells',
      'QUALIFY:CLASS'               => 'Qualify for Class',
      'QUALIFY:DEITY'               => 'Qualify for Deity',
      'QUALIFY:DOMAIN'              => 'Qualify for Domain',
      'QUALIFY:EQUIPMENT'           => 'Qualify for Equipment',
      'QUALIFY:EQMOD'               => 'Qualify for Equip Modifier',
      'QUALIFY:FEAT'                => 'Qualify for Feat',
      'QUALIFY:RACE'                => 'Qualify for Race',
      'QUALIFY:SPELL'               => 'Qualify for Spell',
      'QUALIFY:SKILL'               => 'Qualify for Skill',
      'QUALIFY:TEMPLATE'            => 'Qualify for Template',
      'QUALIFY:WEAPONPROF'          => 'Qualify for Weapon Proficiency',
      'RACESUBTYPE:.CLEAR'          => 'Clear Racial Subtype',
      'RACESUBTYPE'                 => 'Race Subtype',
      'RACETYPE:.CLEAR'             => 'Clear Main Racial Type',
      'RACETYPE'                    => 'Main Race Type',
      'RANGE:.CLEAR'                => 'Clear Range',
      'RANGE'                       => 'Range',
      'RATEOFFIRE'                  => 'Rate of Fire',
      'REACH'                       => 'Reach',
      'REACHMULT'                   => 'Reach Multiplier',
      'REGION'                      => 'Region',
      'REPEATLEVEL'                 => 'Repeat this Level',
      'REMOVABLE'                   => 'Removable?',
      'REMOVE'                      => 'Remove Object',
      'REP'                         => 'Reputation',
      'ROLE'                        => 'Monster Role',
      'SA'                          => 'Special Ability',
      'SA:.CLEAR'                   => 'Clear SAs',
      'SAB:.CLEAR'                  => 'Clear Special ABility',
      'SAB'                         => 'Special ABility',
      'SAVEINFO'                    => 'Save Info',
      'SCHOOL:.CLEAR'               => 'Clear School',
      'SCHOOL'                      => 'School',
      'SELECT'                      => 'Selections',
      'SERVESAS'                    => 'Serves As',
      'SIZE'                        => 'Size',
      'SKILLLIST'                   => 'Use Class Skill List',
      'SOURCE'                      => 'Source Index',
      'SOURCEPAGE:.CLEAR'           => 'Clear Source Page',
      'SOURCEPAGE'                  => 'Source Page',
      'SOURCELONG'                  => 'Source, Long Desc.',
      'SOURCESHORT'                 => 'Source, Short Desc.',
      'SOURCEWEB'                   => 'Source URI',
      'SOURCEDATE'                  => 'Source Pub. Date',
      'SOURCELINK'                  => 'Source Pub Link',
      'SPELLBOOK'                   => 'Spellbook',
      'SPELLFAILURE'                => '% of Spell Failure',
      'SPELLLIST'                   => 'Use Spell List',
      'SPELLKNOWN:CLASS'            => 'List of Known Class Spells by Level',
      'SPELLKNOWN:DOMAIN'           => 'List of Known Domain Spells by Level',
      'SPELLLEVEL:CLASS'            => 'List of Class Spells by Level',
      'SPELLLEVEL:DOMAIN'           => 'List of Domain Spells by Level',
      'SPELLRES'                    => 'Spell Resistance',
      'SPELL'                       => 'Deprecated Spell tag',
      'SPELLS'                      => 'Innate Spells',
      'SPELLSTAT'                   => 'Spell Stat',
      'SPELLTYPE'                   => 'Spell Type',
      'SPROP:.CLEAR'                => 'Clear Special Property',
      'SPROP'                       => 'Special Property',
      'SR'                          => 'Spell Res.',
      'STACK'                       => 'Stackable?',
      'STARTSKILLPTS'               => 'Skill Pts/Lvl',
      'STAT'                        => 'Key Attribute',
      'SUBCLASSLEVEL'               => 'Subclass Level',
      'SUBRACE'                     => 'Subrace',
      'SUBREGION'                   => 'Subregion',
      'SUBSCHOOL'                   => 'Sub-School',
      'SUBSTITUTIONLEVEL'           => 'Substitution Level',
      'SYNERGY'                     => 'Synergy Skill',
      'TARGETAREA:.CLEAR'           => 'Clear Target Area or Effect',
      'TARGETAREA'                  => 'Target Area or Effect',
      'TEMPDESC'                    => 'Temporary effect description',
      'TEMPLATE'                    => 'Template',
      'TEMPLATE:.CLEAR'             => 'Clear Templates',
      'TYPE'                        => 'Type',
      'TYPE:.CLEAR'                 => 'Clear Types',
      'UDAM'                        => 'Unarmed Damage',
      'UMULT'                       => 'Unarmed Multiplier',
      'UNENCUMBEREDMOVE'            => 'Ignore Encumberance',
      'VARIANTS'                    => 'Spell Variations',
      'VFEAT'                       => 'Virtual Feat',
      'VFEAT:.CLEAR'                => 'Clear Virtual Feat',
      'VISIBLE'                     => 'Visible',
      'VISION'                      => 'Vision',
      'WEAPONBONUS'                 => 'Optionnal Weapon Prof.',
      'WEIGHT'                      => 'Weight',
      'WT'                          => 'Weight',
      'XPCOST'                      => 'XP Cost',
      'XTRAFEATS'                   => 'Extra Feats',
   },

   'ABILITYCATEGORY' => {
      '000AbilityCategory'       => '# Ability Category',
      'CATEGORY'                 => 'Category of Object',
      'DISPLAYLOCATION'          => 'Display Location',
      'DISPLAYNAME'              => 'Display where?',
      'EDITABLE'                 => 'Editable?',
      'EDITPOOL'                 => 'Change Pool?',
      'FRACTIONALPOOL'           => 'Fractional values?',
      'PLURAL'                   => 'Plural description for UI',
      'POOL'                     => 'Base Pool number',
      'TYPE'                     => 'Type of Object',
      'ABILITYLIST'              => 'Specific choices list',
      'VISIBLE'                  => 'Visible',
   },

   'BIOSET AGESET' => {
      'AGESET'                   => '# Age set',
   },

   'BIOSET RACENAME' => {
      'RACENAME'                 => '# Race name',
   },

   'CLASS' => {
      '000ClassName'             => '# Class Name',
      'FACT:CLASSTYPE'           => 'Class Type',
      'CLASSTYPE'                => 'Class Type',
      'FACT:Abb'                 => 'Abbreviation',
      'ABB'                      => 'Abbreviation',
      'ALLOWBASECLASS',          => 'Base class as subclass?',
      'HASSUBSTITUTIONLEVEL'     => 'Substitution levels?',
      'ITEMCREATE'               => 'Craft Level Mult.',
      'LEVELSPERFEAT'            => 'Levels per Feat',
      'MODTOSKILLS'              => 'Add INT to Skill Points?',
      'MONNONSKILLHD'            => 'Extra Hit Die Skills Limit',
      'MULTIPREREQS'             => 'MULTIPREREQS',
      'DEITY'                    => 'Deities allowed',
      'ROLE'                     => 'Monster Role',
   },

   'CLASS Level' => {
      '000Level'                 => '# Level',
   },

   'COMPANIONMOD' => {
      '000Follower'              => '# Class of the Master',
      '000MasterBonusRace'       => '# Race of familiar',
      'COPYMASTERBAB'            => 'Copy Masters BAB',
      'COPYMASTERCHECK'          => 'Copy Masters Checks',
      'COPYMASTERHP'             => 'HP formula based on Master',
      'FOLLOWER'                 => 'Added Value',
      'SWITCHRACE'               => 'Change Racetype',
      'USEMASTERSKILL'           => 'Use Masters skills?',
   },

   'DEITY' => {
      '000DeityName'             => '# Deity Name',
      'DOMAINS'                  => 'Domains',
      'FOLLOWERALIGN'            => 'Clergy AL',
      'DESC'                     => 'Description of Deity/Title',
      'FACT:SYMBOL'              => 'Holy Item',
      'SYMBOL'                   => 'Holy Item',
      'DEITYWEAP'                => 'Deity Weapon',
      'FACT:TITLE'               => 'Deity Title',
      'TITLE'                    => 'Deity Title',
      'FACTSET:WORSHIPPERS'      => 'Usual Worshippers',
      'WORSHIPPERS'              => 'Usual Worshippers',
      'FACT:APPEARANCE'          => 'Deity Appearance',
      'APPEARANCE'               => 'Deity Appearance',
      'ABILITY'                  => 'Granted Ability',
   },

   'EQUIPMENT' => {
      '000EquipmentName'         => '# Equipment Name',
      'BASEITEM'                 => 'Base Item for EQMOD',
      'RESIZE'                   => 'Can be Resized',
      'QUALITY'                  => 'Quality and value',
      'SLOTS'                    => 'Slot Needed',
      'WIELD'                    => 'Wield Category',
      'MODS'                     => 'Requires Modification?',
   },

   'EQUIPMOD' => {
      '000ModifierName'          => '# Modifier Name',
      'ADDPROF'                  => 'Add Req. Prof.',
      'ARMORTYPE'                => 'Change Armor Type',
      'ASSIGNTOALL'              => 'Apply to both heads',
      'CHARGES'                  => 'Nb of Charges',
      'COSTPRE'                  => 'Cost before resizing',
      'FORMATCAT'                => 'Naming Format',
      'IGNORES'                  => 'Keys to ignore',
      'ITYPE'                    => 'Type granted',
      'KEY'                      => 'Unique Key',
      'NAMEOPT'                  => 'Naming Option',
      'PLUS'                     => 'Plus',
      'REPLACES'                 => 'Keys to replace',
   },

   'KIT STARTPACK' => {
      'STARTPACK'                => '# Kit Name',
      'APPLY'                    => 'Apply method to char',
   },

   'KIT CLASS' => {
      'CLASS'                    => '# Class',
   },

   'KIT FUNDS' => {
      'FUNDS'                    => '# Funds',
   },

   'KIT GEAR' => {
      'GEAR'                     => '# Gear',
   },

   'KIT LANGBONUS' => {
      'LANGBONUS'                => '# Bonus Language',
   },

   'KIT NAME' => {
      'NAME'                     => '# Name',
   },

   'KIT RACE' => {
      'RACE'                     => '# Race',
   },

   'KIT SELECT' => {
      'SELECT'                   => '# Select choice',
   },

   'KIT SKILL' => {
      'SKILL'                    => '# Skill',
      'SELECTION'                => 'Selections',
   },

   'KIT TABLE' => {
      'TABLE'                    => '# Table name',
      'VALUES'                   => 'Table Values',
   },

   'MASTERBONUSRACE' => {
      '000MasterBonusRace'       => '# Race of familiar',
   },

   'RACE' => {
      '000RaceName'              => '# Race Name',
      'FACT'                     => 'Base size',
      'FAVCLASS'                 => 'Favored Class',
      'SKILLMULT'                => 'Skill Multiplier',
      'MONCSKILL'                => 'Racial HD Class Skills',
      'MONCCSKILL'               => 'Racial HD Cross-class Skills',
      'MONSTERCLASS'             => 'Monster Class Name and Starting Level',
   },

   'SPELL' => {
      '000SpellName'             => '# Spell Name',
      'CLASSES'                  => 'Classes of caster',
      'DOMAINS'                  => 'Domains granting the spell',
   },

   'SUBCLASS' => {
      '000SubClassName'          => '# Subclass',
   },

   'SUBSTITUTIONCLASS' => {
      '000SubstitutionClassName' => '# Substitution Class',
   },

   'TEMPLATE' => {
      '000TemplateName'          => '# Template Name',
      'ADDLEVEL'                 => 'Add Levels',
      'BONUS:MONSKILLPTS'        => 'Bonus Monster Skill Points',
      'BONUSFEATS'               => 'Number of Bonus Feats',
      'FAVOREDCLASS'             => 'Favored Class',
      'GENDERLOCK'               => 'Lock Gender Selection',
   },

   'VARIABLE' => {
      '000VariableName'          => '# Variable Name',
      'EXPLANATION'              => 'Explanation',
   },

   'GLOBALMOD' => {
      '000GlobalmodName'         => '# Name',
      'EXPLANATION'              => 'Explanation',
   },

   'DATACONTROL' => {
      '000DatacontrolName'       => '# Name',
      'EXPLANATION'              => 'Explanation',
   },
   'ALIGNMENT' => {
      '000AlignmentName'         => '# Name',
   },
   'STAT' => {
      '000StatName'              => '# Name',
   },
   'SAVE' => {
      '000SaveName'              => '# Name',
   },

);

my %tokenAddTag = (
   'ADD:.CLEAR'               => 1,
   'ADD:CLASSSKILLS'          => 1,
   'ADD:DOMAIN'               => 1,
   'ADD:EQUIP'                => 1,
   'ADD:FAVOREDCLASS'         => 1,
   'ADD:LANGUAGE'             => 1,
   'ADD:SAB'                  => 1,
   'ADD:SPELLCASTER'          => 1,
   'ADD:SKILL'                => 1,
   'ADD:TEMPLATE'             => 1,
   'ADD:WEAPONPROFS'          => 1,

   'ADD:FEAT'                 => 1,    # Deprecated
   'ADD:FORCEPOINT'           => 1,    # Deprecated - never heard of this!
   'ADD:INIT'                 => 1,    # Deprecated
   'ADD:SPECIAL'              => 1,    # Deprecated - Remove 5.16 - Special abilities are now set using hidden feats or Abilities.
   'ADD:VFEAT'                => 1,    # Deprecated
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

   SPELLLEVEL => {
      CLASS                   => 1,
      DOMAIN                  => 1,
   },

   SPELLKNOWN => {
      CLASS                   => 1,
      DOMAIN                  => 1,
   },
);

my %tokenBonusTag = (
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
);

my %tokenProficiencyTag = (
   'WEAPON'                => 1,
   'ARMOR'                 => 1,
   'SHIELD'                => 1,
);

my %tokenQualifyTag = (
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
   'ABILITY'         => 1,
   'ABILITYCATEGORY' => 1, # Not sure how we want to do this, so leaving off the list for now. - Tir Gwaith
   'BIOSET'          => 1,
   'CLASS'           => 1,
   'CLASS Level'     => 1,
   'COMPANIONMOD'    => 1,
   'COPYRIGHT'       => 0,
   'COVER'           => 0,
   'DEITY'           => 1,
   'DOMAIN'          => 1,
   'EQUIPMENT'       => 1,
   'EQUIPMOD'        => 1,
   'FEAT'            => 1,
   'KIT'             => 1,
   'LANGUAGE'        => 1,
   'LSTEXCLUDE'      => 0,
   'INFOTEXT'        => 0,
   'PCC'             => 1,
   'RACE'            => 1,
   'SKILL'           => 1,
   'SPELL'           => 1,
   'TEMPLATE'        => 1,
   'WEAPONPROF'      => 1,
   'ARMORPROF'       => 1,
   'SHIELDPROF'      => 1,
   '#EXTRAFILE'      => 0,
   'VARIABLE'        => 1,
   'DATACONTROL'     => 1,
   'GLOBALMOD'       => 1,
   'SAVE'            => 1,
   'STAT'            => 1,
   'ALIGNMENT'       => 1,
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

# Some ppl may still want to use the old ways (for PCGen v5.9.5 and older)
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

   DATACONTROL => [
      \%SourceLineDef,
      {  Linetype       => 'DATACONTROL',
         RegEx          => qr(^([^\t:]+)),
         Mode           => MAIN,
         Format         => BLOCK,
         Header         => BLOCK_HEADER,
         ValidateKeep   => YES,
      },
   ],
   GLOBALMOD => [
      \%SourceLineDef,
      {  Linetype       => 'GLOBALMOD',
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

);

=head2 checkLimitedValueTags

   Certain tags only specif a specific set of fixed values. This operation is
   used to ensure their values are correct.

   ALIGN and PREALIGN can both take multiples of a specific set of tags, they
   are handled separately.

=cut

sub checkLimitedValueTags {

   my ($tag) = @_;


   # Special treament for the ALIGN and PREALIGN tags
   if ( $tag->id eq 'ALIGN' || $tag->id eq 'PREALIGN' ) {

      processAlign($tag);

   } else {

      processNonAlign($tag);
   }
}

=head2 getHeader

   Return the correct header for a particular tag in a
   particular file type.

   If no tag is defined for the filetype, the default for
   the tag is used. If there is no default for the tag,
   the tag name is returned.

   Parameters: $tag_name, $line_type

=cut

sub getHeader {
   my ( $tag_name, $line_type ) = @_;
   my $header = $tagheader{$line_type}{$tag_name} || $tagheader{default}{$tag_name} || $tag_name;

   if ( getOption('missingheader') && $tag_name eq $header ) {
      $missing_headers{$line_type}{$header}++;
   }

   $header;
}

=head2 getMissingHeaders

   Get the hash that stores the missing header information

   This is a nested hash indexed on linetype and tag name, each tag taht
   appears on a linetype which does not have a defined header will have a defined
   entry in the ahsh.

=cut

sub getMissingHeaders {
   return \%missing_headers;
}

=head2 getParseControl

   Get the Parse control record where the lineType field of the record matches
   the key used to look it up. This ensure we get the main record for the line
   type as lines can multiple linetype records.

=cut

sub getParseControl {
   my ($fileType) = @_;

   for my $rec ( @{ $parseControl{$fileType} } ) {
      return $rec if $rec->{ lineType } = $fileType;
   }

   # didn't find the record
   return undef;
}


# These are populated after parseSystemFiles has been run
my %validCheckName = ();
my %validGameModes = ();

=head2  getValidSystemArr

   Get an array of valid 'alignments', 'checks', 'gamemodes', 'stats', or 'vars'

=cut

sub getValidSystemArr {
   my ($type) = @_;

   my $arr = {
      'alignments' => \@validSystemAlignments,
      'checks'     => \@validSystemCheckNames,
      'gamemodes'  => \@validSystemGameModes,
      'stats'      => \@validSystemStats,
      'vars'       => \@validSystemVarNames
   }->{$type};

   defined $arr ? @{$arr} : ();
}

=head2 isValidCheck

   Returns true if the given check is valid.

=cut

sub isValidCheck{
   my ($check) = @_;
   return exists $validCheckName{$check};
}

=head2 isValidFixedValue

   Is this a valid value for the tag.

=cut

sub isValidFixedValue {

   my ($tag, $value) = @_;

   return exists $tagFixValue{$tag}{$value};
}


=head2 isValidGamemode

   Returns true if the given Gamemode is valid.

=cut

sub isValidGamemode {
   my ($Gamemode) = @_;
   return exists $validGameModes{$Gamemode};
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

=head2 parseAddTag

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

sub parseAddTag {

   my $tag = shift;

   # Old Format
   if ($tag =~ /\s*ADD:([^\(]+)\((.+)\)(\d*)/) {

      my ($token, $theRest, $numCount) = ($1, $2, $3);

      if (!$numCount) {
         $numCount = 1;
      }

      # Old format token ADD tag found,
      if ( exists $tokenAddTag{"ADD:$token"} ) {
         return ( 1, "ADD:$token", $theRest, $numCount );

      # Old format adlib ADD tag found.
      } else {
         return ( 2, "ADD:$token", $theRest, $numCount);
      }
   }

   # New format ADD tag.
   if ($tag =~ /\s*ADD:([^\|]+)(\|\d+)?\|(.+)/) {

      my ($token, $numCount, $optionList) = ($1, $2, $3);

      if (!$numCount) {
         $numCount = 1;
      }

      # 5.12 format ADD tag, using known token.
      if ( exists $tokenAddTag{"ADD:$token"}) {
         return ( 3, "ADD:$token", $optionList, $numCount);

      # 5.12 format ADD tag, not using known token.
      } else {
         return ( 4, "ADD:$token", $optionList, $numCount);
      }
   }

   # Not a good ADD tag.
   return ( 0, "", undef, 0 );
}

=head2 parseAutoTag

   Check that the Auto tag is valid and adjust the $tag if appropraite.

=cut

sub parseAutoTag {

   my ($tag) = @_;

   my $logger = getLogger();

   my $foundAutoType;

   AUTO_TYPE:
   for my $autoType ( sort { length($b) <=> length($a) || $a cmp $b } keys %{ $validSubTags{'AUTO'} } ) {

      if ( $tag->value =~ m/^$autoType/ ) {
         # We found what we were looking for
         $tag->value($tag->value =~ s/^$autoType//r);
         $foundAutoType = $autoType;
         last AUTO_TYPE;
      }
   }

   if ($foundAutoType) {

      $tag->id($tag->id . ':' . $foundAutoType);

   } elsif ( $tag->value =~ /^([^=:|]+)/ ) {

      my $potentialAddTag = $tag->id . ':' . $1;

      LstTidy::Report::incCountInvalidTags($tag->lineType, $potentialAddTag);
      $logger->notice(
         qq{Invalid tag "$potentialAddTag" found in } . $tag->lineType,
         $tag->file,
         $tag->line
      );
      $tag->noMoreErrors(1);

   } else {

      LstTidy::Report::incCountInvalidTags($tag->lineType, "AUTO");
      $logger->notice(
         qq{Invalid ADD tag "} . $tag->origTag . q{" found in } . $tag->lineType,
         $tag->file,
         $tag->line
      );
      $tag->noMoreErrors(1);

   }
}


=head2 extractVariables

   Parse an expression and return a list of variables found.

   Parameter:  $formula : String containing the formula
               $tag     : The Tag object

=cut

sub extractVariables {

   # We absolutely need to be called in array context.
   if (!wantarray) {
      croak q{extractVariables must be called in list context}
   };

   my ($toParse, $tag) = @_;

   # If the -nojep command line option was used, we
   # call the old parser
   if ( getOption('nojep') ) {
      return _oldExtractVariables($toParse, $tag->fullRealTag, $tag->file, $tag->line);
   } else {
      return _parseJepFormula($toParse, $tag->fullRealTag, $tag->file, $tag->line, 0 );
   }
}


=head2 parseSubTag

   Check that the sub token is valid and adjust the $tag if appropraite.

=cut

sub parseSubTag {

   my ($tag) = @_;

   my $logger = getLogger();

   # If this is s a subTag, the subTag is currently on the front of the value.
   my ($subTag) = ($tag->value =~ /^([^=:|]+)/ );

   my $potentialTag = $tag->id . ':' . $subTag;

   if ($subTag && exists $validSubTags{$tag->id}{$subTag}) {

      $tag->id($potentialTag);
      $tag->value($tag->value =~ s/^$subTag(.*)/$1/r);

   } elsif ($subTag) {

      # No valid type found
      LstTidy::Report::incCountInvalidTags($tag->lineType, $potentialTag);
      $logger->notice(
         qq{Invalid $potentialTag tag "} . $tag->origTag . q{" found in } . $tag->lineType,
         $tag->file,
         $tag->line
      );
      $tag->noMoreErrors(1);

   } else {

      LstTidy::Report::incCountInvalidTags($tag->lineType, $tag->id);
      $logger->notice(
         q{Invalid } . $tag->id . q{ tag "} . $tag->origTag . q{" found in } . $tag->lineType,
         $tag->file,
         $tag->line
      );
      $tag->noMoreErrors(1);
   }
}


=head2 parseSystemFiles

   This operation searches the given gamemode directory and parses out
   Allowable game modes, Stats, alignments, variable names and check names. These
   are then used to populate the valid data for later parses of LST files.

=cut

sub parseSystemFiles {
   my ($systemFilePath, $log) = @_;
   my $originalSystemFilePath = $systemFilePath;

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
   @validSystemAlignments = grep { !$seen{$_}++ } @verifiedAlignments;

   %seen = ();
   @validSystemCheckNames = grep { !$seen{$_}++ } @verifiedCheckNames;

   %seen = ();
   @validSystemGameModes = grep { !$seen{$_}++ } @verifiedAllowedModes;

   %seen = ();
   @validSystemStats = grep { !$seen{$_}++ } @verifiedStats;

   %seen = ();
   @validSystemVarNames = grep { !$seen{$_}++ } @verifiedVarNames;

   # Now we bitch if we are not happy
   if ( scalar @verifiedStats == 0 ) {
      $log->error(
         q{Could not find any STATNAME: tag in the system files},
         $originalSystemFilePath
      );
   }

   if ( scalar @validSystemGameModes == 0 ) {
      $log->error(
         q{Could not find any ALLOWEDMODES: tag in the system files},
         $originalSystemFilePath
      );
   }

   if ( scalar @validSystemCheckNames == 0 ) {
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
      for my $alignment (@validSystemAlignments) {
         print {$csvFile} qq{"$alignment"\n};
      }
      print {$csvFile} qq{\n};

      print {$csvFile} qq{"Allowed Modes"\n};
      for my $mode (sort @validSystemGameModes) {
         print {$csvFile} qq{"$mode"\n};
      }
      print {$csvFile} qq{\n};

      print {$csvFile} qq{"Stats Abbreviations"\n};
      for my $stat (@validSystemStats) {
         print {$csvFile} qq{"$stat"\n};
      }
      print {$csvFile} qq{\n};

      print {$csvFile} qq{"Variable Names"\n};
      for my $varName (sort @validSystemVarNames) {
         print {$csvFile} qq{"$varName"\n};
      }
      print {$csvFile} qq{\n};

      close $csvFile;
   }

   return;
}

=head2 extractTag

   This opeatrion takes a tag and makes sure it is suitable for further
   processing. It eliminates comments and dentifies pragma.

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

   # Is this a pragma?
   if ( $tagText =~ m/^(\#.*?):(.*)/ && LstTidy::Reformat::isValidTag($linetype, $1)) {
      return ( $1, $2 )
   }

   # Return already if no text to parse (comment)
   if (length $tagText == 0 || $tagText =~ /^\s*\#/) {
      return  ( "", "" )
   }

   # Remove any spaces before and after the tag
   $tagText =~ s/^\s+//;
   $tagText =~ s/\s+$//;
   
   return $tagText;
}

=head2 parseTag

   The most common use of this function is for the addition, conversion or
   removal of tags. The tag object passed in is modified and may be queried for
   the updated tag.

=cut

sub parseTag {

   my ($tag) = @_;

   # my ($tagText, $linetype, $file, $line) = @_;

   my $logger = getLogger();

   # All PCGen tags should have at least TAG_NAME:TAG_VALUE (Some rare tags
   # have two colons). Anything without a tag value is an anomaly. The only
   # exception to this rule is LICENSE that can be used without a value to
   # display an empty line.

   if ( (!defined $tag->value || $tag->value eq q{}) && $tag->fullTag ne 'LICENSE:') {
      $logger->warning(
         qq(The tag "} . $tag->fullTag . q{" is missing a value (or you forgot a : somewhere)),
         $tag->file,
         $tag->line
      );

      # We set the value to prevent further errors
      $tag->value(q{});
   }

   # [ 1387361 ] No KIT STARTPACK entry for \"KIT:xxx\"
   # STARTPACK lines in Kit files weren't getting added to $valid_entities. If
   # the verify flag is set and they aren't added to valid_entities, each Kit
   # will cause a spurious error. I've added them to valid entities to prevent
   # that.
   if ($tag->id eq 'STARTPACK') {
      my $value = $tag->value;
      LstTidy::Validate::setEntityValid('KIT STARTPACK', "KIT:$value");
      LstTidy::Validate::setEntityValid('KIT STARTPACK', "$value");
   }

   # Special cases like ADD:... and BONUS:...
   if (exists $tagProcessor{$tag->id}) {

      my $processor = $tagProcessor{$tag->id};

      if ( ref ($processor) eq "CODE" ) {
         &{ $processor }($tag);
      }
   }

   if ( defined $tag->value && $tag->value =~ /^.CLEAR/i ) {
      LstTidy::Validate::validateClearTag($tag);
   }

   # The tag is invalid and it's not a commnet.
   if ( ! LstTidy::Reformat::isValidTag($tag->lineType, $tag->id) && index( $tag->fullTag, '#' ) != 0 ) {

      processInvalidNonComment($tag);

   } elsif (LstTidy::Reformat::isValidTag($tag->lineType, $tag->id)) {

      # Statistic gathering
      LstTidy::Report::incCountValidTags($tag->lineType, $tag->realId);
   }

   # Check and reformat the values for the tags with only a limited number of
   # values.

   if ( exists $tagFixValue{$tag->id} ) {
      checkLimitedValueTags($tag);
   }

   ############################################################
   ######################## Conversion ########################
   # We manipulate the tag here
   doTagConversions($tag);

   ############################################################
   # We call the validating function if needed
   if (getOption('xcheck')) {
      LstTidy::Validate::validateTag($tag->realId, $tag->value, $tag->lineType, $tag->file, $tag->line)
   };

   if ($tag->value eq q{}) {
      $logger->debug(qq{parseTag: } . $tag->fullTag, $tag->file, $tag->line)
   };
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
         LstTidy::Validate::setEntityValid($linetype, $new_name);
      }

      last COLUMN;

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

      LstTidy::Validate::setEntityValid($linetype, $token);

      # Check to see if the token must be recorded for other
      # token types.
      if ( exists $line_info->{OtherValidEntries} ) {
         for my $entry_type ( @{ $line_info->{OtherValidEntries} } ) {
            LstTidy::Validate::setEntityValid($entry_type, $token);
         }
      }

   }
}

=head2 processAlign

   It is possible for the ALIGN and PREALIGN tags to have more then one value,
   make sure they are all valid. Convert them from number to text if necessary.

=cut

sub processAlign {

   my ($tag) = @_;

   my $logger = getLogger();
      
   # All the limited values are uppercase except the alignment value 'Deity'
   my $newvalue = uc($tag->value);
      
   my $is_valid = 1;

   # ALIGN use | for separator, PREALIGN use ,
   my $slip_patern = $tag->id eq 'PREALIGN' ? qr{[,]}xms : qr{[|]}xms;

   for my $align (split $slip_patern, $newvalue) {

      if ( $align eq 'DEITY' ) {
         $align = 'Deity';
      }

      # Is it a number?
      my ($number) = $align =~ / \A (\d+) \z /xms;

      if ( defined $number && $number >= 0 && $number < scalar @validSystemAlignments) {
         $align = $validSystemAlignments[$number];
         $newvalue =~ s{ (?<! \d ) ($number) (?! \d ) }{$align}xms;
      }

      # Is it a valid alignment?
      if (!exists $tagFixValue{$tag->id}{$align}) {
         $logger->notice(
            qq{Invalid value "$align" for tag "} . $tag->realId . q{"},
            $tag->file,
            $tag->line
         );
         $is_valid = 0;
      }
   }

   # Was the tag changed ?
   if ( $is_valid && $tag->value ne $newvalue) {

      $tag->value = $newvalue;

      $logger->warning(
         qq{Replaced "} . $tag->origTag . q{" with "} . $tag->fullRealId . qq{"},
         $tag->file,
         $tag->line
      );
   }

   return  $is_valid;
}

=head2 processInvalidNonComment

   After modifying the tag to account for sub tags, it is still invalid, check
   if it might be a valid ADD tag, if not log it (if allowed) and count it.

=cut

sub processInvalidNonComment {

   my ($tag) = @_;

   my $invalidTag = 1;

   # See if it might be a valid ADD tag.
   if ($tag->fullTag =~ /^ADD:([^\(\|]+)[\|\(]+/) {
      my $subTag = ($1);
      if (LstTidy::Reformat::isValidTag($tag->lineType, "ADD:$subTag")) {
         $invalidTag = 0;
      }
   }

   if ($invalidTag && !$tag->noMoreErrors) {

      getLogger()->notice(
         qq{The tag "} . $tag->id . q{" from "} . $tag->origTag . q{" is not in the } . $tag->lineType . q{ tag list\n},
         $tag->file,
         $tag->line
      );

      # If no more errors is set, we have already counted the invalid tag.
      LstTidy::Report::incCountInvalidTags($tag->lineType, $tag->realId);
   }
}

=head2 processNonAlign

   Any tag that has limited values but is not an ALIGN or PREALIGN can only
   have one value.  The value shold be uppercase, Check for validity and if
   necessary change the value.

=cut

sub processNonAlign {

   my ($tag) = @_;

   my $logger = getLogger();

   # All the limited values are uppercase
   my $newvalue = uc($tag->value);

   # Standerdize the YES NO and other such tags
   if ( exists $tagProperValue{$newvalue} ) {
      $newvalue = $tagProperValue{$newvalue};
   }

   # Is this a proper value for the tag?
   if ( !exists $tagFixValue{$tag->id}{$newvalue} ) {

      $logger->notice(
         qq{Invalid value "} . $tag->value . q{" for tag "} . $tag->realId . q{"},
         $tag->file,
         $tag->line
      );

   } elsif ($tag->value ne $newvalue) {

      $tag->value = $newvalue;

      $logger->warning(
         qq{Replaced "} . $tag->origTag . q{" by "} . $tag->fullRealId . qq{"},
         $tag->file,
         $tag->line
      );
   }
}

=head2 updateValidity

   This operation is intended to be called after parseSystemFiles, since that
   operation can change the value of both @validSystemCheckNames
   @validSystemGameModes,

=cut

sub updateValidity {
   %validCheckName = map { $_ => 1} @validSystemCheckNames, '%LIST', '%CHOICE';

   %validGameModes = map { $_ => 1 } (
      @validSystemGameModes,

      # CMP game modes
      'CMP_OGL_Arcana_Unearthed',
      'CMP_DnD_Blackmoor',
      'CMP_DnD_Dragonlance',
      'CMP_DnD_Eberron',
      'CMP_DnD_Forgotten_Realms_v30e',
      'CMP_DnD_Forgotten_Realms_v35e',
      'CMP_HARP',
      'CMP_D20_Modern',
      'CMP_DnD_Oriental_Adventures_v30e',
      'CMP_DnD_Oriental_Adventures_v35e',
      'CMP_D20_Fantasy_v30e',
      'CMP_D20_Fantasy_v35e',
      'CMP_D20_Fantasy_v35e_Kalamar',
      'DnD_v3.5e_VPWP',
      'CMP_D20_Fantasy_v35e_VPWP',
      '4e',
      '5e',
      'DnDNext',
      'AE',
      'Arcana_Evolved',
      'Dragon_Age',
      'MC_WoD',
      'MutantsAndMasterminds3e',
      'Starwars_SE',
      'SWSE',
      'Starwars_Edge',
      'T20',
      'Traveller20',
   );

   # When this function is called the system data has been processed. These
   # keys don't exist in %tagFixValue yet, so there is no danger of
   # overwriting.

   my %extraFixValue = (
      BONUSSPELLSTAT       => { map { $_ => 1 } ( @validSystemStats, qw(NONE) ) },
      SPELLSTAT            => { map { $_ => 1 } ( @validSystemStats, qw(SPELL NONE OTHER) ) },
      ALIGN                => { map { $_ => 1 } @validSystemAlignments },
      PREALIGN             => { map { $_ => 1 } @validSystemAlignments },
      KEYSTAT              => { map { $_ => 1 } @validSystemStats },
   );

   while (my ($key, $value) = each %extraFixValue) {
      $tagFixValue{$key} = $value;
   }

};

=head2 _oldExtractVariables

   The prejep variable parser. This is used both by the jep parser and when the
   jep option is turned off.

=cut

sub _oldExtractVariables {

   my ( $formula, $tag, $file, $line ) = @_;

   return () unless $formula;

   # Will hold the result values
   my @variable_names = ();

   # Get the logger singleton
   my $logger = getLogger();

   # We remove the COUNT[xxx] from the formulas
   while ( $formula =~ s/(COUNT\[[^]]*\])//g ) {
      push @variable_names, $1;
   }

   # We have to catch all the VAR=Funky Text before anything else
   while ( $formula =~ s/([a-z][a-z0-9_]*=[a-z0-9_ =\{\}]*)//i ) {
      my @values = split '=', $1;
      if ( @values > 2 ) {

         # There should only be one = per variable
         $logger->warning(
            qq{Too many = in "$1" found in "$tag"},
            $file,
            $line
         );
      }

      # [ 1104117 ] BL is a valid variable, like CL
      elsif ( $values[0] eq 'BL' || $values[0] eq 'CL' ||
         $values[0] eq 'CLASS' || $values[0] eq 'CLASSLEVEL' ) {
         # Convert {} to () for proper validation
         $values[1] =~ tr/{}/()/;
         push @LstTidy::Report::xcheck_to_process,
         [
            'CLASS',                qq(@@" in "$tag),
            $file, $line,
            $values[1]
         ];
      }

      elsif ($values[0] eq 'SKILLRANK' || $values[0] eq 'SKILLTOTAL' ) {

         # Convert {} to () for proper validation
         $values[1] =~ tr/{}/()/;
         push @LstTidy::Report::xcheck_to_process,
         [
            'SKILL',                qq(@@" in "$tag),
            $file, $line,
            $values[1]
         ];

      } else {

         $logger->notice(
            qq{Invalid variable "$values[0]" before the = in "$1" found in "$tag"},
            $file,
            $line
         );
      }
   }

   # Variables begin with a letter or the % and are followed
   # by letters, numbers, or the _
   VAR_NAME:
   for my $var_name ( $formula =~ /([a-z%][a-z0-9_]*)/gi ) {

      # If it's an operator, we skip it.
      if ( index( $var_name, 'MAX'   ) != -1
         || index( $var_name, 'MIN'   ) != -1
         || index( $var_name, 'TRUNC' ) != -1) {

         next VAR_NAME
      };

      push @variable_names, $var_name;
   }

   return @variable_names;
}

=head2 _parseJepFormula

   Parse a Jep formula expression and return a list of variables
   found.

   Parameter:  $formula   : String containing the formula
               $tag       : Tag containing the formula
               $file      : Filename to use with ewarn
               $line      : Line number to use with ewarn
               $is_param  : Indicate if the Jep expression is a function parameter

=cut

sub _parseJepFormula {
   my ($formula, $tag, $file, $line, $is_param) = @_;

   return () if !defined $formula;

   my @variables_found = ();   # Will contain the return values
   my $last_token      = q{};  # Only use for error messages
   my $last_token_type = q{};

   pos $formula = 0;

   # Get the logger singleton
   my $logger = getLogger();

   while ( pos $formula < length $formula ) {

      # If it's an identifier or a function
      if ( my ($ident) = ( $formula =~ / \G ( $isIdentRegex ) /xmsgc ) ) {

         # Identifiers are only valid after an operator or a separator
         if ( $last_token_type && $last_token_type ne 'operator' && $last_token_type ne 'separator' ) {

            # We "eat" the rest of the string and report an error
            my ($bogus_text) = ( $formula =~ / \G (.*) /xmsgc );
            $logger->notice(
               qq{Jep syntax error near "$ident$bogus_text" found in "$tag"},
               $file,
               $line
            );

         # Indentificator followed by bracket = function
         } elsif ( $formula =~ / \G [(] /xmsgc ) {

            # It's a function, is it valid?
            if ( !$isJepFunction{$ident} ) {
               $logger->notice(
                  qq{Not a valid Jep function: $ident() found in $tag},
                  $file,
                  $line
               );
            }

            # Reset the regex position just before the parantesis
            pos $formula = pos($formula) - 1;

            # We extract the function parameters
            my ($extracted_text) = Text::Balanced::extract_bracketed( $formula, '(")' );

            carp $formula if !$extracted_text;

            $last_token = "$ident$extracted_text";
            $last_token_type = 'function';

            # We remove the enclosing brackets
            ($extracted_text) = ( $extracted_text =~ / \A [(] ( .* ) [)] \z /xms );

            # For the var() function, we call the old parser
            if ( $ident eq 'var' ) {
               my ($var_text, $reminder) = Text::Balanced::extract_delimited( $extracted_text );

               # Verify that the values are between ""
               if ( $var_text ne q{} && $reminder eq q{} ) {

                  # Revove the "" and use the extracted text with the old var parser
                  ($var_text) = ( $var_text =~ / \A [\"] ( .* ) [\"] \z /xms );

               } else {

                  # We use the original extracted text with the old var parser
                  $var_text = $extracted_text;

                  $logger->notice(
                     qq{Quote missing for the var() parameter in "$tag"},
                     $file,
                     $line
                  );
               }

               # It's a variable, use the old varname operation.
               push @variables_found, _oldExtractVariables($var_text, $tag, $file, $line);

            } else {

               # Otherwise, each of the function parameters should be a valid Jep expression
               push @variables_found, _parseJepFormula( $extracted_text, $tag, $file, $line, 1 );
            }

         } else {

            # It's an identifier
            push @variables_found, $ident;
            $last_token = $ident;
            $last_token_type = 'ident';
         }

      } elsif ( my ($operator) = ( $formula =~ / \G ( $isOperatorRegex ) /xmsgc ) ) {
         # It's an operator

         if ( $operator eq '=' ) {
            if ( $last_token_type eq 'ident' ) {
               $logger->notice(
                  qq{Forgot to use var()? Dubious use of Jep variable assignation near }
                  . qq{"$last_token$operator" in "$tag"},
                  $file,
                  $line
               );

            } else {
               $logger->notice(
                  qq{Did you want the logical "=="? Dubious use of Jep variable assignation near }
                  . qq{"$last_token$operator" in "$tag"},
                  $file,
                  $line
               );
            }
         }

         $last_token = $operator;
         $last_token_type = 'operator';

      } elsif ( $formula =~ / \G [(] /xmsgc ) {

         # Reset the regex position just before the bracket
         pos $formula = pos($formula) - 1;

         # Extract what is between the () and call recursivly
         my ($extracted_text) = Text::Balanced::extract_bracketed( $formula, '(")' );

         if ($extracted_text) {

            $last_token = $extracted_text;
            $last_token_type = 'expression';

            # Remove the outside brackets
            ($extracted_text) = ( $extracted_text =~ / \A [(] ( .* ) [)] \z /xms );

            # Recursive call
            push @variables_found, _parseJepFormula( $extracted_text, $tag, $file, $line, 0 );

         } else {

            # We "eat" the rest of the string and report an error
            my ($bogus_text) = ( $formula =~ / \G (.*) /xmsgc );
            $logger->notice(
               qq{Unbalance () in "$bogus_text" found in "$tag"},
               $file,
               $line
            );
         }

      } elsif ( my ($number) = ( $formula =~ / \G ( $isNumberRegex ) /xmsgc ) ) {

         # It's a number
         $last_token = $number;
         $last_token_type = 'number';

      } elsif ( $formula =~ / \G [\"'] /xmsgc ) {

         # It's a string
         # Reset the regex position just before the quote
         pos $formula = pos($formula) - 1;

         # Extract what is between the () and call recursivly
         my ($extracted_text) = Text::Balanced::extract_delimited( $formula );

         if ($extracted_text) {

            $last_token = $extracted_text;
            $last_token_type = 'string';

         } else {

            # We "eat" the rest of the string and report an error
            my ($bogus_text) = ( $formula =~ / \G (.*) /xmsgc );
            $logger->notice(
               qq{Unbalance quote in "$bogus_text" found in "$tag"},
               $file,
               $line
            );
         }

      } elsif ( my ($separator) = ( $formula =~ / \G ( [,] ) /xmsgc ) ) {

         # It's a comma
         if ( $is_param == 0 ) {
            # Commas are allowed only as parameter separator
            my ($bogus_text) = ( $formula =~ / \G (.*) /xmsgc );
            $logger->notice(
               qq{Jep syntax error found near "$separator$bogus_text" in "$tag"},
               $file,
               $line
            );
         }

         $last_token = $separator;
         $last_token_type = 'separator';

      } elsif ( $formula =~ / \G \s+ /xmsgc ) {
         # Spaces are allowed in Jep expressions, we simply ignore them

      } else {

         if ( $formula =~ /\G\[.+\]/gc ) {
            # Allow COUNT[something]
         } else {
            # If we are here, all is not well
            my ($bogus_text) = ( $formula =~ / \G (.*) /xmsgc );
            $logger->notice(
               qq{Jep syntax error found near unknown function "$bogus_text" in "$tag"},
               $file,
               $line
            );
         }
      }
   }

   return @variables_found;
}

1;
