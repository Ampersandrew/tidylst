#!/usr/bin/perl

use strict;
use warnings;

# expand library path so we can find LstTidy modules
use File::Basename qw(dirname);
use Cwd  qw(abs_path);
use lib dirname(dirname abs_path $0) . '/lib';

use Test::More tests => 15;

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
