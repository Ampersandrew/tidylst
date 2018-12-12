#!/usr/bin/perl

use strict;
use warnings;

# expand library path so we can find lsttidy modules
use File::Basename qw(dirname);
use Cwd  qw(abs_path);
use lib dirname(dirname abs_path $0) . '/lib';

use Test::More tests => 43;

use_ok ('LstTidy::Tag');

my $tag = LstTidy::Tag->new(
   tag      => 'KEY',
   value    => 'Rogue ~ Sneak Attack',
   lineType => 'ABILITY',
   file     => 'foo_abilities.lst',
);

is($tag->tag(), 'KEY', "Basic accessor is ok");

is($tag->hasLine(), q{}, "There is no line attribute");

$tag->line(24);

is($tag->hasLine(), 1, "There is now a line attribute");

$tag = LstTidy::Tag->new(
   tag      => 'Category',
   value    => 'Feat',
   lineType => 'ABILITY',
   file     => 'foo_abilities.lst',
   line     => 42,
);

is($tag->tag(), 'Category', "Tag constructed correctly");
is($tag->value(), 'Feat', "value constructed correctly");
is($tag->lineType(), 'ABILITY', "lineType is correct");
is($tag->file(), 'foo_abilities.lst', "File is correct");
is($tag->hasLine(), 1, "There is a line attribute");
is($tag->line(), 42, "line is correct");

$tag = LstTidy::Tag->new(
   tagValue => 'KEY:Rogue ~ Sneak Attack',
   lineType => 'ABILITY',
   file     => 'foo_abilities.lst',
);

is($tag->tag(), 'KEY', "Tag constructed correctly");
is($tag->value(), 'Rogue ~ Sneak Attack', "value constructed correctly");

is($tag->lineType(), 'ABILITY', "lineType is unaffected");
is($tag->file(), 'foo_abilities.lst', "File is unaffected");

$tag = LstTidy::Tag->new(
   {
      tagValue => 'LICENCE:',
      lineType => 'ABILITY',
      file     => 'foo_abilities.lst',
   }
);

is($tag->tag(), 'LICENCE', "Tag constructed correctly");
is($tag->realTag(), 'LICENCE', "LICENCE: Real tag constructed correctly");
is($tag->value(), '', "value constructed correctly");

is($tag->lineType(), 'ABILITY', "lineType is unaffected");
is($tag->file(), 'foo_abilities.lst', "File is unaffected");

$tag = LstTidy::Tag->new(
   {
      tagValue => 'BROKEN',
      lineType => 'ABILITY',
      file     => 'foo_abilities.lst',
   }
);

is($tag->tag(), 'BROKEN', "Tag constructed correctly");
is($tag->realTag(), 'BROKEN', "Real tag constructed correctly");
is($tag->value(), undef, "value constructed correctly");
is($tag->lineType(), 'ABILITY', "lineType is unaffected");
is($tag->file(), 'foo_abilities.lst', "File is unaffected");

$tag = LstTidy::Tag->new(
   {
      tagValue => '!PREFOO:1|Wibble',
      lineType => 'ABILITY',
      file     => 'foo_abilities.lst',
   }
);

is($tag->tag(), 'PREFOO', "PREFOO tag constructed correctly");
is($tag->realTag(), '!PREFOO', "!PREFOO real tag constructed correctly");
is($tag->value(), "1|Wibble", "value constructed correctly");
is($tag->lineType(), 'ABILITY', "lineType is unaffected");
is($tag->file(), 'foo_abilities.lst', "File is unaffected");

is($tag->fullTag(), 'PREFOO:1|Wibble', "Full tag reconstituted correctly.");
is($tag->fullRealTag(), '!PREFOO:1|Wibble', "Full real tag reconstituted correctly.");


$tag = LstTidy::Tag->new(
   {
      tagValue => 'ABILITY:FEAT|AUTOMATIC|Toughness',
      lineType => 'ABILITY',
      file     => 'foo_abilities.lst',
   }
);


is($tag->tag(), 'ABILITY', "Tag constructed correctly");
is($tag->realTag(), 'ABILITY', "Real tag constructed correctly");
is($tag->value(), "FEAT|AUTOMATIC|Toughness", "value constructed correctly");
is($tag->lineType(), 'ABILITY', "lineType is unaffected");
is($tag->file(), 'foo_abilities.lst', "File is unaffected");

is($tag->fullTag(), 'ABILITY:FEAT|AUTOMATIC|Toughness', "Full tag reconstituted correctly.");
is($tag->fullRealTag(), 'ABILITY:FEAT|AUTOMATIC|Toughness', "Full Real tag reconstituted correctly.");
is($tag->origTag(), 'ABILITY:FEAT|AUTOMATIC|Toughness', "Original tag is correct.");

$tag->tag('FEAT');

is($tag->tag(), 'FEAT', "Tag changes correctly");
is($tag->fullTag(), 'FEAT:FEAT|AUTOMATIC|Toughness', "Full tag reconstituted correctly after change of tag.");
is($tag->fullRealTag(), 'FEAT:FEAT|AUTOMATIC|Toughness', "Full Real tag reconstituted correctly after change of tag.");
is($tag->origTag(), 'ABILITY:FEAT|AUTOMATIC|Toughness', "Original tag is correct after change of tag.");
