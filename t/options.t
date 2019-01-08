#!/usr/bin/perl

use strict;
use warnings;

# expand library path so we can find TidyLst modules
use File::Basename qw(dirname);
use Cwd  qw(abs_path);
use lib dirname(dirname abs_path $0) . '/lib';

use Test::More tests => 56;

use_ok ('TidyLst::Options');

# ****************************************************************
# Test parseOptions

my @options = qw( basepath   convert   exportlist  filetype
   gamemode       help       htmlhelp  inputpath   man
   missingheader  nojep      nowarning noxcheck    oldsourcetag
   outputerror    outputpath report    systempath  test
   warninglevel   xcheck);

for my $opt ( @options ) {
   is(TidyLst::Options::getOption($opt), undef, "Options $opt is undef before processing command line" );
}

TidyLst::Options::parseOptions('--noxcheck', '--i=foo\\bar');

# when parseOptions has been called, these default values should be set
# unless they were passed as commandline arguments
my %defaults = (
   'warninglevel'  => 'notice',    

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
   is(TidyLst::Options::getOption($key), $value, "Options ${key} is default after processing command line" );
} 

# Calling parseOptions also exercises _processOptions and _fixPath 

is(TidyLst::Options::getOption('noxcheck'), 1, "Command line has changed default noxcheck");
is(TidyLst::Options::getOption('xcheck'), 0, "Command line has changed default xcheck");

is(TidyLst::Options::getOption('basepath'),   qq{foo/bar/},   "basepath set as expected");
is(TidyLst::Options::getOption('inputpath'),  qq{foo/bar/},  "inputpath set as expected");
is(TidyLst::Options::getOption('outputpath'), qq{}, "outputpath is still default");


# ****************************************************************
# Test getOption and setOption

TidyLst::Options::setOption('gamemode', "D&D");
is( TidyLst::Options::getOption('gamemode'), "D&D", "Gamemode updated correctly") ;


# ****************************************************************
# Test isConversionActive, disableConversion, and enableConversion


# Change the state of option 'ALL:Fix Common Extended ASCII'
my $isActive = TidyLst::Options::isConversionActive('ALL:Fix Common Extended ASCII');

if ($isActive) {
   TidyLst::Options::disableConversion('ALL:Fix Common Extended ASCII');
   is( TidyLst::Options::isConversionActive('ALL:Fix Common Extended ASCII'), 0, "Conversion toggled inactive") ;
   TidyLst::Options::enableConversion('ALL:Fix Common Extended ASCII');
   is( TidyLst::Options::isConversionActive('ALL:Fix Common Extended ASCII'), 1, "Conversion returned to active") ;
} else {
   TidyLst::Options::enableConversion('ALL:Fix Common Extended ASCII');
   is( TidyLst::Options::isConversionActive('ALL:Fix Common Extended ASCII'), 1, "Conversion toggled active") ;
   TidyLst::Options::disableConversion('ALL:Fix Common Extended ASCII');
   is( TidyLst::Options::isConversionActive('ALL:Fix Common Extended ASCII'), 0, "Conversion returned to inactive") ;
}

# ****************************************************************
# Test checkInputPath

TidyLst::Options::setOption('inputpath', qq{});
TidyLst::Options::setOption('filetype', qq{});
TidyLst::Options::setOption('man', 0);
TidyLst::Options::setOption('htmlhelp', 0);
TidyLst::Options::setOption('help', 0);

is(TidyLst::Options::checkInputPath(), "inputpath parameter is missing\n", "Correct error for no input path");
is(TidyLst::Options::getOption('help'), 1, "Help is turned on");


# ****************************************************************
#  _enableRequestedConversion
 
is(TidyLst::Options::isConversionActive('DEITY:Followeralign conversion'), 0, "First Conversion inactive") ;
is(TidyLst::Options::isConversionActive('ALL:ADD Syntax Fix'            ), 0, "Second Conversion inactive") ;
is(TidyLst::Options::isConversionActive('ALL:PRESPELLTYPE Syntax'       ), 0, "Third Conversion inactive") ;
is(TidyLst::Options::isConversionActive('ALL:EQMOD has new keys'        ), 0, "Fourth Conversion inactive") ;

TidyLst::Options::_enableRequestedConversion('pcgen5120');
 
is(TidyLst::Options::isConversionActive('DEITY:Followeralign conversion'), 1, "First Conversion active") ;
is(TidyLst::Options::isConversionActive('ALL:ADD Syntax Fix'            ), 1, "Second Conversion active") ;
is(TidyLst::Options::isConversionActive('ALL:PRESPELLTYPE Syntax'       ), 1, "Third Conversion active") ;
is(TidyLst::Options::isConversionActive('ALL:EQMOD has new keys'        ), 1, "Fourth Conversion active") ;
