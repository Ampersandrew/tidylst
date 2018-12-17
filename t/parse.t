#!/usr/bin/perl

use strict;
use warnings;

# expand library path so we can find LstTidy modules
use File::Basename qw(dirname);
use Cwd  qw(abs_path);
use lib dirname(dirname abs_path $0) . '/lib';

use Test::More tests => 45;

use_ok ('LstTidy::Parse');

my %enabled = (
   'ABILITY'         => [ 'code'  => "ABILITY is parsed " ],
   'ABILITYCATEGORY' => [ 'code'  => "ABILITYCATEGORY is parsed " ],
   'BIOSET'          => [ 'code'  => "BIOSET is parsed " ],
   'CLASS'           => [ 'code'  => "CLASS is parsed " ],
   'COMPANIONMOD'    => [ 'code'  => "COMPANIONMOD is parsed " ],
   'DEITY'           => [ 'code'  => "DEITY is parsed " ],
   'DOMAIN'          => [ 'code'  => "DOMAIN is parsed " ],
   'EQUIPMENT'       => [ 'code'  => "EQUIPMENT is parsed " ],
   'EQUIPMOD'        => [ 'code'  => "EQUIPMOD is parsed " ],
   'FEAT'            => [ 'code'  => "FEAT is parsed " ],
   'INFOTEXT'        => [ 0       => "INFOTEXT is not parsed " ],
   'KIT'             => [ 'code'  => "KIT is parsed " ],
   'LANGUAGE'        => [ 'code'  => "LANGUAGE is parsed " ],
   'LSTEXCLUDE'      => [ 0       => "LSTEXCLUDE is not parsed " ],
   'PCC'             => [ 1       => "PCC is not parsed " ],
   'RACE'            => [ 'code'  => "RACE is parsed " ],
   'SKILL'           => [ 'code'  => "SKILL is parsed " ],
   'SOURCELONG'      => [ 0       => "SOURCELONG is not parsed " ],
   'SOURCESHORT'     => [ 0       => "SOURCESHORT is not parsed " ],
   'SOURCEWEB'       => [ 0       => "SOURCEWEB is not parsed " ],
   'SOURCEDATE'      => [ 0       => "SOURCEDATE is not parsed " ],
   'SOURCELINK'      => [ 0       => "SOURCELINK is not parsed " ],
   'SPELL'           => [ 'code'  => "SPELL is parsed " ],
   'TEMPLATE'        => [ 'code'  => "TEMPLATE is parsed " ],
   'WEAPONPROF'      => [ 'code'  => "WEAPONPROF is parsed " ],
   'ARMORPROF'       => [ 'code'  => "ARMORPROF is parsed " ],
   'SHIELDPROF'      => [ 'code'  => "SHIELDPROF is parsed " ],
   'VARIABLE'        => [ 'code'  => "VARIABLE is parsed " ],
   'DATACONTROL'     => [ 'code'  => "DATACONTROL is parsed " ],
   'GLOBALMOD'       => [ 'code'  => "GLOBALMOD is parsed " ],
   '#EXTRAFILE'      => [ 1       => "#EXTRAFILE is not parsed " ],
   'SAVE'            => [ 'code'  => "SAVE is parsed " ],
   'STAT'            => [ 'code'  => "STAT is parsed " ],
   'ALIGNMENT'       => [ 'code'  => "ALIGNMENT is parsed " ] );

for my $type ( keys %enabled ) {
   my ($data, $string) = ( @{ $enabled{$type} } );

   if ($data eq 'code') {
      like(LstTidy::Parse::isParseableFileType($type), qr{^CODE}, $string);
   } else {
      like(LstTidy::Parse::isParseableFileType($type), qr{^\d}, $string);
   }

}

is(LstTidy::Parse::isWriteableFileType('ABILITY'), 1, "Ability files are writeable");
is(LstTidy::Parse::isWriteableFileType('COPYRIGHT'), 0, "Copyright files are not writeable");

is(LstTidy::Parse::isValidCheck('Will'), q{}, "Validity data not yet populated checks");
is(LstTidy::Parse::isValidGamemode('Pathfinder'), q{}, "Validity data not yet populated gamemodes");

LstTidy::Parse::updateValidity();

is(LstTidy::Parse::isValidCheck('Will'), 1, "Valid check is valid");
is(LstTidy::Parse::isValidGamemode('Pathfinder'), 1, "Valid gamemode is valid");

is(LstTidy::Parse::isParseableFileType('Arse'), undef, "Arse is not a parsable File type");
like(LstTidy::Parse::isParseableFileType('ABILITY'), qr{CODE}, "ABILITY is a parsable File type");

is(LstTidy::Parse::isWriteableFileType('COVER'), 0, "COVER is not a writable File type");
is(LstTidy::Parse::isWriteableFileType('EQUIPMENT'), 1, "EQUIPMENT is a writable File type");

# LstTidy::Parse::parse_system_files

