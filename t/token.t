#!/usr/bin/perl

use strict;
use warnings;

# expand library path so we can find lsttidy modules
use File::Basename qw(dirname);
use Cwd  qw(abs_path);
use lib dirname(dirname abs_path $0) . '/lib';

use Test::More tests => 44;

use_ok ('LstTidy::Token');

# Test the most basic form of the constructor with the four mantatory data items

my $token = LstTidy::Token->new(
   tag      => 'KEY',
   value    => 'Rogue ~ Sneak Attack',
   lineType => 'ABILITY',
   file     => 'foo_abilities.lst',
);

is($token->tag, 'KEY', "Basic accessor is ok");

# Test the has line predicate and line attribute

is($token->hasLine, q{}, "There is no line attribute");

$token->line(24);

is($token->hasLine, 1, "There is now a line attribute");

# Test the the six basic accessors work

$token = LstTidy::Token->new(
   tag      => 'Category',
   value    => 'Feat',
   lineType => 'ABILITY',
   file     => 'foo_abilities.lst',
   line     => 42,
);

is($token->tag, 'Category', "Tag is Category");
is($token->value, 'Feat', "Value is FEAT");
is($token->lineType, 'ABILITY', "lineType is ABILITY");
is($token->file, 'foo_abilities.lst', "File is correct");
is($token->hasLine, 1, "There is a line attribute");
is($token->line, 42, "line is correct");

# Test using the full tag instead of the tag & value parameters

$token = LstTidy::Token->new(
   fullToken => 'KEY:Rogue ~ Sneak Attack',
   lineType  => 'ABILITY',
   file      => 'foo_abilities.lst',
);

is($token->tag, 'KEY', "Tag is KEY");
is($token->value, 'Rogue ~ Sneak Attack', "Value is Rogue ~ Sneak Attack");

# Test empty Value properly sets the tag & value

$token = LstTidy::Token->new(
   {
      fullToken => 'LICENCE:',
      lineType  => 'ABILITY',
      file      => 'foo_abilities.lst',
   }
);

is($token->tag, 'LICENCE', "Tag constructed correctly");
is($token->realTag, 'LICENCE', "LICENCE: Real tag constructed correctly");
is($token->value, '', "value constructed correctly");

# Test that a broken tag (no :) gives an undefined value.
# Also test the realTag accessor (identical to tag for non !PRE)

$token = LstTidy::Token->new(
   fullToken => 'BROKEN',
   lineType  => 'ABILITY',
   file      => 'foo_abilities.lst',
);

is($token->tag, 'BROKEN', "Tag constructed correctly");
is($token->realTag, 'BROKEN', "Real tag constructed correctly");
is($token->value, undef, "value constructed correctly");

# Test the negated PRE sets tag & value and realTag correctly

$token = LstTidy::Token->new(
   fullToken => '!PREFOO:1,Wibble',
   lineType  => 'ABILITY',
   file      => 'foo_abilities.lst',
);

is($token->tag, 'PREFOO', "PREFOO tag constructed correctly");
is($token->realTag, '!PREFOO', "!PREFOO real tag constructed correctly");
is($token->value, "1,Wibble", "value constructed correctly");

is($token->fullToken, 'PREFOO:1,Wibble', "Full tag reconstituted correctly.");
is($token->fullRealToken, '!PREFOO:1,Wibble', "Full real tag reconstituted correctly.");


$token = LstTidy::Token->new(
   fullToken  => 'ABILITY:FEAT|AUTOMATIC|Toughness',
   lineType  => 'ABILITY',
   file      => 'foo_abilities.lst',
);


is($token->tag, 'ABILITY', "Tag constructed correctly");
is($token->realTag, 'ABILITY', "Real tag constructed correctly");
is($token->value, "FEAT|AUTOMATIC|Toughness", "value constructed correctly");
is($token->lineType, 'ABILITY', "lineType is unaffected");
is($token->file, 'foo_abilities.lst', "File is unaffected");

is($token->fullToken, 'ABILITY:FEAT|AUTOMATIC|Toughness', "Full tag reconstituted correctly.");
is($token->fullRealToken, 'ABILITY:FEAT|AUTOMATIC|Toughness', "Full Real tag reconstituted correctly.");
is($token->origToken, 'ABILITY:FEAT|AUTOMATIC|Toughness', "Original tag is correct.");

# Test that changing the tag updates tag, fullToken, fullRealToken, but not origToken

$token->tag('FEAT');

is($token->tag, 'FEAT', "Tag changes correctly");
is($token->fullToken, 'FEAT:FEAT|AUTOMATIC|Toughness', "Full tag reconstituted correctly after change of tag.");
is($token->fullRealToken, 'FEAT:FEAT|AUTOMATIC|Toughness', "Full Real tag reconstituted correctly after change of tag.");
is($token->origToken, 'ABILITY:FEAT|AUTOMATIC|Toughness', "Original tag is correct after change of tag.");

# Test noMoreErrors

is($token->noMoreErrors, undef, "Unset no more errors is undefined");

$token->noMoreErrors(1);

is($token->noMoreErrors, 1, "set no more errors is 1");

$token = LstTidy::Token->new(
   fullToken  => 'ABILITY:FEAT|AUTOMATIC|Toughness|!PREFOO:1,Wibble',
   lineType  => 'ABILITY',
   file      => 'foo_abilities.lst',
);

my $subToken = $token->clone(tag => '!PREFOO', value => '1,Wibble');

is($subToken->tag, 'PREFOO', "PREFOO tag correct after clone");
is($subToken->realTag, '!PREFOO', "!PREFOO real tag correct after clone");
is($subToken->value, "1,Wibble", "value correct after clone");
is($subToken->lineType, 'ABILITY', "lineType correct after clone");
is($subToken->file, 'foo_abilities.lst', "File correct after clone");

is($subToken->fullToken, 'PREFOO:1,Wibble', "Full tag reconstituted correctly after clone.");
is($subToken->fullRealToken, '!PREFOO:1,Wibble', "Full real tag reconstituted correctly after clone.");
