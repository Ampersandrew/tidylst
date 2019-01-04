#!/usr/bin/perl

use strict;
use warnings;

# expand library path so we can find LstTidy modules
use File::Basename qw(dirname);
use Cwd  qw(abs_path);
use lib dirname(dirname abs_path $0) . '/lib';

use LstTidy::Token;

use Test::More tests => 10;
use Test::Warn;

use_ok ('LstTidy::Line');

my $line = LstTidy::Line->new (
   lineType => 'ABILITY',
   file     => 'foo_ability',
);

is($line->lineType, 'ABILITY', 'lineType is ABILITY');
is($line->file, 'foo_ability', 'file is foo_ability');

is($line->hasColumn('KEY'), "", 'Nothing in column KEY');

my $token = LstTidy::Token->new(
   tag      => 'KEY',
   value    => 'Rogue ~ Sneak Attack',
   lineType => 'ABILITY',
   file     => 'foo_abilities.lst',
);

$line->addToken($token);

is($line->hasColumn('KEY'), 1, 'Column KEY is populated');

my $column = $line->column('KEY');

is($column->[0]->value, 'Rogue ~ Sneak Attack', 'first token in column is correct');

my $token1 = LstTidy::Token->new(
   fullToken  => 'ABILITY:FEAT|AUTOMATIC|Acrobatic',
   lineType  => 'CLASS',
   file     => 'foo_class.lst',
);

my $token2 = LstTidy::Token->new(
   fullToken  => 'ABILITY:FEAT|AUTOMATIC|Toughness',
   lineType  => 'CLASS',
   file      => 'foo_class.lst',
);

is($line->hasColumn('ABILITY'), "", 'Nothing in column ABILITY');

$line->addToken($token1);

is($line->hasColumn('ABILITY'), 1, 'Column ABILITY is populated');

$line->addToken($token2);

$column = $line->column('ABILITY');

is($column->[0]->value, 'FEAT|AUTOMATIC|Acrobatic', 'First FEAT is correct');
is($column->[1]->value, 'FEAT|AUTOMATIC|Toughness', 'Second FEAT is correct');
