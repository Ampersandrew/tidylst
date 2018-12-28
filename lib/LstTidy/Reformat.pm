package LstTidy::Reformat;

use strict;
use warnings;

require Exporter;

our @ISA = qw(Exporter);
our @EXPORT_OK = qw(getEntityName getEntityNameTag);

use File::Basename qw(dirname);
use Cwd  qw(abs_path);
use lib dirname(dirname abs_path $0);

use LstTidy::Options qw{getOption isConversionActive};

# Global tags allowed in PCC files.
our @doublePCCTags = (
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


# The PRExxx tags. These are used in many of the line types, but they are only
# defined once and every line type will get the same sort order.

my @PRETags = (
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
      'KEY',
      'SORTKEY',
      'NAMEISPI',
      'OUTPUTNAME',
      'FACT:AppliedName',
      'CATEGORY',
      'TYPE:.CLEAR',
      'TYPE:*',
      'VISIBLE',
      'INFO:Prerequisite',
      @PRETags,
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
      @globalBONUSTags,              # [ 1956340 ] Centralize global BONUS tags
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
      'DR',
      'REP',
      'COST',
      'KIT',
      'FACT:*',
      @SOURCETags,
      'NATURALATTACKS:*',
      'ASPECT:*',
      'BENEFIT:.CLEAR',
      'BENEFIT:*',
      'INFO:*',
      'TEMPDESC',
      'SPELLKNOWN:CLASS:*',
      'SPELLKNOWN:DOMAIN:*',
      'SPELLLEVEL:CLASS:*',
      'SPELLLEVEL:DOMAIN:*',
      'UNENCUMBEREDMOVE',
      'TEMPBONUS:*',
      'TEMPVALUE:*',
      'AUTO:FEAT:*',                   # Deprecated 6.05.01
      'VFEAT:*',                       # Deprecated 6.05.01
      'ADD:FEAT:*',                    # Deprecated 6.05.01
      'ADD:VFEAT:*',                   # Deprecated 6.05.01
      'APPLIEDNAME',                   # Deprecated 6.05.01
      'SA:.CLEAR',                     # Deprecated
      'SA:*',                          # Deprecated
      'ADD:SPECIAL',                   # Deprecated - Remove 5.16 - Special abilities are now set using hidden feats 0r Abilities.
      'LANGAUTO:.CLEAR',               # Deprecated - 6.0
      'LANGAUTO:*',                    # Deprecated - 6.0
   ],

   'ABILITYCATEGORY' => [
      '000AbilityCategory',
      'VISIBLE',
      'EDITABLE',
      'EDITPOOL',
      'FRACTIONALPOOL',
      'POOL',
      'CATEGORY',
      'TYPE',
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
      'TYPE',
      'HANDS',
      @PRETags,
      @SOURCETags,
      @globalBONUSTags,              # [ 1956340 ] Centralize global BONUS tags
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
      'KEY',                           # [ 1695877 ] KEY tag is global
      'NAMEISPI',
      'OUTPUTNAME',
      'HD',
      'XTRAFEATS',
      'SPELLSTAT',
      'BONUSSPELLSTAT',
      'FACT:SpellType:*',
      'SPELLTYPE',
      'TYPE',
      'FACT:ClassType',
      'CLASSTYPE',
      'FACT:Abb:*',
      'ABB',
      'MAXLEVEL',
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
      'DOMAIN:*',                      # [ 1973526 ] DOMAIN is supported on Class line
      'ADDDOMAINS:*',
      'REMOVE',
      'BONUS:HD:*',                    # Class Lines
      @globalBONUSTags,              # [ 1956340 ] Centralize global BONUS tags
      'BONUS:WEAPON:*',
      'REP:*',
      'SPELLLIST',
      'GENDER',
      'TEMPLATE:.CLEAR',
      'TEMPLATE:*',
      'KIT',
      'DEITY',
      @PRETags,
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
      'HASSPELLFORMULA',               # [ 1893279 ] HASSPELLFORMULA Class Line tag  # [ 1973497 ] HASSPELLFORMULA is deprecated
      'ADD:SPECIAL',                   # Deprecated - Remove 5.16 - Special abilities are now set using hidden feats 0r Abilities.
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
      @PRETags,
      'SAB:.CLEAR',
      'SAB:*',
      'BONUS:HD:*',                    # Class Lines
      @globalBONUSTags,              # [ 1956340 ] Centralize global BONUS tags
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
      'ADD:VFEAT:*',                   # Deprecated 6.05.01
      'SPECIALS',                      # Deprecated 6.05.01
      'FEAT',                          # Deprecated 6.05.01
      'VFEAT:*',                       # Deprecated 6.05.01
      'AUTO:FEAT:*',                   # Deprecated 6.05.01
      'SA:.CLEAR:*',                   # Deprecated 6.05.01
      'SA:*',                          # Deprecated 6.05.01
      'ADD:SPECIAL',                   # Deprecated - Remove 5.16 - Special abilities are now set using hidden feats 0r Abilities.
      'LANGAUTO:.CLEAR',               # Deprecated - 6.0
      'LANGAUTO:*',                    # Deprecated - 6.0
      'FEATAUTO:.CLEAR',               # Deprecated - 6.0
      'FEATAUTO:*',                    # Deprecated - 6.0
   ],

   'COMPANIONMOD' => [
      '000Follower',
      'SORTKEY',
      'KEY',                           # [ 1695877 ] KEY tag is global
      'FOLLOWER',
      'TYPE',
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
      'MOVE',
      'KIT',
      'AUTO:ARMORPROF:*',
      'SAB:.CLEAR',
      'SAB:*',
      'ADD:LANGUAGE',
      'DEFINE:*',
      'DEFINESTAT:*',
      @globalBONUSTags,              # [ 1956340 ] Centralize global BONUS tags
      'RACETYPE',
      'SWITCHRACE:*',
      'TEMPLATE:*',                    # [ 2946558 ] TEMPLATE can be used in COMPANIONMOD lines
      'STACK',
      'MULT',
      'CHOOSE',
      'SELECT',
      'DESC:.CLEAR',
      'DESC:*',
      'FEAT:.CLEAR',                   # Deprecated 6.05.01
      'FEAT:*',                        # Deprecated 6.05.01
      'VFEAT:*',                       # Deprecated 6.05.01
      'AUTO:FEAT:.CLEAR',              # Deprecated 6.05.01
      'AUTO:FEAT:*',                   # Deprecated 6.05.01
      'SA:.CLEAR',                     # Deprecated 6.05.01
      'SA:*',                          # Deprecated 6.05.01
   ],

   'DATACONTROL' => [
      '000DatacontrolName',
      'DATAFORMAT',
      'REQUIRED',
      'SELECTABLE',
      'VISIBLE',
      'DISPLAYNAME',
      'EXPLANATION',
   ],

   'DEITY' => [
      '000DeityName',
      'SORTKEY',
      'KEY',                           # [ 1695877 ] KEY tag is global
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
      @PRETags,
      @QUALIFYTags,
      @globalBONUSTags,              # [ 1956340 ] Centralize global BONUS tags
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
      'KEY',                           # [ 1695877 ] KEY tag is global
      'NAMEISPI',
      'OUTPUTNAME',
      @PRETags,
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
      @globalBONUSTags,              # [ 1956340 ] Centralize global BONUS tags
      @SOURCETags,
      'DESCISPI',
      'DESC:.CLEAR',
      'DESC:*',
      'SPELLKNOWN:DOMAIN:*',
      'SPELLLEVEL:DOMAIN',
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
      'KEY',
      'SORTKEY',
      'NAMEISPI',
      'OUTPUTNAME',
      'PROFICIENCY:WEAPON',
      'PROFICIENCY:ARMOR',
      'PROFICIENCY:SHIELD',
      'TYPE:.CLEAR',
      'TYPE:*',
      'ALTTYPE',
      'RESIZE',                        # [ 1956719 ] Add RESIZE tag to Equipment file
      'CONTAINS',
      'NUMPAGES',
      'PAGEUSAGE',
      'COST',
      'WT',
      'SLOTS',
      @PRETags,
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
      @globalBONUSTags,              # [ 1956340 ] Centralize global BONUS tags
      'BONUS:EQM:*',
      'BONUS:EQMARMOR:*',
      'BONUS:EQMWEAPON:*',
      'BONUS:ESIZE:*',
      'BONUS:ITEMCOST:*',
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
      'AUTO:WEAPONPROF:*',
      'DESC:.CLEAR',
      'DESC:*',
      'DESCISPI',
      'INFO:*',
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
      'NAMEISPI',
      'OUTPUTNAME',
      'FORMATCAT',
      'NAMEOPT',
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
      @PRETags,
      @QUALIFYTags,
      'ADDPROF',
      'VISION',
      'SR',
      'DR',
      @globalBONUSTags,              # [ 1956340 ] Centralize global BONUS tags
      'BONUS:EQM:*',
      'BONUS:EQMARMOR:*',
      'BONUS:EQMWEAPON:*',
      'BONUS:ITEMCOST:*',
      'BONUS:WEAPON:*',
      'SPROP:*',
      'ABILITY',
      'FUMBLERANGE',
      'SAB:.CLEAR',
      'SAB:*',
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
      'UNENCUMBEREDMOVE',
      'RATEOFFIRE',                    #  Deprecated 6.05.01
      'VFEAT:*',                       #  Deprecated 6.05.01
      'SA:.CLEAR',                     #  Deprecated 6.05.01
      'SA:*',                          #  Deprecated 6.05.01
   ],

# This entire File is being deprecated
   'FEAT' => [
      '000FeatName',
      'KEY',                           # [ 1695877 ] KEY tag is global
      'NAMEISPI',
      'OUTPUTNAME',
      'TYPE:.CLEAR',
      'TYPE',
      'VISIBLE',
      'CATEGORY',                      # [ 1671410 ] xcheck CATEGORY:Feat in Feat object.
      @PRETags,
      @QUALIFYTags,
      'SERVESAS',
      'SA:.CLEAR',
      'SA:*',
      'SAB:.CLEAR',
      'SAB:*',
      'DEFINE:*',
      'DEFINESTAT:*',
      'SPELL:*',
      'SPELLS:*',
      'DESCISPI',
      'DESC:.CLEAR',                   # [ 1594651 ] New Tag: Feat.lst: DESC:.CLEAR and multiple DESC tags
      'DESC:*',                        # [ 1594651 ] New Tag: Feat.lst: DESC:.CLEAR and multiple DESC tags
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
      @globalBONUSTags,              # [ 1956340 ] Centralize global BONUS tags
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
   ],

   'GLOBALMODIFIER' => [
      '000GlobalmonName',
      'EXPLANATION',
   ],

   'KIT ALIGN' => [
      'ALIGN',
      'OPTION',
      @PRETags,
   ],

   'KIT CLASS' => [
      'CLASS',
      'LEVEL',
      'SUBCLASS',
      'OPTION',
      @PRETags,
   ],

   'KIT DEITY' => [
      'DEITY',
      'DOMAIN',
      'COUNT',
      'OPTION',
      @PRETags,
   ],

   'KIT FEAT' => [
      'FEAT',
      'FREE',
      'COUNT',
      'OPTION',
      @PRETags,
   ],
   'KIT ABILITY' => [
      'ABILITY',
      'FREE',
      'OPTION',
      @PRETags,
   ],

   'KIT FUNDS' => [
      'FUNDS',
      'QTY',
      'OPTION',
      @PRETags,
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
      @PRETags,
   ],

   'KIT GENDER' => [
      'GENDER',
      'OPTION',
      @PRETags,
   ],

   'KIT KIT' => [
      'KIT',
      'OPTION',
      @PRETags,
   ],

   'KIT LANGBONUS' => [
      'LANGBONUS',
      'OPTION',
      @PRETags,
   ],

   'KIT LEVELABILITY' => [
      'LEVELABILITY',
      'ABILITY',
      @PRETags,
   ],

   'KIT NAME' => [
      'NAME',
      @PRETags,
   ],

   'KIT PROF' => [
      'PROF',
      'RACIAL',
      'COUNT',
      @PRETags,
   ],

   'KIT RACE' => [
      'RACE',
      @PRETags,
   ],

   'KIT REGION' => [
      'REGION',
      @PRETags,
   ],

   'KIT SELECT' => [
      'SELECT',
      @PRETags,
   ],

   'KIT SKILL' => [
      'SKILL',
      'RANK',
      'FREE',
      'COUNT',
      'OPTION',
      'SELECTION',
      @PRETags,
   ],

   'KIT SPELLS' => [
      'SPELLS',
      'COUNT',
      'OPTION',
      @PRETags,
   ],

   'KIT STARTPACK' => [
      'STARTPACK',
      'TYPE',
      'VISIBLE',
      'APPLY',
      'EQUIPBUY',
      'EQUIPSELL',
      'TOTALCOST',
      @PRETags,
      'SOURCEPAGE',
   ],

   'KIT STAT' => [
      'STAT',
      'OPTION',
      @PRETags,
   ],

   'KIT TABLE' => [
      'TABLE',
      'LOOKUP',
      'VALUES',
      @PRETags,
   ],

   'KIT TEMPLATE' => [
      'TEMPLATE',
      'OPTION',
      @PRETags,
   ],

   'LANGUAGE' => [
      '000LanguageName',
      'KEY',                           # [ 1695877 ] KEY tag is global
      'NAMEISPI',
      'TYPE',
      'SOURCEPAGE',
      @PRETags,
      @QUALIFYTags,
   ],

   'MASTERBONUSRACE' => [
      '000MasterBonusRace',
      'TYPE',
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
      'BONUS:SAVE:*',                  # Global        Replacement for CHECKS
      'BONUS:SKILL:*',
      'BONUS:STAT:*',
      'BONUS:UDAM:*',
      'BONUS:VAR:*',
      'ADD:LANGUAGE',
      'ABILITY:*',                     # [ 2596967 ] ABILITY not recognized for MASTERBONUSRACE
      'VFEAT:*',                       # Deprecated 6.05.01
      'SA:.CLEAR',                     # Deprecated 6.05.01
      'SA:*',                          # Deprecated 6.05.01
      'SAB:.CLEAR',
      'SAB:*',

   ],

   'PCC' => [
      'ALLOWDUPES',
      'CAMPAIGN',
      'GAMEMODE',
      'GENRE',
      'BOOKTYPE',
      'KEY',                           # KEY is allowed
      'PUBNAMELONG',
      'PUBNAMESHORT',
      'PUBNAMEWEB',
      'RANK',
      'SETTING',
      'TYPE',
      'PRECAMPAIGN',
      '!PRECAMPAIGN',
      'SHOWINMENU',                    # [ 1718370 ] SHOWINMENU tag missing for PCC files
      'SOURCELONG',
      'SOURCESHORT',
      'SOURCEWEB',
      'SOURCEDATE',                    # [ 1584007 ] New Tag: SOURCEDATE in PCC
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
      'COMPANIONLIST',                 # [ 1672551 ] PCC tag COMPANIONLIST
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
      'CLASSSKILL',
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
      'WEAPONPROF',
      '#EXTRAFILE',                    # Fix #EXTRAFILE so it recognizes #EXTRAFILE references (so OGL is a known referenced file again.)

      #These tags are normal file global tags....
      @doublePCCTags,                  # Global tags that are double - $tag has an embeded ':'
   ],

   'RACE' => [
      '000RaceName',
      'SORTKEY',
      'KEY',                           # [ 1695877 ] KEY tag is global
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
      @PRETags,
      @QUALIFYTags,
      'SERVESAS',
      'LANGBONUS:.CLEAR',
      'LANGBONUS:*',
      'WEAPONBONUS:*',
      'CHANGEPROF:*',
      'PROF',
      @globalBONUSTags,              # [ 1956340 ] Centralize global BONUS tags
      'BONUS:LANGUAGES:*',
      'CSKILL:.CLEAR',
      'CSKILL',
      'CCSKILL',
      'MONCSKILL',
      'MONCCSKILL',
      'AUTO:ARMORPROF:*',
      'AUTO:EQUIP:*',
      'AUTO:FEAT:*',                   #  Deprecated 6.05.01
      'AUTO:LANG:*',
      'AUTO:SHIELDPROF:*',
      'AUTO:WEAPONPROF:*',
      'VFEAT:*',                       #  Deprecated 6.05.01
      'FEAT:*',                        #  Deprecated 6.05.01
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
      'RACETYPE:.CLEAR',
      'RACETYPE:*',
      'RACESUBTYPE:.CLEAR',
      'RACESUBTYPE:*',
      'TYPE',
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
      'ADD:FEAT:*',                    # Deprecated 6.05.01
      'ADD:LANGUAGE:*',
      'ADD:SPELLCASTER:*',
      'ADD:TEMPLATE:*',
      'ADD:VFEAT:*',                   # Deprecated 6.05.01
      'REGION',
      'SUBREGION',
      'SPELLKNOWN:CLASS:*',
      'SPELLKNOWN:DOMAIN:*',
      'SPELLLEVEL:CLASS:*',
      'SPELLLEVEL:DOMAIN:*',
      'KIT',
      'SA:.CLEAR',                     # Deprecated
      'SA:*',                          # Deprecated
      'ADD:SPECIAL',                   # Deprecated - Remove 5.16 - Special abilities are now set using hidden feats 0r Abilities.
      'LANGAUTO:.CLEAR',               # Deprecated - 6.0
      'LANGAUTO:*',                    # Deprecated - 6.0
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
      'TYPE',
      'HANDS',
      @PRETags,
      @SOURCETags,
      @globalBONUSTags,              # [ 1956340 ] Centralize global BONUS tags
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
      'KEY',                           # [ 1695877 ] KEY tag is global
      'NAMEISPI',
      'OUTPUTNAME',
      'KEYSTAT',
      'USEUNTRAINED',
      'ACHECK',
      'EXCLUSIVE',
      'CLASSES',
      'TYPE',
      'VISIBLE',
      @PRETags,
      @QUALIFYTags,
      'SERVESAS',
      @SOURCETags,
      'STACK',
      'MULT',
      'CHOOSE',
      'SELECT',
      'SITUATION',
      'DEFINE',
      'DEFINESTAT:*',
      'VFEAT:*',                       # Deprecated 6.05.01
      'AUTO:EQUIP:*',
      'ABILITY',
      @globalBONUSTags,              # [ 1956340 ] Centralize global BONUS tags
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
      'KEY',                           # [ 1695877 ] KEY tag is global
      'NAMEISPI',
      'OUTPUTNAME',
      'TYPE',
      'CLASSES:.CLEARALL',
      'CLASSES:*',
      'DOMAINS',
      'STAT:*',
      'PPCOST',
#     'SPELLPOINTCOST:*',              # Delay implementing this until SPELLPOINTCOST is documented
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
      @PRETags,
      'DEFINE',
      'DEFINESTAT:*',
#     @globalBONUSTags,              # [ 1956340 ] Centralize global BONUS tags
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
      'BONUS:SAVE:*',                  # Global        Replacement for CHECKS
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
#     'SPELLPOINTCOST:*',
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
      'KEY',                           # [ 1695877 ] KEY tag is global
      'NAMEISPI',
      'OUTPUTNAME',
      'HD',
#     'ABB',                           # Invalid for SubClass
      'COST',
      'PROHIBITCOST',
      'CHOICE',
      'SPELLSTAT',
      'SPELLTYPE',
      'LANGAUTO:.CLEAR',               # Deprecated 6.05.01
      'LANGAUTO:*',                    # Deprecated 6.05.01
      'LANGBONUS:.CLEAR',
      'LANGBONUS:*',
      'BONUS:ABILITYPOOL:*',           # SubClass has a short list of BONUS tags
      'BONUS:CASTERLEVEL:*',
      'BONUS:CHECKS:*',
      'BONUS:COMBAT:*',
      'BONUS:DC:*',
      'BONUS:FEAT:*',                  # Deprecated 6.05.01
      'BONUS:HD:*',
      'BONUS:SAVE:*',                  # Global Replacement for CHECKS
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
      'ADD:FEAT:*',                    # Deprecated 6.05.01
      'ADD:LANGUAGE:*',
      'ADD:SPELLCASTER:*',
      'ADD:TEMPLATE:*',
      'ADD:VFEAT:*',                   # Deprecated 6.05.01
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
      @PRETags,
      'CSKILL:.CLEAR',
      'CSKILL',
      'CCSKILL:.CLEAR',
      'CCSKILL',
      'DOMAIN:*',                      # [ 1973526 ] DOMAIN is supported on Class line
      'ADDDOMAINS',
      'UNENCUMBEREDMOVE',
      @SOURCETags,
      'SA:.CLEAR:*',                   # Deprecated
      'SA:*',                          # Deprecated
      'ADD:SPECIAL',                   # Deprecated - Remove 5.16 - Special abilities are now set using hidden feats 0r Abilities.
   ],

   'SUBSTITUTIONCLASS' => [
      '000SubstitutionClassName',
      'KEY',                           # [ 1695877 ] KEY tag is global
      'NAMEISPI',
      'OUTPUTNAME',
#     'ABB',                           # Invalid for SubClass
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
      'BONUS:FEAT:*',                  # Deprecated 6.05.01
      'BONUS:HD:*',
      'BONUS:SAVE:*',                  # Global Replacement for CHECKS
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
      'ADD:FEAT:*',                    # Deprecated 6.05.01
      'ADD:LANGUAGE:*',
      'ADD:SPELLCASTER:*',
      'ADD:TEMPLATE:*',
      'ADD:VFEAT:*',                   # Deprecated 6.05.01
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
      @PRETags,
      'CSKILL:.CLEAR',
      'CSKILL',
      'CCSKILL:.CLEAR',
      'CCSKILL',
      'ADDDOMAINS',
      'UNENCUMBEREDMOVE',
      @SOURCETags,
      'ADD:SPECIAL',                   # Deprecated - Remove 5.16 - Special abilities are now set using hidden feats 0r Abilities.
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
      'SA:.CLEAR:*',                   # Deprecated 6.05.01
      'SA:*',                          # Deprecated 6.05.01
      'SAB:.CLEAR',
      'SAB:*',
      'BONUS:HD:*',                    # Class Lines
      @globalBONUSTags,              # [ 1956340 ] Centralize global BONUS tags
      'BONUS:WEAPON:*',
      'HITDIE',
      'ABILITY:*',
      'DEFINE:*',
      'DEFINESTAT:*',
      'CSKILL:.CLEAR',
      'CSKILL:*',
      'CCSKILL:.CLEAR',
      'CCSKILL:*',
      'LANGAUTO.CLEAR',                # Deprecated - Remove 6.0
      'LANGAUTO:*',                    # Deprecated - Remove 6.0
      'ADD:.CLEAR',
      'ADD:*',
      'ADD:ABILITY:*',
      'ADD:CLASSSKILLS',
      'ADD:EQUIP:*',
      'ADD:FEAT:*',                    # Deprecated 6.05.01
      'ADD:LANGUAGE:*',
      'ADD:SPECIAL',                   # Deprecated - Remove 5.16 - Special abilities are now set using hidden feats 0r Abilities.
      'ADD:TEMPLATE:*',
      'ADD:VFEAT:*',                   # Deprecated 6.05.01
      'DONOTADD:*',
      'EXCHANGELEVEL',
      'SPELLS:*',
      'TEMPLATE:.CLEAR',
      'TEMPLATE:*',
      'VFEAT:*',                       # Deprecated 6.05.01
      'AUTO:ARMORPROF:*',
      'AUTO:EQUIP:*',
      'AUTO:FEAT:*',                   # Deprecated 6.05.01
      'AUTO:SHIELDPROF:*',
      'AUTO:WEAPONPROF:*',
      'CHANGEPROF:*',
      'REMOVE',
      'ADDDOMAINS',
      'WEAPONBONUS',
      'FEATAUTO:.CLEAR',               # Deprecated 6.05.01
      'FEATAUTO:*',                    # Deprecated 6.05.01
      'SUBCLASS',
      'SPELLLIST',
      'NATURALATTACKS',
      'UNENCUMBEREDMOVE',
      'PREVAREQ:*',
      'SPECIALS',                      # Deprecated
      'SPELL',                         # Deprecated
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
      'SA:.CLEAR:*',                   # Deprecated 6.05.01
      'SA:*',                          # Deprecated 6.05.01
      'SAB:.CLEAR',
      'SAB:*',
      'BONUS:HD:*',                    # Class Lines
      @globalBONUSTags,              # [ 1956340 ] Centralize global BONUS tags
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
      'ADD:FEAT:*',                    # Deprecated 6.05.01
      'ADD:LANGUAGE:*',
      'ADD:TEMPLATE:*',
      'ADD:VFEAT:*',                   # Deprecated 6.05.01
      'EXCHANGELEVEL',
      'SPECIALS',                      # Deprecated 6.05.01
      'SPELL',
      'SPELLS:*',
      'TEMPLATE:.CLEAR',
      'TEMPLATE:*',
      'VFEAT:*',                       # Deprecated 6.05.01
      'AUTO:ARMORPROF:*',
      'AUTO:EQUIP:*',
      'AUTO:FEAT:*',                   # Deprecated 6.05.01
      'AUTO:SHIELDPROF:*',
      'AUTO:WEAPONPROF:*',
      'CHANGEPROF:*',
      'REMOVE',
      'ADDDOMAINS',
      'WEAPONBONUS',
      'FEATAUTO:.CLEAR',               # Deprecated 6.05.01
      'FEATAUTO:*',                    # Deprecated 6.05.01
      'SUBCLASS',
      'SPELLLIST',
      'NATURALATTACKS',
      'UNENCUMBEREDMOVE',
      'LANGAUTO.CLEAR',                # Deprecated - Remove 6.0
      'LANGAUTO:*',                    # Deprecated - Remove 6.0
      'ADD:SPECIAL',                   # Deprecated - Remove 5.16 - Special abilities are now set using hidden feats 0r Abilities.
   ],

   'SWITCHRACE' => [
      'SWITCHRACE',
   ],

   'TEMPLATE' => [
      '000TemplateName',
      'SORTKEY',
      'KEY',                           # [ 1695877 ] KEY tag is global
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
      'SA:.CLEAR',                     # Deprecated 6.05.01
      'SA:*',                          # Deprecated 6.05.01
      'SAB:.CLEAR',
      'SAB:*',
      'DEFINE:*',
      'DEFINESTAT:*',
      'LEVEL:*',
      @PRETags,
      @QUALIFYTags,
      @globalBONUSTags,              # [ 1956340 ] Centralize global BONUS tags
      'BONUSFEATS',                    # Template Bonus
      'BONUS:MONSKILLPTS',             # Template Bonus
      'BONUSSKILLPOINTS',              # Template Bonus
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
      'ADD:FEAT:*',                    # Deprecated 6.05.01
      'ADD:LANGUAGE:*',
      'ADD:TEMPLATE:*',
      'ADD:VFEAT:*',                   # Deprecated 6.05.01
      'FAVOREDCLASS',
      'ABILITY:*',
      'FEAT:*',                        # Deprecated 6.05.01
      'VFEAT:*',                       # Deprecated 6.05.01
      'AUTO:ARMORPROF:*',
      'AUTO:EQUIP:*',
      'AUTO:FEAT:*',                   # Deprecated 6.05.01
      'AUTO:LANG:*',
      'AUTO:SHIELDPROF:*',
      'AUTO:WEAPONPROF:*',
      'REMOVE:*',
      'CHANGEPROF:*',
      'KIT',
      'LANGBONUS:.CLEAR',
      'LANGBONUS:*',
      'MOVE',
      'MOVEA',                         # Deprecated 6.05.01
      'MOVECLONE',
      'REGION',
      'SUBREGION',
      'REMOVABLE',
      'SR:*',
      'SUBRACE',
      'RACETYPE',
      'RACESUBTYPE:.REMOVE',
      'RACESUBTYPE:*',
      'TYPE',
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
      'TEMPBONUS',
      'SPELL:*',                       # Deprecated 5.x.x - Remove 6.0 - use SPELLS
      'ADD:SPECIAL',                   # Deprecated - Remove 5.16 - Special abilities are now set using hidden feats 0r Abilities.
#     'HEIGHT',                        # Deprecated
      'LANGAUTO:.CLEAR',               # Deprecated - 6.0
      'LANGAUTO:*',                    # Deprecated - 6.0
#     'WEIGHT',                        # Deprecated
   ],

   'VARIABLE' => [
      '000VariableName',
      'EXPLANATION',
      'GLOBAL'
   ],

   'WEAPONPROF' => [
      '000WeaponName',
      'KEY',                           # [ 1695877 ] KEY tag is global
      'NAMEISPI',
      'OUTPUTNAME',
      'TYPE',
      'HANDS',
      @PRETags,
      @SOURCETags,
      @globalBONUSTags,              # [ 1956340 ] Centralize global BONUS tags
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

my %columnWithNoTag = (
   'ABILITY'           => '000AbilityName', 
   'ABILITYCATEGORY'   => '000AbilityCategory',
   'ALIGNMENT'         => '000AlignmentName',
   'ARMORPROF'         => '000ArmorName',
   'CLASS Level'       => '000Level',
   'CLASS'             => '000ClassName',
   'COMPANIONMOD'      => '000Follower',
   'DATACONTROL'       => '000DatacontrolName',
   'DEITY'             => '000DeityName',
   'DOMAIN'            => '000DomainName',
   'EQUIPMENT'         => '000EquipmentName',
   'EQUIPMOD'          => '000ModifierName',
   'FEAT'              => '000FeatName',
   'GLOBALMOD'         => '000GlobalmodName',
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

my %master_mult;        # Will hold the tags that can be there more then once

my %validTags;         # Will hold the valid tags for each type of file.



=head2 getEntityName

   C<getEntityName(lineType, lineTokens)>

   Get the name of the entity in this Line, uses the lineType to look up the
   tag holding the tag name.

=cut

sub getEntityName {

   my ($lineType, $lineTokens) = @_;

   my $tagName    = @{getLineTypeOrder($lineType)}[0];
   my $identifier = $lineTokens->{ $tagName }[0];
}



=head2 getEntityNameTag

   Get the name of the first column of a line that does not start with a tag.

=cut

sub getEntityNameTag {

   my ($entity) = @_;
   $columnWithNoTag{$entity};
}




=head2 getValidLineTypes

   Return a list of valid line types (i.e. types with an entry in %masterOrder).

=cut

sub getValidLineTypes {
   return keys %masterOrder;
}


=head2 getLineTypeOrder

   Returns an array ref of the order of tags on the line type.

=cut

sub getLineTypeOrder {
   my ($lineType) = @_;

   return $masterOrder{$lineType};
};


=head2 constructValidTags

   Construct the valid tags for all file types. Also populate the data
   structure that allows a tag to appear more than once on a line.

=cut

sub constructValidTags {

   #################################################
   # We populate %validTags for all file types.

   for my $line_type ( getValidLineTypes() ) {
      for my $tag ( @{ getLineTypeOrder($line_type) } ) {
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


=head2 isValidMultiTag

   C<isValidMultiTag(linetype, tag)>

   Returns true if linetype may contain multiple instance of tag 

=cut

sub isValidMultiTag {
   my ($lineType, $tag) = @_;
            
   return exists $master_mult{$lineType}{$tag};
};

=head2 isValidTag

   C<isValidTag(linetype, tag)>

   Returns true if tag is valid on linetype

=cut

sub isValidTag {
   my ($lineType, $tag) = @_;
            
   return exists $validTags{$lineType}{$tag};
};

#################################################################
######################## Conversion #############################
# Tags that must be seen as valid to allow conversion.

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

   if ( isConversionActive('BIOSET:generate the new files') ) {
      push @{ $masterOrder{'RACE'} },           'AGE', 'HEIGHT', 'WEIGHT';
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

   # vvvvvv This one is disactivated
   if ( 0 && isConversionActive('ALL:Convert SPELL to SPELLS') ) {
      push @{ $masterOrder{'CLASS Level'} },    'SPELL:*';
      push @{ $masterOrder{'DOMAIN'} },         'SPELL:*';
      push @{ $masterOrder{'EQUIPMOD'} },       'SPELL:*';
      push @{ $masterOrder{'SUBCLASSLEVEL'} },  'SPELL:*';
   }

   # vvvvvv This one is disactivated
   if ( 0 && isConversionActive('TEMPLATE:HITDICESIZE to HITDIE') ) {
      push @{ $masterOrder{'TEMPLATE'} },       'HITDICESIZE';
   }
}

1;
