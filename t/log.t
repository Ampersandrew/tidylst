#!/usr/bin/perl

use strict;
use warnings;

# expand library path so we can find LstTidy modules
use File::Basename qw(dirname);
use Cwd  qw(abs_path);
use lib dirname(dirname abs_path $0) . '/lib';

use Test::More tests => 37;
use Test::Warn;

use_ok ('LstTidy::Log');

my $log = LstTidy::Log->new({warningLevel=>1});

is($log->warningLevel, 5, "Creating with warning level too low uses default");

$log = LstTidy::Log->new({warningLevel=>8});

is($log->warningLevel, 5, "Creating with warning level too high uses default");

$log = LstTidy::Log->new({warningLevel=>6});

is($log->warningLevel, 6, "Creating with a numeric warning level in range uses default");

$log = LstTidy::Log->new({warningLevel=>'foo'});

is($log->warningLevel, 5, "Creating with a non-existent string warning level uses default");

$log = LstTidy::Log->new({warningLevel=>'debug'});

is($log->warningLevel, 7, "Creating with a valid string warning level uses it");

$log->warningLevel('foo');

is($log->warningLevel, 5, "Changing the warning level to bad string value gives default");

$log->warningLevel('error');

is($log->warningLevel, 3, "Changing the warning level to error (a good string value) uses it");

$log->warningLevel('warning');

is($log->warningLevel, 4, "Changing the warning level to warning (a good string value) uses it");

$log->warningLevel('notice');

is($log->warningLevel, 5, "Changing the warning level to notice (a good string value) uses it");

$log->warningLevel('info');

is($log->warningLevel, 6, "Changing the warning level to info (a good string value) uses it");

$log->warningLevel('debug');

is($log->warningLevel, 7, "Changing the warning level to debug (a good string value) uses it");


# ************************************************************ 
# Test previousFile

$log->previousFile("my_foo.lst");
is($log->previousFile, 'my_foo.lst', "Previous file name works getter and setter");

# ************************************************************ 
#  Test isStartOfLog and header

is($log->header, '', "New object has blank header");
is($log->isStartOfLog, 1, "New object has is start of log true");
is($log->printHeader , 1, "New object has print header true");

$log->header("Header string\n");

is($log->header, "Header string\n", "New object does not modify header");
is($log->isStartOfLog, 1, "is start of log still true");
is($log->previousFile, '', "Previous file has been cleared");
is($log->printHeader , 1, "New object has print header true");

warnings_like {$log->debug('Dude it broke', "my_foo.lst")}
[qr"^Header\s+string", qr"^my_foo.lst", qr"^DBGDude\s+it\s+broke",], "Test Debug";

is($log->isStartOfLog, 0, "is start of log is false");

# not the start of the log, so the ehader will be modified
$log->header('Second header');

is($log->header, "\nSecond header", "Second header is modified");
is($log->previousFile, '', "Previous file has been cleared");
is($log->printHeader , 1, "New object has print header true");

warnings_like {$log->info('Dude it broke', "my_bar.lst")}
[qr"", qr"^my_bar.lst", qr"^  -Dude\s+it\s+broke",], "Test Info";

is($log->previousFile, 'my_bar.lst', "Previous file name set");

warnings_like {$log->notice('A notice', "my_bar.lst")} [qr"^   A\s+notice",], "Test notice";

warnings_like {$log->warning('A warning', "my_bar.lst")} [qr"^\*=>A\s+warning",], "Test warning";

warnings_like {$log->error('An error', "my_bar.lst")} [qr"^\*\*\*An\s+error",], "Test error";

# ************************************************************ 
# Test alternative to warning

is($log->isOutputting, 1, "Object is set up to output via warn.");

is($log->isOutputting(0), 0, "Object is now gathering output.");

$log->header('Third header');

$log->notice(q{Something to note}, "my_bar.lst");

my ($header, $filename, $message) = ( @{ $log->collectedWarnings } );

is($header, "\nThird header", "Header was printed");
is($filename, "my_bar.lst\n", "header added, filename is also printed");
is($message, qq{   Something to note\n}, "Message is correct");

is(scalar @{$log->collectedWarnings}, 3, "Collected Warnings has three entries.");
$log->collectedWarnings( [] );
is(scalar @{$log->collectedWarnings}, 0, "Collected Warnings has been emptied.");
