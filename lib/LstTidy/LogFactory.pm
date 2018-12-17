package LstTidy::LogFactory;

use strict;
use warnings;

use File::Basename qw(dirname);
use Cwd  qw(abs_path);
use lib dirname(dirname abs_path $0);

use LstTidy::Log;
use LstTidy::Options qw(getOption);

my $logger;

sub getLogger {
   
   return $logger if defined $logger;

   $logger = LstTidy::Log->new(warningLevel=>getOption('warninglevel'));

   return $logger;
}

1;
