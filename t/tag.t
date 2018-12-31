#!/usr/bin/perl

use strict;
use warnings;

# expand library path so we can find lsttidy modules
use File::Basename qw(dirname);
use Cwd  qw(abs_path);
use lib dirname(dirname abs_path $0) . '/lib';

use Test::More tests => 44;

use_ok ('LstTidy::Tag');

# Test the most basic form of the constructor with the four mantatory data items

my $tag = LstTidy::Tag->new(
   id       => 'KEY',
   value    => 'Rogue ~ Sneak Attack',
   lineType => 'ABILITY',
   file     => 'foo_abilities.lst',
);

is($tag->id, 'KEY', "Basic accessor is ok");

# Test the has line predicate and line attribute

is($tag->hasLine, q{}, "There is no line attribute");

$tag->line(24);

is($tag->hasLine, 1, "There is now a line attribute");

# Test the the six basic accessors work

$tag = LstTidy::Tag->new(
   id       => 'Category',
   value    => 'Feat',
   lineType => 'ABILITY',
   file     => 'foo_abilities.lst',
   line     => 42,
);

is($tag->id, 'Category', "Id is Category");
is($tag->value, 'Feat', "Value is FEAT");
is($tag->lineType, 'ABILITY', "lineType is ABILITY");
is($tag->file, 'foo_abilities.lst', "File is correct");
is($tag->hasLine, 1, "There is a line attribute");
is($tag->line, 42, "line is correct");

# Test using the full tag instead of the id & value parameters

$tag = LstTidy::Tag->new(
   fullTag => 'KEY:Rogue ~ Sneak Attack',
   lineType => 'ABILITY',
   file     => 'foo_abilities.lst',
);

is($tag->id, 'KEY', "Id is KEY");
is($tag->value, 'Rogue ~ Sneak Attack', "Value is Rogue ~ Sneak Attack");

# Test empty Value properly sets the id & value

$tag = LstTidy::Tag->new(
   {
      fullTag => 'LICENCE:',
      lineType => 'ABILITY',
      file     => 'foo_abilities.lst',
   }
);

is($tag->id, 'LICENCE', "Id constructed correctly");
is($tag->realId, 'LICENCE', "LICENCE: Real tag constructed correctly");
is($tag->value, '', "value constructed correctly");

# Test that a broken tag (no :) gives an undefined value.
# Also test the realId accessor (identical to id for non !PRE)

$tag = LstTidy::Tag->new(
   fullTag => 'BROKEN',
   lineType => 'ABILITY',
   file     => 'foo_abilities.lst',
);

is($tag->id, 'BROKEN', "Id constructed correctly");
is($tag->realId, 'BROKEN', "Real tag constructed correctly");
is($tag->value, undef, "value constructed correctly");

# Test the negated PRE sets id & value and realId correctly

$tag = LstTidy::Tag->new(
   fullTag => '!PREFOO:1,Wibble',
   lineType => 'ABILITY',
   file     => 'foo_abilities.lst',
);

is($tag->id, 'PREFOO', "PREFOO tag constructed correctly");
is($tag->realId, '!PREFOO', "!PREFOO real tag constructed correctly");
is($tag->value, "1,Wibble", "value constructed correctly");

is($tag->fullTag, 'PREFOO:1,Wibble', "Full tag reconstituted correctly.");
is($tag->fullRealTag, '!PREFOO:1,Wibble', "Full real tag reconstituted correctly.");


$tag = LstTidy::Tag->new(
   fullTag  => 'ABILITY:FEAT|AUTOMATIC|Toughness',
   lineType => 'ABILITY',
   file     => 'foo_abilities.lst',
);


is($tag->id, 'ABILITY', "Id constructed correctly");
is($tag->realId, 'ABILITY', "Real tag constructed correctly");
is($tag->value, "FEAT|AUTOMATIC|Toughness", "value constructed correctly");
is($tag->lineType, 'ABILITY', "lineType is unaffected");
is($tag->file, 'foo_abilities.lst', "File is unaffected");

is($tag->fullTag, 'ABILITY:FEAT|AUTOMATIC|Toughness', "Full tag reconstituted correctly.");
is($tag->fullRealTag, 'ABILITY:FEAT|AUTOMATIC|Toughness', "Full Real tag reconstituted correctly.");
is($tag->origTag, 'ABILITY:FEAT|AUTOMATIC|Toughness', "Original tag is correct.");

# Test that changing the id updates id, fullTag, fullRealTag, but not origTag

$tag->id('FEAT');

is($tag->id, 'FEAT', "Id changes correctly");
is($tag->fullTag, 'FEAT:FEAT|AUTOMATIC|Toughness', "Full tag reconstituted correctly after change of tag.");
is($tag->fullRealTag, 'FEAT:FEAT|AUTOMATIC|Toughness', "Full Real tag reconstituted correctly after change of tag.");
is($tag->origTag, 'ABILITY:FEAT|AUTOMATIC|Toughness', "Original tag is correct after change of tag.");

# Test noMoreErrors

is($tag->noMoreErrors, undef, "Unset no more errors is undefined");

$tag->noMoreErrors(1);

is($tag->noMoreErrors, 1, "set no more errors is 1");

$tag = LstTidy::Tag->new(
   fullTag  => 'ABILITY:FEAT|AUTOMATIC|Toughness|!PREFOO:1,Wibble',
   lineType => 'ABILITY',
   file     => 'foo_abilities.lst',
);

my $subTag = $tag->clone(id => '!PREFOO', value => '1,Wibble');

is($subTag->id, 'PREFOO', "PREFOO tag correct after clone");
is($subTag->realId, '!PREFOO', "!PREFOO real tag correct after clone");
is($subTag->value, "1,Wibble", "value correct after clone");
is($subTag->lineType, 'ABILITY', "lineType correct after clone");
is($subTag->file, 'foo_abilities.lst', "File correct after clone");

is($subTag->fullTag, 'PREFOO:1,Wibble', "Full tag reconstituted correctly after clone.");
is($subTag->fullRealTag, '!PREFOO:1,Wibble', "Full real tag reconstituted correctly after clone.");
