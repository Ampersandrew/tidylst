#!/usr/bin/perl

use strict;
use warnings;

# expand library path so we can find TidyLst modules
use File::Basename qw(dirname);
use Cwd  qw(abs_path);
use lib dirname(dirname abs_path $0) . '/lib';

use TidyLst::Token;

use Test::More tests => 23;
use Test::Warn;

use_ok ('TidyLst::Convert');

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
#   '<sup>~</sup>'   => {orig => "x\x98z", expect => "x<sup>~</sup>z"},
#   '<sup>TM</sup>'  => {orig => "x\x99z", expect => "x<sup>TM</sup>z"},
   '>'              => {orig => "x\x9Bz", expect => "x>z"},
   'oe'             => {orig => "x\x9Cz", expect => "xoez"},
);

for my $conv ( keys %conversions ) {

   my $orig   = $conversions{$conv}->{'orig'};
   my $expect = $conversions{$conv}->{'expect'};

   my $got = TidyLst::Convert::convertEntities($orig);

   is($got, $expect, "Converted $expect");
}

# =====================================
# Test convertPreSpellType
# =====================================

my $token = TidyLst::Token->new(
   fullToken => 'PRESPELLTYPE:Arcane|Divine,2,3',
   lineType  => 'SPELL',
   file      => 'foo_spells.lst',
);

is($token->tag, 'PRESPELLTYPE', "Tag is PRESPELLTYPE");
is($token->value, 'Arcane|Divine,2,3', "Value is Arcane|Divine,2,3"); 

my @arr = ();

TidyLst::Options::parseOptions(@arr);
TidyLst::Options::enableConversion('ALL:PRESPELLTYPE Syntax');

warnings_like { TidyLst::Convert::convertPreSpellType($token) } [
   qr{Warning: something's wrong at /mnt/c/github/tidylst/lib/TidyLst/Log.pm line},
   qr{foo_spells.lst},
   qr{   Invalid standalone PRESPELLTYPE tag "PRESPELLTYPE:Arcane|Divine,2,3" found and converted in SPELL}
], "Throws warnings";

is($token->tag, 'PRESPELLTYPE', "Tag has not changed (PRESPELLTYPE)");
is($token->value, '2,Arcane=3,Divine=3', "Value is now 2,Arcane=3,Divine=3"); 

# =====================================
# Continue Test convertPreSpellType
# =====================================

$token = TidyLst::Token->new(
   fullToken => 'FEAT:Foo|PRESPELLTYPE:Arcane,2,3',
   lineType  => 'RACE',
   file      => 'foo_race.lst',
);

is($token->tag, 'FEAT', "Tag is PRESPELLTYPE");
is($token->value, 'Foo|PRESPELLTYPE:Arcane,2,3', "Value is Foo|PRESPELLTYPE:Arcane,2,3"); 


warnings_like { TidyLst::Convert::convertPreSpellType($token) } 
[
   qr{foo_race.lst},
   qr{   Invalid embedded PRESPELLTYPE tag "FEAT:Foo|PRESPELLTYPE:2,Arcane=3" found and converted RACE.}
], "Throws warnings";

is($token->tag, 'FEAT', "Tag has not changed (FEAT)");
is($token->value, 'Foo|PRESPELLTYPE:2,Arcane=3', "Value is now Foo|PRESPELLTYPE:2,Arcane=3"); 
