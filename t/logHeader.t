#!/usr/bin/perl

use strict;
use warnings;

# expand library path so we can find TidyLst modules
use File::Basename qw(dirname);
use Cwd  qw(abs_path);
use lib dirname(dirname abs_path $0) . '/lib';

use Test::More tests => 3;

use_ok ('TidyLst::LogHeader');

my $head = TidyLst::LogHeader::get('PCC');
my $expect = "================================================================\n"
   . "Messages generated while parsing the .PCC files\n"
   . "----------------------------------------------------------------\n";

is($head, $expect, "PCC header correct");

$head = TidyLst::LogHeader::get('PCC', "lib/Foo/");
$expect = "================================================================\n"
. "Messages generated while parsing the .PCC files\n"
. "lib/Foo/\n"
. "----------------------------------------------------------------\n";

is($head, $expect, "PCC header contains path");
