package LstTidy::Parse;

use strict;
use warnings;
use English;

require Exporter;

our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
   getHeaderMissingOnLineType 
   getMissingHeaderLineTypes 
   mungKey 
   parseLine
   );

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

   charbonusto ceil    cl      classlevel      count   floor
   min         max     roll    skillinfo       var     mastervar
   APPLIEDAS
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

my $className         = "";
my $sourceCurrentFile = "";
my %classSpellTypes   = ();
my %sourceTags        = ();
my %spellsForEQMOD    = ();

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
   FACT        => \&LstTidy::Parse::parseProteanSubTag,
   FACTSET     => \&LstTidy::Parse::parseProteanSubTag,
   INFO        => \&LstTidy::Parse::parseProteanSubTag,
   PROFICIENCY => \&LstTidy::Parse::parseSubTag,
   QUALIFY     => \&LstTidy::Parse::parseSubTag,
   QUALITY     => \&LstTidy::Parse::parseProteanSubTag,
   SPELLKNOWN  => \&LstTidy::Parse::parseSubTag,
   SPELLLEVEL  => \&LstTidy::Parse::parseSubTag,
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
      '000ClassName'                      => '# Class Name',
      '001SkillName'                      => 'Class Skills (All skills are seperated by a pipe delimiter \'|\')',

      '000DomainName'                     => '# Domain Name',
      '001DomainEffect'                   => 'Description',

      'DESC'                              => 'Description',

      '000AbilityName'                    => '# Ability Name',
      '000FeatName'                       => '# Feat Name',

      '000AbilityCategory',               => '# Ability Category Name',

      '000LanguageName'                   => '# Language',

      'FAVCLASS'                          => 'Favored Class',
      'XTRASKILLPTSPERLVL'                => 'Skills/Level',
      'STARTFEATS'                        => 'Starting Feats',

      '000SkillName'                      => '# Skill Name',

      'KEYSTAT'                           => 'Key Stat',
      'EXCLUSIVE'                         => 'Exclusive?',
      'USEUNTRAINED'                      => 'Untrained?',
      'SITUATION'                         => 'Situational Skill',

      '000TemplateName'                   => '# Template Name',

      '000WeaponName'                     => '# Weapon Name',
      '000ArmorName'                      => '# Armor Name',
      '000ShieldName'                     => '# Shield Name',

      '000VariableName'                   => '# Name',
      '000GlobalmodName'                  => '# Name',
      '000DatacontrolName'                => '# Name',
      '000SaveName'                       => '# Name',
      '000StatName'                       => '# Name',
      '000AlignmentName'                  => '# Name',
      'DATAFORMAT'                        => 'Dataformat',
      'REQUIRED'                          => 'Required',
      'SELECTABLE'                        => 'Selectable',
      'DISPLAYNAME'                       => 'Displayname',

      'ABILITY'                           => 'Ability',
      'ACCHECK'                           => 'AC Penalty Check',
      'ACHECK'                            => 'Skill Penalty?',
      'ADD'                               => 'Add',
      'ADD:EQUIP'                         => 'Add Equipment',
      'ADD:FEAT'                          => 'Add Feat',
      'ADD:SAB'                           => 'Add Special Ability',
      'ADD:SKILL'                         => 'Add Skill',
      'ADD:TEMPLATE'                      => 'Add Template',
      'ADDDOMAINS'                        => 'Add Divine Domain',
      'ADDSPELLLEVEL'                     => 'Add Spell Lvl',
      'APPLIEDNAME'                       => 'Applied Name',
      'AGE'                               => 'Age',
      'AGESET'                            => 'Age Set',
      'ALIGN'                             => 'Align',
      'ALTCRITMULT'                       => 'Alt Crit Mult',
      'ALTCRITRANGE'                      => 'Alt Crit Range',
      'ALTDAMAGE'                         => 'Alt Damage',
      'ALTEQMOD'                          => 'Alt EQModifier',
      'ALTTYPE'                           => 'Alt Type',
      'ATTACKCYCLE'                       => 'Attack Cycle',
      'ASPECT'                            => 'Aspects',
      'AUTO'                              => 'Auto',
      'AUTO:ARMORPROF'                    => 'Auto Armor Prof',
      'AUTO:EQUIP'                        => 'Auto Equip',
      'AUTO:FEAT'                         => 'Auto Feat',
      'AUTO:LANG'                         => 'Auto Language',
      'AUTO:SHIELDPROF'                   => 'Auto Shield Prof',
      'AUTO:WEAPONPROF'                   => 'Auto Weapon Prof',
      'BASEQTY'                           => 'Base Quantity',
      'BENEFIT'                           => 'Benefits',
      'BONUS'                             => 'Bonus',
      'BONUSSPELLSTAT'                    => 'Spell Stat Bonus',
      'BONUS:ABILITYPOOL'                 => 'Bonus Ability Pool',
      'BONUS:CASTERLEVEL'                 => 'Caster level',
      'BONUS:CHECKS'                      => 'Save checks bonus',
      'BONUS:CONCENTRATION'               => 'Concentration bonus',
      'BONUS:SAVE'                        => 'Save bonus',
      'BONUS:COMBAT'                      => 'Combat bonus',
      'BONUS:DAMAGE'                      => 'Weapon damage bonus',
      'BONUS:DOMAIN'                      => 'Add domain number',
      'BONUS:DC'                          => 'Bonus DC',
      'BONUS:DR'                          => 'Bonus DR',
      'BONUS:EQMARMOR'                    => 'Bonus Armor Mods',
      'BONUS:EQM'                         => 'Bonus Equip Mods',
      'BONUS:EQMWEAPON'                   => 'Bonus Weapon Mods',
      'BONUS:ESIZE'                       => 'Modify size',
      'BONUS:FEAT'                        => 'Number of Feats',
      'BONUS:FOLLOWERS'                   => 'Number of Followers',
      'BONUS:HD'                          => 'Modify HD type',
      'BONUS:HP'                          => 'Bonus to HP',
      'BONUS:ITEMCOST'                    => 'Modify the item cost',
      'BONUS:LANGUAGES'                   => 'Bonus language',
      'BONUS:MISC'                        => 'Misc bonus',
      'BONUS:MOVEADD'                     => 'Add to base move',
      'BONUS:MOVEMULT'                    => 'Multiply base move',
      'BONUS:POSTMOVEADD'                 => 'Add to magical move',
      'BONUS:PCLEVEL'                     => 'Caster level bonus',
      'BONUS:POSTRANGEADD'                => 'Bonus to Range',
      'BONUS:RANGEADD'                    => 'Bonus to base range',
      'BONUS:RANGEMULT'                   => '% bonus to range',
      'BONUS:REPUTATION'                  => 'Bonus to Reputation',
      'BONUS:SIZEMOD'                     => 'Adjust PC Size',
      'BONUS:SKILL'                       => 'Bonus to skill',
      'BONUS:SITUATION'                   => 'Bonus to Situation',
      'BONUS:SKILLPOINTS'                 => 'Bonus to skill point/L',
      'BONUS:SKILLPOOL'                   => 'Bonus to skill point for a level',
      'BONUS:SKILLRANK'                   => 'Bonus to skill rank',
      'BONUS:SLOTS'                       => 'Bonus to nb of slots',
      'BONUS:SPELL'                       => 'Bonus to spell attribute',
      'BONUS:SPECIALTYSPELLKNOWN'         => 'Bonus Specialty spells',
      'BONUS:SPELLCAST'                   => 'Bonus to spell cast/day',
      'BONUS:SPELLCASTMULT'               => 'Multiply spell cast/day',
      'BONUS:SPELLKNOWN'                  => 'Bonus to spell known/L',
      'BONUS:STAT'                        => 'Stat bonus',
      'BONUS:TOHIT'                       => 'Attack roll bonus',
      'BONUS:UDAM'                        => 'Unarmed Damage Level bonus',
      'BONUS:VAR'                         => 'Modify VAR',
      'BONUS:VISION'                      => 'Add to vision',
      'BONUS:WEAPON'                      => 'Weapon prop. bonus',
      'BONUS:WEAPONPROF'                  => 'Weapon prof. bonus',
      'BONUS:WIELDCATEGORY'               => 'Wield Category bonus',
      'TEMPBONUS'                         => 'Temporary Bonus',
      'CAST'                              => 'Cast',
      'CASTAS'                            => 'Cast As',
      'CASTTIME:.CLEAR'                   => 'Clear Casting Time',
      'CASTTIME'                          => 'Casting Time',
      'CATEGORY'                          => 'Category of Ability',
      'CCSKILL:.CLEAR'                    => 'Remove Cross-Class Skill',
      'CCSKILL'                           => 'Cross-Class Skill',
      'CHANGEPROF'                        => 'Change Weapon Prof. Category',
      'CHOOSE'                            => 'Choose',
      'CLASSES'                           => 'Classes',
      'COMPANIONLIST'                     => 'Allowed Companions',
      'COMPS'                             => 'Components',
      'CONTAINS'                          => 'Contains',
      'COST'                              => 'Cost',
      'CR'                                => 'Challenge Rating',
      'CRMOD'                             => 'CR Modifier',
      'CRITMULT'                          => 'Crit Mult',
      'CRITRANGE'                         => 'Crit Range',
      'CSKILL:.CLEAR'                     => 'Remove Class Skill',
      'CSKILL'                            => 'Class Skill',
      'CT'                                => 'Casting Threshold',
      'DAMAGE'                            => 'Damage',
      'DEF'                               => 'Def',
      'DEFINE'                            => 'Define',
      'DEFINESTAT'                        => 'Define Stat',
      'DEITY'                             => 'Deity',
      'DESC'                              => 'Description',
      'DESC:.CLEAR'                       => 'Clear Description',
      'DESCISPI'                          => 'Desc is PI?',
      'DESCRIPTOR:.CLEAR'                 => 'Clear Spell Descriptors',
      'DESCRIPTOR'                        => 'Descriptor',
      'DOMAIN'                            => 'Domain',
      'DOMAINS'                           => 'Domains',
      'DONOTADD'                          => 'Do Not Add',
      'DR:.CLEAR'                         => 'Remove Damage Reduction',
      'DR'                                => 'Damage Reduction',
      'DURATION:.CLEAR'                   => 'Clear Duration',
      'DURATION'                          => 'Duration',
      'EQMOD'                             => 'Modifier',
      'EXCLASS'                           => 'Ex Class',
      'EXPLANATION'                       => 'Explanation',
      'FACE'                              => 'Face/Space',
      'FACT:Abb'                          => 'Abbreviation',
      'FACT:AppliedName'                  => 'Applied Name',
      'FACT:Article'                      => 'Applied Name',
      'FACT:BaseSize'                     => 'Base Size',
      'FACT:ClassType'                    => 'Class Type',
      'FACT:SpellType'                    => 'Spell Type',
      'FACTSET:Worshipers'                => 'Usual Worshipers',
      'FACT:RateOfFire'                   => 'Rate of Fire',
      'FACT:CompMaterial'                 => 'Material Components',
      'FEAT'                              => 'Feat',
      'FEATAUTO'                          => 'Feat Auto',
      'FOLLOWERS'                         => 'Allow Follower',
      'FREE'                              => 'Free',
      'FUMBLERANGE'                       => 'Fumble Range',
      'GENDER'                            => 'Gender',
      'HANDS'                             => 'Nb Hands',
      'HASSUBCLASS'                       => 'Subclass?',
      'ALLOWBASECLASS'                    => 'Base class as subclass?',
      'HD'                                => 'Hit Dice',
      'HEIGHT'                            => 'Height',
      'HITDIE'                            => 'Hit Dice Size',
      'HITDICEADVANCEMENT'                => 'Hit Dice Advancement',
      'HITDICESIZE'                       => 'Hit Dice Size',
      'ITEM'                              => 'Item',
      'KEY'                               => 'Unique Key',
      'KIT'                               => 'Apply Kit',
      'KNOWN'                             => 'Known',
      'KNOWNSPELLS'                       => 'Automatically Known Spell Levels',
      'LANGBONUS'                         => 'Bonus Languages',
      'LANGBONUS:.CLEAR'                  => 'Clear Bonus Languages',
      'LEGS'                              => 'Nb Legs',
      'LEVEL'                             => 'Level',
      'LEVELADJUSTMENT'                   => 'Level Adjustment',
      'MAXCOST'                           => 'Maximum Cost',
      'MAXDEX'                            => 'Maximum DEX Bonus',
      'MAXLEVEL'                          => 'Max Level',
      'MEMORIZE'                          => 'Memorize',
      'MFEAT'                             => 'Default Monster Feat',
      'MONSKILL'                          => 'Monster Initial Skill Points',
      'MOVE'                              => 'Move',
      'MOVECLONE'                         => 'Clone Movement',
      'MULT'                              => 'Multiple?',
      'NAMEISPI'                          => 'Product Identity?',
      'NATURALARMOR'                      => 'Natural Armor',
      'NATURALATTACKS'                    => 'Natural Attacks',
      'NUMPAGES'                          => 'Number of Pages',
      'OUTPUTNAME'                        => 'Output Name',
      'PAGEUSAGE'                         => 'Page Usage',
      'PANTHEON'                          => 'Pantheon',
      'PPCOST'                            => 'Power Points',
      'PRE:.CLEAR'                        => 'Clear Prereq.',
      'PREABILITY'                        => 'Required Ability',
      '!PREABILITY'                       => 'Restricted Ability',
      'PREAGESET'                         => 'Minimum Age',
      '!PREAGESET'                        => 'Maximum Age',
      'PREALIGN'                          => 'Required AL',
      '!PREALIGN'                         => 'Restricted AL',
      'PREATT'                            => 'Req. Att.',
      'PREARMORPROF'                      => 'Req. Armor Prof.',
      '!PREARMORPROF'                     => 'Prohibited Armor Prof.',
      'PREBASESIZEEQ'                     => 'Required Base Size',
      '!PREBASESIZEEQ'                    => 'Prohibited Base Size',
      'PREBASESIZEGT'                     => 'Minimum Base Size',
      'PREBASESIZEGTEQ'                   => 'Minimum Size',
      'PREBASESIZELT'                     => 'Maximum Base Size',
      'PREBASESIZELTEQ'                   => 'Maximum Size',
      'PREBASESIZENEQ'                    => 'Prohibited Base Size',
      'PRECAMPAIGN'                       => 'Required Campaign(s)',
      '!PRECAMPAIGN'                      => 'Prohibited Campaign(s)',
      'PRECHECK'                          => 'Required Check',
      '!PRECHECK'                         => 'Prohibited Check',
      'PRECHECKBASE'                      => 'Required Check Base',
      'PRECITY'                           => 'Required City',
      '!PRECITY'                          => 'Prohibited City',
      'PRECLASS'                          => 'Required Class',
      '!PRECLASS'                         => 'Prohibited Class',
      'PRECLASSLEVELMAX'                  => 'Maximum Level Allowed',
      '!PRECLASSLEVELMAX'                 => 'Should use PRECLASS',
      'PRECSKILL'                         => 'Required Class Skill',
      '!PRECSKILL'                        => 'Prohibited Class SKill',
      'PREDEITY'                          => 'Required Deity',
      '!PREDEITY'                         => 'Prohibited Deity',
      'PREDEITYDOMAIN'                    => 'Required Deitys Domain',
      'PREDOMAIN'                         => 'Required Domain',
      '!PREDOMAIN'                        => 'Prohibited Domain',
      'PREDSIDEPTS'                       => 'Req. Dark Side',
      'PREDR'                             => 'Req. Damage Resistance',
      '!PREDR'                            => 'Prohibited Damage Resistance',
      'PREEQUIP'                          => 'Req. Equipement',
      'PREEQMOD'                          => 'Req. Equipment Mod.',
      '!PREEQMOD'                         => 'Prohibited Equipment Mod.',
      'PREFEAT'                           => 'Required Feat',
      '!PREFEAT'                          => 'Prohibited Feat',
      'PREGENDER'                         => 'Required Gender',
      '!PREGENDER'                        => 'Prohibited Gender',
      'PREHANDSEQ'                        => 'Req. nb of Hands',
      'PREHANDSGT'                        => 'Min. nb of Hands',
      'PREHANDSGTEQ'                      => 'Min. nb of Hands',
      'PREHD'                             => 'Required Hit Dice',
      'PREHP'                             => 'Required Hit Points',
      'PREITEM'                           => 'Required Item',
      'PRELANG'                           => 'Required Language',
      'PRELEVEL'                          => 'Required Lvl',
      'PRELEVELMAX'                       => 'Maximum Level',
      'PREKIT'                            => 'Required Kit',
      '!PREKIT'                           => 'Prohibited Kit',
      'PREMOVE'                           => 'Required Movement Rate',
      '!PREMOVE'                          => 'Prohibited Movement Rate',
      'PREMULT'                           => 'Multiple Requirements',
      '!PREMULT'                          => 'Multiple Prohibitions',
      'PREPCLEVEL'                        => 'Required Non-Monster Lvl',
      'PREPROFWITHARMOR'                  => 'Required Armor Proficiencies',
      '!PREPROFWITHARMOR'                 => 'Prohibited Armor Proficiencies',
      'PREPROFWITHSHIELD'                 => 'Required Shield Proficiencies',
      '!PREPROFWITHSHIELD'                => 'Prohbited Shield Proficiencies',
      'PRERACE'                           => 'Required Race',
      '!PRERACE'                          => 'Prohibited Race',
      'PRERACETYPE'                       => 'Reg. Race Type',
      'PREREACH'                          => 'Minimum Reach',
      'PREREACHEQ'                        => 'Required Reach',
      'PREREACHGT'                        => 'Minimum Reach',
      'PREREGION'                         => 'Required Region',
      '!PREREGION'                        => 'Prohibited Region',
      'PRERULE'                           => 'Req. Rule (in options)',
      'PRESA'                             => 'Req. Special Ability',
      '!PRESA'                            => 'Prohibite Special Ability',
      'PRESHIELDPROF'                     => 'Req. Shield Prof.',
      '!PRESHIELDPROF'                    => 'Prohibited Shield Prof.',
      'PRESIZEEQ'                         => 'Required Size',
      'PRESIZEGT'                         => 'Must be Larger',
      'PRESIZEGTEQ'                       => 'Minimum Size',
      'PRESIZELT'                         => 'Must be Smaller',
      'PRESIZELTEQ'                       => 'Maximum Size',
      'PRESKILL'                          => 'Required Skill',
      '!PRESITUATION'                     => 'Prohibited Situation',
      'PRESITUATION'                      => 'Required Situation',
      '!PRESKILL'                         => 'Prohibited Skill',
      'PRESKILLMULT'                      => 'Special Required Skill',
      'PRESKILLTOT'                       => 'Total Skill Points Req.',
      'PRESPELL'                          => 'Req. Known Spell',
      'PRESPELLBOOK'                      => 'Req. Spellbook',
      'PRESPELLBOOK'                      => 'Req. Spellbook',
      'PRESPELLCAST'                      => 'Required Casting Type',
      '!PRESPELLCAST'                     => 'Prohibited Casting Type',
      'PRESPELLDESCRIPTOR'                => 'Required Spell Descriptor',
      '!PRESPELLDESCRIPTOR'               => 'Prohibited Spell Descriptor',
      'PRESPELLSCHOOL'                    => 'Required Spell School',
      'PRESPELLSCHOOLSUB'                 => 'Required Sub-school',
      '!PRESPELLSCHOOLSUB'                => 'Prohibited Sub-school',
      'PRESPELLTYPE'                      => 'Req. Spell Type',
      'PRESREQ'                           => 'Req. Spell Resist',
      'PRESRGT'                           => 'SR Must be Greater',
      'PRESRGTEQ'                         => 'SR Min. Value',
      'PRESRLT'                           => 'SR Must be Lower',
      'PRESRLTEQ'                         => 'SR Max. Value',
      'PRESRNEQ'                          => 'Prohibited SR Value',
      'PRESTAT'                           => 'Required Stat',
      '!PRESTAT',                         => 'Prohibited Stat',
      'PRESUBCLASS'                       => 'Required Subclass',
      '!PRESUBCLASS'                      => 'Prohibited Subclass',
      'PRETEMPLATE'                       => 'Required Template',
      '!PRETEMPLATE'                      => 'Prohibited Template',
      'PRETEXT'                           => 'Required Text',
      'PRETYPE'                           => 'Required Type',
      '!PRETYPE'                          => 'Prohibited Type',
      'PREVAREQ'                          => 'Required Var. value',
      '!PREVAREQ'                         => 'Prohibited Var. Value',
      'PREVARGT'                          => 'Var. Must Be Grater',
      'PREVARGTEQ'                        => 'Var. Min. Value',
      'PREVARLT'                          => 'Var. Must Be Lower',
      'PREVARLTEQ'                        => 'Var. Max. Value',
      'PREVARNEQ'                         => 'Prohibited Var. Value',
      'PREVISION'                         => 'Required Vision',
      '!PREVISION'                        => 'Prohibited Vision',
      'PREWEAPONPROF'                     => 'Req. Weapond Prof.',
      '!PREWEAPONPROF'                    => 'Prohibited Weapond Prof.',
      'PREWIELD'                          => 'Required Wield Category',
      '!PREWIELD'                         => 'Prohibited Wield Category',
      'PROFICIENCY:WEAPON'                => 'Required Weapon Proficiency',
      'PROFICIENCY:ARMOR'                 => 'Required Armor Proficiency',
      'PROFICIENCY:SHIELD'                => 'Required Shield Proficiency',
      'PROHIBITED'                        => 'Spell Scoll Prohibited',
      'PROHIBITSPELL'                     => 'Group of Prohibited Spells',
      'QUALIFY:CLASS'                     => 'Qualify for Class',
      'QUALIFY:DEITY'                     => 'Qualify for Deity',
      'QUALIFY:DOMAIN'                    => 'Qualify for Domain',
      'QUALIFY:EQUIPMENT'                 => 'Qualify for Equipment',
      'QUALIFY:EQMOD'                     => 'Qualify for Equip Modifier',
      'QUALIFY:FEAT'                      => 'Qualify for Feat',
      'QUALIFY:RACE'                      => 'Qualify for Race',
      'QUALIFY:SPELL'                     => 'Qualify for Spell',
      'QUALIFY:SKILL'                     => 'Qualify for Skill',
      'QUALIFY:TEMPLATE'                  => 'Qualify for Template',
      'QUALIFY:WEAPONPROF'                => 'Qualify for Weapon Proficiency',
      'QUALITY:Aura'                      => 'Aura',
      'QUALITY:Capacity'                  => 'Capacity',
      'QUALITY:Caster Level'              => 'Caster Level',
      'QUALITY:Construction Cost'         => 'Construction Cost',
      'QUALITY:Construction Craft DC'     => 'Construction Craft DC',
      'QUALITY:Construction Requirements' => 'Construction Requirements',
      'QUALITY:Slot'                      => 'Slot',
      'QUALITY:Usage'                     => 'Usage',
      'RACESUBTYPE:.CLEAR'                => 'Clear Racial Subtype',
      'RACESUBTYPE'                       => 'Race Subtype',
      'RACETYPE:.CLEAR'                   => 'Clear Main Racial Type',
      'RACETYPE'                          => 'Main Race Type',
      'RANGE:.CLEAR'                      => 'Clear Range',
      'RANGE'                             => 'Range',
      'RATEOFFIRE'                        => 'Rate of Fire',
      'REACH'                             => 'Reach',
      'REACHMULT'                         => 'Reach Multiplier',
      'REGION'                            => 'Region',
      'REPEATLEVEL'                       => 'Repeat this Level',
      'REMOVABLE'                         => 'Removable?',
      'REMOVE'                            => 'Remove Object',
      'REP'                               => 'Reputation',
      'ROLE'                              => 'Monster Role',
      'SA'                                => 'Special Ability',
      'SA:.CLEAR'                         => 'Clear SAs',
      'SAB:.CLEAR'                        => 'Clear Special ABility',
      'SAB'                               => 'Special ABility',
      'SAVEINFO'                          => 'Save Info',
      'SCHOOL:.CLEAR'                     => 'Clear School',
      'SCHOOL'                            => 'School',
      'SELECT'                            => 'Selections',
      'SERVESAS'                          => 'Serves As',
      'SIZE'                              => 'Size',
      'SKILLLIST'                         => 'Use Class Skill List',
      'SOURCE'                            => 'Source Index',
      'SOURCEPAGE:.CLEAR'                 => 'Clear Source Page',
      'SOURCEPAGE'                        => 'Source Page',
      'SOURCELONG'                        => 'Source, Long Desc.',
      'SOURCESHORT'                       => 'Source, Short Desc.',
      'SOURCEWEB'                         => 'Source URI',
      'SOURCEDATE'                        => 'Source Pub. Date',
      'SOURCELINK'                        => 'Source Pub Link',
      'SPELLBOOK'                         => 'Spellbook',
      'SPELLFAILURE'                      => '% of Spell Failure',
      'SPELLLIST'                         => 'Use Spell List',
      'SPELLKNOWN:CLASS'                  => 'List of Known Class Spells by Level',
      'SPELLKNOWN:DOMAIN'                 => 'List of Known Domain Spells by Level',
      'SPELLLEVEL:CLASS'                  => 'List of Class Spells by Level',
      'SPELLLEVEL:DOMAIN'                 => 'List of Domain Spells by Level',
      'SPELLRES'                          => 'Spell Resistance',
      'SPELL'                             => 'Deprecated Spell tag',
      'SPELLS'                            => 'Innate Spells',
      'SPELLSTAT'                         => 'Spell Stat',
      'SPELLTYPE'                         => 'Spell Type',
      'SPROP:.CLEAR'                      => 'Clear Special Property',
      'SPROP'                             => 'Special Property',
      'SR'                                => 'Spell Res.',
      'STACK'                             => 'Stackable?',
      'STARTSKILLPTS'                     => 'Skill Pts/Lvl',
      'STAT'                              => 'Key Attribute',
      'SUBCLASSLEVEL'                     => 'Subclass Level',
      'SUBRACE'                           => 'Subrace',
      'SUBREGION'                         => 'Subregion',
      'SUBSCHOOL'                         => 'Sub-School',
      'SUBSTITUTIONLEVEL'                 => 'Substitution Level',
      'SYNERGY'                           => 'Synergy Skill',
      'TARGETAREA:.CLEAR'                 => 'Clear Target Area or Effect',
      'TARGETAREA'                        => 'Target Area or Effect',
      'TEMPDESC'                          => 'Temporary effect description',
      'TEMPLATE'                          => 'Template',
      'TEMPLATE:.CLEAR'                   => 'Clear Templates',
      'TYPE'                              => 'Type',
      'TYPE:.CLEAR'                       => 'Clear Types',
      'UDAM'                              => 'Unarmed Damage',
      'UMULT'                             => 'Unarmed Multiplier',
      'UNENCUMBEREDMOVE'                  => 'Ignore Encumberance',
      'VARIANTS'                          => 'Spell Variations',
      'VFEAT'                             => 'Virtual Feat',
      'VFEAT:.CLEAR'                      => 'Clear Virtual Feat',
      'VISIBLE'                           => 'Visible',
      'VISION'                            => 'Vision',
      'WEAPONBONUS'                       => 'Optionnal Weapon Prof.',
      'WEIGHT'                            => 'Weight',
      'WT'                                => 'Weight',
      'XPCOST'                            => 'XP Cost',
      'XTRAFEATS'                         => 'Extra Feats',
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
   'ADD:.CLEAR'            => 1,
   'ADD:CLASSSKILLS'       => 1,
   'ADD:DOMAIN'            => 1,
   'ADD:EQUIP'             => 1,
   'ADD:FAVOREDCLASS'      => 1,
   'ADD:LANGUAGE'          => 1,
   'ADD:SAB'               => 1,
   'ADD:SPELLCASTER'       => 1,
   'ADD:SKILL'             => 1,
   'ADD:TEMPLATE'          => 1,
   'ADD:WEAPONPROFS'       => 1,

   'ADD:FEAT'              => 1,    # Deprecated
   'ADD:FORCEPOINT'        => 1,    # Deprecated - never heard of this!
   'ADD:INIT'              => 1,    # Deprecated
   'ADD:SPECIAL'           => 1,    # Deprecated - Remove 5.16 - Special abilities are now set using hidden feats or Abilities.
   'ADD:VFEAT'             => 1,    # Deprecated
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
   'CLASS Level'     => 1,
   'CLASS'           => 1,
   'COMPANIONMOD'    => 1,
   'DATACONTROL'     => 1,
   'DEITY'           => 1,
   'DOMAIN'          => 1,
   'EQUIPMENT'       => 1,
   'EQUIPMOD'        => 1,
   'FEAT'            => 1,
   'GLOBALMOD'       => 1,
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

# Some people may still want to use the old ways (for PCGen v5.9.5 and older)
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
   
# New files already added

# ALIGNMENT
# DATACONTROL
# GLOBALMODIFIER
# SAVE
# STAT
# VARIABLE

# New files, not added yet

   'DATATABLE' => [
      \%SourceLineDef,
   ],

   'DYNAMIC' => [
      \%SourceLineDef,
   ],

   'SIZE' => [
      \%SourceLineDef,
      {  Linetype       => 'DATACONTROL',
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


=head2 getMissingHeaderLineTypes

   Get a list of the line types with missing headers.

=cut

sub getMissingHeaderLineTypes {
   return keys %missing_headers;
}

=head2 getHeaderMissingOnLineType

   Get a list of the line types with missing headers.

=cut

sub  getHeaderMissingOnLineType {
   my ($lineType) = @_;
   return keys %{ $missing_headers{$lineType} };
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

   my $log = getLogger();

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
      $log->notice(
         qq{Invalid tag "$potentialAddTag" found in } . $tag->lineType,
         $tag->file,
         $tag->line
      );
      $tag->noMoreErrors(1);

   } else {

      LstTidy::Report::incCountInvalidTags($tag->lineType, "AUTO");
      $log->notice(
         qq{Invalid ADD tag "} . $tag->origTag . q{" found in } . $tag->lineType,
         $tag->file,
         $tag->line
      );
      $tag->noMoreErrors(1);

   }
}


###############################################################
# parseLine
# ------------------------
#
# This function does additional parsing on each line once
# they have been seperated into tags.
#
# Most commun use is for addition, conversion or removal of tags.
#
# Paramter: $filetype   Type for the current file
#           $lineTokens Ref to a hash containing the tags of the line
#           $file       Name of the current file
#           $line       Number of the current line
#           $line_info  (Optional) structure generated by FILETYPE_parse
#


sub parseLine {

   my ( $filetype, $lineTokens, $file, $line, $line_info ) = @_;

   my $log = getLogger();

   ##################################################################
   # [ 1596310 ] xcheck: TYPE:Spellbook for equip w/ NUMPAGES and PAGEUSAGE
   # Gawaine42 (Richard)
   # Check to see if the TYPE contains Spellbook, if so, warn if
   # NUMUSES or PAGEUSAGE aren't there.
   # Then check to see if NUMPAGES or PAGEUSAGE are there, and if they
   # are there, but the TYPE doesn't contain Spellbook, warn.

   if ($filetype eq 'EQUIPMENT') {

      if (exists $lineTokens->{'TYPE'} && $lineTokens->{'TYPE'}[0] =~ /Spellbook/) {

         if (exists $lineTokens->{'NUMPAGES'} && exists $lineTokens->{'PAGEUSAGE'}) {
            #Nothing to see here, move along.
         } else {
            $log->info(
               qq{You have a Spellbook defined without providing NUMPAGES or PAGEUSAGE.} 
               . qq{ If you want a spellbook of finite capacity, consider adding these tags.},
               $file,
               $line
            );
         }

      } else {

         if (exists $lineTokens->{'NUMPAGES'} ) {
            $log->warning(
               qq{Invalid use of NUMPAGES tag in a non-spellbook. Remove this tag, or correct the TYPE.},
               $file,
               $line
            );
         }

         if  (exists $lineTokens->{'PAGEUSAGE'})
         {
            $log->warning(
               qq{Invalid use of PAGEUSAGE tag in a non-spellbook. Remove this tag, or correct the TYPE.},
               $file,
               $line
            );
         }
      }

      #################################################################
      #  Do the same for Type Container with and without CONTAINS
      if (exists $lineTokens->{'TYPE'} && $lineTokens->{'TYPE'}[0] =~ /Container/) {

         if (exists $lineTokens->{'CONTAINS'}) {
#                       $lineTokens =~ s/'CONTAINS:-1'/'CONTAINS:UNLIM'/g;   # [ 1777282 ] CONTAINS Unlimited Weight is UNLIM, not -1
         } else {
            $log->warning(
               qq{Any object with TYPE:Container must also have a CONTAINS tag to be activated.},
               $file,
               $line
            );
         }

      } elsif (exists $lineTokens->{'CONTAINS'}) {

         $log->warning(
            qq{Any object with CONTAINS must also be TYPE:Container for the CONTAINS tag to be activated.},
            $file,
            $line
         );
      }

   }

   ##################################################################
   # [ 1864711 ] Convert ADD:SA to ADD:SAB
   #
   # In most files, take ADD:SA and replace with ADD:SAB

   if (isConversionActive('ALL:Convert ADD:SA to ADD:SAB') && exists $lineTokens->{'ADD:SA'}) {
      $log->warning(
         qq{Change ADD:SA for ADD:SAB in "$lineTokens->{'ADD:SA'}[0]"},
         $file,
         $line
      );
      my $satag;
      $satag = $lineTokens->{'ADD:SA'}[0];
      $satag =~ s/ADD:SA/ADD:SAB/;
      $lineTokens->{'ADD:SAB'}[0] = $satag;
      delete $lineTokens->{'ADD:SA'};
   }



   ##################################################################
   # [ 1514765 ] Conversion to remove old defaultmonster tags
   # Gawaine42 (Richard Bowers)
   # Bonuses associated with a PREDEFAULTMONSTER:Y need to be removed
   # This should remove the whole tag.
   if (isConversionActive('RACE:Fix PREDEFAULTMONSTER bonuses') && $filetype eq "RACE") {

      for my $key ( keys %$lineTokens ) {

         my $ary = $lineTokens->{$key};
         my $iCount = 0;

         foreach (@$ary) {
            my $ttag = $$ary[$iCount];
            if ($ttag =~ /PREDEFAULTMONSTER:Y/) {
               $$ary[$iCount] = "";
               $log->warning(
                  qq{Removing "$ttag".},
                  $file,
                  $line
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

   if (   isConversionActive('EQUIP: ALTCRITICAL to ALTCRITMULT')
      && $filetype eq "EQUIPMENT"
      && exists $lineTokens->{'ALTCRITICAL'}
   ) {
      # Throw warning if both ALTCRITICAL and ALTCRITMULT are on the same line,
      #   then remove ALTCRITICAL.
      if ( exists $lineTokens->{ALTCRITMULT} ) {
         $log->warning(
            qq{Removing ALTCRITICAL, ALTCRITMULT already present on same line.},
            $file,
            $line
         );
         delete $lineTokens->{'ALTCRITICAL'};
      } else {
         $log->warning(
            qq{Change ALTCRITICAL for ALTCRITMULT in "$lineTokens->{'ALTCRITICAL'}[0]"},
            $file,
            $line
         );
         my $ttag;
         $ttag = $lineTokens->{'ALTCRITICAL'}[0];
         $ttag =~ s/ALTCRITICAL/ALTCRITMULT/;
         $lineTokens->{'ALTCRITMULT'}[0] = $ttag;
         delete $lineTokens->{'ALTCRITICAL'};
      }
   }


   ##################################################################
   # [ 1514765 ] Conversion to remove old defaultmonster tags
   #
   # In RACE files, remove all MFEAT and HITDICE tags, but only if
   # there is a MONSTERCLASS present.

   # We remove MFEAT or warn of missing MONSTERCLASS tag.
   if (   isConversionActive('RACE:Remove MFEAT and HITDICE')
      && $filetype eq "RACE"
      && exists $lineTokens->{'MFEAT'}
   ) { if ( exists $lineTokens->{'MONSTERCLASS'}
      ) { for my $tag ( @{ $lineTokens->{'MFEAT'} } ) {
            $log->warning(
               qq{Removing "$tag".},
               $file,
               $line
            );
         }
         delete $lineTokens->{'MFEAT'};
      }
      else {$log->warning(
            qq{MONSTERCLASS missing on same line as MFEAT, need to look at by hand.},
            $file,
            $line
         );
      }
   }

   # We remove HITDICE or warn of missing MONSTERCLASS tag.
   if (   isConversionActive('RACE:Remove MFEAT and HITDICE')
      && $filetype eq "RACE"
      && exists $lineTokens->{'HITDICE'}
   ) { if ( exists $lineTokens->{'MONSTERCLASS'}
      ) { for my $tag ( @{ $lineTokens->{'HITDICE'} } ) {
            $log->warning(
               qq{Removing "$tag".},
               $file,
               $line
            );
         }
         delete $lineTokens->{'HITDICE'};
      }
      else {$log->warning(
            qq{MONSTERCLASS missing on same line as HITDICE, need to look at by hand.},
            $file,
            $line
         );
      }
   }

   #######################################################
   ## [ 1689538 ] Conversion: Deprecation of FOLLOWERALIGN
   ## Gawaine42
   ## Note: Makes simplifying assumption that FOLLOWERALIGN
   ## will occur only once in a given line, although DOMAINS may
   ## occur multiple times.
   if ((isConversionActive('DEITY:Followeralign conversion'))
      && $filetype eq "DEITY"
      && (exists $lineTokens->{'FOLLOWERALIGN'}))
   {
      my $followeralign = $lineTokens->{'FOLLOWERALIGN'}[0];
      $followeralign =~ s/^FOLLOWERALIGN://;
      my $newprealign = "";
      my $aligncount  = 0;
      my @valid_alignments = getValidSystemArr('alignments');

      for my $align (split //, $followeralign) {
         # Is it a number?
         my $number;
         if ( (($number) = ($align =~ / \A (\d+) \z /xms))
            && $number >= 0
            && $number < scalar @valid_alignments)
         {
            my $newalign = $valid_alignments[$number];
            if ($aligncount > 0) {
               $newprealign .= ',';
            }
            $aligncount++;
            $newprealign .= "$newalign";
         }
         else {
            $log->notice(
               qq{Invalid value "$align" for tag "$lineTokens->{'FOLLOWERALIGN'}[0]"},
               $file,
               $line
            );

         }
      }

      my $dom_count=0;

      if (exists $lineTokens->{'DOMAINS'}) {
         for my $line ($lineTokens->{'DOMAINS'})
         {
            $lineTokens->{'DOMAINS'}[$dom_count] .= "|PREALIGN:$newprealign";
            $dom_count++;
         }
         $log->notice(
            qq{Adding PREALIGN to domain information and removing "$lineTokens->{'FOLLOWERALIGN'}[0]"},
            $file,
            $line
         );

         delete $lineTokens->{'FOLLOWERALIGN'};
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
      && not ( exists $lineTokens->{'RACETYPE'} )
      && not ( exists $lineTokens->{'TYPE'}  )
   ) {
      # .MOD / .FORGET / .COPY don't need RACETYPE or TYPE'
      my $race_name = $lineTokens->{'000RaceName'}[0];
      if ($race_name =~ /\.(FORGET|MOD|COPY=.+)$/) {
      } else { $log->warning(
            qq{Race entry missing both TYPE and RACETYPE.},
            $file,
            $line
         );
      }
   };

   if (   isConversionActive('RACE:TYPE to RACETYPE')
      && ( $filetype eq "RACE"
         || $filetype eq "TEMPLATE" )
      && not (exists $lineTokens->{'RACETYPE'})
      && exists $lineTokens->{'TYPE'}
   ) { $log->warning(
         qq{Changing TYPE for RACETYPE in "$lineTokens->{'TYPE'}[0]".},
         $file,
         $line
      );
      $lineTokens->{'RACETYPE'} = [ "RACE" . $lineTokens->{'TYPE'}[0] ];
      delete $lineTokens->{'TYPE'};
   };

#                       $lineTokens->{'MONCSKILL'} = [ "MON" . $lineTokens->{'CSKILL'}[0] ];
#                       delete $lineTokens->{'CSKILL'};


   ##################################################################
   # [ 1444527 ] New SOURCE tag format
   #
   # The SOURCELONG tags found on any linetype but the SOURCE line type must
   # be converted to use tab if | are found.

   if (   isConversionActive('ALL:New SOURCExxx tag format')
      && exists $lineTokens->{'SOURCELONG'} ) {
      my @new_tags;

      for my $tag ( @{ $lineTokens->{'SOURCELONG'} } ) {
         if( $tag =~ / [|] /xms ) {
            push @new_tags, split '\|', $tag;
            $log->warning(
               qq{Spliting "$tag"},
               $file,
               $line
            );
         }
      }

      if( @new_tags ) {
         delete $lineTokens->{'SOURCELONG'};

         for my $new_tag (@new_tags) {
            my ($tag_name) = ( $new_tag =~ / ( [^:]* ) [:] /xms );
            push @{ $lineTokens->{$tag_name} }, $new_tag;
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

   if ( isConversionActive('ALL:Convert SPELL to SPELLS')
      && exists $lineTokens->{'SPELL'} )
   {
      my %spellbooks;

      # We parse all the existing SPELL tags
      for my $tag ( @{ $lineTokens->{'SPELL'} } ) {
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
                  $file,
                  $line
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
            $file,
            $line
         );
      }

      # We delete the SPELL tags
      delete $lineTokens->{'SPELL'};

      # We add the new SPELLS tags
      for my $spellbook ( sort keys %spellbooks ) {
         for my $times ( sort keys %{ $spellbooks{$spellbook} } ) {
            for my $pretags ( sort keys %{ $spellbooks{$spellbook}{$times} } ) {
               my $spells = "SPELLS:$spellbook|TIMES=$times";

               for my $spellname ( sort @{ $spellbooks{$spellbook}{$times}{$pretags} } ) {
                  $spells .= "|$spellname";
               }

               $spells .= "|$pretags" unless $pretags eq "NONE";

               $log->warning( qq{Adding   "$spells"}, $file, $line );

               push @{ $lineTokens->{'SPELLS'} }, $spells;
            }
         }
      }
   }

   ##################################################################
   # We get rid of all the PREALIGN tags.
   #
   # This is needed by my good CMP friends.

   if ( isConversionActive('ALL:CMP remove PREALIGN') ) {
      if ( exists $lineTokens->{'PREALIGN'} ) {
         my $number = +@{ $lineTokens->{'PREALIGN'} };
         delete $lineTokens->{'PREALIGN'};
         $log->warning(
            qq{Removing $number PREALIGN tags},
            $file,
            $line
         );
      }

      if ( exists $lineTokens->{'!PREALIGN'} ) {
         my $number = +@{ $lineTokens->{'!PREALIGN'} };
         delete $lineTokens->{'!PREALIGN'};
         $log->warning(
            qq{Removing $number !PREALIGN tags},
            $file,
            $line
         );
      }
   }

   ##################################################################
   # Need to fix the STR bonus when the monster have only one
   # Natural Attack (STR bonus is then 1.5 * STR).
   # We add it if there is only one Melee attack and the
   # bonus is not already present.

   if ( isConversionActive('ALL:CMP NatAttack fix')
      && exists $lineTokens->{'NATURALATTACKS'} )
   {

      # First we verify if if there is only one melee attack.
      if ( @{ $lineTokens->{'NATURALATTACKS'} } == 1 ) {
         my @NatAttacks = split '\|', $lineTokens->{'NATURALATTACKS'}[0];
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
                  if ( exists $lineTokens->{'BONUS:WEAPONPROF'} ) {
                     my $AlreadyThere = 0;
                     FIND_BONUS:
                     for my $bonus ( @{ $lineTokens->{'BONUS:WEAPONPROF'} } ) {
                        if ( $bonus eq "BONUS:WEAPONPROF=$NatAttackName|DAMAGE|STR/2" )
                        {
                           $AlreadyThere = 1;
                           last FIND_BONUS;
                        }
                     }

                     unless ($AlreadyThere) {
                        push @{ $lineTokens->{'BONUS:WEAPONPROF'} },
                        "BONUS:WEAPONPROF=$NatAttackName|DAMAGE|STR/2";
                        $log->warning(
                           qq{Added "$lineTokens->{'BONUS:WEAPONPROF'}[0]"}
                           . qq{ to go with "$lineTokens->{'NATURALATTACKS'}[0]"},
                           $file,
                           $line
                        );
                     }
                  }
                  else {
                     $lineTokens->{'BONUS:WEAPONPROF'}
                     = ["BONUS:WEAPONPROF=$NatAttackName|DAMAGE|STR/2"];
                     $log->warning(
                        qq{Added "$lineTokens->{'BONUS:WEAPONPROF'}[0]"}
                        . qq{to go with "$lineTokens->{'NATURALATTACKS'}[0]"},
                        $file,
                        $line
                     );
                  }
               }
               elsif ( $IsMelee && $IsRanged ) {
                  $log->warning(
                     qq{This natural attack is both Melee and Ranged}
                     . qq{"$lineTokens->{'NATURALATTACKS'}[0]"},
                     $file,
                     $line
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

   if (   isConversionActive('EQUIP:no more MOVE')
      && $filetype eq "EQUIPMENT"
      && exists $lineTokens->{'MOVE'} )
   {
      $log->warning( qq{Removed MOVE tags}, $file, $line );
      delete $lineTokens->{'MOVE'};
   }

   if (   isConversionActive('CLASS:no more HASSPELLFORMULA')
      && $filetype eq "CLASS"
      && exists $lineTokens->{'HASSPELLFORMULA'} )
   {
      $log->warning( qq{Removed deprecated HASSPELLFORMULA tags}, $file, $line );
      delete $lineTokens->{'HASSPELLFORMULA'};
   }


   ##################################################################
   # Every RACE that has a Climb or a Swim MOVE must have a
   # BONUS:SKILL|Climb|8|TYPE=Racial. If there is a
   # BONUS:SKILLRANK|Swim|8|PREDEFAULTMONSTER:Y present, it must be
   # removed or lowered by 8.

   if (   isConversionActive('RACE:BONUS SKILL Climb and Swim')
      && $filetype eq "RACE"
      && exists $lineTokens->{'MOVE'} )
   {
      my $swim  = $lineTokens->{'MOVE'}[0] =~ /swim/i;
      my $climb = $lineTokens->{'MOVE'}[0] =~ /climb/i;

      if ( $swim || $climb ) {
         my $need_swim  = 1;
         my $need_climb = 1;

         # Is there already a BONUS:SKILL|Swim of at least 8 rank?
         if ( exists $lineTokens->{'BONUS:SKILL'} ) {
            for my $skill ( @{ $lineTokens->{'BONUS:SKILL'} } ) {
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
                        $file,
                        $line
                     );
                  }

                  if ( $need_climb && $skill_rank == 8 ) {
                     $skill_list
                     = join( ',', sort( split ( ',', $skill_list ), 'Climb' ) );
                     $skill = "BONUS:SKILL|$skill_list|8|TYPE=Racial";
                     $log->warning(
                        qq{Added Climb to "$skill"},
                        $file,
                        $line
                     );
                  }

                  if ( ( $need_climb || $need_swim ) && $skill_rank != 8 ) {
                     $log->info(
                        qq{You\'ll have to deal with this one yourself "$skill"},
                        $file,
                        $line
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
         if ( exists $lineTokens->{'BONUS:SKILLRANK'} ) {
            for ( my $index = 0; $index < @{ $lineTokens->{'BONUS:SKILLRANK'} }; $index++ ) {
               my $skillrank = $lineTokens->{'BONUS:SKILLRANK'}[$index];

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
                              $file,
                              $line
                           );
                        }
                        else {
                           $log->warning(
                              qq{Removing "$skillrank"},
                              $file,
                              $line
                           );
                           delete $lineTokens->{'BONUS:SKILLRANK'}[$index];
                           $index--;
                        }
                     }
                     else {
                        $log->info(
                           qq{You\'ll have to deal with this one yourself "$skillrank"},
                           $file,
                           $line
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
                              $file,
                              $line
                           );
                        }
                        else {
                           $log->warning(
                              qq{Removing "$skillrank"},
                              $file,
                              $line
                           );
                           delete $lineTokens->{'BONUS:SKILLRANK'}[$index];
                           $index--;
                        }
                     }
                     else {
                        $log->info(
                           qq{You\'ll have to deal with this one yourself "$skillrank"},
                           $file,
                           $line
                        );
                     }
                  }
               }
            }

            # If there are no more BONUS:SKILLRANK, we remove the tag entry
            delete $lineTokens->{'BONUS:SKILLRANK'}
            unless @{ $lineTokens->{'BONUS:SKILLRANK'} };
         }
      }
   }

   ##################################################################
   # [ 845853 ] SIZE is no longer valid in the weaponprof files
   #
   # The SIZE tag must be removed from all WEAPONPROF files since it
   # cause loading problems with the latest versio of PCGEN.

   if (   isConversionActive('WEAPONPROF:No more SIZE')
      && $filetype eq "WEAPONPROF"
      && exists $lineTokens->{'SIZE'} )
   {
      my $tagLookup = @{LstTidy::Reformat::getLineTypeOrder('WEAPONPROF')}[0];

      $log->warning(
         qq{Removing the SIZE tag in line "$lineTokens->{$tagLookup}[0]"},
         $file,
         $line
      );
      delete $lineTokens->{'SIZE'};
   }

   ##################################################################
   # [ 832164 ] Adding NoProfReq to AUTO:WEAPONPROF for most races
   #
   # NoProfReq must be added to AUTO:WEAPONPROF if the race has
   # at least one hand and if NoProfReq is not already there.

   if (   isConversionActive('RACE:NoProfReq')
      && $filetype eq "RACE" )
   {
      my $needNoProfReq = 1;

      # Is NoProfReq already present?
      if ( exists $lineTokens->{'AUTO:WEAPONPROF'} ) {
         $needNoProfReq = 0 if $lineTokens->{'AUTO:WEAPONPROF'}[0] =~ /NoProfReq/;
      }

      my $nbHands = 2;        # Default when no HANDS tag is present

      # How many hands?
      if ( exists $lineTokens->{'HANDS'} ) {
         if ( $lineTokens->{'HANDS'}[0] =~ /HANDS:(\d+)/ ) {
            $nbHands = $1;
         }
         else {
            $log->info(
               qq(Invalid value in tag "$lineTokens->{'HANDS'}[0]"),
               $file,
               $line
            );
            $needNoProfReq = 0;
         }
      }

      if ( $needNoProfReq && $nbHands ) {
         if ( exists $lineTokens->{'AUTO:WEAPONPROF'} ) {
            $log->warning(
               qq{Adding "TYPE=NoProfReq" to tag "$lineTokens->{'AUTO:WEAPONPROF'}[0]"},
               $file,
               $line
            );
            $lineTokens->{'AUTO:WEAPONPROF'}[0] .= "|TYPE=NoProfReq";
         }
         else {
            $lineTokens->{'AUTO:WEAPONPROF'} = ["AUTO:WEAPONPROF|TYPE=NoProfReq"];
            $log->warning(
               qq{Creating new tag "AUTO:WEAPONPROF|TYPE=NoProfReq"},
               $file,
               $line
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

   if (   isConversionActive('RACE:CSKILL to MONCSKILL')
      && $filetype eq "RACE"
      && exists $lineTokens->{'CSKILL'}
      && exists $lineTokens->{'MONSTERCLASS'}
      && !exists $lineTokens->{'MONCSKILL'} )
   {
      $log->warning(
         qq{Change CSKILL for MONSKILL in "$lineTokens->{'CSKILL'}[0]"},
         $file,
         $line
      );

      $lineTokens->{'MONCSKILL'} = [ "MON" . $lineTokens->{'CSKILL'}[0] ];
      delete $lineTokens->{'CSKILL'};
   }

   ##################################################################
   # [ 728038 ] BONUS:VISION must replace VISION:.ADD
   #
   # VISION:.ADD must be converted to BONUS:VISION
   # Some exemple of VISION:.ADD tags:
   #   VISION:.ADD,Darkvision (60')
   #   VISION:1,Darkvision (60')
   #   VISION:.ADD,See Invisibility (120'),See Etheral (120'),Darkvision (120')

   if (   isConversionActive('ALL: , to | in VISION')
      && exists $lineTokens->{'VISION'}
      && $lineTokens->{'VISION'}[0] =~ /(\.ADD,|1,)(.*)/i )
   {
      $log->warning(
         qq{Removing "$lineTokens->{'VISION'}[0]"},
         $file,
         $line
      );

      my $newvision = "VISION:";
      my $coma;

      for my $vision_bonus ( split ',', $2 ) {
         if ( $vision_bonus =~ /(\w+)\s*\((\d+)\'\)/ ) {
            my ( $type, $bonus ) = ( $1, $2 );
            push @{ $lineTokens->{'BONUS:VISION'} }, "BONUS:VISION|$type|$bonus";
            $log->warning(
               qq{Adding "BONUS:VISION|$type|$bonus"},
               $file,
               $line
            );
            $newvision .= "$coma$type (0')";
            $coma = ',';
         }
         else {
            $log->error(
               qq(Do not know how to convert "VISION:.ADD,$vision_bonus"),
               $file,
               $line
            );
         }
      }

      $log->warning( qq{Adding "$newvision"}, $file, $line );

      $lineTokens->{'VISION'} = [$newvision];
   }

   ##################################################################
   #
   #
   # For items with TYPE:Boot, Glove, Bracer, we must check for plural
   # form and add a SLOTS:2 tag is the item is plural.

   if (   isConversionActive('EQUIPMENT: SLOTS:2 for plurals')
      && $filetype            eq 'EQUIPMENT'
      && $line_info->[0] eq 'EQUIPMENT'
      && !exists $lineTokens->{'SLOTS'} )
   {
      my $tagLookup = @{LstTidy::Reformat::getLineTypeOrder('EQUIPMENT')}[0];
      my $equipment_name = $lineTokens->{ $tagLookup }[0];

      if ( exists $lineTokens->{'TYPE'} ) {
         my $type = $lineTokens->{'TYPE'}[0];
         if ( $type =~ /(Boot|Glove|Bracer)/ ) {
            if (   $1 eq 'Boot' && $equipment_name =~ /boots|sandals/i
               || $1 eq 'Glove'  && $equipment_name =~ /gloves|gauntlets|straps/i
               || $1 eq 'Bracer' && $equipment_name =~ /bracers|bracelets/i )
            {
               $lineTokens->{'SLOTS'} = ['SLOTS:2'];
               $log->warning(
                  qq{"SLOTS:2" added to "$equipment_name"},
                  $file,
                  $line
               );
            }
            else {
               $log->error( qq{"$equipment_name" is a $1}, $file, $line );
            }
         }
      }
      else {
         $log->warning(
            qq{$equipment_name has no TYPE.},
            $file,
            $line
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

   if ( isConversionActive('EQUIPMENT: generate EQMOD') ) {
      if (   $filetype eq 'SPELL'
         && $line_info->[0] eq 'SPELL'
         && ( exists $lineTokens->{'CLASSES'} ) )
      {
         my $spell_name  = $lineTokens->{'000SpellName'}[0];
         my $spell_level = -1;

         CLASS:
         for ( split '\|', $lineTokens->{'CLASSES'}[0] ) {
            if ( index( $_, 'Wizard' ) != -1 || index( $_, 'Cleric' ) != -1 ) {
               $spell_level = (/=(\d+)$/)[0];
               last CLASS;
            }
         }

         $spellsForEQMOD{$spell_name} = $spell_level
         if $spell_level > -1;

      }
      elsif ($filetype eq 'EQUIPMENT'
         && $line_info->[0] eq 'EQUIPMENT'
         && ( !exists $lineTokens->{'EQMOD'} ) )
      {
         my $equip_name = $lineTokens->{'000EquipmentName'}[0];
         my $spell_name;

         if ( $equip_name =~ m{^Wand \((.*)/(\d\d?)(st|rd|th) level caster\)} ) {
            $spell_name = $1;
            my $caster_level = $2;

            if ( exists $spellsForEQMOD{$spell_name} ) {
               my $spell_level = $spellsForEQMOD{$spell_name};
               my $eqmod_tag   = "EQMOD:SE_50TRIGGER|SPELLNAME[$spell_name]"
               . "SPELLLEVEL[$spell_level]"
               . "CASTERLEVEL[$caster_level]CHARGES[50]";
               $lineTokens->{'EQMOD'}    = [$eqmod_tag];
               $lineTokens->{'BASEITEM'} = ['BASEITEM:Wand']
               unless exists $lineTokens->{'BASEITEM'};
               delete $lineTokens->{'COST'} if exists $lineTokens->{'COST'};
               $log->warning(
                  qq{$equip_name: removing "COST" and adding "$eqmod_tag"},
                  $file,
                  $line
               );
            }
            else {
               $log->warning(
                  qq($equip_name: not enough information to add charges),
                  $file,
                  $line
               );
            }
         }
         elsif ( $equip_name =~ /^Wand \((.*)\)/ ) {
            $spell_name = $1;
            if ( exists $spellsForEQMOD{$spell_name} ) {
               my $spell_level  = $spellsForEQMOD{$spell_name};
               my $caster_level = $spell_level * 2 - 1;
               my $eqmod_tag   = "EQMOD:SE_50TRIGGER|SPELLNAME[$spell_name]"
               . "SPELLLEVEL[$spell_level]"
               . "CASTERLEVEL[$caster_level]CHARGES[50]";
               $lineTokens->{'EQMOD'} = [$eqmod_tag];
               delete $lineTokens->{'COST'} if exists $lineTokens->{'COST'};
               $log->warning(
                  qq{$equip_name: removing "COST" and adding "$eqmod_tag"},
                  $file,
                  $line
               );
            }
            else {
               $log->warning(
                  qq{$equip_name: not enough information to add charges},
                  $file,
                  $line
               );
            }
         }
         elsif ( $equip_name =~ /^Wand/ ) {
            $log->warning(
               qq{$equip_name: not enough information to add charges},
               $file,
               $line
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

   if (   isConversionActive('BIOSET:generate the new files')
      && $filetype            eq 'RACE'
      && $line_info->[0] eq 'RACE'
      && (   exists $lineTokens->{'AGE'}
         || exists $lineTokens->{'HEIGHT'}
         || exists $lineTokens->{'WEIGHT'} )
   ) {
      my ( $tagLookup, $dir, $race, $age, $height, $weight );

      $tagLookup = @{LstTidy::Reformat::getLineTypeOrder('RACE')}[0];
      $dir       = File::Basename::dirname($file);
      $race      = $lineTokens->{ $tagLookup }[0];

      if ( $lineTokens->{'AGE'} ) {
         $age = $lineTokens->{'AGE'}[0];
         $log->warning( qq{Removing "$lineTokens->{'AGE'}[0]"}, $file, $line );
         delete $lineTokens->{'AGE'};
      }
      if ( $lineTokens->{'HEIGHT'} ) {
         $height = $lineTokens->{'HEIGHT'}[0];
         $log->warning( qq{Removing "$lineTokens->{'HEIGHT'}[0]"}, $file, $line );
         delete $lineTokens->{'HEIGHT'};
      }
      if ( $lineTokens->{'WEIGHT'} ) {
         $weight = $lineTokens->{'WEIGHT'}[0];
         $log->warning( qq{Removing "$lineTokens->{'WEIGHT'}[0]"}, $file, $line );
         delete $lineTokens->{'WEIGHT'};
      }

      record_bioset_tags( $dir, $race, $age, $height, $weight, $file,
         $line );
   }

   ##################################################################
   # [ 653596 ] Add a TYPE tag for all SPELLs
   # .

   if (   isConversionActive('SPELL:Add TYPE tags')
      && exists $lineTokens->{'SPELLTYPE'}
      && $filetype            eq 'CLASS'
      && $line_info->[0] eq 'CLASS'
   ) {

      # We must keep a list of all the SPELLTYPE for each class.
      # It is assumed that SPELLTYPE cannot be found more than once
      # for the same class. It is also assumed that SPELLTYPE has only
      # one value. SPELLTYPE:Any is ignored.

      my $tagLookup = @{LstTidy::Reformat::getLineTypeOrder('CLASS')}[0];
      my $className = $lineTokens->{ $tagLookup }[0];
      SPELLTYPE_TAG:
      for my $spelltype_tag ( values %{ $lineTokens->{'SPELLTYPE'} } ) {
         my $spelltype = "";
         ($spelltype) = ($spelltype_tag =~ /SPELLTYPE:(.*)/);
         next SPELLTYPE_TAG if $spelltype eq "" or uc($spelltype) eq "ANY";
         $classSpellTypes{$className}{$spelltype}++;
      }
   }

   if (isConversionActive('SPELL:Add TYPE tags') && $filetype eq 'SPELL' && $line_info->{Linetype} eq 'SPELL' ) {

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

   if (   isConversionActive('SOURCE line replacement')
      && defined $line_info
      && $line_info->[0] eq 'SOURCE'
      && $sourceCurrentFile ne $file )
   {

      my $inputpath =  getOption('inputpath');
      # Only the first SOURCE tag is replaced.
      if ( exists $sourceTags{ File::Basename::dirname($file) } ) {

         # We replace the line with a concatanation of SOURCE tags found in
         # the directory .PCC
         my %line_tokens;
         while ( my ( $tag, $value )
            = each %{ $sourceTags{ File::Basename::dirname($file) } } )
         {
            $line_tokens{$tag} = [$value];
            $sourceCurrentFile = $file;
         }

         $line_info->[1] = \%line_tokens;
      }
      elsif ( $file =~ / \A ${inputpath} /xmsi ) {
         # We give this notice only if the curent file is under getOption('inputpath').
         # If -basepath is used, there could be files loaded outside of the -inputpath
         # without their PCC.
         $log->notice( "No PCC source information found", $file, $line );
      }
   }

   # Extract lists
   # ====================
   # Export each file name and log them with the filename and the
   # line number

   if ( isConversionActive('Export lists') ) {
      my $filename = $file;
      $filename =~ tr{/}{\\};

      if ( $filetype eq 'SPELL' ) {

         # Get the spell name
         my $spellname  = $lineTokens->{'000SpellName'}[0];
         my $sourcepage = "";
         $sourcepage = $lineTokens->{'SOURCEPAGE'}[0] if exists $lineTokens->{'SOURCEPAGE'};

         # Write to file
         LstTidy::Report::printToExportList('SPELL', qq{"$spellname","$sourcepage","$line","$filename"\n});
      }
      if ( $filetype eq 'CLASS' ) {
         my $class = ( $lineTokens->{'000ClassName'}[0] =~ /^CLASS:(.*)/ )[0];
         if ($className ne $class) {
            LstTidy::Report::printToExportList('CLASS', qq{"$class","$line","$filename"\n})
         };
         $className = $class;
      }

      if ( $filetype eq 'DEITY' ) {
         LstTidy::Report::printToExportList('DEITY', qq{"$lineTokens->{'000DeityName'}[0]","$line","$filename"\n});
      }

      if ( $filetype eq 'DOMAIN' ) {
         LstTidy::Report::printToExportList('DOMAIN', qq{"$lineTokens->{'000DomainName'}[0]","$line","$filename"\n});
      }

      if ( $filetype eq 'EQUIPMENT' ) {
         my $tagLookup = @{LstTidy::Reformat::getLineTypeOrder($filetype)}[0];
         my $equipname  = $lineTokens->{ $tagLookup }[0];
         my $outputname = "";
         $outputname = substr( $lineTokens->{'OUTPUTNAME'}[0], 11 )
         if exists $lineTokens->{'OUTPUTNAME'};
         my $replacementname = $equipname;
         if ( $outputname && $equipname =~ /\((.*)\)/ ) {
            $replacementname = $1;
         }
         $outputname =~ s/\[NAME\]/$replacementname/;
         LstTidy::Report::printToExportList('EQUIPMENT', qq{"$equipname","$outputname","$line","$filename"\n});
      }

      if ( $filetype eq 'EQUIPMOD' ) {
         my $tagLookup = @{LstTidy::Reformat::getLineTypeOrder($filetype)}[0];
         my $equipmodname = $lineTokens->{ $tagLookup }[0];
         my ( $key, $type ) = ( "", "" );
         $key  = substr( $lineTokens->{'KEY'}[0],  4 ) if exists $lineTokens->{'KEY'};
         $type = substr( $lineTokens->{'TYPE'}[0], 5 ) if exists $lineTokens->{'TYPE'};
         LstTidy::Report::printToExportList('EQUIPMOD', qq{"$equipmodname","$key","$type","$line","$filename"\n});
      }

      if ( $filetype eq 'FEAT' ) {
         my $tagLookup = @{LstTidy::Reformat::getLineTypeOrder($filetype)}[0];
         my $featname = $lineTokens->{ $tagLookup }[0];
         LstTidy::Report::printToExportList('FEAT', qq{"$featname","$line","$filename"\n});
      }

      if ( $filetype eq 'KIT STARTPACK' ) {
         my $tagLookup = @{LstTidy::Reformat::getLineTypeOrder($filetype)}[0];
         my ($kitname) = ( $lineTokens->{ $tagLookup }[0] =~ /\A STARTPACK: (.*) \z/xms );
         LstTidy::Report::printToExportList('KIT', qq{"$kitname","$line","$filename"\n});
      }

      if ( $filetype eq 'KIT TABLE' ) {
         my $tagLookup = @{LstTidy::Reformat::getLineTypeOrder($filetype)}[0];
         my ($tablename)
         = ( $lineTokens->{ $tagLookup }[0] =~ /\A TABLE: (.*) \z/xms );
         LstTidy::Report::printToExportList('TABLE', qq{"$tablename","$line","$filename"\n});
      }

      if ( $filetype eq 'LANGUAGE' ) {
         my $tagLookup = @{LstTidy::Reformat::getLineTypeOrder($filetype)}[0];
         my $languagename = $lineTokens->{ $tagLookup }[0];
         LstTidy::Report::printToExportList('LANGUAGE', qq{"$languagename","$line","$filename"\n});
      }

      if ( $filetype eq 'RACE' ) {
         my $tagLookup = @{LstTidy::Reformat::getLineTypeOrder($filetype)}[0];
         my $racename            = $lineTokens->{ $tagLookup }[0];

         my $race_type = q{};
         $race_type = $lineTokens->{'RACETYPE'}[0] if exists $lineTokens->{'RACETYPE'};
         $race_type =~ s{ \A RACETYPE: }{}xms;

         my $race_sub_type = q{};
         $race_sub_type = $lineTokens->{'RACESUBTYPE'}[0] if exists $lineTokens->{'RACESUBTYPE'};
         $race_sub_type =~ s{ \A RACESUBTYPE: }{}xms;

         LstTidy::Report::printToExportList('RACE', qq{"$racename","$race_type","$race_sub_type","$line","$filename"\n});
      }

      if ( $filetype eq 'SKILL' ) {
         my $tagLookup = @{LstTidy::Reformat::getLineTypeOrder($filetype)}[0];
         my $skillname = $lineTokens->{ $tagLookup }[0];
         LstTidy::Report::printToExportList('SKILL', qq{"$skillname","$line","$filename"\n});
      }

      if ( $filetype eq 'TEMPLATE' ) {
         my $tagLookup = @{LstTidy::Reformat::getLineTypeOrder($filetype)}[0];
         my $template_name = $lineTokens->{ $tagLookup }[0];
         LstTidy::Report::printToExportList('TEMPLATE', qq{"$template_name","$line","$filename"\n});
      }
   }

   ############################################################
   ######################## Conversion ########################
   # We manipulate the tags for the line here

   if ( isConversionActive('Generate BONUS and PRExxx report') ) {
      for my $tag_type ( sort keys %$lineTokens ) {
         if ( $tag_type =~ /^BONUS|^!?PRE/ ) {
            addToBonusAndPreReport($lineTokens, $filetype, $tag_type);
         }
      }
   }

   1;
}



=head2 parseProteanSubTag

   Parse the sub set of tokens where data can freely define sub tokens.  Such
   as FACT or QUALITY.

   Sume of these are standard and become tags with embeded colons (Similar to
   ADD). Others are accepted as valid as is, no token munging is done.

=cut

sub parseProteanSubTag {

   my ($tag) = @_;

   my $log = getLogger();

   # If this is s a subTag, the subTag is currently on the front of the value.
   my ($subTag) = ($tag->value =~ /^([^=:|]+)/ );

   my $potentialTag = $tag->id . ':' . $subTag;

   if ($subTag && exists $validSubTags{$tag->id}{$subTag}) {

      $tag->id($potentialTag);
      $tag->value($tag->value =~ s/^$subTag(.*)/$1/r);

   } elsif ($subTag) {
     
      # Give a really low priority note that we saw this. Mostly we don't care,
      # the data team can freely define these and they don't want to hear that
      # they've done that.
      $log->info(
         qq{Non-standard } . $tag->id . qq{ tag $potentialTag in "} . $tag->origTag . q{" found in } . $tag->lineType,
         $tag->file,
         $tag->line
      );

   } else {

      LstTidy::Report::incCountInvalidTags($tag->lineType, $tag->id);
      $log->notice(
         q{Invalid } . $tag->id . q{ tag "} . $tag->origTag . q{" found in } . $tag->lineType,
         $tag->file,
         $tag->line
      );
      $tag->noMoreErrors(1);
   }
}

=head2 parseSubTag

   Check that the sub token is valid and adjust the $tag if appropraite.

=cut

sub parseSubTag {

   my ($tag) = @_;

   my $log = getLogger();

   # If this is s a subTag, the subTag is currently on the front of the value.
   my ($subTag) = ($tag->value =~ /^([^=:|]+)/ );

   my $potentialTag = $tag->id . ':' . $subTag;

   if ($subTag && exists $validSubTags{$tag->id}{$subTag}) {

      $tag->id($potentialTag);
      $tag->value($tag->value =~ s/^$subTag(.*)/$1/r);

   } elsif ($subTag) {

      # No valid type found
      LstTidy::Report::incCountInvalidTags($tag->lineType, $potentialTag);
      $log->notice(
         qq{Invalid $potentialTag tag "} . $tag->origTag . q{" found in } . $tag->lineType,
         $tag->file,
         $tag->line
      );
      $tag->noMoreErrors(1);

   } else {

      LstTidy::Report::incCountInvalidTags($tag->lineType, $tag->id);
      $log->notice(
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

   my ($systemFilePath) = @_;

   my $originalSystemFilePath = $systemFilePath;
   
   my $log = getLogger();

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

   my $log = getLogger();

   # All PCGen tags should have at least TAG_NAME:TAG_VALUE (Some rare tags
   # have two colons). Anything without a tag value is an anomaly. The only
   # exception to this rule is LICENSE that can be used without a value to
   # display an empty line.

   if ( (!defined $tag->value || $tag->value eq q{}) && $tag->fullTag ne 'LICENSE:') {
      $log->warning(
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
      LstTidy::Validate::validateTag($tag)
   };

   if ($tag->value eq q{}) {
      $log->debug(qq{parseTag: } . $tag->fullTag, $tag->file, $tag->line)
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

      # Exit the loop
      return 1; #last COLUMN;

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

   # don't exit the loop
   return 0;
}

=head2 processAlign

   It is possible for the ALIGN and PREALIGN tags to have more then one value,
   make sure they are all valid. Convert them from number to text if necessary.

=cut

sub processAlign {

   my ($tag) = @_;

   my $log = getLogger();
      
   # Most of the limited values are uppercase except TIMEUNITS and the alignment value 'Deity'
   my $newvalue = $tag->value;
      
   my $is_valid = 1;

   # ALIGN uses | for separator, PREALIGN uses ,
   my $splitPatern = $tag->id eq 'PREALIGN' ? qr{[,]}xms : qr{[|]}xms;

   for my $value (split $splitPatern, $newvalue) {

      my $align = mungKey($tag->id , $value);

      # Is it a number?
      my ($number) = $align =~ / \A (\d+) \z /xms;

      if ( defined $number && $number >= 0 && $number < scalar @validSystemAlignments) {
         $align = $validSystemAlignments[$number];
         $newvalue =~ s{ (?<! \d ) ($number) (?! \d ) }{$align}xms;
      }

      # Is it a valid alignment?
      if (!exists $tagFixValue{$tag->id}{$align}) {
         $log->notice(
            qq{Invalid alignment "$align" for tag "} . $tag->realId . q{"},
            $tag->file,
            $tag->line
         );
         $is_valid = 0;
      }
   }

   # Was the tag changed ?
   if ( $is_valid && $tag->value ne $newvalue) {

      $tag->value($newvalue);

      $log->warning(
         qq{Replaced "} . $tag->origTag . q{" with "} . $tag->fullRealTag . qq{"},
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

=head2 mungKey

   Modify the key if possible, so that it is possible to use it to lookup one
   of the values of tags that only take fixed values.

=cut

sub mungKey {

   my ($tag, $key) = @_;

   # Possibly change the key, need to Standerdize YES, NO, etc.
   if ( exists $tagProperValue{$key} ) {
      $key = $tagProperValue{$key};
   } elsif ( exists $tagProperValue{uc $key} ) {
      $key = $tagProperValue{uc $key};
   }

   # make it uppercase if necessary for the lookup
   if (exists $tagFixValue{$tag}{uc $key}) {
      $key = uc $key;

   # make it titlecase if necessary for the lookup
   } elsif (exists $tagFixValue{$tag}{ucfirst lc $key}) {
      $key = ucfirst lc $key;
   }

   return $key
}

=head2 processNonAlign

   Any tag that has limited values but is not an ALIGN or PREALIGN can only
   have one value.  The value shold be uppercase, Check for validity and if
   necessary change the value.

=cut

sub processNonAlign {

   my ($tag) = @_;

   my $log = getLogger();

   # Convert the key if possible to make the lookup work
   my $value = mungKey($tag->id, $tag->value);

   # Warn if it's not a proper value
   if ( !exists $tagFixValue{$tag->id}{$value} ) {

      $log->notice(
         qq{Invalid value "} . $tag->value . q{" for tag "} . $tag->realId . q{"},
         $tag->file,
         $tag->line
      );

   # If we had to modify the lookup, change the data
   } elsif ($tag->value ne $value) {

      $tag->value = $value;

      $log->warning(
         qq{Replaced "} . $tag->origTag . q{" by "} . $tag->fullRealTag . qq{"},
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
   my $log = getLogger();

   # We remove the COUNT[xxx] from the formulas
   while ( $formula =~ s/(COUNT\[[^]]*\])//g ) {
      push @variable_names, $1;
   }

   # We have to catch all the VAR=Funky Text before anything else
   while ( $formula =~ s/([a-z][a-z0-9_]*=[a-z0-9_ =\{\}]*)//i ) {
      my @values = split '=', $1;
      if ( @values > 2 ) {

         # There should only be one = per variable
         $log->warning(
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

         $log->notice(
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
   my $log = getLogger();

   while ( pos $formula < length $formula ) {

      # If it's an identifier or a function
      if ( my ($ident) = ( $formula =~ / \G ( $isIdentRegex ) /xmsgc ) ) {

         # Identifiers are only valid after an operator or a separator
         if ( $last_token_type && $last_token_type ne 'operator' && $last_token_type ne 'separator' ) {

            # We "eat" the rest of the string and report an error
            my ($bogus_text) = ( $formula =~ / \G (.*) /xmsgc );
            $log->notice(
               qq{Jep syntax error near "$ident$bogus_text" found in "$tag"},
               $file,
               $line
            );

         # Indentificator followed by bracket = function
         } elsif ( $formula =~ / \G [(] /xmsgc ) {

            # It's a function, is it valid?
            if ( !$isJepFunction{$ident} ) {
               $log->notice(
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

                  $log->notice(
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
               $log->notice(
                  qq{Forgot to use var()? Dubious use of Jep variable assignation near }
                  . qq{"$last_token$operator" in "$tag"},
                  $file,
                  $line
               );

            } else {
               $log->notice(
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
            $log->notice(
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
            $log->notice(
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
            $log->notice(
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
            $log->notice(
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
