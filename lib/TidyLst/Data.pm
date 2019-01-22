package TidyLst::Data;

use strict;
use warnings;

use Data::Dumper;
use Scalar::Util;

use Carp;

require Exporter;

our @ISA = qw(Exporter);
our @EXPORT = qw(
   BLOCK BLOCK_HEADER COMMENT FIRST_COLUMN LINE LINE_HEADER MAIN
   NO NO_HEADER SINGLE SUB YES
);

our @EXPORT_OK = qw(
   addSourceToken
   addTagsForConversions
   addToValidTypes
   addValidCategory
   addValidSubEntity
   constructValidTags
   dirHasSourceTags
   foundInvalidTags
   getCrossCheckData
   getDirSourceTags
   getEntityFirstTag
   getEntityName
   getEntityNameTag
   getHeader
   getHeaderMissingOnLineType
   getMissingHeaderLineTypes
   getOrderForLineType
   getTagCount
   getValidLineTypes
   getValidSystemArr
   incCountInvalidTags
   incCountValidTags
   isFauxTag
   isValidCategory
   isValidCheck
   isValidEntity
   isValidFixedValue
   isValidGamemode
   isValidMultiTag
   isValidPreTag
   isValidSubEntity
   isValidTag
   isValidType
   mungKey
   registerXCheck
   searchRace
   seenSourceToken
   setEntityValid
   setFileHeader
   setValidSystemArr
   splitAndAddToValidEntities
   tagTakesFixedValues
   updateValidity
   validSubEntityExists
);

# expand library path so we can find TidyLst modules
use File::Basename qw(dirname fileparse);
use Cwd  qw(abs_path);
use lib dirname(dirname abs_path $0);

use TidyLst::Options qw(getOption isConversionActive);

# Constants for the master_line_type
use constant {
   # Line importance (Mode)
   MAIN           => 1, # Main line type for the file
   SUB            => 2, # Sub line type, must be linked to a MAIN
   SINGLE         => 3, # Independant line type
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
};

# Finds the CVS lines at the top of LST files, so we can delete them
# and replace with a single line TidyLst Header.
our $CVSPattern    = qr{\#.*CVS.*Revision}i;
our $headerPattern = qr{\#.*reformatt?ed by}i;
our $TidyLstHeader;


sub setFileHeader {
   my ($header) = @_;

   $TidyLstHeader = $header;
}


my %columnWithNoTag = (
   'ABILITY'           => '000AbilityName', 
   'ABILITYCATEGORY'   => '000AbilityCategory',
   'ALIGNMENT'         => '000AlignmentName',
   'ARMORPROF'         => '000ArmorName',
   'CLASS Level'       => '000Level',
   'CLASS'             => '000ClassName',
   'COMPANIONMOD'      => '000Follower',
   'DEITY'             => '000DeityName',
   'DOMAIN'            => '000DomainName',
   'EQUIPMENT'         => '000EquipmentName',
   'EQUIPMOD'          => '000ModifierName',
   'FEAT'              => '000FeatName',
   'GLOBALMODIFIER'    => '000GlobalmodName',
   'LANGUAGE'          => '000LanguageName',
   'MASTERBONUSRACE'   => '000MasterBonusRace',
   'RACE'              => '000RaceName',
   'SAVE'              => '000SaveName',
   'SHIELDPROF'        => '000ShieldName',
   'SIZE'              => '000SizeName',
   'SKILL'             => '000SkillName',
   'SPELL'             => '000SpellName',
   'STAT'              => '000StatName',
   'SUBCLASS'          => '000SubClassName',
   'SUBSTITUTIONCLASS' => '000SubstitutionClassName',
   'TEMPLATE'          => '000TemplateName',
   'VARIABLE'          => '000VariableName',
   'WEAPONPROF'        => '000WeaponName',
);

my %fauxTag = map {$_ => 1} values %columnWithNoTag;


# The global BONUS:xxx tags are used in many of the line types.  They are
# defined in one place, and every line type will get the same sort order.
# BONUSes only valid for specific line types are listed on those line types

my @globalBONUSTags = (
   'BONUS:ABILITYPOOL:*',
   'BONUS:CASTERLEVEL:*',
   'BONUS:CHECKS:*',
   'BONUS:COMBAT:*',
   'BONUS:CONCENTRATION:*',
   'BONUS:DC:*',
   'BONUS:DOMAIN:*',
   'BONUS:DR:*',
   'BONUS:FEAT:*',
   'BONUS:FOLLOWERS:*',
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
   'BONUS:SITUATION:*',
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

my @INFO_Tags = (
   'INFO:Prerequisite',
   'INFO:Normal',
   'INFO:Special',
   'INFO:*',
);

# Will hold the tags that do not have defined headers for each linetype.
my %missing_headers;

# Global tags allowed in PCC files.
my @pccBonusTags = (
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

# The PRExxx tags. These are used in many of the line types, but they are only
# defined once and every line type will get the same sort order.

my @PreTags = (
   'PRE:.CLEAR',
   'PREABILITY:*',
   '!PREABILITY:*',
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
);

# Ensure consistent ordering in the masterOrder structure
our @QUALIFYTags = (
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

# Ensure consistent ordering in the masterOrder structure
my @QUALITY_Tags = (
   'QUALITY:Capacity:*',
   'QUALITY:Usage:*',
   'QUALITY:Aura:*',
   'QUALITY:Caster Level:*',
   'QUALITY:Slot:*',
   'QUALITY:Construction Craft DC:*',
   'QUALITY:Construction Cost:*',
   'QUALITY:Construction Requirements:*',
   'QUALITY:*',
);

# This will hold a list of the SOURCE tags found for a given directory. Since
# all the lst files in a directory should have the same source tags. These are
# tags actually found in the files.
my %sourceTokens = ();

# Ensure consistent ordering in the masterOrder structure
our @SOURCETags = (
   'SOURCELONG',
   'SOURCESHORT',
   'SOURCEWEB',
   'SOURCEPAGE:.CLEAR',
   'SOURCEPAGE',
   'SOURCELINK',
   'SOURCEDATE',
);

# Order for the tags for each line type.
# 
# Note: This is also the validity info. If a tag doesn't appear here it gets
# reported as invalid for the linetype.
our %masterOrder = (
   'ABILITY' => [
      '000AbilityName',
      'SORTKEY',
      'KEY',
      'NAMEISPI',
      'OUTPUTNAME',
      'FACT:AppliedName',
      'CATEGORY',
      'GROUP:*',
      'TYPE:.CLEAR',
      'TYPE:*',
      'VISIBLE',
      'INFO:Prerequisite',
      @PreTags,
      @QUALIFYTags,
      'SERVESAS:*',
      'SAB:.CLEAR',
      'SAB:*',
      'DEFINE:*',
      'DEFINESTAT:*',
      'MODIFY:*',
      'SPELL:*',
      'SPELLS:*',
      'DESCISPI',
      'DESC:.CLEAR',
      'DESC:*',
      'STACK',
      'MULT',
      'CHOOSE',
      'SELECT',
      'TEMPLATE:.CLEAR',
      'TEMPLATE:*',
      'MOVE',
      'MOVECLONE',
      'AUTO:ARMORPROF:*',
      'AUTO:EQUIP:*',
      'AUTO:LANG:*',
      'AUTO:SHIELDPROF:*',
      'AUTO:WEAPONPROF:*',
      'UDAM',
      'UMULT',
      'ABILITY:*',
      'ADD:.CLEAR',
      'ADD:*',
      'ADD:ABILITY:*',
      'ADD:CLASSSKILLS',
      'ADD:EQUIP:*',
      'ADD:FAVOREDCLASS',
      'ADD:FORCEPOINT',
      'ADD:LANGUAGE:*',
      'ADD:SKILL:*',
      'ADD:SPELLCASTER:*',
      'ADD:TEMPLATE:*',
      'ADD:WEAPONPROFS',
      'ADDSPELLLEVEL',
      'REMOVE',
      @globalBONUSTags,
      'BONUS:LANGUAGES:*',
      'BONUS:WEAPON:*',
      'FOLLOWERS',
      'CHANGEPROF',
      'COMPANIONLIST:*',
      'CSKILL:.CLEAR',
      'CSKILL:*',
      'CCSKILL',
      'VISION:.CLEAR',
      'VISION:*',
      'SR',
      'DR:*',
      'REP',
      'COST',
      'KIT',
      'FACT:*',
      @SOURCETags,
      'NATURALATTACKS:*',
      'ASPECT:*',
      'BENEFIT:.CLEAR',
      'BENEFIT:*',
      'INFO:Special',
      'INFO:*',
      'TEMPDESC',
      'SPELLKNOWN:CLASS:*',
      'SPELLKNOWN:DOMAIN:*',
      'SPELLLEVEL:CLASS:*',
      'SPELLLEVEL:DOMAIN:*',
      'UNENCUMBEREDMOVE',
      'TEMPBONUS:*',
      'TEMPVALUE:*',

      'ADD:FEAT:*',                    # Deprecated 6.05.01
      'ADD:SPECIAL',                   # Deprecated - Remove 5.16 - Special abilities are now set using hidden feats 0r Abilities.
      'ADD:VFEAT:*',                   # Deprecated 6.05.01
      'APPLIEDNAME',                   # Deprecated 6.05.01
      'AUTO:FEAT:*',                   # Deprecated 6.05.01
      'LANGAUTO:.CLEAR',               # Deprecated - 6.0
      'LANGAUTO:*',                    # Deprecated - 6.0
      'SA:.CLEAR',                     # Deprecated
      'SA:*',                          # Deprecated
      'VFEAT:*',                       # Deprecated 6.05.01
   ],

   'ABILITYCATEGORY' => [
      '000AbilityCategory',
      'VISIBLE',
      'EDITABLE',
      'EDITPOOL',
      'FRACTIONALPOOL',
      'POOL',
      'CATEGORY',
      'GROUP:*',
      'TYPE:.CLEAR',
      'TYPE:*',
      'ABILITYLIST',
      'PLURAL',
      'DISPLAYNAME',
      'DISPLAYLOCATION',
   ],

   'ALIGNMENT' => [
      '000AlignmentName',
      'SORTKEY',
      'ABB',
      'KEY',
      'VALIDFORDEITY',
      'VALIDFORFOLLOWER',
   ],

   'ARMORPROF' => [
      '000ArmorName',
      'KEY',
      'NAMEISPI',
      'OUTPUTNAME',
      'GROUP:*',
      'TYPE:.CLEAR',
      'TYPE:*',
      'HANDS',
      @PreTags,
      @SOURCETags,
      @globalBONUSTags,
      'SAB:.CLEAR',
      'SAB:*',

      'SA:.CLEAR',                     # Deprecated
      'SA:*',                          # Deprecated
   ],

   'BIOSET AGESET' => [
      'AGESET',
      'BONUS:STAT:*',
   ],

   'BIOSET RACENAME' => [
      'RACENAME',
      'CLASS',
      'SEX',
      'BASEAGE',
      'MAXAGE',
      'AGEDIEROLL',
      'HAIR',
      'EYES',
      'SKINTONE',
   ],

   'CLASS' => [
      '000ClassName',
      'SORTKEY',
      'KEY',
      'NAMEISPI',
      'OUTPUTNAME',
      'HD',
      'XTRAFEATS',
      'SPELLSTAT',
      'BONUSSPELLSTAT',
      'FACT:SpellType:*',
      'SPELLTYPE',
      'GROUP:*',
      'TYPE:.CLEAR',
      'TYPE:*',
      'FACT:ClassType',
      'CLASSTYPE',
      'FACT:Abb:*',
      'ABB',
      'MAXLEVEL',
      'SERVESAS',
      'CASTAS',
      'MEMORIZE',
      'KNOWNSPELLS',
      'SPELLBOOK',
      'HASSUBCLASS',
      'ALLOWBASECLASS',
      'HASSUBSTITUTIONLEVEL',
      'EXCLASS',
      @SOURCETags,
      'LANGBONUS:.CLEAR',
      'LANGBONUS:*',
      'WEAPONBONUS',
      'VISION',
      'SR',
      'DR',
      'ATTACKCYCLE',
      'DEF',
      'ITEMCREATE',
      'KNOWNSPELLSFROMSPECIALTY',
      'PROHIBITED',
      'PROHIBITSPELL:*',
      'LEVELSPERFEAT',
      'ABILITY:*',
      'VFEAT:*',
      'MULTIPREREQS',
      'VISIBLE',
      'DEFINE:*',
      'DEFINESTAT:*',
      'AUTO:ARMORPROF:*',
      'AUTO:EQUIP:*',
      'AUTO:FEAT:*',
      'AUTO:LANG:*',
      'AUTO:SHIELDPROF:*',
      'AUTO:WEAPONPROF:*',
      'ADD:.CLEAR',
      'ADD:*',
      'ADD:ABILITY:*',
      'ADD:CLASSSKILLS',
      'ADD:EQUIP:*',
      'ADD:FEAT:*',
      'ADD:LANGUAGE:*',
      'ADD:SPELLCASTER:*',
      'ADD:TEMPLATE:*',
      'ADD:VFEAT:*',
      'CHANGEPROF',
      'DOMAIN:*',
      'ADDDOMAINS:*',
      'REMOVE',
      'BONUS:HD:*',
      @globalBONUSTags,
      'BONUS:WEAPON:*',
      'REP:*',
      'SPELLLIST',
      'GENDER',
      'TEMPLATE:.CLEAR',
      'TEMPLATE:*',
      'KIT',
      'DEITY',
      @PreTags,
      'PRERACETYPE',
      '!PRERACETYPE',
      'STARTSKILLPTS',
      'MODTOSKILLS',
      'SKILLLIST',
      'CSKILL:.CLEAR',
      'CSKILL',
      'CCSKILL:.CLEAR',
      'CCSKILL',
      'MONSKILL',
      'MONNONSKILLHD:*',
      'SPELLKNOWN:CLASS:*',
      'SPELLKNOWN:DOMAIN:*',
      'SPELLLEVEL:CLASS',
      'SPELLLEVEL:DOMAIN',
      'UNENCUMBEREDMOVE',
      'TEMPBONUS',
      'ROLE',

      'ADD:SPECIAL',                   # Deprecated - Remove 5.16 - Special abilities are now set using hidden feats 0r Abilities.
      'HASSPELLFORMULA',               # [ 1893279 ] HASSPELLFORMULA Class Line tag  # [ 1973497 ] HASSPELLFORMULA is deprecated
      'LANGAUTO:.CLEAR',               # Deprecated - 6.0
      'LANGAUTO:*',                    # Deprecated - 6.0
   ],

   'CLASS Level' => [
      '000Level',
      'REPEATLEVEL',
      'DONOTADD',
      'UATT',
      'UDAM',
      'UMULT',
      'ADD:SPELLCASTER',
      'CAST',
      'KNOWN',
      'SPECIALTYKNOWN',
      'KNOWNSPELLS',
      'PROHIBITSPELL:*',
      'HITDIE',
      'MOVE',
      'VISION',
      'SR',
      'DR',
      'DOMAIN:*',
      'DEITY',
      @PreTags,
      'SAB:.CLEAR',
      'SAB:*',
      'BONUS:HD:*',
      @globalBONUSTags,
      'BONUS:WEAPON:*',
      'TEMPDESC',
      'DEFINE:*',
      'DEFINESTAT:*',
      'CSKILL:.CLEAR',
      'CSKILL',
      'CCSKILL:.CLEAR',
      'CCSKILL',
      'ADD:.CLEAR',
      'ADD:*',
      'ADD:ABILITY:*',
      'ADD:CLASSSKILLS',
      'ADD:EQUIP:*',
      'ADD:LANGUAGE:*',
      'ADD:TEMPLATE:*',
      'REMOVE',
      'LANGBONUS:.CLEAR',
      'LANGBONUS:*',
      'STACK',
      'MULT',
      'CHOOSE',
      'SELECT',
      'EXCHANGELEVEL',
      'ABILITY:*',
      'SPELL',
      'SPELLS:*',
      'TEMPLATE:.CLEAR',
      'TEMPLATE:*',
      'KIT',
      'AUTO:ARMORPROF:*',
      'AUTO:EQUIP:*',
      'AUTO:LANG:*',
      'AUTO:SHIELDPROF:*',
      'AUTO:WEAPONPROF:*',
      'CHANGEPROF:*',
      'ADDDOMAINS',                    # [ 1973660 ] ADDDOMAINS is supported on Class Level lines
      @QUALIFYTags,
      'SERVESAS',
      'WEAPONBONUS',
      'SUBCLASS',
      'SPELLKNOWN:CLASS:*',
      'SPELLKNOWN:DOMAIN:*',
      'SPELLLEVEL:CLASS',
      'SPELLLEVEL:DOMAIN',
      'SPELLLIST',
      'NATURALATTACKS',
      'UNENCUMBEREDMOVE',

      'ADD:FEAT:*',                    # Deprecated 6.05.01
      'ADD:SPECIAL',                   # Deprecated - Remove 5.16 - Special abilities are now set using hidden feats 0r Abilities.
      'ADD:VFEAT:*',                   # Deprecated 6.05.01
      'AUTO:FEAT:*',                   # Deprecated 6.05.01
      'FEAT',                          # Deprecated 6.05.01
      'FEATAUTO:.CLEAR',               # Deprecated - 6.0
      'FEATAUTO:*',                    # Deprecated - 6.0
      'LANGAUTO:.CLEAR',               # Deprecated - 6.0
      'LANGAUTO:*',                    # Deprecated - 6.0
      'SA:.CLEAR:*',                   # Deprecated 6.05.01
      'SA:*',                          # Deprecated 6.05.01
      'SPECIALS',                      # Deprecated 6.05.01
      'VFEAT:*',                       # Deprecated 6.05.01
   ],

   'COMPANIONMOD' => [
      '000Follower',
      'SORTKEY',
      'KEY',
      'FOLLOWER',
      'GROUP:*',
      'TYPE:.CLEAR',
      'TYPE:*',
      'HD',
      'DR',
      'SR',
      'ABILITY:.CLEAR',
      'ABILITY:*',
      'COPYMASTERBAB',
      'COPYMASTERCHECK',
      'COPYMASTERHP',
      'USEMASTERSKILL',
      'GENDER',
      'PRERACE',
      '!PRERACE',
      'PREABILITY:*',
      '!PREABILITY:*',
      'MOVE',
      'KIT',
      'AUTO:ARMORPROF:*',
      'SAB:.CLEAR',
      'SAB:*',
      'ADD:LANGUAGE',
      'DEFINE:*',
      'DEFINESTAT:*',
      @globalBONUSTags,
      'RACETYPE',
      'SWITCHRACE:*',
      'TEMPLATE:*',
      'STACK',
      'MULT',
      'CHOOSE',
      'SELECT',
      'DESC:.CLEAR',
      'DESC:*',

      'AUTO:FEAT:*',                   # Deprecated 6.05.01
      'AUTO:FEAT:.CLEAR',              # Deprecated 6.05.01
      'FEAT:*',                        # Deprecated 6.05.01
      'FEAT:.CLEAR',                   # Deprecated 6.05.01
      'SA:.CLEAR',                     # Deprecated 6.05.01
      'SA:*',                          # Deprecated 6.05.01
      'VFEAT:*',                       # Deprecated 6.05.01
   ],

   'DATACONTROL DEFAULTVARIABLEVALUE' => [
      'DEFAULTVARIABLEVALUE',
   ],

   'DATACONTROL FACTDEF' => [
      'FACTDEF',
      'DATAFORMAT',
      'REQUIRED',
      'SELECTABLE',
      'VISIBLE',
      'DISPLAYNAME',
      'EXPLANATION',
   ],

   'DATACONTROL FACTSETDEF' => [
      'FACTSETDEF',
      'DATAFORMAT',
      'SELECTABLE',
      'VISIBLE',
      'EXPLANATION',
   ],

   'DATACONTROL FUNCTION' => [
      'FUNCTION',
      'VALUE',
      'EXPLANATION',
   ],

   'DEITY' => [
      '000DeityName',
      'SORTKEY',
      'KEY',
      'NAMEISPI',
      'OUTPUTNAME',
      'DOMAINS:*',
      'FOLLOWERALIGN',
      'DESCISPI',
      'DESC:.CLEAR',
      'DESC',
      'DEITYWEAP',
      'ALIGN',
      @SOURCETags,
      @PreTags,
      @QUALIFYTags,
      @globalBONUSTags,
      'DEFINE:*',
      'DEFINESTAT:*',
      'SR',
      'DR',
      'AUTO:WEAPONPROF',
      'SAB:.CLEAR',
      'SAB:*',
      'ABILITY:*',
      'UNENCUMBEREDMOVE',
      'GROUP',
      'FACT:Article',
      'FACT:Symbol',
      'FACTSET:Pantheon',
      'FACT:Title',
      'FACT:Worshippers',
      'FACT:Appearance',
      'FACT:*',
      'FACTSET:Race',
      'FACTSET:*',
      'SYMBOL',                        # Deprecated 6.05.01
      'PANTHEON',                      # Deprecated 6.05.01
      'TITLE',                         # Deprecated 6.05.01
      'WORSHIPPERS',                   # Deprecated 6.05.01
      'APPEARANCE',                    # Deprecated 6.05.01
      'VFEAT:*',                       # Deprecated 6.05.01
      'SA:.CLEAR',                     # Deprecated 6.05.01
      'SA:*',                          # Deprecated 6.05.01
      'RACE:*',                        # Deprecated 6.05.01
   ],

   'DOMAIN' => [
      '000DomainName',
      'SORTKEY',
      'KEY',
      'NAMEISPI',
      'OUTPUTNAME',
      @PreTags,
      @QUALIFYTags,
      'FACT:*',
      'CSKILL:.CLEAR',
      'CSKILL',
      'CCSKILL',
      'STACK',
      'MULT',
      'CHOOSE',
      'SELECT',
      'SPELL',
      'SPELLS:*',
      'VISION',
      'SR',
      'DR',
      'ABILITY:*',
      'ADD:.CLEAR',
      'ADD:*',
      'ADD:ABILITY:*',
      'ADD:CLASSSKILLS',
      'ADD:EQUIP:*',
      'ADD:LANGUAGE:*',
      'ADD:SPELLCASTER:*',
      'ADD:TEMPLATE:*',
      'AUTO:ARMORPROF:*',
      'AUTO:EQUIP:*',
      'AUTO:LANG:*',
      'AUTO:SHIELDPROF:*',
      'AUTO:WEAPONPROF:*',
      'SAB:.CLEAR',
      'SAB:*',
      'DEFINE:*',
      'DEFINESTAT:*',
      @globalBONUSTags,
      @SOURCETags,
      'DESCISPI',
      'DESC:.CLEAR',
      'DESC:*',
      'SPELLKNOWN:DOMAIN:*',
      'SPELLLEVEL:DOMAIN:*',
      'UNENCUMBEREDMOVE',
      'FEAT:*',                        # Deprecated 6.05.01
      'VFEAT:*',                       # Deprecated 6.05.01
      'ADD:FEAT:*',                    # Deprecated 6.05.01
      'ADD:VFEAT:*',                   # Deprecated 6.05.01
      'AUTO:FEAT:*',                   # Deprecated 6.05.01
      'FEATAUTO',                      # Deprecated
      'SA:*',                          # Deprecated
      'ADD:SPECIAL',                   # Deprecated - Remove 5.16 - Special abilities are now set using hidden feats 0r Abilities.
   ],

   'EQUIPMENT' => [
      '000EquipmentName',
      'SORTKEY',
      'KEY',
      'NAMEISPI',
      'OUTPUTNAME',
      'PROFICIENCY:WEAPON',
      'PROFICIENCY:ARMOR',
      'PROFICIENCY:SHIELD',
      'GROUP:*',
      'TYPE:.CLEAR',
      'TYPE:*',
      'ALTTYPE',
      'VISIBLE',
      'RESIZE',                        # [ 1956719 ] Add RESIZE tag to Equipment file
      'CONTAINS',
      'NUMPAGES',
      'PAGEUSAGE',
      'COST',
      'WT',
      'SLOTS',
      @PreTags,
      @QUALIFYTags,
      'DEFINE:*',
      'DEFINESTAT:*',
      'ACCHECK:*',
      'BASEITEM',
      'BASEQTY',
      'STACK',
      'MULT',
      'CHOOSE',
      'SELECT',
      'CRITMULT',
      'CRITRANGE',
      'ALTCRITMULT',
      'ALTCRITRANGE',
      'FUMBLERANGE',
      'DAMAGE',
      'ALTDAMAGE',
      'EQMOD:*',
      'ALTEQMOD',
      'HANDS',
      'WIELD',
      'MAXDEX',
      'MODS',
      'RANGE',
      'REACH',
      'REACHMULT',
      'SIZE',
      'MOVE',
      'MOVECLONE',
      @SOURCETags,
      'NATURALATTACKS',
      'SPELLFAILURE',
      'ADD:.CLEAR',
      'ADD:*',
      'ADD:ABILITY:*',
      'ADD:CLASSSKILLS',
      'ADD:EQUIP:*',
      'ADD:LANGUAGE:*',
      'ADD:SPELLCASTER:*',
      'ADD:TEMPLATE:*',
      'ABILITY:*',
      'VISION',
      'SR',
      'DR',
      'SPELL:*',
      'SPELLS:*',
      @globalBONUSTags,
      'BONUS:EQM:*',
      'BONUS:EQMARMOR:*',
      'BONUS:EQMWEAPON:*',
      'BONUS:ESIZE:*',
      'BONUS:ITEMCOST:*',
      'BONUS:LOADMULT:*',
      'BONUS:WEAPON:*',
      @QUALITY_Tags,
      'SPROP:.CLEAR',
      'SPROP:*',
      'SAB:.CLEAR',
      'SAB:*',
      'CSKILL:.CLEAR',
      'CSKILL',
      'UDAM',
      'UMULT',
      'AUTO:EQUIP:*',
      'AUTO:LANG:*',
      'AUTO:WEAPONPROF:*',
      'DESC:.CLEAR',
      'DESC:*',
      'DESCISPI',
      'INFO:*',
      'SPELLKNOWN:DOMAIN:*',
      'SPELLLEVEL:DOMAIN',
      'SPELLKNOWN:CLASS:*',
      'SPELLLEVEL:CLASS',
      'TEMPBONUS:*',
      'TEMPDESC',
      'UNENCUMBEREDMOVE',
      'ICON',
      'VFEAT:.CLEAR',                  # Deprecated 6.05.01
      'VFEAT:*',                       # Deprecated 6.05.01
      'ADD:FEAT:*',                    # Deprecated 6.05.01
      'ADD:VFEAT:*',                   # Deprecated 6.05.01
      'LANGAUTO:.CLEAR',               # Deprecated - replaced by AUTO:LANG
      'LANGAUTO:*',                    # Deprecated - replaced by AUTO:LANG
      'RATEOFFIRE',                    # Deprecated 6.05.01 - replaced by FACT
      'ADD:SPECIAL',                   # Deprecated - Remove 5.16 - Special abilities are now set using hidden feats 0r Abilities.
      'SA:.CLEAR',                     # Deprecated - replaced by SAB
      'SA:*',                          # Deprecated
   ],

   'EQUIPMOD' => [
      '000ModifierName',
      'KEY',
      'SORTKEY',
      'NAMEISPI',
      'OUTPUTNAME',
      'FORMATCAT',
      'NAMEOPT',
      'GROUP:*',
      'TYPE:.CLEAR',
      'TYPE:*',
      'PLUS',
      'COST',
      'VISIBLE',
      'ITYPE',
      'IGNORES',
      'REPLACES',
      'COSTPRE',
      @SOURCETags,
      @PreTags,
      @QUALIFYTags,
      'ADDPROF',
      'VISION',
      'SR',
      'DR',
      @globalBONUSTags,
      'BONUS:EQM:*',
      'BONUS:EQMARMOR:*',
      'BONUS:EQMWEAPON:*',
      'BONUS:ITEMCOST:*',
      'BONUS:WEAPON:*',
      'SPROP:*',
      'ABILITY:*',
      'FUMBLERANGE',
      'SAB:.CLEAR',
      'SAB:*',
      'INFO:*',
      'ARMORTYPE:*',
      'STACK',
      'MULT',
      'CHOOSE',
      'SELECT',
      'ASSIGNTOALL',
      'CHARGES',
      'DEFINE:*',
      'DEFINESTAT:*',
      'SPELL',
      'SPELLS:*',
      'AUTO:EQUIP:*',
      'AUTO:WEAPONPROF:*',
      'UNENCUMBEREDMOVE',
      'DESC:.CLEAR',
      'DESC:*',
      'DESCISPI',

      'RATEOFFIRE',                    #  Deprecated 6.05.01
      'SA:.CLEAR',                     #  Deprecated 6.05.01
      'SA:*',                          #  Deprecated 6.05.01
      'VFEAT:*',                       #  Deprecated 6.05.01
   ],

# This entire File is being deprecated
   'FEAT' => [
      '000FeatName',
      'KEY',
      'NAMEISPI',
      'OUTPUTNAME',
      'GROUP:*',
      'TYPE:.CLEAR',
      'TYPE:*',
      'VISIBLE',
      'CATEGORY',
      @PreTags,
      @QUALIFYTags,
      'SERVESAS',
      'SAB:.CLEAR',
      'SAB:*',
      'DEFINE:*',
      'DEFINESTAT:*',
      'SPELL:*',
      'SPELLS:*',
      'DESCISPI',
      'DESC:.CLEAR',
      'DESC:*',
      'STACK',
      'MULT',
      'CHOOSE',
      'SELECT',
      'TEMPLATE:.CLEAR',
      'TEMPLATE:*',
      'MOVE',
      'MOVECLONE',
      'REMOVE',
      'AUTO:ARMORPROF:*',
      'AUTO:EQUIP:*',
      'AUTO:FEAT:*',
      'AUTO:LANG:*',
      'AUTO:SHIELDPROF:*',
      'AUTO:WEAPONPROF:*',
      'UDAM',
      'UMULT',
      'VFEAT:*',
      'ABILITY:*',
      'ADD:*',
      'ADD:.CLEAR',
      'ADD:ABILITY:*',
      'ADD:CLASSSKILLS',
      'ADD:EQUIP:*',
      'ADD:FAVOREDCLASS',
      'ADD:FEAT:*',
      'ADD:FORCEPOINT',
      'ADD:LANGUAGE:*',
      'ADD:SKILL',
      'ADD:SPELLCASTER:*',
      'ADD:TEMPLATE:*',
      'ADD:VFEAT:*',
      'ADD:WEAPONPROFS',
      'ADDSPELLLEVEL',
      'APPLIEDNAME',
      @globalBONUSTags,
      'BONUS:WEAPON:*',
      'CHANGEPROF:*',
      'FOLLOWERS',
      'COMPANIONLIST:*',
      'CSKILL:.CLEAR',
      'CSKILL',
      'CCSKILL',
      'VISION',
      'SR',
      'DR:.CLEAR',
      'DR:*',
      'REP',
      'COST',
      'KIT',
      @SOURCETags,
      'NATURALATTACKS',
      'ASPECT:*',
      'BENEFIT:*',
      @INFO_Tags,
      'TEMPDESC',
      'SPELLKNOWN:CLASS:*',
      'SPELLKNOWN:DOMAIN:*',
      'SPELLLEVEL:CLASS:*',
      'SPELLLEVEL:DOMAIN:*',
      'UNENCUMBEREDMOVE',
      'TEMPBONUS',

      'ADD:SPECIAL',                   # Deprecated - Remove 5.16 - Special abilities are now set using hidden feats 0r Abilities.
      'LANGAUTO:.CLEAR',               # Deprecated - 6.0
      'LANGAUTO:*',                    # Deprecated - 6.0
      'SA:.CLEAR',                     # Deprecated 6.05.01
      'SA:*',                          # Deprecated 6.05.01
   ],

   'GLOBALMODIFIER' => [
      '000GlobalmonName',
      'EXPLANATION',
   ],

   'KIT AGE' => [
      'AGE',
      @PreTags,
   ],

   'KIT ALIGN' => [
      'ALIGN',
      'OPTION',
      @PreTags,
   ],

   'KIT CLASS' => [
      'CLASS',
      'LEVEL',
      'SUBCLASS',
      'OPTION',
      @PreTags,
   ],

   'KIT DEITY' => [
      'DEITY',
      'DOMAIN',
      'COUNT',
      'OPTION',
      @PreTags,
   ],

   'KIT FEAT' => [
      'FEAT',
      'FREE',
      'COUNT',
      'OPTION',
      @PreTags,
   ],
   'KIT ABILITY' => [
      'ABILITY',
      'FREE',
      'OPTION',
      @PreTags,
   ],

   'KIT FUNDS' => [
      'FUNDS',
      'QTY',
      'OPTION',
      @PreTags,
   ],

   'KIT GEAR' => [
      'GEAR',
      'QTY',
      'SIZE',
      'MAXCOST',
      'LOCATION',
      'EQMOD',
      'LOOKUP',
      'LEVEL',
      'SPROP',
      'OPTION',
      @PreTags,
   ],

   'KIT GENDER' => [
      'GENDER',
      'OPTION',
      @PreTags,
   ],

   'KIT KIT' => [
      'KIT',
      'OPTION',
      @PreTags,
   ],

   'KIT LANGBONUS' => [
      'LANGBONUS',
      'OPTION',
      @PreTags,
   ],

   'KIT LEVELABILITY' => [
      'LEVELABILITY',
      'ABILITY',
      @PreTags,
   ],

   'KIT NAME' => [
      'NAME',
      @PreTags,
   ],

   'KIT PROF' => [
      'PROF',
      'RACIAL',
      'COUNT',
      @PreTags,
   ],

   'KIT RACE' => [
      'RACE',
      @PreTags,
   ],

   'KIT REGION' => [
      'REGION',
      @PreTags,
   ],

   'KIT SELECT' => [
      'SELECT',
      @PreTags,
   ],

   'KIT SKILL' => [
      'SKILL',
      'RANK',
      'FREE',
      'COUNT',
      'OPTION',
      'SELECTION',
      @PreTags,
   ],

   'KIT SPELLS' => [
      'SPELLS',
      'COUNT',
      'OPTION',
      @PreTags,
   ],

   'KIT STARTPACK' => [
      'STARTPACK',
      'NAMEISPI',
      'GROUP:*',
      'TYPE:.CLEAR',
      'TYPE:*',
      'VISIBLE',
      'APPLY',
      'EQUIPBUY',
      'EQUIPSELL',
      'TOTALCOST',
      @PreTags,
      'SOURCEPAGE',
   ],

   'KIT STAT' => [
      'STAT',
      'OPTION',
      @PreTags,
   ],

   'KIT TABLE' => [
      'TABLE',
      'LOOKUP',
      'VALUES',
      @PreTags,
   ],

   'KIT TEMPLATE' => [
      'TEMPLATE',
      'OPTION',
      @PreTags,
   ],

   'LANGUAGE' => [
      '000LanguageName',
      'KEY',
      'NAMEISPI',
      'GROUP:*',
      'TYPE:.CLEAR',
      'TYPE:*',
      'SOURCEPAGE',
      @PreTags,
      @QUALIFYTags,
   ],

   'MASTERBONUSRACE' => [
      '000MasterBonusRace',
      'GROUP:*',
      'TYPE:.CLEAR',
      'TYPE:*',
      'DEFINE:*',
      'BONUS:ABILITYPOOL:*',
      'BONUS:CASTERLEVEL:*',
      'BONUS:CHECKS:*',
      'BONUS:COMBAT:*',
      'BONUS:CONCENTRATION:*',
      'BONUS:DC:*',
      'BONUS:FEAT:*',
      'BONUS:MOVEADD:*',
      'BONUS:HP:*',
      'BONUS:MOVEMULT:*',
      'BONUS:POSTMOVEADD:*',
      'BONUS:SAVE:*',
      'BONUS:SKILL:*',
      'BONUS:STAT:*',
      'BONUS:UDAM:*',
      'BONUS:VAR:*',
      'ADD:LANGUAGE',
      'ABILITY:*',
      'SAB:.CLEAR',
      'SAB:*',

      'SA:.CLEAR',                     # Deprecated 6.05.01
      'SA:*',                          # Deprecated 6.05.01
      'VFEAT:*',                       # Deprecated 6.05.01
   ],

   'PCC' => [
      'ALLOWDUPES',
      'CAMPAIGN',
      'GAMEMODE',
      'GENRE',
      'BOOKTYPE',
      'KEY',
      'PUBNAMELONG',
      'PUBNAMESHORT',
      'PUBNAMEWEB',
      'RANK',
      'SETTING',
      'GROUP:*',
      'TYPE:.CLEAR',
      'TYPE:*',
      'PRECAMPAIGN',
      '!PRECAMPAIGN',
      'SHOWINMENU',
      'SOURCELONG',
      'SOURCESHORT',
      'SOURCEWEB',
      'SOURCEDATE',
      'COVER',
      'COPYRIGHT',
      'LOGO',
      'DESC',
      'URL',
      'LICENSE',
      'HELP',
      'INFOTEXT',
      'ISD20',
      'ISLICENSED',
      'ISOGL',
      'ISMATURE',
      'BIOSET',
      'HIDETYPE',
      'COMPANIONLIST',
      'REQSKILL',
      'STATUS',
      'FORWARDREF',
      'OPTION',

      # These tags load files
      'ABILITY',
      'ABILITYCATEGORY',
      'ALIGNMENT',
      'ARMORPROF',
      'CLASS',
      # 'CLASSSKILL',
      'CLASSSPELL',
      'COMPANIONMOD',
      'DATACONTROL',
      'DATATABLE',
      'DEITY',
      'DOMAIN',
      'DYNAMIC',
      'EQUIPMENT',
      'EQUIPMOD',
      'FEAT',
      'GLOBALMODIFIER',
      'KIT',
      'LANGUAGE',
      'LSTEXCLUDE',
      'PCC',
      'RACE',
      'SAVE',
      'SHIELDPROF',
      'SIZE',
      'SKILL',
      'SPELL',
      'STAT',
      'TEMPLATE',
      'VARIABLE',
      'WEAPONPROF',
      '#EXTRAFILE',                    # Fix #EXTRAFILE so it recognizes #EXTRAFILE references (so OGL is a known referenced file again.)

      #These tags are normal file global tags....
      @pccBonusTags,                  # Global tags that are double - $tag has an embeded ':'
   ],

   'RACE' => [
      '000RaceName',
      'SORTKEY',
      'KEY',
      'NAMEISPI',
      'OUTPUTNAME',
      'FAVCLASS',
      'XTRASKILLPTSPERLVL',
      'STARTFEATS',
      'FACT:BaseSize',
      'SIZE',
      'MOVE',
      'MOVECLONE',
      'UNENCUMBEREDMOVE',
      'FACE',
      'REACH',
      'VISION',
      'FACT:IsPC',
      'FACT:*',
      @PreTags,
      @QUALIFYTags,
      'SERVESAS',
      'LANGBONUS:.CLEAR',
      'LANGBONUS:*',
      'WEAPONBONUS:*',
      'CHANGEPROF:*',
      'PROF',
      @globalBONUSTags,
      'BONUS:LANGUAGES:*',
      'CSKILL:.CLEAR',
      'CSKILL',
      'CCSKILL',
      'MONCSKILL',
      'MONCCSKILL',
      'AUTO:ARMORPROF:*',
      'AUTO:EQUIP:*',
      'AUTO:LANG:*',
      'AUTO:SHIELDPROF:*',
      'AUTO:WEAPONPROF:*',
      'ABILITY:*',
      'MFEAT:*',
      'LEGS',
      'HANDS',
      'GENDER',
      'NATURALATTACKS:*',
      'SAB:.CLEAR',
      'SAB:*',
      'DEFINE:*',
      'DEFINESTAT:*',
      'HITDICE',
      'SR',
      'DR:.CLEAR',
      'DR:*',
      'SKILLMULT',
      'BAB',
      'HITDIE',
      'MONSTERCLASS',
      'GROUP:*',
      'RACETYPE:.CLEAR',
      'RACETYPE:*',
      'RACESUBTYPE:.CLEAR',
      'RACESUBTYPE:*',
      'TYPE:.CLEAR',
      'TYPE:*',
      'TEMPLATE:.CLEAR',
      'TEMPLATE:*',
      'HITDICEADVANCEMENT',
      'LEVELADJUSTMENT',
      'CR',
      'CRMOD',
      'ROLE',
      @SOURCETags,
      'SPELL:*',
      'SPELLS:*',
      'STACK',
      'MULT',
      'CHOOSE',
      'SELECT',
      'ADD:.CLEAR',
      'ADD:*',
      'ADD:ABILITY:*',
      'ADD:CLASSSKILLS',
      'ADD:EQUIP:*',
      'ADD:LANGUAGE:*',
      'ADD:SPELLCASTER:*',
      'ADD:TEMPLATE:*',
      'REGION',
      'SUBREGION',
      'SPELLKNOWN:CLASS:*',
      'SPELLKNOWN:DOMAIN:*',
      'SPELLLEVEL:CLASS:*',
      'SPELLLEVEL:DOMAIN:*',
      'KIT',

      'ADD:FEAT:*',                    # Deprecated 6.05.01
      'ADD:SPECIAL',                   # Deprecated - Remove 5.16 - Special abilities are now set using hidden feats 0r Abilities.
      'ADD:VFEAT:*',                   # Deprecated 6.05.01
      'AUTO:FEAT:*',                   # Deprecated 6.05.01
      'FEAT:*',                        # Deprecated 6.05.01
      'LANGAUTO:*',                    # Deprecated - 6.0
      'LANGAUTO:.CLEAR',               # Deprecated - 6.0
      'SA:.CLEAR',                     # Deprecated
      'SA:*',                          # Deprecated
      'VFEAT:*',                       # Deprecated 6.05.01
   ],

   'SAVE' => [
      '000SaveName',
      'SORTKEY',
      'KEY',
      @globalBONUSTags,
   ],

   'SHIELDPROF' => [
      '000ShieldName',
      'KEY',
      'NAMEISPI',
      'OUTPUTNAME',
      'GROUP:*',
      'TYPE:.CLEAR',
      'TYPE:*',
      'HANDS',
      @PreTags,
      @SOURCETags,
      @globalBONUSTags,
      'SAB:.CLEAR',
      'SAB:*',

      'SA:.CLEAR',                     # Deprecated
      'SA:*',                          # Deprecated
   ],

   'SIZE' => [
      '000SizeName',
      'ABB',
      'BONUS:ACVALUE',
      'BONUS:COMBAT:*',
      'BONUS:ITEMCAPACITY',
      'BONUS:ITEMCOST',
      'BONUS:ITEMWEIGHT:*',
      'BONUS:LOADMULT',
      'BONUS:SKILL:*',
      'DISPLAYNAME',
      'MODIFY:*',
      'SIZENUM',
   ],

   'SKILL' => [
      '000SkillName',
      'SORTKEY',
      'KEY',
      'NAMEISPI',
      'OUTPUTNAME',
      'KEYSTAT',
      'USEUNTRAINED',
      'ACHECK',
      'EXCLUSIVE',
      'CLASSES',
      'GROUP:*',
      'TYPE:.CLEAR',
      'TYPE:*',
      'VISIBLE',
      @PreTags,
      @QUALIFYTags,
      'SERVESAS',
      @SOURCETags,
      'STACK',
      'MULT',
      'CHOOSE',
      'SELECT',
      'SITUATION',
      'DEFINE:*',
      'DEFINESTAT:*',
      'AUTO:EQUIP:*',
      'AUTO:LANG:*',
      'ABILITY',
      @globalBONUSTags,
      'BONUS:WEAPON:*',
      'CSKILL:.CLEAR',
      'CSKILL',
      'CCSKILL:.CLEAR',
      'CCSKILL',
      'REQ',
      'SAB:.CLEAR',
      'SAB:*',
      'DESC',
      'TEMPDESC',
      'TEMPBONUS',

      'SA:.CLEAR:*',                   # Deprecated
      'SA:*',                          # Deprecated
      'VFEAT:*',                       # Deprecated 6.05.01
   ],

   'SOURCE' => [
      'SOURCELONG',
      'SOURCESHORT',
      'SOURCEWEB',
      'SOURCEDATE',                    # [ 1584007 ] New Tag: SOURCEDATE in PCC
   ],

   'SPELL' => [
      '000SpellName',
      'SORTKEY',
      'KEY',
      'NAMEISPI',
      'OUTPUTNAME',
      'GROUP:*',
      'TYPE:.CLEAR',
      'TYPE:*',
      'CLASSES:.CLEARALL',
      'CLASSES:*',
      'DOMAINS',
      'STAT:*',
      'PPCOST',
      'SCHOOL:.CLEAR',
      'SCHOOL:*',
      'SUBSCHOOL',
      'DESCRIPTOR:.CLEAR',
      'DESCRIPTOR:*',
      'VARIANTS:.CLEAR',
      'VARIANTS:*',
      'COMPS',
      'FACT:CompMaterial',
      'CASTTIME:.CLEAR',
      'CASTTIME:*',
      'RANGE:.CLEAR',
      'RANGE:*',
      'ITEM:*',
      'TARGETAREA:.CLEAR',
      'TARGETAREA:*',
      'DURATION:.CLEAR',
      'DURATION:*',
      'CT',
      'SAVEINFO',
      'SPELLRES',
      'COST',
      'XPCOST',
      @PreTags,
      'DEFINE',
      'DEFINESTAT:*',
      'BONUS:PPCOST',                  # SPELL has a short list of BONUS tags
      'BONUS:CASTERLEVEL:*',
      'BONUS:CHECKS',
      'BONUS:COMBAT:*',
      'BONUS:DAMAGE:*',
      'BONUS:DR:*',
      'BONUS:FEAT:*',
      'BONUS:HP',
      'BONUS:MISC:*',
      'BONUS:MOVEADD',
      'BONUS:MOVEMULT:*',
      'BONUS:POSTMOVEADD',
      'BONUS:RANGEMULT:*',
      'BONUS:SAVE:*',
      'BONUS:SIZEMOD',
      'BONUS:SKILL:*',
      'BONUS:STAT:*',
      'BONUS:UDAM:*',
      'BONUS:VAR:*',
      'BONUS:VISION',
      'BONUS:WEAPON:*',
      'BONUS:WEAPONPROF:*',
      'BONUS:WIELDCATEGORY:*',
      'DR:.CLEAR',
      'DR:*',
      'STACK',
      'MULT',
      'CHOOSE',
      'SELECT',
      @SOURCETags,
      'DESCISPI',
      'DESC:.CLEAR',
      'DESC:*',
      'TEMPDESC',
      'TEMPBONUS:*',
      'TEMPVALUE',
      'FACTSET:*',
   ],

   'STAT' => [
      '000StatName',
      'SORTKEY',
      'ABB',
      'KEY',
      'STATMOD',
      'DEFINE:MAXLEVELSTAT',
      'DEFINE:*',
      'MODIFY:*',
      @globalBONUSTags,
      'ABILITY',
      'BONUS:LANG:*',
      'BONUS:MODSKILLPOINTS:*',
   ],

   'SUBCLASS' => [
      '000SubClassName',
      'KEY',
      'NAMEISPI',
      'OUTPUTNAME',
      'HD',
      'COST',
      'PROHIBITCOST',
      'CHOICE',
      'SPELLSTAT',
      'SPELLTYPE',
      'LANGBONUS:.CLEAR',
      'LANGBONUS:*',
      'BONUS:CASTERLEVEL:*',
      'BONUS:CHECKS:*',
      'BONUS:COMBAT:*',
      'BONUS:DC:*',
      'BONUS:HD:*',
      'BONUS:SKILL:*',
      'BONUS:UDAM:*',
      'BONUS:VAR:*',
      'BONUS:WEAPON:*',
      'BONUS:WIELDCATEGORY:*',
      'ADD:.CLEAR',
      'ADD:*',
      'ADD:ABILITY:*',
      'ADD:CLASSSKILLS',
      'ADD:EQUIP:*',
      'ADD:LANGUAGE:*',
      'ADD:SPELLCASTER:*',
      'ADD:TEMPLATE:*',
      'REMOVE',
      'TEMPLATE:.CLEAR',
      'TEMPLATE:*',
      'SPELLLIST',
      'KNOWNSPELLSFROMSPECIALTY',
      'PROHIBITED',
      'PROHIBITSPELL:*',
      'STARTSKILLPTS',
      'SAB:.CLEAR',
      'SAB:*',
      'DEFINE',
      'DEFINESTAT:*',
      @PreTags,
      'CSKILL:.CLEAR',
      'CSKILL',
      'CCSKILL:.CLEAR',
      'CCSKILL',
      'DOMAIN:*',
      'ADDDOMAINS',
      'UNENCUMBEREDMOVE',
      @SOURCETags,

      'ADD:FEAT:*',                    # Deprecated 6.05.01
      'ADD:SPECIAL',                   # Deprecated - Remove 5.16 - Special abilities are now set using hidden feats 0r Abilities.
      'ADD:VFEAT:*',                   # Deprecated 6.05.01
      'BONUS:ABILITYPOOL:*',           # SubClass has a short list of BONUS tags
      'BONUS:FEAT:*',                  # Deprecated 6.05.01
      'BONUS:SAVE:*',                  # Global Replacement for CHECKS
      'LANGAUTO:*',                    # Deprecated 6.05.01
      'LANGAUTO:.CLEAR',               # Deprecated 6.05.01
      'SA:.CLEAR:*',                   # Deprecated
      'SA:*',                          # Deprecated
   ],

   'SUBSTITUTIONCLASS' => [
      '000SubstitutionClassName',
      'KEY',
      'NAMEISPI',
      'OUTPUTNAME',
      'COST',
      'PROHIBITCOST',
      'CHOICE',
      'SPELLSTAT',
      'SPELLTYPE',
      'BONUS:ABILITYPOOL:*',           # Substitution Class has a short list of BONUS tags
      'BONUS:CASTERLEVEL:*',
      'BONUS:CHECKS:*',
      'BONUS:COMBAT:*',
      'BONUS:DC:*',
      'BONUS:HD:*',
      'BONUS:SAVE:*',
      'BONUS:SKILL:*',
      'BONUS:UDAM:*',
      'BONUS:VAR:*',
      'BONUS:WEAPON:*',
      'BONUS:WIELDCATEGORY:*',
      'ADD:.CLEAR',
      'ADD:*',
      'ADD:ABILITY:*',
      'ADD:CLASSSKILLS',
      'ADD:EQUIP:*',
      'ADD:LANGUAGE:*',
      'ADD:SPELLCASTER:*',
      'ADD:TEMPLATE:*',
      'TEMPLATE:.CLEAR',
      'TEMPLATE:*',
      'REMOVE',
      'SPELLLIST',
      'KNOWNSPELLSFROMSPECIALTY',
      'PROHIBITED',
      'PROHIBITSPELL:*',
      'STARTSKILLPTS',
      'SAB:.CLEAR',
      'SAB:*',
      'DEFINE',
      'DEFINESTAT:*',
      @PreTags,
      'CSKILL:.CLEAR',
      'CSKILL',
      'CCSKILL:.CLEAR',
      'CCSKILL',
      'ADDDOMAINS',
      'UNENCUMBEREDMOVE',
      @SOURCETags,

      'ADD:FEAT:*',                    # Deprecated 6.05.01
      'ADD:SPECIAL',                   # Deprecated - Remove 5.16 - Special abilities are now set using hidden feats 0r Abilities.
      'ADD:VFEAT:*',                   # Deprecated 6.05.01
      'BONUS:FEAT:*',                  # Deprecated 6.05.01
      'SA:.CLEAR:*',                   # Deprecated
      'SA:*',                          # Deprecated
   ],

   'SUBCLASSLEVEL' => [
      'SUBCLASSLEVEL',
      'REPEATLEVEL',
      @QUALIFYTags,
      'SERVESAS',
      'UATT',
      'UDAM',
      'UMULT',
      'ADD:SPELLCASTER:*',
      'SPELLKNOWN:CLASS:*',
      'SPELLLEVEL:CLASS:*',
      'CAST',
      'KNOWN',
      'SPECIALTYKNOWN',
      'KNOWNSPELLS',
      'PROHIBITSPELL:*',
      'VISION',
      'SR',
      'DR',
      'DOMAIN:*',
      'SAB:.CLEAR',
      'SAB:*',
      'BONUS:HD:*',
      @globalBONUSTags,
      'BONUS:WEAPON:*',
      'HITDIE',
      'ABILITY:*',
      'DEFINE:*',
      'DEFINESTAT:*',
      'CSKILL:.CLEAR',
      'CSKILL:*',
      'CCSKILL:.CLEAR',
      'CCSKILL:*',
      'ADD:.CLEAR',
      'ADD:*',
      'ADD:ABILITY:*',
      'ADD:CLASSSKILLS',
      'ADD:EQUIP:*',
      'ADD:LANGUAGE:*',
      'ADD:TEMPLATE:*',
      'DONOTADD:*',
      'EXCHANGELEVEL',
      'SPELLS:*',
      'TEMPLATE:.CLEAR',
      'TEMPLATE:*',
      'AUTO:ARMORPROF:*',
      'AUTO:EQUIP:*',
      'AUTO:SHIELDPROF:*',
      'AUTO:WEAPONPROF:*',
      'CHANGEPROF:*',
      'REMOVE',
      'ADDDOMAINS',
      'WEAPONBONUS',
      'SUBCLASS',
      'SPELLLIST',
      'NATURALATTACKS',
      'UNENCUMBEREDMOVE',
      @PreTags,

      'ADD:FEAT:*',                    # Deprecated 6.05.01
      'ADD:SPECIAL',                   # Deprecated - Remove 5.16 - Special abilities are now set using hidden feats 0r Abilities.
      'ADD:VFEAT:*',                   # Deprecated 6.05.01
      'AUTO:FEAT:*',                   # Deprecated 6.05.01
      'FEATAUTO:*',                    # Deprecated 6.05.01
      'FEATAUTO:.CLEAR',               # Deprecated 6.05.01
      'LANGAUTO.CLEAR',                # Deprecated - Remove 6.0
      'LANGAUTO:*',                    # Deprecated - Remove 6.0
      'SA:.CLEAR:*',                   # Deprecated 6.05.01
      'SA:*',                          # Deprecated 6.05.01
      'SPECIALS',                      # Deprecated
      'SPELL',                         # Deprecated
      'VFEAT:*',                       # Deprecated 6.05.01
   ],

   'SUBSTITUTIONLEVEL' => [
      'SUBSTITUTIONLEVEL',
      'REPEATLEVEL',
      @QUALIFYTags,
      'SERVESAS',
      'HD',
      'STARTSKILLPTS',
      'UATT',
      'UDAM',
      'UMULT',
      'ADD:SPELLCASTER',
      'SPELLKNOWN:CLASS:*',
      'SPELLLEVEL:CLASS:*',
      'CAST',
      'KNOWN',
      'SPECIALTYKNOWN',
      'KNOWNSPELLS',
      'PROHIBITSPELL:*',
      'VISION',
      'SR',
      'DR',
      'DOMAIN',
      'SAB:.CLEAR',
      'SAB:*',
      'BONUS:HD:*',
      @globalBONUSTags,
      'BONUS:WEAPON:*',
      'HITDIE',
      'ABILITY:*',
      'DEFINE:*',
      'DEFINESTAT:*',
      'CSKILL:.CLEAR',
      'CSKILL',
      'CCSKILL:.CLEAR',
      'CCSKILL',
      'ADD:.CLEAR',
      'ADD:*',
      'ADD:ABILITY:*',
      'ADD:CLASSSKILLS',
      'ADD:EQUIP:*',
      'ADD:LANGUAGE:*',
      'ADD:TEMPLATE:*',
      'EXCHANGELEVEL',
      'SPELL',
      'SPELLS:*',
      'TEMPLATE:.CLEAR',
      'TEMPLATE:*',
      'AUTO:ARMORPROF:*',
      'AUTO:EQUIP:*',
      'AUTO:SHIELDPROF:*',
      'AUTO:WEAPONPROF:*',
      'CHANGEPROF:*',
      'REMOVE',
      'ADDDOMAINS',
      'WEAPONBONUS',
      'SUBCLASS',
      'SPELLLIST',
      'NATURALATTACKS',
      'UNENCUMBEREDMOVE',

      'ADD:FEAT:*',                    # Deprecated 6.05.01
      'ADD:SPECIAL',                   # Deprecated - Remove 5.16 - Special abilities are now set using hidden feats 0r Abilities.
      'ADD:VFEAT:*',                   # Deprecated 6.05.01
      'AUTO:FEAT:*',                   # Deprecated 6.05.01
      'FEATAUTO:*',                    # Deprecated 6.05.01
      'FEATAUTO:.CLEAR',               # Deprecated 6.05.01
      'LANGAUTO.CLEAR',                # Deprecated - Remove 6.0
      'LANGAUTO:*',                    # Deprecated - Remove 6.0
      'SA:.CLEAR:*',                   # Deprecated 6.05.01
      'SA:*',                          # Deprecated 6.05.01
      'SPECIALS',                      # Deprecated 6.05.01
      'VFEAT:*',                       # Deprecated 6.05.01
   ],

   'SWITCHRACE' => [
      'SWITCHRACE',
   ],

   'TEMPLATE' => [
      '000TemplateName',
      'SORTKEY',
      'KEY',
      'NAMEISPI',
      'OUTPUTNAME',
      'FACT:AppliedName',
      'HITDIE',
      'HITDICESIZE',
      'CR',
      'SIZE',
      'FACE',
      'REACH',
      'LEGS',
      'HANDS',
      'GENDER',
      'VISIBLE',
      'REMOVEABLE',
      'DR:*',
      'LEVELADJUSTMENT',
      'TEMPLATE:.CLEAR',
      'TEMPLATE:*',
      @SOURCETags,
      'SAB:.CLEAR',
      'SAB:*',
      'DEFINE:*',
      'DEFINESTAT:*',
      'LEVEL:*',
      @PreTags,
      @QUALIFYTags,
      @globalBONUSTags,
      'BONUSFEATS',
      'BONUS:MONSKILLPTS',
      'BONUSSKILLPOINTS',
      'BONUS:WEAPON:*',
      'NONPP',
      'STACK',
      'MULT',
      'CHOOSE',
      'SELECT',
      'CSKILL:.CLEAR',
      'CSKILL',
      'CCSKILL:.CLEAR',
      'CCSKILL',
      'ADD:.CLEAR',
      'ADD:*',
      'ADD:ABILITY:*',
      'ADD:CLASSSKILLS',
      'ADD:EQUIP:*',
      'ADD:LANGUAGE:*',
      'ADD:TEMPLATE:*',
      'FAVOREDCLASS',
      'ABILITY:*',
      'AUTO:ARMORPROF:*',
      'AUTO:EQUIP:*',
      'AUTO:LANG:*',
      'AUTO:SHIELDPROF:*',
      'AUTO:WEAPONPROF:*',
      'REMOVE:*',
      'CHANGEPROF:*',
      'KIT',
      'LANGBONUS:.CLEAR',
      'LANGBONUS:*',
      'MOVE',
      'MOVECLONE',
      'REGION',
      'SUBREGION',
      'REMOVABLE',
      'SR:*',
      'SUBRACE',
      'GROUP:*',
      'RACETYPE',
      'RACESUBTYPE:.REMOVE',
      'RACESUBTYPE:*',
      'TYPE:.CLEAR',
      'TYPE:*',
      'ADDLEVEL',
      'VISION',
      'HD:*',
      'WEAPONBONUS',
      'GENDERLOCK',
      'SPELLS:*',
      'SPELLKNOWN:CLASS:*',
      'SPELLKNOWN:DOMAIN:*',
      'SPELLLEVEL:CLASS:*',
      'SPELLLEVEL:DOMAIN:*',
      'ADD:SPELLCASTER',
      'NATURALATTACKS:*',
      'UNENCUMBEREDMOVE',
      'COMPANIONLIST',
      'FOLLOWERS',
      'DESC:.CLEAR',
      'DESC:*',
      'TEMPDESC',
      'TEMPBONUS:*',
      'TEMPVALUE:*',

      'ADD:FEAT:*',                    # Deprecated 6.05.01
      'ADD:SPECIAL',                   # Deprecated - Remove 5.16 - Special abilities are now set using hidden feats 0r Abilities.
      'ADD:VFEAT:*',                   # Deprecated 6.05.01
      'AUTO:FEAT:*',                   # Deprecated 6.05.01
      'FEAT:*',                        # Deprecated 6.05.01
      'LANGAUTO:*',                    # Deprecated - 6.0
      'LANGAUTO:.CLEAR',               # Deprecated - 6.0
      'MOVEA',                         # Deprecated 6.05.01
      'SA:.CLEAR',                     # Deprecated 6.05.01
      'SA:*',                          # Deprecated 6.05.01
      'SPELL:*',                       # Deprecated 5.x.x - Remove 6.0 - use SPELLS
      'VFEAT:*',                       # Deprecated 6.05.01
   ],

   'VARIABLE' => [
      '000VariableName',
      'EXPLANATION',
      'GLOBAL'
   ],

   'WEAPONPROF' => [
      '000WeaponName',
      'KEY',
      'NAMEISPI',
      'OUTPUTNAME',
      'GROUP:*',
      'TYPE:.CLEAR',
      'TYPE:*',
      'HANDS',
      @PreTags,
      @SOURCETags,
      @globalBONUSTags,
      'SAB:.CLEAR',
      'SAB:*',

      'SA:.CLEAR',                     # Deprecated 6.05.01
      'SA:*',                          # Deprecated 6.05.01
   ],

   # New files already added

# ALIGNMENT
#      '000AlignmentName',
# DATACONTROL
#      '000DatacontrolName',
# GLOBALMODIFIER
#      '000GlobalmonName',             # questionable
# SAVE
#      '000SaveName',
# STAT
#      '000StatName',
# VARIABLE
#      '000VariableName',

   # New files, not added

# 'DATATABLE' => [],
# 'DYNAMIC' => [],
#
# SIZE
#      '000SizeName',

);

# Will hold the tags that can appear more then once on a line
my %master_mult;        

# Will hold the number of each tag found (by linetype)
my %tagCount;

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

# A data structure containing headers to use as the comment for each of the
# tokens used in the script This data structure maps line type (not file type)
# to token to label Line type comes from the parseControl structure.
my %tokenHeader = (
   default => {

      '001DomainEffect'                   => 'Description',
      '001SkillName'                      => 'Class Skills (All skills are seperated by a pipe delimiter \'|\')',

      'DESC'                              => 'Description',
      'EXCLUSIVE'                         => 'Exclusive?',
      'FAVCLASS'                          => 'Favored Class',
      'KEYSTAT'                           => 'Key Stat',
      'SITUATION'                         => 'Situational Skill',
      'STARTFEATS'                        => 'Starting Feats',
      'USEUNTRAINED'                      => 'Untrained?',
      'XTRASKILLPTSPERLVL'                => 'Skills/Level',
      'DATAFORMAT'                        => 'Dataformat',
      'REQUIRED'                          => 'Required',
      'SELECTABLE'                        => 'Selectable',
      'DISPLAYNAME'                       => 'Display name',

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
      'GROUP'                             => 'Assigned Groups',
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
      
   ABILITY => {
      '000AbilityName'           => '# Ability Name',
   },

   ABILITYCATEGORY => {
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

   ALIGNMENT => {
      '000AlignmentName'         => '# Name',
   },

   ARMORPROF => {
      '000ArmorName'             => '# Armor Name',
   },

   'BIOSET AGESET' => {
      'AGESET'                   => '# Age set',
   },

   'BIOSET RACENAME' => {
      'RACENAME'                 => '# Race name',
   },

   CLASS => {
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

   COMPANIONMOD => {
      '000Follower'              => '# Class of the Master',
      '000MasterBonusRace'       => '# Race of familiar',
      'COPYMASTERBAB'            => 'Copy Masters BAB',
      'COPYMASTERCHECK'          => 'Copy Masters Checks',
      'COPYMASTERHP'             => 'HP formula based on Master',
      'FOLLOWER'                 => 'Added Value',
      'SWITCHRACE'               => 'Change Racetype',
      'USEMASTERSKILL'           => 'Use Masters skills?',
   },
   
   'DATACONTROL FACTDEF' => {
      'FACTDEF'                  => '# Fact Definition',
      'DATAFORMAT'               => 'Data type',
      'REQUIRED'                 => 'Necessity',
      'SELECTABLE'               => 'Selectability',
      'VISIBLE'                  => 'Visibility',
      'DISPLAYNAME'              => 'Name for display',
      'EXPLANATION'              => "What it's for",
   },
   
   'DATACONTROL FACTSETDEF' => {
      'FACTSETDEF'               => '# Fact Set Definition',
      'DATAFORMAT'               => 'Data type',
      'SELECTABLE'               => 'Selectability',
      'VISIBLE'                  => 'Visibility',
      'EXPLANATION'              => "What it's for",
   },

   'DATACONTROL FUNCTION' => {
      'FUNCTION'                 => '# Function Name',
      'VALUE'                    => 'Function Value',
      'EXPLANATION'              => "What it's for",
   },

   DEITY => {
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

   DOMAIN => {
      '000DomainName'            => '# Domain Name',
   },

   EQUIPMENT => {
      '000EquipmentName'         => '# Equipment Name',
      'BASEITEM'                 => 'Base Item for EQMOD',
      'RESIZE'                   => 'Can be Resized',
      'QUALITY'                  => 'Quality and value',
      'SLOTS'                    => 'Slot Needed',
      'WIELD'                    => 'Wield Category',
      'MODS'                     => 'Requires Modification?',
   },

   EQUIPMOD => {
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

   FEAT => {
      '000FeatName'                       => '# Feat Name',
   },

   GLOBALMODIFIER => {
      '000GlobalmodName'         => '# Name',
      'EXPLANATION'              => 'Explanation',
   },

   'KIT STARTPACK' => {
      'STARTPACK'                => '# Kit Name',
      'APPLY'                    => 'Apply method to char',
   },

   'KIT AGE' => {
      'AGE'                      => '# Age',
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

   LANGUAGE => {
      '000LanguageName'          => '# Language',
   },

   MASTERBONUSRACE => {
      '000MasterBonusRace'       => '# Race of familiar',
   },

   RACE => {
      '000RaceName'              => '# Race Name',
      'FACT'                     => 'Base size',
      'FAVCLASS'                 => 'Favored Class',
      'SKILLMULT'                => 'Skill Multiplier',
      'MONCSKILL'                => 'Racial HD Class Skills',
      'MONCCSKILL'               => 'Racial HD Cross-class Skills',
      'MONSTERCLASS'             => 'Monster Class Name and Starting Level',
   },

   SAVE => {
      '000SaveName'              => '# Name',
   },

   SHILEDPROF => {
      '000ShieldName'            => '# Shield Name',
   },

   SKILL => {
      '000SkillName'             => '# Skill Name',
   },

   SPELL => {
      '000SpellName'             => '# Spell Name',
      'CLASSES'                  => 'Classes of caster',
      'DOMAINS'                  => 'Domains granting the spell',
   },

   STAT => {
      '000StatName'              => '# Name',
   },

   SUBCLASS => {
      '000SubClassName'          => '# Subclass',
   },

   SUBSTITUTIONCLASS => {
      '000SubstitutionClassName' => '# Substitution Class',
   },

   TEMPLATE => {
      '000TemplateName'          => '# Template Name',
      'ADDLEVEL'                 => 'Add Levels',
      'BONUS:MONSKILLPTS'        => 'Bonus Monster Skill Points',
      'BONUSFEATS'               => 'Number of Bonus Feats',
      'FAVOREDCLASS'             => 'Favored Class',
      'GENDERLOCK'               => 'Lock Gender Selection',
   },

   VARIABLE => {
      '000VariableName'          => '# Variable Name',
      'EXPLANATION'              => 'Explanation',
   },

   WEAPONPROF => {
      '000WeaponName'            => '# Weapon Name',
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

# Populated after parseSystemFiles has been run
my %validCheckName = ();

# Will hold the valid categories for CATEGORY= found in abilities.
# Format validCategories{$entitytype}{$categoryname}
my %validCategories;

# Will hold the entries that may be refered to by other tags Format
# $validEntities{$entitytype}{$entityname} We initialise the hash with global
# system values that are valid but never defined in the .lst files.
my %validEntities;

# Populated after parseSystemFiles has been run
my %validGameModes = ();

# Will hold the valid tags for each type of file.
my %validTags;


# Will hold the entities that are allowed to include
# a sub-entity between () in their name.
# e.g. Skill Focus(Spellcraft)
# Format: $validSubEntities{$entity_type}{$entity_name} = $sub_entity_type;
# e.g. :  $validSubEntities{'FEAT'}{'Skill Focus'} = 'SKILL';
my %validSubEntities;

# Will hold the valid types for the TYPE. or TYPE= found in different tags.
# Format validTypes{$entitytype}{$typename}
my %validTypes;

# Lists of defaults for values defined in system files
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


# Will hold the information for the entries that must be added in %referrer or
# %referrer_types. The array is needed because all the files must have been
# parsed before processing the information to be added.  The function
# add_to_xcheck_tables will be called with each line of the array.
our @xcheck_to_process;  



=head2 addSourceToken

   found a SOURCE token, add a note of it for this directory.

=cut

sub addSourceToken {

   my ($input, $token) = @_;

   my ($file, $path) = fileparse($input);

   $sourceTokens{$path}{$token->tag} = $token;
}


=head2 addTagsForConversions

   Some of the conversions need tags to be accepted as valid in order to change
   them. This operation updates the masterOrder, which controls validity.

=cut

sub addTagsForConversions {

   if ( isConversionActive('ALL:Convert ADD:SA to ADD:SAB') ) {
      push @{ $masterOrder{'CLASS'} },          'ADD:SA';
      push @{ $masterOrder{'CLASS Level'} },    'ADD:SA';
      push @{ $masterOrder{'COMPANIONMOD'} },   'ADD:SA';
      push @{ $masterOrder{'DEITY'} },          'ADD:SA';
      push @{ $masterOrder{'DOMAIN'} },         'ADD:SA';
      push @{ $masterOrder{'EQUIPMENT'} },      'ADD:SA';
      push @{ $masterOrder{'EQUIPMOD'} },       'ADD:SA';
      push @{ $masterOrder{'FEAT'} },           'ADD:SA';
      push @{ $masterOrder{'RACE'} },           'ADD:SA';
      push @{ $masterOrder{'SKILL'} },          'ADD:SA';
      push @{ $masterOrder{'SUBCLASSLEVEL'} },  'ADD:SA';
      push @{ $masterOrder{'TEMPLATE'} },       'ADD:SA';
      push @{ $masterOrder{'WEAPONPROF'} },     'ADD:SA';
   }
   if ( isConversionActive('EQUIP: ALTCRITICAL to ALTCRITMULT') ) {
      push @{ $masterOrder{'EQUIPMENT'} },      'ALTCRITICAL';
   }

   if ( isConversionActive('EQUIPMENT: remove ATTACKS') ) {
      push @{ $masterOrder{'EQUIPMENT'} },      'ATTACKS';
   }

   if ( isConversionActive('PCC:GAME to GAMEMODE') ) {
      push @{ $masterOrder{'PCC'} },            'GAME';
   }

   if ( isConversionActive('ALL:BONUS:MOVE conversion') ) {
      push @{ $masterOrder{'CLASS'} },          'BONUS:MOVE:*';
      push @{ $masterOrder{'CLASS Level'} },    'BONUS:MOVE:*';
      push @{ $masterOrder{'COMPANIONMOD'} },   'BONUS:MOVE:*';
      push @{ $masterOrder{'DEITY'} },          'BONUS:MOVE:*';
      push @{ $masterOrder{'DOMAIN'} },         'BONUS:MOVE:*';
      push @{ $masterOrder{'EQUIPMENT'} },      'BONUS:MOVE:*';
      push @{ $masterOrder{'EQUIPMOD'} },       'BONUS:MOVE:*';
      push @{ $masterOrder{'FEAT'} },           'BONUS:MOVE:*';
      push @{ $masterOrder{'RACE'} },           'BONUS:MOVE:*';
      push @{ $masterOrder{'SKILL'} },          'BONUS:MOVE:*';
      push @{ $masterOrder{'SUBCLASSLEVEL'} },  'BONUS:MOVE:*';
      push @{ $masterOrder{'TEMPLATE'} },       'BONUS:MOVE:*';
      push @{ $masterOrder{'WEAPONPROF'} },     'BONUS:MOVE:*';
   }

   if ( isConversionActive('WEAPONPROF:No more SIZE') ) {
      push @{ $masterOrder{'WEAPONPROF'} },     'SIZE';
   }

   if ( isConversionActive('EQUIP:no more MOVE') ) {
      push @{ $masterOrder{'EQUIPMENT'} },      'MOVE';
   }
}


=head2 addToValidTypes

   C<addToValidTypes(LineType, Type)>

   Mark the type valid in line type

=cut

sub addToValidTypes {

   my ($lineType, $type) = @_;

   $validTypes{$lineType}{$type}++ 
}



=head2 addValidCategory

   Make this category valid

=cut

sub addValidCategory {
   my ($lineType, $category) = @_;

   $validCategories{$lineType}{$category}++;
}


=head2 addValidSubEntity

   Record validity data for a particular sub-entity of a given entity.

=cut

sub addValidSubEntity {

   my ($entity, $subEntity, $data) = @_;

   $validSubEntities{$entity}{$subEntity} = $data;
}





=head2 constructValidTags

   Construct the valid tags for all file types. Also populate the data
   structure that allows a tag to appear more than once on a line.

=cut

sub constructValidTags {

   #################################################
   # We populate %validTags for all file types.

   for my $line_type ( getValidLineTypes() ) {
      for my $tag ( @{ getOrderForLineType($line_type) } ) {
         if ( $tag =~ / ( .* ) [:][*] \z /xms ) {

            # Tag that end by :* are allowed
            # to be present more then once on the same line

            $tag = $1;
            $master_mult{$line_type}{$tag} = 1;
         }

         if ( exists $validTags{$line_type}{$tag} ) {
            die "Tag $tag found more then once for $line_type";
         } else {
            $validTags{$line_type}{$tag} = 1;
         }
      }
   }
}


=head2 dirHasSourceTags

   True if Source tags have been found in the PCC file in the same directory as
   $file.

=cut

sub dirHasSourceTags {

   my ($input) = @_;

   my ($file, $path) = fileparse($input);

   exists $sourceTokens{ $path };
}


sub dumpValidEntities {

   print STDERR Dumper %validEntities;

}


=head2 foundInvalidTags

   Returns true if any invalid tags were found while processing the lst files.

=cut

sub foundInvalidTags {
   return exists $tagCount{"Invalid"};
}


=head2 getCrossCheckData

   Get the Cross check data collected while parsing the Lst files

=cut

sub getCrossCheckData {
   \@xcheck_to_process;  
}


=head2 getDirSourceTags

   Gets the Source tokens that have been found in $file's path (in the PCC).

=cut

sub getDirSourceTags {

   my ($input) = @_;

   my ($file, $path) = fileparse($input);

   $sourceTokens{ $path };
}


=head2 getEntityFirstTag

   C<getEntityFirstTag($lineType)>

   Get the name of the first column of a line. Similar to getEntityNameTag, but
   this one works even when the first token on the line does have a tag, 
   i.e. not a pretend tag that starts 000

=cut

sub getEntityFirstTag {

   my ($entity) = @_;

   confess "Opps comment\n" unless $entity ne 'COMMENT';

   my $arrayRef = getOrderForLineType($entity);

   return "" unless defined $arrayRef;

   $arrayRef->[0];
}


=head2 getEntityName

   C<getEntityName($lineType, $lineTokens)>

   Get the name of the entity in this Line, uses the lineType to look up the
   tag holding the tag name. Only works for lines that have a faux tag in the
   first position i.e. one that starts 000

=cut

sub getEntityName {

   my ($lineType, $lineTokens) = @_;

   my $tagName = @{getOrderForLineType($lineType)}[0];
   $lineTokens->{ $tagName }[0];
}


=head2 getEntityNameTag

   Get the name of the first column of a line that does not start with a tag.

=cut

sub getEntityNameTag {

   my ($entity) = @_;
   $columnWithNoTag{$entity};
}

=head2 getHeader

   Return the correct header for a particular tag in a particular line type.

   If no tag is defined for the line type, the default for the tag is used. If
   there is no default for the tag, the tag itself is returned.

   Parameters: $tagName, $lineType

=cut

sub getHeader {
   my ( $tagName, $lineType ) = @_;

   confess "In GetHeader undefined \$tagName" unless defined $tagName;
   confess "In GetHeader undefined \$lineType" unless defined $lineType;

   my $header = 
         $tokenHeader{$lineType}{$tagName} 
      || $tokenHeader{default}{$tagName} 
      || $tagName;

   if ( getOption('missingheader') && $tagName eq $header ) {
      $missing_headers{$lineType}{$header}++;
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

   This is a nested hash indexed on linetype and tag name, each tag that
   appears on a linetype which does not have a defined header will have a defined
   entry in the ahsh.

=cut

sub getMissingHeaders {
   return \%missing_headers;
}



=head2 getOrderForLineType

   Returns an array ref of the order of tags on the line type.

=cut

sub getOrderForLineType {
   my ($lineType) = @_;

   return $masterOrder{$lineType};
};


=head2 getTagCount

   Get the count of valid and invalid tags found

=cut

sub getTagCount {
   \%tagCount;
}



=head2 getValidCategories

   Return a reference to the hash of valid categories for cross checking.

   Format validCategories{$entitytype}{$categoryname}

=cut

sub getValidCategories {
   return \%validCategories;
}



=head2 getValidLineTypes

   Return a list of valid line types (i.e. types with an entry in %masterOrder).

=cut

sub getValidLineTypes {
   return keys %masterOrder;
}


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


=head2 isFauxTag

   Returns true if the given tag is a Faux tag (doesn't exist in the files, but
   the value appears at the start of the line).

=cut

sub isFauxTag {
   my ($tag) = @_;

   exists $fauxTag{$tag};
}



=head2 incCountInvalidTags

   Increment the statistics of invalid tags found, counting both the total and a
   count of each tag by line type.

=cut

sub incCountInvalidTags {

   my ($lineType, $tag) = @_;

   $tagCount{"Invalid"}{"Total"}{$tag}++;
   $tagCount{"Invalid"}{$lineType}{$tag}++;
}


=head2 incCountValidTags

   Increment the statistics of valid tags found, counting both the total and a
   count of each tag by line type.

=cut

sub incCountValidTags {

   my ($lineType, $tag) = @_;

   $tagCount{"Valid"}{"Total"}{$tag}++;
   $tagCount{"Valid"}{$lineType}{$tag}++;
}


=head2 isValidCategory

   c<isValidCategory($lineType, $category)>

   Return true if the category is valid for this linetype

=cut

sub isValidCategory {
   my ($lineType, $category) = @_;

   return exists $validCategories{$lineType}{$category};
}



=head2 isValidCheck

   Returns true if the given check is valid.

=cut

sub isValidCheck{
   my ($check) = @_;
   return exists $validCheckName{$check};
}



=head2 isValidEntity

   Returns true if the entity is valid.

=cut

sub isValidEntity {
   my ($entitytype, $entityname) = @_;

   return exists $validEntities{$entitytype}{$entityname};
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
   my ($gamemode) = @_;
   return exists $validGameModes{$gamemode};
}


=head2 isValidMultiTag

   C<isValidMultiTag(linetype, tag)>

   Returns true if linetype may contain multiple instance of tag 

=cut

sub isValidMultiTag {
   my ($lineType, $tag) = @_;
            
   return exists $master_mult{$lineType}{$tag};
};


=head2 isValidPreTag

   True if the PRE tag is recognised

=cut

sub isValidPreTag {
   my ($tag) = @_;
   
   exists $PreTags{$tag};
}


=head2 isValidSubEntity

   Returns any data stored for the given entity sub-entity combination.

=cut

sub isValidSubEntity {

   my ($entity, $subEntity) = @_;

   $validSubEntities{$entity}{$subEntity};
}


=head2 isValidTag

   C<isValidTag(linetype, tag)>

   Returns true if tag is valid on linetype

=cut

sub isValidTag {
   my ($lineType, $tag) = @_;
            
   return exists $validTags{$lineType}{$tag};
};


=head2 isValidType

   C<isValidType($myEntity, $myType);>

   Returns true if the given type is valid for the given entity.

=cut

sub isValidType {
   my ($entity, $type) = @_;

   return exists $validTypes{$entity}{$type};
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
   if (isValidFixedValue($tag, uc $key)) {
      $key = uc $key;

   # make it titlecase if necessary for the lookup
   } elsif (isValidFixedValue($tag, ucfirst lc $key)) {
      $key = ucfirst lc $key;
   }

   return $key
}



=head2 registerXCheck

   Register this data for later cross checking

=cut

sub registerXCheck {
   my ($entityType, $tag, $file, $line, @values) = @_;
   
   push @xcheck_to_process, [ $entityType, $tag, $file, $line, @values ];
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


=head2 seenSourceToken

   Have we seen this source tag on this path before?

=cut

sub seenSourceToken {

   my ($input, $token) = @_;

   my ($file, $path) = fileparse($input);

   exists $sourceTokens{$path}{$token->tag};
}


=head2 setEntityValid

   Increments the number of times entity has been seen, and makes the exists
   test true for this entity.

=cut

sub setEntityValid {
   my ($entitytype, $entityname) = @_;

   # sometimes things get added to validEntities like foo(cold) =>
   # STRING|cold|fire|sonic we can't increment STRING|cold|fire|sonic when
   # foo(cold) is used in the data
   if (exists $validEntities{$entitytype}{$entityname}) {
      if (Scalar::Util::looks_like_number $validEntities{$entitytype}{$entityname}) {
         $validEntities{$entitytype}{$entityname}++;
      }
   } else {
      $validEntities{$entitytype}{$entityname}++;
   }
}


=head2 setValidSystemArr

   Replace all the data in the given valid system array with the supplied values.

=cut

sub setValidSystemArr {

   my ($type, @values) = @_;

   my $arr = {
      'alignments' => \@validSystemAlignments,
      'checks'     => \@validSystemCheckNames,
      'gamemodes'  => \@validSystemGameModes,
      'stats'      => \@validSystemStats,
      'vars'       => \@validSystemVarNames
   }->{$type};

   if (defined $arr) {
      @{$arr} = @values;
   }
}



=head2 splitAndAddToValidEntities

   ad-hod/special list of thingy It adds to the valid entities instead of the
   valid sub-entities.  We do this when we find a CHOOSE but we do not know what
   it is for.

=cut

sub splitAndAddToValidEntities {
   my ($entitytype, $ability, $value) = @_;

   return unless defined $value;

   for my $abil ( split '\|', $value ) {
      $validEntities{'ABILITY'}{"$ability($abil)"}  = $value;
      $validEntities{'ABILITY'}{"$ability ($abil)"} = $value;
   }
}


=head2 tagTakesFixedValues

   True if this tag only accepts a limited range of values

=cut

sub tagTakesFixedValues {

   my ($tag) = @_;
   return exists $tagFixValue{$tag};
};


=head2 updateValidity

   This operation is intended to be called after parseSystemFiles, since that
   operation can change the value of both @validSystemCheckNames
   @validSystemGameModes,

=cut

sub updateValidity {
   %validCheckName = map { $_ => 1} getValidSystemArr('checks'), '%LIST', '%CHOICE';

   %validGameModes = map { $_ => 1 } (
      getValidSystemArr('gamemodes'),

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
      BONUSSPELLSTAT       => { map { $_ => 1 } ( getValidSystemArr('stats'), qw(NONE) ) },
      SPELLSTAT            => { map { $_ => 1 } ( getValidSystemArr('stats'), qw(SPELL NONE OTHER) ) },
      ALIGN                => { map { $_ => 1 } getValidSystemArr('alignments') },
      PREALIGN             => { map { $_ => 1 } getValidSystemArr('alignments') },
      KEYSTAT              => { map { $_ => 1 } getValidSystemArr('stats') },
   );

   while (my ($key, $value) = each %extraFixValue) {
      $tagFixValue{$key} = $value;
   }

   ##############################################
   # Global variables used by the validation code

   # Add pre-defined valid entities
   for my $var_name (getValidSystemArr('vars')) {
      setEntityValid('DEFINE Variable', $var_name);
   }

   for my $stat (getValidSystemArr('stats')) {
      setEntityValid('DEFINE Variable', $stat);
      setEntityValid('DEFINE Variable', $stat . 'SCORE');
   }

   # Add the magical values 'ATWILL' fot the SPELLS tag's TIMES= component.
   setEntityValid('DEFINE Variable', 'ATWILL');

   # Add the magical values 'UNLIM' fot the CONTAINS tag.
   setEntityValid('DEFINE Variable', 'UNLIM');

};


=head2 validSubEntityExists

   Returns any data stored for the given entity sub-entity combination.

=cut

sub validSubEntityExists {

   my ($entity, $subEntity) = @_;

   $validSubEntities{$entity}{$subEntity};
}


1;
