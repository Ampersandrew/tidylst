#!/usr/bin/perl

use strict;
use warnings;

# expand library path so we can find LstTidy modules
use File::Basename qw(dirname);
use Cwd  qw(abs_path);
use lib dirname(dirname abs_path $0) . '/lib';

use Test::More tests => 58;

use_ok ('LstTidy::Options');

# ****************************************************************
# Test parseOptions

my @options = qw( basepath   convert   exportlist  filetype
   gamemode       help       htmlhelp  inputpath   man
   missingheader  nojep      nowarning noxcheck    oldsourcetag
   outputerror    outputpath report    systempath  test
   warninglevel   xcheck);

for my $opt ( @options ) {
   is(LstTidy::Options::getOption($opt), undef, "Options $opt is undef before processing command line" );
}

LstTidy::Options::parseOptions('--noxcheck', '--i=foo\\bar');

# when parseOptions has been called, these default values should be set
# unless they were passed as commandline arguments
my %defaults = (
   'warninglevel'  => 'info',    

   'exportlist'    => 0,         
   'help'          => 0,         
   'htmlhelp'      => 0,         
   'man'           => 0,         
   'missingheader' => 0,         
   'nojep'         => 0,         
   'nowarning'     => 0,         
   'noxcheck'      => 0,         
   'oldsourcetag'  => 0,         
   'report'        => 0,         
   'test'          => 0,         

   'xcheck'        => 1,         

   'basepath'      => q{},       
   'convert'       => q{},       
   'filetype'      => q{},       
   'gamemode'      => q{},       
   'inputpath'     => q{},       
   'outputerror'   => q{},       
   'outputpath'    => q{},       
   'systempath'    => q{},       
);

# All except the cross check options should not have the default
for my $key ( grep {$_ !~ qr((?:check|(?:base|put)path)$)} keys %defaults ) {
   my $value = $defaults{$key}; 
   is(LstTidy::Options::getOption($key), $value, "Options ${key} is default after processing command line" );
} 

# Calling parseOptions also exercises _processOptions and _fixPath 

is(LstTidy::Options::getOption('noxcheck'), 1, "Command line has changed default noxcheck");
is(LstTidy::Options::getOption('xcheck'), 0, "Command line has changed default xcheck");

is(LstTidy::Options::getOption('basepath'),   qq{foo/bar},   "basepath set as expected");
is(LstTidy::Options::getOption('inputpath'),  qq{foo/bar},  "inputpath set as expected");
is(LstTidy::Options::getOption('outputpath'), qq{}, "outputpath is still default");


# ****************************************************************
# Test getOption and setOption

LstTidy::Options::setOption('gamemode', "D&D");
is( LstTidy::Options::getOption('gamemode'), "D&D", "Gamemode updated correctly") ;


# ****************************************************************
# Test isConversionActive, disableConversion, and enableConversion


# Change the state of option 'ALL:Fix Common Extended ASCII'
my $isActive = LstTidy::Options::isConversionActive('ALL:Fix Common Extended ASCII');

if ($isActive) {
   LstTidy::Options::disableConversion('ALL:Fix Common Extended ASCII');
   is( LstTidy::Options::isConversionActive('ALL:Fix Common Extended ASCII'), 0, "Conversion toggled inactive") ;
   LstTidy::Options::enableConversion('ALL:Fix Common Extended ASCII');
   is( LstTidy::Options::isConversionActive('ALL:Fix Common Extended ASCII'), 1, "Conversion returned to active") ;
} else {
   LstTidy::Options::enableConversion('ALL:Fix Common Extended ASCII');
   is( LstTidy::Options::isConversionActive('ALL:Fix Common Extended ASCII'), 1, "Conversion toggled active") ;
   LstTidy::Options::disableConversion('ALL:Fix Common Extended ASCII');
   is( LstTidy::Options::isConversionActive('ALL:Fix Common Extended ASCII'), 0, "Conversion returned to inactive") ;
}

# ****************************************************************
# Test checkInputPath

LstTidy::Options::setOption('inputpath', qq{});
LstTidy::Options::setOption('filetype', qq{});
LstTidy::Options::setOption('man', 0);
LstTidy::Options::setOption('htmlhelp', 0);
LstTidy::Options::setOption('help', 0);

is(LstTidy::Options::checkInputPath(), "inputpath parameter is missing\n", "Correct error for no input path");
is(LstTidy::Options::getOption('help'), 1, "Help is turned on");

# ****************************************************************
#  fixWarningLevel

LstTidy::Options::setOption('warninglevel' => 'debug');
LstTidy::Options::fixWarningLevel();

is(LstTidy::Options::getOption('warninglevel'), 7, "dwbug is correctly converted to 7");

LstTidy::Options::setOption('warninglevel' => 'none');

my $expected = <<"STRING_END";
\nInvalid warning level: none
Valid options are: error, warning, notice, info and debug\n
STRING_END

is(LstTidy::Options::fixWarningLevel(), $expected, "Correct error message for bad warning level");


# ****************************************************************
#  _enableRequestedConversion
 
is(LstTidy::Options::isConversionActive('DEITY:Followeralign conversion'), 0, "First Conversion inactive") ;
is(LstTidy::Options::isConversionActive('ALL:ADD Syntax Fix'            ), 0, "Second Conversion inactive") ;
is(LstTidy::Options::isConversionActive('ALL:PRESPELLTYPE Syntax'       ), 0, "Third Conversion inactive") ;
is(LstTidy::Options::isConversionActive('ALL:EQMOD has new keys'        ), 0, "Fourth Conversion inactive") ;

LstTidy::Options::_enableRequestedConversion('pcgen5120');
 
is(LstTidy::Options::isConversionActive('DEITY:Followeralign conversion'), 1, "First Conversion active") ;
is(LstTidy::Options::isConversionActive('ALL:ADD Syntax Fix'            ), 1, "Second Conversion active") ;
is(LstTidy::Options::isConversionActive('ALL:PRESPELLTYPE Syntax'       ), 1, "Third Conversion active") ;
is(LstTidy::Options::isConversionActive('ALL:EQMOD has new keys'        ), 1, "Fourth Conversion active") ;
