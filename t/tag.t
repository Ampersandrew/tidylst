#!/usr/bin/perl

use strict;
use warnings;

# expand library path so we can find lsttidy modules
use File::Basename qw(dirname);
use Cwd  qw(abs_path);
use lib dirname(dirname abs_path $0) . '/lib';

use Test::More tests => 22;

use_ok ('LstTidy::Tag');

my $tag = LstTidy::Tag->new(
   tag      => 'KEY',
   value    => 'Rogue ~ Sneak Attack',
   linetype => 'ABILITY',
   file     => 'foo_abilities.lst',
);

is($tag->tag(), 'KEY', "Basic accessor is ok");

is($tag->hasLine(), q{}, "There is no line attribute");

$tag->line(24);

is($tag->hasLine(), 1, "There is now a line attribute");

$tag = LstTidy::Tag->new(
   tag      => 'Category',
   value    => 'Feat',
   linetype => 'ABILITY',
   file     => 'foo_abilities.lst',
   line     => 42,
);

is($tag->tag(), 'Category', "Tag constructed correctly");
is($tag->value(), 'Feat', "value constructed correctly");
is($tag->linetype(), 'ABILITY', "Linetype is correct");
is($tag->file(), 'foo_abilities.lst', "File is correct");
is($tag->hasLine(), 1, "There is a line attribute");
is($tag->line(), 42, "line is correct");

$tag = LstTidy::Tag->new(
   tagValue => 'KEY:Rogue ~ Sneak Attack',
   linetype => 'ABILITY',
   file     => 'foo_abilities.lst',
);

is($tag->tag(), 'KEY', "Tag constructed correctly");
is($tag->value(), 'Rogue ~ Sneak Attack', "value constructed correctly");

is($tag->linetype(), 'ABILITY', "Linetype is unaffected");
is($tag->file(), 'foo_abilities.lst', "File is unaffected");

$tag = LstTidy::Tag->new(
   {
      tagValue => 'LICENCE:',
      linetype => 'ABILITY',
      file     => 'foo_abilities.lst',
   }
);

is($tag->tag(), 'LICENCE', "Tag constructed correctly");
is($tag->value(), '', "value constructed correctly");

is($tag->linetype(), 'ABILITY', "Linetype is unaffected");
is($tag->file(), 'foo_abilities.lst', "File is unaffected");

$tag = LstTidy::Tag->new(
   {
      tagValue => 'BROKEN',
      linetype => 'ABILITY',
      file     => 'foo_abilities.lst',
   }
);

is($tag->tag(), 'BROKEN', "Tag constructed correctly");
is($tag->value(), undef, "value constructed correctly");
is($tag->linetype(), 'ABILITY', "Linetype is unaffected");
is($tag->file(), 'foo_abilities.lst', "File is unaffected");
