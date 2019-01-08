#!/usr/bin/perl

use strict;
use warnings;

# expand library path so we can find TidyLst modules
use File::Basename qw(dirname);
use Cwd  qw(abs_path);
use lib dirname(dirname abs_path $0) . '/lib';

use TidyLst::Token;
use TidyLst::Options qw(getOption parseOptions);

use Test::More tests => 15;
use Test::Warn;

use_ok ('TidyLst::Line');

my $line = TidyLst::Line->new (
   type => 'ABILITY',
   file => 'foo_ability',
);

is($line->type, 'ABILITY', 'type is ABILITY');
is($line->file, 'foo_ability', 'file is foo_ability');

is($line->hasColumn('KEY'), "", 'Nothing in column KEY');

my $token = TidyLst::Token->new(
   tag      => 'KEY',
   value    => 'Rogue ~ Sneak Attack',
   lineType => 'ABILITY',
   file     => 'foo_abilities.lst',
);

$line->add($token);

is($line->hasColumn('KEY'), 1, 'Column KEY is populated');

my $column = $line->column('KEY');

is($column->[0]->value, 'Rogue ~ Sneak Attack', 'first token in column is correct');
is($line->_columnLength('KEY'), 24, "Column length correct for single entry");

parseOptions(@ARGV);

my $token1 = TidyLst::Token->new(
   fullToken => 'ABILITY:FEAT|AUTOMATIC|Acrobatic',
   lineType  => 'CLASS',
   file      => 'foo_class.lst',
);

my $token2 = TidyLst::Token->new(
   fullToken => 'ABILITY:FEAT|AUTOMATIC|Toughness',
   lineType  => 'CLASS',
   file      => 'foo_class.lst',
);

is($line->hasColumn('ABILITY'), "", 'Nothing in column ABILITY');

$line->add($token1);

is($line->hasColumn('ABILITY'), 1, 'Column ABILITY is populated');

$line->add($token2);

$column = $line->column('ABILITY');

is($column->[0]->value, 'FEAT|AUTOMATIC|Acrobatic', 'First FEAT is correct');
is($column->[1]->value, 'FEAT|AUTOMATIC|Toughness', 'Second FEAT is correct');
is($line->_columnLength('ABILITY'), 68, "Column length correct for two entries");

is($line->_columnLength('ABILITY'), 68, "Column length does not destroy the data");

$token1 = TidyLst::Token->new(
   fullToken => 'TYPE:Magic.Medium',
   lineType  => 'CLASS',
   file      => 'foo_equipment.lst',
);

$token2 = TidyLst::Token->new(
   fullToken => 'TYPE:Container.Spellbook.Wondrous',
   lineType  => 'CLASS',
   file      => 'foo_equipment.lst',
);

$line->add($token1);
$line->add($token2);

is($line->hasType('Spellbook'), 1, "Line has TYPE Spellbook");
is($line->hasType('Sword'), 0, "Line does not have TYPE Sword");
