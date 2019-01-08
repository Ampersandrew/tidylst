package TidyLst::LogFactory;

use strict;
use warnings;

require Exporter;

our @ISA = qw(Exporter);
our @EXPORT_OK = qw(getLogger);

use File::Basename qw(dirname);
use Cwd  qw(abs_path);
use lib dirname(dirname abs_path $0);

use TidyLst::Log;
use TidyLst::Options qw(getOption);

my $log;

sub getLogger {
   
   return $log if defined $log;

   $log = TidyLst::Log->new(warningLevel=>getOption('warninglevel'));

   return $log;
}

1;
