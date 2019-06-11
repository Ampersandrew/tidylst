package TidyLst::File;

use strict;
use warnings;

# expand library path so we can find TidyLst modules
use File::Basename qw(dirname);
use Cwd  qw(abs_path);
use lib dirname(dirname abs_path $0);

use TidyLst::Options qw(getOption);

use Mouse;
   

has [qw( originalName pccDirectory type )] => (
   is       => 'ro',
   isa      => 'Str',
   required => 1,
);

has 'gameMode' => (
   is       => 'ro',
   isa      => 'ArrayRef[Str]',
   required => 1,
);

has 'inputName' => (
   is        => 'rw',
   isa       => 'Str',
   predicate => 'hasInputName',
);

has 'outputName' => (
   is        => 'rw',
   isa       => 'Str',
   predicate => 'hasOutputName',
);

has 'vendorName' => (
   is        => 'rw',
   isa       => 'Str',
   predicate => 'hasVendorName',
);

has [qw(isOnInputPath isMultiLine)] => (
   is       => 'rw',
   isa      => 'Bool',
);


sub BUILD {

   my ($self) = @_;

   my $name = $self->originalName;

   # Change all the \ for / in the file name
   $name =~ tr{\\}{/};

   # See if the vendor path replacement is necessary
   if ($name =~ m{ ^[*] }xmsi && getOption('vendorpath')) {
      $name = $self->_maybeSetVendorFile($name);
   }

   # If we weren't able to set a vendor path
   if (!$self->hasVendorName) {
      $name = $self->_addBaseOrPCC($name);
   }

   # Remove /xxx/../ if it exists in the file name
   if ($name =~ / [.][.] /xms ) {
      if( $name !~ s{ [/] [^/]+ [/]+ [.][.] [/] }{/}xmsg ) {
         die qq{Cannot deal with the .. directory in "$name"};
      }
   }
   
   # At this point $name should have the name of the file to read.
   my $inputPath = getOption('inputpath');
   my $index     = index $name, $inputPath;

   $self->isOnInputPath($index == 0);
   $self->inputName($name);

   $self->_setOutputName;
}

sub _addBaseOrPCC {

   my ($self, $name) = @_;

   # Potentially replace @ by the base path
   my $basePath   = getOption('basepath');
   my $mungedName = $name =~ s{ ^[@] [/]? }{$basePath}xmsir;

   # If name hasn't changed, there was no leading @, the name is relative to
   # the PCCDirectory
   if ($name eq $mungedName) {
      if ($self->pccDirectory =~ qr/\/$/) {
         $name = $self->pccDirectory . $name;
      } else {
         $name = $self->pccDirectory . "/${name}";
      }
   } else {
      $name = $mungedName;
   }

   return $name;
}


# If the filename in the PCC began with *, then we should check if the file
# exists under the vendorpath. If that file does not exist, then replace the *
# with @ and try the standard lookups. This is only called if the vendor path
# option was set and the filename starts with an *

sub _maybeSetVendorFile {

   my ($self, $name) = @_;

   # Remove the leading * and the / if it is present
   $name =~ s{ ^[*] [/]? }{}xmsi;

   my $vendorFile = getOption('vendorpath') . $name;

   # If the vendor path replacement references a file that actually exists,
   # then we're done.
   if ( -e $vendorFile ) {
      $self->vendorName($vendorFile);
      return  $vendorFile;
   }

   return '@' . $name;
}


# Only set the output name if the file is on the input path. This prevents the
# overwriting of files referenced by PCCs we process that are under a path
# other than the input path.

sub _setOutputName {
   my ($self) = @_;

   my $inputPath  = getOption('inputpath');
   my $outputPath = getOption('outputpath');

   if ($self->isOnInputPath) {
      if ($inputPath eq $outputPath) {
         $self->outputName($self->inputName);
      } else {
         my $outName = $self->inputName =~ s(^$inputPath)($outputPath)r;
         $self->outputName($outName);
      }
   }
}


1;
