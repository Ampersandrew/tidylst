#!/usr/bin/perl

use strict;
use warnings;

# expand library path so we can find LstTidy modules
use File::Basename qw(dirname);
use Cwd  qw(abs_path);
use lib dirname(dirname abs_path $0) . '/lib';

use LstTidy::Tag;

use Test::More tests => 25;
use Test::Warn;

use_ok ('LstTidy::Convert');

my %conversions = (

   ','              => {orig => "x\x82z", expect => "x,z"},  
   ',,'             => {orig => "x\x84z", expect => "x,,z"},
   '...'            => {orig => "x\x85z", expect => "x...z"},
   '^'              => {orig => "x\x88z", expect => "x^z"},
   '<'              => {orig => "x\x8Bz", expect => "x<z"},
   'Oe'             => {orig => "x\x8Cz", expect => "xOez"},
   '\''             => {orig => "x\x91z", expect => "xz'z"},
   '\''             => {orig => "x\x92z", expect => "x'z"},
   '\"'             => {orig => "x\x93z", expect => "x\"z"},
   '\"'             => {orig => "x\x94z", expect => "x\"z"},
   '*'              => {orig => "x\x95z", expect => "x*z"},
   '-'              => {orig => "x\x96z", expect => "x-z"},
   '-'              => {orig => "x\x97z", expect => "x-z"},
   '<sup>~</sup>'   => {orig => "x\x98z", expect => "x<sup>~</sup>z"},
   '<sup>TM</sup>'  => {orig => "x\x99z", expect => "x<sup>TM</sup>z"},
   '>'              => {orig => "x\x9Bz", expect => "x>z"},
   'oe'             => {orig => "x\x9Cz", expect => "xoez"},
);

for my $conv ( keys %conversions ) {

   my $orig   = $conversions{$conv}->{'orig'};
   my $expect = $conversions{$conv}->{'expect'};

   my $got = LstTidy::Convert::convertEntities($orig);

   is($got, $expect, "Converted $expect");
}

# =====================================
# Test convertPreSpellType
# =====================================

my $tag = LstTidy::Tag->new(
   fullTag => 'PRESPELLTYPE:Arcane|Divine,2,3',
   lineType => 'SPELL',
   file     => 'foo_spells.lst',
);

is($tag->id, 'PRESPELLTYPE', "Id is PRESPELLTYPE");
is($tag->value, 'Arcane|Divine,2,3', "Value is Arcane|Divine,2,3"); 

my @arr = ();

LstTidy::Options::parseOptions(@arr);
LstTidy::Options::enableConversion('ALL:PRESPELLTYPE Syntax');

warnings_like { LstTidy::Convert::convertPreSpellType($tag) } [
   qr{Warning: something's wrong at /mnt/c/github/lst-tidy/lib/LstTidy/Log.pm line 270.},
   qr{foo_spells.lst},
   qr{   Invalid standalone PRESPELLTYPE tag "PRESPELLTYPE:Arcane|Divine,2,3" found and converted in SPELL}
], "Throws warnings";

is($tag->id, 'PRESPELLTYPE', "Id has not changed (PRESPELLTYPE)");
is($tag->value, '2,Arcane=3,Divine=3', "Value is now 2,Arcane=3,Divine=3"); 

# =====================================
# Continue Test convertPreSpellType
# =====================================

$tag = LstTidy::Tag->new(
   fullTag => 'FEAT:Foo|PRESPELLTYPE:Arcane,2,3',
   lineType => 'RACE',
   file     => 'foo_race.lst',
);

is($tag->id, 'FEAT', "Id is PRESPELLTYPE");
is($tag->value, 'Foo|PRESPELLTYPE:Arcane,2,3', "Value is Foo|PRESPELLTYPE:Arcane,2,3"); 


warnings_like { LstTidy::Convert::convertPreSpellType($tag) } 
[
   qr{foo_race.lst},
   qr{   Invalid embedded PRESPELLTYPE tag "FEAT:Foo|PRESPELLTYPE:2,Arcane=3" found and converted RACE.}
], "Throws warnings";

is($tag->id, 'FEAT', "Id has not changed (FEAT)");
is($tag->value, 'Foo|PRESPELLTYPE:2,Arcane=3', "Value is now Foo|PRESPELLTYPE:2,Arcane=3"); 
